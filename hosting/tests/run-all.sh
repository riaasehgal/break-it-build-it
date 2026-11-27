#!/usr/bin/env bash
# Runs every offline test. Needs: bash, helm, network to ghcr.io; docker for shellcheck/kubeconform.
set -Euo pipefail
T="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$T/../.." && pwd)"
failed=0
run() { echo "== $1"; if bash "$T/$1"; then echo; else echo "!! $1 FAILED"; echo; failed=$((failed + 1)); fi; }
run test-sizing.sh
run test-cli.sh
run test-render.sh
run test-manifests.sh
run test-buildit.sh

echo "== shellcheck"
if command -v docker >/dev/null 2>&1; then
  # docker on Windows needs C:/... for the volume; pwd -W only exists in Git Bash
  if ! src=$(cd "$REPO" && pwd -W 2>/dev/null); then src=$REPO; fi
  if (cd "$REPO" && MSYS_NO_PATHCONV=1 docker run --rm -v "$src:/mnt" -w /mnt koalaman/shellcheck:stable \
        -x hosting/*.sh hosting/lib/*.sh hosting/tests/*.sh); then echo "shellcheck clean"; else echo "!! shellcheck FAILED"; failed=$((failed + 1)); fi
else
  echo "SKIP: docker not available"
fi

(( failed == 0 )) || { echo "$failed test group(s) failed"; exit 1; }
echo "ALL OFFLINE TESTS PASSED"
