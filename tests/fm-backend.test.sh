#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/config" "$TMP/home/state"
FM_HOME="$TMP/home"
FM_CONFIG_OVERRIDE="$TMP/home/config"
# shellcheck source=bin/fm-backend.sh
. "$ROOT/bin/fm-backend.sh"

fail() { echo "not ok - $1" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "$3 (got '$1', want '$2')"; }

assert_eq "$(fm_backend_name)" herdr "the product default must be Herdr"
assert_eq "$FM_BACKEND_KNOWN" herdr "known provider set must contain only Herdr"
assert_eq "$(fm_backend_required_tools herdr)" "herdr jq treehouse" "Herdr toolchain must retain Treehouse and JSON parsing"

FM_BACKEND=tmux
if fm_backend_name >"$TMP/out" 2>"$TMP/err"; then fail "an excluded provider must be refused"; fi
grep -q "requires backend=herdr" "$TMP/err" || fail "excluded provider refusal must name the migration"
unset FM_BACKEND
printf 'zellij\n' > "$TMP/home/config/backend"
if fm_backend_name >"$TMP/out" 2>"$TMP/err"; then fail "an excluded configured provider must be refused"; fi
grep -q "never falls back" "$TMP/err" || fail "configured-provider refusal must state no fallback"
printf 'herdr\n' > "$TMP/home/config/backend"
assert_eq "$(fm_backend_name)" herdr "explicit Herdr config must pass"

cat > "$TMP/home/state/old.meta" <<EOF
window=legacy:0
worktree=$TMP/work
project=$TMP/project
EOF
assert_eq "$(fm_backend_of_meta "$TMP/home/state/old.meta")" legacy-unrecorded "absent provider metadata must not be reinterpreted"
if fm_backend_validate_task_endpoint "$TMP/home/state/old.meta" old 2>"$TMP/err"; then fail "old absent provider metadata must block cleanup"; fi
grep -q "explicit migration to Herdr metadata is required" "$TMP/err" || fail "legacy blocker must be concrete"

cat > "$TMP/home/state/task.meta" <<EOF
window=lab:w1:p2
endpoint_task_id=task
worktree=$TMP/work
project=$TMP/project
backend=herdr
herdr_session=lab
herdr_workspace_id=w1
herdr_tab_id=w1:t1
herdr_pane_id=w1:p2
EOF
fm_backend_validate_task_endpoint "$TMP/home/state/task.meta" task || fail "exact Herdr metadata should validate"
assert_eq "$FM_BACKEND_VALIDATED_BACKEND" herdr "validated provider"
assert_eq "$FM_BACKEND_VALIDATED_TARGET" lab:w1:p2 "validated target"
assert_eq "$(fm_backend_resolve_selector task "$TMP/home/state")" lab:w1:p2 "task selectors must resolve through metadata"
if fm_backend_resolve_selector 'legacy:0' "$TMP/home/state" 2>"$TMP/err"; then fail "ad hoc legacy endpoints must be refused"; fi
grep -Eq "unsupported in the Herdr-only edition|explicit migration|unsupported session provider" "$TMP/err" || fail "ad hoc refusal must explain the boundary"

echo "ok - Herdr-only provider selection and metadata migration"
