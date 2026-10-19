#!/usr/bin/env bash
# The Pi pacman configuration is load-bearing: every one of these was a real
# failure during the port.
source "$(dirname "$0")/../lib.sh"
CONF="$ROOT/config/pacman/pacman-pi.conf"
MIRROR="$ROOT/config/pacman/mirrorlist-pi"

assert_file "$CONF"
assert_file "$MIRROR"

assert_grep '^Architecture *= *aarch64' "$CONF" "architecture pinned to aarch64"

# Without SigLevel = ... DatabaseOptional, every sync 404s on core.db.sig,
# because Arch Linux ARM does not publish database signatures.
assert_grep '^SigLevel *=.*DatabaseOptional' "$CONF" "DatabaseOptional set (ALARM ships no .db.sig)"

# multilib is x86-only and has no ARM counterpart; its presence breaks sync.
assert_no_grep '^\[multilib\]' "$CONF" "no [multilib] section"

# Reject x86_64 and legacy endpoints while allowing the official ARM channel.
assert_no_grep_active 'stable-mirror\.omarchy\.org|pkgs\.omarchy\.org/(x86_64|\$arch)' "$CONF" \
  "no upstream x86_64 Omarchy repo configured"

# Our patched packages must take precedence over the official ARM channel.
assert_grep '^\[omarchy-pi\]' "$CONF" "our [omarchy-pi] repo is present"
assert_grep_active '^Server = https://pkgs\.omarchy\.org/stable/\$arch$' "$CONF" "official stable aarch64 packages are available"
local_line=$(grep -n '^\[omarchy-pi\]' "$CONF" | cut -d: -f1)
official_line=$(grep -n '^\[omarchy\]' "$CONF" | cut -d: -f1)
[ "$local_line" -lt "$official_line" ]
assert $? "local Pi packages take precedence over official packages"

assert_grep '^\[alarm\]' "$CONF" "Arch Linux ARM [alarm] repo present"
assert_grep 'mirror\.archlinuxarm\.org' "$MIRROR" "mirrorlist points at Arch Linux ARM"

# DisableSandbox belongs in [options]; appended at the end it lands in the last
# repo section, where pacman ignores it and warns on every invocation.
if grep -q '^DisableSandbox' "$CONF"; then
  bad "DisableSandbox not shipped in the image config" "it is a build-time container workaround only"
else
  ok "DisableSandbox not shipped in the image config"
fi
