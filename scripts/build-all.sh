#!/usr/bin/env bash
# Host-side orchestrator: packages -> rootfs -> bootable image.
#
# Runs on an Apple Silicon Mac with Docker (native aarch64 containers, so no
# emulation penalty), or an x86_64 host with ARM binfmt support.
# Produces work/out/omarchy-pi.img.
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$PWD
VARIANT="${VARIANT:-vm}"
PKGS_REPO="${PKGS_REPO:-$ROOT/../omarchy-pkgs}"
OMARCHY="${OMARCHY:-$ROOT/../omarchy}"
WORK="$ROOT/work"
mkdir -p "$WORK/out"

[ -d "$PKGS_REPO" ] || { echo "Missing $PKGS_REPO (git clone omacom-io/omarchy-pkgs)" >&2; exit 1; }
[ -d "$OMARCHY" ]   || { echo "Missing $OMARCHY (clone of our omarchy fork)" >&2; exit 1; }

for package in omarchy omarchy-settings; do
  package_version=$(bash -c 'source "$1"; printf "%s" "$pkgver"' bash "$PKGS_REPO/pkgbuilds/$package/PKGBUILD")
  port_version=$(bash -c 'source "$1"; printf "%s" "$pkgver"' bash "$ROOT/pkgbuilds/omarchy/PKGBUILD")
  package_commit=$(bash -c 'source "$1"; printf "%s" "$_commit"' bash "$PKGS_REPO/pkgbuilds/$package/PKGBUILD")
  [ "$package_version" = "$port_version" ] && git -C "$OMARCHY" merge-base --is-ancestor "$package_commit" HEAD || {
    echo "$package recipe does not match the port's $port_version sources; use matching checkouts" >&2
    exit 1
  }
done

echo "### Stage 0: container images"
docker build --quiet --platform linux/arm64 -t alarm-work  -f docker/Dockerfile.alarm  docker/ >/dev/null
docker build --quiet --platform linux/arm64 -t alarm-build -f docker/Dockerfile.build docker/ >/dev/null

# Persistent package cache: a rebuild otherwise re-downloads several GB.
docker volume create omarchy-pi-pacman-cache >/dev/null

# Snapshot the scripts rather than bind-mounting them live. bash reads a script
# incrementally as it executes, so editing one mid-run corrupts that run.
SNAP="$WORK/.scripts"
rm -rf "$SNAP" && cp -r "$ROOT/scripts" "$SNAP"

if [ "${SKIP_PACKAGES:-0}" != 1 ]; then
  echo "### Stage 1: build aarch64 packages"
  RECIPES="$WORK/.pkgbuilds"
  mkdir -p "$RECIPES"
  cp -r "$PKGS_REPO/pkgbuilds/." "$RECIPES/"
  cp "$ROOT/pkgbuilds/omarchy/PKGBUILD" "$RECIPES/omarchy/PKGBUILD"
  docker run --rm --platform linux/arm64 \
    -v "$RECIPES:/pkgbuilds:ro" \
    -v "$SNAP:/scripts:ro" \
    -v "$OMARCHY:/omarchy:ro" \
    -v "$WORK/out:/out" \
    -v omarchy-pi-pacman-cache:/var/cache/pacman/pkg \
    -e OMARCHY_SRC=/omarchy -e JOBS="${JOBS:-2}" \
    -e PACKAGES="$(tr '\n' ' ' < "$ROOT/packages/aarch64-rebuild.txt")" \
    alarm-build bash /scripts/build-pkgs.sh
fi
for package in omarchy omarchy-keyring; do
  compgen -G "$WORK/out/$package-[0-9]*.pkg.tar.*" >/dev/null || {
    echo "Required package was not built: $package (see $WORK/out/logs)" >&2
    exit 1
  }
done

if [ "${SKIP_ROOTFS:-0}" != 1 ]; then
  echo "### Stage 2: build rootfs ($VARIANT)"
  docker rm -f omarchy-rootfs >/dev/null 2>&1 || true

  # Keypair for the automated smoke test (scripts/smoke-test.sh).
  if [ ! -f "$WORK/id_omarchy" ]; then
    ssh-keygen -q -t ed25519 -N '' -C omarchy-pi-smoke -f "$WORK/id_omarchy"
  fi

  docker run --name omarchy-rootfs --platform linux/arm64 \
    -v "$WORK:/keys:ro" \
    -v omarchy-pi-pacman-cache:/var/cache/pacman/pkg \
    -v "$SNAP:/scripts:ro" \
    -v "$ROOT/config:/config:ro" \
    -v "$OMARCHY:/omarchy:ro" \
    -v "$WORK/out:/pkgs:ro" \
    -e VARIANT="$VARIANT" -e ALLOW_SSH="${ALLOW_SSH:-}" \
    alarm-work bash /scripts/build-rootfs.sh

  echo "### Stage 3: export rootfs"
  docker export omarchy-rootfs -o "$WORK/rootfs.tar"
else
  [ -f "$WORK/rootfs.tar" ] || { echo "Missing $WORK/rootfs.tar" >&2; exit 1; }
  echo "### Reusing $WORK/rootfs.tar"
fi

echo "### Stage 4: assemble image"
docker run --rm --platform linux/arm64 \
  -v "$SNAP:/scripts:ro" \
  -v "$ROOT/config:/config:ro" \
  -v "$WORK:/work" \
  -v omarchy-pi-pacman-cache:/var/cache/pacman/pkg \
  -e VARIANT="$VARIANT" \
  -e PARTITION_TABLE="${PARTITION_TABLE:-gpt}" \
  alarm-work bash -c '
    set -e
    for attempt in 1 2 3; do
      if pacman -S --noconfirm --needed e2fsprogs dosfstools mtools gptfdisk util-linux; then
        break
      fi
      if [ "$attempt" -eq 3 ]; then
        echo "Failed to install image assembly tools after 3 attempts" >&2
        exit 1
      fi
      echo "WARN: image assembly tools unavailable; retrying ($attempt/3)"
      sleep 10
    done
    rm -rf /work/rootfs && mkdir -p /work/rootfs
    trap "rm -rf /work/rootfs" EXIT
    tar -xf /work/rootfs.tar -C /work/rootfs
    # Docker-injected files that must not ship in the image
    rm -f /work/rootfs/.dockerenv /work/rootfs/etc/hostname /work/rootfs/etc/hosts /work/rootfs/etc/resolv.conf
    # Bind-mount points export as empty directories; they are build scaffolding.
    rmdir /work/rootfs/config /work/rootfs/omarchy /work/rootfs/scripts /work/rootfs/pkgs /work/rootfs/keys 2>/dev/null || true
    printf "omarchy-pi\n" > /work/rootfs/etc/hostname
    printf "127.0.0.1 localhost\n::1 localhost\n127.0.1.1 omarchy-pi\n" > /work/rootfs/etc/hosts
    ln -sf /run/systemd/resolve/stub-resolv.conf /work/rootfs/etc/resolv.conf
    OUT=/work/out/omarchy-pi.img ROOTFS=/work/rootfs bash /scripts/build-image.sh
  '

echo
echo "### Done: $WORK/out/omarchy-pi.img"
echo "    Boot it:  ./scripts/run-vm.sh"
