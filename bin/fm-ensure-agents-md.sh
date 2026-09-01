#!/usr/bin/env bash
# Ensure a project worktree has the canonical AGENTS.md knowledge file and
# maintenance section. Canonical CLAUDE.md pointers are preserved; legacy or
# divergent memory and invalid pointers are refused before AGENTS.md mutation.
# Usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]
set -eu

usage() {
  echo "usage: fm-ensure-agents-md.sh [repo-or-worktree-dir]" >&2
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac
[ "$#" -le 1 ] || { usage; exit 1; }

DIR=${1:-.}
[ -d "$DIR" ] && [ ! -L "$DIR" ] || {
  echo "error: project directory must be a real directory: $DIR" >&2
  exit 1
}
DIR=$(cd "$DIR" && pwd -P)
cd "$DIR"
AGENTS=AGENTS.md
CLAUDE=CLAUDE.md

claude_pointer_content() {
  cat <<'EOF'
<!-- Points Claude at AGENTS.md via import; edit AGENTS.md, not this file. -->
@AGENTS.md
EOF
}

is_canonical_claude_pointer() {
  [ -f "$CLAUDE" ] && [ ! -L "$CLAUDE" ] || return 1
  claude_pointer_content | cmp -s - "$CLAUDE"
}

is_correct_claude_symlink() {
  [ -L "$CLAUDE" ] || return 1
  local target
  target=$(readlink "$CLAUDE")
  case "$target" in
    "$AGENTS"|"./$AGENTS") return 0 ;;
  esac
  [ -e "$AGENTS" ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$CLAUDE" "$AGENTS" <<'PY'
import os
import sys
sys.exit(0 if os.path.realpath(sys.argv[1]) == os.path.realpath(sys.argv[2]) else 1)
PY
}

write_maintenance_section() {
  cat <<'EOF'
## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
EOF
}

write_maintenance_section_with_eol() {
  local eol=$1 line
  while IFS= read -r line; do
    printf '%s%s' "$line" "$eol"
  done < <(write_maintenance_section)
}

MAINT_INJECTED=0
ensure_maintenance_section() {
  MAINT_INJECTED=0
  if grep -Fqx '## Maintaining this file' "$AGENTS" ||
    grep -Fqx $'## Maintaining this file\r' "$AGENTS"; then
    return 0
  fi
  local eol=$'\n' sep=''
  if LC_ALL=C grep -q $'\r$' "$AGENTS"; then
    eol=$'\r\n'
  fi
  if [ -s "$AGENTS" ]; then
    if [ -n "$(tail -c 1 "$AGENTS")" ]; then
      sep="${eol}${eol}"
    else
      sep=$eol
    fi
  fi
  {
    printf '%s' "$sep"
    write_maintenance_section_with_eol "$eol"
  } >> "$AGENTS"
  MAINT_INJECTED=1
}

write_skeleton() {
  cat > "$AGENTS" <<'EOF'
# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Add durable project-specific notes here as they are discovered through real work.
EOF
  ensure_maintenance_section
}

for entry in *; do
  if [ ! -e "$entry" ] && [ ! -L "$entry" ]; then
    continue
  fi
  if [ "$entry" != "$AGENTS" ]; then
    case "$entry" in
      [Aa][Gg][Ee][Nn][Tt][Ss].[Mm][Dd])
        echo "conflict: memory file is named $entry in $DIR but the convention is AGENTS.md; rename it to AGENTS.md for portable resolution" >&2
        exit 1
        ;;
    esac
  fi
done

if [ -L "$AGENTS" ]; then
  echo "conflict: AGENTS.md is a symlink in $DIR; expected AGENTS.md to be the real file" >&2
  exit 1
fi
if [ -e "$AGENTS" ] && [ ! -f "$AGENTS" ]; then
  echo "conflict: AGENTS.md exists in $DIR but is not a regular file" >&2
  exit 1
fi

if [ -L "$CLAUDE" ]; then
  if ! is_correct_claude_symlink; then
    echo "conflict: CLAUDE.md is a symlink in $DIR but does not point to AGENTS.md; curate the pointer manually before rerunning" >&2
    exit 1
  fi
elif [ -e "$CLAUDE" ]; then
  if [ ! -f "$CLAUDE" ]; then
    echo "conflict: CLAUDE.md exists in $DIR but is not a regular file or symlink; curate it manually before rerunning" >&2
    exit 1
  fi
  if ! is_canonical_claude_pointer; then
    echo "conflict: CLAUDE.md contains legacy project memory in $DIR; curate AGENTS.md and CLAUDE.md manually before rerunning" >&2
    exit 1
  fi
fi

if [ -f "$AGENTS" ]; then
  ensure_maintenance_section
  if [ "$MAINT_INJECTED" -eq 1 ]; then
    echo "updated: added ## Maintaining this file to AGENTS.md in $DIR"
  else
    echo "unchanged: AGENTS.md in $DIR"
  fi
  exit 0
fi

write_skeleton
echo "created: AGENTS.md in $DIR"
