# Building and iterating

Builds need Docker with `linux/arm64` support, internet access, and at least
40 GB of free disk space. Docker Desktop provides ARM emulation on x86_64;
enable integration for your distribution under **Resources → WSL Integration**
when building in WSL. Native aarch64 hosts build substantially faster.

The current port uses Omarchy 4.0.5. Keep the source and package recipes at
matching revisions:

```bash
mkdir -p work/src
git clone --single-branch --branch pi5 https://github.com/bbreisch26/omarchy.git work/src/omarchy
git -C work/src/omarchy fetch https://github.com/omacom/omarchy.git tag v4.0.5
git clone https://github.com/omacom/omarchy-pkgs.git work/src/omarchy-pkgs
git -C work/src/omarchy-pkgs checkout --detach 0126fa4b8bd616f22e0ecf20d6849c4c7d1e8ea4

export OMARCHY="$PWD/work/src/omarchy"
export PKGS_REPO="$PWD/work/src/omarchy-pkgs"
VARIANT=pi JOBS=4 ./scripts/build-all.sh
```

`build-all.sh` builds the containers, rebuilds the patched Omarchy runtime,
installs the desktop into a root filesystem, and assembles
`work/out/omarchy-pi.img`. Package downloads and completed dependency packages
are cached. Desktop dependencies come from the official
`https://pkgs.omarchy.org/stable/aarch64` repository and Arch Linux ARM;
the local Pi repository takes precedence. The `omarchy` package is rebuilt each time
so edits to the source checkout reach the next image. Inspect package failures
in `work/out/logs/` and `work/out/failed.txt`.
When retrying only root filesystem or image assembly after an error, set
`SKIP_PACKAGES=1` to reuse the already built packages in `work/out/`.
Set `SKIP_ROOTFS=1` as well to reassemble an image from `work/rootfs.tar`
without rebuilding the root filesystem. Keep `VARIANT` the same as the tarball.
Image assembly extracts and formats temporary files under `work/`, not Docker's
overlay storage. On WSL, Windows C: still needs free space for Docker Desktop's
disk image even when the Linux filesystem reports ample room.

Use `VARIANT=pi` for Raspberry Pi 4B and 5 firmware boot. The firmware selects
the board's V3D overlay. The MBR image has booted on a real Pi 4B, while
application and GPIO coverage remain in progress.
Pi images use MBR by default for the tested bootloader path; set
`PARTITION_TABLE=gpt` only to compare a GPT image. `VARIANT=vm` builds the UEFI
VM image used by `run-vm.sh` and `smoke-test.sh`.
The Pi build also installs the audio packages in
`config/packages/pi-desktop.packages` and a pinned package from the
[`raspi-config` Arch fork](https://github.com/bbreisch26/raspi-config-alarm/tree/arch-trixie).
Run `sudo raspi-config` on the Pi to toggle SPI, I2C, serial and 1-Wire;
changes to boot settings require a reboot. The menu is intentionally limited
to these interfaces until other Raspberry Pi OS actions are ported to Arch.
The build suppresses the optional Voxtype
first-run invitation until its prebuilt aarch64 binaries pass Pi 4B tests.

Flash `work/out/omarchy-pi.img` to a 32 GB or larger card with Balena Etcher
or Raspberry Pi Imager's **Use custom** option. The default login is
`omarchy` / `omarchy`; change the
password after boot. The root filesystem expands to fill the card.

Builds generate `work/id_omarchy` for key-based SSH. For a development image
that allows SSH through the firewall, add `ALLOW_SSH=1` to the build command;
connect with `ssh -i work/id_omarchy omarchy@<pi-address>`. Password SSH is
disabled when this key is included.

To produce a compressed image and checksum:

```bash
xz -T0 -3 -k work/out/omarchy-pi.img
sha256sum work/out/omarchy-pi.img.xz > work/out/omarchy-pi.img.xz.sha256
```

Run `./test/run.sh` for fast checks, `./test/run.sh container` for ARM container
checks, and `./scripts/test-raspi4b.sh` for a partial Pi boot test with QEMU.
