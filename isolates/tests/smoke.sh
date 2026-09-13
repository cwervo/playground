#!/bin/sh
# smoke.sh - end-to-end test of the HTTP server and control API.
# usage: sh tests/smoke.sh ./bin/isolates
set -eu
BIN=${1:-./bin/isolates}
PORT=${PORT:-18787}
BASE="http://127.0.0.1:$PORT"
TMP=$(mktemp -d)
trap 'kill $PID 2>/dev/null; rm -rf "$TMP"' EXIT

"$BIN" serve --port "$PORT" --data "$TMP/data" --examples workers \
    --load workers/hello.isoasm --load workers/counter.isoasm \
    --load workers/cpu-hog.isoasm >"$TMP/server.log" 2>&1 &
PID=$!
for i in 1 2 3 4 5 6 7 8 9 10; do
    curl -s "$BASE/api/status" >/dev/null 2>&1 && break
    sleep 0.2
done

fail() { echo "SMOKE FAIL: $*" >&2; cat "$TMP/server.log" >&2; exit 1; }
expect() { # expect <description> <needle> <haystack>
    case "$3" in *"$2"*) ;; *) fail "$1: expected '$2' in: $3" ;; esac
}

echo "status"
expect status '"version":"' "$(curl -s "$BASE/api/status")"
expect status-isolates '"isolates":3' "$(curl -s "$BASE/api/status")"

echo "worker by path prefix"
expect hello 'hello from worker hello on /there' "$(curl -s "$BASE/w/hello/there")"
expect hello-headers 'X-Isolate-Worker: hello' "$(curl -si "$BASE/w/hello")"

echo "worker by host header"
expect host 'hello from worker hello on /' "$(curl -s -H 'Host: hello.workers.local' "$BASE/")"

echo "unknown route"
expect unknown 'Error 1003' "$(curl -s "$BASE/w/nope")"
expect unknown-status '404' "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/w/nope")"

echo "kv persists across requests"
curl -s "$BASE/w/counter" >/dev/null
expect counter 'hit 2 times' "$(curl -s "$BASE/w/counter")"
expect kv-list '"key":"hits","value":"2"' "$(curl -s "$BASE/api/workers/counter/kv")"
expect kv-put '"ok":true' "$(curl -s -X PUT --data-binary 41 "$BASE/api/workers/counter/kv/hits")"
expect counter-after-put 'hit 42 times' "$(curl -s "$BASE/w/counter")"

echo "resource limits map to 503 / 500"
expect cpu-limit 'Error 1102' "$(curl -s "$BASE/w/cpu-hog/forever")"
expect cpu-status '503' "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/w/cpu-hog/forever")"
expect trap-status '500' "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/w/cpu-hog/trap")"
expect logs '"msg":"error 1102' "$(curl -s "$BASE/api/workers/cpu-hog/logs")"

echo "deploy via API"
DEPLOY='{"script":"push \"content-type\"\npush \"application/json\"\nres.header\npush \"{\\\"ok\\\":true,\\\"who\\\":\\\"\"\npush \"WHO\"\nenv\nconcat\npush \"\\\"}\"\nconcat\nres.body\nhalt\n","cpu_limit":5000,"env":{"WHO":"api"}}'
expect deploy-created '"name":"deployed"' "$(curl -s -X PUT -H 'Content-Type: application/json' --data-binary "$DEPLOY" "$BASE/api/workers/deployed")"
expect deploy-status '201' "$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data-binary "$DEPLOY" "$BASE/api/workers/deployed2")"
expect deploy-run '{"ok":true,"who":"api"}' "$(curl -s "$BASE/w/deployed/")"
expect deploy-limit '"cpu_limit":5000' "$(curl -s "$BASE/api/workers/deployed")"
expect deploy-persisted 'push "WHO"' "$(cat "$TMP/data/deployed.isoasm")"
expect deploy-meta '"WHO":"api"' "$(cat "$TMP/data/deployed.meta.json")"

echo "assemble errors are 422"
expect asm-error 'unknown instruction' "$(curl -s -X PUT --data-binary '{"script":"frobnicate"}' "$BASE/api/workers/bad")"
expect asm-status '422' "$(curl -s -o /dev/null -w '%{http_code}' -X PUT --data-binary '{"script":"frobnicate"}' "$BASE/api/workers/bad")"
expect asm-check '"ok":false' "$(curl -s -X POST --data-binary '{"script":"jmp nowhere"}' "$BASE/api/assemble")"
expect asm-ok '"ok":true' "$(curl -s -X POST --data-binary '{"script":"halt"}' "$BASE/api/assemble")"

echo "invoke API"
INV=$(curl -s -X POST --data-binary '{"method":"post","path":"/x?y=1","headers":{"X-Test":"1"},"body":"hi"}' "$BASE/api/workers/hello/invoke")
expect invoke-body 'hello from worker hello on /x' "$INV"
expect invoke-metrics '"instructions":' "$INV"
expect invoke-error '"error_code":1102' "$(curl -s -X POST --data-binary '{"path":"/forever"}' "$BASE/api/workers/cpu-hog/invoke")"

echo "listing, reference, examples, disasm"
expect list '"name":"counter"' "$(curl -s "$BASE/api/workers")"
expect reference '"name":"kv.put"' "$(curl -s "$BASE/api/reference")"
expect examples '"name":"router"' "$(curl -s "$BASE/api/examples")"
expect disasm '"text":"halt"' "$(curl -s "$BASE/api/workers/hello/disasm")"

echo "cors preflight"
expect cors 'Access-Control-Allow-Origin: *' "$(curl -si -X OPTIONS "$BASE/api/workers")"

echo "delete"
expect delete '"ok":true' "$(curl -s -X DELETE "$BASE/api/workers/deployed2")"
expect deleted '404' "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/workers/deployed2")"
[ ! -f "$TMP/data/deployed2.isoasm" ] || fail "script file not removed"

echo "concurrent long requests interleave"
CURLS=""
for i in 1 2 3 4 5 6 7 8; do
    curl -s "$BASE/w/cpu-hog/" >"$TMP/c$i" &
    CURLS="$CURLS $!"
done
wait $CURLS
for i in 1 2 3 4 5 6 7 8; do
    expect "concurrent $i" 'did 50000 instructions' "$(cat "$TMP/c$i")"
done
expect switches '"context_switches":' "$(curl -s "$BASE/api/status")"

echo "restart reloads persisted workers"
kill $PID; wait $PID 2>/dev/null || true
"$BIN" serve --port "$PORT" --data "$TMP/data" >"$TMP/server2.log" 2>&1 &
PID=$!
for i in 1 2 3 4 5 6 7 8 9 10; do
    curl -s "$BASE/api/status" >/dev/null 2>&1 && break
    sleep 0.2
done
expect reload '{"ok":true,"who":"api"}' "$(curl -s "$BASE/w/deployed/")"
expect reload-limits '"cpu_limit":5000' "$(curl -s "$BASE/api/workers/deployed")"

echo "smoke: all checks passed"
