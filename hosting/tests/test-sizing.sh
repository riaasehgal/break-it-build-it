#!/usr/bin/env bash
# Unit tests for lib/sizing.sh (pure functions, no cloud access).
set -Eeuo pipefail
# shellcheck source=../lib/sizing.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/sizing.sh"

fails=0
check() {
  local name=$1 expected=$2 actual=$3
  if [[ "$expected" == "$actual" ]]; then echo "ok   $name"; else echo "FAIL $name: expected '$expected' got '$actual'"; fails=$((fails + 1)); fi
}

check "vcpus e2-standard-8"            8                  "$(machine_vcpus e2-standard-8)"
check "mem e2-highmem-8"               64                 "$(machine_mem_gib e2-highmem-8)"
check "auto_nodes 65"                  2                  "$(auto_nodes 65)"
check "auto_nodes 40"                  1                  "$(auto_nodes 40)"
check "auto_nodes 15"                  1                  "$(auto_nodes 15)"
# args: instances machine nodes free_cpus free_addrs free_ssd_gb
check "event: 65 on 2x e2-standard-8"  "e2-standard-8 2"  "$(choose_shape 65 e2-standard-8 2 24 8 500)"
check "trial: 65 -> e2-highmem-8 x1"   "e2-highmem-8 1"   "$(choose_shape 65 e2-standard-8 2 8 4 250)"
check "trial: 15 on 1x e2-standard-8"  "e2-standard-8 1"  "$(choose_shape 15 e2-standard-8 1 8 4 250)"
check "4 free cpus -> e2-highmem-4"    "e2-highmem-4 1"   "$(choose_shape 65 e2-standard-8 2 4 4 250)"
check "2 addresses -> 1 node shape"    "e2-highmem-8 1"   "$(choose_shape 65 e2-standard-8 2 24 2 500)"
check "1 address -> nothing fits"      "NONE"             "$(choose_shape 65 e2-standard-8 2 24 1 500 || echo NONE)"
check "500 instances -> nothing fits"  "NONE"             "$(choose_shape 500 e2-standard-8 2 8 4 250 || echo NONE)"
check "unknown type -> fallback"       "e2-highmem-8 1"   "$(choose_shape 65 n2-standard-8 2 8 4 250)"
check "low ssd quota -> 1 node"        "e2-highmem-8 1"   "$(choose_shape 65 e2-standard-8 2 24 8 60)"
check "max e2-highmem-8 x1 (pod cap)"  90                 "$(max_instances_for e2-highmem-8 1)"
check "max e2-standard-4 x1 (memory)"  55                 "$(max_instances_for e2-standard-4 1)"

(( fails == 0 )) || { echo "$fails test(s) failed"; exit 1; }
echo "all sizing tests passed"
