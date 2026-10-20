# omarchy-pi

Run [Omarchy](https://omarchy.org) on a Raspberry Pi 4B or 5.

> Omarchy 4.0.5 boots to the desktop on a real Pi 4B using the MBR image.
> Omarchy 4.0.4 reached the desktop on a real Pi 5. The build uses Omarchy's
> official aarch64 package channel and includes the Pi audio packages.
> See [docs/PORTING.md](docs/PORTING.md).

![Omarchy 4.0.1 running on aarch64](docs/images/omarchy-pi-vm.png)

*Omarchy 4 (Quattro) on aarch64, built by this repo and booted in QEMU.*

## Goal

A ready-to-flash SD card image (`.img`, flashable with Raspberry Pi Imager) that boots a Pi 4B or Pi 5 into Omarchy, tracking upstream stable releases with a minimal patch set.

## How it's structured

| Piece | What it is |
|---|---|
| **This repo** | Docs, image build tooling, Pi-specific configs, fast CI checks |
| [`bbreisch26/omarchy`](https://github.com/bbreisch26/omarchy) (`pi5` branch) | Fork of `omacom/omarchy`: upstream stable tag + a few Pi/ARM patch commits, rebased on each upstream release |
| [`bbreisch26/raspi-config-alarm`](https://github.com/bbreisch26/raspi-config-alarm) (`arch-trixie` branch) | Raspberry Pi OS interface menu adapted to Arch Linux ARM; pinned package recipe in `pkgbuilds/raspi-config/` |
| aarch64 packages | The [official stable ARM repository](https://pkgs.omarchy.org/stable/aarch64/) supplies desktop packages; [pkgbuilds/](pkgbuilds/) holds the patched runtime and pinned Pi configuration recipes |

## What works today

Follow [the build instructions](scripts/README.md) to produce a Pi image. The
4.0.4 image reached the Pi 5 desktop; its VM smoke tests confirmed:

- boots to `graphical.target` with **no failed systemd units**
- SDDM autologins into the Omarchy session; Hyprland and quickshell run
- pacman configured for aarch64, with Pi packages ahead of official stable ARM packages

Getting there needed three source patch commits to Omarchy plus additive build
configuration — all genuine ARM/Pi portability fixes, kept as a small series on
the `pi5` branch and [documented here](docs/PORTING.md#found-and-fixed-in-this-port).

## Approach

- Base: **Arch Linux ARM**, with `linux-rpi` on the Pi and the generic
  `linux-aarch64` kernel for the VM image
- Omarchy is installed as a **pacman package** (that is how Omarchy 4 ships),
  rebuilt for aarch64 from our `pi5` branch. Updates mean rebasing the patch
  series on the new upstream tag and rebuilding — see
  [the update workflow](docs/PORTING.md#update-workflow)
- Boot: Pi firmware boot on hardware, systemd-boot in the VM. Omarchy's
  Limine + btrfs-snapshot layer assumes PC-style UEFI and does not apply
- Images build natively on aarch64 or under Docker's ARM emulation on x86_64
- Prior ARM work that informed this: [ggalancs/omarchy-arm-utm](https://github.com/basecamp/omarchy/discussions/7956)

## Hardware target

- Raspberry Pi 4B, 4 GB+; Raspberry Pi 5, 8 GB
- Board-appropriate official USB-C PSU and cooling
- 32 GB+ microSD (A2-rated recommended) or NVMe HAT

## Prior art & credits

- [Omarchy](https://github.com/basecamp/omarchy) by DHH / Basecamp — the thing itself
- [omarchy-arm-utm](https://github.com/basecamp/omarchy/discussions/7956) — Omarchy 4 native aarch64 UTM build
- [omarchy-arm-fixes](https://github.com/happybigmtn/omarchy-arm-fixes) — ARM package/config fixes (Apple Silicon)
- [Pi 5 install guide (discussion #642)](https://github.com/basecamp/omarchy/discussions/642) — earlier Manjaro-based attempt; source of Pi-specific gotchas

## License

MIT — see [LICENSE](LICENSE). Omarchy itself is MIT-licensed by its authors.
