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

# Exercise fresh and repeat installs against a local Git server. Only the
# transport is mocked; ancestry, worktree state and fast-forward use real Git.
real_git=$(command -v git)
remote="$work/official.git"
git init -q --bare "$remote"
git -C "$target" branch -M main
git -C "$target" remote add origin "$remote"
git -C "$target" push -q -u origin main
git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
mockbin="$work/mockbin"
mkdir "$mockbin"
cat > "$mockbin/git" <<'SH'
#!/bin/bash
if [ "${1:-}" = clone ]; then
    args=("$@")
    for ((i=0; i<${#args[@]}; i++)); do
        if [ "${args[i]}" = https://github.com/Diman6267/VPS-Server-Menu.git ]; then
            args[i]=$TEST_GIT_REMOTE
        fi
    done
    "$REAL_GIT" "${args[@]}"
    dest=${args[$((${#args[@]} - 1))]}
    "$REAL_GIT" -C "$dest" remote set-url origin https://github.com/Diman6267/VPS-Server-Menu.git
else
    if [ "${1:-}" = -C ] && [ "${3:-}" = fetch ]; then
        "$REAL_GIT" -C "$2" fetch "$TEST_GIT_REMOTE" main:refs/remotes/origin/main
    else
        exec "$REAL_GIT" "$@"
    fi
fi
SH
chmod +x "$mockbin/git"
export TEST_GIT_REMOTE="$remote" REAL_GIT="$real_git"
fresh="$work/fresh/VPS-Server-Menu"
PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" VPS_MENU_BIN_DIR="$work/freshbin" \
    VPS_MENU_BASHRC="$bashrc" VPS_MENU_SKIP_DEPS=1 VPS_MENU_ALLOW_NON_ROOT_TEST=1 \
    "$repo/install.sh" --non-interactive --no-autostart > "$work/fresh.log" || {
        cat "$work/fresh.log" >&2; exit 1;
    }
test -d "$fresh/.git"
test "$(git -C "$fresh" remote get-url origin)" = https://github.com/Diman6267/VPS-Server-Menu.git
test "$(cat "$bashrc")" = '# untouched'
test "$(readlink "$work/freshbin/server-menu")" = "$(readlink -f "$fresh/server-menu")"
test "$(git -C "$fresh" rev-parse HEAD)" = "$(git -C "$target" rev-parse HEAD)"
grep -q "Installed VPS-Server-Menu commit: $(git -C "$fresh" rev-parse HEAD)" "$work/fresh.log"
printf 'keep\n' > "$fresh/user-file"
if PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" VPS_MENU_BIN_DIR="$work/freshbin" \
    VPS_MENU_SKIP_DEPS=1 VPS_MENU_ALLOW_NON_ROOT_TEST=1 \
    "$repo/install.sh" --non-interactive --no-autostart >/dev/null 2>&1; then
    echo 'dirty checkout updated' >&2; exit 1
fi
test "$(cat "$fresh/user-file")" = keep
rm "$fresh/user-file"
git -C "$fresh" checkout -q --detach
if PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" VPS_MENU_BIN_DIR="$work/freshbin" \
    VPS_MENU_SKIP_DEPS=1 VPS_MENU_ALLOW_NON_ROOT_TEST=1 \
    "$repo/install.sh" --non-interactive --no-autostart >/dev/null 2>&1; then
    echo 'detached checkout updated' >&2; exit 1
fi
sed -n '/^function menu_git_state {/,/^}/p' "$repo/server-menu" > "$work/git-state.sh"
source "$work/git-state.sh"
test "$(PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" menu_git_state)" = pinned
git -C "$fresh" checkout -q main
PATH="$mockbin:$PATH" git -C "$fresh" fetch origin main
test "$(PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" menu_git_state)" = current
printf 'remote\n' > "$target/remote-change"
git -C "$target" add remote-change
git -C "$target" commit -qm remote-change
git -C "$target" push -q origin main
test "$(PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" menu_git_state)" = behind
PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" VPS_MENU_BIN_DIR="$work/freshbin" \
    VPS_MENU_BASHRC="$bashrc" VPS_MENU_SKIP_DEPS=1 VPS_MENU_ALLOW_NON_ROOT_TEST=1 \
    "$repo/install.sh" --non-interactive --no-autostart >/dev/null
test "$(PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" menu_git_state)" = current
git -C "$fresh" config user.name test
git -C "$fresh" config user.email test@example.invalid
printf 'local\n' > "$fresh/local-change"
git -C "$fresh" add local-change
git -C "$fresh" commit -qm local-change
test "$(PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" menu_git_state)" = ahead
printf 'remote2\n' > "$target/remote-change-2"
git -C "$target" add remote-change-2
git -C "$target" commit -qm remote-change-2
git -C "$target" push -q origin main
test "$(PATH="$mockbin:$PATH" VPS_MENU_TARGET_DIR="$fresh" menu_git_state)" = diverged
echo 'fresh Git install and safety tests passed'
