# Testing the VM image

The VM runs the same aarch64 userspace as the Pi. It runs natively on Apple
Silicon or an ARM64 Linux host; x86_64 hosts use emulation. It cannot verify
the Pi's GPU driver or firmware boot path.

## Build it

Set up the source and packaging checkouts as in the
[build instructions](../scripts/README.md), then build the VM variant with
Docker and QEMU installed:

```bash
export OMARCHY="$PWD/work/src/omarchy"
export PKGS_REPO="$PWD/work/src/omarchy-pkgs"
VARIANT=vm ./scripts/build-all.sh
```

## Run it

```bash
./scripts/run-vm.sh
```

A window opens and boots to the Omarchy desktop. Log in as `omarchy` /
`omarchy`.

For scripted testing without a window:

```bash
HEADLESS=1 ./scripts/run-vm.sh
ssh -p 2222 omarchy@localhost
```

## What the VM does and does not prove

| Proven in the VM | Only provable on the Pi |
|---|---|
| Selected desktop packages resolve and install on aarch64 | V3D GPU driver behaviour |
| Omarchy's installer runs to completion | Pi-specific rendering behaviour |
| systemd services start cleanly | Pi firmware boot path |
| Hyprland, SDDM and the shell come up | Thermals and real-world performance |

The VM has no real GPU, so Hyprland runs on software rendering. Do not judge
animation smoothness there.

`scripts/smoke-test.sh` runs a headless boot check. It requires KVM on Linux or
HVF on macOS; x86_64 emulation alone is not sufficient for this test.
