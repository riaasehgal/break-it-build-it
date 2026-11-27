#!/usr/bin/env bash
# Deletes what deploy.sh created and verifies nothing billable is left.
#   hosting/teardown.sh --project ID --mode project|cluster [--zone Z] [--yes]
#   --mode project : delete budget, unlink billing, delete the whole project (test + standby projects)
#   --mode cluster : delete the LB service + cluster, keep the project (e.g. organizer-owned project)
# Without --yes nothing is deleted: it only lists what's there.
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"

usage() { echo "Usage: teardown.sh --project ID --mode project|cluster [--zone Z] [--yes]"; }
PROJECT="" MODE="" YES=0 ZONE_ARG=""
while (( $# )); do
  case $1 in
    --project) PROJECT=${2:-}; shift 2 ;;
    --mode) MODE=${2:-}; shift 2 ;;
    --zone) ZONE_ARG=${2:-}; shift 2 ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done
[[ -n $PROJECT ]] || { usage >&2; die "--project is required"; }
[[ $MODE == project || $MODE == cluster ]] || { usage >&2; die "--mode must be project or cluster"; }

require_owned_project "$PROJECT"
GEN=$(project_gen_dir "$PROJECT")
ZONE="" CLUSTER="juice"
# shellcheck disable=SC1091
if [[ -f $GEN/deploy-info.env ]]; then source "$GEN/deploy-info.env"; fi
ZONE=${ZONE_ARG:-${ZONE:-us-central1-a}}

# billable_leftovers : one line per resource type that still has items; empty output = clean
billable_leftovers() {
  local kind out
  for kind in "container clusters" "compute instances" "compute disks" "compute forwarding-rules" \
              "compute addresses" "compute target-pools" "compute backend-services"; do
    # shellcheck disable=SC2086  # $kind is two words on purpose
    out=$(gcloud $kind list --project "$PROJECT" --format='value(name)' 2>/dev/null || true)
    if [[ -n $out ]]; then printf '%s: %s\n' "$kind" "$(printf '%s' "$out" | tr '\n' ' ')"; fi
  done
}

if (( ! YES )); then
  log "DRY RUN (no --yes): mode=$MODE project=$PROJECT zone=$ZONE cluster=$CLUSTER"
  left=$(billable_leftovers)
  if [[ -n $left ]]; then printf 'Billable resources present:\n%s\n' "$left"; else echo "No billable compute/GKE resources found."; fi
  log "re-run with --yes to delete"
  exit 0
fi

if [[ $MODE == cluster ]]; then
  use_project_kubeconfig "$PROJECT"
  if gcloud container clusters describe "$CLUSTER" --zone "$ZONE" --project "$PROJECT" >/dev/null 2>&1; then
    gcloud container clusters get-credentials "$CLUSTER" --zone "$ZONE" --project "$PROJECT" --quiet || true
    # Delete the LoadBalancer Service first so GKE removes the forwarding rule it created.
    kubectl -n "$NAMESPACE" delete svc multi-juicer-public --wait=true --timeout=3m \
      || warn "could not delete the LB service; checking for leftover forwarding rules below"
    gcloud container clusters delete "$CLUSTER" --zone "$ZONE" --project "$PROJECT" --quiet
  else
    log "cluster $CLUSTER not found in $ZONE"
  fi
  left=$(billable_leftovers)
  if [[ -n $left ]]; then
    warn "billable resources still present in $PROJECT:"; printf '%s\n' "$left" >&2
    warn "delete them in the console (Compute Engine / Network services) or with gcloud, then re-run this script"
    exit 1
  fi
  rm -f "$GEN/kubeconfig"
  log "VERIFIED: no clusters, VMs, disks, forwarding rules, static IPs, target pools or backend services left in $PROJECT"
  exit 0
fi

# ---- mode project ----
BA=$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)' 2>/dev/null || true)
BA=${BA#billingAccounts/}
if [[ -n $BA ]]; then
  budgets=$(gcloud billing budgets list --billing-account="$BA" --billing-project="$PROJECT" \
    --format='csv[no-heading](name,displayName)' 2>/dev/null || true)
  while IFS=, read -r bname bdisplay; do
    if [[ $bdisplay == "bibi-$PROJECT" ]]; then
      if gcloud billing budgets delete "$bname" --billing-project="$PROJECT" --quiet; then
        log "deleted budget $bdisplay"
      else
        warn "could not delete budget $bdisplay (harmless; remove it under Billing > Budgets & alerts)"
      fi
    fi
  done <<<"$budgets"
  gcloud billing projects unlink "$PROJECT" --quiet >/dev/null
  log "billing unlinked: nothing in $PROJECT can be charged from now on"
fi
gcloud projects delete "$PROJECT" --quiet
state=$(gcloud projects describe "$PROJECT" --format='value(lifecycleState)' 2>/dev/null || echo UNKNOWN)
billing=$(gcloud billing projects describe "$PROJECT" --format='value(billingEnabled)' 2>/dev/null || echo unknown)
rm -f "$GEN/kubeconfig"
if [[ $state == DELETE_REQUESTED && ${billing,,} != true ]]; then
  log "VERIFIED: project $PROJECT is DELETE_REQUESTED (all resources shut down; purged after 30 days) and billing is disabled"
else
  warn "project state=$state billingEnabled=$billing. Check the console: IAM & Admin > Manage resources"
  exit 1
fi
