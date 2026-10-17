#!/bin/bash
# Offline regression tests: all external WARP/network commands are mocked.
set -eu
project_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v jq >/dev/null || ! command -v python3 >/dev/null; then
    echo 'Need jq and python3'
    exit 1
fi
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir "$work/bin"
export WARP_TEST_DIR="$work" WARP_LOCK_FILE="$work/warp.lock"
cat > "$work/bin/mock" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, sys
root = pathlib.Path(os.environ['WARP_TEST_DIR'])
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
p = root / 'state.json'
s = json.loads(p.read_text())
with (root / 'calls.jsonl').open('a') as f:
    f.write(json.dumps([name] + args) + '\n')
if name == 'timeout':
    if args[0].startswith('--kill-after='):
        args = args[1:]
    os.execvp(args[1], args[1:])
if name == 'sleep':
    sys.exit(0)
if name == 'systemctl':
    sys.exit(int(s.get('service_down', False)))
if name == 'ss':
    if not s.get('no_listener'):
        print(f"LISTEN 0 1024 127.0.0.1:{s['settings']['proxy_port']} 0.0.0.0:*")
    sys.exit(0)
if name == 'curl':
    dead = s['settings'].get('override_warp_endpoint') == '198.51.100.1:9'
    if s.get('curl_fail'):
        sys.exit(7)
    print('warp=' + ('off' if dead or s.get('trace_off') else 'on'))
    print('ip=192.0.2.1\ncolo=TEST\nloc=ZZ')
    sys.exit(0)
if name != 'warp-cli':
    sys.exit(99)
if args == ['--version']:
    print(s.get('version', 'warp-cli 2026.8.2110.0'))
    sys.exit(0)
args = [a for a in args if a not in ('--accept-tos', '--json')]
if '--help' in args:
    sys.exit(1 if s.get('no_capabilities') else 0)
cfg = s['settings']
if args == ['tunnel', 'stats']:
    if s.get('no_stats'):
        sys.exit(1)
    print(json.dumps({'protocol': s.get('transport', 'MASQUE (HTTPS via UDP)'),
                     'tls': {'sni': 'consumer-masque-proxy.cloudflareclient.com'}}))
    sys.exit(0)
if args == ['settings']:
    print(json.dumps({'settings': {} if s.get('unknown_schema') else cfg}))
    sys.exit(0)
if args == ['status']:
    print(json.dumps({'status': 'Connected' if cfg['always_on'] else 'Disconnected'}))
    sys.exit(0)
if args[:3] == ['tunnel', 'endpoint', 'set'] and s.pop('fail_set_once', False):
    p.write_text(json.dumps(s))
    print('simulated set failure', file=sys.stderr)
    sys.exit(1)
if args == ['disconnect']:
    cfg['always_on'] = False
elif args == ['connect']:
    cfg['always_on'] = True
elif args[:1] == ['mode']:
    cfg['operation_mode'] = args[1]
elif args[:2] == ['proxy', 'port']:
    cfg['proxy_port'] = int(args[2])
elif args[:3] == ['tunnel', 'protocol', 'set']:
    cfg['warp_tunnel_protocol'] = args[3].lower()
elif args[:3] == ['tunnel', 'endpoint', 'set']:
    if not s.get('ignore_set'):
        cfg['override_warp_endpoint'] = args[3]
elif args == ['tunnel', 'endpoint', 'reset']:
    cfg.pop('override_warp_endpoint', None)
else:
    print('unhandled mock CLI command', args, file=sys.stderr)
    sys.exit(99)
p.write_text(json.dumps(s))
print(json.dumps({'status': 'Success'}))
PY
chmod +x "$work/bin/mock"
for name in warp-cli systemctl timeout ss curl sleep; do ln -s mock "$work/bin/$name"; done
export PATH="$work/bin:$PATH"
# Functions and globals are loaded from the canonical script without starting its menu.
# shellcheck disable=SC1091
source "$project_dir/menu_warp.sh"
export RED='' GREEN='' YELLOW='' CYAN='' BLUE='' NC=''
warp_health=''
warp_scan_sni=''
warp_endpoint=''
command() {
    if [ "${1:-}" = -v ] && [ "${2:-}" = "${WARP_MISSING:-}" ]; then return 1; fi
    builtin command "$@"
}
reset_state() {
    printf '%s\n' '{"settings":{"operation_mode":"proxy","proxy_port":45678,"always_on":true,"warp_tunnel_protocol":"masque","masque_http_version":"MASQUE (HTTP/2)"}}' > "$work/state.json"
    : > "$work/calls.jsonl"
}
flag() {
    python3 - "$work/state.json" "$1" "$2" <<'PY'
import json, pathlib, sys
p=pathlib.Path(sys.argv[1]); s=json.loads(p.read_text()); s[sys.argv[2]]=json.loads(sys.argv[3]); p.write_text(json.dumps(s))
PY
}
settings() { jq -Sc '.settings' "$work/state.json"; }
assert_health() {
    check_warp_health quiet || true
    test "$warp_health" = "$1" || { echo "Expected health $1, got $warp_health"; exit 1; }
}
reset_state
assert_health HEALTHY
WARP_MISSING=curl assert_health DEGRADED
WARP_MISSING=warp-cli assert_health DOWN
WARP_MISSING=jq assert_health DEGRADED
saved=$(settings)
if WARP_MISSING=curl apply_warp_change endpoint '192.0.2.1:443'; then exit 1; fi
test "$saved" = "$(settings)"
get_warp_scan_profile
test "$warp_scan_sni" = consumer-masque-proxy.cloudflareclient.com
flag transport '"MASQUE (HTTPS via TCP)"'
if get_warp_scan_profile; then echo 'Unknown transport accepted'; exit 1; fi
flag no_stats true
get_warp_scan_profile
flag version '"warp-cli unknown-version"'
if get_warp_scan_profile; then echo 'Unknown transport/version fallback accepted'; exit 1; fi
read_warp_state
test "$warp_endpoint" = UNKNOWN
saved=$(settings)
if apply_warp_change endpoint '192.0.2.1:443'; then echo 'Unknown AUTO state mutated'; exit 1; fi
test "$saved" = "$(settings)"
for pair in 'service_down DOWN' 'no_listener DOWN' 'curl_fail DEGRADED' 'trace_off DEGRADED' 'unknown_schema DEGRADED'; do
    reset_state
    read -r setting expected <<< "$pair"
    flag "$setting" true
    assert_health "$expected"
done
for endpoint in '192.0.2.1:443' '[2001:db8::1]:1701' '[::ffff:192.0.2.1]:443'; do validate_warp_endpoint "$endpoint"; done
test "$(normalize_warp_endpoint '[2001:0DB8::1]:00443')" = '[2001:db8::1]:443'
for endpoint in '1.2.3.999:443' 'example.com:443' '[1.2.3.4]:443' '::1:443' '[:::1]:443' '1.2.3.4:0' '1.2.3.4:65536' '1.2.3.4:443;id' '1.2.3.4:٤٤٣' $'1.2.3.4:443\n127.0.0.1:22'; do
    if validate_warp_endpoint "$endpoint"; then echo 'Invalid endpoint accepted'; exit 1; fi
done
reset_state
apply_warp_change endpoint '[2001:0DB8::1]:00443'
test "$(jq -r '.settings.override_warp_endpoint' "$work/state.json")" = '[2001:db8::1]:443'
apply_warp_change endpoint AUTO
apply_warp_change endpoint '192.0.2.1:443'
test "$(jq -r '.settings.override_warp_endpoint' "$work/state.json")" = '192.0.2.1:443'
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45678
saved=$(settings)
if apply_warp_change endpoint '198.51.100.1:9'; then echo 'Dead endpoint accepted'; exit 1; fi
test "$saved" = "$(settings)"
flag fail_set_once true
if apply_warp_change endpoint '192.0.2.2:443'; then echo 'Set failure accepted'; exit 1; fi
test "$saved" = "$(settings)"
flag ignore_set true
if apply_warp_change endpoint '192.0.2.2:443'; then echo 'Ignored set accepted'; exit 1; fi
test "$saved" = "$(settings)"
flag ignore_set false
apply_warp_change endpoint AUTO
test "$(jq -r '.settings | has("override_warp_endpoint")' "$work/state.json")" = false
apply_warp_change port 45679
test "$(jq -r '.settings.proxy_port' "$work/state.json")" = 45679
saved=$(settings)
if apply_warp_change protocol wireguard; then echo 'WireGuard allowed in proxy'; exit 1; fi
test "$saved" = "$(settings)"
reset_state
warp_cli disconnect >/dev/null
saved=$(settings)
if apply_warp_change endpoint '198.51.100.1:9'; then exit 1; fi
test "$saved" = "$(settings)"
reset_state
flag unknown_schema true
saved=$(settings)
if apply_warp_change endpoint '192.0.2.1:443'; then echo 'Unknown state mutated'; exit 1; fi
test "$saved" = "$(settings)"
reset_state
flag no_capabilities true
if apply_warp_change endpoint '192.0.2.1:443'; then echo 'Unknown CLI mutated'; exit 1; fi
python3 - "$work/calls.jsonl" <<'PY'
import json,pathlib,sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert not any(c[0]=='warp-cli' and '--help' not in c and 'endpoint' in c and 'set' in c for c in calls)
PY
reset_state
assert_health HEALTHY
python3 - "$work/calls.jsonl" <<'PY'
import json,pathlib,sys
calls=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines()]
c=next(c for c in calls if c[0]=='curl')
assert c[1]=='--disable' and c[c.index('--noproxy')+1]==''
assert c[c.index('--proxy')+1]=='socks5h://127.0.0.1:45678'
assert '--connect-timeout' in c and '--max-time' in c
PY
echo 'PASS: health layers, endpoint validation, apply, readback, port preservation, rollback (AUTO/custom/disconnected), unknown schema/CLI, protocol isolation, SOCKS DNS/timeouts.'
