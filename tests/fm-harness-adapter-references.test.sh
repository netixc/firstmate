#!/usr/bin/env bash
set -eu
# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SKILL="$ROOT/.agents/skills/harness-adapters/SKILL.md"
assert_grep "Plain Pi is Firstmate's only supported worker and primary harness" "$SKILL" "router declares plain Pi only"
assert_grep 'references/harness/pi.md' "$SKILL" "router selects Pi reference"
for old in claude codex opencode grok kimi cursor muse pi-signed; do
  if grep -q "references/harness/$old.md" "$SKILL"; then fail "$old reference remains routable"; fi
  pass "$old reference is not routable"
done
