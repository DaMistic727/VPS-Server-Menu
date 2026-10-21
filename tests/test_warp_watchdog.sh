#!/bin/bash
set -euo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/units"
export WATCH_TEST_DIR="$work" WARP_WATCHDOG_STATE_DIR="$work/state" \
    WARP_WATCHDOG_UNIT_DIR="$work/units" WARP_LOCK_FILE="$work/warp.lock" \
    WARP_WATCHDOG_HEALTH_BIN="$work/bin/server-menu" WARP_WATCHDOG_BOOT_ID=boot-A
printf '%s\n' '{"timer":false,"service":true,"failed":false,"connected":true,"always_on":true,"port":40000,"listener":true,"trace":"on"}' > "$work/mock.json"
: > "$work/calls"
cat > "$work/bin/mock" <<'PY'
#!/usr/bin/env python3
import fcntl, json, os, pathlib, sys, time
root = pathlib.Path(os.environ['WATCH_TEST_DIR'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
state = root / 'mock.json'
s = json.loads(state.read_text())
with (root / 'calls').open('a') as f:
    f.write(json.dumps([name] + args) + '\n')
if name == 'id':
    print('0' if args == ['-u'] else 'root')
elif name == 'flock':
    try: fcntl.flock(int(args[-1]), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError: sys.exit(1)
elif name == 'timeout':
    if args[0].startswith('--kill-after='): args = args[1:]
    os.execvp(args[1], args[1:])
elif name == 'sleep':
    sys.exit(0)
elif name == 'logger':
    sys.exit(0)
elif name == 'systemctl':
    if args[:2] == ['is-enabled', '--quiet']:
        sys.exit(0 if s['timer'] else 1)
    if args[:2] == ['is-active', '--quiet']:
        sys.exit(0 if s['service'] else 1)
    if args[:2] == ['is-failed', '--quiet']:
        sys.exit(0 if s['failed'] else 1)
    if args[:2] == ['enable', '--now']:
        s['timer'] = True
    elif args[:2] == ['disable', '--now']:
        s['timer'] = False
    elif args[:2] == ['start', 'warp-svc']:
        s['service'] = True; s['failed'] = False; s['connected'] = True
    elif args[0] not in ('daemon-reload', 'stop'):
        sys.exit(99)
    state.write_text(json.dumps(s))
elif name == 'warp-cli':
    args = [a for a in args if a not in ('--accept-tos', '--json')]
    if args == ['settings']:
        if not s['service']: sys.exit(1)
        print(json.dumps({'settings': {'proxy_port':s['port'], 'operation_mode':'proxy', 'always_on':s['always_on']}}))
    elif args == ['status']:
        print(json.dumps({'status':'Connected' if s['connected'] else 'Disconnected'}))
    elif args == ['connect']:
        s['connected'] = True; state.write_text(json.dumps(s)); print('{}')
    else: sys.exit(99)
elif name == 'server-menu':
    assert args[:2] == ['warp','health'] and args[2:4] == ['--port', str(s['port'])]
    if s.get('health_delay'): time.sleep(s['health_delay'])
    if s.get('timeout'): sys.exit(124)
    if s.get('health_bad'): print('not JSON'); sys.exit(0)
    if not s['service'] or not s['connected'] or not s['listener']:
        status, reason, code = 'DOWN', 'confirmed WARP failure', 3
    elif s['trace'] == 'unavailable':
        status, reason, code = 'DEGRADED', 'trace unavailable', 2
    elif s['trace'] == 'off':
        status, reason, code = 'DEGRADED', 'warp=off', 2
    else:
        status, reason, code = 'HEALTHY', 'warp=on', 0
    print(json.dumps({'status':status, 'reason':reason, 'mode':'proxy',
                      'port':s['port'], 'endpoint':'AUTO', 'exitIp':'192.0.2.1', 'colo':'TEST'}))
    sys.exit(code)
else: sys.exit(99)
PY
chmod +x "$work/bin/mock"
for name in id flock timeout sleep logger systemctl warp-cli server-menu; do
    ln -s mock "$work/bin/$name"
done
export PATH="$work/bin:$PATH"
watchdog="$repo/warp_watchdog.sh"
set_mock() {
    python3 - "$work/mock.json" "$1" "$2" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); s=json.loads(p.read_text()); s[sys.argv[2]]=json.loads(sys.argv[3]); p.write_text(json.dumps(s))
PY
}
state() { jq -r "$1" "$work/state/state.json"; }
count_call() {
    python3 - "$work/calls" "$1" <<'PY'
import json, pathlib, sys
print(sum(1 for x in pathlib.Path(sys.argv[1]).read_text().splitlines() if json.loads(x)[0] == sys.argv[2]))
PY
}

"$watchdog" enable >/dev/null
"$watchdog" enable >/dev/null
test "$(jq -r .timer "$work/mock.json")" = true
test -f "$work/units/vps-warp-watchdog.timer"
test -f "$work/units/vps-warp-watchdog.service"
test "$(stat -f %Lp "$work/state/config.json" 2>/dev/null || stat -c %a "$work/state/config.json")" = 600
test "$(stat -f %Lp "$work/state" 2>/dev/null || stat -c %a "$work/state")" = 700
"$watchdog" run
test "$(state .status)" = HEALTHY
test "$(state .port)" = 40000
test "$(stat -f %Lp "$work/state/state.json" 2>/dev/null || stat -c %a "$work/state/state.json")" = 600
test "$(state .consecutiveFailures)" = 0
set_mock listener false
"$watchdog" run; test "$(state .consecutiveFailures)" = 1; test "$(state .incidentCount)" = 0
"$watchdog" run; test "$(state .consecutiveFailures)" = 2; test "$(state .incidentCount)" = 0
"$watchdog" run; test "$(state .consecutiveFailures)" = 3; test "$(state .incidentCount)" = 1
"$watchdog" run; test "$(state '.events | map(select(.type == "incident")) | length')" = 1
set_mock listener true
"$watchdog" run
test "$(state .status)" = HEALTHY
test "$(state .consecutiveFailures)" = 0
test "$(state .incidentOpen)" = false
test "$(state '.events | map(select(.type == "recovery")) | length')" = 1
test "$(state '.lastOutageSeconds >= 0')" = true

set_mock trace '"unavailable"'
"$watchdog" run
test "$(state .status)" = DEGRADED
set_mock trace '"off"'
"$watchdog" run
test "$(state .status)" = DEGRADED
set_mock timeout true
"$watchdog" run
test "$(state .status)" = DEGRADED
set_mock timeout false
set_mock health_bad true
"$watchdog" run
test "$(state .status)" = DEGRADED
set_mock health_bad false
set_mock trace '"on"'
set_mock service false
set_mock failed true
"$watchdog" run
test "$(state .status)" = DOWN
test "$(jq -r .service "$work/mock.json")" = false  # recovery is off
"$watchdog" auto-on
"$watchdog" run
"$watchdog" run
test "$(jq -r .service "$work/mock.json")" = true
test "$(state .status)" = HEALTHY
test "$(state .lastAttemptResult)" = 'start succeeded'

# A deliberate stop is DOWN through the existing API, but must never be restarted.
set_mock service false
set_mock failed false
"$watchdog" run
test "$(state .status)" = DOWN
test "$(jq -r .service "$work/mock.json")" = false
set_mock service true
"$watchdog" run

set_mock connected false
"$watchdog" run; "$watchdog" run; "$watchdog" run
test "$(jq -r .connected "$work/mock.json")" = false  # cooldown
jq '.lastAttemptEpoch=0' "$work/state/state.json" > "$work/updated.json"
mv "$work/updated.json" "$work/state/state.json"
"$watchdog" run
test "$(jq -r .connected "$work/mock.json")" = true
test "$(state .lastAttemptResult)" = 'connect succeeded'

set_mock port 45679
"$watchdog" run
test "$(state .status)" = HEALTHY
python3 - "$work/calls" <<'PY'
import json, pathlib, sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert any(x[0]=='server-menu' and x[2:4]==['health','--port'] and x[4]=='45679' for x in calls)
PY

"$watchdog" manual-stop
set_mock service false
set_mock failed true
jq '.lastAttemptEpoch=0' "$work/state/state.json" > "$work/updated.json"; mv "$work/updated.json" "$work/state/state.json"
"$watchdog" run; "$watchdog" run; "$watchdog" run
test "$(jq -r .service "$work/mock.json")" = false
"$watchdog" manual-start
set_mock service true
set_mock failed false
set_mock connected true
"$watchdog" run

# A new boot resets transient failure streaks while retaining totals.
set_mock listener false
"$watchdog" run; "$watchdog" run
export WARP_WATCHDOG_BOOT_ID=boot-B
"$watchdog" run
test "$(state .consecutiveFailures)" = 1
set_mock listener true
"$watchdog" run

# Both a concurrent runner and Endpoint Manager use the same lock.
exec 8>>"$WARP_LOCK_FILE"
python3 - "$WARP_LOCK_FILE" <<'PY'
import fcntl, os
fcntl.flock(8, fcntl.LOCK_EX | fcntl.LOCK_NB)
PY
last=$(state .lastCheck)
"$watchdog" run
test "$(state .lastCheck)" = "$last"
exec 8>&-

"$watchdog" disable >/dev/null
before=$(count_call server-menu)
"$watchdog" run
test "$(count_call server-menu)" = "$before"
"$watchdog" check-now
test "$(count_call server-menu)" -gt "$before"
printf 'keep\n' > "$work/state/unrelated"
"$watchdog" remove
test ! -e "$work/units/vps-warp-watchdog.timer"
test ! -e "$work/state/state.json"
test -f "$work/state/unrelated"
echo 'WARP Watchdog tests passed'
