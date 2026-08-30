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
printf '%s\n' "\$*" > "\${FM_TEST_GH_ARGS:-/dev/null}"
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
FM_TEST_GH_ARGS="$TMP_ROOT/allowed-api.args" \
  run_policy "$allowed_repo" "$allowed_bin" "$TMP_ROOT/allowed.out" "$TMP_ROOT/allowed.err" \
  || fail "canonical netixc repository was refused: $(cat "$TMP_ROOT/allowed.err")"
[ "$(cat "$TMP_ROOT/allowed.out")" = 'netixc/firstmate' ] \
  || fail "allowed canonical identity was not emitted for native command binding"
assert_contains "$(cat "$TMP_ROOT/allowed-api.args")" '--hostname github.com' \
  "authoritative API lookup was not bound to github.com"
pass "owner policy allows and emits canonical netixc identity through its executable interface"

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
assert_contains "$(cat "$TMP_ROOT/ambiguous.err")" 'origin fetch destination is absent or ambiguous (2 URLs)' \
  "ambiguous-origin refusal was not explicit"
pass "owner policy refuses absent and ambiguous remote evidence"

push_override_repo="$TMP_ROOT/push-override"
make_repo "$push_override_repo" https://github.com/netixc/firstmate.git
git -C "$push_override_repo" remote set-url --push origin git@github.com:octocat/Hello-World.git
rc=0
run_policy "$push_override_repo" "$allowed_bin" "$TMP_ROOT/push-override.out" \
  "$TMP_ROOT/push-override.err" || rc=$?
expect_code 1 "$rc" "a divergent non-netixc push destination must be refused"
assert_contains "$(cat "$TMP_ROOT/push-override.err")" \
  "origin push destination 'octocat/Hello-World' differs from fetch repository 'netixc/firstmate'" \
  "push-destination refusal did not identify both repositories"
pass "owner policy refuses a divergent push destination before caller mutation"

ambiguous_push_repo="$TMP_ROOT/ambiguous-push"
make_repo "$ambiguous_push_repo" https://github.com/netixc/firstmate.git
git -C "$ambiguous_push_repo" remote set-url --push origin \
  https://github.com/netixc/firstmate.git
git -C "$ambiguous_push_repo" remote set-url --add --push origin \
  git@github.com:netixc/firstmate.git
rc=0
run_policy "$ambiguous_push_repo" "$allowed_bin" "$TMP_ROOT/ambiguous-push.out" \
  "$TMP_ROOT/ambiguous-push.err" || rc=$?
expect_code 1 "$rc" "multiple effective push destinations must be refused"
assert_contains "$(cat "$TMP_ROOT/ambiguous-push.err")" \
  'origin push destination is absent or ambiguous (2 URLs)' \
  "ambiguous push-destination refusal was not explicit"
pass "owner policy refuses ambiguous effective push destinations before caller mutation"

rewritten_push_repo="$TMP_ROOT/rewritten-push"
make_repo "$rewritten_push_repo" https://github.com/netixc/firstmate.git
git -C "$rewritten_push_repo" config \
  url.git@github.com:octocat/.pushInsteadOf https://github.com/netixc/
rc=0
run_policy "$rewritten_push_repo" "$allowed_bin" "$TMP_ROOT/rewritten-push.out" \
  "$TMP_ROOT/rewritten-push.err" || rc=$?
expect_code 1 "$rc" "an effective push destination rewritten by pushInsteadOf must be refused"
assert_contains "$(cat "$TMP_ROOT/rewritten-push.err")" \
  "origin push destination 'octocat/firstmate' differs from fetch repository 'netixc/firstmate'" \
  "effective rewritten push-destination refusal did not identify both repositories"
pass "owner policy verifies and refuses an effective pushInsteadOf destination"

same_rewritten_push_repo="$TMP_ROOT/same-rewritten-push"
make_repo "$same_rewritten_push_repo" https://github.com/netixc/firstmate.git
git -C "$same_rewritten_push_repo" config \
  url.git@github.com:netixc/.pushInsteadOf https://github.com/netixc/
run_policy "$same_rewritten_push_repo" "$allowed_bin" "$TMP_ROOT/same-rewritten-push.out" \
  "$TMP_ROOT/same-rewritten-push.err" \
  || fail "equivalent effective push rewrite was refused: $(cat "$TMP_ROOT/same-rewritten-push.err")"
[ "$(cat "$TMP_ROOT/same-rewritten-push.out")" = 'netixc/firstmate' ] \
  || fail "equivalent effective push rewrite did not emit the canonical identity"
pass "owner policy preserves an effective pushInsteadOf destination for the verified repository"

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
