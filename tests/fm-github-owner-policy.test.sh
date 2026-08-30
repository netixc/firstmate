#!/usr/bin/env bash
# Behavioral regression for the public GitHub owner-policy verifier.
# Fake gh-axi responses isolate refusal mechanics; the separately env-gated
# live test proves canonical identity against GitHub itself.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=tests/lib.sh
. "$ROOT/tests/lib.sh"
POLICY="$ROOT/bin/fm-github-owner-policy.sh"
TMP_ROOT=$(fm_test_tmproot fm-github-owner-policy)
trap 'rm -rf "$TMP_ROOT"' EXIT

make_repo() {
  local dir=$1 origin=${2-}
  mkdir -p "$dir"
  git -C "$dir" init -q
  if [ -n "$origin" ]; then
    git -C "$dir" remote add origin "$origin"
  fi
}

make_fake_gh_axi() {
  local dir=$1 owner=$2 name=$3 url=$4
  mkdir -p "$dir"
  cat > "$dir/gh-axi" <<EOF
#!/usr/bin/env bash
printf '%s\n' 'full_name: $name' 'html_url: "$url"' 'owner: $owner'
EOF
  chmod +x "$dir/gh-axi"
}

run_policy() {
  local repo=$1 fakebin=$2 out=$3 err=$4
  PATH="$fakebin:$PATH" "$POLICY" "$repo" >"$out" 2>"$err"
}

allowed_repo="$TMP_ROOT/allowed"
allowed_bin="$TMP_ROOT/allowed-bin"
make_repo "$allowed_repo" https://github.com/netixc/firstmate.git
make_fake_gh_axi "$allowed_bin" netixc netixc/firstmate https://github.com/netixc/firstmate
run_policy "$allowed_repo" "$allowed_bin" "$TMP_ROOT/allowed.out" "$TMP_ROOT/allowed.err" \
  || fail "canonical netixc repository was refused: $(cat "$TMP_ROOT/allowed.err")"
assert_contains "$(cat "$TMP_ROOT/allowed.out")" 'allowed: netixc/firstmate' \
  "allowed canonical identity was not reported"
pass "owner policy allows canonical netixc identity through its executable interface"

other_repo="$TMP_ROOT/other"
other_bin="$TMP_ROOT/other-bin"
make_repo "$other_repo" git@github.com:octocat/Hello-World.git
make_fake_gh_axi "$other_bin" octocat octocat/Hello-World https://github.com/octocat/Hello-World
rc=0
run_policy "$other_repo" "$other_bin" "$TMP_ROOT/other.out" "$TMP_ROOT/other.err" || rc=$?
expect_code 1 "$rc" "non-netixc canonical owner must be refused"
assert_contains "$(cat "$TMP_ROOT/other.err")" "canonical GitHub owner 'octocat' is not allowed" \
  "wrong-owner refusal did not name the canonical owner"
pass "owner policy refuses a non-netixc canonical identity before caller mutation"

missing_repo="$TMP_ROOT/missing"
make_repo "$missing_repo"
rc=0
run_policy "$missing_repo" "$allowed_bin" "$TMP_ROOT/missing.out" "$TMP_ROOT/missing.err" || rc=$?
expect_code 1 "$rc" "missing origin must be refused"
assert_contains "$(cat "$TMP_ROOT/missing.err")" 'no readable origin remote' \
  "missing-origin refusal was not explicit"

ambiguous_repo="$TMP_ROOT/ambiguous"
make_repo "$ambiguous_repo" https://github.com/netixc/firstmate.git
git -C "$ambiguous_repo" remote set-url --add origin git@github.com:netixc/firstmate.git
rc=0
run_policy "$ambiguous_repo" "$allowed_bin" "$TMP_ROOT/ambiguous.out" "$TMP_ROOT/ambiguous.err" || rc=$?
expect_code 1 "$rc" "multiple origin URLs must be refused"
assert_contains "$(cat "$TMP_ROOT/ambiguous.err")" 'origin is absent or ambiguous (2 URLs)' \
  "ambiguous-origin refusal was not explicit"
pass "owner policy refuses absent and ambiguous remote evidence"

incomplete_repo="$TMP_ROOT/incomplete"
incomplete_bin="$TMP_ROOT/incomplete-bin"
make_repo "$incomplete_repo" https://github.com/netixc/firstmate.git
make_fake_gh_axi "$incomplete_bin" netixc netixc/firstmate ''
rc=0
run_policy "$incomplete_repo" "$incomplete_bin" "$TMP_ROOT/incomplete.out" "$TMP_ROOT/incomplete.err" || rc=$?
expect_code 1 "$rc" "incomplete GitHub identity must be refused"
assert_contains "$(cat "$TMP_ROOT/incomplete.err")" 'GitHub repository identity is absent or ambiguous' \
  "incomplete API refusal was not explicit"
pass "owner policy refuses incomplete authoritative GitHub identity"
