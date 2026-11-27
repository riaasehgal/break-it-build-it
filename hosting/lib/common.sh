#!/usr/bin/env bash
# Shared helpers for the hosting scripts. Source this file; don't run it.
# shellcheck disable=SC2034  # variables are used by the scripts that source this file

HOSTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN_ROOT="${HOSTING_DIR}/generated"
PROJECT_LABEL_KEY="purpose"
PROJECT_LABEL_VALUE="break-it-build-it"
NAMESPACE="multi-juicer"
RELEASE="multi-juicer"
CHART_REF="oci://ghcr.io/juice-shop/multi-juicer/helm/multi-juicer"
CHART_VERSION="10.4.0"

# Git Bash (MSYS) rewrites arguments that look like POSIX paths when it starts Windows programs.
# We need that for gcloud (its bash launcher hands /c/... paths to Windows Python), so it stays on
# globally. Use no_pathconv for commands whose arguments are Linux paths inside a container
# (e.g. kubectl exec ... -- /nodejs/bin/node), and native_path for files given to Windows binaries.
no_pathconv() { MSYS_NO_PATHCONV=1 "$@"; }

native_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s\n' "$1"; fi; }

ts()   { date +%H:%M:%S; }
log()  { printf '[%s] %s\n' "$(ts)" "$*" >&2; }
warn() { printf '[%s] WARN: %s\n' "$(ts)" "$*" >&2; }
die()  { printf '[%s] ERROR: %s\n' "$(ts)" "$*" >&2; exit 1; }

# retry ATTEMPTS DELAY_SECONDS CMD... : run CMD until it succeeds or attempts run out
retry() {
  local attempts=$1 delay=$2 n=1
  shift 2
  until "$@"; do
    if (( n >= attempts )); then return 1; fi
    warn "attempt $n/$attempts failed: $*; retrying in ${delay}s"
    sleep "$delay"
    n=$((n + 1))
  done
}

# random_secret [LEN=24] : alphanumeric secret (no SIGPIPE-prone pipes)
random_secret() { head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-"${1:-24}"; }

PHASE_NAMES=(); PHASE_SECS=(); _PHASE_NAME=""; _PHASE_T0=0; _RUN_T0=$SECONDS
phase_start() { _PHASE_NAME=$1; _PHASE_T0=$SECONDS; log "=== PHASE: $1 ==="; }
phase_end() {
  local d=$((SECONDS - _PHASE_T0))
  PHASE_NAMES+=("$_PHASE_NAME"); PHASE_SECS+=("$d")
  log "=== DONE:  ${_PHASE_NAME} (${d}s) ==="
}
# print_timings [CSV_FILE] : table to stderr; optionally append "stamp,phase,seconds" rows to CSV
print_timings() {
  local csv=${1:-} i total=$((SECONDS - _RUN_T0)) stamp
  stamp=$(date +%Y-%m-%dT%H:%M:%S)
  printf '\n%-28s %8s\n' "PHASE" "SECONDS" >&2
  for i in "${!PHASE_NAMES[@]}"; do
    printf '%-28s %8s\n' "${PHASE_NAMES[$i]}" "${PHASE_SECS[$i]}" >&2
    if [[ -n $csv ]]; then printf '%s,%s,%s\n' "$stamp" "${PHASE_NAMES[$i]}" "${PHASE_SECS[$i]}" >> "$csv"; fi
  done
  printf '%-28s %8s\n\n' "TOTAL (wall clock)" "$total" >&2
  if [[ -n $csv ]]; then printf '%s,%s,%s\n' "$stamp" "TOTAL" "$total" >> "$csv"; fi
  return 0
}

project_gen_dir() { printf '%s/%s\n' "$GEN_ROOT" "$1"; }

# use_project_kubeconfig PROJECT : keep cluster credentials out of ~/.kube
use_project_kubeconfig() {
  local d
  d=$(project_gen_dir "$1")
  mkdir -p "$d"
  KUBECONFIG=$(native_path "$d/kubeconfig")
  export KUBECONFIG
}

# require_owned_project PROJECT : refuse to modify/delete a project we didn't create or explicitly adopt
require_owned_project() {
  local p=$1 v
  if [[ -f "$(project_gen_dir "$p")/adopted" ]]; then return 0; fi
  v=$(gcloud projects describe "$p" --format="value(labels.${PROJECT_LABEL_KEY})" 2>/dev/null) \
    || die "cannot read project $p (does it exist? logged in as the right account?)"
  [[ $v == "$PROJECT_LABEL_VALUE" ]] \
    || die "project $p is not labelled ${PROJECT_LABEL_KEY}=${PROJECT_LABEL_VALUE} and was not adopted on this machine; refusing"
}
