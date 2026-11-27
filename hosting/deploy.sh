#!/usr/bin/env bash
# One-command MultiJuicer deploy onto a dedicated GKE project. Safe to re-run: each phase skips
# work that's already done. Prints per-phase timing and appends it to generated/<project>/timings.csv.
#
#   hosting/deploy.sh --project ID --instances N [options]      (see --help)
set -Eeuo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$HERE/lib/common.sh"
# shellcheck source=lib/sizing.sh
source "$HERE/lib/sizing.sh"

PHASES="preflight project billing apis quota node-sa cluster k8s-base helm warm verify"

usage() {
  cat <<'EOF'
Usage: deploy.sh --project ID --instances N [options]

Required:
  --project ID            GCP project to deploy into. Only this project is touched.
  --instances N           Juice Shop instances to allow (one per person or team).

Options:
  --create-project        Create the project if missing (labelled purpose=break-it-build-it).
  --adopt-project         Accept an existing unlabelled project (e.g. organizer-made). Records a
                          local marker so teardown.sh will also accept it.
  --billing-account ID    Link this billing account if the project has none (gcloud billing accounts list).
  --region R              Default: us-central1
  --zone Z                Default: <region>-a
  --machine-type T        Default: e2-standard-8 (falls back automatically if quota is short)
  --nodes N               Default: ceil(instances / 40)
  --juice-image IMG:TAG   Default: bkimminich/juice-shop:v20.1.1
  --with-buildit          Also host the Build-It site (sandbox mode) on its own public IP.
  --buildit-image IMG:TAG Default: ghcr.io/riaasehgal/bib-buildit:v1
  --budget AMOUNT         Budget alert in the billing account's currency; 0 = skip. Default: 50
  --stop-after PHASE      Stop after PHASE: preflight project billing apis quota node-sa cluster k8s-base helm warm
  --skip-verify           Skip the smoke test and isolation probes.
  -h, --help
EOF
}

PROJECT="" INSTANCES="" CREATE_PROJECT=0 ADOPT_PROJECT=0 BILLING_ACCOUNT="" REGION="us-central1" ZONE=""
MACHINE_TYPE="e2-standard-8" NODES="" JUICE_IMAGE="bkimminich/juice-shop:v20.1.1" BUDGET=50 STOP_AFTER="" SKIP_VERIFY=0
WITH_BUILDIT=0 BUILDIT_IMAGE="ghcr.io/riaasehgal/bib-buildit:v1"
CLUSTER="juice"

while (( $# )); do
  case $1 in
    --project) PROJECT=${2:-}; shift 2 ;;
    --instances) INSTANCES=${2:-}; shift 2 ;;
    --create-project) CREATE_PROJECT=1; shift ;;
    --adopt-project) ADOPT_PROJECT=1; shift ;;
    --billing-account) BILLING_ACCOUNT=${2:-}; shift 2 ;;
    --region) REGION=${2:-}; shift 2 ;;
    --zone) ZONE=${2:-}; shift 2 ;;
    --machine-type) MACHINE_TYPE=${2:-}; shift 2 ;;
    --nodes) NODES=${2:-}; shift 2 ;;
    --juice-image) JUICE_IMAGE=${2:-}; shift 2 ;;
    --with-buildit) WITH_BUILDIT=1; shift ;;
    --buildit-image) BUILDIT_IMAGE=${2:-}; shift 2 ;;
    --budget) BUDGET=${2:-}; shift 2 ;;
    --stop-after) STOP_AFTER=${2:-}; shift 2 ;;
    --skip-verify) SKIP_VERIFY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

# ---- validation (no cloud calls above this line) ----
[[ -n $PROJECT ]] || { usage >&2; die "--project is required"; }
[[ $PROJECT =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] || die "invalid project ID: $PROJECT"
if ! [[ $INSTANCES =~ ^[0-9]+$ ]] || (( INSTANCES < 1 )); then die "--instances must be a positive number"; fi
[[ $BUDGET =~ ^[0-9]+$ ]] || die "--budget must be a whole number"
if [[ -n $STOP_AFTER && " $PHASES " != *" $STOP_AFTER "* ]]; then die "--stop-after must be one of: $PHASES"; fi
if [[ -n $NODES ]] && { ! [[ $NODES =~ ^[0-9]+$ ]] || (( NODES < 1 )); }; then die "--nodes must be a positive number"; fi
[[ $JUICE_IMAGE == *:* && $JUICE_IMAGE != *@* ]] || die "--juice-image must be IMAGE:TAG (digests not supported)"
[[ $BUILDIT_IMAGE == *:* && $BUILDIT_IMAGE != *@* ]] || die "--buildit-image must be IMAGE:TAG (digests not supported)"
ZONE=${ZONE:-${REGION}-a}
NODES=${NODES:-$(auto_nodes "$INSTANCES")}
GEN=$(project_gen_dir "$PROJECT"); mkdir -p "$GEN"
TIMINGS_CSV="$GEN/timings.csv"
SECRETS="$GEN/secret-values.yaml"
NODE_SA="gke-nodes@${PROJECT}.iam.gserviceaccount.com"
use_project_kubeconfig "$PROJECT"

# shellcheck disable=SC2154  # rc is assigned inside the trap string itself
trap 'rc=$?; log "FAILED in phase: ${_PHASE_NAME:-?} (exit $rc). Fix the cause and re-run the same command; finished phases are skipped."; print_timings "$TIMINGS_CSV"; exit $rc' ERR
maybe_stop() {
  if [[ $STOP_AFTER == "$1" ]]; then print_timings "$TIMINGS_CSV"; log "stopping after phase '$1' as requested"; exit 0; fi
}

# ---- preflight ----
phase_start preflight
if ! prereq_out=$("$HERE/check-prereqs.sh" 2>&1); then printf '%s\n' "$prereq_out" >&2; die "prerequisites missing (see above)"; fi
ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)
ACCOUNT=$(printf '%s\n' "$ACCOUNT" | sed -n 1p)
log "account=$ACCOUNT project=$PROJECT zone=$ZONE instances=$INSTANCES requested=${NODES}x${MACHINE_TYPE} image=$JUICE_IMAGE"
phase_end; maybe_stop preflight

# ---- project ----
phase_start project
if gcloud projects describe "$PROJECT" --format='value(projectId)' >/dev/null 2>&1; then
  label=$(gcloud projects describe "$PROJECT" --format="value(labels.${PROJECT_LABEL_KEY})")
  if [[ $label != "$PROJECT_LABEL_VALUE" && ! -f $GEN/adopted ]]; then
    (( ADOPT_PROJECT )) || die "project $PROJECT exists but isn't labelled ${PROJECT_LABEL_KEY}=${PROJECT_LABEL_VALUE}. If it is the dedicated event project, re-run with --adopt-project."
    : > "$GEN/adopted"
    log "adopted existing project $PROJECT (marker: $GEN/adopted)"
  fi
  log "project $PROJECT exists"
else
  (( CREATE_PROJECT )) || die "project $PROJECT not found or no access. Use --create-project to create it."
  gcloud projects create "$PROJECT" --name="break-it-build-it" --labels="${PROJECT_LABEL_KEY}=${PROJECT_LABEL_VALUE}" --quiet
fi
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')
phase_end; maybe_stop project

# ---- billing ----
phase_start billing
enabled=$(gcloud billing projects describe "$PROJECT" --format='value(billingEnabled)' 2>/dev/null || true)
if [[ ${enabled,,} == true ]]; then
  log "billing already enabled"
else
  [[ -n $BILLING_ACCOUNT ]] || die "project has no billing account; pass --billing-account (list: gcloud billing accounts list)"
  gcloud billing projects link "$PROJECT" --billing-account="$BILLING_ACCOUNT" --quiet >/dev/null
fi
BILLING_ACCOUNT=$(gcloud billing projects describe "$PROJECT" --format='value(billingAccountName)')
BILLING_ACCOUNT=${BILLING_ACCOUNT#billingAccounts/}
log "billing account: $BILLING_ACCOUNT"
phase_end; maybe_stop billing

# ---- apis ----
phase_start apis
gcloud services enable compute.googleapis.com container.googleapis.com iam.googleapis.com \
  billingbudgets.googleapis.com --project "$PROJECT" --quiet
phase_end; maybe_stop apis

# ---- quota + sizing ----
phase_start quota
CLUSTER_EXISTS=0
if gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --zone "$ZONE" >/dev/null 2>&1; then CLUSTER_EXISTS=1; fi
if (( CLUSTER_EXISTS )); then
  shape=$(gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --zone "$ZONE" \
    --format='value(nodePools[0].config.machineType,currentNodeCount)')
  read -r MACHINE_TYPE_FINAL NODES_FINAL <<<"$shape"
  log "cluster already exists: ${NODES_FINAL}x${MACHINE_TYPE_FINAL} (quota check skipped)"
else
  quota_csv() { gcloud "$@" --project "$PROJECT" --flatten=quotas --format='csv[no-heading](quotas.metric,quotas.limit,quotas.usage)'; }
  free_of() { awk -F, -v m="$2" '$1==m {printf "%d\n", $2-$3; f=1} END {if (!f) print 0}' <<<"$1"; }
  regional=$(retry 6 10 quota_csv compute regions describe "$REGION")
  global=$(retry 6 10 quota_csv compute project-info describe)
  cpus_r=$(free_of "$regional" CPUS); cpus_g=$(free_of "$global" CPUS_ALL_REGIONS)
  addrs=$(free_of "$regional" IN_USE_ADDRESSES); ssd=$(free_of "$regional" SSD_TOTAL_GB)
  free_cpus=$(( cpus_r < cpus_g ? cpus_r : cpus_g ))
  if (( WITH_BUILDIT )); then addrs=$((addrs - 1)); fi   # Build-It's LoadBalancer needs one more external IP
  log "free quota: CPUS($REGION)=$cpus_r CPUS_ALL_REGIONS=$cpus_g IN_USE_ADDRESSES=$addrs SSD_TOTAL_GB=$ssd"
  printf 'region=%s cpus=%s cpus_all_regions=%s in_use_addresses=%s ssd_total_gb=%s\n' \
    "$REGION" "$cpus_r" "$cpus_g" "$addrs" "$ssd" > "$GEN/quota.txt"
  if ! shape=$(choose_shape "$INSTANCES" "$MACHINE_TYPE" "$NODES" "$free_cpus" "$addrs" "$ssd"); then
    die "no machine shape fits $INSTANCES instances in this quota. Options: fewer instances (run pairs/teams; 1x e2-highmem-4 holds $(max_instances_for e2-highmem-4 1)), another --region, or a quota increase."
  fi
  read -r MACHINE_TYPE_FINAL NODES_FINAL <<<"$shape"
  if [[ "$MACHINE_TYPE_FINAL $NODES_FINAL" != "$MACHINE_TYPE $NODES" ]]; then
    warn "requested ${NODES}x${MACHINE_TYPE} doesn't fit quota; using ${NODES_FINAL}x${MACHINE_TYPE_FINAL}"
  fi
fi
log "cluster shape: ${NODES_FINAL}x${MACHINE_TYPE_FINAL} (capacity ~$(max_instances_for "$MACHINE_TYPE_FINAL" "$NODES_FINAL" || echo '?') instances)"
phase_end; maybe_stop quota

# ---- node service account (minimal permissions) ----
phase_start node-sa
if ! gcloud iam service-accounts describe "$NODE_SA" --project "$PROJECT" >/dev/null 2>&1; then
  gcloud iam service-accounts create gke-nodes --project "$PROJECT" --display-name="GKE nodes (minimal)" --quiet
fi
retry 6 10 gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$NODE_SA" \
  --role=roles/container.defaultNodeServiceAccount --condition=None --quiet >/dev/null
phase_end; maybe_stop node-sa

# ---- budget (runs in background during cluster creation; never fatal) ----
create_budget() {
  if (( BUDGET == 0 )); then log "budget: skipped (--budget 0)"; return 0; fi
  local name="bibi-${PROJECT}" existing
  existing=$(gcloud billing budgets list --billing-account="$BILLING_ACCOUNT" --billing-project="$PROJECT" \
    --format='value(displayName)' 2>/dev/null || true)
  if [[ $'\n'"$existing"$'\n' == *$'\n'"$name"$'\n'* ]]; then log "budget: $name already exists"; return 0; fi
  # exclude-all-credits: alert on gross usage. With trial/promo credits, net spend stays 0 and a
  # default budget would never fire.
  if gcloud billing budgets create --billing-account="$BILLING_ACCOUNT" --billing-project="$PROJECT" \
      --display-name="$name" --budget-amount="$BUDGET" --filter-projects="projects/$PROJECT_NUMBER" \
      --credit-types-treatment=exclude-all-credits \
      --threshold-rule=percent=0.25 --threshold-rule=percent=0.5 \
      --threshold-rule=percent=0.9 --threshold-rule=percent=1.0 --quiet >/dev/null 2>"$GEN/budget.err"; then
    log "budget: created $name ($BUDGET, billing-account currency; emails go to billing admins)"
  else
    warn "budget: not created (details: $GEN/budget.err). Set one in the console: Billing > Budgets & alerts."
  fi
}

# ---- cluster ----
phase_start cluster
create_budget & BUDGET_PID=$!
create_cluster() {
  gcloud container clusters create "$CLUSTER" --project "$PROJECT" --zone "$ZONE" \
    --release-channel=regular \
    --num-nodes="$NODES_FINAL" --machine-type="$MACHINE_TYPE_FINAL" \
    --disk-type=pd-balanced --disk-size="$DISK_GB_PER_NODE" --image-type=COS_CONTAINERD \
    --enable-dataplane-v2 \
    --workload-pool="${PROJECT}.svc.id.goog" --workload-metadata=GKE_METADATA \
    --service-account="$NODE_SA" \
    --shielded-secure-boot --shielded-integrity-monitoring \
    --logging=NONE --monitoring=NONE --no-enable-managed-prometheus \
    --quiet
}
if (( CLUSTER_EXISTS )); then
  log "cluster $CLUSTER already exists"
elif ! create_cluster; then
  # Typical first-run cause: the new node service account hasn't propagated through IAM yet.
  if gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --zone "$ZONE" >/dev/null 2>&1; then
    die "cluster create failed but a cluster object exists. Inspect: gcloud container clusters describe $CLUSTER --zone $ZONE --project $PROJECT"
  fi
  warn "cluster create failed; retrying once in 30s"
  sleep 30
  create_cluster
fi
retry 3 10 gcloud container clusters get-credentials "$CLUSTER" --project "$PROJECT" --zone "$ZONE" --quiet
GKE_VERSION=$(gcloud container clusters describe "$CLUSTER" --project "$PROJECT" --zone "$ZONE" --format='value(currentMasterVersion)')
log "GKE version: $GKE_VERSION"
phase_end; maybe_stop cluster

# ---- base Kubernetes objects (LB first so its IP provisions while Helm runs) ----
phase_start k8s-base
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
retry 10 2 kubectl -n "$NAMESPACE" patch serviceaccount default -p '{"automountServiceAccountToken": false}'
kubectl apply -f - < "$HERE/manifests/lb-service.yaml"
kubectl apply -f - < "$HERE/manifests/networkpolicy.yaml"
sed "s|__JUICE_IMAGE__|${JUICE_IMAGE}|g" "$HERE/manifests/prepull-daemonset.yaml" | kubectl apply -f -
if (( WITH_BUILDIT )); then
  sed "s|__BUILDIT_IMAGE__|${BUILDIT_IMAGE}|g" "$HERE/manifests/buildit.yaml" | kubectl apply -f -
fi
phase_end; maybe_stop k8s-base

# ---- helm ----
phase_start helm
if [[ ! -s $SECRETS ]]; then
  ( umask 077
    printf 'adminPassword: "%s"\ncookie:\n  cookieParserSecret: "%s"\n' "$(random_secret 20)" "$(random_secret 24)" > "$SECRETS" )
  log "generated new admin password + cookie secret in $SECRETS"
fi
helm upgrade --install "$RELEASE" "$CHART_REF" --version "$CHART_VERSION" --namespace "$NAMESPACE" \
  -f "$(native_path "$HERE/values.yaml")" -f "$(native_path "$SECRETS")" \
  --set config.maxInstances=$((INSTANCES + 1)) \
  --set-string config.juiceShop.image="${JUICE_IMAGE%:*}" \
  --set-string config.juiceShop.tag="${JUICE_IMAGE##*:}" \
  --wait --timeout 5m
phase_end; maybe_stop helm

# ---- warm: image on every node, public IP answering ----
phase_start warm
kubectl -n "$NAMESPACE" rollout status daemonset/juice-shop-prepull --timeout=5m
LB_IP=""
for _ in $(seq 1 60); do
  LB_IP=$(kubectl -n "$NAMESPACE" get svc multi-juicer-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [[ -n $LB_IP ]]; then break; fi
  sleep 5
done
[[ -n $LB_IP ]] || die "LoadBalancer IP not assigned after 5 min. Check: kubectl -n $NAMESPACE describe svc multi-juicer-public"
URL="http://$LB_IP"
retry 30 5 curl -fsS -o /dev/null --max-time 5 "$URL/multi-juicer/api/readiness"
# Build-It is optional: any problem here is a warning, never a reason to fail the MultiJuicer deploy.
warm_buildit() {
  local ip=""
  for _ in $(seq 1 60); do
    ip=$(kubectl -n "$NAMESPACE" get svc buildit-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
    if [[ -n $ip ]]; then break; fi
    sleep 5
  done
  if [[ -z $ip ]]; then warn "Build-It LoadBalancer IP not assigned after 5 min (kubectl -n $NAMESPACE describe svc buildit-public)"; return 1; fi
  # Point Build-It's "Open Juice Shop" button at MultiJuicer (no-op if already set).
  kubectl -n "$NAMESPACE" set env deploy/buildit JUICE_SHOP_URL="$URL" || return 1
  kubectl -n "$NAMESPACE" rollout status deploy/buildit --timeout=3m || return 1
  retry 30 5 curl -fsS -o /dev/null --max-time 5 "http://$ip/api/vulns" || return 1
  BUILDIT_URL="http://$ip"
}
BUILDIT_URL=""
if (( WITH_BUILDIT )) && ! warm_buildit; then
  warn "Build-It is NOT ready. MultiJuicer is fine; re-run the same command later to retry Build-It."
fi
cat > "$GEN/deploy-info.env" <<EOF
PROJECT=$PROJECT
ZONE=$ZONE
CLUSTER=$CLUSTER
URL=$URL
INSTANCES=$INSTANCES
SHAPE=${NODES_FINAL}x${MACHINE_TYPE_FINAL}
GKE_VERSION=$GKE_VERSION
JUICE_IMAGE=$JUICE_IMAGE
BUILDIT_URL=$BUILDIT_URL
EOF
phase_end; maybe_stop warm

# ---- verify ----
if (( ! SKIP_VERIFY )); then
  phase_start verify
  "$HERE/verify.sh" --project "$PROJECT" || warn "VERIFY FAILED. Read the output above before opening the doors."
  phase_end
fi

wait "$BUDGET_PID" 2>/dev/null || true
ADMIN_PASSWORD=$(sed -n 's/^adminPassword: "\(.*\)"$/\1/p' "$SECRETS")
print_timings "$TIMINGS_CSV"
cat >&2 <<EOF
================================================================
 Participants:  $URL
 Admin:         $URL  -> team name "admin", passcode: $ADMIN_PASSWORD
 Build-It:      ${BUILDIT_URL:-(not deployed; add --with-buildit)}
 Capacity:      $INSTANCES instances on ${NODES_FINAL}x${MACHINE_TYPE_FINAL} (GKE $GKE_VERSION)
 kubectl:       export KUBECONFIG="$KUBECONFIG"
 Load test:     hosting/loadtest.sh --project $PROJECT --teams 10 --cleanup
 Teardown:      hosting/teardown.sh --project $PROJECT --mode project --yes
================================================================
EOF
