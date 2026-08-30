#!/usr/bin/env bash
# Opt-in live behavioral proof for the public GitHub owner-policy verifier.
# This performs read-only repository API calls only. It never invokes a PR or
# issue mutation, and proves a non-netixc repository is refused first.

set -u
[ "${FM_GITHUB_OWNER_POLICY_LIVE:-0}" = 1 ] || {
  echo "skip: set FM_GITHUB_OWNER_POLICY_LIVE=1 for read-only GitHub owner-policy proof"
  exit 0
}

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"
POLICY="$ROOT/bin/fm-github-owner-policy.sh"
TMP_ROOT=$(fm_test_tmproot fm-github-owner-policy-live)
trap 'rm -rf "$TMP_ROOT"' EXIT

make_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" remote add origin "$2"
}

make_repo "$TMP_ROOT/netixc" https://github.com/netixc/firstmate.git
out=$("$POLICY" "$TMP_ROOT/netixc") \
  || fail "live GitHub evidence refused netixc/firstmate"
[ "$out" = 'netixc/firstmate' ] \
  || fail "live GitHub evidence returned unexpected netixc identity: $out"
pass "live GitHub API allows canonical netixc/firstmate"

make_repo "$TMP_ROOT/other" https://github.com/octocat/Hello-World.git
rc=0
mutation_probe="$TMP_ROOT/non-netixc-mutation-attempted"
if out=$("$POLICY" "$TMP_ROOT/other" 2>&1); then
  touch "$mutation_probe"
else
  rc=$?
fi
expect_code 1 "$rc" "live non-netixc GitHub repository must be refused"
assert_contains "$out" "canonical GitHub owner 'octocat' is not allowed" \
  "live non-netixc refusal did not name GitHub's canonical owner"
assert_absent "$mutation_probe" \
  "the caller advanced to its mutation branch after the non-netixc refusal"
pass "live GitHub API refuses canonical octocat/Hello-World before mutation"
