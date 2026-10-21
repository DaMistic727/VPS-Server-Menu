#!/bin/bash
# Optional systemd timer for the existing official-WARP health API.
set -euo pipefail

STATE_DIR="${WARP_WATCHDOG_STATE_DIR:-/var/lib/vps-server-menu/warp-watchdog}"
UNIT_DIR="${WARP_WATCHDOG_UNIT_DIR:-/etc/systemd/system}"
LOCK_FILE="${WARP_LOCK_FILE:-/run/lock/vps-server-menu-warp.lock}"
HEALTH_BIN="${WARP_WATCHDOG_HEALTH_BIN:-/usr/local/bin/server-menu}"
SCRIPT_DIR=$(cd "$(dirname "$(readlink -f "$0")")" && pwd)
STATE_FILE="$STATE_DIR/state.json"
CONFIG_FILE="$STATE_DIR/config.json"
MANUAL_STOP_FILE="$STATE_DIR/manual-stop"
TIMER=vps-warp-watchdog.timer
SERVICE=vps-warp-watchdog.service

need_root() { [ "$(id -u)" -eq 0 ] || { echo 'Run as root.' >&2; return 1; }; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date -u +%s; }
boot_id() { if [ -n "${WARP_WATCHDOG_BOOT_ID:-}" ]; then echo "$WARP_WATCHDOG_BOOT_ID"; else cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown; fi; }
log_event() { logger -t vps-warp-watchdog -- "$1" 2>/dev/null || true; }

ensure_dir() {
    install -d -m 700 "$STATE_DIR"
    [ -f "$CONFIG_FILE" ] || printf '{"autoRecovery":false}\n' > "$CONFIG_FILE"
    chmod 600 "$CONFIG_FILE"
}

default_state() {
    jq -n '{status:"UNKNOWN",lastCheck:null,lastSuccess:null,consecutiveFailures:0,
      consecutiveDown:0,lastReason:"",incidentCount:0,incidentOpen:false,
      firstFailureEpoch:null,incidentConfirmedEpoch:null,
      lastRecovery:null,lastOutageSeconds:null,
      exitIp:null,colo:null,lastAttemptEpoch:0,lastAttemptResult:null,
      bootId:"",port:null,events:[]}'
}

read_state() {
    if [ -f "$STATE_FILE" ] && jq -e 'type == "object" and (.events | type == "array") and
        (.consecutiveFailures | type == "number") and (.incidentCount | type == "number")' \
        "$STATE_FILE" >/dev/null 2>&1; then
        # Older state stored only the confirmation time; the first failure is unknown.
        jq -c '.firstFailureEpoch = (.firstFailureEpoch // null) |
            .incidentConfirmedEpoch = (.incidentConfirmedEpoch //
                (if .incidentOpen then .incidentStartEpoch else null end)) |
            del(.incidentStartEpoch)' "$STATE_FILE"
    else
        default_state
    fi
}

write_state() {
    local temp
    temp=$(mktemp "$STATE_DIR/.state.XXXXXXXX") || return 1
    chmod 600 "$temp"
    if ! cat > "$temp"; then rm -f -- "$temp"; return 1; fi
    mv -f -- "$temp" "$STATE_FILE"
}

install_units() {
    need_root
    install -d -m 755 "$UNIT_DIR"
    install -m 644 "$SCRIPT_DIR/systemd/$SERVICE" "$UNIT_DIR/$SERVICE"
    install -m 644 "$SCRIPT_DIR/systemd/$TIMER" "$UNIT_DIR/$TIMER"
    systemctl daemon-reload
}

enabled() { systemctl is-enabled --quiet "$TIMER" 2>/dev/null; }

enable_watchdog() {
    need_root
    for dep in jq flock timeout warp-cli systemctl; do
        command -v "$dep" >/dev/null 2>&1 || { echo "Missing dependency: $dep" >&2; return 1; }
    done
    ensure_dir
    install_units
    systemctl enable --now "$TIMER"
    echo 'WARP Watchdog enabled.'
}

disable_watchdog() {
    need_root
    if enabled; then
        systemctl disable --now "$TIMER" >/dev/null 2>&1 || true
    else
        systemctl stop "$TIMER" >/dev/null 2>&1 || true
    fi
    systemctl stop "$SERVICE" >/dev/null 2>&1 || true
    if enabled || systemctl is-active --quiet "$TIMER" ||
        systemctl is-active --quiet "$SERVICE"; then
        echo 'Watchdog timer or service is still enabled or active.' >&2
        return 1
    fi
    echo 'WARP Watchdog disabled.'
}

remove_watchdog() {
    need_root
    disable_watchdog >/dev/null
    rm -f -- "$UNIT_DIR/$TIMER" "$UNIT_DIR/$SERVICE"
    systemctl daemon-reload
    rm -f -- "$STATE_FILE" "$CONFIG_FILE" "$MANUAL_STOP_FILE"
    rmdir "$STATE_DIR" 2>/dev/null || true
}

auto_recovery_set() {
    local enabled_value="$1" temp
    need_root
    ensure_dir
    temp=$(mktemp "$STATE_DIR/.config.XXXXXXXX") || return 1
    chmod 600 "$temp"
    if ! jq -nc --argjson value "$enabled_value" '{autoRecovery:$value}' > "$temp"; then
        rm -f -- "$temp"; return 1
    fi
    mv -f -- "$temp" "$CONFIG_FILE"
}

auto_recovery_enabled() {
    [ -f "$CONFIG_FILE" ] && jq -e '.autoRecovery == true' "$CONFIG_FILE" >/dev/null 2>&1
}

watchdog_summary() {
    local mode=Disabled recovery=Off
    enabled && mode=Enabled
    auto_recovery_enabled && recovery=On
    if [ -f "$STATE_FILE" ]; then
        jq -r --arg mode "$mode" --arg recovery "$recovery" \
            '"Watchdog: \($mode) | WARP: \(.status) | Last check: \(.lastCheck // "never") | Failures: \(.consecutiveFailures) | Auto-recovery: \($recovery)"' \
            "$STATE_FILE" 2>/dev/null || echo "Watchdog: $mode | WARP: UNKNOWN | Auto-recovery: $recovery"
    else
        echo "Watchdog: $mode | WARP: UNKNOWN | Last check: never | Failures: 0 | Auto-recovery: $recovery"
    fi
}

watchdog_status() {
    watchdog_summary
    if [ -f "$STATE_FILE" ]; then
        jq -r '"Last success: \(.lastSuccess // "never")\nLast reason: \(.lastReason)\nIncidents: \(.incidentCount)\nLast recovery: \(.lastRecovery // "never")\nLast outage: \(if .lastOutageSeconds == null then "unknown" else (.lastOutageSeconds|tostring) + " seconds" end)\nExit IP: \(.exitIp // "unknown")\nColo: \(.colo // "unknown")\nLast action: \(.lastAttemptResult // "none")"' "$STATE_FILE"
    fi
}

watchdog_events() {
    if [ -f "$STATE_FILE" ]; then
        jq -r '.events[-20:][] | "\(.time) \(.type): \(.detail)"' "$STATE_FILE"
    fi
}

# Read only the live port. The health verdict itself always comes from PR #6.
live_port() {
    local settings
    settings=$(timeout --kill-after=2s 8s warp-cli --accept-tos --json settings 2>/dev/null) || return 1
    jq -er '.settings.proxy_port | select(type == "number" and . >= 1 and . <= 65535 and floor == .)' \
        <<< "$settings"
}

health_result() {
    local port="$1" response code=0
    response=$(timeout --kill-after=2s 35s "$HEALTH_BIN" warp health --port "$port" --json 2>/dev/null) || code=$?
    if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
        jq -nc '{status:"DEGRADED",reason:"Health check timed out",exitIp:"",colo:""}'
    elif [ "$code" -eq 0 ] || [ "$code" -eq 2 ] || [ "$code" -eq 3 ]; then
        if jq -e --argjson code "$code" 'type == "object" and
            (.status == "HEALTHY" and $code == 0 or
             .status == "DEGRADED" and $code == 2 or
             .status == "DOWN" and $code == 3) and (.reason | type == "string")' \
             <<< "$response" >/dev/null 2>&1; then
            jq -c '{status,reason,exitIp,colo}' <<< "$response"
        else
            jq -nc '{status:"DEGRADED",reason:"Invalid health API response",exitIp:"",colo:""}'
        fi
    else
        jq -nc '{status:"DEGRADED",reason:"Health API failed",exitIp:"",colo:""}'
    fi
}

recovery_action() {
    local port="$1" status settings
    [ ! -e "$MANUAL_STOP_FILE" ] || return 1
    # A failed unit is a confirmed crash; an inactive unit may be a manual stop.
    if systemctl is-failed --quiet warp-svc; then
        echo start
        timeout --kill-after=2s 10s systemctl start warp-svc >/dev/null 2>&1 || return 1
        return 0
    fi
    systemctl is-active --quiet warp-svc || return 1
    settings=$(timeout --kill-after=2s 8s warp-cli --accept-tos --json settings 2>/dev/null) || return 1
    jq -e --argjson port "$port" '.settings.operation_mode == "proxy" and
        .settings.proxy_port == $port and .settings.always_on == true' \
        <<< "$settings" >/dev/null 2>&1 || return 1
    status=$(timeout --kill-after=2s 8s warp-cli --accept-tos --json status 2>/dev/null) || return 1
    jq -e '.status == "Disconnected"' <<< "$status" >/dev/null 2>&1 || return 1
    echo connect
    timeout --kill-after=2s 10s warp-cli --accept-tos --json connect >/dev/null 2>&1 || return 1
}

incident_duration() {
    local started="$1" ended="$2"
    if [[ "$started" =~ ^[0-9]+$ ]] && [ "$ended" -gt "$started" ]; then
        echo "$((ended - started))"
    else
        echo null
    fi
}

close_incident() {
    local state="$1" stamp="$2" duration="$3"
    jq -c --arg time "$stamp" --argjson seconds "$duration" '
        .incidentOpen=false | .firstFailureEpoch=null | .incidentConfirmedEpoch=null |
        .lastRecovery=$time | .lastOutageSeconds=$seconds |
        .events=((.events + [{time:$time,type:"recovery",
            detail:(if $seconds == null then "outage duration unavailable"
                    else "outage " + ($seconds|tostring) + " seconds" end)}])[-50:])' <<< "$state"
}

watchdog_run() {
    local port result status reason ip colo old updated stamp epoch current_boot
    local old_boot marker_boot failures down_failures open incident_count last_attempt
    local action='' action_rc=0 attempt_result='' attempt_epoch recovered_epoch recovered_stamp
    local started duration
    need_root
    [ "${1:-}" = force ] || { enabled || return 0; }
    for dep in jq flock timeout; do command -v "$dep" >/dev/null 2>&1 || return 1; done
    ensure_dir
    exec 9>>"$LOCK_FILE"
    flock -n 9 || return 0  # Endpoint Manager or another check owns the lock.
    old=$(read_state)
    epoch=$(now_epoch); stamp=$(now_iso); current_boot=$(boot_id)
    old_boot=$(jq -r '.bootId // ""' <<< "$old")
    if [ -e "$MANUAL_STOP_FILE" ]; then
        marker_boot=$(cat "$MANUAL_STOP_FILE" 2>/dev/null || true)
        if { [ -n "$marker_boot" ] && [ "$marker_boot" != "$current_boot" ]; } ||
            { [ -z "$marker_boot" ] && [ -n "$old_boot" ] && [ "$old_boot" != "$current_boot" ]; } ||
            { [ -z "$marker_boot" ] && systemctl is-failed --quiet warp-svc; } ||
            systemctl is-active --quiet warp-svc; then
            rm -f -- "$MANUAL_STOP_FILE"
        fi
    fi
    if [ "$old_boot" != "$current_boot" ]; then
        old=$(jq -c '.consecutiveFailures=0 | .consecutiveDown=0 |
            if .incidentOpen then . else .firstFailureEpoch=null end' <<< "$old")
    fi
    if port=$(live_port); then
        result=$(health_result "$port")
    elif ! systemctl is-active --quiet warp-svc; then
        port=$(jq -r '.port // 40000' <<< "$old")
        result=$(health_result "$port")
    else
        result='{"status":"DEGRADED","reason":"Cannot determine live SOCKS5 port","exitIp":"","colo":""}'
    fi
    status=$(jq -r '.status' <<< "$result")
    reason=$(jq -r '.reason' <<< "$result" | cut -c 1-300)
    ip=$(jq -r '.exitIp // ""' <<< "$result" | cut -c 1-80)
    colo=$(jq -r '.colo // ""' <<< "$result" | cut -c 1-80)
    failures=$(jq -r '.consecutiveFailures' <<< "$old")
    down_failures=$(jq -r '.consecutiveDown // 0' <<< "$old")
    open=$(jq -r '.incidentOpen' <<< "$old")
    incident_count=$(jq -r '.incidentCount' <<< "$old")
    last_attempt=$(jq -r '.lastAttemptEpoch // 0' <<< "$old")
    if [ "$status" = HEALTHY ]; then
        if [ "$open" = true ]; then
            started=$(jq -r '.firstFailureEpoch // empty' <<< "$old")
            duration=$(incident_duration "$started" "$epoch")
            old=$(close_incident "$old" "$stamp" "$duration")
            if [ "$duration" = null ]; then
                log_event 'Recovered; outage duration unavailable'
            else
                log_event "Recovered after ${duration}s"
            fi
        else
            old=$(jq -c '.firstFailureEpoch=null | .incidentConfirmedEpoch=null' <<< "$old")
        fi
        failures=0; down_failures=0
    else
        if [ "$failures" -eq 0 ] && [ "$open" != true ]; then
            old=$(jq -c --argjson epoch "$epoch" '.firstFailureEpoch=$epoch' <<< "$old")
        fi
        failures=$((failures + 1))
        if [ "$status" = DOWN ]; then down_failures=$((down_failures + 1)); else down_failures=0; fi
        if [ "$failures" -ge 3 ] && [ "$open" != true ]; then
            incident_count=$((incident_count + 1))
            old=$(jq -c --arg time "$stamp" --arg reason "$reason" --argjson epoch "$epoch" \
                '.incidentOpen=true | .incidentConfirmedEpoch=$epoch |
                 .events=((.events + [{time:$time,type:"incident",detail:$reason}])[-50:])' <<< "$old")
            log_event "Incident $incident_count: $status: $reason"
        fi
    fi
    updated=$(jq -c --arg status "$status" --arg reason "$reason" --arg time "$stamp" \
        --arg boot "$current_boot" --arg ip "$ip" --arg colo "$colo" \
        --argjson port "${port:-null}" \
        --argjson failures "$failures" --argjson down "$down_failures" \
        --argjson incidents "$incident_count" \
        '.status=$status | .lastCheck=$time | .lastReason=$reason |
         .consecutiveFailures=$failures | .consecutiveDown=$down |
         .incidentCount=$incidents | .bootId=$boot | .port=$port |
         if $status == "HEALTHY" then .lastSuccess=$time | .exitIp=$ip | .colo=$colo
         else . end' <<< "$old")
    # Auto-recovery requires three confirmed DOWN checks and a 15-minute cooldown.
    if [ "$status" = DOWN ] && [ "$down_failures" -ge 3 ] && enabled && auto_recovery_enabled &&
        [ $((epoch - last_attempt)) -ge 900 ]; then
        if [ -n "${port:-}" ]; then
            action=$(recovery_action "$port") || action_rc=$?
        fi
        if [ -n "$action" ]; then
            attempt_epoch=$(now_epoch)
            updated=$(jq -c --argjson epoch "$attempt_epoch" '.lastAttemptEpoch=$epoch' <<< "$updated")
            if [ "$action_rc" -eq 0 ]; then
                attempt_result="$action succeeded"
                sleep 3
                port=$(live_port) || true
                if [ -n "$port" ]; then
                    result=$(health_result "$port")
                else
                    result='{"status":"DEGRADED","reason":"Cannot determine live SOCKS5 port after recovery","exitIp":"","colo":""}'
                fi
                if [ "$(jq -r '.status' <<< "$result")" = HEALTHY ]; then
                    recovered_epoch=$(now_epoch); recovered_stamp=$(now_iso)
                    started=$(jq -r '.firstFailureEpoch // empty' <<< "$updated")
                    duration=$(incident_duration "$started" "$recovered_epoch")
                    updated=$(close_incident "$updated" "$recovered_stamp" "$duration")
                    updated=$(jq -c --arg time "$recovered_stamp" --argjson port "$port" \
                        --arg ip "$(jq -r '.exitIp // ""' <<< "$result")" \
                        --arg colo "$(jq -r '.colo // ""' <<< "$result")" \
                        '.status="HEALTHY" | .lastCheck=$time | .lastSuccess=$time |
                         .lastReason="Recovered after action" | .consecutiveFailures=0 |
                         .consecutiveDown=0 | .port=$port | .exitIp=$ip | .colo=$colo' <<< "$updated")
                else
                    attempt_result="$action did not restore HEALTHY"
                fi
            else
                attempt_result="$action failed"
            fi
            updated=$(jq -c --arg time "$stamp" --arg result "$attempt_result" \
                '.lastAttemptResult=$result |
                 .events=((.events + [{time:$time,type:"action",detail:$result}])[-50:])' <<< "$updated")
            log_event "$attempt_result"
        fi
    fi
    printf '%s\n' "$updated" | write_state
}

case "${1:-}" in
    run) watchdog_run ;;
    check-now) watchdog_run force ;;
    enable) enable_watchdog ;;
    disable) disable_watchdog ;;
    remove) remove_watchdog ;;
    install-units) install_units ;;
    auto-on) auto_recovery_set true ;;
    auto-off) auto_recovery_set false ;;
    manual-stop) need_root; ensure_dir; boot_id > "$MANUAL_STOP_FILE"; chmod 600 "$MANUAL_STOP_FILE" ;;
    manual-start) need_root; rm -f -- "$MANUAL_STOP_FILE" ;;
    status) watchdog_status ;;
    summary) watchdog_summary ;;
    events) watchdog_events ;;
    *) echo 'Usage: warp_watchdog.sh {enable|disable|auto-on|auto-off|status|summary|events|run|check-now|remove}' >&2; exit 64 ;;
esac
