#!/usr/bin/env bash
# bin/fm-composer-lib.sh - the ONE fleet-wide owner of composer classification:
# every shape a verified harness draws, every glyph, every container proof, and
# the empty|pending|pending-unproven|unknown verdict, shared by every
# session-provider adapter (tmux via bin/fm-tmux-lib.sh and Herdr via
# bin/backends/herdr.sh).
#
# WHY THIS EXISTS: composer shape knowledge is centralized so the supported
# adapters cannot drift into conflicting harness classifications.
# The consolidation rule that prevents a recurrence: an adapter CAPTURES a
# screen and DESCRIBES its capabilities; it never classifies. A new harness
# shape is taught to fm_composer_classify_screen below, once, and every backend
# that can capture a screen learns it in the same commit.
#
# THE CAPABILITY MODEL: adapters differ in what their capture primitive can
# see, and those differences enter here as DATA (the <caps> argument), never as
# adapter code. Capability differences change how CONFIDENTLY a shape can be
# judged; they never change what the shapes ARE:
#   styled=1    the capture preserves ANSI styling, so ghost/placeholder text
#               is detectable and can be stripped (tmux -e and Herdr ANSI).
#               With styled=0, ghost text is unreadable, so a bare glyph row
#               carrying trailing non-idle text degrades to `unknown` rather
#               than `pending`: the text may be the harness's own idle
#               suggestion, and a false `pending` blocks every safe caller.
#   cursor=1    a cursor row is supplied (tmux #{cursor_y} only). The cursor
#               anchors shape selection: the shape containing the cursor is the
#               composer. Without it, the bottom-most shape wins.
#   identity=1  a native agent identity/state probe exists (herdr `agent get`;
#               the tmux pi foreground-process probe). Identity is what makes
#               Pi's blank separated composer provable; with identity=0 that
#               shape stays `unknown`.
#   rows=<n>    the capture's bounded row count (informational).
#
# THE STRICT BLANK-ROW RULE (captain decision blank-row-injection-posture,
# 2026-08-09): a blank or otherwise unidentified input row with no positive
# container proof is `unknown` and callers defer. This replaced tmux's
# permissive "blank cursor row = empty = safe to inject" rule fleet-wide: a
# blank row under the cursor can be a modal dialog, a dead shell between
# transcript rules, or a mid-redraw pane, and the away-mode injector types
# escalations into whatever it calls empty. Positive container proof means one
# of the shapes in the catalogue below.
#
# THE SHAPE CATALOGUE (all verified against real harnesses; byte-level
# captures in data/fm-composer-consolidation-audit-s1/report.md and
# docs/verification/runtime-backends.md):
#   bordered   - a complete boxed composer: a top border, side-bordered content
#                rows of the same family, and a matching bottom border.
#   separated  - pi: content rows between two solid horizontal `─` rules, no
#                glyph and no side border. Provable only with a live agent
#                identity reporting an idle/done/blocked pi (herdr `agent
#                get`; the tmux foreground-process probe), because a blank
#                region between two transcript rules is otherwise exactly the
#                strict rule's unidentifiable blank row.
#
# THE SAFETY RULE for glyphs: a bare shell-like prompt glyph (`>` `❯` `$` `%` `#`) -
# what a pane shows once its agent has exited to a plain login shell - is a
# genuine empty agent composer ONLY inside a bordered container. On a bare row
# it is a dead-shell prompt and classifies `unknown` (never a safe injection
# target).
#
# GHOST/PLACEHOLDER TEXT: a harness may fill an otherwise-empty composer with
# de-emphasized ghost text that a plain capture cannot tell apart from text a human typed.
# fm_composer_strip_ghost is the ONE ANSI-aware extractor of "real typed
# content": it drops every dim/faint (SGR 2) run and keeps only normal-intensity,
# normally-coloured text.
#
# UNICODE WHITESPACE (issue #1988; open PRs #1995/#2047 target the same
# defect and #1995's naming is adopted here so the implementations converge):
# a harness may separate its prompt glyph from composer content with a
# non-ASCII space. POSIX `[[:space:]]` includes U+00A0 only
# under some locales, so every trim used to be locale-dependent: the same live
# pane read `empty` under a UTF-8 shell and `pending` under LC_ALL=C (a
# daemon, launchd, or ssh context), deferring every away-mode escalation.
# fm_composer_normalize_trim_var is the one fix: it maps every code point
# Unicode gives the property White_Space=Yes outside ASCII onto a plain ASCII
# space before any trim or comparison, byte-exactly, so the verdict cannot
# depend on the ambient locale. Glyph strips use literal byte-exact pattern
# removal for the same reason: `${v#?}` removes one BYTE under LC_ALL=C and
# one CHARACTER under UTF-8, which used to leave partial multibyte residue.
#
# Re-sourcing is a cheap idempotent redefinition, so this file needs no
# include guard (matching bin/fm-tmux-lib.sh).

# fm_composer_strip_ansi: drop every CSI escape sequence, leaving plain text.
# Used for STRUCTURAL row/shape detection, where ghost text must be KEPT so the
# composer box border or bare prompt glyph is still visible; content extraction
# uses fm_composer_strip_ghost instead. Reads the styled text on stdin and prints
# plain text (stdin-only, matching fm_composer_strip_ghost). The character class
# includes ':' so an ITU colon-form SGR (38:2::r:g:b) is stripped whole, not left
# with a dangling tail.
fm_composer_strip_ansi() {
  local esc; esc=$(printf '\033')
  LC_ALL=C sed "s/${esc}\\[[0-9;:?]*[[:alpha:]]//g"
}

# Every code point Unicode gives the property White_Space=Yes that lies OUTSIDE
# ASCII, as UTF-8 byte sequences. Built from octal escapes rather than written
# literally so each entry stays reviewable in source instead of being an
# invisible character:
#   U+0085 NEXT LINE                  U+00A0 NO-BREAK SPACE
#   U+1680 OGHAM SPACE MARK           U+2000..U+200A EN QUAD..HAIR SPACE
#   U+2028 LINE SEPARATOR             U+2029 PARAGRAPH SEPARATOR
#   U+202F NARROW NO-BREAK SPACE      U+205F MEDIUM MATHEMATICAL SPACE
#   U+3000 IDEOGRAPHIC SPACE
# ASCII whitespace is absent because POSIX `[[:space:]]` already covers it.
# U+200B ZERO WIDTH SPACE is deliberately absent: Unicode gives it
# White_Space=No (a format character), so listing it would substitute this
# owner's own guess for the property it claims to follow. The live harness
# guard (bin/fm-test-run.sh, live-harness-optin) is what catches a harness
# that starts drawing its composer with a character outside this property.
FM_COMPOSER_UNICODE_SPACES=()
for _fm_composer_space_octal in \
  '\0302\0205' '\0302\0240' '\0341\0232\0200' \
  '\0342\0200\0200' '\0342\0200\0201' '\0342\0200\0202' '\0342\0200\0203' \
  '\0342\0200\0204' '\0342\0200\0205' '\0342\0200\0206' '\0342\0200\0207' \
  '\0342\0200\0210' '\0342\0200\0211' '\0342\0200\0212' \
  '\0342\0200\0250' '\0342\0200\0251' '\0342\0200\0257' \
  '\0342\0201\0237' '\0343\0200\0200'; do
  printf -v _fm_composer_space_utf8 '%b' "$_fm_composer_space_octal"
  FM_COMPOSER_UNICODE_SPACES+=("$_fm_composer_space_utf8")
done
unset -v _fm_composer_space_octal _fm_composer_space_utf8

# fm_composer_normalize_spaces_var: the ONE Unicode-whitespace mapping.
# Replaces in place through the named variable so no caller needs a subshell.
# Substitution, never deletion: deleting would silently join "foo<NBSP>bar"
# into one token, while a space preserves the separation the harness drew.
fm_composer_normalize_spaces_var() {  # <varname>
  local __fmns_name=$1 __fmns_text=${!1} __fmns_space
  for __fmns_space in "${FM_COMPOSER_UNICODE_SPACES[@]}"; do
    __fmns_text=${__fmns_text//"$__fmns_space"/ }
  done
  printf -v "$__fmns_name" '%s' "$__fmns_text"
}

# fm_composer_normalize_trim_var: the one whitespace-normalizing trim shared by
# this owner and every structural row scan - map Unicode whitespace onto ASCII
# space, then strip leading and trailing whitespace, in place through the named
# variable. Idempotent, locale-independent.
fm_composer_normalize_trim_var() {  # <varname>
  local __fmnt_name=$1 __fmnt_text
  fm_composer_normalize_spaces_var "$__fmnt_name"
  __fmnt_text=${!__fmnt_name}
  __fmnt_text="${__fmnt_text#"${__fmnt_text%%[![:space:]]*}"}"
  __fmnt_text="${__fmnt_text%"${__fmnt_text##*[![:space:]]}"}"
  printf -v "$__fmnt_name" '%s' "$__fmnt_text"
}

# fm_composer_strip_ghost: the ONE fleet-wide ANSI-aware extractor of "real typed
# content" from a captured, styled composer row. Reads the styled line on stdin
# (from `tmux capture-pane -e`, `herdr pane read --format ansi`, or
# a styled capture) and prints the
# plain, non-ghost text on stdout, dropping:
#   - dim/faint runs (SGR 2): de-emphasized suggestion text.
#     A reset (SGR 0) or normal-intensity (SGR 22) ends a dim run.
# Codes are processed left to right within a sequence, so "ESC[0;2m" reads as dim.
# LC_ALL=C makes awk walk bytes, so multibyte glyphs (e.g. ❯) and de-emphasised
# runs alike pass through or drop intact without locale-dependent classes.
fm_composer_strip_ghost() {
  LC_ALL=C awk '
    function sgr_code(v, b) {
      b = v
      sub(/:.*/, "", b)
      if (b == "") b = "0"
      return b
    }
    function skip_color_payload(a, p, k, mode, code) {
      if (index(a[p], ":") > 0) return p
      if (p >= k) return p
      mode = a[p + 1]
      code = sgr_code(mode)
      if (index(mode, ":") > 0) return p + 1
      if (code == "5") return p + 2
      if (code == "2") return p + 4
      return p + 1
    }
    {
      line = $0; out = ""; dim = 0; n = length(line); i = 1
      while (i <= n) {
        c = substr(line, i, 1)
        if (c == "\033") {            # ESC: consume a CSI ... final-byte sequence
          j = i + 1
          if (substr(line, j, 1) == "[") {
            j++; params = ""
            while (j <= n) {
              cc = substr(line, j, 1)
              if (cc ~ /[@-~]/) break
              params = params cc; j++
            }
            if (j <= n && substr(line, j, 1) == "m") {   # SGR: update de-emphasis
              if (params == "") params = "0"
              k = split(params, a, ";")
              for (p = 1; p <= k; p++) {
                v = a[p]; code = sgr_code(v)
                if (code == "38" || code == "48" || code == "58") {
                  p = skip_color_payload(a, p, k)
                } else if (code == "2") dim = 1
                else if (code == "0") dim = 0
                else if (code == "22") dim = 0
              }
            }
            if (j <= n) { i = j + 1; continue }
          }
          i = i + 1; continue          # lone/other ESC: drop the ESC byte only
        }
        if (dim == 0) out = out c   # keep only non-de-emphasised bytes
        i++
      }
      print out
    }
  '
}


# --- Delivery-only rendered busy footers (backend-agnostic) -------------------
#
# These live here, in the ONE shared composer/delivery owner, rather than in any
# single backend adapter, because every backend needs them for the SAME job:
# proving a submitted Enter actually landed. Keeping them in bin/fm-tmux-lib.sh
# would make signatures reachable only from tmux, even though Herdr runs the
# same harnesses and faces the same acknowledgement problem.
#
# This is a DELIVERY guard, deliberately NOT a worker-state source. The semantic
# busy contract - what firstmate records and supervises on - is owned by
# bin/fm-busy-lib.sh, which forbids classifying a harness from rendered text.
# Matching a footer to confirm a keystroke landed is a different question from
# asking what a worker is doing, and the two must not be conflated.
# Delivery-only rendered busy footers per harness. Pi renders "Working...".
# The harness-less default is the UNION of the per-harness tokens below, used
# when a caller has no recorded harness for the pane (the submit cores read the
# baseline and the post-Enter transition this way).
FM_DELIVERY_BUSY_REGEX_DEFAULT='Working\.\.\.'
FM_DELIVERY_PI_BUSY_REGEX_DEFAULT='Working\.\.\.'

fm_busy_lines_match() {  # [harness]
  local harness=${1:-} lines regex
  IFS= read -r -d '' lines || true
  if [ -n "${FM_BUSY_REGEX:-}" ]; then
    regex=$FM_BUSY_REGEX
  else
    case "$harness" in
      pi) regex=$FM_DELIVERY_PI_BUSY_REGEX_DEFAULT ;;
      '') regex=$FM_DELIVERY_BUSY_REGEX_DEFAULT ;;
      *)
        # A supplied harness must never borrow another harness's signature.
        # Register its verified signature explicitly before classifying it busy.
        regex=
        ;;
    esac
  fi
  [ -n "$regex" ] && printf '%s' "$lines" | grep -qiE "$regex"
}

# Shell prompt glyphs are genuine empty composers only inside a verified
# composer container. Newline-separated and consumed by `read` rather than
# word splitting, so `$`, `%`, and `#` stay literal and no entry is ever
# exposed to pathname expansion.
FM_COMPOSER_SHELL_PROMPT_GLYPHS=$(printf '%s\n' '>' '❯' '$' '%' '#')

# FM_COMPOSER_IDLE_RE lets an unverified harness declare composer text it
# renders in an empty composer that a plain capture cannot distinguish from
# typed text. The default deliberately matches nothing.
FM_COMPOSER_IDLE_RE_DEFAULT='a^'

# The bounded row window adapters should capture for a composer read. One
# shared policy (previously three per-backend variables that had drifted to
# 20/20/200): the composer is bottom-anchored, so a small tail window is
# sufficient and keeps stale scrollback (startup banners, old transcript
# boxes) from ever competing with the live composer.
FM_COMPOSER_CAPTURE_LINES=${FM_COMPOSER_CAPTURE_LINES:-20}

# Pi allows a multi-line composer between its horizontal separators. Bound the
# structural candidate so two unrelated transcript rules with an arbitrarily
# large region between them can never be promoted into a composer.
FM_COMPOSER_PI_MAX_LINES=${FM_COMPOSER_PI_MAX_LINES:-8}

# 0 when <content> is exactly one glyph drawn from <glyph-list>.
_fm_composer_is_prompt_glyph() {  # <content> <glyph-list>
  local content=$1 glyph
  while IFS= read -r glyph; do
    [ -n "$glyph" ] || continue
    [ "$content" = "$glyph" ] && return 0
  done <<EOF
$2
EOF
  return 1
}

# fm_composer_leading_prompt_glyph_var: set <out-varname> to the ONE prompt
# glyph <content> begins with once its leading whitespace is ignored, or to the
# empty string (returning 1) when it begins with none. Both glyph lists are
# reached here, so no caller can respell them and drift. Returning the matched
# glyph as a LITERAL string lets every caller remove it byte-exactly with
# `${v#"$glyph"}`, which is correct in every locale.
fm_composer_leading_prompt_glyph_var() {  # <out-varname> <content>
  local __fmpg_out=$1 __fmpg_text=$2 __fmpg_glyph
  __fmpg_text="${__fmpg_text#"${__fmpg_text%%[![:space:]]*}"}"
  while IFS= read -r __fmpg_glyph; do
    [ -n "$__fmpg_glyph" ] || continue
    case "$__fmpg_text" in
      "$__fmpg_glyph"*) printf -v "$__fmpg_out" '%s' "$__fmpg_glyph"; return 0 ;;
    esac
  done <<EOF
$FM_COMPOSER_SHELL_PROMPT_GLYPHS
EOF
  printf -v "$__fmpg_out" '%s' ''
  return 1
}

fm_composer_leading_shell_glyph_var() {  # <out-varname> <content>
  local __fmsg_out=$1 __fmsg_text=$2 __fmsg_glyph
  __fmsg_text="${__fmsg_text#"${__fmsg_text%%[![:space:]]*}"}"
  while IFS= read -r __fmsg_glyph; do
    [ -n "$__fmsg_glyph" ] || continue
    case "$__fmsg_text" in
      "$__fmsg_glyph"*) printf -v "$__fmsg_out" '%s' "$__fmsg_glyph"; return 0 ;;
    esac
  done <<EOF
$FM_COMPOSER_SHELL_PROMPT_GLYPHS
EOF
  printf -v "$__fmsg_out" '%s' ''
  return 1
}

fm_composer_idle_matches() {
  local content=$1 idle_re=$2 idle_case=$3
  [ -n "$idle_re" ] || return 1
  case "$idle_case" in
    insensitive) printf '%s' "$content" | grep -qiE "$idle_re" ;;
    *) printf '%s' "$content" | grep -qE "$idle_re" ;;
  esac
}

# fm_composer_classify_content: the single shared composer-content verdict.
#   <bordered> 1 when <content> came from a genuine agent-composer container (a
#              bordered composer box or an identity-proven separated composer).
#   <content>  the candidate composer content, border-stripped by the caller.
#   [idle_re]  optional idle-placeholder regex; empty means no idle matching.
#              The screen classifier below passes the resolved fleet-wide idle
#              set; this parameter stays pure so a direct caller's semantics
#              cannot shift underneath it.
#   [idle_case] `sensitive` (default) or `insensitive`.
#   [plain_content] the unstripped plain row.
# Content and plain_content are normalized and re-trimmed on entry, so the
# verdict never depends on which whitespace alphabet the calling adapter
# trimmed with.
fm_composer_classify_content() {  # <bordered> <content> [idle_re] [idle_case] [plain_content] [placeholder-position] [styled]
  local bordered=$1 idle_re=${3:-} idle_case=${4:-sensitive} content plain_content glyph=''
  local placeholder_position=${6:-0} styled=${7:-1} idle_collision=0
  content=$2
  fm_composer_normalize_trim_var content
  plain_content=${5:-$2}
  fm_composer_normalize_trim_var plain_content
  if [ "$bordered" != 1 ] && [ -z "$content" ] && [ -n "$plain_content" ]; then
    printf 'unknown'; return 0
  fi
  if _fm_composer_is_prompt_glyph "$content" "$FM_COMPOSER_SHELL_PROMPT_GLYPHS"; then
    if [ "$bordered" = 1 ]; then printf 'empty'; else printf 'unknown'; fi
    return 0
  fi
  [ -n "$content" ] || { printf 'empty'; return 0; }
  fm_composer_idle_matches "$content" "$idle_re" "$idle_case" && idle_collision=1
  if fm_composer_leading_prompt_glyph_var glyph "$content"; then
    content=${content#*"$glyph"}
  fi
  fm_composer_normalize_trim_var content
  [ -n "$content" ] || { printf 'empty'; return 0; }
  fm_composer_idle_matches "$content" "$idle_re" "$idle_case" && idle_collision=1
  if [ "$idle_collision" = 1 ]; then
    if [ "$placeholder_position" = 1 ] && [ "$bordered" = 1 ] && [ "$styled" != 1 ]; then
      printf 'empty'; return 0
    fi
    if [ "$styled" != 1 ]; then
      printf 'unknown'; return 0
    fi
  fi
  printf 'pending'; return 0
}

# --- The screen classifier ---------------------------------------------------
#
# fm_composer_classify_screen <caps> <screen> [cursor_row] [identity]
#   <caps>       newline-separated key=value capability facts (see header).
#   <screen>     the captured screen: ANSI-preserving when styled=1, plain
#                otherwise.
#   [cursor_row] zero-based row index of the cursor within <screen>, only
#                meaningful when caps carry cursor=1.
#   [identity]   "<agent>\t<status>" from the backend's native identity probe,
#                or `probe-absent` when the probe found no live identity; only
#                meaningful when caps carry identity=1.
# Prints exactly one verdict: empty | pending | pending-unproven | unknown,
# or the internal sentinel `need-identity` when caps declare identity=1, no
# identity result was supplied, and the verdict depends on it. Adapters answer
# `need-identity` by running their identity probe once and re-calling with
# either its result or `probe-absent`; the sentinel never escapes an adapter.
# Identity stays a lazy second pass so the common non-pi read never pays for
# the probe.
#
# Consumers that can overwrite input or confirm delivery must accept only the
# exact positive proof they require (`empty`), so unrecognized future verdicts
# fail safe by default.

# _fm_composer_pi_separator_row: a solid pi separator - nothing but `─`, at
# least 8 columns wide. The width floor is a literal substring test so it is
# byte-exact in every locale.
_fm_composer_pi_separator_row() {  # <trimmed-row>
  local row=$1
  [ -n "$row" ] || return 1
  [ -z "${row//─/}" ] || return 1
  case "$row" in
    *────────*) return 0 ;;
  esac
  return 1
}

# Row-scan results are returned through FM_COMPOSER_SCAN_* globals (bash 3.2
# has no nameref); they are internal to this owner.
_fm_composer_scan_screen() {  # <plain-screen> <cursor-or-empty> [extract-wrap]
  local pane=$1 cy=${2:-}
  local line indent left_stripped trimmed kind family side_family
  local top_inner top_spaces='' geometry_check=0 geometry_ambiguous=0
  local content_inner content_spaces bottom_inner bottom_spaces glyph
  local current_indent='' current_family='' row=0 top=-1 valid=0 content_rows=0
  # Complete-box results: the box containing the cursor (cursor mode) or the
  # bottom-most complete box (no cursor).
  FM_COMPOSER_SCAN_BOX_TOP=-1
  FM_COMPOSER_SCAN_BOX_BOTTOM=-1
  FM_COMPOSER_SCAN_BOX_AMBIG=0
  FM_COMPOSER_SCAN_INCOMPLETE_BOX_FROM=-1
  FM_COMPOSER_SCAN_UNSAFE=0
  FM_COMPOSER_SCAN_CURSOR_EDGE=0
  FM_COMPOSER_SCAN_SHELL_ROW=-1
  FM_COMPOSER_SCAN_PI_PAIR_FOUND=0
  FM_COMPOSER_SCAN_PI_PAIR_VALID=0
  FM_COMPOSER_SCAN_PI_OPEN=-1
  FM_COMPOSER_SCAN_PI_CLOSE=-1
  FM_COMPOSER_SCAN_PI_LAST_SEPARATOR=-1
  local pi_open=-1 pi_lines=0 pi_max
  pi_max=$FM_COMPOSER_PI_MAX_LINES
  case "$pi_max" in ''|*[!0-9]*|0) pi_max=8 ;; esac
  while IFS= read -r line; do
    indent=${line%%[![:space:]]*}
    left_stripped="${line#"${line%%[![:space:]]*}"}"
    trimmed=$left_stripped
    fm_composer_normalize_trim_var trimmed
    kind=
    family=
    case "$trimmed" in
      '╭'*'╮') kind=top; family=rounded ;;
      '┌'*'┐') kind=top; family=light ;;
      '╔'*'╗') kind=top; family=double ;;
      '┏'*'┓') kind=top; family=heavy ;;
      '╰'*'╯') kind=bottom; family=rounded ;;
      '└'*'┘') kind=bottom; family=light ;;
      '╚'*'╝') kind=bottom; family=double ;;
      '┗'*'┛') kind=bottom; family=heavy ;;
      '+'*'+') kind=ascii; family=ascii ;;
    esac
    # Pi separator rows: a solid `─` rule at least 8 columns wide. A separator
    # closes the preceding candidate and immediately opens the next, so an
    # earlier transcript rule can never outrank the live bottom composer pair.
    if _fm_composer_pi_separator_row "$trimmed"; then
      FM_COMPOSER_SCAN_PI_LAST_SEPARATOR=$row
      if [ "$pi_open" -ge 0 ]; then
        FM_COMPOSER_SCAN_PI_PAIR_FOUND=1
        FM_COMPOSER_SCAN_PI_OPEN=$pi_open
        FM_COMPOSER_SCAN_PI_CLOSE=$row
        if [ "$pi_lines" -le "$pi_max" ]; then
          FM_COMPOSER_SCAN_PI_PAIR_VALID=1
        else
          FM_COMPOSER_SCAN_PI_PAIR_VALID=0
        fi
      fi
      pi_open=$row
      pi_lines=0
    elif [ "$pi_open" -ge 0 ]; then
      pi_lines=$((pi_lines + 1))
    fi
    # Keep lower shell prompts as staleness evidence for cursorless selection.
    if [ "$top" -lt 0 ] && fm_composer_leading_shell_glyph_var glyph "$trimmed"; then
      FM_COMPOSER_SCAN_SHELL_ROW=$row
    fi
    # Terminal-cursor safety: a cursor sitting on a structural edge row is never an
    # input row.
    if [ -n "$cy" ] && [ "$row" -eq "$cy" ] && fm_composer_row_has_edge "$trimmed"; then
      FM_COMPOSER_SCAN_CURSOR_EDGE=1
    fi
    # Complete-box state machine (all border families, geometry, ambiguity).
    if [ "$kind" = top ] || { [ "$kind" = ascii ] && [ "$top" -lt 0 ]; }; then
      if [ -n "$cy" ] && [ "$top" -ge 0 ] && [ "$top" -lt "$cy" ] && [ "$cy" -le "$row" ]; then
        FM_COMPOSER_SCAN_UNSAFE=1
      fi
      top=$row
      FM_COMPOSER_SCAN_INCOMPLETE_BOX_FROM=$row
      current_family=$family
      current_indent=$indent
      valid=1
      content_rows=0
      geometry_ambiguous=0
      geometry_check=1
      top_inner=$trimmed
      case "$family" in
        rounded) top_inner=${top_inner#╭}; top_inner=${top_inner%╮}; top_spaces=${top_inner//─/ } ;;
        light) top_inner=${top_inner#┌}; top_inner=${top_inner%┐}; top_spaces=${top_inner//─/ } ;;
        double) top_inner=${top_inner#╔}; top_inner=${top_inner%╗}; top_spaces=${top_inner//═/ } ;;
        heavy) top_inner=${top_inner#┏}; top_inner=${top_inner%┓}; top_spaces=${top_inner//━/ } ;;
        ascii) top_inner=${top_inner#+}; top_inner=${top_inner%+}; top_spaces=${top_inner//-/ } ;;
      esac
      case "$top_spaces" in
        *[![:space:]]*) geometry_check=0; geometry_ambiguous=1 ;;
      esac
    elif [ "$kind" = bottom ] || { [ "$kind" = ascii ] && [ "$top" -ge 0 ]; }; then
      if [ "$top" -ge 0 ] && [ "$family" = "$current_family" ] \
         && [ "$valid" = 1 ] && [ "$content_rows" -gt 0 ]; then
        [ "$indent" = "$current_indent" ] || geometry_ambiguous=1
        if [ "$geometry_check" = 1 ]; then
          bottom_inner=$trimmed
          case "$family" in
            rounded) bottom_inner=${bottom_inner#╰}; bottom_inner=${bottom_inner%╯}; bottom_spaces=${bottom_inner//─/ } ;;
            light) bottom_inner=${bottom_inner#└}; bottom_inner=${bottom_inner%┘}; bottom_spaces=${bottom_inner//─/ } ;;
            double) bottom_inner=${bottom_inner#╚}; bottom_inner=${bottom_inner%╝}; bottom_spaces=${bottom_inner//═/ } ;;
            heavy) bottom_inner=${bottom_inner#┗}; bottom_inner=${bottom_inner%┛}; bottom_spaces=${bottom_inner//━/ } ;;
            ascii) bottom_inner=${bottom_inner#+}; bottom_inner=${bottom_inner%+}; bottom_spaces=${bottom_inner//-/ } ;;
          esac
          if [ "$bottom_spaces" != "$top_spaces" ]; then
            geometry_ambiguous=1
          fi
        fi
        if [ -n "$cy" ]; then
          if [ "$top" -lt "$cy" ] && [ "$cy" -le "$row" ]; then
            FM_COMPOSER_SCAN_BOX_TOP=$top
            FM_COMPOSER_SCAN_BOX_BOTTOM=$row
            FM_COMPOSER_SCAN_BOX_AMBIG=$geometry_ambiguous
          fi
        else
          FM_COMPOSER_SCAN_BOX_TOP=$top
          FM_COMPOSER_SCAN_BOX_BOTTOM=$row
          FM_COMPOSER_SCAN_BOX_AMBIG=$geometry_ambiguous
        fi
        FM_COMPOSER_SCAN_INCOMPLETE_BOX_FROM=-1
      else
        if [ "$FM_COMPOSER_SCAN_INCOMPLETE_BOX_FROM" -lt 0 ]; then
          FM_COMPOSER_SCAN_INCOMPLETE_BOX_FROM=$row
        fi
        if [ -n "$cy" ]; then
          if { [ "$top" -ge 0 ] && [ "$top" -lt "$cy" ] && [ "$cy" -le "$row" ]; } \
             || [ "$row" -eq "$cy" ]; then
            FM_COMPOSER_SCAN_UNSAFE=1
          fi
        fi
      fi
      top=-1
      current_family=
      current_indent=
      valid=0
      content_rows=0
    elif [ "$top" -ge 0 ]; then
      side_family=
      case "$trimmed" in
        '│'*'│') side_family=single ;;
        '┃'*'┃') side_family=heavy ;;
        '║'*'║') side_family=double ;;
        '|'*'|') side_family=ascii ;;
      esac
      case "$current_family:$side_family" in
        rounded:single|light:single|heavy:heavy|double:double|ascii:ascii)
          content_rows=$((content_rows + 1))
          [ "$indent" = "$current_indent" ] || geometry_ambiguous=1
          if [ "$geometry_check" = 1 ]; then
            content_inner=$trimmed
            case "$side_family" in
              single) content_inner=${content_inner#│}; content_inner=${content_inner%│} ;;
              heavy) content_inner=${content_inner#┃}; content_inner=${content_inner%┃} ;;
              double) content_inner=${content_inner#║}; content_inner=${content_inner%║} ;;
              ascii) content_inner=${content_inner#|}; content_inner=${content_inner%|} ;;
            esac
            if content_spaces=$(fm_composer_geometry_spaces "$content_inner"); then
              [ "$content_spaces" = "$top_spaces" ] || geometry_ambiguous=1
            else
              geometry_ambiguous=1
            fi
          fi
          ;;
        *) valid=0 ;;
      esac
    fi
    row=$((row + 1))
  done <<EOF
$pane
EOF
  if [ -n "$cy" ] && [ "$top" -ge 0 ] && [ "$top" -lt "$cy" ]; then
    FM_COMPOSER_SCAN_UNSAFE=1
  fi
}

# fm_composer_row_has_edge: 0 when the trimmed row starts or ends with a
# box-drawing/edge glyph - a structural row, never an input row.
# Half-block glyphs used by supported composers are edges too.
fm_composer_row_has_edge() {  # <trimmed-row>
  local row=$1
  fm_composer_normalize_trim_var row
  case "$row" in
    '│'*|*'│'|'┃'*|*'┃'|'║'*|*'║'|'╭'*|*'╭'|'╮'*|*'╮'|\
    '┌'*|*'┌'|'┐'*|*'┐'|'╔'*|*'╔'|'╗'*|*'╗'|'┏'*|*'┏'|'┓'*|*'┓'|\
    '╰'*|*'╰'|'╯'*|*'╯'|'└'*|*'└'|'┘'*|*'┘'|'╚'*|*'╚'|'╝'*|*'╝'|\
    '┗'*|*'┗'|'┛'*|*'┛'|'─'*|*'─'|'━'*|*'━'|'═'*|*'═'|'|'*|*'|'|'+'*|*'+'|\
    '▀'*|*'▀'|'▁'*|*'▁'|'▔'*|*'▔')
      return 0
      ;;
  esac
  return 1
}

# fm_composer_geometry_spaces: prove a box content row blank to the same width
# as its border. One leading prompt glyph is blanked (every prompt glyph
# occupies one column), the content is normalized so a Unicode space cannot
# defeat the blankness proof, then every remaining ASCII-printable is mapped to
# a space; any other residue fails the proof.
fm_composer_geometry_spaces() {  # <content-inner> -> spaces
  local content=$1 glyph
  fm_composer_normalize_spaces_var content
  if fm_composer_leading_prompt_glyph_var glyph "$content"; then
    content=${content/"$glyph"/ }
  fi
  content=$(printf '%s' "$content" | LC_ALL=C sed 's/[!-~]/ /g')
  case "$content" in
    *[![:space:]]*) return 1 ;;
  esac
  printf '%s' "$content"
}

# _fm_composer_screen_row: print row <n> (zero-based) of <screen>.
_fm_composer_screen_row() {  # <n> <screen>
  printf '%s\n' "$2" | sed -n "$(($1 + 1))p"
}

# _fm_composer_row_content: extract the classification content of one raw row:
# ghost-strip when styled, plain otherwise, normalize-trim, and strip one
# matching pair of side border glyphs.
_fm_composer_row_content() {  # <raw-row> <styled> -> content on stdout
  local raw=$1 styled=$2 stripped
  if [ "$styled" = 1 ]; then
    stripped=$(printf '%s\n' "$raw" | fm_composer_strip_ghost)
  else
    stripped=$(printf '%s\n' "$raw" | fm_composer_strip_ansi)
  fi
  fm_composer_normalize_trim_var stripped
  case "$stripped" in
    '│'*'│') stripped=${stripped#│}; stripped=${stripped%│} ;;
    '┃'*'┃') stripped=${stripped#┃}; stripped=${stripped%┃} ;;
    '║'*'║') stripped=${stripped#║}; stripped=${stripped%║} ;;
    '|'*'|') stripped=${stripped#|}; stripped=${stripped%|} ;;
  esac
  fm_composer_normalize_trim_var stripped
  printf '%s' "$stripped"
}

# _fm_composer_classify_rows: shared multi-row container verdict for the box
# and separated shapes: pending beats empty, an unreadable row is unknown, and
# geometry ambiguity turns pending into pending-unproven and empty into
# unknown (an ambiguous container is not positive proof).
_fm_composer_classify_rows() {  # <screen> <styled> <ambiguous> <first-row> <last-row>
  local screen=$1 styled=$2 ambiguous=$3 first=$4 last=$5
  local row raw content plain state unknown_seen=0
  row=$first
  while [ "$row" -le "$last" ]; do
    raw=$(_fm_composer_screen_row "$row" "$screen")
    content=$(_fm_composer_row_content "$raw" "$styled")
    plain=$(_fm_composer_row_content "$raw" 0)
    state=$(fm_composer_classify_content 1 "$content" \
      "${FM_COMPOSER_IDLE_RE:-$FM_COMPOSER_IDLE_RE_DEFAULT}" insensitive "$plain" 1 "$styled")
    case "$state" in
      pending)
        if [ "$ambiguous" = 1 ]; then printf 'pending-unproven'; else printf 'pending'; fi
        return 0
        ;;
      unknown) unknown_seen=1 ;;
    esac
    row=$((row + 1))
  done
  if [ "$unknown_seen" = 1 ] || [ "$ambiguous" = 1 ]; then
    printf 'unknown'
  else
    printf 'empty'
  fi
}

_fm_composer_select_cursorless() {
  local plain=$1 generic=-1 next boundary raw trimmed
  FM_COMPOSER_SELECTED_KIND=
  FM_COMPOSER_SELECTED_FIRST=-1
  FM_COMPOSER_SELECTED_LAST=-1
  FM_COMPOSER_SELECTED_AMBIG=0
  if [ "$FM_COMPOSER_SCAN_BOX_BOTTOM" -ge 0 ]; then
    generic=$FM_COMPOSER_SCAN_BOX_BOTTOM
    FM_COMPOSER_SELECTED_KIND=box
    FM_COMPOSER_SELECTED_FIRST=$((FM_COMPOSER_SCAN_BOX_TOP + 1))
    FM_COMPOSER_SELECTED_LAST=$((FM_COMPOSER_SCAN_BOX_BOTTOM - 1))
    FM_COMPOSER_SELECTED_AMBIG=$FM_COMPOSER_SCAN_BOX_AMBIG
  fi
  if [ "$FM_COMPOSER_SCAN_INCOMPLETE_BOX_FROM" -gt "$generic" ]; then
    FM_COMPOSER_SELECTED_KIND=
    return 1
  fi
  if [ "$FM_COMPOSER_SCAN_PI_PAIR_FOUND" = 1 ] \
     && [ "$FM_COMPOSER_SCAN_PI_CLOSE" -gt "$generic" ] \
     && [ "$generic" -lt "$FM_COMPOSER_SCAN_PI_OPEN" ]; then
    generic=$FM_COMPOSER_SCAN_PI_CLOSE
    FM_COMPOSER_SELECTED_KIND=pi
    FM_COMPOSER_SELECTED_FIRST=$((FM_COMPOSER_SCAN_PI_OPEN + 1))
    FM_COMPOSER_SELECTED_LAST=$((FM_COMPOSER_SCAN_PI_CLOSE - 1))
  fi
  if [ "$FM_COMPOSER_SCAN_PI_PAIR_FOUND" = 0 ] \
     && [ "$FM_COMPOSER_SCAN_PI_LAST_SEPARATOR" -gt "$generic" ]; then
    FM_COMPOSER_SELECTED_KIND=
    return 1
  fi
  if [ "$FM_COMPOSER_SCAN_SHELL_ROW" -gt "$generic" ]; then
    FM_COMPOSER_SELECTED_KIND=
    return 1
  fi
  if [ "$FM_COMPOSER_SELECTED_KIND" = box ]; then
    boundary=$FM_COMPOSER_SCAN_BOX_BOTTOM
    next=$((boundary + 1))
    raw=$(_fm_composer_screen_row "$next" "$plain")
    trimmed=$raw
    fm_composer_normalize_trim_var trimmed
    if [ -n "$trimmed" ] && ! fm_composer_row_has_edge "$trimmed"; then
      FM_COMPOSER_SELECTED_KIND=
      return 1
    fi
  fi
  [ -n "$FM_COMPOSER_SELECTED_KIND" ]
}

fm_composer_extract_selected_content() {  # <caps> <screen>
  local caps=$1 screen=$2 styled=0 kv plain row raw content glyph joined='' prompt_row=-1
  local placeholder_position=0 prompt_is_shell=0
  while IFS= read -r kv; do
    [ "$kv" = styled=1 ] && styled=1
  done <<EOF
$caps
EOF
  plain=$(printf '%s\n' "$screen" | fm_composer_strip_ansi)
  _fm_composer_scan_screen "$plain" '' 1
  _fm_composer_select_cursorless "$plain" || return 1
  row=$FM_COMPOSER_SELECTED_FIRST
  while [ "$row" -le "$FM_COMPOSER_SELECTED_LAST" ]; do
    raw=$(_fm_composer_screen_row "$row" "$screen")
    content=$(_fm_composer_row_content "$raw" "$styled")
    placeholder_position=0
    case "$FM_COMPOSER_SELECTED_KIND" in
      box)
        if [ "$prompt_row" -lt 0 ] \
           && fm_composer_leading_prompt_glyph_var glyph "$content"; then
          prompt_row=$row
          placeholder_position=1
          if _fm_composer_is_prompt_glyph "$glyph" "$FM_COMPOSER_SHELL_PROMPT_GLYPHS"; then
            prompt_is_shell=1
          fi
          content=${content#*"$glyph"}
        elif [ "$prompt_row" -lt 0 ]; then
          placeholder_position=1
        fi
        ;;
    esac
    fm_composer_normalize_spaces_var content
    fm_composer_normalize_trim_var content
    # A styled agent-glyph placeholder disappears above when ghost stripping
    # proves it is furniture. If the same placeholder-looking bytes survive
    # styling, they are real user input and must remain in the extracted content.
    # An unstyled boxed placeholder has no styling proof, so its structurally
    # fixed position remains the idle-regex exception here.
    if [ -z "$content" ] \
       || { [ "$FM_COMPOSER_SELECTED_KIND" = box ] && [ "$prompt_is_shell" = 1 ] && [ "$styled" != 1 ] \
            && [ "$placeholder_position" = 1 ] \
            && fm_composer_idle_matches "$content" "${FM_COMPOSER_IDLE_RE:-$FM_COMPOSER_IDLE_RE_DEFAULT}" insensitive; }; then
      row=$((row + 1))
      continue
    fi
    joined="${joined}${joined:+ }$content"
    row=$((row + 1))
  done
  printf '%s\n' "$joined" | LC_ALL=C awk '{$1=$1; printf "%s", $0}'
}

fm_composer_classify_screen() {  # <caps> <screen> [cursor_row] [identity]
  local caps=$1 screen=$2 cy=${3:-} identity=${4:-}
  local styled=0 cursor=0 has_identity=0 kv plain
  while IFS= read -r kv; do
    case "$kv" in
      styled=1) styled=1 ;;
      cursor=1) cursor=1 ;;
      identity=1) has_identity=1 ;;
    esac
  done <<EOF
$caps
EOF
  [ "$cursor" = 1 ] || cy=''
  if [ -n "$cy" ]; then
    case "$cy" in *[!0-9]*) printf 'unknown'; return 0 ;; esac
  fi
  plain=$(printf '%s\n' "$screen" | fm_composer_strip_ansi)
  _fm_composer_scan_screen "$plain" "$cy"
  if [ -n "$cy" ]; then
    # In cursor mode (tmux), the shape CONTAINING the cursor is the composer.
    if [ "$FM_COMPOSER_SCAN_UNSAFE" = 1 ]; then
      printf 'unknown'; return 0
    fi
    if [ "$FM_COMPOSER_SCAN_BOX_TOP" -ge 0 ]; then
      _fm_composer_classify_rows "$screen" "$styled" "$FM_COMPOSER_SCAN_BOX_AMBIG" \
        "$((FM_COMPOSER_SCAN_BOX_TOP + 1))" "$((FM_COMPOSER_SCAN_BOX_BOTTOM - 1))"
      return 0
    fi
    if [ "$FM_COMPOSER_SCAN_PI_PAIR_FOUND" = 1 ] \
       && [ "$cy" -gt "$FM_COMPOSER_SCAN_PI_OPEN" ] \
       && [ "$cy" -lt "$FM_COMPOSER_SCAN_PI_CLOSE" ]; then
      _fm_composer_pi_verdict "$screen" "$styled" "$has_identity" "$identity"
      return 0
    fi
    if [ "$FM_COMPOSER_SCAN_CURSOR_EDGE" = 1 ]; then
      printf 'unknown'; return 0
    fi
    # STRICT: a blank or otherwise unidentified cursor row has no positive
    # container proof. This replaced the permissive blank-cursor-row rule
    # (captain decision blank-row-injection-posture).
    printf 'unknown'
    return 0
  fi
  # No cursor: the bottom-most shape wins, with the pi-separator staleness
  # rules layered on (a live pi composer pair below the generic candidate
  # proves that candidate stale).
  if ! _fm_composer_select_cursorless "$plain"; then
    printf 'unknown'
    return 0
  fi
  case "$FM_COMPOSER_SELECTED_KIND" in
    pi)
      _fm_composer_pi_verdict "$screen" "$styled" "$has_identity" "$identity"
      ;;
    box)
      _fm_composer_classify_rows "$screen" "$styled" "$FM_COMPOSER_SELECTED_AMBIG" \
        "$FM_COMPOSER_SELECTED_FIRST" "$FM_COMPOSER_SELECTED_LAST"
      ;;
  esac
}

# fm_composer_submit_retry_core: the ONE verify-and-retry-Enter submit loop
# for cursor-less capture paths, parameterised by the
# adapter's send-key and composer-state functions. The caller has already
# typed the text ONCE (send_literal) and settled; this loop submits with
# Enter, re-reading the composer verdict, and retries Enter ONLY - never
# retypes, because a swallowed Enter leaves the text in the composer and
# retyping would duplicate it. Proven pending (and pending-unproven) retries
# consume the budget; any other verdict returns immediately, so `unknown`
# stays a loud refusal rather than a blind retry into an unreadable pane.
# tmux keeps its own richer core (bin/fm-tmux-lib.sh: the idle-baseline
# turn-started conversion its busy primitive enables), and
# herdr confirms through native agent-state; both consume the same shared
# verdict, so no shape knowledge lives in any of the three loops.
fm_composer_submit_retry_core() {  # <send-key-fn> <state-fn> <target> <retries> <enter-sleep> [expected-label]
  local send_key_fn=$1 state_fn=$2 target=$3 retries=$4 sleep_s=$5 expected_label=${6:-} i=0 state
  while :; do
    "$send_key_fn" "$target" Enter "$expected_label" || true
    sleep "$sleep_s"
    state=$("$state_fn" "$target" "$expected_label")
    case "$state" in
      pending|pending-unproven) ;;
      *) printf '%s' "$state"; return 0 ;;
    esac
    i=$((i + 1))
    [ "$i" -lt "$retries" ] || { printf '%s' "$state"; return 0; }
  done
}

_fm_composer_classify_pi_rows() {  # <screen> <styled>
  local screen=$1 styled=$2 row raw content
  row=$((FM_COMPOSER_SCAN_PI_OPEN + 1))
  while [ "$row" -lt "$FM_COMPOSER_SCAN_PI_CLOSE" ]; do
    raw=$(_fm_composer_screen_row "$row" "$screen")
    content=$(_fm_composer_row_content "$raw" "$styled")
    fm_composer_normalize_trim_var content
    if [ -n "$content" ]; then
      printf 'pending'
      return 0
    fi
    row=$((row + 1))
  done
  printf 'empty'
}

# The pi separated-shape verdict: identity + structure conjunction (herdr's
# rule, now fleet-wide). A missing identity capability keeps the shape
# unknown; an unfetched identity on an identity-capable backend asks the
# adapter to probe (lazily) and re-call. Proven input remains pending for every
# live pi state, while only an idle/done/blocked pi proves an empty composer.
_fm_composer_pi_verdict() {  # <screen> <styled> <has_identity> <identity>
  local screen=$1 styled=$2 has_identity=$3 identity=$4 agent agent_status state
  if [ "$has_identity" != 1 ]; then
    printf 'unknown'
    return 0
  fi
  if [ -z "$identity" ]; then
    printf 'need-identity'
    return 0
  fi
  if [ "$identity" = probe-absent ]; then
    printf 'unknown'
    return 0
  fi
  agent=${identity%%$'\t'*}
  agent_status=${identity#*$'\t'}
  if [ "$agent" != pi ] || [ "$FM_COMPOSER_SCAN_PI_PAIR_VALID" != 1 ]; then
    printf 'unknown'
    return 0
  fi
  state=$(_fm_composer_classify_pi_rows "$screen" "$styled")
  if [ "$state" = pending ]; then
    printf 'pending'
    return 0
  fi
  case "$agent_status" in
    idle|done|blocked) printf 'empty' ;;
    *) printf 'unknown' ;;
  esac
}
