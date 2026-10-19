# Pi-specific config overrides

Configs added to the image without enlarging the Omarchy source patch series:

- `boot/config.txt` — Pi firmware boot settings for Pi 4B and Pi 5
- `pacman/` — Arch Linux ARM mirrors, the official ARM channel, and a local Pi package repo
- `mkinitcpio/` — Pi boot hooks and modules
- `packages/pi-desktop.packages` — audio packages omitted by the ISO package path
