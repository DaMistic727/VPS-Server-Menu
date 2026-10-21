#!/bin/bash

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
TARGET_DIR="${VPS_MENU_TARGET_DIR:-/root/VPS-Server-Menu}"
BIN_DIR="${VPS_MENU_BIN_DIR:-/usr/local/bin}"
BASHRC_FILE="${VPS_MENU_BASHRC_FILE:-$HOME/.bashrc}"

echo -e "${YELLOW}>>> Начинаю удаление VPS-Server-Menu...${NC}"

# A missing or broken symlink must not leave an enabled timer behind.
watchdog_bin="$BIN_DIR/warp_watchdog.sh"
watchdog_source="$TARGET_DIR/warp_watchdog.sh"
watchdog_unit_dir="${WARP_WATCHDOG_UNIT_DIR:-/etc/systemd/system}"
watchdog_state_dir="${WARP_WATCHDOG_STATE_DIR:-/var/lib/vps-server-menu/warp-watchdog}"
if [ -x "$watchdog_bin" ]; then
    "$watchdog_bin" remove || exit 1
elif [ -x "$watchdog_source" ]; then
    "$watchdog_source" remove || exit 1
else
    if command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now vps-warp-watchdog.timer >/dev/null 2>&1 || true
        systemctl stop vps-warp-watchdog.timer >/dev/null 2>&1 || true
        systemctl stop vps-warp-watchdog.service >/dev/null 2>&1 || true
        if systemctl is-enabled --quiet vps-warp-watchdog.timer ||
            systemctl is-active --quiet vps-warp-watchdog.timer ||
            systemctl is-active --quiet vps-warp-watchdog.service; then
            echo 'Не удалось остановить WARP Watchdog; удаление остановлено.' >&2
            exit 1
        fi
    elif [ -e "$watchdog_unit_dir/vps-warp-watchdog.timer" ] ||
        [ -e "$watchdog_unit_dir/vps-warp-watchdog.service" ]; then
        echo 'Нужен systemctl для безопасного удаления Watchdog.' >&2
        exit 1
    fi
    rm -f -- "$watchdog_unit_dir/timers.target.wants/vps-warp-watchdog.timer" \
        "$watchdog_unit_dir/vps-warp-watchdog.timer" "$watchdog_unit_dir/vps-warp-watchdog.service"
    if command -v systemctl >/dev/null 2>&1; then systemctl daemon-reload || exit 1; fi
    rm -f -- "$watchdog_state_dir/state.json" "$watchdog_state_dir/config.json" "$watchdog_state_dir/manual-stop"
    rmdir "$watchdog_state_dir" 2>/dev/null || true
fi
[ ! -L "$watchdog_bin" ] || rm -f -- "$watchdog_bin"

# 1. Удаление символических ссылок из /usr/local/bin
echo -e "${YELLOW}>>> Удаление системных ссылок...${NC}"
[ -L "$BIN_DIR/server-menu" ] && rm "$BIN_DIR/server-menu" && echo -e "${GREEN}✓ Ссылка server-menu удалена${NC}"
[ -L "$BIN_DIR/ipv6-menu" ] && rm "$BIN_DIR/ipv6-menu" && echo -e "${GREEN}✓ Ссылка ipv6-menu удалена${NC}"

# 2. Удаление конфигурационных файлов
echo -e "${YELLOW}>>> Удаление вспомогательных файлов...${NC}"
[ -f "$BIN_DIR/_config_and_utils.sh" ] && rm "$BIN_DIR/_config_and_utils.sh" && echo -e "${GREEN}✓ _config_and_utils.sh удален${NC}"

# 3. Удаление основной директории репозитория
if [ -d "$TARGET_DIR" ]; then
    read -p "Удалить папку репозитория $TARGET_DIR со всеми скриптами? (y/n): " confirm
    if [[ $confirm == [yY] ]]; then
        rm -rf "$TARGET_DIR"
        echo -e "${GREEN}✓ Директория $TARGET_DIR полностью удалена${NC}"
    else
        echo -e "${YELLOW}! Директория сохранена${NC}"
    fi
fi
# 4. Удаление автозапуска из .bashrc
echo -e "${YELLOW}>>> Очистка автозапуска из ~/.bashrc...${NC}"
if grep -q "server-menu" "$BASHRC_FILE" 2>/dev/null; then
    # Удаляем строку, содержащую "server-menu", и сохраняем во временный файл
    sed -i '/server-menu/d' "$BASHRC_FILE"
    echo -e "${GREEN}✓ Автозапуск удален из ~/.bashrc${NC}"
else
    echo -e "${YELLOW}! Запись автозапуска не найдена${NC}"
fi

# Бонус: очистка пустых строк, которые могли остаться в конце файла
[ ! -f "$BASHRC_FILE" ] || sed -i '${/^$/d;}' "$BASHRC_FILE"
echo -e "${GREEN}======================================================"
echo -e "✅ УДАЛЕНИЕ ЗАВЕРШЕНО"
echo -e "------------------------------------------------------"
echo -e "Система очищена от скриптов меню."
echo -e "======================================================${NC}"
