#!/usr/bin/env bash
# Shared AFK injection entrypoint. The canonical retained behavior now runs
# only through the isolated named-session Herdr fixture.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec "$ROOT/tests/fm-afk-inject-herdr-e2e.test.sh" "$@"
