#!/usr/bin/env bash
# Simulates N teams registering at the same moment and reports time-to-ready for each instance.
#   hosting/loadtest.sh --project ID --teams N [--prefix lt] [--concurrency N] [--cleanup]
#   hosting/loadtest.sh --url http://IP --teams N        (cleanup needs MJ_ADMIN_PASSWORD)
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

usage() {
  cat <<'EOF'
Usage: loadtest.sh (--project ID | --url URL) --teams N [--prefix lt] [--concurrency N] [--cleanup]
  --teams N        number of simultaneous registrations (team names <prefix>-001 ...)
  --prefix P       lowercase letters/digits/hyphens, max 9 chars (default: lt)
  --concurrency C  parallel workers (default: all at once)
  --cleanup        delete the load-test teams afterwards via the admin API
EOF
}

PROJECT="" URL="" TEAMS="" PREFIX="lt" CONCURRENCY="" CLEANUP=0 ADMIN_PASSWORD="${MJ_ADMIN_PASSWORD:-}"
while (( $# )); do
  case $1 in
    --project) PROJECT=${2:-}; shift 2 ;;
    --url) URL=${2:-}; shift 2 ;;
    --teams) TEAMS=${2:-}; shift 2 ;;
    --prefix) PREFIX=${2:-}; shift 2 ;;
    --concurrency) CONCURRENCY=${2:-}; shift 2 ;;
    --cleanup) CLEANUP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done
if [[ -n $PROJECT ]]; then
  GEN=$(project_gen_dir "$PROJECT")
  [[ -f $GEN/deploy-info.env ]] || die "no $GEN/deploy-info.env; run deploy.sh first"
  # shellcheck disable=SC1091
  source "$GEN/deploy-info.env"
  ADMIN_PASSWORD=$(sed -n 's/^adminPassword: "\(.*\)"$/\1/p' "$GEN/secret-values.yaml")
fi
[[ -n $URL ]] || { usage >&2; die "give --url or --project"; }
if ! [[ $TEAMS =~ ^[0-9]+$ ]] || (( TEAMS < 1 || TEAMS > 999 )); then die "--teams must be 1-999"; fi
[[ $PREFIX =~ ^[a-z0-9][-a-z0-9]{0,8}$ ]] || die "prefix must be lowercase letters/digits/hyphens, max 9 chars"
CONCURRENCY=${CONCURRENCY:-$TEAMS}
OUT_DIR="$GEN_ROOT/loadtest"; mkdir -p "$OUT_DIR"
RESULTS="$OUT_DIR/$(date +%Y%m%d-%H%M%S)-${TEAMS}teams.csv"
export URL

one_team() {
  local team=$1 jar t0 code ready_ms=-1 proxy=000 body i
  jar=$(mktemp)
  t0=$(date +%s%N)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 -c "$jar" -H 'Content-Type: application/json' \
    -d '{}' -X POST "$URL/multi-juicer/api/teams/$team/join" || echo 000)
  if [[ $code == 200 ]]; then
    for (( i = 0; i < 600; i++ )); do   # up to ~5 min
      body=$(curl -s --max-time 10 -b "$jar" "$URL/multi-juicer/api/teams/$team/status" || true)
      if [[ $body == *'"readiness":true'* ]]; then ready_ms=$(( ($(date +%s%N) - t0) / 1000000 )); break; fi
      sleep 0.5
    done
    proxy=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -b "$jar" "$URL/rest/admin/application-version" || echo 000)
  fi
  rm -f "$jar"
  printf '%s,%s,%s,%s\n' "$team" "$code" "$ready_ms" "$proxy"
}
export -f one_team

echo "team,join_http,ready_ms,proxy_http" > "$RESULTS"
log "starting $TEAMS registrations against $URL (concurrency $CONCURRENCY)"
T0=$SECONDS
# shellcheck disable=SC2016  # single quotes on purpose: $1 expands in the child bash, not here
seq -f "${PREFIX}-%03g" 1 "$TEAMS" | xargs -P "$CONCURRENCY" -I{} bash -c 'one_team "$1"' _ {} >> "$RESULTS"
log "all workers finished in $((SECONDS - T0))s; raw results: $RESULTS"

total=$(( $(wc -l < "$RESULTS") - 1 ))
joined=$(awk -F, 'NR>1 && $2==200' "$RESULTS" | wc -l | tr -d ' ')
proxied=$(awk -F, 'NR>1 && $4==200' "$RESULTS" | wc -l | tr -d ' ')
mapfile -t times < <(awk -F, 'NR>1 && $3>=0 {print $3}' "$RESULTS" | sort -n)
ready=${#times[@]}
printf '\nteams=%s joined=%s ready=%s proxy_ok=%s\n' "$total" "$joined" "$ready" "$proxied"
awk -F, 'NR>1 && $2!=200 {c[$2]++} END {for (k in c) printf "  join HTTP %s x%d\n", k, c[k]}' "$RESULTS"
pct() { local i=$(( (ready * $1 + 99) / 100 - 1 )); (( i < 0 )) && i=0; echo "${times[$i]}"; }
if (( ready > 0 )); then
  printf 'time-to-ready ms: min=%s p50=%s p90=%s p95=%s max=%s\n' \
    "${times[0]}" "$(pct 50)" "$(pct 90)" "$(pct 95)" "${times[ready-1]}"
fi
if (( ready == total )); then log "RESULT: all $total instances ready"; else warn "RESULT: $((total - ready)) of $total instances NOT ready"; fi

if (( CLEANUP )); then
  [[ -n $ADMIN_PASSWORD ]] || die "--cleanup needs the admin password (use --project, or set MJ_ADMIN_PASSWORD)"
  jar=$(mktemp)
  curl -s -o /dev/null --max-time 10 -c "$jar" -H 'Content-Type: application/json' \
    -d "{\"passcode\":\"$ADMIN_PASSWORD\"}" -X POST "$URL/multi-juicer/api/teams/admin/join"
  seq -f "${PREFIX}-%03g" 1 "$TEAMS" | xargs -P 10 -I{} curl -s -o /dev/null --max-time 15 -b "$jar" \
    -X DELETE "$URL/multi-juicer/api/admin/teams/{}/delete"
  rm -f "$jar"
  log "deleted $TEAMS load-test teams"
fi
(( ready == total ))
