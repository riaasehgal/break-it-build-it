#!/usr/bin/env bash
# Post-deploy checks against a live deployment:
#  1. a team can be created, becomes ready, and its Juice Shop answers through the balancer
#  2. from INSIDE that Juice Shop pod: metadata server, kube API and internet are unreachable;
#     the balancer webhook is reachable (proves DNS + the allowed path work)
#  3. a pod without balancer labels cannot reach the Juice Shop (ingress isolation)
#  4. the test team is deleted again via the admin API
#   hosting/verify.sh --project ID
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

PROJECT=""
while (( $# )); do
  case $1 in
    --project) PROJECT=${2:-}; shift 2 ;;
    -h|--help) echo "Usage: verify.sh --project ID"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ -n $PROJECT ]] || die "--project is required"
GEN=$(project_gen_dir "$PROJECT")
[[ -f $GEN/deploy-info.env ]] || die "no $GEN/deploy-info.env; run deploy.sh first"
# shellcheck disable=SC1091
source "$GEN/deploy-info.env"
use_project_kubeconfig "$PROJECT"
ADMIN_PASSWORD=$(sed -n 's/^adminPassword: "\(.*\)"$/\1/p' "$GEN/secret-values.yaml")

TEAM="verify-$(date +%H%M%S)"
JAR=$(mktemp); ADMIN_JAR=$(mktemp)
trap 'rm -f "$JAR" "$ADMIN_JAR"' EXIT
failures=0
pass() { log "PASS: $*"; }
fail() { log "FAIL: $*"; failures=$((failures + 1)); }

# TCP-level probe run with Juice Shop's own node binary. Prints REACHABLE or BLOCKED <reason>.
# A NetworkPolicy drop shows up as a timeout; ECONNREFUSED means packets got through.
PROBE_JS='const [h,p]=process.argv.slice(1);const s=require("net").connect({host:h,port:+p,timeout:3000});
s.on("connect",()=>{console.log("REACHABLE");s.destroy()});
s.on("timeout",()=>{console.log("BLOCKED timeout");s.destroy()});
s.on("error",e=>console.log(e.code==="ECONNREFUSED"?"REACHABLE refused":"BLOCKED "+e.code));'

# 1. create + time-to-ready + proxy
t0=$(date +%s%N)
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -c "$JAR" -H 'Content-Type: application/json' \
  -d '{}' -X POST "$URL/multi-juicer/api/teams/$TEAM/join" || echo 000)
if [[ $code == 200 ]]; then pass "team $TEAM created"; else fail "team create returned HTTP $code"; fi
ready=0
for _ in $(seq 1 120); do
  body=$(curl -s --max-time 10 -b "$JAR" "$URL/multi-juicer/api/teams/$TEAM/status" || true)
  if [[ $body == *'"readiness":true'* ]]; then ready=1; break; fi
  sleep 1
done
ms=$(( ($(date +%s%N) - t0) / 1000000 ))
if (( ready )); then pass "instance ready in ${ms} ms"; else fail "instance not ready after ${ms} ms"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -b "$JAR" "$URL/rest/admin/application-version" || echo 000)
if [[ $code == 200 ]]; then pass "Juice Shop answers through the balancer"; else fail "proxied Juice Shop request returned HTTP $code"; fi

# 2. egress from inside the Juice Shop pod
probe_from_juice() {
  no_pathconv kubectl -n "$NAMESPACE" exec "deploy/juiceshop-$TEAM" -c juice-shop -- \
    /nodejs/bin/node -e "$PROBE_JS" "$1" "$2" 2>/dev/null || echo "EXEC-FAILED"
}
expect_blocked() {
  local r; r=$(probe_from_juice "$1" "$2")
  # A DNS failure also "blocks" the connection, but it means cluster DNS is broken for Juice Shop pods
  # (which also breaks the solve webhook), so it must not count as a pass.
  if [[ $r == *EAI_AGAIN* || $r == *ENOTFOUND* ]]; then fail "juice pod cannot resolve $1 ($r): DNS egress is broken"; return; fi
  if [[ $r == BLOCKED* ]]; then pass "juice pod -> $1:$2 blocked ($r)"; else fail "juice pod -> $1:$2 expected BLOCKED, got: $r"; fi
}
if (( ready )); then
  expect_blocked 169.254.169.254 80          # GCE metadata server
  expect_blocked 169.254.169.252 988         # GKE metadata server
  expect_blocked kubernetes.default.svc 443  # kube API
  expect_blocked 8.8.8.8 443                 # internet by IP
  expect_blocked example.com 443             # internet by name (DNS allowed, TCP not)
  r=$(probe_from_juice multijuicer-private 80)
  if [[ $r == REACHABLE* ]]; then pass "juice pod -> balancer webhook reachable"; else fail "juice pod -> multijuicer-private:80 expected REACHABLE, got: $r (solve notifications would break)"; fi
fi

# 3. ingress: an unlabelled pod must not reach the Juice Shop directly
if (( ready )); then
  r=$(no_pathconv kubectl -n "$NAMESPACE" run "probe-$TEAM" --image="$JUICE_IMAGE" --restart=Never --rm -i --quiet \
        --command -- /nodejs/bin/node -e "$PROBE_JS" "juiceshop-$TEAM" 3000 2>/dev/null || echo "RUN-FAILED")
  if [[ $r == *BLOCKED* ]]; then pass "unlabelled pod -> juice shop blocked"; else fail "unlabelled pod -> juiceshop-$TEAM:3000 expected BLOCKED, got: $r"; fi
fi

# 3b. hosted Build-It (only if deployed with --with-buildit)
if [[ -n ${BUILDIT_URL:-} ]]; then
  BA=$(mktemp); BB=$(mktemp)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$BUILDIT_URL/api/vulns" || echo 000)
  if [[ $code == 200 ]]; then pass "Build-It answers at $BUILDIT_URL"; else fail "Build-It /api/vulns returned HTTP $code"; fi
  curl -s -o /dev/null --max-time 10 -b "$BA" -c "$BA" -X POST -H 'Content-Type: application/json' \
    -d '{"code":"verify-edit"}' "$BUILDIT_URL/api/vulns/sqli/save" || true
  a=$(curl -s --max-time 10 -b "$BA" -c "$BA" "$BUILDIT_URL/api/vulns/sqli" || true)
  b=$(curl -s --max-time 10 -b "$BB" -c "$BB" "$BUILDIT_URL/api/vulns/sqli" || true)
  if [[ $a == *'"isVulnerable":false'* && $b == *'"isVulnerable":true'* ]]; then
    pass "Build-It practice copies are per visitor"
  else
    fail "Build-It sandbox isolation (visitor A: ${a:0:80} / visitor B: ${b:0:80})"
  fi
  r=$(curl -s --max-time 10 -b "$BA" -c "$BA" -X POST -H 'Content-Type: application/json' "$BUILDIT_URL/api/vulns/sqli/reset" || true)
  if [[ $r == *'"status":"reset"'* ]]; then pass "Build-It reset restores the original"; else fail "Build-It reset: ${r:0:120}"; fi
  rm -f "$BA" "$BB"
  code=$(curl -s --path-as-is -o /dev/null -w '%{http_code}' --max-time 10 "$BUILDIT_URL/../server.js" || echo 000)
  if [[ $code == 404 ]]; then pass "Build-It blocks path traversal"; else fail "Build-It /../server.js returned HTTP $code"; fi
  r=$(no_pathconv kubectl -n "$NAMESPACE" exec deploy/buildit -- node -e "$PROBE_JS" 8.8.8.8 443 2>/dev/null || echo "EXEC-FAILED")
  if [[ $r == BLOCKED* ]]; then pass "Build-It pod -> internet blocked ($r)"; else fail "Build-It pod -> 8.8.8.8:443 expected BLOCKED, got: $r"; fi
fi

# 4. cleanup via admin API
curl -s -o /dev/null --max-time 10 -c "$ADMIN_JAR" -H 'Content-Type: application/json' \
  -d "{\"passcode\":\"$ADMIN_PASSWORD\"}" -X POST "$URL/multi-juicer/api/teams/admin/join" || true
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -b "$ADMIN_JAR" -X DELETE \
  "$URL/multi-juicer/api/admin/teams/$TEAM/delete" || echo 000)
if [[ $code == 200 ]]; then pass "admin login + delete of $TEAM"; else fail "admin delete returned HTTP $code"; fi

if (( failures > 0 )); then log "VERIFY: $failures check(s) failed"; exit 1; fi
log "VERIFY: all checks passed"
