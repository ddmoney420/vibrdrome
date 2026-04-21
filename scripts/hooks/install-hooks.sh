#!/usr/bin/env bash
# Install Vibrdrome git hooks.
#
# Run once after cloning. Re-run after pulling new hooks from scripts/hooks/.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
HOOKS_SRC="$REPO_ROOT/scripts/hooks"
HOOKS_DST="$REPO_ROOT/.git/hooks"

for hook in pre-commit; do
    src="$HOOKS_SRC/$hook"
    dst="$HOOKS_DST/$hook"
    if [ ! -f "$src" ]; then
        echo "install-hooks: missing source hook $src" >&2
        exit 1
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "install-hooks: installed $hook"
done
