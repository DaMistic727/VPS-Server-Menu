#!/bin/bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
TARGET_DIR="${VPS_MENU_TARGET_DIR:-/root/VPS-Server-Menu}"
BIN_DIR="${VPS_MENU_BIN_DIR:-/usr/local/bin}"
BASHRC_FILE="${VPS_MENU_BASHRC:-/root/.bashrc}"
REPOSITORY="https://github.com/Diman6267/VPS-Server-Menu.git"
SOURCE_DIR=""
PINNED_COMMIT=""
NON_INTERACTIVE=0
NO_AUTOSTART=0

usage() {
    cat <<'EOF'
Usage: install.sh [--non-interactive] [--no-autostart]
                  [--source-dir DIR] [--pinned-commit SHA]

--source-dir installs an existing checkout in place. --pinned-commit refuses
an unexpected revision and disables updates from main. Without --source-dir,
the official main is cloned on first install or fast-forwarded when safe.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --non-interactive) NON_INTERACTIVE=1 ;;
        --no-autostart) NO_AUTOSTART=1 ;;
        --source-dir) shift; SOURCE_DIR="${1:?missing source directory}" ;;
        --pinned-commit) shift; PINNED_COMMIT="${1:?missing pinned commit}" ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
    shift
done

if [ "${VPS_MENU_ALLOW_NON_ROOT_TEST:-0}" != 1 ]; then
    [ "$(id -u)" -eq 0 ] || { echo "Run as root." >&2; exit 1; }
fi
mkdir -p "$(dirname "$TARGET_DIR")"
mkdir -p "$BIN_DIR"
TARGET_DIR="$(cd "$(dirname "$TARGET_DIR")" && pwd -P)/$(basename "$TARGET_DIR")"
BIN_DIR=$(readlink -f "$BIN_DIR")
if [ "$NO_AUTOSTART" -eq 0 ] && [ "$NON_INTERACTIVE" -eq 0 ]; then
    BASHRC_FILE="$(cd "$(dirname "$BASHRC_FILE")" && pwd -P)/$(basename "$BASHRC_FILE")"
fi
echo -e "${YELLOW}>>> Начало установки VPS-Server-Menu...${NC}"

missing=()
for command in curl git bc jq qrencode; do
    command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done
if [ "${#missing[@]}" -gt 0 ] && [ "${VPS_MENU_SKIP_DEPS:-0}" != 1 ]; then
    echo -e "${YELLOW}>>> Установка необходимых пакетов...${NC}"
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 update
    DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=600 install -y --no-install-recommends "${missing[@]}"
fi

if [ -n "$SOURCE_DIR" ]; then
    SOURCE_DIR=$(readlink -f "$SOURCE_DIR")
    [ "$SOURCE_DIR" = "$TARGET_DIR" ] || {
        echo "--source-dir must be $TARGET_DIR to preserve its .git checkout." >&2
        exit 1
    }
    [ -d "$TARGET_DIR/.git" ] || { echo "Source directory is not a Git checkout." >&2; exit 1; }
fi

if [ -d "$TARGET_DIR/.git" ]; then
    origin_url=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)
    if [ "$origin_url" != "$REPOSITORY" ] &&
        [ "$origin_url" != "https://github.com/Diman6267/VPS-Server-Menu" ]; then
        if [ -z "$PINNED_COMMIT" ] || [ -z "$SOURCE_DIR" ] || [ -n "$origin_url" ]; then
            echo "Existing checkout origin is not the official repository." >&2
            exit 1
        fi
    fi
    if [ -z "$PINNED_COMMIT" ] && [ -z "$SOURCE_DIR" ]; then
        [ "$(git -C "$TARGET_DIR" branch --show-current)" = main ] || {
            echo "Existing checkout is not on main; refusing automatic update." >&2; exit 1;
        }
        [ -z "$(git -c core.filemode=false -C "$TARGET_DIR" status --porcelain)" ] || {
            echo "Existing checkout has local changes; refusing automatic update." >&2; exit 1;
        }
        git -C "$TARGET_DIR" fetch origin main
        if ! git -C "$TARGET_DIR" merge-base --is-ancestor HEAD origin/main; then
            echo "Local main is ahead or diverged; refusing automatic update." >&2
            exit 1
        fi
        git -c core.filemode=false -C "$TARGET_DIR" merge --ff-only origin/main
    fi
else
    [ ! -e "$TARGET_DIR" ] || {
        echo "Target exists but is not a Git checkout; refusing to remove it." >&2; exit 1;
    }
    [ -z "$SOURCE_DIR" ] || { echo "--source-dir checkout does not exist." >&2; exit 1; }
    [ -z "$PINNED_COMMIT" ] || { echo "Pinned install needs an existing --source-dir checkout." >&2; exit 1; }
    mkdir -p "$(dirname "$TARGET_DIR")"
    staging=$(mktemp -d "${TARGET_DIR}.staging.XXXXXXXX")
    trap 'rm -rf -- "$staging"' EXIT
    git clone --branch main --single-branch "$REPOSITORY" "$staging"
    mv "$staging" "$TARGET_DIR"
    trap - EXIT
fi

if [ -n "$PINNED_COMMIT" ]; then
    actual=$(git -C "$TARGET_DIR" rev-parse HEAD)
    [ "$actual" = "$PINNED_COMMIT" ] || {
        printf 'Pinned revision mismatch: expected %s, got %s\n' "$PINNED_COMMIT" "$actual" >&2
        exit 1
    }
    git -c core.filemode=false -C "$TARGET_DIR" diff --quiet HEAD -- || {
        echo "Pinned checkout contains tracked changes." >&2
        exit 1
    }
fi
printf 'Installed VPS-Server-Menu commit: %s\n' "$(git -C "$TARGET_DIR" rev-parse HEAD)"

echo -e "${YELLOW}>>> Настройка прав и системных ссылок...${NC}"
mkdir -p "$BIN_DIR"
find "$TARGET_DIR" -path "$TARGET_DIR/.git" -prune -o -type d -exec chmod 755 {} +
find "$TARGET_DIR" -path "$TARGET_DIR/.git" -prune -o -type f -exec chmod 644 {} +
for file in "$TARGET_DIR"/*.sh "$TARGET_DIR/server-menu" "$TARGET_DIR/ipv6-menu"; do
    [ -f "$file" ] && chmod 755 "$file"
done
for file in "$TARGET_DIR"/*.sh "$TARGET_DIR/server-menu" "$TARGET_DIR/ipv6-menu"; do
    [ -f "$file" ] && ln -sfn "$file" "$BIN_DIR/$(basename "$file")"
done

if [ "$NO_AUTOSTART" -eq 0 ] && [ "$NON_INTERACTIVE" -eq 0 ]; then
    echo -e "${YELLOW}>>> Настройка автозапуска меню...${NC}"
    if ! grep -q "server-menu" "$BASHRC_FILE"; then
        printf '\n# Автозапуск основного меню\nif [[ -t 0 ]]; then server-menu; fi\n' >> "$BASHRC_FILE"
        echo -e "${GREEN}✓ Автозапуск добавлен в $BASHRC_FILE${NC}"
    fi
else
    echo -e "${YELLOW}>>> Автозапуск в .bashrc не изменяется.${NC}"
fi

echo -e "${GREEN}✅ VPS-Server-Menu установлен. Запуск: server-menu${NC}"
