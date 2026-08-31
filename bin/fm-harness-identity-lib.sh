#!/usr/bin/env bash

fm_harness_excluded_name() {
  case "${1:-}" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse) printf '%s\n' "$1"; return 0 ;;
    cursor-agent) printf 'cursor\n'; return 0 ;;
    muse-bin-*) printf 'muse\n'; return 0 ;;
  esac
  return 1
}

fm_harness_excluded_install_path() {
  local path=${1:-}
  case "$path" in
    */bin/pi-signed) printf 'pi-signed\n'; return 0 ;;
    */bin/claude|*/claude/versions/*) printf 'claude\n'; return 0 ;;
    */bin/codex|*/@openai/codex/bin/codex.js) printf 'codex\n'; return 0 ;;
    */bin/opencode|*/opencode/bin/opencode.js) printf 'opencode\n'; return 0 ;;
    */bin/grok) printf 'grok\n'; return 0 ;;
    */bin/kimi) printf 'kimi\n'; return 0 ;;
    */bin/cursor|*/bin/cursor-agent) printf 'cursor\n'; return 0 ;;
    */bin/muse|*/bin/muse-bin-*) printf 'muse\n'; return 0 ;;
  esac
  return 1
}

fm_harness_excluded_entrypoint() {
  local path=${1:-} identity
  [ -n "$path" ] || return 1
  identity=$(fm_harness_excluded_name "$(basename -- "$path")" || true)
  [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  fm_harness_excluded_install_path "$path"
}

fm_harness_interpreter() {
  case "$(basename -- "${1:-}")" in
    bash|sh|zsh|dash|node|nodejs|python|python[0-9]*|ruby|perl|bun|deno) return 0 ;;
    *) return 1 ;;
  esac
}

fm_harness_command_entrypoint() {
  local comm=$1 args=${2:-} pid=${3:-} executable=${4:-}
  fm_harness_interpreter "$comm" || return 1
  python3 - "$comm" "$args" "$pid" "$executable" <<'PY'
import re
import shlex
import subprocess
import sys
from pathlib import Path

name = Path(sys.argv[1]).name
ambiguous = "unverified-interpreter"
if sys.argv[3] and Path(f"/proc/{sys.argv[3]}/cmdline").is_file():
    try:
        words = Path(f"/proc/{sys.argv[3]}/cmdline").read_bytes().split(b"\0")
    except OSError:
        print(ambiguous)
        raise SystemExit(0)
    words = [word.decode(errors="surrogateescape") for word in words if word]
else:
    try:
        words = shlex.split(sys.argv[2])
    except ValueError:
        print(ambiguous)
        raise SystemExit(0)

args = words[1:]
takes_value = {
    "node": set(), "nodejs": set(),
    "bash": {"-c", "-O", "+O", "-o", "+o", "--init-file", "--rcfile"},
    "sh": {"-c", "-o", "+o"}, "zsh": {"-c", "-o", "+o"}, "dash": {"-c", "-o", "+o"},
    "python": {"-c", "-m", "-W", "-X", "--check-hash-based-pycs"},
    "ruby": {"-e", "-C", "-E", "-F", "-I", "-K", "-r", "-T", "-W", "--disable", "--dump", "--enable", "--encoding", "--external-encoding", "--internal-encoding"},
    "perl": {"-e", "-E", "-F", "-I", "-M", "-m"},
    "bun": {"-e", "--eval", "-p", "--print", "--cwd", "--config"},
    "deno": {"-e", "--eval", "--config", "--import-map", "--location"},
}
if name.startswith("python"):
    name = "python"
known_options = {key: set(value) for key, value in takes_value.items()}
if name in {"node", "nodejs"}:
    node = sys.argv[4] or name
    try:
        help_text = subprocess.run([node, "--help"], check=True, capture_output=True, text=True).stdout
    except (OSError, subprocess.SubprocessError):
        help_text = ""
    for line in help_text.splitlines():
        declaration = line.strip().split("  ", 1)[0]
        options = re.findall(r"(?<![\w-])(--?[A-Za-z0-9-]+)(=\.\.\.)?", declaration)
        known_options[name].update(option for option, _ in options)
        if any(value for _, value in options):
            takes_value[name].update(option for option, _ in options)
no_script = {
    "node": {"-e", "--eval", "-p", "--print"}, "nodejs": {"-e", "--eval", "-p", "--print"},
    "bash": {"-c"}, "sh": {"-c"}, "zsh": {"-c"}, "dash": {"-c"},
    "python": {"-c", "-m"}, "ruby": {"-e"}, "perl": {"-e", "-E", "-V"}, "bun": {"-e", "--eval", "-p", "--print"},
    "deno": {"-e", "--eval"},
}
attached_value = {
    "bash": {"-O", "+O", "-o", "+o"}, "sh": {"-o", "+o"}, "zsh": {"-o", "+o"}, "dash": {"-o", "+o"},
    "python": {"-W", "-X"}, "ruby": {"-C", "-E", "-F", "-I", "-K", "-r", "-T", "-W", "-x"},
    "perl": {"-F", "-I", "-M", "-m", "-V", "-x"},
}
subcommands = {"bun": {"run"}, "deno": {"run"}}
skip = False
options_ended = False
for word in args:
    if skip:
        skip = False
        continue
    if word == "--" and not options_ended:
        options_ended = True
        continue
    option = word.split("=", 1)[0]
    if not options_ended and option in no_script.get(name, set()):
        break
    if not options_ended and option in takes_value.get(name, set()):
        skip = "=" not in word
        continue
    if not options_ended and any(word.startswith(prefix) and word != prefix for prefix in attached_value.get(name, set())):
        continue
    if not options_ended and word.startswith(("-", "+")):
        if option in known_options.get(name, set()):
            continue
        print(ambiguous)
        break
    if not options_ended and word in subcommands.get(name, set()):
        continue
    print(word)
    break
else:
    if skip:
        print(ambiguous)
PY
}

fm_harness_process_identity() {
  local comm=$1 args=${2:-} executable=${3:-} argv0 identity entrypoint parser
  argv0=${args%% *}
  for entrypoint in "$comm" "$argv0" "$executable"; do
    identity=$(fm_harness_excluded_entrypoint "$entrypoint" || true)
    [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  done
  parser=$comm
  case "$(basename -- "$executable")" in node|nodejs) parser=$executable ;; esac
  entrypoint=$(fm_harness_command_entrypoint "$parser" "$args" "" "$executable" || true)
  if [ "$entrypoint" = unverified-interpreter ]; then
    printf 'unverified-interpreter\n'
    return 0
  fi
  if fm_harness_interpreter "$parser" && [ "$(basename -- "$comm")" != pi ] && [ "$(basename -- "$parser")" != "$(basename -- "$comm")" ] && [ -z "$entrypoint" ]; then
    printf 'unverified-node\n'
    return 0
  fi
  identity=$(fm_harness_excluded_entrypoint "$entrypoint" || true)
  [ -z "$identity" ] || { printf '%s\n' "$identity"; return 0; }
  return 1
}

fm_harness_pid_excluded_argv() {
  local pid=$1 comm=$2 fallback=${3:-} executable=${4:-} parser entrypoint identity
  parser=$comm
  case "$(basename -- "$executable")" in node|nodejs) parser=$executable ;; esac
  entrypoint=$(fm_harness_command_entrypoint "$parser" "$fallback" "$pid" "$executable" || true)
  if [ "$entrypoint" = unverified-interpreter ]; then
    printf 'unverified-interpreter\n'
    return 0
  fi
  if [ "$(basename -- "$executable")" = node ] || [ "$(basename -- "$executable")" = nodejs ]; then
    if [ "$(basename -- "$comm")" != pi ] && [ -z "$entrypoint" ]; then
      printf 'unverified-node\n'
      return 0
    fi
  fi
  identity=$(fm_harness_excluded_entrypoint "$entrypoint" || true)
  [ -z "$identity" ] || printf '%s\n' "$identity"
  [ -n "$identity" ]
}

fm_harness_file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" 2>/dev/null | awk '{print $1}'
  else
    return 1
  fi
}

fm_harness_pi_cli_canonical() {
  local cli digest version
  cli=$(python3 - "$1" <<'PY'
import sys
from pathlib import Path
try:
    print(Path(sys.argv[1]).resolve(strict=True))
except OSError:
    raise SystemExit(1)
PY
) || return 1
  [ -f "$cli" ] && [ ! -L "$cli" ] || return 1
  digest=$(python3 - "$cli" <<'PY'
import hashlib
import sys
from pathlib import Path
root = Path(sys.argv[1]).parent
value = hashlib.sha256()
try:
    files = sorted(path for path in root.rglob("*") if path.is_file())
    for path in files:
        value.update(path.relative_to(root).as_posix().encode())
        value.update(b"\0")
        value.update(path.read_bytes())
        value.update(b"\0")
except OSError:
    raise SystemExit(1)
print(value.hexdigest())
PY
) || return 1
  [ "$digest" = 1dfa94d6d88b01237cb5bcd6fbaed13289108ebb76e580806833be228372fd08 ] || return 1
  version=$("$cli" --version 2>/dev/null || true)
  [ "$version" = 0.84.4 ]
}

fm_harness_pid_pi_registration() {
  local pid=$1 root state_dir expected_extension marker marker_version marker_pid marker_start marker_extension marker_cli current_start actual_version
  root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  if [ -n "${FM_HARNESS_IDENTITY_HOME:-}" ]; then
    state_dir="$FM_HARNESS_IDENTITY_HOME/state"
    expected_extension="$FM_HARNESS_IDENTITY_HOME/.pi/extensions/fm-pi-process-registration.ts"
  else
    state_dir=${FM_STATE_OVERRIDE:-${FM_HOME:-${FM_ROOT_OVERRIDE:-$root}}/state}
    expected_extension="$root/.pi/extensions/fm-pi-process-registration.ts"
  fi
  marker="$state_dir/.pi-processes/$pid"
  [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
  marker_version=$(sed -n '1p' "$marker" 2>/dev/null)
  marker_pid=$(sed -n '2p' "$marker" 2>/dev/null)
  marker_start=$(sed -n '3p' "$marker" 2>/dev/null)
  marker_extension=$(sed -n '4p' "$marker" 2>/dev/null)
  marker_cli=$(sed -n '5p' "$marker" 2>/dev/null)
  [ "$marker_pid" = "$pid" ] && [ -n "$marker_start" ] || return 1
  [ "$marker_extension" = "$expected_extension" ] || return 1
  fm_harness_pi_cli_canonical "$marker_cli" || return 1
  [ -f "$marker_extension" ] && [ ! -L "$marker_extension" ] || return 1
  actual_version="sha256:$(fm_harness_file_sha256 "$root/.pi/extensions/fm-pi-process-registration.ts")" || return 1
  [ "$marker_version" = "$actual_version" ] || return 1
  [ "$(fm_harness_file_sha256 "$marker_extension")" = "${actual_version#sha256:}" ] || return 1
  current_start=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ "$current_start" = "$marker_start" ]
}

fm_harness_pid_executable() {
  local pid=$1 path
  if [ -e "/proc/$pid/exe" ]; then
    readlink "/proc/$pid/exe" 2>/dev/null
    return
  fi
  path=$(lsof -a -p "$pid" -d txt -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

fm_harness_pid_identity() {
  local pid=$1 comm=$2 args=${3:-} identity executable
  executable=$(fm_harness_pid_executable "$pid" || true)
  identity=$(fm_harness_pid_excluded_argv "$pid" "$comm" "$args" "$executable" || true)
  if fm_harness_identity_excluded "$identity"; then
    printf '%s\n' "$identity"
    return 0
  fi
  identity=$(fm_harness_process_identity "$comm" "$args" "$executable" || true)
  if fm_harness_identity_excluded "$identity"; then
    printf '%s\n' "$identity"
    return 0
  fi
  [ "$(basename -- "$comm")" = pi ] || return 1
  fm_harness_pid_pi_registration "$pid" || return 1
  case "$(basename -- "$executable")" in
    node|nodejs) printf 'pi\n' ;;
    *) return 1 ;;
  esac
}

fm_harness_identity_excluded() {
  case "$1" in
    pi-signed|claude|codex|opencode|grok|kimi|cursor|muse|unverified-node|unverified-interpreter) return 0 ;;
    *) return 1 ;;
  esac
}
