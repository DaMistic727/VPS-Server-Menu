#!/bin/bash
# Watchdog removal must work even when its command symlink is gone.
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/mock-bin"
cat > "$work/mock-bin/systemctl" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['WATCH_UNINSTALL_CASE'])
p = root / 'mock.json'
s = json.loads(p.read_text())
a = sys.argv[1:]
if a[:2] == ['is-enabled', '--quiet']:
    sys.exit(0 if s['enabled'] else 1)
if a[:2] == ['is-active', '--quiet']:
    active = s['timer_active'] if a[-1].endswith('.timer') else s['service_active']
    sys.exit(0 if active else 1)
if a[:2] == ['disable', '--now']:
    if s.get('disable_fail'): sys.exit(1)
    s['enabled'] = False
    if s.get('disable_timer_stop_fail'):
        p.write_text(json.dumps(s))
        sys.exit(1)
    s['timer_active'] = False
    (root / 'units/timers.target.wants/vps-warp-watchdog.timer').unlink(missing_ok=True)
elif a[0] == 'stop':
    if a[-1].endswith('.timer'):
        if s.get('stop_timer_fail'): sys.exit(1)
        s['timer_active'] = False
    else:
        if s.get('stop_service_fail'): sys.exit(1)
        s['service_active'] = False
elif a != ['daemon-reload']:
    sys.exit(99)
p.write_text(json.dumps(s))
PY
chmod +x "$work/mock-bin/systemctl"
cat > "$work/mock-bin/id" <<'SH'
#!/bin/sh
[ "$1" = -u ] && echo 0
SH
chmod +x "$work/mock-bin/id"
export PATH="$work/mock-bin:$PATH"

prepare_case() {
    case_dir="$work/$1"
    mkdir -p "$case_dir/bin" "$case_dir/units/timers.target.wants" "$case_dir/state"
    printf '%s\n' '{"enabled":true,"timer_active":true,"service_active":false}' > "$case_dir/mock.json"
    : > "$case_dir/units/vps-warp-watchdog.timer"
    : > "$case_dir/units/vps-warp-watchdog.service"
    ln -s ../vps-warp-watchdog.timer "$case_dir/units/timers.target.wants/vps-warp-watchdog.timer"
    : > "$case_dir/state/state.json"
    : > "$case_dir/state/config.json"
    : > "$case_dir/state/manual-stop"
    : > "$case_dir/state/unrelated"
    export WATCH_UNINSTALL_CASE="$case_dir" VPS_MENU_BIN_DIR="$case_dir/bin" \
        VPS_MENU_TARGET_DIR="$case_dir/absent-repo" VPS_MENU_BASHRC_FILE="$case_dir/absent-bashrc" \
        WARP_WATCHDOG_UNIT_DIR="$case_dir/units" WARP_WATCHDOG_STATE_DIR="$case_dir/state"
}

assert_removed() {
    test ! -e "$case_dir/units/vps-warp-watchdog.timer"
    test ! -e "$case_dir/units/vps-warp-watchdog.service"
    test ! -L "$case_dir/units/timers.target.wants/vps-warp-watchdog.timer"
    test ! -L "$case_dir/bin/warp_watchdog.sh"
    test ! -e "$case_dir/state/state.json"
    test ! -e "$case_dir/state/config.json"
    test ! -e "$case_dir/state/manual-stop"
    test -e "$case_dir/state/unrelated"
    jq -e '.enabled == false and .timer_active == false and .service_active == false' "$case_dir/mock.json" >/dev/null
}

assert_preserved() {
    test -e "$case_dir/units/vps-warp-watchdog.timer"
    test -e "$case_dir/units/vps-warp-watchdog.service"
    test -L "$case_dir/bin/warp_watchdog.sh"
    test -e "$case_dir/state/state.json"
    test -e "$case_dir/state/config.json"
    test -e "$case_dir/state/manual-stop"
}

set_case_flag() {
    jq --arg key "$1" --argjson value "$2" '.[$key]=$value' "$case_dir/mock.json" > "$case_dir/updated.json"
    mv "$case_dir/updated.json" "$case_dir/mock.json"
}

prepare_case missing
bash "$repo/uninstall.sh" > "$case_dir/output" 2>&1
assert_removed

prepare_case broken
ln -s "$case_dir/missing-target" "$case_dir/bin/warp_watchdog.sh"
bash "$repo/uninstall.sh" > "$case_dir/output" 2>&1
assert_removed

# An intact source checkout remains a usable removal path when the bin link is absent.
prepare_case source
mkdir -p "$case_dir/absent-repo"
ln -s "$repo/warp_watchdog.sh" "$case_dir/absent-repo/warp_watchdog.sh"
printf 'n\n' | bash "$repo/uninstall.sh" > "$case_dir/output" 2>&1
assert_removed

# If the timer cannot be disabled, uninstall must stop before deleting files.
prepare_case disable-fails
set_case_flag disable_fail true
if bash "$repo/uninstall.sh" > "$case_dir/output" 2>&1; then
    echo 'Uninstall accepted an enabled timer' >&2
    exit 1
fi
test -e "$case_dir/units/vps-warp-watchdog.timer"

# Exercise the executable-script path used by a normal Server Menu install.
prepare_case active-service
ln -s "$repo/warp_watchdog.sh" "$case_dir/bin/warp_watchdog.sh"
set_case_flag service_active true
set_case_flag stop_service_fail true
if bash "$repo/uninstall.sh" > "$case_dir/output" 2>&1; then
    echo 'Uninstall removed an active Watchdog service' >&2
    exit 1
fi
assert_preserved
jq -e '.service_active == true' "$case_dir/mock.json" >/dev/null

prepare_case active-timer
ln -s "$repo/warp_watchdog.sh" "$case_dir/bin/warp_watchdog.sh"
set_case_flag disable_timer_stop_fail true
if bash "$repo/uninstall.sh" > "$case_dir/output" 2>&1; then
    echo 'Uninstall removed an active Watchdog timer' >&2
    exit 1
fi
assert_preserved
jq -e '.timer_active == true' "$case_dir/mock.json" >/dev/null

prepare_case inactive-absent
ln -s "$repo/warp_watchdog.sh" "$case_dir/bin/warp_watchdog.sh"
rm -f "$case_dir/units/vps-warp-watchdog.timer" "$case_dir/units/vps-warp-watchdog.service" \
    "$case_dir/units/timers.target.wants/vps-warp-watchdog.timer"
set_case_flag enabled false
set_case_flag timer_active false
bash "$repo/uninstall.sh" > "$case_dir/output" 2>&1
assert_removed
echo 'Watchdog uninstall tests passed'
