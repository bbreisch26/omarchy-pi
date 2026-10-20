# Porting plan

## Phases

| # | Phase | Status |
|---|---|---|
| 1 | Establish the aarch64 build environment (Docker, native arm64 on Apple Silicon) | done |
| 2 | Determine package availability | done — official stable aarch64 packages now cover the desktop |
| 3 | Build a bootable VM image and run Omarchy's own installer on ARM | done — 4.0.2, zero failed steps |
| 3b | Verify the Pi boot chain as far as emulation allows (see below) | done |
| 4 | Verify on real Pi 5 hardware (V3D GPU, firmware boot, thermals) | **boots to the desktop** — Omarchy 4.0.4 from NVMe on a Pi 5 Rev 1.1: zero failed units, Hyprland on the V3D GPU (no software rendering), HDMI 1920×1080@60, root grown to 469 GB, 49 °C idle. Needed one fix: Plymouth hung boot before `sysinit.target` |
| 5 | Build and verify flashable images | local build works; automated publication is not configured |
| 6 | Host an aarch64 pacman repo so installed systems get package updates | superseded for desktop dependencies by the official stable ARM channel; patched `omarchy` still needs a hosted update path |

### Pi 4B compatibility checks

The 4.0.5 image has booted to the desktop on a real Pi 4B in user testing.
That does not establish application, audio, or GPU compatibility. Track those
separately before advertising them as supported:

| Feature | Current evidence | Acceptance check |
|---|---|---|
| Boot and desktop | Real Pi 4B reaches the desktop | Repeat on a freshly flashed image; check `systemctl --failed` |
| HDMI audio | The first image omitted `pipewire-audio`, `pipewire-alsa`, and `pipewire-pulse`; installing those three on a Pi 4B and rebooting restored audio (user report). The rebuilt image includes them but is not yet hardware-tested | On a fresh image, confirm `pacman -Q pipewire-audio pipewire-alsa pipewire-pulse wireplumber`, `wpctl status`, and audible browser and `mpv` playback |
| Voxtype dictation | Pi 4B `systemd-coredump` recorded `SIGILL` in `/usr/lib/voxtype/voxtype-cpu`; the crash instruction was identified as `swpalb` (LSE atomic), unsupported by Cortex-A72. The image does not install it and suppresses the first-run invitation, but the manual installer remains available | Keep the first-run invitation suppressed; if already installed, disable its user service and remove `voxtype-bin` to stop the shell status follower; only offer it after both CPU and ONNX variants start and transcribe on Cortex-A72 hardware |
| Suspend/resume | The stock `linux-rpi` [recipe](https://github.com/archlinuxarm/PKGBUILDs/blob/master/core/linux-rpi/PKGBUILD) uses Raspberry Pi's [bcm2711 defconfig](https://github.com/raspberrypi/linux/blob/rpi-6.18.y/arch/arm64/configs/bcm2711_defconfig), which has `CONFIG_SUSPEND` disabled; this port does not rebuild the kernel or set suspend policy | Unsupported on Pi 4B until both kernel support and reliable firmware/device wake-up are demonstrated on hardware; screen blanking is not suspend |
| Documents and graphics | VM tests do not exercise the Pi 4B V3D driver | Open and convert a document, then exercise browser/video rendering on the board |

The patched `omarchy` package is primarily scripts and data. Setting C/C++ or
Rust flags in this image build would not change Voxtype's separately built
upstream binaries. Upstream's [CPU](https://github.com/peteonrails/voxtype/blob/dev/Dockerfile.aarch64-cpu)
and [ONNX](https://github.com/peteonrails/voxtype/blob/dev/Dockerfile.aarch64-onnx)
ARM Dockerfiles set `RUSTFLAGS="-C target-cpu=neoverse-n1"`; that is not a
Cortex-A72 baseline despite their Pi 4 comments. A source build with an
ARMv8-A baseline, plus an audit of native dependencies, still needs a real
Pi 4B runtime test before inclusion.

### Package findings (Omarchy 4.0.2)

These are historical findings from before Omarchy published
`https://pkgs.omarchy.org/stable/aarch64`. Current images use the official ARM
channel for desktop packages and rebuild only the Pi-patched `omarchy` runtime
package and bootstrap keyring. The old list below records what the first port
needed to prove.

The current build skips `kdenlive`: Arch Linux ARM indexed version 26.08.2-1,
but its recommended mirror and a second official mirror returned 404 for the
package file on 2026-10-18. The video editor is not needed for boot or the
desktop; remove the skip in `scripts/build-rootfs.sh` when the mirror serves it.

Of the 148 packages in `install/omarchy-base.packages`, 122 install directly
from Arch Linux ARM. The rest:

- **19 rebuilt** from [omarchy-pkgs](https://github.com/omacom-io/omarchy-pkgs)
  PKGBUILDs. Most already declared `aarch64`; the rest needed only an `arch=`
  addition, not code changes.
- **4 core packages** built separately: `omarchy`, `omarchy-settings`,
  `omarchy-keyring`, `ttf-jetbrains-mono-nerd-basic`. The `omarchy` package is
  `arch=any` but hard-depends on the Limine bootloader stack, so we build a
  [patched PKGBUILD](../pkgbuilds/omarchy/PKGBUILD).
- **`nvim`** needs nothing — Arch Linux ARM's `neovim` already provides it.
- **6 dropped** on the `pi5` branch: `asdcontrol`, `qemu-user-static-binfmt`
  (x86-only, no Pi relevance) and `dotnet-runtime`, `pinta`, `obs-studio`,
  `obsidian` (no aarch64 build). None are needed for the desktop.
- **`herdr`** builds on ARM but gets OOM-killed while linking under Docker
  Desktop's default 4 GB. Not an architecture problem — it needs more memory.

### Historical emulation checks before Pi 5 hardware testing

No emulator models the BCM2712: QEMU tops out at `raspi4b` (BCM2711, a
hardwired Cortex-A72, no PCIe, no GPU), and this QEMU build has no virgl. So
the Pi-specific risks are split across two harnesses that each cover a slice:

| Harness | Models | Verified |
|---|---|---|
| `scripts/test-raspi4b.sh` | Pi-family SoC (BCM2711), SD controller, the real `linux-rpi` kernel + initramfs from the image | Kernel boots, SD card found (as `mmc1`), root located by **PARTUUID**, ext4 mounted rw, systemd reaches `System Initialization`. Userspace console is invisible there (QEMU cannot clock the BCM2711 PL011), so progress is read from the journal the boot writes onto the image's own root filesystem |
| `scripts/test-a76-nvme.sh` | The Pi 5's **Cortex-A76** core (TCG), root on an emulated **NVMe** controller — the exact path an NVMe HAT takes | Boots by PARTUUID from `nvme0n1p2`; every shipped binary runs with **no illegal-instruction faults**; Hyprland and quickshell start and render; 0 failed units. `omacalc`/`omawrite` exit 134 (SIGABRT) when run with no display — Qt aborting, not an ISA fault; both run under `QT_QPA_PLATFORM=offscreen` |

Not covered by anything virtual: BCM2712 peripherals, RP1, the V3D GPU driver,
and the real firmware's `config.txt` handling. Those need the board.

## Known Pi/ARM gotchas

### Found and fixed in this port

These were hit while getting Omarchy 4.0.1 to install on aarch64. Each is fixed
on the [`pi5` branch](https://github.com/bbreisch26/omarchy/tree/pi5).

| Symptom | Cause | Fix |
|---|---|---|
| `bundled Node.js tarball missing` on first install | `install/user/mise-work.sh` globs `node-v*-linux-x64.tar.gz` unconditionally | Derive the suffix from `uname -m` |
| Install step dies before doing anything | `install/hardware/apple/fix-spi-keyboard.sh` reads `/sys/class/dmi/id/product_name`; the Pi has no DMI, so the assignment fails under `bash -eE` | `\|\| true` on the read |
| `Hook 'btrfs-overlayfs' cannot be found` | `omarchy_hooks.conf` HOOKS ends in a hook shipped by the Limine/snapper stack we do not install | Removed by our additive drop-in, not by editing their file |
| `module not found: 'thunderbolt'` | `thunderbolt_module.conf` adds a module the Pi kernel lacks | Removed by our additive drop-in |
| `snapper.sh` exits 127 | snapper is not installed on this port | Skip when the binary is absent |
| pacman left pointing at x86 mirrors | `post-install/pacman.sh` restores `default/pacman/pacman-$OMARCHY_MIRROR.conf`, defaulting to `stable` (Omarchy's Arch mirror has no aarch64 tree, and `[multilib]` does not exist for ARM) | Add a `pi` mirror variant and set `OMARCHY_MIRROR=pi` |

### Build-environment traps (not Omarchy bugs)

| Symptom | Cause |
|---|---|
| Kernel panics with no root device | `mkinitcpio`'s `autodetect` hook trims modules to the *build* machine's hardware. Generic images must not autodetect |
| A rebuilt package has no effect | pacman installs the stale cached tarball, since a rebuild keeps the same version-release. Evict it from the cache first |
| Package build killed while linking | Docker Desktop's 4 GB default. Not an ARM issue — raise the memory or build with `JOBS=1` |
| Script dies mid-run with a syntax error | bash reads scripts incrementally; editing a mounted script while a container runs it corrupts that run. `build-all.sh` snapshots them |
| UFW setup cannot determine the iptables version in Docker | Enable the default-deny firewall offline and apply Omarchy's rules on boot |
| Image assembly runs out of Docker overlay space | Extract the rootfs and format temporary images under the mounted `work/` directory |

## Keeping upstream updates safe

How the port avoids letting an Omarchy release break a user's Pi — the
three tiers of patching and the release gate — is in
[ADAPTER.md](ADAPTER.md).

## Update workflow

**Omarchy 4 ships itself as pacman packages, not a git checkout.** The `omarchy`
package installs to `/usr/share/omarchy`. The official stable ARM repository
now supplies most packages. This port rebuilds the patched `omarchy` runtime
against the matching stable source tag.

Two pieces:

**1. Source patches** live on the `pi5` branch of our
[omarchy fork](https://github.com/bbreisch26/omarchy), based on the upstream
stable tag. On each upstream release:

```
git fetch upstream --tags
git rebase v<new-tag> pi5
git push --force-with-lease origin pi5
```

**2. Packages**: build the patched `omarchy` runtime from that branch and place
it ahead of the official ARM channel in pacman. The upstream PKGBUILD supports
`OMARCHY_SRC=/path/to/checkout`, so the matching recipe can build our patched
tree directly. The bootstrap keyring is also built locally.

Our `omarchy` PKGBUILD ([pkgbuilds/omarchy](../pkgbuilds/omarchy/PKGBUILD))
drops the `limine` / `limine-mkinitcpio-hook` / `limine-snapper-sync` / `snapper`
hard dependencies. Those assume PC-style UEFI boot and a btrfs root; the Pi
boots from its own firmware off the FAT partition.

The image currently includes a file-backed local repository for the patched
runtime. Official ARM desktop dependencies update normally. A hosted update
path for the patched runtime remains necessary before claiming unattended
Omarchy runtime updates.

## Non-goals

- Supporting other SBCs
- Diverging from upstream behavior beyond what ARM/Pi strictly requires
