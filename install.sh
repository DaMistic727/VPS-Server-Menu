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
an unexpected revision and disables updates from main.
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
TARGET_DIR=$(readlink -f "$TARGET_DIR")
BIN_DIR=$(readlink -f "$BIN_DIR")
BASHRC_FILE=$(readlink -f "$BASHRC_FILE")
echo -e "${YELLOW}>>> Начало установки VPS-Server-Menu...${NC}"

missing=()
for command in curl git bc jq ufw qrencode; do
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
elif [ -d "$TARGET_DIR/.git" ]; then
    if [ -n "$PINNED_COMMIT" ]; then
        echo -e "${YELLOW}>>> Используется существующий закреплённый checkout.${NC}"
    else
        echo -e "${YELLOW}>>> Репозиторий уже существует. Обновляем main...${NC}"
        git -C "$TARGET_DIR" fetch origin main
        git -C "$TARGET_DIR" reset --hard origin/main
    fi
else
    [ "$NON_INTERACTIVE" -eq 0 ] || {
        echo "Non-interactive install requires a prepared --source-dir checkout." >&2
        exit 1
    }
    rm -rf "$TARGET_DIR"
    git clone "$REPOSITORY" "$TARGET_DIR"
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

echo -e "${YELLOW}>>> Настройка прав и системных ссылок...${NC}"
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
