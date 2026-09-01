#!/usr/bin/env bash
# tests/fm-composer-lib.test.sh - the shared composer-content classifier
# (bin/fm-composer-lib.sh), the ONE fleet-wide owner every backend adapter
# delegates its empty|pending|unknown verdict to.
#
# The load-bearing contract, task fm-composer-shellglyph-safety:
#   1. A BARE shell prompt glyph (`>`/`$`/`%`/`#`) on an unstructured row is a
#      dead shell, NOT an empty agent composer - it must read `unknown`
#      (unsafe-for-injection), never `empty`. This is the safety fix.
#   2. The SAME shell glyph INSIDE a bordered composer box remains empty.
#   3. Pi's `❯` prompt glyph is a genuine empty agent composer either way.
#   4. Real unsubmitted text reads `pending`; a known idle placeholder reads
#      `empty`.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck source=/dev/null
. "$ROOT/bin/fm-composer-lib.sh"

# classify <bordered> <content> [idle_re] -> echoes the verdict.
classify() { fm_composer_classify_content "$@"; }

# --- Safety fix: bare shell prompt is NOT an empty agent composer -----------

test_bare_shell_glyphs_are_unknown() {
  local g out
  for g in '>' '$' '%' '#'; do
    out=$(classify 0 "$g")
    [ "$out" = unknown ] \
      || fail "bare shell glyph '$g' must read unknown (dead shell, unsafe), got '$out'"
  done
  pass "fm_composer_classify_content: a bare shell prompt glyph (>/\$/%/#) reads unknown, never empty"
}

test_stripped_unbordered_content_uses_plain_content() {
  local plain out
  for plain in '$' 'user@host $'; do
    out=$(classify 0 '' '' sensitive "$plain")
    [ "$out" = unknown ] \
      || fail "stripped unbordered content '$plain' must retain its unknown safety verdict, got '$out'"
  done
  out=$(classify 0 '' '' sensitive '❯')
  [ "$out" = empty ] || fail "a stripped Pi prompt glyph must remain empty, got '$out'"
  pass "fm_composer_classify_content: stripped unbordered content is unknown except the Pi glyph"
}

test_bare_shell_prompt_with_command_is_not_empty() {
  local out
  # A dead shell showing a typed command must not read empty either.
  out=$(classify 0 '$ ls -la')
  [ "$out" != empty ] || fail "a bare shell prompt with a command must not read empty, got '$out'"
  pass "fm_composer_classify_content: a bare shell prompt carrying a command is not empty"
}

# --- Preserved: shell glyph inside a composer box is the harness prompt ------

test_bordered_shell_glyph_is_empty() {
  local g out
  for g in '>' '$' '%' '#'; do
    out=$(classify 1 "$g")
    [ "$out" = empty ] \
      || fail "a shell glyph '$g' inside a bordered composer box must read empty, got '$out'"
  done
  pass "fm_composer_classify_content: a bare prompt glyph inside a bordered composer box reads empty (Pi's idle composer)"
}

# --- Agent glyphs are empty either way --------------------------------------

test_pi_glyph_is_empty_bordered_and_bare() {
  local out
  out=$(classify 0 '❯'); [ "$out" = empty ] || fail "bare Pi '❯' should read empty, got '$out'"
  out=$(classify 1 '❯'); [ "$out" = empty ] || fail "bordered Pi '❯' should read empty, got '$out'"
  pass "fm_composer_classify_content: the Pi prompt glyph reads empty bordered or bare"
}

# --- Empty content and idle placeholder -------------------------------------

test_empty_content_is_empty() {
  local out
  out=$(classify 0 ''); [ "$out" = empty ] || fail "empty bare content should read empty, got '$out'"
  out=$(classify 1 ''); [ "$out" = empty ] || fail "empty bordered content should read empty, got '$out'"
  pass "fm_composer_classify_content: an empty composer reads empty"
}

test_idle_placeholder_is_empty() {
  local idle='^Type a message\.\.\.$' out
  out=$(classify 1 'Type a message...' "$idle" sensitive 'Type a message...' 1 1)
  [ "$out" = pending ] || fail "placeholder-like text surviving a styled box capture should read pending, got '$out'"
  out=$(classify 1 '❯ Type a message...' "$idle" sensitive '❯ Type a message...' 1 0)
  [ "$out" = empty ] || fail "a glyph-bearing plain box placeholder should read empty, got '$out'"
  out=$(classify 0 '❯ Type a message...' "$idle" sensitive '❯ Type a message...' 0 1)
  [ "$out" = pending ] || fail "placeholder text on a styled bare input row must be pending, got '$out'"
  out=$(classify 0 '❯ Type a message...' "$idle" sensitive '❯ Type a message...' 0 0)
  [ "$out" = unknown ] || fail "placeholder text on a plain bare input row must be unknown, got '$out'"
  out=$(classify 1 'Type a message...')
  [ "$out" = pending ] || fail "without an idle regex the placeholder text is pending, got '$out'"
  pass "fm_composer_classify_content: idle matching is limited to proven placeholder positions"
}

test_idle_placeholder_case_mode_is_explicit() {
  local idle='^Type a message\.\.\.$' out
  out=$(classify 1 'type a message...' "$idle" sensitive 'type a message...' 1 0)
  [ "$out" = pending ] || fail "a case-variant idle placeholder should remain pending by default, got '$out'"
  out=$(classify 1 'type a message...' "$idle" insensitive 'type a message...' 1 0)
  [ "$out" = empty ] || fail "an explicitly insensitive plain placeholder should read empty, got '$out'"
  pass "fm_composer_classify_content: idle matching preserves the caller's case mode"
}

# --- Real text is pending ---------------------------------------------------

test_real_text_is_pending() {
  local out
  out=$(classify 0 '❯ fix findings 1 and 3'); [ "$out" = pending ] || fail "bare '❯ <text>' should be pending, got '$out'"
  out=$(classify 1 '> deploy staging now'); [ "$out" = pending ] || fail "bordered '> <text>' should be pending, got '$out'"
  out=$(classify 0 '❯ second turn'); [ "$out" = pending ] || fail "bare Pi text should be pending, got '$out'"
  # A slash-command popup argument-hint placeholder is still unsubmitted text.
  out=$(classify 1 '/compact compaction instructions'); [ "$out" = pending ] || fail "a popup placeholder fill should be pending, got '$out'"
  pass "fm_composer_classify_content: real unsubmitted text reads pending (including a popup argument-hint fill)"
}

# =============================================================================
# fm_composer_classify_screen: the adapter-facing screen classifier and the
# correctness matrix (audit data/fm-composer-consolidation-audit-s1, task
# fm-composer-thin-adapter-refactor-r1).
#
# Fixtures cover the real Pi prompt and separated composer shapes.
#
# Capability profiles mirror the real adapters' descriptors: tmux
# (styled+cursor+identity), herdr/zellij (styled), cmux/orca (plain). Every
# emptiness verdict is asserted under the ambient UTF-8 locale AND LC_ALL=C,
# pinning the locale-safe Unicode-space normalization (issue #1988).
# =============================================================================

ESC=$(printf '\033')
NBSP=$(printf '\302\240')
CAPS_TMUX=$'styled=1\ncursor=1\nidentity=1\nrows=0'
CAPS_STYLED=$'styled=1\ncursor=0\nidentity=1\nrows=20'      # herdr
CAPS_STYLED_NOID=$'styled=1\ncursor=0\nidentity=0\nrows=20' # zellij
CAPS_PLAIN=$'styled=0\ncursor=0\nidentity=0\nrows=20'       # cmux, orca

# assert_screen <label> <want> <caps> <screen> [cursor] [identity]: one
# verdict, asserted under the ambient locale AND LC_ALL=C.
assert_screen() {
  local label=$1 want=$2 out
  shift 2
  out=$(fm_composer_classify_screen "$@")
  [ "$out" = "$want" ] || fail "$label: expected $want, got '$out'"
  out=$(LC_ALL=C fm_composer_classify_screen "$@")
  [ "$out" = "$want" ] || fail "$label under LC_ALL=C: expected $want, got '$out'"
}

test_matrix_pi_separated_needs_identity() {
  # Real idle pi: a blank row between two solid rules. The blank row alone is
  # exactly what the strict rule refuses; only structure PLUS a live
  # idle/done pi identity proves the composer (herdr's rule, now
  # fleet-wide; tmux supplies identity from its foreground-process probe).
  local screen typed pi_idle pi_working pi_blocked none
  screen=$'transcript\n────────────────────────\n\n────────────────────────\n footer'
  pi_idle=$(printf 'pi\tidle'); pi_working=$(printf 'pi\tworking'); none=$(printf 'zsh\t')
  pi_blocked=$(printf 'pi\tblocked')
  assert_screen "pi idle with identity" empty "$CAPS_STYLED" "$screen" '' "$pi_idle"
  assert_screen "pi idle on tmux with identity" empty "$CAPS_TMUX" "$screen" 2 "$pi_idle"
  assert_screen "pi idle on zellij" unknown "$CAPS_STYLED_NOID" "$screen"
  # Identity-capable but unfetched: the adapter is asked to probe lazily.
  [ "$(fm_composer_classify_screen "$CAPS_STYLED" "$screen")" = need-identity ] \
    || fail "an identity-capable profile should request the lazy identity probe"
  # No identity capability (cmux/orca/zellij): the shape is unprovable.
  assert_screen "pi pair without identity capability" unknown "$CAPS_PLAIN" "$screen"
  # A working pi cannot authorize injection into the blank region.
  assert_screen "working pi defers" unknown "$CAPS_STYLED" "$screen" '' "$pi_working"
  # A pi parked on an interactive prompt reports `blocked`: it is waiting on a
  # human keystroke, so the blank region is a menu's, not a free composer's.
  # Typing there answers the prompt and the text is discarded (issue #2797).
  assert_screen "blocked pi defers" unknown "$CAPS_STYLED" "$screen" '' "$pi_blocked"
  # The audit's live counterexample: a plain shell running sleep, cursor
  # parked on a blank line between two rules, NO pi process. The permissive
  # rule read this `empty`; identity+structure refuses it.
  assert_screen "sleep-pane counterexample" unknown "$CAPS_TMUX" "$screen" 2 "$none"
  assert_screen "absent identity cannot prove blank pi pair" unknown "$CAPS_TMUX" "$screen" 2 probe-absent
  typed=$'────────────────────────\nfix the flaky test\n────────────────────────'
  assert_screen "pi typed" pending "$CAPS_STYLED" "$typed" '' "$pi_idle"
  typed=$'────────────────────────\n❯\n────────────────────────'
  assert_screen "pi lone-glyph draft with identity" pending "$CAPS_STYLED" "$typed" '' "$pi_idle"
  assert_screen "pi lone-glyph draft on tmux" pending "$CAPS_TMUX" "$typed" 1 "$pi_idle"
  assert_screen "lone glyph without identity capability" empty "$CAPS_STYLED_NOID" "$typed"
  assert_screen "lone glyph on plain backend" empty "$CAPS_PLAIN" "$typed"
  assert_screen "lone glyph with non-pi identity" empty "$CAPS_STYLED" "$typed" '' "$none"
  pass "matrix: pi's separated composer needs identity + structure; the blank row alone never proves it"
}

test_strict_blank_row_divergence() {
  # THE STRICT POSTURE PIN (captain decision blank-row-injection-posture,
  # 2026-08-09): a blank or otherwise unidentified input row with no positive
  # container proof is `unknown`. Each case below read `empty` (or `pending`)
  # under the replaced permissive rule; if any of them drifts back, the
  # permissive posture has silently returned and away-mode injection would
  # again type escalations into unproven panes.
  local out
  # Permissive read this blank cursor row as empty = safe to inject.
  out=$(fm_composer_classify_screen "$CAPS_TMUX" $'some output\nmore output\n' 2)
  [ "$out" = unknown ] || fail "a blank unidentified cursor row must be unknown (was permissive empty), got '$out'"
  # A dead shell's prompt row.
  out=$(fm_composer_classify_screen "$CAPS_TMUX" $'output\n$ ' 1)
  [ "$out" = unknown ] || fail "a dead-shell prompt row must be unknown, got '$out'"
  # A bare busy-footer row is not a composer container.
  out=$(fm_composer_classify_screen "$CAPS_TMUX" $'Working...' 0)
  [ "$out" = unknown ] || fail "a bare busy-footer row must be unknown (was permissive empty), got '$out'"
  # An unidentified free-text cursor row carries no container proof either.
  out=$(fm_composer_classify_screen "$CAPS_TMUX" $'output\nhuman draft text' 1)
  [ "$out" = unknown ] || fail "an unidentified text row must be unknown under strict, got '$out'"
  # A blank screen with no cursor capability.
  out=$(fm_composer_classify_screen "$CAPS_PLAIN" $'\n\n')
  [ "$out" = unknown ] || fail "a blank screen must be unknown, got '$out'"
  pass "strict posture: blank and unidentified rows are unknown, never injectable empty"
}

test_bare_wrap_region_classifies() {
  # Long typed input wraps below the glyph row; the cursor rides the wrapped
  # continuation. The region is IDENTIFIED (glyph row + contiguous non-blank,
  # non-structural rows), so a swallowed Enter still reads pending and earns
  # its retry; a wrapped GHOST suggestion still proves empty.
  local wrapped ghost_wrapped out
  wrapped=$'❯ a very long steer message that\nwraps onto the following line'
  assert_screen "wrapped typed input" pending "$CAPS_TMUX" "$wrapped" 1
  wrapped=$'❯ wrapped typed input\ncontinues without a terminal-inserted glyph'
  assert_screen "ordinary wrapped input" pending "$CAPS_TMUX" "$wrapped" 1
  ghost_wrapped=$'❯ '"${ESC}[2ma long rotating suggestion that${ESC}[0m"$'\n'"${ESC}[2mwraps onto the next line${ESC}[0m"
  out=$(fm_composer_classify_screen "$CAPS_TMUX" "$ghost_wrapped" 1)
  [ "$out" = empty ] || fail "a wrapped ghost suggestion should still prove empty, got '$out'"
  # A structural row between the glyph and the cursor breaks the wrap claim.
  out=$(fm_composer_classify_screen "$CAPS_TMUX" $'❯ text\n────────────────\nbelow the rule' 2)
  [ "$out" = unknown ] || fail "a rule between glyph and cursor must break the wrap region, got '$out'"
  out=$(fm_composer_classify_screen "$CAPS_TMUX" $'❯ text\n$ live shell' 1)
  [ "$out" = unknown ] || fail "a shell prompt below a glyph row must not become wrapped input, got '$out'"
  pass "fm_composer_classify_screen: the bare composer's wrap region stays identified; structure breaks it"
}

test_contiguous_transcript_reanchors_on_live_prompt() {
  local screen
  screen=$'❯ hi\nHello!\n❯'
  assert_screen "contiguous transcript live prompt on cursorless styled backend" empty "$CAPS_STYLED_NOID" "$screen"
  assert_screen "contiguous transcript live prompt on cursorless plain backend" empty "$CAPS_PLAIN" "$screen"
  assert_screen "contiguous transcript live prompt with cursor" empty "$CAPS_TMUX" "$screen" 2
  pass "fm_composer_classify_screen: a row-leading agent glyph reanchors the live composer"
}

test_lower_dead_shell_invalidates_cursorless_candidate() {
  local stale live out
  stale=$'old transcript\n❯\nprocess exited\n$'
  assert_screen "stale composer above dead shell on herdr" unknown "$CAPS_STYLED" "$stale"
  assert_screen "stale composer above dead shell on zellij" unknown "$CAPS_STYLED_NOID" "$stale"
  assert_screen "stale composer above dead shell on cmux/orca" unknown "$CAPS_PLAIN" "$stale"
  out=$(fm_composer_classify_screen "$CAPS_TMUX" "$stale" 1)
  [ "$out" = empty ] \
    || fail "cursor mode must keep the cursor-anchored composer verdict, got '$out'"

  live=$'transcript shell snippet\n$ echo old output\nmore transcript\n❯'
  assert_screen "shell transcript above live composer on herdr" empty "$CAPS_STYLED" "$live"
  assert_screen "shell transcript above live composer on zellij" empty "$CAPS_STYLED_NOID" "$live"
  assert_screen "shell transcript above live composer on cmux/orca" empty "$CAPS_PLAIN" "$live"
  pass "fm_composer_classify_screen: a lower dead shell invalidates only cursorless stale composers"
}

test_cursorless_bare_wrap_region_classifies() {
  local activity status bounded ghost out
  activity=$'❯\nWorking on request...'
  assert_screen "cursorless activity below bare row on herdr" pending "$CAPS_STYLED" "$activity"
  assert_screen "cursorless activity below bare row on zellij" pending "$CAPS_STYLED_NOID" "$activity"
  assert_screen "cursorless activity below bare row on cmux/orca" unknown "$CAPS_PLAIN" "$activity"

  status=$'❯\n\nPi status line'
  assert_screen "blank-separated Pi status on herdr" empty "$CAPS_STYLED" "$status"
  assert_screen "blank-separated Pi status on zellij" empty "$CAPS_STYLED_NOID" "$status"
  assert_screen "blank-separated Pi status on cmux/orca" empty "$CAPS_PLAIN" "$status"

  bounded=$'────────────────────────\n❯\n────────────────────────\nPi'
  assert_screen "rule-bounded Pi footer on herdr" empty "$CAPS_STYLED" "$bounded" '' probe-absent
  assert_screen "rule-bounded Pi footer on zellij" empty "$CAPS_STYLED_NOID" "$bounded"
  assert_screen "rule-bounded Pi footer on cmux/orca" empty "$CAPS_PLAIN" "$bounded"

  ghost=$'❯ '"${ESC}[2ma long rotating suggestion that${ESC}[0m"$'\n'"${ESC}[2mwraps onto the next line${ESC}[0m"
  out=$(fm_composer_classify_screen "$CAPS_STYLED" "$ghost")
  [ "$out" = empty ] || fail "cursorless ghost wrap on herdr should be empty, got '$out'"
  out=$(fm_composer_classify_screen "$CAPS_STYLED_NOID" "$ghost")
  [ "$out" = empty ] || fail "cursorless ghost wrap on zellij should be empty, got '$out'"
  pass "fm_composer_classify_screen: cursorless bare wrap regions participate in verdicts"
}

test_bottom_most_candidate_wins() {
  # The one ranking rule: the live composer is bottom-anchored, so a stale
  # decorative box can never outrank the real Pi row
  # below it - the confidently-wrong orca case from the audit.
  local screen out
  screen=$'╭────────────────────────╮\n│ permissions: YOLO mode │\n╰────────────────────────╯\n❯'"$NBSP"
  assert_screen "banner above live Pi row" empty "$CAPS_PLAIN" "$screen"
  screen=$'❯ old draft\n\n❯'
  assert_screen "blank-separated newer bare composer" empty "$CAPS_STYLED_NOID" "$screen"
  pass "fm_composer_classify_screen: the bottom-most candidate wins; stale banners cannot"
}

test_incomplete_lower_box_invalidates_stale_candidate() {
  local screen out
  screen=$'╭────────────────────────╮\n│ ❯                      │\n╰────────────────────────╯\nstartup complete\n╭────────────────────────╮\n│ ❯ clipped live draft  '
  out=$(fm_composer_classify_screen "$CAPS_PLAIN" "$screen")
  [ "$out" = unknown ] \
    || fail "an incomplete lower box must invalidate an earlier empty box, got '$out'"
  pass "fm_composer_classify_screen: incomplete lower structure invalidates stale boxes"
}

test_cursor_on_proven_box_bottom_classifies_content() {
  local screen out
  screen=$'╭────────────────────────╮\n│ ❯                      │\n╰────────────────────────╯'
  out=$(fm_composer_classify_screen "$CAPS_TMUX" "$screen" 2)
  [ "$out" = empty ] \
    || fail "a cursor on a proven box bottom must classify its content, got '$out'"
  pass "fm_composer_classify_screen: a proven box tolerates a bottom-border cursor"
}

test_selected_content_is_composer_scoped_and_wrap_normalized() {
  local screen out
  screen=$'hello captain in transcript\n╭────────────────────╮\n│ unrelated          │\n│ draft               │\n╰────────────────────╯'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ "$out" = 'unrelated draft' ] \
    || fail "box extraction should contain only normalized selected composer rows, got '$out'"
  screen=$'hello captain in transcript\n┃ hello\n┃ captain\n┃ Build · GPT-5.5 Fast OpenAI · high'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ "$out" = 'hello captain' ] \
    || fail "left-bar extraction should join user rows without footer furniture, got '$out'"
  screen=$'╭────────────────────╮\n│ ❯ '"${ESC}[2mType a message...${ESC}[0m"$'│\n╰────────────────────╯'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ -z "$out" ] \
    || fail "ghost agent-prompt placeholders should be excluded from extracted user content, got '$out'"
  screen=$'╭────────────────────╮\n│ > '"${ESC}[2mType a message...${ESC}[0m"$'│\n╰────────────────────╯'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ -z "$out" ] \
    || fail "ghost shell-prompt placeholders should be excluded from boxed user content, got '$out'"
  screen=$'╭────────────────────╮\n│ ❯ Type a message...│\n╰────────────────────╯'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ "$out" = 'Type a message...' ] \
    || fail "surviving placeholder-like input should remain extracted user content, got '$out'"
  screen=$'❯ a legitimately long steer that\nwraps across the next bare row\n\ntranscript below the break'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ "$out" = 'a legitimately long steer that wraps across the next bare row' ] \
    || fail "bare extraction should include only its contiguous wrap region, got '$out'"
  screen=$'❯ wrapped user content\ncontinuation preserves a mid-row ❯ glyph'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ "$out" = 'wrapped user content continuation preserves a mid-row ❯ glyph' ] \
    || fail "bare extraction should preserve mid-row agent glyph bytes, got '$out'"
  screen=$'❯ stale composer\n$ live shell'
  if out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen"); then
    fail "a lower live shell must invalidate composer extraction, got '$out'"
  fi
  screen=$'╭──────────────────────────────╮\n│ > wrapped user content       │\n│ ❯ preserves its leading glyph│\n╰──────────────────────────────╯'
  out=$(fm_composer_extract_selected_content "$CAPS_STYLED_NOID" "$screen")
  [ "$out" = 'wrapped user content ❯ preserves its leading glyph' ] \
    || fail "box extraction should strip only its actual prompt-row glyph, got '$out'"
  pass "fm_composer_extract_selected_content: scopes user content and excludes furniture"
}

test_bare_shell_glyphs_are_unknown
test_stripped_unbordered_content_uses_plain_content
test_bare_shell_prompt_with_command_is_not_empty
test_bordered_shell_glyph_is_empty
test_pi_glyph_is_empty_bordered_and_bare
test_empty_content_is_empty
test_idle_placeholder_is_empty
test_idle_placeholder_case_mode_is_explicit
test_real_text_is_pending
test_matrix_pi_separated_needs_identity
test_strict_blank_row_divergence
test_bare_wrap_region_classifies
test_contiguous_transcript_reanchors_on_live_prompt
test_lower_dead_shell_invalidates_cursorless_candidate
test_cursorless_bare_wrap_region_classifies
test_bottom_most_candidate_wins
test_incomplete_lower_box_invalidates_stale_candidate
test_cursor_on_proven_box_bottom_classifies_content
test_selected_content_is_composer_scoped_and_wrap_normalized

test_queued_enter_verdict_busy_pending_is_empty() {
  local out
  out=$(fm_composer_queued_enter_verdict pending busy)
  [ "$out" = empty ] || fail "busy + proven pending must be queued delivery (empty), got '$out'"
  pass "fm_composer_queued_enter_verdict: pending + busy returns empty (queued Enter)"
}

test_queued_enter_verdict_idle_pending_stays_pending() {
  local out
  out=$(fm_composer_queued_enter_verdict pending idle)
  [ "$out" = pending ] || fail "idle + proven pending must stay a genuine swallow, got '$out'"
  out=$(fm_composer_queued_enter_verdict pending unknown)
  [ "$out" = pending ] || fail "unknown busy is not proof of a queue, got '$out'"
  pass "fm_composer_queued_enter_verdict: pending + idle/unknown stays pending"
}

test_queued_enter_verdict_does_not_convert_other_states() {
  local state out
  for state in empty pending-unproven unknown send-failed future-state; do
    out=$(fm_composer_queued_enter_verdict "$state" busy)
    [ "$out" = "$state" ] || fail "busy must not convert '$state', got '$out'"
    out=$(fm_composer_queued_enter_verdict "$state" idle)
    [ "$out" = "$state" ] || fail "idle must not convert '$state', got '$out'"
  done
  pass "fm_composer_queued_enter_verdict: only proven pending is converted"
}

test_queued_enter_verdict_busy_pending_is_empty
test_queued_enter_verdict_idle_pending_stays_pending
test_queued_enter_verdict_does_not_convert_other_states
