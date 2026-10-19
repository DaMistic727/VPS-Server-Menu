#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
target="$work/VPS-Server-Menu"
bin="$work/bin"
bashrc="$work/bashrc"
mkdir -p "$target" "$bin"
cp -R "$repo"/. "$target"/
rm -rf "$target/.git"
git -C "$target" init -q
git -C "$target" config user.name test
git -C "$target" config user.email test@example.invalid
git -C "$target" add .
git -C "$target" commit -qm fixture
commit=$(git -C "$target" rev-parse HEAD)
printf '# untouched\n' > "$bashrc"

VPS_MENU_TARGET_DIR="$target" \
VPS_MENU_BIN_DIR="$bin" \
VPS_MENU_BASHRC="$bashrc" \
VPS_MENU_SKIP_DEPS=1 \
VPS_MENU_ALLOW_NON_ROOT_TEST=1 \
    "$target/install.sh" --non-interactive --no-autostart \
        --source-dir "$target" --pinned-commit "$commit" >/dev/null

test -d "$target/.git"
test "$(cat "$bashrc")" = '# untouched'
test -L "$bin/server-menu"
test -L "$bin/menu_warp.sh"
test -L "$bin/_config_and_utils.sh"
test "$(readlink "$bin/server-menu")" = "$(readlink -f "$target/server-menu")"
test -x "$target/server-menu"
test -x "$target/menu_warp.sh"
test ! -x "$target/main_menu.png"
git -c core.filemode=false -C "$target" diff --quiet HEAD --

if VPS_MENU_TARGET_DIR="$target" VPS_MENU_BIN_DIR="$bin" \
    VPS_MENU_SKIP_DEPS=1 VPS_MENU_ALLOW_NON_ROOT_TEST=1 \
    "$target/install.sh" --non-interactive --no-autostart \
        --source-dir "$target" --pinned-commit 0000000000000000000000000000000000000000 \
        >/dev/null 2>&1; then
    echo 'mismatched pinned commit was accepted' >&2
    exit 1
fi

echo 'non-interactive install tests passed'
