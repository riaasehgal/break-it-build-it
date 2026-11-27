#!/usr/bin/env bash
# Renders the real MultiJuicer 10.4.0 chart with our values and asserts the keys we rely on.
# Needs network access to ghcr.io (chart pull) and helm.
set -Eeuo pipefail
# shellcheck source=../lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/common.sh"

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
printf 'adminPassword: "TESTADMINPW123"\ncookie:\n  cookieParserSecret: "TESTCOOKIESECRET12345678"\n' > "$tmp/secret.yaml"

out=$(helm template "$RELEASE" "$CHART_REF" --version "$CHART_VERSION" --namespace "$NAMESPACE" \
  -f "$(native_path "$HOSTING_DIR/values.yaml")" -f "$(native_path "$tmp/secret.yaml")" \
  --set config.maxInstances=66 \
  --set-string config.juiceShop.image=example.org/juice --set-string config.juiceShop.tag=v20.1.1-test)

fails=0
expect() {  # expect DESCRIPTION FIXED_STRING
  if [[ $out == *"$2"* ]]; then echo "ok   $1"; else echo "FAIL $1 (missing: $2)"; fails=$((fails + 1)); fi
}
expect "maxInstances passed through"        '"maxInstances": 66'
expect "juice image repo override"          '"image": "example.org/juice"'
expect "juice image tag override"           '"tag": "v20.1.1-test"'
expect "juice memory request 200Mi"         '"memory": "200Mi"'
expect "juice cpu request 50m"              '"cpu": "50m"'
expect "juice memory limit 768Mi"           '"memory": "768Mi"'
expect "local logo (no egress at startup)"  'logo: JuiceShop_Logo.png'
expect "local favicon"                      'favicon: favicon_js.ico'
expect "admin password from secret file"    "adminPassword: \"$(printf 'TESTADMINPW123' | base64)\""
expect "cookie secret from secret file"     "cookieParserSecret: \"$(printf 'TESTCOOKIESECRET12345678' | base64)\""
expect "balancer replicas 2"                'replicas: 2'
expect "balancer cpu limit raised"          'cpu: "2"'
expect "chart Service stays ClusterIP"      'type: ClusterIP'
expect "plain-HTTP cookie (secure false)"   '"secure": false'

(( fails == 0 )) || { echo "$fails render assertion(s) failed"; exit 1; }
echo "all render tests passed"
