# The adapter layer

The goal is to catch incompatible Omarchy releases before publishing a new Pi
image. Official ARM dependencies can still change independently on an installed
system, so the build gate does not guarantee that later upgrades are safe.

## Why users are structurally safe

Omarchy now publishes a stable **aarch64** package channel. This port places
its patched `omarchy` package ahead of that channel, while taking
`omarchy-settings` and desktop dependencies from the official repository.
The patched runtime must remain at the same version as official Settings;
the build checks this before packaging.

An upstream release can affect official ARM dependencies before this port
rebases. The Pi image build and VM smoke test are the release gate.

## Three tiers, in order of preference

### Tier 1 — additive files (safest)

We add a file upstream does not ship, and never edit one it does. Nothing to
conflict on, and it survives upstream rewriting its own files.

| What | Where |
|---|---|
| initramfs hooks/modules fixes | [`config/mkinitcpio/zz-omarchy-pi.conf`](../config/mkinitcpio/zz-omarchy-pi.conf) — sorts after Omarchy's drop-ins and edits the arrays |
| Pi pacman configuration | [`config/pacman/pacman-pi.conf`](../config/pacman/pacman-pi.conf) and [`config/pacman/mirrorlist-pi`](../config/pacman/mirrorlist-pi), injected into Omarchy's `default/pacman/` during the image build and selected with `OMARCHY_MIRROR=pi` |
| root filesystem expansion | `omarchy-pi-expand-root.service` |
| firewall/SSH policy | `omarchy-pi-allow-ssh.service` |

Prefer this tier always. Two patches that used to edit
`etc/mkinitcpio.conf.d/*` were moved here precisely because they were the most
likely to conflict.

### Tier 2 — pacman `backup=` files

Omarchy lists its `/etc` files in `backup=()`, so pacman never silently
overwrites a modified one — it writes `.pacnew` and leaves yours in place.
Usable, but it drifts silently from upstream, so prefer Tier 1.

### Tier 3 — source patches on the `pi5` branch (last resort)

Some fixes have to live inside the package because they *are* the package.
Three commits modify four install files; these are the changes that can
conflict on rebase:

| Patch | Runs when |
|---|---|
| `omarchy-base.packages` — drop x86-only packages | image build |
| `mise-work.sh` — Node tarball architecture | first install, new user |
| `snapper.sh` — skip when snapper absent | install, `omarchy apply system` |
| `fix-spi-keyboard.sh` — machines with no DMI | install, `omarchy apply hardware` |

These changes run at **install or provisioning time**, not during a normal
`omarchy-update`. That limits the blast radius: a stale copy on a running
system does nothing until a user is provisioned or hardware is re-applied.

Keep this tier as small as possible. Every patch here is a future merge
conflict.

## Channel policy: stable tags only

This port tracks stable tags rather than upstream development branches.
`scripts/sync-upstream.sh` resolves the newest tag with no
`alpha`/`beta`/`rc` suffix and rebases the series onto that:

```bash
./scripts/sync-upstream.sh
```

Omarchy itself defines three channels (`stable`, `rc`, `edge`) in
`default/pacman/`. The image builder injects a fourth variant, `pi`, built from
the stable one without patching the fork. Following `rc` or `edge` would mean
debugging upstream's in-flight changes and a Pi port at the same time.

## Package policy: no third-party rebuilds

The port rebuilds **only Omarchy's patched runtime** and its bootstrap keyring.
The official stable ARM channel supplies the rest of the desktop.

It does **not** rebuild third-party software that lacks an aarch64 build.
Ghostty was the test case: building it locally needed a pinned older Zig, a
dependency patched out, and a hand-fix to a stale dependency cache. That is not
something anyone wants to re-do every release. Such software is documented as
unsupported instead.

`scripts/build-pkgs.sh` enforces this — it refuses any package with no PKGBUILD
in `omarchy-pkgs` rather than letting the maintenance burden grow quietly.

## The manual release gate

Runtime cleverness cannot save a user from a bad package. Not shipping one can.
The release sequence must be, in order:

1. `git fetch upstream --tags` and rebase `pi5` onto the new tag
2. **A conflict stops here.** This is the intended failure: fix the patch
   against the new upstream, or drop it if upstream fixed it themselves
3. Rebuild the aarch64 packages
4. Build an image and boot it — `scripts/smoke-test.sh` must pass:
   reaches `graphical.target`, zero failed units, SDDM and Hyprland running
5. Only then publish to the repo

A release that fails any step is not published. The fast checks enforce a patch
budget and local-repo precedence; `omarchy-pi-doctor` checks a booted image.
Reassess each source patch on rebase and drop it if upstream fixes the issue.
