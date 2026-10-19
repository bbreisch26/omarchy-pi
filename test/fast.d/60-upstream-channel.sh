#!/usr/bin/env bash
# The port follows tagged stable releases, never upstream's development branch.
source "$(dirname "$0")/../lib.sh"
SYNC="$ROOT/scripts/sync-upstream.sh"
assert_file "$SYNC"

assert_grep 'alpha\|beta\|rc' "$SYNC" "sync filters out pre-release tags"
assert_no_grep 'upstream/(master|main)' "$SYNC" "sync never rebases onto a branch"

# The filter must actually reject pre-releases, not merely mention them.
filtered=$(printf 'v4.0.1\nv4.0.0-beta3\nv4.0.0rc2\nv4.0.0\n' \
  | grep -vE '\-?(alpha|beta|rc)[0-9]*$' | head -1)
if [ "$filtered" = "v4.0.1" ]; then
  ok "pre-release filter picks v4.0.1 over beta/rc tags"
else
  bad "pre-release filter picks v4.0.1 over beta/rc tags" "picked: $filtered"
fi

# A conflict must stop the release, not be worked around.
assert_grep 'REBASE CONFLICT' "$SYNC" "a rebase conflict halts with an explanation"

# CI checks the port but does not build or publish images.
WF="$ROOT/.github/workflows/checks.yml"
assert_file "$WF"
assert_grep './test/run.sh fast' "$WF" "CI runs fast checks"
assert_no_grep 'build-all\.sh|action-gh-release|gh release' "$WF" "CI does not publish an unverified image"
