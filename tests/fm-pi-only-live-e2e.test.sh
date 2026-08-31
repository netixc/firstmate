#!/usr/bin/env bash
# Credentialed real-model proof that plain Pi exposes Firstmate's exact identity.
set -eu
if [ "${FM_PI_ONLY_LIVE_E2E:-0}" != 1 ]; then
  echo "skip: set FM_PI_ONLY_LIVE_E2E=1 to run the real plain Pi integration"
  exit 0
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v pi >/dev/null 2>&1 || { echo "not ok - pi unavailable" >&2; exit 1; }
PI_VERSION=$(pi --version 2>/dev/null || true)
[ "$PI_VERSION" = 0.84.4 ] || { printf 'not ok - real Pi 0.84.4 required, found %s\n' "${PI_VERSION:-unknown}" >&2; exit 1; }
TMP=$(mktemp -d "${TMPDIR:-/tmp}/fm-pi-only-live.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"
out=$(cd "$ROOT" && FM_HOME="$TMP" pi --print --approve --no-session --no-context-files --no-extensions \
  -e "$ROOT/.pi/extensions/fm-primary-pi-watch.ts" \
  -e "$ROOT/.pi/extensions/fm-primary-turnend-guard.ts" \
  --model openai-codex/gpt-5.6-sol --thinking low \
  "Use the bash tool to run: bash -c '. bin/fm-session-lock-lib.sh; fm_harness_ancestry_pid >/dev/null && echo pi'. Reply with exactly the command's one-word stdout and nothing else.")
[ "$out" = pi ] || { printf 'not ok - real Pi returned %q\n' "$out" >&2; exit 1; }
printf 'ok - real Pi extensions register lifecycle identity (Pi %s)\n' "$PI_VERSION"
