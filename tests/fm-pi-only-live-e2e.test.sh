#!/usr/bin/env bash
# Credentialed real-model proof that plain Pi exposes Firstmate's exact identity.
set -eu
if [ "${FM_PI_ONLY_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_PI_ONLY_LIVE_E2E=1 to run the real plain Pi integration"
  exit 0
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v pi >/dev/null 2>&1 || { echo "not ok - pi unavailable" >&2; exit 1; }
out=$(cd "$ROOT" && pi --print --approve --no-session --no-context-files --no-extensions \
  --model openai-codex/gpt-5.6-sol --thinking low \
  "Use the bash tool to run PI_CODING_AGENT=true bin/fm-harness.sh. Reply with exactly the command's one-word stdout and nothing else.")
[ "$out" = pi ] || { printf 'not ok - real Pi returned %q\n' "$out" >&2; exit 1; }
printf 'ok - real Pi model and child-process identity resolve exact plain pi (Pi %s)\n' "$(pi --version)"
