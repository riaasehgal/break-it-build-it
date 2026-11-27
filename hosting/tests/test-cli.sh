#!/usr/bin/env bash
# Argument-validation tests. None of these reach gcloud: validation happens before any cloud call.
set -Euo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fails=0
# expect_fail DESCRIPTION EXPECTED_SUBSTRING CMD... : command must exit non-zero and print substring
expect_fail() {
  local desc=$1 needle=$2 out rc; shift 2
  out=$("$@" 2>&1); rc=$?
  if (( rc != 0 )) && [[ $out == *"$needle"* ]]; then echo "ok   $desc"; else echo "FAIL $desc (rc=$rc, output: ${out:0:200})"; fails=$((fails + 1)); fi
}
expect_ok() {
  local desc=$1 needle=$2 out rc; shift 2
  out=$("$@" 2>&1); rc=$?
  if (( rc == 0 )) && [[ $out == *"$needle"* ]]; then echo "ok   $desc"; else echo "FAIL $desc (rc=$rc, output: ${out:0:200})"; fails=$((fails + 1)); fi
}

expect_ok   "deploy --help"                 "Usage: deploy.sh"          bash "$H/deploy.sh" --help
expect_fail "deploy needs --project"        "--project is required"     bash "$H/deploy.sh"
expect_fail "deploy needs --instances"      "--instances must be"       bash "$H/deploy.sh" --project bibi-test-abc
expect_fail "deploy rejects bad project id" "invalid project ID"        bash "$H/deploy.sh" --project Bad_ID --instances 5
expect_fail "deploy rejects unknown flag"   "unknown argument"          bash "$H/deploy.sh" --bogus
expect_fail "deploy rejects bad phase"      "--stop-after must be one of" bash "$H/deploy.sh" --project bibi-test-abc --instances 5 --stop-after nope
expect_fail "deploy rejects bad buildit img" "--buildit-image must be" bash "$H/deploy.sh" --project bibi-test-abc --instances 5 --buildit-image nodigest
expect_ok   "verify --help"                 "Usage: verify.sh"          bash "$H/verify.sh" --help
expect_fail "verify needs --project"        "--project is required"     bash "$H/verify.sh"
expect_ok   "loadtest --help"               "Usage: loadtest.sh"        bash "$H/loadtest.sh" --help
expect_fail "loadtest needs a target"       "--url or --project"        bash "$H/loadtest.sh" --teams 3
expect_fail "loadtest validates prefix"     "prefix must be"            bash "$H/loadtest.sh" --url http://127.0.0.1 --teams 3 --prefix BAD
expect_fail "loadtest validates teams"      "--teams must be"           bash "$H/loadtest.sh" --url http://127.0.0.1 --teams x
expect_ok   "teardown --help"               "Usage: teardown.sh"        bash "$H/teardown.sh" --help
expect_fail "teardown needs --mode"         "--mode must be"            bash "$H/teardown.sh" --project bibi-test-abc
expect_fail "teardown needs --project"      "--project is required"     bash "$H/teardown.sh" --mode project

(( fails == 0 )) || { echo "$fails CLI test(s) failed"; exit 1; }
echo "all CLI tests passed"
