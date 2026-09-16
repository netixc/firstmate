#!/usr/bin/env bash
# Retire Firstmate-owned artifacts from the removed standalone Kimi adapter.
#
# Usage: fm-retired-kimi-cleanup.sh
#
# The command is cleanup-only. It never launches Kimi or installs a hook.
# It removes only the exact marker-delimited Firstmate region from
# $HOME/.kimi-code/config.toml, exact generated hook bytes, and conservative
# orphan registry tokens. Existing configuration bytes outside the owned region
# are preserved exactly. Any symlink, malformed marker, unexpected generated
# file, malformed token, or token whose task record still exists is refused
# before the external configuration is changed.
set -u

if [ "$#" -ne 0 ]; then
  printf 'usage: %s\n' "${0##*/}" >&2
  exit 2
fi
if [ -z "${HOME:-}" ]; then
  printf 'fm-retired-kimi-cleanup: refused: HOME is unset.\n' >&2
  exit 1
fi

config_dir="$HOME/.kimi-code"
if [ -e "$config_dir" ] || [ -L "$config_dir" ]; then
  if [ ! -d "$config_dir" ] || [ -L "$config_dir" ]; then
    printf 'fm-retired-kimi-cleanup: refused: Kimi config root is not a regular directory: %s.\n' "$config_dir" >&2
    exit 1
  fi
else
  exit 0
fi
config="$config_dir/config.toml"
hook="$config_dir/fm-turn-end.sh"
registry="$config_dir/fm-turn-end.d"
owned=0
if [ -f "$config" ] && [ ! -L "$config" ] \
  && LC_ALL=C grep -aq 'FIRSTMATE KIMI TURN-END HOOK' "$config" 2>/dev/null; then
  owned=1
fi
[ ! -e "$hook" ] && [ ! -L "$hook" ] || owned=1
[ ! -e "$registry" ] && [ ! -L "$registry" ] || owned=1
[ "$owned" -eq 1 ] || exit 0

if ! command -v python3 >/dev/null 2>&1; then
  printf 'fm-retired-kimi-cleanup: refused: python3 is required for byte-preserving cleanup.\n' >&2
  exit 1
fi

python3 - "$config_dir" <<'PY'
import os
import re
import stat
import sys
import tempfile

CONFIG_DIR = sys.argv[1]
CONFIG = os.path.join(CONFIG_DIR, "config.toml")
HOOK = os.path.join(CONFIG_DIR, "fm-turn-end.sh")
REGISTRY = os.path.join(CONFIG_DIR, "fm-turn-end.d")
BEGIN = b"# BEGIN FIRSTMATE KIMI TURN-END HOOK"
BEGIN_OWNS_NEWLINE = BEGIN + b" (OWNS PRECEDING NEWLINE)"
END = b"# END FIRSTMATE KIMI TURN-END HOOK"
IDENTIFIER = b"FIRSTMATE KIMI TURN-END HOOK"
HOOK_NAME = b"fm-turn-end.sh"
TOKEN_NAME = re.compile(r"fm\.[A-Za-z0-9]{12}\Z")
TURN_END_SUFFIX = ".turn-ended"

HOOK_BYTES = b'''#!/usr/bin/env bash
# Firstmate Kimi turn-end hook. Managed by fm-kimi-turnend-hook.sh.
# This hook is deliberately passive: every path is silent and exits zero.
set +e
exec >/dev/null 2>&1
payload=
IFS= read -r payload || [ -n "$payload" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
workspace=$(jq -er 'select(.hook_event_name == "Stop") | .cwd | strings | select(length > 0)' <<< "$payload" 2>/dev/null) || exit 0
pointer="$workspace/.fm-kimi-turnend"
[ -f "$pointer" ] || exit 0
first=
IFS= read -r -n 256 first < "$pointer" 2>/dev/null || [ -n "$first" ] || exit 0
case "$first" in token=*) token=${first#token=} ;; *) exit 0 ;; esac
case "$token" in fm.????????????) : ;; *) exit 0 ;; esac
case "$token" in *[!A-Za-z0-9._-]*) exit 0 ;; esac
auth_dir=${HOME:-}/.kimi-code/fm-turn-end.d
[ -n "${HOME:-}" ] || exit 0
target=$(cat "$auth_dir/$token" 2>/dev/null) || exit 0
case "$target" in /*.turn-ended) : ;; *) exit 0 ;; esac
touch -- "$target" 2>/dev/null || true
exit 0
'''


def refuse(reason: str) -> None:
    print(f"fm-retired-kimi-cleanup: refused: {reason}", file=sys.stderr)
    raise SystemExit(1)


def regular_not_symlink(path: str, label: str) -> os.stat_result:
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        refuse(f"{label} is missing at {path}.")
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        refuse(f"{label} is not a regular non-symlink file at {path}.")
    return info


def locate_region(data: bytes):
    normal_count = data.count(BEGIN + b"\n")
    owned_count = data.count(BEGIN_OWNS_NEWLINE + b"\n")
    end_count = data.count(END)
    identifier_count = data.count(IDENTIFIER)
    if normal_count + owned_count == 0 and end_count == 0 and identifier_count == 0:
        return None
    if normal_count + owned_count != 1 or end_count != 1 or identifier_count != 2:
        refuse("config.toml has partial, duplicated, or altered Firstmate region markers.")
    marker = BEGIN_OWNS_NEWLINE if owned_count else BEGIN
    marker_at = data.find(marker)
    if marker_at != 0 and data[marker_at - 1 : marker_at] != b"\n":
        refuse("the Firstmate begin marker is not at a line boundary.")
    start = marker_at
    if owned_count:
        if marker_at == 0 or data[marker_at - 1 : marker_at] != b"\n":
            refuse("the Firstmate region claims a preceding newline that is absent.")
        start -= 1
    end_at = data.find(END, marker_at + len(marker))
    if end_at < 0:
        refuse("the Firstmate end marker is missing.")
    after = end_at + len(END)
    if after < len(data):
        if data[after : after + 1] != b"\n":
            refuse("the Firstmate end marker is not a complete line.")
        after += 1
    return start, after, marker


def without_region(data: bytes, region) -> bytes:
    prefix = data[: region[0]]
    suffix = data[region[1] :]
    separator = b"\n" if region[2] == BEGIN_OWNS_NEWLINE and suffix else b""
    return prefix + separator + suffix


def atomic_write(path: str, data: bytes, mode: int) -> None:
    fd, temporary = tempfile.mkstemp(prefix=f".{os.path.basename(path)}.", dir=os.path.dirname(path))
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as stream:
            fd = -1
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    except Exception:
        if fd >= 0:
            os.close(fd)
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def registry_tokens() -> list[str]:
    if not os.path.lexists(REGISTRY):
        return []
    info = os.lstat(REGISTRY)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        refuse(f"Firstmate registry is not a regular directory at {REGISTRY}.")
    tokens = []
    active = []
    for name in sorted(os.listdir(REGISTRY)):
        path = os.path.join(REGISTRY, name)
        child = os.lstat(path)
        if not TOKEN_NAME.fullmatch(name) or stat.S_ISLNK(child.st_mode) or not stat.S_ISREG(child.st_mode):
            refuse(f"Firstmate registry contains an unexpected entry at {path}.")
        with open(path, "rb") as stream:
            raw = stream.read()
        if raw.endswith(b"\n"):
            raw = raw[:-1]
        if b"\n" in raw or b"\r" in raw or b"\x00" in raw:
            refuse(f"Firstmate registry token has malformed content at {path}.")
        try:
            target = raw.decode("utf-8")
        except UnicodeDecodeError:
            refuse(f"Firstmate registry token is not UTF-8 at {path}.")
        if not target.startswith("/") or not target.endswith(TURN_END_SUFFIX):
            refuse(f"Firstmate registry token has an unexpected target at {path}.")
        meta = target[: -len(TURN_END_SUFFIX)] + ".meta"
        if os.path.lexists(meta):
            active.append(name)
        tokens.append(path)
    if active:
        refuse("registry still contains token(s) whose task records exist: " + ", ".join(active) + ".")
    return tokens


try:
    root_info = os.lstat(CONFIG_DIR)
    if stat.S_ISLNK(root_info.st_mode) or not stat.S_ISDIR(root_info.st_mode):
        refuse(f"Kimi config root is not a regular directory: {CONFIG_DIR}.")

    config_info = None
    original = b""
    region = None
    if os.path.lexists(CONFIG):
        config_info = regular_not_symlink(CONFIG, "Kimi config")
        with open(CONFIG, "rb") as stream:
            original = stream.read()
        region = locate_region(original)
        outside = original if region is None else without_region(original, region)
        if HOOK_NAME in outside:
            refuse("config.toml references fm-turn-end.sh outside the Firstmate-owned region.")
    else:
        outside = original

    if os.path.lexists(HOOK):
        info = regular_not_symlink(HOOK, "Firstmate hook script")
        with open(HOOK, "rb") as stream:
            if stream.read() != HOOK_BYTES:
                refuse(f"Firstmate hook script has unexpected content at {HOOK}.")
        if stat.S_IMODE(info.st_mode) & 0o077:
            refuse(f"Firstmate hook script has unexpectedly broad permissions at {HOOK}.")

    tokens = registry_tokens()
    if config_info is not None and outside != original:
        atomic_write(CONFIG, outside, stat.S_IMODE(config_info.st_mode))
    for token in tokens:
        os.unlink(token)
    if os.path.lexists(HOOK):
        os.unlink(HOOK)
    if os.path.lexists(REGISTRY):
        os.rmdir(REGISTRY)
except OSError as error:
    refuse(f"filesystem operation failed: {error}.")
PY
