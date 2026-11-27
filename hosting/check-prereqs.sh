#!/usr/bin/env bash
# Checks that this machine can run deploy.sh / verify.sh / loadtest.sh / teardown.sh.
# Usage: hosting/check-prereqs.sh      (exit 0 = ready, 1 = something missing)
# Works in Git Bash on Windows and in Google Cloud Shell.
set -Eeuo pipefail
# shellcheck source=lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

problems=0
ok()  { printf '  %-24s OK    %s\n' "$1" "$2"; }
bad() { printf '  %-24s FAIL  %s\n' "$1" "$2"; problems=$((problems + 1)); }

# In PowerShell, plain `bash` is C:\Windows\System32\bash.exe = WSL, a separate Linux VM that can see
# Windows gcloud but not kubectl.exe/helm.exe or your gcloud login. Catch that before the confusing FAILs.
if grep -qi microsoft /proc/version 2>/dev/null && [[ "$(command -v gcloud 2>/dev/null)" == /mnt/* ]]; then
  echo "This is WSL (Linux VM), not Git Bash, and it is using the Windows gcloud install."
  printf '%s\n' 'From PowerShell run:  & "C:\Program Files\Git\bin\bash.exe" hosting/<script>.sh ...'
  echo "or open a Git Bash terminal. (Or install gcloud/kubectl/helm inside WSL and log in there.)"
  exit 1
fi
# version_ge A B : true if dotted version A >= B
version_ge() { [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | sed -n 1p)" == "$2" ]]; }

echo "Tools:"
if (( BASH_VERSINFO[0] >= 4 )); then ok bash "$BASH_VERSION"; else bad bash "need bash >= 4 (have $BASH_VERSION)"; fi
for c in curl awk sed sort cut tr xargs seq mktemp; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c" "found"; else bad "$c" "not found"; fi
done

if command -v gcloud >/dev/null 2>&1; then
  ok gcloud "$(gcloud version 2>/dev/null | sed -n 1p)"
else
  bad gcloud "install the Google Cloud SDK (Windows: winget install Google.CloudSDK)"
fi

if command -v kubectl >/dev/null 2>&1; then
  v=$(kubectl version --client -o yaml 2>/dev/null | awk '/gitVersion/ && !f {print $2; f=1}' | tr -d 'v"')
  v=${v%%-*}
  if [[ -n $v ]] && version_ge "$v" 1.30; then ok kubectl "$v"; else bad kubectl "need >= 1.30 (have ${v:-unknown}); run: gcloud components install kubectl"; fi
else
  bad kubectl "run: gcloud components install kubectl"
fi

if command -v gke-gcloud-auth-plugin >/dev/null 2>&1; then
  ok gke-gcloud-auth-plugin "found"
else
  bad gke-gcloud-auth-plugin "run: gcloud components install gke-gcloud-auth-plugin"
fi

if command -v helm >/dev/null 2>&1; then
  v=$(helm version --template '{{.Version}}' 2>/dev/null | tr -d 'v')
  if [[ -n $v ]] && version_ge "$v" 3.8.0; then ok helm "$v"; else bad helm "need >= 3.8 for OCI charts (have ${v:-unknown})"; fi
else
  bad helm "install Helm 3.8+ (Windows: winget install Helm.Helm)"
fi

echo "gcloud login:"
if command -v gcloud >/dev/null 2>&1; then
  acct=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)
  acct=$(printf '%s\n' "$acct" | sed -n 1p)
  if [[ -n $acct ]]; then ok "active account" "$acct"; else bad "active account" "none; run: gcloud auth login"; fi
fi

echo "Optional:"
if command -v docker >/dev/null 2>&1; then
  printf '  %-24s OK    %s\n' docker "(only needed for local image builds and offline tests)"
else
  printf '  %-24s --    %s\n' docker "not found (fine for deploys)"
fi

if (( problems > 0 )); then echo "NOT READY: $problems problem(s) above."; exit 1; fi
echo "READY."
