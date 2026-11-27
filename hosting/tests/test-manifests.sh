#!/usr/bin/env bash
# Schema-validates our manifests with kubeconform (via docker; nothing to install).
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"
command -v docker >/dev/null 2>&1 || { echo "SKIP: docker not available"; exit 0; }

docs=""
for f in "$HOSTING_DIR"/manifests/*.yaml; do
  docs+=$(sed -e 's|__JUICE_IMAGE__|bkimminich/juice-shop:v20.1.1|g' -e 's|__BUILDIT_IMAGE__|ghcr.io/example/bib-buildit:v1|g' -e 's|__JUICE_SHOP_URL__|http://203.0.113.7|g' "$f")$'\n---\n'
done
printf '%s' "$docs" | docker run --rm -i ghcr.io/yannh/kubeconform:v0.6.7 -strict -summary -kubernetes-version 1.34.0 -
