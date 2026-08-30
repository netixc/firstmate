#!/usr/bin/env bash
# Ensure the project has an AGENTS.md knowledge file and its maintenance rule.
set -eu
DIR=${1:-.}
[ -d "$DIR" ] && [ ! -L "$DIR" ] || { echo "error: project directory must be a real directory: $DIR" >&2; exit 1; }
DIR=$(cd "$DIR" && pwd -P)
AGENTS="$DIR/AGENTS.md"
SECTION='## Maintaining this file'
BODY='Keep this file for knowledge useful to almost every future agent session in this project.\nDo not repeat what the codebase already shows; point to the authoritative file, command, or doc.\nPrefer rewriting or pruning existing entries over appending new ones.'
if [ -L "$AGENTS" ]; then echo "conflict: AGENTS.md must be a regular file" >&2; exit 1; fi
if [ ! -e "$AGENTS" ]; then
  printf '# Project instructions\n\n%b\n\n%b\n' "$SECTION" "$BODY" > "$AGENTS"
  echo "created: AGENTS.md in $DIR"
  exit 0
fi
[ -f "$AGENTS" ] || { echo "conflict: AGENTS.md is not a regular file" >&2; exit 1; }
if grep -qxF "$SECTION" "$AGENTS"; then echo "unchanged: AGENTS.md in $DIR"; exit 0; fi
printf '\n%s\n\n%b\n' "$SECTION" "$BODY" >> "$AGENTS"
echo "updated: added $SECTION to AGENTS.md in $DIR"
