#!/usr/bin/env bash
# Exact Herdr cleanup identity and legacy-record preservation regressions.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
# shellcheck source=bin/fm-herdr.sh
. "$ROOT/bin/fm-herdr.sh"
TEARDOWN="$ROOT/bin/fm-teardown.sh"
TMP_ROOT=$(fm_test_tmproot fm-teardown-endpoint-safety)

write_current() { # <meta> <id>
  local meta=$1 id=$2
  fm_write_meta "$meta" \
    "backend=herdr" "window=lab:w-$id:p1" "endpoint_task_id=$id" \
    "herdr_session=lab" "herdr_workspace_id=w-$id" "herdr_tab_id=t-$id" \
    "herdr_pane_id=w-$id:p1" "worktree=/tmp/$id" "project=/tmp/project" \
    "harness=pi" "kind=ship" "mode=local-only"
}

test_exact_current_metadata_validates() {
  local state=$TMP_ROOT/current id=Task_A.1
  mkdir -p "$state"; write_current "$state/$id.meta" "$id"
  fm_herdr_validate_task_endpoint "$state/$id.meta" "$id" || fail "exact Herdr metadata should validate"
  [ "$FM_HERDR_VALIDATED_TARGET" = "lab:w-$id:p1" ] || fail "exact endpoint identity changed"
  pass "cleanup identity accepts exact current Herdr metadata"
}

test_invalid_and_legacy_metadata_refuse_without_calls() {
  local state=$TMP_ROOT/refuse id=legacy-a out before
  mkdir -p "$state"
  fm_write_meta "$state/$id.meta" "window=firstmate:fm-$id" "worktree=/tmp/$id" "project=/tmp/project"
  before=$(shasum -a 256 "$state/$id.meta" | awk '{print $1}')
  out=$(fm_herdr_validate_task_endpoint "$state/$id.meta" "$id" 2>&1) \
    && fail "fieldless metadata should refuse"
  assert_contains "$out" 'retired legacy tmux metadata' "fieldless refusal did not name preservation"
  [ "$(shasum -a 256 "$state/$id.meta" | awk '{print $1}')" = "$before" ] || fail "fieldless validation rewrote metadata"

  for mutation in missing-window wrong-binding duplicate-backend malformed-target; do
    write_current "$state/$id.meta" "$id"
    case "$mutation" in
      missing-window) grep -v '^window=' "$state/$id.meta" > "$state/$id.tmp" && mv "$state/$id.tmp" "$state/$id.meta" ;;
      wrong-binding) perl -pi -e 's/^endpoint_task_id=.*/endpoint_task_id=other/' "$state/$id.meta" ;;
      duplicate-backend) printf 'backend=herdr\n' >> "$state/$id.meta" ;;
      malformed-target) perl -pi -e 's/^window=.*/window=lab:p1/' "$state/$id.meta" ;;
    esac
    fm_herdr_validate_task_endpoint "$state/$id.meta" "$id" >/dev/null 2>&1 \
      && fail "$mutation metadata should refuse"
  done
  pass "missing, duplicate, malformed, mismatched, and legacy identity all refuse"
}

make_teardown_world() { # <name> <id> <mode>
  local name=$1 id=$2 mode=$3 world home fb
  world=$TMP_ROOT/$name; home=$world/home; fb=$world/fakebin
  mkdir -p "$home/state" "$home/data" "$home/config" "$fb"
  write_current "$home/state/$id.meta" "$id"
  perl -pi -e "s|^worktree=.*|worktree=$world/missing-wt|; s|^project=.*|project=$world/missing-project|" "$home/state/$id.meta"
  cat > "$fb/herdr" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "$FM_HERDR_LOG"
case "${1:-} ${2:-}" in
  "status --json") printf '{"client":{"version":"0.8.0","protocol":19},"server":{"running":true,"protocol":19}}\n' ;;
  "session list")
    [ "${FM_HERDR_TEST_MODE:-}" != unreachable ] || exit 1
    printf '{"sessions":[{"name":"lab","running":true,"socket_path":"%s/herdr.sock"}]}\n' "${FM_HOME:-/tmp}" ;;
  "pane get")
    if [ "${FM_HERDR_TEST_MODE:-}" = ambiguous ]; then printf 'not-json\n'
    else printf '{"error":{"code":"pane_not_found"}}\n'; fi ;;
  *) printf '{"result":{}}\n' ;;
esac
SH
  chmod +x "$fb/herdr"
  fm_fake_exit0 "$fb" treehouse no-mistakes gh gh-axi
  printf '%s|%s|%s\n' "$world" "$home" "$fb"
}

test_unreachable_or_ambiguous_herdr_preserves_records() {
  local mode id=cleanup-a rec world home fb out before
  for mode in unreachable ambiguous; do
    rec=$(make_teardown_world "$mode" "$id" "$mode")
    IFS='|' read -r world home fb <<EOF
$rec
EOF
    before=$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')
    : > "$world/herdr.log"
    out=$(PATH="$fb:$PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$ROOT" \
      FM_HERDR_LOG="$world/herdr.log" FM_HERDR_TEST_MODE="$mode" \
      "$TEARDOWN" "$id" --force 2>&1) && fail "$mode Herdr should refuse cleanup"
    assert_contains "$out" 'nothing was changed' "$mode refusal did not state the preservation boundary"
    [ "$(shasum -a 256 "$home/state/$id.meta" | awk '{print $1}')" = "$before" ] || fail "$mode refusal changed metadata"
  done
  pass "unreachable and ambiguous Herdr stop cleanup with durable records intact"
}

test_exact_current_metadata_validates
test_invalid_and_legacy_metadata_refuse_without_calls
test_unreachable_or_ambiguous_herdr_preserves_records
