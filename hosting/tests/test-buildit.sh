#!/usr/bin/env bash
# Tests buildit/server.js sandbox mode (the hosted copy) plus the static-file guard in both modes.
# Needs node and curl. Starts throwaway servers on local ports; no Juice Shop needed.
set -Euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
command -v node >/dev/null 2>&1 || { echo "SKIP: node not available"; exit 0; }

fails=0
check() { if [[ "$2" == *"$3"* ]]; then echo "ok   $1"; else echo "FAIL $1 (expected to contain: $3; got: ${2:0:200})"; fails=$((fails + 1)); fi; }
tmp=$(mktemp -d); pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done; rm -rf "$tmp"; }
trap cleanup EXIT

start() {  # start PORT [ENV=VAL...] : run server in background, wait until it answers
  local port=$1; shift
  env PORT="$port" "$@" node "$REPO/buildit/server.js" >"$tmp/server-$port.log" 2>&1 &
  pids+=($!)
  for _ in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$port/api/vulns" && return 0; sleep 0.1; done
  echo "server on $port did not start"; cat "$tmp/server-$port.log"; exit 1
}

S=http://127.0.0.1:31871
start 31871 BUILDIT_MODE=sandbox JUICE_SHOP_URL=http://203.0.113.7 JUICE_ROOT=/nonexistent
A=(-s -b "$tmp/a.jar" -c "$tmp/a.jar"); B=(-s -b "$tmp/b.jar" -c "$tmp/b.jar")
post() { curl -X POST "$@" -H 'Content-Type: application/json'; }

check "list has 6 vulns"                    "$(curl -s $S/api/vulns | grep -o '"id"' | wc -l | tr -d ' ')" "6"
check "fresh visitor sees vulnerable code"  "$(curl "${A[@]}" $S/api/vulns/sqli)" '"isVulnerable":true'
check "save stores visitor A's edit"        "$(post "${A[@]}" -d '{"code":"MY FIX"}' $S/api/vulns/sqli/save)" '"status":"saved"'
check "A sees own edit, patched"            "$(curl "${A[@]}" $S/api/vulns/sqli)" '"isVulnerable":false'
check "A's current code is the edit"        "$(curl "${A[@]}" $S/api/vulns/sqli)" '"currentCode":"MY FIX"'
check "visitor B is unaffected"             "$(curl "${B[@]}" $S/api/vulns/sqli)" '"isVulnerable":true'
check "second save needs reset first"       "$(post "${A[@]}" -d '{"code":"OTHER"}' $S/api/vulns/sqli/save)" '"status":"already_fixed"'
check "reset works with a NON-model fix"    "$(post "${A[@]}" $S/api/vulns/sqli/reset)" '"status":"reset"'
check "after reset A is vulnerable again"   "$(curl "${A[@]}" $S/api/vulns/sqli)" '"isVulnerable":true'
check "reset twice is harmless"             "$(post "${A[@]}" $S/api/vulns/sqli/reset)" '"status":"already_vulnerable"'
check "model fix also counts as patched"    "$(post "${A[@]}" -d "$(node -e "process.stdout.write(JSON.stringify({code:'x'}))")" $S/api/vulns/jwt/save)" '"status":"saved"'
check "read-only entry rejects save"        "$(post "${A[@]}" -d '{"code":"x"}' $S/api/vulns/xss/save)" 'read-only'
big=$(head -c 70000 /dev/zero | tr '\0' 'a')
check "oversized body rejected"             "$(printf '{"code":"%s"}' "$big" | post "${A[@]}" --data-binary @- $S/api/vulns/idor/save)" 'too large'
check "unknown vuln 404"                    "$(curl -s -o /dev/null -w '%{http_code}' $S/api/vulns/nope)" '404'
check "disk never touched (no JUICE_ROOT)"  "$(cat "$tmp/server-31871.log")" 'Mode: sandbox'
check "index served"                        "$(curl -s $S/)" 'Build-It'
check "Juice Shop link rewritten"           "$(curl -s $S/)" 'href="http://203.0.113.7"'
check "logo served"                         "$(curl -s -o /dev/null -w '%{http_code}' $S/logos/issessions.png)" '200'
check "path traversal blocked (sandbox)"    "$(curl -s --path-as-is -o /dev/null -w '%{http_code}' $S/../server.js)" '404'

L=http://127.0.0.1:31872
start 31872 JUICE_ROOT=/nonexistent
check "path traversal blocked (live mode)"  "$(curl -s --path-as-is -o /dev/null -w '%{http_code}' $L/../server.js)" '404'
check "live mode still reads from disk"     "$(curl -s $L/api/vulns/sqli)" 'Cannot read'

(( fails == 0 )) || { echo "$fails buildit test(s) failed"; exit 1; }
echo "all buildit tests passed"
