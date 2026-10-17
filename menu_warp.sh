#!/bin/bash
if [ -f "/root/VPS-Server-Menu/_config_and_utils.sh" ]; then
    source /root/VPS-Server-Menu/_config_and_utils.sh
elif [ -f "/usr/local/bin/_config_and_utils.sh" ]; then
    source /usr/local/bin/_config_and_utils.sh
fi

# ----------------------------------------------------------------------
# УПРАВЛЕНИЕ CLOUDFLARE WARP
# ----------------------------------------------------------------------

function get_warp_status {
    if ! command -v warp-cli &> /dev/null; then
        echo -e "${RED}НЕ УСТАНОВЛЕН${NC}"
    elif systemctl is-active --quiet warp-svc; then
        echo -e "${GREEN}РАБОТАЕТ${NC}"
    else
        echo -e "${YELLOW}ОСТАНОВЛЕН${NC}"
    fi
}

function setup_warp_cron {
    while true; do
        clear
        echo -e "${CYAN}--- 🔄 НАСТРОЙКА АВТОПЕРЕЗАПУСКА WARP --------------------${NC}"
        echo -e "    Текущий статус: $(get_warp_cron_status)"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        echo -e "1) 🌙  Каждую ночь (в 03:00)"
        echo -e "2) 📅  Раз в неделю (в Воскресенье ночью)"
        echo -e "3) ⏳  Каждые 12 часов"
        echo -e "4) 🚫  Отключить автоперезапуск"
        echo -e "5) ✍️   Задать свой график (формат Cron)"
        echo -e "X) 🔙  Назад"
        echo -e "${BLUE}----------------------------------------------------------${NC}"
        read -p "Выбор: " cron_choice
        case $cron_choice in
            1) cron_rule="0 3 * * * systemctl restart warp-svc >/dev/null 2>&1" ;;
            2) cron_rule="0 3 * * 0 systemctl restart warp-svc >/dev/null 2>&1" ;;
            3) cron_rule="0 */12 * * * systemctl restart warp-svc >/dev/null 2>&1" ;;
            4) crontab -l 2>/dev/null | grep -v "warp-svc" | crontab -; echo -e "${GREEN}✅ Отключено.${NC}"; sleep 1; return ;;
            5)
                echo -e "\n${CYAN}╭─── Справка по формату Cron ──────────────────────╮${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}* * * * *${NC}                                       ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ │ │ │${NC}                                       ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ │ │ └${NC} День недели (0-7, где 0 или 7 это Вс) ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ │ └────${NC} Месяц (1-12)                        ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ │ └──────${NC} День месяца (1-31)                  ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}│ └────────${NC} Часы (0-23)                         ${CYAN}│${NC}"
                echo -e "${CYAN}│${NC}  ${YELLOW}└──────────${NC} Минуты (0-59)                       ${CYAN}│${NC}"
                echo -e "${CYAN}╰──────────────────────────────────────────────────╯${NC}"
                echo -e "${YELLOW}Доступные форматы: ${GREEN}*${NC} (все), ${GREEN}1-5${NC} (диапазон), ${GREEN}6,0${NC} (список), ${GREEN}*/10${NC} (шаг)"
                echo -e "${YELLOW}Популярные примеры:${NC}"
                echo -e "  ${GREEN}0 5 * * *${NC}    (Каждый день ровно в 05:00)"
                echo -e "  ${GREEN}*/30 * * * *${NC} (Каждые 30 минут)"
                echo -e "  ${GREEN}0 2 * * 1-5${NC}  (По будням в 02:00)"
                echo -e "  ${GREEN}0 12 * * 6,0${NC} (По выходным в 12:00)"
                echo ""
                read -p "Ваш график (5 значений через пробел): " custom_cron
                
                # Простая проверка: должно быть ровно 5 "слов" (значений)
                if [[ $(echo "$custom_cron" | wc -w) -eq 5 ]]; then
                    cron_rule="$custom_cron systemctl restart warp-svc >/dev/null 2>&1"
                else
                    echo -e "${RED}❌ Ошибка! Нужно ввести ровно 5 значений (например: 0 4 * * *).${NC}"
                    sleep 2
                    continue
                fi
                ;;
            [Xx]) return ;;
            *) continue ;;
        esac
        
        # Применяем правило
        crontab -l 2>/dev/null | grep -v "warp-svc" | crontab -
        (crontab -l 2>/dev/null; echo "$cron_rule") | crontab -
        echo -e "${GREEN}✅ Расписание обновлено!${NC}"; sleep 1; return
    done
}


function get_warp_cron_status {
    local cron_rule=$(crontab -l 2>/dev/null | grep -w "warp-svc")
    
    if [ -z "$cron_rule" ]; then
        echo -e "${RED}ВЫКЛЮЧЕН${NC}"
        return
    fi

    local m=$(echo "$cron_rule" | awk '{print $1}')
    local h=$(echo "$cron_rule" | awk '{print $2}')
    local d=$(echo "$cron_rule" | awk '{print $3}')
    local mon=$(echo "$cron_rule" | awk '{print $4}')
    local dow=$(echo "$cron_rule" | awk '{print $5}')

    # 0. Ежеминутно (* * * * * или * * * * 0-7)
    if [[ "$m" == "*" && "$h" == "*" && "$d" == "*" && "$mon" == "*" && ("$dow" == "*" || "$dow" == "0-7") ]]; then
        echo -e "${GREEN}Каждую минуту (Осторожно!)${NC}"

    # 1. Ежедневно в определенное время (0 2 * * * или 0 2 * * 0-7)
    elif [[ "$d" == "*" && "$mon" == "*" && ("$dow" == "*" || "$dow" == "0-7") && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$h" "$m"
        echo -e "${GREEN}Ежедневно в $formatted_time${NC}"

    # 2. По будням (например, 0 2 * * 1-5)
    elif [[ "$d" == "*" && "$mon" == "*" && "$dow" == "1-5" && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$h" "$m"
        echo -e "${GREEN}По будням в $formatted_time${NC}"

    # 3. По выходным (например, 0 2 * * 6,0 или 6,7)
    elif [[ "$d" == "*" && "$mon" == "*" && ("$dow" == "6,0" || "$dow" == "0,6" || "$dow" == "6,7") && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$h" "$m"
        echo -e "${GREEN}По выходным в $formatted_time${NC}"

    # 4. Раз в неделю (конкретный день, например 0 3 * * 0)
    elif [[ "$d" == "*" && "$mon" == "*" && "$dow" =~ ^[0-7]$ && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$h" "$m"
        local days=("Вс" "Пн" "Вт" "Ср" "Чт" "Пт" "Сб" "Вс")
        echo -e "${GREEN}Раз в неделю (${days[$dow]} $formatted_time)${NC}"

    # 5. Ежемесячно (например, 0 5 15 * * -> 15-го числа)
    elif [[ "$d" =~ ^[0-9]+$ && "$mon" == "*" && "$dow" == "*" && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$h" "$m"
        echo -e "${GREEN}Каждое $d-е число в $formatted_time${NC}"

    # 6. Точная дата / Ежегодно (например, 23 4 21 3 * -> 21 Марта в 04:23)
    elif [[ "$d" =~ ^[0-9]+$ && "$mon" =~ ^[0-9]+$ && "$dow" == "*" && "$h" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]]; then
        printf -v formatted_time "%02d:%02d" "$h" "$m"
        local months=("" "Января" "Февраля" "Марта" "Апреля" "Мая" "Июня" "Июля" "Августа" "Сентября" "Октября" "Ноября" "Декабря")
        echo -e "${GREEN}Ежегодно $d ${months[$mon]} в $formatted_time${NC}"

    # 7. Каждые X часов (например, 0 */12 * * *)
    elif [[ "$h" == */* && "$m" =~ ^[0-9]+$ && "$d" == "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        local hours=${h#*/}
        echo -e "${GREEN}Каждые $hours ч.${NC}"

    # 8. Каждые X минут (например, */30 * * * *)
    elif [[ "$m" == */* && "$h" == "*" && "$d" == "*" && "$mon" == "*" && "$dow" == "*" ]]; then
        local mins=${m#*/}
        echo -e "${GREEN}Каждые $mins мин.${NC}"

    # 9. Если кастомный (совсем сложная комбинация)
    else
        echo -e "${GREEN}Свой график ($m $h $d $mon $dow)${NC}"
    fi
}

# WARPSCOUT работает отдельно от официального warp-cli / warp-svc.
function install_warpscout() (
    local installer
    umask 077
    installer=$(mktemp) || return 1
    trap 'rm -f -- "$installer"' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}❌ Для установки WARPSCOUT нужен curl (apt install curl).${NC}"
        return 1
    fi
    echo -e "${CYAN}>>> Загрузка официального installer WARPSCOUT...${NC}"
    if ! curl -fSL --connect-timeout 15 --max-time 120 \
        https://raw.githubusercontent.com/vernette/warpscout/master/install.sh -o "$installer"; then
        echo -e "${RED}❌ Не удалось загрузить installer с GitHub. Повторите позже.${NC}"
        return 1
    fi
    # Повторный запуск обновляет бинарник; актуальная версия остаётся на месте.
    INSTALL_DIR=/usr/local/bin sh "$installer" --yes || return "$?"
    /usr/local/bin/warpscout version
)

function prepare_warpscout_data {
    if ! (umask 077; mkdir -p -- "$warpscout_dir") || ! chmod 700 "$warpscout_dir"; then
        echo -e "${RED}❌ Не удалось подготовить каталог: ${warpscout_dir}${NC}"
        return 1
    fi
    if [ -f "$warpscout_account" ] && ! chmod 600 "$warpscout_account"; then
        echo -e "${RED}❌ Не удалось защитить account: ${warpscout_account}${NC}"
        return 1
    fi
}

function show_warpscout_status {
    local version
    if [ ! -x "$warpscout_bin" ]; then
        echo -e "📦 WARPSCOUT: ${RED}НЕ УСТАНОВЛЕН${NC}"
    elif version=$("$warpscout_bin" version); then
        printf '%b%s%b\n' "📦 WARPSCOUT: ${GREEN}" "$version" "$NC"
    else
        echo -e "📦 WARPSCOUT: ${RED}ОШИБКА ЗАПУСКА — повторите установку${NC}"
    fi
    if [ -s "$warpscout_account" ] && [ -r "$warpscout_account" ]; then
        echo -e "🔑 Account: ${GREEN}ФАЙЛ НАЙДЕН${NC}"
    else
        echo -e "🔑 Account: ${YELLOW}ОТСУТСТВУЕТ / ПУСТ / НЕДОСТУПЕН${NC}"
    fi
    printf '   %s\n' "$warpscout_account"
}

function run_warpscout_command() (
    # Изменения cwd/umask и обработчиков сигналов не затрагивают родительское меню.
    trap - INT
    umask 077
    cd -- "$warpscout_dir" || return 1
    "$warpscout_bin" "$@"
)

function register_warpscout_account {
    # upstream register при повторном запуске меняет ключи. Здесь только создание.
    if [ -e "$warpscout_account" ] || [ -L "$warpscout_account" ]; then
        echo -e "${YELLOW}Account уже существует и сохранён без изменений.${NC}"
        printf 'Путь: %s\n' "$warpscout_account"
        echo "Для ручного управления используйте warpscout register -h."
        return 0
    fi
    if run_warpscout_command register -a "$warpscout_account"; then
        if [ -s "$warpscout_account" ]; then
            echo -e "${GREEN}✅ Account создан: ${warpscout_account}${NC}"
            return 0
        fi
        echo -e "${RED}❌ WARPSCOUT не создал account file.${NC}"
        return 1
    else
        return "$?"
    fi
}

function scan_warpscout_endpoints {
    local mode="$1" result_dir result=0
    local -a scan_args
    if [ ! -s "$warpscout_account" ] || [ ! -r "$warpscout_account" ]; then
        echo -e "${YELLOW}Сначала создайте account (пункт 2).${NC}"
        return 1
    fi
    result_dir=$(mktemp -d "$warpscout_dir/scan-$(date +%Y%m%d-%H%M%S)-XXXXXX") || return 1
    scan_args=(scan -a "$warpscout_account" -p awg -P -exclude-node DME -o "$result_dir/report.txt")
    case "$mode" in
        best) scan_args+=(-best) ;;
        config) scan_args+=(-conf "$result_dir/warp.conf") ;;
    esac
    echo -e "${CYAN}>>> AWG scan с проверкой туннеля, без узла DME.${NC}"
    echo "Проверяется сеть этой VPS. Каждый пункт запускает новый scan."
    echo "Ctrl+C — остановить scan и вернуться в меню (возможны частичные результаты)."
    printf 'Каталог результатов: %s\n' "$result_dir"
    run_warpscout_command "${scan_args[@]}" || result=$?
    if [ -s "$result_dir/report.txt" ]; then
        printf 'Отчёт: %s\n' "$result_dir/report.txt"
    elif [ "$result" -eq 0 ]; then
        echo -e "${RED}❌ Отчёт не был сохранён.${NC}"
        result=1
    fi
    if [ "$mode" = config ]; then
        if [ -s "$result_dir/warp.conf" ]; then
            printf 'AmneziaWG config: %s\n' "$result_dir/warp.conf"
        elif [ "$result" -eq 0 ]; then
            echo -e "${RED}❌ Config не был создан.${NC}"
            result=1
        fi
    fi
    return "$result"
}

function run_warpscout_menu {
    local warpscout_bin="/usr/local/bin/warpscout"
    local warpscout_dir="/root/.config/warpscout"
    local warpscout_account="$warpscout_dir/warpscout-account.json"
    local warpscout_choice result
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}             🛰️  WARPSCOUT — WARP ENDPOINTS             ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        show_warpscout_status
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e "${GREEN}1) 🚀  Установить / Обновить WARPSCOUT${NC}"
        echo -e "${YELLOW}2) 🔑  Создать WARP account (если отсутствует)${NC}"
        echo -e "${YELLOW}3) 🔎  Рекомендуемый scan (AWG, ping, без DME)${NC}"
        echo -e "${YELLOW}4) 🏆  Найти лучший endpoint (новый scan)${NC}"
        echo -e "${YELLOW}5) 📄  Создать AmneziaWG config (новый scan)${NC}"
        echo -e "${CYAN}6) ℹ️   Проверить статус / Наличие account${NC}"
        echo -e "${RED}X) 🔙  Назад в Endpoint Manager${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        read -r -p "Ваш выбор: " warpscout_choice || return 0
        result=0
        case "$warpscout_choice" in
            1) install_warpscout || result=$? ;;
            2|3|4|5)
                if [ ! -x "$warpscout_bin" ]; then
                    echo -e "${YELLOW}Сначала установите WARPSCOUT (пункт 1).${NC}"
                elif prepare_warpscout_data; then
                    case "$warpscout_choice" in
                        2) register_warpscout_account || result=$? ;;
                        3) scan_warpscout_endpoints scan || result=$? ;;
                        4) scan_warpscout_endpoints best || result=$? ;;
                        5) scan_warpscout_endpoints config || result=$? ;;
                    esac
                fi
                ;;
            6) show_warpscout_status ;;
            [Xx]) return 0 ;;
            *) echo -e "${RED}❌ Неверный ввод.${NC}" ;;
        esac
        if [ "$result" -eq 130 ]; then
            echo -e "${YELLOW}Операция прервана.${NC}"
        elif [ "$result" -ne 0 ]; then
            echo -e "${RED}❌ Операция WARPSCOUT завершилась с кодом ${result}. См. сообщения выше.${NC}"
        fi
        read -r -p "Нажмите Enter для возврата в WARPSCOUT menu..." || return 0
    done
}

# JSON CLI проверен с Cloudflare WARP 2026.8.2110.0. Неизвестная схема — отказ от изменений.
function warp_cli {
    local output result=0
    output=$(LC_ALL=C timeout --kill-after=2 8 warp-cli --accept-tos --json "$@") || result=$?
    if [ "$result" -ne 0 ]; then
        printf '%s\n' "$output" >&2
        return "$result"
    fi
    printf '%s\n' "$output"
}

function read_warp_state {
    local version
    warp_settings='' warp_status='' warp_protocol='' warp_endpoint='' warp_port='' warp_mode=''
    command -v warp-cli >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 &&
        command -v timeout >/dev/null 2>&1 || return 1
    systemctl is-active --quiet warp-svc || return 1
    warp_settings=$(warp_cli settings) || return 1
    # Отсутствующий override в этой схеме означает AUTO; неизвестную схему не принимаем за AUTO.
    jq -e '.settings | type == "object" and
        (.operation_mode | type == "string") and
        (.always_on | type == "boolean") and
        (.warp_tunnel_protocol == "masque" or .warp_tunnel_protocol == "wireguard") and
        (.proxy_port | type == "number" and . >= 1 and . <= 65535 and floor == .) and
        ((has("override_warp_endpoint") | not) or
          (.override_warp_endpoint | type == "string" and length > 0))' \
        <<< "$warp_settings" >/dev/null || return 1
    warp_mode=$(jq -r '.settings.operation_mode' <<< "$warp_settings")
    warp_protocol=$(jq -r '.settings.warp_tunnel_protocol' <<< "$warp_settings")
    if jq -e '.settings | has("override_warp_endpoint")' <<< "$warp_settings" >/dev/null; then
        warp_endpoint=$(jq -r '.settings.override_warp_endpoint' <<< "$warp_settings")
    else
        version=$(LC_ALL=C timeout --kill-after=2 8 warp-cli --version) || return 1
        case "${version%%$'\n'*}" in
            'warp-cli 2026.8.2110.0') warp_endpoint=AUTO ;;
            *) warp_endpoint=UNKNOWN ;;
        esac
    fi
    warp_port=$(jq -r '.settings.proxy_port' <<< "$warp_settings")
    warp_status=$(warp_cli status | jq -er '.status | select(type == "string")') || return 1
}

function show_warp_connection {
    if read_warp_state; then
        local endpoint_display="$warp_endpoint"
        [ "$endpoint_display" != UNKNOWN ] || endpoint_display="не определён (непроверенная версия CLI)"
        printf '🔗 Туннель: %s\n🌐 Протокол: %s\n🎯 Endpoint: %s\n🔌 SOCKS5: 127.0.0.1:%s (mode: %s)\n' \
            "$warp_status" "$warp_protocol" "$endpoint_display" "$warp_port" "$warp_mode"
    else
        echo -e "${YELLOW}🔗 Туннель / Протокол / Endpoint / SOCKS5: не определены${NC}"
    fi
}

function check_warp_health {
    local trace key value
    warp_health=DOWN
    warp_health_detail="warp-cli отсутствует или warp-svc не активен"
    if command -v warp-cli >/dev/null 2>&1 && systemctl is-active --quiet warp-svc; then
        warp_health=DEGRADED
        warp_health_detail="Невозможно прочитать JSON state (нужны jq, timeout и совместимый warp-cli)"
        if read_warp_state; then
            warp_health=DOWN
            warp_health_detail="Туннель: $warp_status; mode: $warp_mode"
            if [ "$warp_status" = Connected ] && [ "$warp_mode" = proxy ]; then
                warp_health_detail="SOCKS5 listener 127.0.0.1:$warp_port отсутствует (нужен ss)"
                if command -v ss >/dev/null 2>&1 &&
                    ss -H -lnt "sport = :$warp_port" | awk -v port="$warp_port" \
                        '$4 == "127.0.0.1:" port {found=1} END {exit !found}'; then
                    warp_health=DEGRADED
                    warp_health_detail="SOCKS5 trace недоступен (нужен curl)"
                    if command -v curl >/dev/null 2>&1 && trace=$(curl --disable -fsS \
                        --connect-timeout 4 --max-time 10 --noproxy "" \
                        --proxy "socks5h://127.0.0.1:$warp_port" https://www.cloudflare.com/cdn-cgi/trace); then
                        local warp_flag='' exit_ip='' colo='' location=''
                        while IFS='=' read -r key value; do
                            case "$key" in
                                warp) warp_flag="$value" ;;
                                ip) exit_ip="$value" ;;
                                colo) colo="$value" ;;
                                loc) location="$value" ;;
                            esac
                        done <<< "$trace"
                        warp_health_detail="warp=${warp_flag:-unknown}; IP=${exit_ip:-unknown}; colo=${colo:-unknown}; loc=${location:-unknown}"
                        [ "$warp_flag" != on ] || warp_health=HEALTHY
                    fi
                fi
            fi
        fi
    fi
    if [ "${1:-}" != quiet ]; then print_warp_health; fi
    [ "$warp_health" = HEALTHY ]
}

function print_warp_health {
    case "$warp_health" in
        HEALTHY) echo -e "${GREEN}❤️  WARP HEALTHY${NC}" ;;
        DEGRADED) echo -e "${YELLOW}❤️  WARP DEGRADED${NC}" ;;
        DOWN) echo -e "${RED}❤️  WARP DOWN${NC}" ;;
    esac
    printf '%s\n' "$warp_health_detail"
}

function wait_warp_health {
    local attempt
    for ((attempt=0; attempt<6; attempt++)); do
        if check_warp_health quiet; then
            print_warp_health
            return 0
        fi
        sleep 2
    done
    print_warp_health
    return 1
}

function normalize_warp_endpoint {
    # ipaddress проверяет IPv4/IPv6 полностью, включая сжатые и IPv4-mapped адреса.
    command -v python3 >/dev/null 2>&1 || { echo "Нужен python3 для проверки endpoint." >&2; return 1; }
    python3 - "$1" <<'PY'
import ipaddress, re, sys
match = re.fullmatch(r'(?:\[([^\]]+)\]|([^:]+)):([0-9]{1,5})', sys.argv[1])
try:
    if not match:
        raise ValueError()
    addr = ipaddress.ip_address(match[1] or match[2])
    port = int(match[3])
    if bool(match[1]) != (addr.version == 6) or not 1 <= port <= 65535 or '%' in str(addr):
        raise ValueError()
except ValueError:
    print('Нужен IPv4:PORT или [IPv6]:PORT, порт 1–65535.', file=sys.stderr)
    sys.exit(1)
print(f'[{addr}]:{port}' if addr.version == 6 else f'{addr}:{port}')
PY
}

function validate_warp_endpoint {
    normalize_warp_endpoint "$1" >/dev/null
}

function set_warp_endpoint {
    if [ "$1" = AUTO ]; then
        warp_cli tunnel endpoint reset >/dev/null
    else
        warp_cli tunnel endpoint set "$1" >/dev/null
    fi
}

function warp_config_matches {
    local expected="$1" expected_endpoint actual_endpoint
    read_warp_state || return 1
    expected_endpoint=$(jq -r '.endpoint' <<< "$expected")
    actual_endpoint="$warp_endpoint"
    if [ "$expected_endpoint" != AUTO ] && [ "$actual_endpoint" != AUTO ]; then
        expected_endpoint=$(normalize_warp_endpoint "$expected_endpoint") || return 1
        actual_endpoint=$(normalize_warp_endpoint "$actual_endpoint") || return 1
    fi
    [ "$expected_endpoint" = "$actual_endpoint" ] || return 1
    jq -e --argjson expected "$expected" '
        .settings as $s | $expected | .mode == $s.operation_mode and
        .port == $s.proxy_port and .protocol == $s.warp_tunnel_protocol' <<< "$warp_settings" >/dev/null
}

function rollback_warp_change {
    [ "$warp_pending" -eq 1 ] || return 0
    # Повторный Ctrl+C не должен оборвать восстановление посередине.
    trap '' INT TERM
    local failed=0
    echo -e "${YELLOW}Изменение не прошло проверку. Восстанавливаю прежние настройки WARP...${NC}"
    warp_cli disconnect >/dev/null || failed=1
    warp_cli mode proxy >/dev/null || failed=1
    warp_cli proxy port "$(jq -r '.port' <<< "$warp_before")" >/dev/null || failed=1
    warp_cli tunnel protocol set "$(jq -r '.protocol | if . == "masque" then "MASQUE" else "WireGuard" end' <<< "$warp_before")" >/dev/null || failed=1
    set_warp_endpoint "$(jq -r '.endpoint' <<< "$warp_before")" || failed=1
    if [ "$(jq -r '.connected' <<< "$warp_before")" = true ]; then
        warp_cli connect >/dev/null || failed=1
        wait_warp_health || failed=1
    else
        warp_cli disconnect >/dev/null || failed=1
        check_warp_health || true
        echo "До изменения WARP был отключён; восстановлено отключённое состояние."
        read_warp_state && [ "$warp_status" = Disconnected ] || failed=1
    fi
    warp_config_matches "$warp_before" || failed=1
    if [ "$failed" -eq 0 ]; then
        echo -e "${GREEN}✅ Rollback завершён.${NC}"
    else
        echo -e "${RED}❌ Rollback не подтверждён полностью. Проверьте warp-cli status и журнал warp-svc.${NC}"
    fi
}

function apply_warp_change() (
    local action="$1" value="$2" warp_before warp_target warp_pending=0 dependency
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    # Сериализуем изменения из разных экземпляров меню; state хранится только в памяти.
    for dependency in jq timeout curl ss python3 flock; do
        command -v "$dependency" >/dev/null 2>&1 || { printf 'Нужна команда: %s\n' "$dependency"; return 1; }
    done
    exec 9>>"${WARP_LOCK_FILE:-/run/lock/vps-server-menu-warp.lock}" || return 1
    flock -n 9 || { echo "Другое меню уже меняет настройки WARP."; return 1; }
    read_warp_state && [ "$warp_mode" = proxy ] || {
        echo -e "${RED}Нужен активный warp-svc с известным JSON state и mode proxy.${NC}"; return 1;
    }
    if [ "$warp_endpoint" = UNKNOWN ]; then
        echo "Текущий endpoint/AUTO в этой версии CLI не подтверждён; безопасный rollback невозможен."
        return 1
    fi
    warp_cli tunnel endpoint set --help >/dev/null && warp_cli tunnel endpoint reset --help >/dev/null &&
        warp_cli tunnel protocol set --help >/dev/null || return 1
    warp_before=$(jq -c --arg endpoint "$warp_endpoint" '.settings | {mode:.operation_mode,port:.proxy_port,
        protocol:.warp_tunnel_protocol,endpoint:$endpoint,connected:.always_on}' <<< "$warp_settings") || return 1
    warp_target="$warp_before"
    case "$action" in
        endpoint)
            if [ "$value" != AUTO ]; then value=$(normalize_warp_endpoint "$value") || return 1; fi
            warp_target=$(jq -c --arg value "$value" '.endpoint=$value' <<< "$warp_target") ;;
        protocol)
            # Runtime: proxy mode в текущем warp-svc поддерживает только MASQUE/QUIC.
            [ "$value" = masque ] || { echo "WireGuard недоступен в SOCKS5 proxy mode."; return 1; }
            warp_target=$(jq -c '.protocol="masque" | .endpoint="AUTO"' <<< "$warp_target") ;;
        port)
            if ! [[ "$value" =~ ^[0-9]{1,5}$ ]] || [ "$((10#$value))" -lt 1 ] || [ "$((10#$value))" -gt 65535 ]; then
                echo "Нужен SOCKS5 порт 1–65535."
                return 1
            fi
            warp_target=$(jq -c --argjson value "$((10#$value))" '.port=$value' <<< "$warp_target") ;;
        *) return 1 ;;
    esac
    [ "$(jq -r '.protocol' <<< "$warp_target")" = masque ] || {
        echo "Proxy mode требует MASQUE. Выберите MASQUE в Endpoint Manager."; return 1;
    }
    trap 'rollback_warp_change' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    warp_pending=1
    warp_cli disconnect >/dev/null || return 1
    case "$action" in
        protocol) warp_cli tunnel protocol set MASQUE >/dev/null || return 1 ;;
        port) warp_cli proxy port "$value" >/dev/null || return 1 ;;
    esac
    if [ "$action" != port ]; then
        set_warp_endpoint "$(jq -r '.endpoint' <<< "$warp_target")" || return 1
    fi
    warp_cli connect >/dev/null || return 1
    if wait_warp_health && warp_config_matches "$warp_target"; then
        warp_pending=0
        echo -e "${GREEN}✅ Настройки применены; SOCKS5 trace подтвердил warp=on.${NC}"
        return 0
    fi
    return 1
)

function get_warp_scan_profile {
    local stats version
    # Читаем реальный transport; HTTP option в settings может игнорироваться proxy.
    stats=$(warp_cli tunnel stats) || stats='{}'
    if [ "$(jq -r '.protocol // ""' <<< "$stats")" = 'MASQUE (HTTPS via UDP)' ]; then
        warp_scan_sni=$(jq -er '.tls.sni | select(type == "string" and test("^[a-zA-Z0-9.-]+$"))' <<< "$stats") || return 1
        return 0
    fi
    # Для отключённого туннеля fallback только на экспериментально проверенную версию.
    version=$(warp-cli --version) || return 1
    if [[ "${version%%$'\n'*}" == 'warp-cli 2026.8.2110.0' ]] &&
        [ "$(jq -r '.protocol // ""' <<< "$stats")" = '' ]; then
        warp_scan_sni=consumer-masque-proxy.cloudflareclient.com
        return 0
    fi
    echo "Transport official proxy не подтверждён как MASQUE/QUIC; автоматический scan отменён."
    return 1
}

function optimize_warp_endpoint {
    local warpscout_bin="/usr/local/bin/warpscout" warpscout_dir="/root/.config/warpscout"
    local warpscout_account="$warpscout_dir/warpscout-account.json" answer result_dir endpoint warp_scan_sni
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    read_warp_state && [ "$warp_mode" = proxy ] || { echo "Нужен активный WARP в mode proxy."; return 1; }
    if [ "$warp_protocol" != masque ]; then
        echo "Текущий SOCKS5 proxy поддерживает только MASQUE. Сначала выберите MASQUE в меню протокола."
        return 1
    fi
    get_warp_scan_profile || return 1
    if [ ! -x "$warpscout_bin" ]; then
        read -r -p "Установить WARPSCOUT для поиска endpoint? [y/N]: " answer || return 1
        [[ "$answer" =~ ^[Yy]$ ]] || return 1
        install_warpscout || return 1
    fi
    prepare_warpscout_data || return 1
    if [ ! -s "$warpscout_account" ]; then
        read -r -p "Создать отдельный WARPSCOUT account? [y/N]: " answer || return 1
        [[ "$answer" =~ ^[Yy]$ ]] || return 1
        register_warpscout_account || return 1
    fi
    result_dir=$(mktemp -d "$warpscout_dir/official-$(date +%Y%m%d-%H%M%S)-XXXXXX") || return 1
    echo -e "${CYAN}>>> MASQUE/QUIC scan для official SOCKS5 WARP; смена Cloudflare node не гарантируется.${NC}"
    printf 'Результаты: %s\n' "$result_dir"
    # -best stdout — только endpoint; stderr остаётся интерактивным, без парсинга таблиц.
    # Proxy WARP использует этот SNI; AWG и MASQUE node-фильтры здесь неприменимы.
    if ! run_warpscout_command scan -a "$warpscout_account" -p masque -P -best -plain \
        -masque-sni "$warp_scan_sni" -o "$result_dir/report.txt" > "$result_dir/best.txt"; then
        echo -e "${RED}Scan не завершился успешно; WARP не изменён.${NC}"
        return 1
    fi
    endpoint=$(cat "$result_dir/best.txt")
    validate_warp_endpoint "$endpoint" || return 1
    if [ -s "$result_dir/report.txt" ]; then
        printf 'Отчёт: %s\n' "$result_dir/report.txt"
    else
        echo -e "${YELLOW}WARPSCOUT не сохранил отчёт; endpoint будет проверен через official SOCKS5.${NC}"
    fi
    # Protocol мог измениться из другого shell за время scan: проверяем повторно.
    read_warp_state && [ "$warp_protocol" = masque ] && [ "$warp_mode" = proxy ] || return 1
    printf 'Найден endpoint: %s\n' "$endpoint"
    apply_warp_change endpoint "$endpoint"
}

function run_warp_endpoint_menu {
    local endpoint_choice endpoint answer
    local warp_settings warp_status warp_protocol warp_endpoint warp_port warp_mode
    local warpscout_bin="/usr/local/bin/warpscout" warpscout_dir="/root/.config/warpscout"
    local warpscout_account="$warpscout_dir/warpscout-account.json"
    while true; do
        clear
        echo -e "${CYAN}--- 🎯 WARP ENDPOINT MANAGER / WARPSCOUT ---------------${NC}"
        echo -e "📦 Служба: $(get_warp_status)"
        show_warp_connection
        show_warpscout_status
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo "1) 🔎 Найти совместимый endpoint → Применить → Проверить"
        echo "2) ✍️  Задать endpoint вручную"
        echo "3) 🔄 Сбросить endpoint на Cloudflare AUTO"
        echo "4) 🌐 Выбрать протокол (совместимость SOCKS5)"
        echo "5) ❤️  Проверить здоровье WARP"
        echo "6) 🛰️  Advanced WARPSCOUT (AWG / AmneziaWG)"
        echo "X) 🔙 Назад в WARP menu"
        read -r -p "Ваш выбор: " endpoint_choice || return 0
        case "$endpoint_choice" in
            1) optimize_warp_endpoint || true ;;
            2)
                read -r -p "Endpoint (IPv4:PORT или [IPv6]:PORT; Enter — отмена): " endpoint || return 0
                [ -z "$endpoint" ] || apply_warp_change endpoint "$endpoint"
                ;;
            3) apply_warp_change endpoint AUTO || true ;;
            4)
                echo "Текущий warp-svc: SOCKS5 proxy поддерживает MASQUE/QUIC; WireGuard не работает."
                echo "Настройка MASQUE HTTP/2 в проверенной версии не меняет transport proxy."
                read -r -p "Выбрать MASQUE и сбросить endpoint на AUTO? [y/N]: " answer || return 0
                if [[ "$answer" =~ ^[Yy]$ ]]; then apply_warp_change protocol masque || true; fi
                ;;
            5) check_warp_health || true ;;
            6) run_warpscout_menu ;;
            [Xx]) return 0 ;;
            *) echo -e "${RED}Неверный ввод.${NC}" ;;
        esac
        read -r -p "Нажмите Enter для возврата в Endpoint Manager..." || return 0
    done
}

function install_official_warp() (
    local key_file codename attempt answer cron_entries
    if command -v warp-cli >/dev/null 2>&1; then
        echo -e "${YELLOW}WARP уже установлен.${NC}"
        check_warp_health
        return "$?"
    fi
    key_file=$(mktemp) || return 1
    trap 'rm -f -- "$key_file"' EXIT
    trap 'exit 130' INT
    echo -e "${CYAN}>>> Установка официального Cloudflare WARP...${NC}"
    if ! command -v curl >/dev/null 2>&1 || ! command -v gpg >/dev/null 2>&1; then
        apt-get update && apt-get install -y curl gpg ca-certificates || return 1
    fi
    codename=$(lsb_release -cs) || return 1
    curl -fSL --connect-timeout 15 --max-time 120 https://pkg.cloudflareclient.com/pubkey.gpg -o "$key_file" &&
        gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg "$key_file" || return 1
    printf 'deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ %s main\n' \
        "$codename" > /etc/apt/sources.list.d/cloudflare-client.list || return 1
    apt-get update && apt-get install -y --no-install-recommends cloudflare-warp jq python3 || return 1
    hash -r
    systemctl enable --now warp-svc || return 1
    for ((attempt=0; attempt<10; attempt++)); do
        if warp_cli settings >/dev/null; then break; fi
        sleep 2
    done
    # Proxy задаём до регистрации/подключения: host routing никогда не включается.
    if ! warp_cli mode proxy >/dev/null || ! warp_cli proxy port 40000 >/dev/null; then
        echo -e "${RED}WARP установлен, но настройка proxy не завершена.${NC}"
        return 1
    fi
    if ! warp_cli registration show >/dev/null; then
        warp_cli registration new >/dev/null || return 1
    fi
    if ! warp_cli connect >/dev/null; then
        echo -e "${RED}WARP установлен, но connect не завершён.${NC}"
        return 1
    fi
    cron_entries=$(crontab -l 2>/dev/null || true)
    if ! { printf '%s\n' "$cron_entries" | grep -v 'warp-svc'; echo '0 3 * * * systemctl restart warp-svc >/dev/null 2>&1'; } | crontab -; then
        echo -e "${YELLOW}Не удалось настроить cron restart; проверьте crontab.${NC}"
    fi
    if wait_warp_health; then
        echo -e "${GREEN}✅ WARP установлен; SOCKS5 127.0.0.1:40000 проверен.${NC}"
    else
        echo -e "${YELLOW}WARP установлен, но tunnel/proxy health check не пройден.${NC}"
        read -r -p "Попробовать подобрать endpoint через WARPSCOUT? [y/N]: " answer || return 1
        [[ "$answer" =~ ^[Yy]$ ]] || return 1
        optimize_warp_endpoint
    fi
)

function run_warp_menu {
    while true; do
        clear
        echo -e "${CYAN}======================================================${NC}"
        echo -e "${CYAN}             ☁️  УПРАВЛЕНИЕ CLOUDFLARE WARP ☁️             ${NC}"
        echo -e "${CYAN}======================================================${NC}"
        echo -e "📦 Служба:        $(get_warp_status)"
        show_warp_connection
        echo -e "🔄 Авторестарт:   $(get_warp_cron_status)"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        echo -e "${GREEN}1) 🚀  Установить WARP (режим SOCKS5)${NC}"
        echo -e "${YELLOW}2) ⚙️   Изменить порт прокси${NC}"
        echo -e "${YELLOW}3) 🔄  Настроить расписание автоперезапуска${NC}"
        echo -e "${YELLOW}4) 🛑  Остановить / Запустить службу${NC}"
        echo -e "${YELLOW}5) 📄  Просмотр логов (в реальном времени)${NC}"
        echo -e "${RED}6) 🗑️   Полностью удалить WARP из системы${NC}"
        echo -e "${CYAN}7) 🎯  Endpoint Manager / WARPSCOUT${NC}"
        echo -e "${CYAN}8) ❤️   Проверить здоровье WARP${NC}"
        echo -e "${RED}X) 🔙  Назад в предыдущее меню${NC}"
        echo -e "${BLUE}------------------------------------------------------${NC}"
        
        read -r -p "Ваш выбор: " choice || return 0
        case $choice in
            1)
                trap ':' INT
                install_official_warp || echo -e "${YELLOW}Установка/проверка WARP не завершена успешно.${NC}"
                read -r -p "Нажмите Enter..."
                trap - INT
                ;;
            2)
                read -r -p "Новый SOCKS5 порт (1–65535): " new_port
                trap ':' INT
                apply_warp_change port "$new_port" || true
                read -r -p "Нажмите Enter..."
                trap - INT
                ;;
            3) setup_warp_cron ;;
            4)
                if systemctl is-active --quiet warp-svc; then
                    systemctl stop warp-svc
                else
                    systemctl start warp-svc
                fi ;;
            5)
                echo -e "${CYAN}>>> Просмотр логов warp-svc (Ctrl+C для выхода)...${NC}"
                sleep 1
                trap ' ' INT
                journalctl -eu warp-svc -f
                trap - INT
                ;;
            6)
                if ! command -v warp-cli &> /dev/null; then
                    echo -e "${RED}WARP не установлен.${NC}"; read -p "Enter..."; continue
                fi
                read -p "⚠️  Вы уверены, что хотите ПОЛНОСТЬЮ удалить WARP? (y/N): " conf
                if [[ "$conf" =~ ^[Yy]$ ]]; then
                    echo -e "${YELLOW}Остановка и очистка...${NC}"
                    warp-cli --accept-tos disconnect >/dev/null 2>&1
                    systemctl disable --now warp-svc >/dev/null 2>&1
                    
                    if DEBIAN_FRONTEND=noninteractive apt-get purge -y cloudflare-warp >/dev/null 2>&1; then
                        rm -f /etc/apt/sources.list.d/cloudflare-client.list
                        rm -f /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
                        crontab -l 2>/dev/null | grep -v "warp-svc" | crontab -
                        hash -r 
                        echo -e "${GREEN}✅ WARP полностью удален из системы.${NC}"
                    else
                        echo -e "${RED}❌ Ошибка! APT заблокирован.${NC}"
                    fi
                fi
                read -p "Нажмите Enter..." ;;
            7)
                trap ':' INT
                run_warp_endpoint_menu
                trap - INT
                ;;
            8)
                trap ':' INT
                check_warp_health || true
                read -r -p "Нажмите Enter..."
                trap - INT
                ;;
            [Xx]) return ;;
        esac
    done
}
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    run_warp_menu
fi
