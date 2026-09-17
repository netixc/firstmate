#!/usr/bin/env bash
# Tests for harness-aware supervision instruction rendering.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-supervision-instructions)
RENDER="$ROOT/bin/fm-supervision-instructions.sh"

test_selected_harness_block_only() {
  local out
  out=$("$RENDER" --harness pi)
  assert_contains "$out" "SUPERVISION OPERATING INSTRUCTIONS - primary harness: pi" "pi heading missing"
  assert_contains "$out" "Mode: Pi extension background wake." "pi snippet missing"
  assert_not_contains "$out" "Mode: Unknown harness fallback." "renderer printed the unknown snippet too"
  pass "renderer prints exactly the selected harness block"
}

test_unknown_fallback() {
  local harness out
  out=$("$RENDER" --harness not-real)
  assert_contains "$out" "primary harness: unknown" "unknown heading missing"
  assert_contains "$out" "Mode: Unknown harness fallback." "unknown fallback snippet missing"

  for harness in codex omp muse opencode; do
    out=$("$RENDER" --harness "$harness")
    assert_contains "$out" "primary harness: unknown" "a stale $harness selection must use the unknown fallback"
    assert_contains "$out" "Mode: Unknown harness fallback." "a stale $harness selection must not select a retired protocol"
    case "$harness" in
      omp)
        assert_not_contains "$out" ".omp/" "a stale OMP selection must not render retired extension paths"
        assert_not_contains "$out" "fm_watch_arm_omp" "a stale OMP selection must not render a retired repair tool"
        ;;
      muse)
        assert_not_contains "$out" "muse-session" "a stale Muse selection must not render retired sidecar paths"
        ;;
    esac
  done
  pass "renderer falls back to unknown.md for unverified and retired harness names"
}

test_conditional_stanzas() {
  local home config out
  home="$TMP_ROOT/conditional-home"
  config="$TMP_ROOT/conditional-config"
  mkdir -p "$home/state" "$home/config" "$config"
  out=$(FM_HOME="$home" FM_CONFIG_OVERRIDE="$config" "$RENDER" --harness pi --read-only 1 --afk 1 --x-mode 1)
  assert_contains "$out" "- Lock: read-only" "read-only stanza missing"
  assert_contains "$out" "- Away mode: active" "afk stanza missing"
  assert_contains "$out" "- X mode: active" "x-mode stanza missing"
  assert_contains "$out" "$config/x-mode.env" "x-mode stanza did not render the effective config path"
  assert_contains "$out" 'Mode: Pi extension background wake.' "pi snippet missing"
  assert_not_contains "$out" "Source \`config/x-mode.env\`" "snippet kept the repo-relative x-mode config path"
  pass "renderer includes read-only, afk, and effective x-mode current-state stanzas"
}

test_quiet_mode_stanzas() {
  local home config out
  home="$TMP_ROOT/quiet-home"
  config="$TMP_ROOT/quiet-config"
  mkdir -p "$home/state" "$config"
  out=$(FM_HOME="$home" FM_CONFIG_OVERRIDE="$config" "$RENDER" --harness pi --afk 1 --afk-mode quiet)
  assert_contains "$out" "- Quiet mode: active" "quiet stanza missing"
  assert_contains "$out" "load /quiet" "quiet stanza did not name the /quiet skill"
  assert_contains "$out" "Ordinary captain chat does NOT exit it" "quiet stanza lost the explicit-only exit rule"
  assert_not_contains "$out" "- Away mode: active" "quiet mode incorrectly rendered as away mode"
  out=$(FM_HOME="$home" "$RENDER" --harness pi --afk 1 --afk-mode quiet --repair-line)
  assert_contains "$out" "Quiet mode owns watcher supervision; load /quiet" "quiet repair line did not name /quiet"

  out=$(FM_HOME="$home" "$RENDER" --harness pi --afk 1)
  assert_contains "$out" "- Away mode: active" "omitting --afk-mode did not default to away (regression)"
  assert_not_contains "$out" "Quiet mode" "omitting --afk-mode leaked quiet-mode text"

  out=$(FM_HOME="$home" "$RENDER" --harness pi --afk 1 --afk-mode not-a-real-mode)
  assert_contains "$out" "- Away mode: active" "unrecognized --afk-mode value did not fall back to away"

  out=$(FM_HOME="$home" "$RENDER" --harness pi --afk 0)
  assert_contains "$out" "- Away/quiet mode: inactive" "inactive stanza missing"
  pass "renderer's away/quiet stanzas are mode-aware, default to away, and fall back safely on garbage input"
}

test_repair_lines() {
  local home out
  home="$TMP_ROOT/repair-home"
  mkdir -p "$home/state" "$home/config"
  out=$(FM_HOME="$home" "$RENDER" --harness pi --queue-pending 1 --repair-line)
  assert_contains "$out" "After draining queued wakes" "queue-pending prefix missing"
  assert_contains "$out" "Pi tool fm_watch_arm_pi" "queue-pending Pi repair lost its recovery tool"

  : > "$home/config/x-mode.env"
  out=$(FM_HOME="$home" "$RENDER" --harness pi --x-mode 1 --repair-line)
  assert_contains "$out" "source '$home/config/x-mode.env' first" "x-mode repair line did not source the effective cadence config"
  assert_contains "$out" "Pi tool fm_watch_arm_pi" "x-mode Pi repair lost its recovery tool"

  out=$(FM_HOME="$home" "$RENDER" --harness pi --read-only 1 --repair-line)
  assert_contains "$out" "session holding the fleet lock" "read-only repair line missing"

  out=$(FM_HOME="$home" "$RENDER" --harness pi --repair-line)
  assert_contains "$out" "Pi tool fm_watch_arm_pi" "pi repair line does not direct the model to the extension-owned tool"
  assert_not_contains "$out" "extension command /fm-watch-arm-pi" "pi repair line still directs the model to the human slash command"
  pass "renderer repair-line mode is harness-aware and honors conditional state"
}

test_pi_ordinary_continuation_and_repair() {
  local ordinary out

  out=$("$RENDER" --harness pi)
  ordinary=$(printf '%s\n' "$out" | grep -F -- '- Ordinary wake:')
  assert_contains "$ordinary" "Pi extension already owns watcher continuity" "pi ordinary-wake line does not leave continuity to the extension"
  assert_not_contains "$ordinary" "fm_watch_arm_pi" "pi ordinary-wake line incorrectly calls the recovery tool"
  out=$("$RENDER" --harness pi --repair-line)
  assert_contains "$out" "fm_watch_arm_pi" "pi recovery line lost the extension-owned repair tool"

  pass "renderer preserves every retained harness ordinary-continuation and missing-cycle repair path"
}

test_pi_signed_preserves_identity_with_pi_supervision_protocol() {
  local out ordinary
  out=$("$RENDER" --harness pi-signed)
  assert_contains "$out" "primary harness: pi-signed" \
    "pi-signed supervision normalized the visible runtime identity to pi"
  assert_contains "$out" "Mode: Pi extension background wake." \
    "pi-signed did not reuse Pi's authoritative supervision protocol"
  ordinary=$(printf '%s\n' "$out" | grep -F -- '- Ordinary wake:')
  assert_contains "$ordinary" "Pi extension already owns watcher continuity" \
    "pi-signed ordinary-wake semantics diverged from Pi"
  out=$("$RENDER" --harness pi-signed --repair-line)
  assert_contains "$out" "Pi tool fm_watch_arm_pi" \
    "pi-signed repair semantics diverged from Pi"
  pass "pi-signed keeps its identity while sharing Pi's supervision protocol"
}

test_pi_snippet_uses_effective_extension_path() {
  local home out turnend watch
  home="$TMP_ROOT/pi-home"
  turnend="$ROOT/.pi/extensions/fm-primary-turnend-guard.ts"
  watch="$ROOT/.pi/extensions/fm-primary-pi-watch.ts"
  mkdir -p "$home/state" "$home/config"
  out=$(FM_HOME="$home" "$RENDER" --harness pi)
  assert_contains "$out" "-e $turnend -e $watch" "pi snippet did not render both effective extension launch paths"
  assert_contains "$out" "The turn-end guard extension lives at \`$turnend\`" "pi snippet did not render the turn-end guard extension path"
  assert_contains "$out" "The watcher extension lives at \`$watch\`" "pi snippet did not render the watcher extension path"
  assert_contains "$out" "MAIN must not re-drain, re-run, or acknowledge it" "pi snippet lost merged-event ownership"
  assert_contains "$out" "MAIN applies judgment about whether and how to surface, summarize, reference, or incorporate a merged sailboat outcome" "pi snippet imposed a mechanical sailboat treatment"
  assert_not_contains "$out" "__FM_PI_EXT__" "renderer leaked the Pi extension path placeholder"
  assert_not_contains "$out" "__FM_PI_TURNEND_EXT__" "renderer leaked the Pi turn-end extension path placeholder"
  assert_not_contains "$out" "state/fm-primary-pi-watch.ts" "pi snippet kept the old generated state-relative extension path"
  pass "pi supervision snippet renders the effective extension path"
}

test_selected_harness_block_only
test_unknown_fallback
test_conditional_stanzas
test_quiet_mode_stanzas
test_repair_lines
test_pi_ordinary_continuation_and_repair
test_pi_signed_preserves_identity_with_pi_supervision_protocol
test_pi_snippet_uses_effective_extension_path
