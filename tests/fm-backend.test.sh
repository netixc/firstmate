#!/usr/bin/env bash
# tests/fm-backend.test.sh - P1 runtime-backend extraction conformance
# (data/fm-backend-design-d7/report.md, herdr-addendum.md "events as the core
# abstraction"). bin/fm-backend.sh and bin/backends/tmux.sh move the tmux
# command sequences that fm-send.sh, fm-peek.sh, fm-spawn.sh, and
# fm-teardown.sh used to run inline into named adapter functions. This suite:
#
#   1. Unit-tests bin/fm-backend.sh's selection, meta, and dispatch helpers.
#   2. Runs the PRE-REFACTOR versions of fm-send.sh, fm-peek.sh, fm-spawn.sh,
#      and fm-teardown.sh (checked out from the merge-base with `main`, the
#      commit this branch started from) against the SAME fake tmux/treehouse
#      binaries and fixtures as the REFACTORED versions in this checkout, then
#      diffs the two command logs byte-for-byte - the report's P1 checklist
#      item "run current main scripts and refactored scripts against the same
#      fake tools and compare command logs". The teardown old-vs-new case also
#      overlays a content-historical permissive tmux kill fixture: after the
#      exact-selector change lands on the default branch, merge-base with main
#      collapses to HEAD and can no longer supply that baseline.
#   3. Asserts the `--backend`/`FM_BACKEND` selection refuses unknown backends
#      and the blocked `codex-app` backend loudly.
#
# fm-watch.sh's signal/stale/check/heartbeat wake-string contract is already
# exercised end-to-end against this refactor by tests/fm-watch-triage.test.sh
# and tests/wake-helpers.sh (same fake-tmux convention, run against the
# now-refactored bin/fm-watch.sh); this suite adds one direct old-vs-new
# diff for the stale-pane path specifically, since that is the one wake path
# that now calls through fm_backend_capture instead of tmux directly.
# The real tmux smoke test (create session, send text + Enter, capture, list,
# kill) lives in tests/fm-backend-tmux-smoke.test.sh.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
fm_git_identity fmtest fmtest@example.invalid

# shellcheck source=/dev/null
. "$ROOT/bin/fm-backend.sh"

TMP_ROOT=$(fm_test_tmproot fm-backend-tests)

# The commit this branch started from - the P1 "current main" baseline.
# Suitable for byte-identical old-vs-new checks while a branch still diverges
# from main. After a squash lands, merge-base(HEAD, main) collapses to HEAD, so
# callers that need a true pre-change fixture must not rely on this alone.
resolve_base_ref() {
  local ref base
  for ref in main refs/heads/main origin/main refs/remotes/origin/main origin/HEAD refs/remotes/origin/HEAD; do
    if git -C "$ROOT" rev-parse --verify -q "$ref^{commit}" >/dev/null; then
      base=$(git -C "$ROOT" merge-base HEAD "$ref" 2>/dev/null) || continue
      [ -n "$base" ] || continue
      printf '%s\n' "$base"
      return 0
    fi
  done
  return 1
}
BASE_REF=$(resolve_base_ref) \
  || fail "fm-backend baseline requires local main or origin/main; fetch the default branch before running this test"

# Newest first-parent revision whose bin/backends/tmux.sh still uses the
# pre-exact permissive kill-window target. Content-addressed from history so the
# fixture stays historical on default-branch CI and on branches cut after the
# exact-selector change, where merge-base with main is self-referential.
resolve_permissive_tmux_kill_ref() {
  local commit body
  while IFS= read -r commit; do
    [ -n "$commit" ] || continue
    body=$(git -C "$ROOT" show "$commit:bin/backends/tmux.sh" 2>/dev/null) || continue
    # shellcheck disable=SC2016
    case "$body" in
      *'tmux kill-window -t "=$session:=$window"'*) continue ;;
    esac
    # shellcheck disable=SC2016
    case "$body" in
      *'tmux kill-window -t "$1"'*|*'tmux kill-window -t "$target"'*)
        printf '%s\n' "$commit"
        return 0
        ;;
    esac
  done < <(git -C "$ROOT" log --first-parent --format='%H' HEAD -- bin/backends/tmux.sh)
  return 1
}

# --- shared: a pre-refactor bin/ shim --------------------------------------
#
# build_old_bin echoes a directory whose bin/ subdir is the complete bin/ tree
# from BASE_REF.
# Materializing the whole historical tree keeps every entrypoint and sourced
# sibling on the same revision, while avoiding a hand-maintained dependency
# list that can omit a newly sourced helper and make the old process abort
# before it reaches the behavior under test.
# FM_ROOT_OVERRIDE pointed at this dir's root makes
# "$FM_ROOT/bin/fm-project-mode.sh" (etc.) resolve correctly.
# The teardown conformance case applies its explicitly historical tmux adapter
# after this complete baseline has been materialized.

build_old_bin() {  # <name> -> echoes root dir (root/bin/<script> is the entry point)
  local name=$1 root archive
  root="$TMP_ROOT/$name"
  archive="$root/bin.tar"
  mkdir -p "$root"
  git -C "$ROOT" archive --format=tar "$BASE_REF" bin > "$archive" \
    || fail "old-bin shim: could not archive bin/ from $BASE_REF"
  tar -xf "$archive" -C "$root" \
    || fail "old-bin shim: could not extract bin/ from $BASE_REF"
  rm -f "$archive"
  printf '%s\n' "$root"
}

# --- fm-backend.sh unit tests ------------------------------------------------

test_backend_name_precedence() {
  local dir cfg
  dir="$TMP_ROOT/name-precedence"; cfg="$dir/config"
  mkdir -p "$cfg"
  [ "$(unset TMUX HERDR_ENV; FM_BACKEND='' FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name)" = tmux ] \
    || fail "fm_backend_name should default to tmux with no markers"
  printf 'herdr\n' > "$cfg/backend"
  [ "$(unset TMUX HERDR_ENV; FM_BACKEND='' FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name)" = herdr ] \
    || fail "fm_backend_name should read config/backend"
  [ "$(unset TMUX HERDR_ENV; FM_BACKEND=tmux FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name)" = tmux ] \
    || fail "FM_BACKEND should win over config/backend"
  pass "fm_backend_name: FM_BACKEND > config/backend > default tmux"
}

# fm_backend_detect: environment-marker runtime auto-detection.
# Every case explicitly controls TMUX and HERDR_ENV so ambient shell markers
# cannot influence the result.
test_backend_detect_precedence() {
  local out
  if out=$(unset TMUX HERDR_ENV; fm_backend_detect); then
    fail "fm_backend_detect should be undetected with no markers, got '$out'"
  fi
  out=$(unset TMUX; HERDR_ENV=1 fm_backend_detect) || fail "HERDR_ENV should detect Herdr"
  [ "$out" = herdr ] || fail "HERDR_ENV should report herdr, got '$out'"
  out=$(unset HERDR_ENV; TMUX='fake,1,0' fm_backend_detect) || fail "TMUX should detect tmux"
  [ "$out" = tmux ] || fail "TMUX should report tmux, got '$out'"
  out=$(TMUX='fake,1,0' HERDR_ENV=1 fm_backend_detect) || fail "nested markers should detect"
  [ "$out" = tmux ] || fail "tmux should win over Herdr, got '$out'"
  pass "fm_backend_detect: tmux and Herdr markers resolve innermost-first"
}

# fm_backend_name's auto-detect step fires only when FM_BACKEND and
# config/backend are absent, and it stays silent for tmux while notifying for Herdr.
test_backend_name_autodetect_notice() {
  local dir cfg out errfile
  dir="$TMP_ROOT/name-autodetect"; cfg="$dir/config-empty"; mkdir -p "$cfg"
  errfile="$dir/err.txt"
  out=$(unset TMUX HERDR_ENV; FM_BACKEND='' FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name 2>"$errfile")
  [ "$out" = tmux ] || fail "no markers should default to tmux, got '$out'"
  [ ! -s "$errfile" ] || fail "default tmux should stay silent"
  out=$(unset TMUX; HERDR_ENV=1 FM_BACKEND='' FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name 2>"$errfile")
  [ "$out" = herdr ] || fail "HERDR_ENV should auto-detect Herdr, got '$out'"
  assert_contains "$(cat "$errfile")" "EXPERIMENTAL herdr backend" "Herdr auto-detection should print its notice"
  out=$(unset HERDR_ENV; TMUX='fake,1,0' FM_BACKEND='' FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name 2>"$errfile")
  [ "$out" = tmux ] || fail "TMUX should auto-detect tmux, got '$out'"
  [ ! -s "$errfile" ] || fail "auto-detected tmux should stay silent"
  out=$(TMUX='fake,1,0' HERDR_ENV=1 FM_BACKEND='' FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name 2>"$errfile")
  [ "$out" = tmux ] || fail "nested tmux should win, got '$out'"
  [ ! -s "$errfile" ] || fail "nested tmux should stay silent"
  pass "fm_backend_name: Herdr detection is loud and tmux detection is silent"
}

# Explicit configuration (FM_BACKEND env or config/backend) always wins over
# runtime auto-detection, even when a detection marker points the other way.
test_backend_name_explicit_beats_detection() {
  local dir cfg out
  dir="$TMP_ROOT/name-explicit-beats-detect"
  cfg="$dir/config-tmux"; mkdir -p "$cfg" "$dir/config-empty"; printf 'tmux\n' > "$cfg/backend"
  out=$(unset TMUX; HERDR_ENV=1 FM_BACKEND=tmux FM_BACKEND_CONFIG_DIR="$dir/config-empty" fm_backend_name)
  [ "$out" = tmux ] || fail "FM_BACKEND should beat Herdr auto-detection"
  out=$(unset TMUX; HERDR_ENV=1 FM_BACKEND='' FM_BACKEND_CONFIG_DIR="$cfg" fm_backend_name)
  [ "$out" = tmux ] || fail "config/backend should beat Herdr auto-detection"
  pass "fm_backend_name: explicit settings beat runtime auto-detection"
}

test_backend_validate_refuses_unknown() {
  local out backend
  for backend in tmux herdr; do
    fm_backend_validate "$backend" 2>/dev/null || fail "fm_backend_validate should accept $backend"
  done
  for backend in bogus codex-app "tmux herdr"; do
    out=$(fm_backend_validate "$backend" 2>&1) && fail "fm_backend_validate should refuse $backend"
    assert_contains "$out" "unknown backend '$backend'" "validation should name rejected backend $backend"
  done
  pass "fm_backend_validate: exactly tmux and Herdr are accepted"
}

test_backend_source_shell_portable() {
  local out status
  # zsh does not word-split unquoted expansions; sourcing fm-backend.sh from
  # an interactive zsh session must still recognize known backend names.
  if command -v zsh >/dev/null 2>&1; then
    zsh -c "cd '$ROOT' && source bin/fm-backend.sh && fm_backend_source herdr && whence -w fm_backend_herdr_capture >/dev/null" 2>/dev/null \
      || fail "zsh: fm_backend_source herdr should load the adapter when sourced"
    out=$(zsh -c "cd '$ROOT' && source bin/fm-backend.sh && fm_backend_source bogus" 2>&1) \
      && fail "zsh: fm_backend_source bogus should fail"
    assert_contains "$out" "unknown backend 'bogus'" \
      "zsh: fm_backend_source did not reject bogus with the expected error"
    pass "zsh: fm_backend_source recognizes known backends and rejects unknown ones"
  else
    pass "zsh: shell-portable backend matching skipped (zsh not found)"
  fi

  bash -c "cd '$ROOT' && source bin/fm-backend.sh && fm_backend_source herdr && declare -F fm_backend_herdr_capture >/dev/null" 2>/dev/null \
    || fail "bash: fm_backend_source herdr should load the adapter when sourced"
  out=$(bash -c "cd '$ROOT' && source bin/fm-backend.sh && fm_backend_source bogus" 2>&1) \
    && fail "bash: fm_backend_source bogus should fail"
  assert_contains "$out" "unknown backend 'bogus'" \
    "bash: fm_backend_source did not reject bogus with the expected error"
  pass "bash: fm_backend_source recognizes known backends and rejects unknown ones"
}

test_backend_validate_spawn_accepts_supported() {
  local out backend
  for backend in tmux herdr; do
    fm_backend_validate_spawn "$backend" 2>/dev/null || fail "spawn validation should accept $backend"
  done
  for backend in bogus codex-app "tmux herdr"; do
    out=$(fm_backend_validate_spawn "$backend" 2>&1) && fail "spawn validation should refuse $backend"
    assert_contains "$out" "unknown backend '$backend'" "spawn validation should name $backend"
  done
  pass "fm_backend_validate_spawn: exactly tmux and Herdr are spawn-supported"
}

test_meta_get_and_backend_of_meta() {
  local meta=$TMP_ROOT/meta-get.meta
  fm_write_meta "$meta" "window=firstmate:fm-x1" "harness=pi"
  [ "$(fm_meta_get "$meta" window)" = "firstmate:fm-x1" ] || fail "fm_meta_get did not read window="
  [ "$(fm_meta_get "$meta" missing)" = "" ] || fail "fm_meta_get should print nothing for an absent key"
  [ "$(fm_backend_of_meta "$meta")" = tmux ] || fail "fm_backend_of_meta should default absent backend= to tmux"

  printf 'backend=tmux\n' >> "$meta"
  [ "$(fm_backend_of_meta "$meta")" = tmux ] || fail "fm_backend_of_meta should read an explicit backend=tmux"

  pass "fm_meta_get / fm_backend_of_meta: read key=value, default backend to tmux"
}

test_resolve_selector_three_forms() {
  local state=$TMP_ROOT/resolve-state fakebin out
  mkdir -p "$state"
  fm_write_meta "$state/task1.meta" "window=firstmate:fm-task1"
  fm_write_meta "$state/dotfiles-d6.meta" "window=default:wA:p2" "backend=herdr"
  fm_write_meta "$state/fm-turnend-all-harnesses-v9.meta" "window=default:wB:p3" "backend=herdr"

  [ "$(fm_backend_resolve_selector 'sess:win' "$state")" = "sess:win" ] \
    || fail "explicit session:window should be used as-is"

  [ "$(fm_backend_resolve_selector 'dotfiles-d6' "$state")" = "default:wA:p2" ] \
    || fail "bare non-fm task id should resolve through exact metadata"
  [ "$(fm_backend_of_selector 'dotfiles-d6' 'default:wA:p2' "$state")" = herdr ] \
    || fail "bare non-fm task id should use its recorded backend"
  [ "$(fm_backend_expected_label_of_selector 'dotfiles-d6' "$state")" = "fm-dotfiles-d6" ] \
    || fail "bare non-fm task id should report the spawned fm-<id> label"

  [ "$(fm_backend_resolve_selector 'fm-turnend-all-harnesses-v9' "$state")" = "default:wB:p3" ] \
    || fail "exact fm-* task id should resolve through its exact metadata"
  [ "$(fm_backend_of_selector 'fm-turnend-all-harnesses-v9' 'default:wB:p3' "$state")" = herdr ] \
    || fail "exact fm-* task id should use exact metadata without stripping fm-"
  [ "$(fm_backend_expected_label_of_selector 'fm-turnend-all-harnesses-v9' "$state")" = "fm-fm-turnend-all-harnesses-v9" ] \
    || fail "exact fm-* task id should report the spawned fm-<id> label"

  [ "$(fm_backend_resolve_selector 'fm-task1' "$state")" = "firstmate:fm-task1" ] \
    || fail "legacy fm-<id> label should resolve through <id>.meta's window="
  [ "$(fm_backend_expected_label_of_selector 'fm-task1' "$state")" = "fm-task1" ] \
    || fail "legacy fm-<id> label should preserve its backend label"

  out=$(fm_backend_resolve_selector 'fm-missing' "$state" 2>&1) && fail "fm-<id> with no meta should fail"
  assert_contains "$out" "no metadata for fm-missing" "missing-meta error text changed"

  fakebin="$TMP_ROOT/resolve-fakebin"; mkdir -p "$fakebin"
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  list-windows) printf 'firstmate:adhoc\nother:otherwin\n' ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  out=$(PATH="$fakebin:$PATH" fm_backend_resolve_selector 'fm-adhoc' "$state" 2>&1) || true
  # fm-adhoc carries no meta file, so it is NOT the bare-name fallback path - it
  # is the fm-* meta-miss error path after exact-id and legacy-label metadata
  # lookup both miss.
  # Only a NON fm-* bare name falls through to the live-window search.
  assert_contains "$out" "no metadata for fm-adhoc" "an fm-* selector must always require meta, not silently fall back to a live search"

  out=$(PATH="$fakebin:$PATH" fm_backend_resolve_selector 'adhoc' "$state")
  [ "$out" = "firstmate:adhoc" ] || fail "an ad hoc bare name should resolve via the tmux live-window fallback, got '$out'"

  pass "fm_backend_resolve_selector: session:window literal, exact task id first, legacy fm-<id> label fallback, ad hoc bare name via tmux list-windows"
}

test_backend_of_selector_matches_explicit_target_meta() {
  local state=$TMP_ROOT/backend-selector-state
  mkdir -p "$state"
  fm_write_meta "$state/herdr-task.meta" "window=default:w1:p2" "backend=herdr"
  fm_write_meta "$state/dotfiles-d6.meta" "window=default:wA:p2" "backend=herdr"
  fm_write_meta "$state/fm-turnend-all-harnesses-v9.meta" "window=default:wB:p3" "backend=herdr"
  fm_write_meta "$state/tmux-task.meta" "window=firstmate:fm-tmux-task"
  fm_write_meta "$state/custom-window-task.meta" "window=custom-window"
  [ "$(fm_backend_of_selector 'dotfiles-d6' 'default:wA:p2' "$state")" = herdr ] || fail "task id should use recorded Herdr backend"
  [ "$(fm_backend_of_selector 'fm-turnend-all-harnesses-v9' 'default:wB:p3' "$state")" = herdr ] || fail "exact fm-prefixed id should win"
  [ "$(fm_backend_of_selector 'fm-herdr-task' 'default:w1:p2' "$state")" = herdr ] || fail "legacy label should use recorded Herdr backend"
  [ "$(fm_backend_resolve_selector 'custom-window' "$state")" = custom-window ] || fail "recorded window should not need live fallback"
  [ "$(fm_backend_of_selector 'default:w1:p2' 'default:w1:p2' "$state")" = herdr ] || fail "explicit target should recover Herdr metadata"
  [ "$(fm_backend_of_selector 'firstmate:fm-tmux-task' 'firstmate:fm-tmux-task' "$state")" = tmux ] || fail "missing backend should mean tmux"
  [ "$(fm_backend_of_selector 'manual:outside' 'manual:outside' "$state")" = tmux ] || fail "unmatched explicit target should default to tmux"
  pass "fm_backend_of_selector routes tmux and Herdr metadata through public selectors"
}

# --- old vs new: fm-send.sh --------------------------------------------------

make_send_fakebin() {  # <dir> -> echoes fakebin dir; logs every tmux call to $FM_TMUX_LOG
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
{ printf 'tmux'; for a in "$@"; do printf '\x1f%s' "$a"; done; printf '\n'; } >> "${FM_TMUX_LOG:?}"
case "${1:-}" in
  send-keys) exit 0 ;;
  display-message)
    for a in "$@"; do case "$a" in *cursor_y*) printf '1\n'; exit 0 ;; esac; done
    printf 'fakepane\n'; exit 0 ;;
  capture-pane)
    start= end=
    while [ $# -gt 0 ]; do
      case "$1" in
        -S) start=$2; shift 2 ;;
        -E) end=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ "$start" = 1 ] && [ "$end" = 1 ]; then
      printf '│    │\n'
    else
      printf '╭────╮\n│    │\n╰────╯\n'
    fi
    exit 0 ;;
  list-windows) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  printf '%s\n' "$fb"
}

run_send_case() {  # <bin-root> <fakebin> <log> <home> -- <send args...>
  local bin=$1 fb=$2 log=$3 home=$4; shift 4
  [ "${1:-}" = -- ] && shift
  : > "$log"
  env PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$bin" FM_HOME="$home" FM_TMUX_LOG="$log" \
    FM_SEND_SETTLE=0 FM_SEND_SLEEP=0 \
    "$bin/bin/fm-send.sh" "$@" >/dev/null 2>&1
}

strip_send_preflight() {  # <log>
  local preflight
  preflight=$'tmux\x1fdisplay-message\x1f-p\x1f-t\x1fsess:win\x1f#{pane_id}'
  awk -v preflight="$preflight" '$0 != preflight { print }' "$1"
}

# The byte-identical old-vs-new tmux log comparison this test used to run
# covered the P1 backend extraction, which promised an unchanged command
# sequence. The composer consolidation (fm-composer-thin-adapter-refactor-r1)
# deliberately changed that sequence - the submit core reads a busy baseline
# before typing (its idle-to-busy turn-started confirmation) and the composer
# verdict comes from one full styled capture instead of a second band capture -
# so the current contract is asserted directly instead.
test_send_tmux_contract() {
  local fb log home rc
  fb=$(make_send_fakebin "$TMP_ROOT/send-fake")
  home="$TMP_ROOT/send-home"; mkdir -p "$home/state"
  log="$TMP_ROOT/send-new.log"

  # Case 1: --key path - target verified, named key sent, no typing.
  run_send_case "$ROOT" "$fb" "$log" "$home" -- "sess:win" --key Escape
  rc=$?
  expect_code 0 "$rc" "fm-send --key should succeed against a live fake pane"
  assert_contains "$(cat "$log")" $'\x1f''display-message'$'\x1f''-p'$'\x1f''-t'$'\x1f''sess:win'$'\x1f''#{pane_id}' \
    "fm-send --key did not verify the explicit tmux target before sending"
  assert_contains "$(cat "$log")" $'\x1f''Escape' "fm-send --key did not send the named key"
  assert_not_contains "$(cat "$log")" $'\x1f''-l'$'\x1f' "fm-send --key must not type literal text"

  # Case 2: plain text - typed literally exactly once, submitted with Enter,
  # confirmed against the bordered-empty fake composer.
  run_send_case "$ROOT" "$fb" "$log" "$home" -- "sess:win" hello captain
  rc=$?
  expect_code 0 "$rc" "fm-send plain text should confirm against the empty fake composer"
  assert_contains "$(cat "$log")" $'\x1f''send-keys'$'\x1f''-t'$'\x1f''sess:win'$'\x1f''-l'$'\x1f''hello captain' \
    "fm-send did not send the literal text with send-keys -l"
  [ "$(grep -c $'\x1f''-l'$'\x1f' "$log")" -eq 1 ] \
    || fail "fm-send must type the text exactly once (Enter-only retries, never a retype)"
  assert_contains "$(cat "$log")" $'\x1f''Enter' "fm-send did not submit with Enter"

  # Case 3: a slash command still opens the popup-settle path (verified in
  # tests/fm-send-popup-settle.test.sh) and ends in the same command shape:
  # one literal type, then Enter.
  run_send_case "$ROOT" "$fb" "$log" "$home" -- "sess:win" /some-skill
  rc=$?
  expect_code 0 "$rc" "fm-send /skill should confirm against the empty fake composer"
  assert_contains "$(cat "$log")" $'\x1f''send-keys'$'\x1f''-t'$'\x1f''sess:win'$'\x1f''-l'$'\x1f''/some-skill' \
    "fm-send /skill did not type the literal slash command"
  [ "$(grep -c $'\x1f''-l'$'\x1f' "$log")" -eq 1 ] \
    || fail "fm-send /skill must type the text exactly once"

  pass "fm-send.sh: explicit tmux targets are verified; text types once and submits with Enter"
}

# --- old vs new: fm-peek.sh --------------------------------------------------

make_peek_fakebin() {  # <dir> <capture-output> -> echoes fakebin dir
  local dir=$1 payload=$2 fb="$1/fakebin"
  mkdir -p "$fb"
  printf '%s' "$payload" > "$dir/capture.out"
  cat > "$fb/tmux" <<SH
#!/usr/bin/env bash
set -u
{ printf 'tmux'; for a in "\$@"; do printf '\\x1f%s' "\$a"; done; printf '\\n'; } >> "\${FM_TMUX_LOG:?}"
case "\${1:-}" in
  capture-pane) cat "$dir/capture.out" ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  printf '%s\n' "$fb"
}

test_peek_conformance_old_vs_new() {
  local old_bin fb log_old log_new home out_old out_new payload neutral_root
  payload=$'line one\nline two\ncaptain on deck'
  old_bin=$(build_old_bin peek-old)
  fb=$(make_peek_fakebin "$TMP_ROOT/peek-fake" "$payload")
  home="$TMP_ROOT/peek-home"; mkdir -p "$home/state"
  log_old="$TMP_ROOT/peek-old.log"; log_new="$TMP_ROOT/peek-new.log"
  # A fresh non-git dir keeps fm-guard.sh's worktree-tangle check inert (it warns
  # to stderr, discarded below) - neither run needs FM_ROOT for anything beyond
  # that guard, since STATE/HOME are already overridden directly.
  neutral_root="$TMP_ROOT/peek-neutral-root"; mkdir -p "$neutral_root"

  : > "$log_old"
  out_old=$(PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$neutral_root" FM_HOME="$home" FM_TMUX_LOG="$log_old" \
    "$old_bin/bin/fm-peek.sh" "sess:win" 25 2>/dev/null)
  : > "$log_new"
  out_new=$(PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$neutral_root" FM_HOME="$home" FM_TMUX_LOG="$log_new" \
    "$ROOT/bin/fm-peek.sh" "sess:win" 25 2>/dev/null)

  [ "$out_old" = "$out_new" ] || fail "fm-peek output differs old vs new"$'\n'"--- old ---"$'\n'"$out_old"$'\n'"--- new ---"$'\n'"$out_new"
  [ "$out_new" = "$payload" ] || fail "fm-peek did not pass through the fake capture-pane output exactly"
  diff -u "$log_old" "$log_new" > "$TMP_ROOT/peek-diff.txt" 2>&1 \
    || fail "fm-peek: tmux command log differs old vs new"$'\n'"$(cat "$TMP_ROOT/peek-diff.txt")"
  assert_contains "$(cat "$log_new")" $'\x1f''capture-pane'$'\x1f''-p'$'\x1f''-t'$'\x1f''sess:win'$'\x1f''-S'$'\x1f''-25' \
    "fm-peek did not call capture-pane -p -t <target> -S -<lines> exactly"

  pass "fm-peek.sh: capture-pane invocation and output are byte-identical old vs new"
}

# --- old vs new: fm-spawn.sh --------------------------------------------------

make_spawn_fakebin() {  # <dir> <fake-worktree-path> -> echoes fakebin dir
  local dir=$1 wt=$2 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<SH
#!/usr/bin/env bash
set -u
{ printf 'tmux'; for a in "\$@"; do printf '\\x1f%s' "\$a"; done; printf '\\n'; } >> "\${FM_TMUX_LOG:?}"
case "\${1:-}" in
  display-message)
    for a in "\$@"; do case "\$a" in *pane_current_path*) printf '%s\\n' "$wt"; exit 0 ;; esac; done
    printf 'firstmate\\n'; exit 0 ;;
  list-windows) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  fm_fake_exit0 "$fb" treehouse
  printf '%s\n' "$fb"
}

run_spawn_case() {  # <bin-root> <fakebin> <log> <state> <data> <config> <proj> -- <spawn args...>
  local bin=$1 fb=$2 log=$3 state=$4 data=$5 config=$6 proj=$7; shift 7
  [ "${1:-}" = -- ] && shift
  : > "$log"
  env PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$bin" \
    FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
    FM_PROJECTS_OVERRIDE="$TMP_ROOT/unused-projects" \
    FM_SPAWN_NO_GUARD=1 TMUX="fake,1,0" FM_TMUX_LOG="$log" \
    "$bin/bin/fm-spawn.sh" "$@"
}

# NOTE: the old-vs-new spawn command-log conformance test that used to live here
# was retired. It asserted the P1 backend refactor was a byte-for-byte pure
# extraction of the spawn window-creation/targeting sequence, but that sequence
# is now DELIBERATELY changed: fm-spawn drives the tmux backend to capture a
# stable window id, pin the window name (automatic-rename/allow-rename off), and
# target that id for the rename-critical spawn steps (robustness under a
# captain's non-default tmux config). A byte-identical old-vs-new diff can no
# longer hold there by design. That intended sequence is now authoritatively and
# comprehensively verified - via a recording fake-tmux - by
# tests/fm-tangle-guard.test.sh ("fm-spawn: appends windows by session-colon,
# pins the name, and targets the window id"), and the real tmux create/kill path
# by tests/fm-backend-tmux-smoke.test.sh. The send/peek/teardown conformance
# tests below remain pure extractions and stay. (make_spawn_fakebin and
# run_spawn_case are retained: test_spawn_default_backend_writes_no_meta_field
# uses make_spawn_fakebin, and #294's run_spawn_symlink_case uses run_spawn_case.)

# --- symlinked project prefix must not false-refuse the isolation guard -----
#
# docs/herdr-backend.md "Known gaps": a real backend's pane_current_path read
# (tmux, herdr) reports the OS-level PHYSICALLY-resolved cwd. When the project
# itself lives under a symlinked prefix (e.g. macOS's /tmp -> /private/tmp),
# fm-spawn.sh's PROJ_ABS - a logical `cd && pwd` - differs string-for-string
# from that physical read even before treehouse moves the pane at all, so the
# worktree-discovery poll used to mistake an UNMOVED pane for one that had
# already left the project, handing validate_spawn_worktree the project's own
# directory as "the worktree" and tripping its false isolation refusal.
# make_spawn_symlink_fakebin's tmux stub returns an unmoved project path on the
# first pane_current_path poll, then the real worktree path from the second poll
# onward, so this test fails loudly if the PROJ_ABS/PROJ_ABS_REAL
# canonicalization in bin/fm-spawn.sh ever regresses.
make_spawn_symlink_fakebin() {  # <dir> <initial-project-path> <worktree-path> -> echoes fakebin dir
  local dir=$1 initial_path=$2 wt=$3 fb="$1/fakebin" counter="$1/poll-count"
  mkdir -p "$fb"
  : > "$counter"
  cat > "$fb/tmux" <<SH
#!/usr/bin/env bash
set -u
{ printf 'tmux'; for a in "\$@"; do printf '\\x1f%s' "\$a"; done; printf '\\n'; } >> "\${FM_TMUX_LOG:?}"
case "\${1:-}" in
  display-message)
    for a in "\$@"; do case "\$a" in *pane_current_path*)
      printf x >> "$counter"
      if [ "\$(wc -c < "$counter")" -le 1 ]; then
        printf '%s\\n' "$initial_path"
      else
        printf '%s\\n' "$wt"
      fi
      exit 0
    ;; esac; done
    printf 'firstmate\\n'; exit 0 ;;
  list-windows) exit 0 ;;
esac
exit 0
SH
  chmod +x "$fb/tmux"
  fm_fake_exit0 "$fb" treehouse
  printf '%s\n' "$fb"
}

run_spawn_symlink_case() {  # <label> <physical|logical>
  local label=$1 first_reply=$2 real_root link_root proj wt id fb data state config log out rc proj_phys initial_path
  real_root="$TMP_ROOT/symlink-real-$label"; link_root="$TMP_ROOT/symlink-link-$label"
  mkdir -p "$real_root"
  ln -s "$real_root" "$link_root"
  proj="$link_root/proj"
  wt="$TMP_ROOT/symlink-wt-$label"
  id="spawnsymlink$label"
  fm_git_worktree "$real_root/proj" "$wt" "fm/$id"
  # TMP_ROOT itself can already sit behind an OS-level symlink (e.g. macOS's
  # /var -> /private/var), so resolve the fakebin's "physical" reply with
  # pwd -P rather than string concatenation - it must match exactly what
  # fm-spawn.sh's own PROJ_ABS_REAL computes, including any symlink layers
  # ABOVE this test's own synthetic real_root/link_root pair.
  proj_phys=$(cd "$real_root/proj" && pwd -P)
  case "$first_reply" in
    physical) initial_path=$proj_phys ;;
    logical) initial_path=$proj ;;
    *) fail "unknown symlink first-reply mode: $first_reply" ;;
  esac
  fb=$(make_spawn_symlink_fakebin "$TMP_ROOT/symlink-fake-$label" "$initial_path" "$wt")
  data="$TMP_ROOT/symlink-data-$label"
  mkdir -p "$data/$id"
  printf 'test brief content\n' > "$data/$id/brief.md"
  state="$TMP_ROOT/symlink-state-$label"; config="$TMP_ROOT/symlink-config-$label"
  mkdir -p "$state" "$config"
  log="$TMP_ROOT/symlink-spawn-$label.log"

  out=$(run_spawn_case "$ROOT" "$fb" "$log" "$state" "$data" "$config" "$proj" -- "$id" "$proj" pi --mode no-mistakes --yolo off 2>&1)
  rc=$?
  expect_code 0 "$rc" "fm-spawn.sh should succeed for a project reached through a symlinked prefix when the backend reports $first_reply cwd"$'\n'"$out"
  assert_contains "$out" "worktree=$wt" \
    "fm-spawn.sh did not resolve a symlinked-prefix project to its real worktree when the backend reports $first_reply cwd"

  rm -rf "/tmp/fm-$id"
}

test_spawn_symlinked_project_prefix_avoids_false_refusal() {
  run_spawn_symlink_case physical physical
  run_spawn_symlink_case logical logical
  pass "fm-spawn.sh: a project reached through a symlinked prefix (e.g. macOS /tmp -> /private/tmp) does not trip the isolation guard's false refusal"
}

# --- old vs new: fm-teardown.sh ----------------------------------------------

make_teardown_fakebin() {  # <dir> -> echoes fakebin dir; logs tmux+treehouse calls
  local dir=$1 fb="$1/fakebin"
  mkdir -p "$fb"
  cat > "$fb/tmux" <<'SH'
#!/usr/bin/env bash
set -u
{ printf 'tmux'; for a in "$@"; do printf '\x1f%s' "$a"; done; printf '\n'; } >> "${FM_TMUX_LOG:?}"
exit 0
SH
  cat > "$fb/treehouse" <<'SH'
#!/usr/bin/env bash
set -u
{ printf 'treehouse'; for a in "$@"; do printf '\x1f%s' "$a"; done; printf '\n'; } >> "${FM_TMUX_LOG:?}"
exit 0
SH
  chmod +x "$fb/tmux" "$fb/treehouse"
  printf '%s\n' "$fb"
}

# run_teardown_case <script> <fm-root-override> <fakebin> <log> <state> <data> <config> <id>
# FM_ROOT_OVERRIDE is passed separately from <script> so both the old and new
# runs can point it at the SAME neutral (non-git) shim root - that root's
# bin/fm-guard.sh is a symlink to the real, unchanged script, so the
# worktree-tangle check runs identically (and silently) for both, regardless
# of which fm-teardown.sh (old or new) is actually being invoked.
run_teardown_case() {
  local script=$1 fmroot=$2 fb=$3 log=$4 state=$5 data=$6 config=$7 id=$8
  : > "$log"
  env PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$fmroot" \
    FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
    FM_TMUX_LOG="$log" \
    "$script" "$id"
}

test_teardown_conformance_old_vs_new() {
  local old_bin fb proj wt id old_tmux_ref saved_base_ref
  local state_old state_new config_old config_new data log_old log_new out_old out_new rc_old rc_new
  # Force the post-squash topology inside this case: merge-base with main may
  # equal HEAD on default-branch CI, and that must not make the legacy kill
  # fixture self-referential. build_old_bin still uses BASE_REF for entrypoints;
  # only the tmux kill adapter is pinned to the content-historical permissive ref.
  saved_base_ref=$BASE_REF
  BASE_REF=$(git -C "$ROOT" rev-parse HEAD)
  old_tmux_ref=$(resolve_permissive_tmux_kill_ref) \
    || { BASE_REF=$saved_base_ref; fail "unable to locate a historical bin/backends/tmux.sh with permissive kill-window selectors"; }
  old_bin=$(build_old_bin teardown-old)
  git -C "$ROOT" show "$old_tmux_ref:bin/backends/tmux.sh" > "$old_bin/bin/backends/tmux.sh" \
    || { BASE_REF=$saved_base_ref; fail "could not materialize historical tmux adapter from $old_tmux_ref"; }
  BASE_REF=$saved_base_ref
  proj="$TMP_ROOT/teardown-project"; wt="$TMP_ROOT/teardown-wt"
  id="teardownconform1"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  fb=$(make_teardown_fakebin "$TMP_ROOT/teardown-fake")

  data="$TMP_ROOT/teardown-data"
  mkdir -p "$data/$id"
  printf 'scout findings\n' > "$data/$id/report.md"

  state_old="$TMP_ROOT/teardown-state-old"; state_new="$TMP_ROOT/teardown-state-new"
  config_old="$TMP_ROOT/teardown-config-old"; config_new="$TMP_ROOT/teardown-config-new"
  mkdir -p "$state_old" "$state_new" "$config_old" "$config_new"

  fm_write_meta "$state_old/$id.meta" \
    "window=firstmate:fm-$id" "worktree=$wt" "project=$proj" "harness=pi" "kind=scout" "mode=no-mistakes" "yolo=off" \
    "decisions_reviewed=1" "decision_keys="
  fm_write_meta "$state_new/$id.meta" \
    "window=firstmate:fm-$id" "worktree=$wt" "project=$proj" "harness=pi" "kind=scout" "mode=no-mistakes" "yolo=off" \
    "decisions_reviewed=1" "decision_keys="
  touch "$state_old/.last-watcher-beat" "$state_new/.last-watcher-beat"

  log_old="$TMP_ROOT/teardown-old.log"; log_new="$TMP_ROOT/teardown-new.log"
  out_old=$(run_teardown_case "$old_bin/bin/fm-teardown.sh" "$old_bin" "$fb" "$log_old" "$state_old" "$data" "$config_old" "$id" 2>&1)
  rc_old=$?
  out_new=$(run_teardown_case "$ROOT/bin/fm-teardown.sh" "$old_bin" "$fb" "$log_new" "$state_new" "$data" "$config_new" "$id" 2>&1)
  rc_new=$?

  expect_code 0 "$rc_old" "old fm-teardown.sh (scout, report present) should succeed"$'\n'"$out_old"
  expect_code 0 "$rc_new" "new fm-teardown.sh (scout, report present) should succeed"$'\n'"$out_new"
  assert_contains "$(cat "$log_new")" "treehouse"$'\x1f''return'$'\x1f''--force'$'\x1f'"$wt" \
    "teardown did not call treehouse return --force <worktree>"
  # The legacy fixture's adapter comes from BASE_REF, so its selector form is
  # whatever the merge-base carried: permissive while the exact-selector change
  # was still on a branch, exact for every branch cut after it landed on main.
  # Pinning the old form here would make this case pass once and then fail
  # forever, so the '=' exactness markers are normalized away and the legacy run
  # is only required to have reached tmux window cleanup for this task. The
  # exact-selector contract belongs to the current script, asserted below.
  assert_contains "$(tr -d '=' < "$log_old")" "tmux"$'\x1f''kill-window'$'\x1f''-t'$'\x1f'"firstmate:fm-$id" \
    "legacy teardown fixture did not exercise tmux window cleanup for the task"
  assert_contains "$(cat "$log_new")" "tmux"$'\x1f''kill-window'$'\x1f''-t'$'\x1f'"=firstmate:=fm-$id" \
    "teardown did not call tmux kill-window with exact session and window selectors"

  pass "fm-teardown.sh: treehouse return remains compatible while tmux cleanup uses exact selectors"
}

# --- backend selection loudly refuses an unknown backend --------------------

test_spawn_refuses_unknown_backend_flag() {
  local out status
  # bogus names a backend with no adapter.
  out=$(FM_ROOT_OVERRIDE='' FM_HOME='' FM_STATE_OVERRIDE='' FM_DATA_OVERRIDE='' \
    FM_PROJECTS_OVERRIDE='' FM_CONFIG_OVERRIDE='' FM_SPAWN_NO_GUARD=1 \
    "$ROOT/bin/fm-spawn.sh" nope-backend-z1 projects/none pi --mode no-mistakes --yolo off --backend bogus 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "fm-spawn --backend bogus should refuse"
  assert_contains "$out" "unknown backend 'bogus'" "fm-spawn did not name the rejected backend"
  pass "fm-spawn.sh --backend bogus is refused loudly"
}

test_spawn_refuses_codex_app_backend_flag() {
  local out status
  out=$(FM_ROOT_OVERRIDE='' FM_HOME='' FM_STATE_OVERRIDE='' FM_DATA_OVERRIDE='' \
    FM_PROJECTS_OVERRIDE='' FM_CONFIG_OVERRIDE='' FM_SPAWN_NO_GUARD=1 \
    "$ROOT/bin/fm-spawn.sh" nope-codex-app-z1 projects/none pi --mode no-mistakes --yolo off --backend codex-app 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "fm-spawn --backend codex-app should refuse"
  assert_contains "$out" "unknown backend 'codex-app'" "fm-spawn did not preserve the blocked codex-app contract"
  pass "fm-spawn.sh --backend codex-app is refused"
}

test_spawn_refuses_unknown_fm_backend_env() {
  local out status
  out=$(FM_ROOT_OVERRIDE='' FM_HOME='' FM_STATE_OVERRIDE='' FM_DATA_OVERRIDE='' \
    FM_PROJECTS_OVERRIDE='' FM_CONFIG_OVERRIDE='' FM_SPAWN_NO_GUARD=1 FM_BACKEND=bogus \
    "$ROOT/bin/fm-spawn.sh" nope-backend-z2 projects/none pi --mode no-mistakes --yolo off 2>&1)
  status=$?
  [ "$status" -ne 0 ] || fail "FM_BACKEND=bogus should refuse"
  assert_contains "$out" "unknown backend 'bogus'" "fm-spawn did not name the rejected FM_BACKEND"
  pass "fm-spawn.sh honors FM_BACKEND and refuses an unimplemented value loudly"
}

test_spawn_default_backend_writes_no_meta_field() {
  local proj wt data id state config out
  proj="$TMP_ROOT/nobackend-project"; wt="$TMP_ROOT/nobackend-wt"; data="$TMP_ROOT/nobackend-data"
  id="nobackendz3"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  local fb
  fb=$(make_spawn_fakebin "$TMP_ROOT/nobackend-fake" "$wt")
  mkdir -p "$data/$id"; printf 'brief\n' > "$data/$id/brief.md"
  state="$TMP_ROOT/nobackend-state"; config="$TMP_ROOT/nobackend-config"
  mkdir -p "$state" "$config"

  out=$(PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
    FM_PROJECTS_OVERRIDE="$TMP_ROOT/unused-projects" FM_SPAWN_NO_GUARD=1 TMUX="fake,1,0" \
    FM_TMUX_LOG="$TMP_ROOT/nobackend.log" \
    "$ROOT/bin/fm-spawn.sh" "$id" "$proj" pi --mode no-mistakes --yolo off --backend tmux 2>&1)
  expect_code 0 $? "explicit --backend tmux should spawn successfully"$'\n'"$out"
  assert_no_grep 'backend=' "$state/$id.meta" \
    "an explicit --backend tmux (the default) must not write backend= to meta (P1 compatibility contract)"
  rm -rf "/tmp/fm-$id"
  pass "fm-spawn.sh: an explicit --backend tmux resolves silently and writes no backend= (missing means tmux)"
}

test_spawn_explicit_backend_flag_beats_autodetect_herdr_env() {
  local proj wt data id state config out fb
  proj="$TMP_ROOT/explicit-backend-project"; wt="$TMP_ROOT/explicit-backend-wt"; data="$TMP_ROOT/explicit-backend-data"
  id="explicitbackendz4"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  fb=$(make_spawn_fakebin "$TMP_ROOT/explicit-backend-fake" "$wt")
  mkdir -p "$data/$id"; printf 'brief\n' > "$data/$id/brief.md"
  state="$TMP_ROOT/explicit-backend-state"; config="$TMP_ROOT/explicit-backend-config"
  mkdir -p "$state" "$config"

  # HERDR_ENV=1 is present (as if firstmate itself were running under herdr),
  # but an explicit --backend tmux flag must still win outright.
  out=$(PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
    FM_PROJECTS_OVERRIDE="$TMP_ROOT/unused-projects" FM_SPAWN_NO_GUARD=1 TMUX="fake,1,0" HERDR_ENV=1 \
    FM_TMUX_LOG="$TMP_ROOT/explicit-backend.log" \
    "$ROOT/bin/fm-spawn.sh" "$id" "$proj" pi --mode no-mistakes --yolo off --backend tmux 2>&1)
  expect_code 0 $? "explicit --backend tmux should spawn successfully even with HERDR_ENV=1 set"$'\n'"$out"
  assert_no_grep 'backend=' "$state/$id.meta" \
    "an explicit --backend tmux must win over an ambient HERDR_ENV=1 auto-detect marker"
  rm -rf "/tmp/fm-$id"
  pass "fm-spawn.sh: explicit --backend tmux wins over an ambient HERDR_ENV=1 auto-detect marker"
}

test_spawn_autodetect_nesting_resolves_tmux_silently() {
  local proj wt data id state config out fb
  proj="$TMP_ROOT/nest-project"; wt="$TMP_ROOT/nest-wt"; data="$TMP_ROOT/nest-data"
  id="nestbackendz5"
  fm_git_worktree "$proj" "$wt" "fm/$id"
  fb=$(make_spawn_fakebin "$TMP_ROOT/nest-fake" "$wt")
  mkdir -p "$data/$id"; printf 'brief\n' > "$data/$id/brief.md"
  state="$TMP_ROOT/nest-state"; config="$TMP_ROOT/nest-config"
  mkdir -p "$state" "$config"

  # No --backend, no FM_BACKEND, no config/backend: nothing is explicitly
  # configured, so auto-detect runs. $TMUX and HERDR_ENV=1 are both present
  # (tmux nested inside a herdr pane) - the full fm-spawn.sh pipeline, not just
  # fm_backend_name, must resolve this to tmux and stay completely silent about
  # it (today's default path, byte-identical).
  out=$(PATH="$fb:$PATH" FM_ROOT_OVERRIDE="$ROOT" \
    FM_STATE_OVERRIDE="$state" FM_DATA_OVERRIDE="$data" FM_CONFIG_OVERRIDE="$config" \
    FM_PROJECTS_OVERRIDE="$TMP_ROOT/unused-projects" FM_SPAWN_NO_GUARD=1 TMUX="fake,1,0" HERDR_ENV=1 \
    FM_TMUX_LOG="$TMP_ROOT/nest.log" \
    "$ROOT/bin/fm-spawn.sh" "$id" "$proj" pi --mode no-mistakes --yolo off 2>&1)
  expect_code 0 $? "fm-spawn.sh should auto-detect tmux and spawn successfully for nested tmux-in-herdr"$'\n'"$out"
  assert_no_grep 'backend=' "$state/$id.meta" \
    "auto-detected nested tmux-in-herdr must resolve to tmux (missing backend= means tmux)"
  case "$out" in
    *NOTICE*) fail "auto-detecting tmux (even nested inside herdr) must stay silent, no NOTICE expected"$'\n'"$out" ;;
  esac
  rm -rf "/tmp/fm-$id"
  pass "fm-spawn.sh: auto-detect resolves nested tmux-in-herdr to tmux and stays silent end to end"
}

test_backend_name_precedence
test_backend_detect_precedence
test_backend_name_autodetect_notice
test_backend_name_explicit_beats_detection
test_backend_validate_refuses_unknown
test_backend_source_shell_portable
test_backend_validate_spawn_accepts_supported
test_meta_get_and_backend_of_meta
test_resolve_selector_three_forms
test_backend_of_selector_matches_explicit_target_meta
test_send_tmux_contract
test_peek_conformance_old_vs_new
test_spawn_symlinked_project_prefix_avoids_false_refusal
test_teardown_conformance_old_vs_new
test_spawn_refuses_unknown_backend_flag
test_spawn_refuses_codex_app_backend_flag
test_spawn_refuses_unknown_fm_backend_env
test_spawn_default_backend_writes_no_meta_field
test_spawn_explicit_backend_flag_beats_autodetect_herdr_env
test_spawn_autodetect_nesting_resolves_tmux_silently
