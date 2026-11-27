#!/usr/bin/env bash
# Pure sizing math (no gcloud calls) so it can be unit-tested. Numbers come from the design spec:
# Juice Shop idles at ~160-175 MiB; we request 200Mi. GKE Standard caps pods at 110/node.
# shellcheck disable=SC2034

INSTANCE_MEM_MIB=200          # keep in sync with values.yaml config.juiceShop.resources.requests.memory
NODE_OVERHEAD_MIB=2048        # system pods + balancer + pre-pull per node
MAX_INSTANCES_PER_NODE=90     # 110 pod cap minus ~20 system/balancer/pre-pull pods
DISK_GB_PER_NODE=50           # pd-balanced boot disk (counts against SSD_TOTAL_GB)
FALLBACK_SHAPES=("e2-highmem-8 1" "e2-highmem-4 1" "e2-standard-4 1")

machine_vcpus() {
  case $1 in
    e2-standard-4|e2-highmem-4) echo 4 ;;
    e2-standard-8|e2-highmem-8) echo 8 ;;
    e2-standard-16|e2-highmem-16) echo 16 ;;
    *) return 1 ;;
  esac
}

machine_mem_gib() {
  case $1 in
    e2-standard-4) echo 16 ;;
    e2-standard-8|e2-highmem-4) echo 32 ;;
    e2-standard-16|e2-highmem-8) echo 64 ;;
    e2-highmem-16) echo 128 ;;
    *) return 1 ;;
  esac
}

# auto_nodes INSTANCES [PER_NODE=40] : ceil(instances / per_node)
auto_nodes() { local n=$1 per=${2:-40}; echo $(( (n + per - 1) / per )); }

# rough allocatable memory (MiB) after kubelet/system reservations
_alloc_mib() { local mem; mem=$(machine_mem_gib "$1") || return 1; echo $(( mem * 1024 * 80 / 100 )); }

# shape_fits INSTANCES MACHINE NODES FREE_CPUS FREE_ADDRS FREE_SSD_GB
#   FREE_CPUS = min(regional CPUS free, CPUS_ALL_REGIONS free). +1 address for the LoadBalancer.
shape_fits() {
  local inst=$1 m=$2 nodes=$3 cpus=$4 addrs=$5 ssd=$6 vc alloc
  vc=$(machine_vcpus "$m") || return 1
  alloc=$(_alloc_mib "$m") || return 1
  (( nodes >= 1 )) || return 1
  (( vc * nodes <= cpus )) || return 1
  (( nodes + 1 <= addrs )) || return 1
  (( nodes * DISK_GB_PER_NODE <= ssd )) || return 1
  (( inst <= nodes * MAX_INSTANCES_PER_NODE )) || return 1
  (( inst * INSTANCE_MEM_MIB + nodes * NODE_OVERHEAD_MIB <= nodes * alloc )) || return 1
}

# choose_shape INSTANCES MACHINE NODES FREE_CPUS FREE_ADDRS FREE_SSD_GB
#   prints "MACHINE NODES" for the requested shape, else the first fallback that fits; returns 1 if none
choose_shape() {
  local inst=$1 m=$2 nodes=$3 cpus=$4 addrs=$5 ssd=$6 s
  if shape_fits "$inst" "$m" "$nodes" "$cpus" "$addrs" "$ssd"; then echo "$m $nodes"; return 0; fi
  for s in "${FALLBACK_SHAPES[@]}"; do
    # shellcheck disable=SC2086  # $s is "machine nodes" and must split
    if shape_fits "$inst" $s "$cpus" "$addrs" "$ssd"; then echo "$s"; return 0; fi
  done
  return 1
}

# max_instances_for MACHINE NODES : capacity of a shape (min of memory and pod-count limits)
max_instances_for() {
  local m=$1 nodes=$2 alloc by_mem by_pods
  alloc=$(_alloc_mib "$m") || return 1
  by_mem=$(( (nodes * alloc - nodes * NODE_OVERHEAD_MIB) / INSTANCE_MEM_MIB ))
  by_pods=$(( nodes * MAX_INSTANCES_PER_NODE ))
  echo $(( by_mem < by_pods ? by_mem : by_pods ))
}
