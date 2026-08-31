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
        options = re.findall(r"(?<![\w-])(--?[A-Za-z0-9-]+)(=\.\.\.)?(?=[,\s]|$)", declaration)
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

fm_harness_pi_launch_record_publish() {  # <state-dir> <pid> <extension> <canonical-cli> [start]
  local state_dir=$1 pid=$2 extension=$3 cli=$4 start=${5:-} version digest launch_id launch_dir image launch image_tmp launch_tmp owner_start
  [ -f "$extension" ] && [ ! -L "$extension" ] || return 1
  fm_harness_pi_cli_canonical "$cli" || return 1
  if [ -z "$start" ]; then
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      start=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [ -z "$start" ] || break
      sleep 0.05
    done
  fi
  [ -n "$start" ] || return 1
  version="sha256:$(fm_harness_file_sha256 "$extension")" || return 1
  digest=${version#sha256:}
  launch_id=$(printf '%s' "$start" | fm_harness_file_sha256 /dev/stdin) || return 1
  launch_dir="$state_dir/.pi-launches"
  image="$launch_dir/images/$digest.ts"
  launch="$launch_dir/$pid-$launch_id"
  mkdir -p "$launch_dir/images" || return 1
  if [ ! -f "$image" ]; then
    image_tmp="$image.parent.$$"
    if ! cp "$extension" "$image_tmp" || ! chmod 444 "$image_tmp" || ! mv -f "$image_tmp" "$image"; then
      rm -f "$image_tmp"
      return 1
    fi
  fi
  [ ! -L "$image" ] && [ "$(fm_harness_file_sha256 "$image")" = "$digest" ] || return 1
  owner_start=$(ps -o lstart= -p "$$" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$owner_start" ] || return 1
  launch_tmp="$launch.parent.$$"
  printf '%s\n%s\n%s\n%s\n%s\n%s\nparent-v1\n%s\n%s\n' "$version" "$pid" "$start" "$image" "$cli" "$extension" "$$" "$owner_start" > "$launch_tmp" || return 1
  chmod 444 "$launch_tmp" || { rm -f "$launch_tmp"; return 1; }
  rm -f "$launch"
  mv "$launch_tmp" "$launch"
}

fm_harness_pi_launch_record_migrate() {  # <state-dir> <pid> <version> <start> <extension> <cli>
  local state_dir=$1 pid=$2 version=$3 start=$4 extension=$5 cli=$6 root rel commit candidate launch
  root=$(git -C "$(dirname "$extension")" rev-parse --show-toplevel 2>/dev/null || true)
  if [ -f "$extension" ] && [ "sha256:$(fm_harness_file_sha256 "$extension")" = "$version" ]; then
    fm_harness_pi_launch_record_publish "$state_dir" "$pid" "$extension" "$cli" "$start" || return 1
    launch="$state_dir/.pi-launches/$pid-$(printf '%s' "$start" | fm_harness_file_sha256 /dev/stdin)"
    sed '7s/parent-v1/migration-v1/;8,9d' "$launch" > "$launch.migration" && mv "$launch.migration" "$launch" || { rm -f "$launch.migration"; return 1; }
    return
  fi
  [ -n "$root" ] || return 1
  rel=${extension#"$root"/}
  candidate="$state_dir/.pi-launches/.migration-image.$$"
  mkdir -p "$(dirname "$candidate")" || return 1
  for commit in $(git -C "$root" log --all --format=%H -- "$rel" 2>/dev/null); do
    git -C "$root" show "$commit:$rel" > "$candidate" 2>/dev/null || continue
    if [ "sha256:$(fm_harness_file_sha256 "$candidate")" = "$version" ]; then
      fm_harness_pi_launch_record_publish "$state_dir" "$pid" "$candidate" "$cli" "$start" || { rm -f "$candidate"; return 1; }
      launch="$state_dir/.pi-launches/$pid-$(printf '%s' "$start" | fm_harness_file_sha256 /dev/stdin)"
      sed '7s/parent-v1/migration-v1/;8,9d' "$launch" > "$launch.migration" && mv "$launch.migration" "$launch" || { rm -f "$candidate" "$launch.migration"; return 1; }
      rm -f "$candidate"
      return 0
    fi
  done
  rm -f "$candidate"
  return 1
}

fm_harness_pid_pi_registration() {
  local pid=$1 root state_dir expected_extension marker marker_version marker_pid marker_start marker_extension marker_cli marker_launch current_start launch_id launch_version launch_pid launch_start launch_image launch_cli launch_extension launch_owner launch_parent launch_parent_start current_parent current_parent_start parent_args
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
  marker_launch=$(sed -n '6p' "$marker" 2>/dev/null)
  [ "$marker_pid" = "$pid" ] && [ -n "$marker_start" ] || return 1
  [ "$marker_extension" = "$expected_extension" ] || return 1
  fm_harness_pi_cli_canonical "$marker_cli" || return 1
  current_start=$(ps -o lstart= -p "$pid" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ "$current_start" = "$marker_start" ] || return 1
  launch_id=$(printf '%s' "$marker_start" | fm_harness_file_sha256 /dev/stdin) || return 1
  marker_launch="$state_dir/.pi-launches/$pid-$launch_id"
  if [ ! -f "$marker_launch" ] || ! grep -Eq '^(parent|migration)-v1$' < <(sed -n '7p' "$marker_launch" 2>/dev/null); then
    fm_harness_pi_launch_record_migrate "$state_dir" "$pid" "$marker_version" "$marker_start" "$marker_extension" "$marker_cli" || return 1
  fi
  [ -f "$marker_launch" ] && [ ! -L "$marker_launch" ] || return 1
  launch_version=$(sed -n '1p' "$marker_launch" 2>/dev/null)
  launch_pid=$(sed -n '2p' "$marker_launch" 2>/dev/null)
  launch_start=$(sed -n '3p' "$marker_launch" 2>/dev/null)
  launch_image=$(sed -n '4p' "$marker_launch" 2>/dev/null)
  launch_cli=$(sed -n '5p' "$marker_launch" 2>/dev/null)
  launch_extension=$(sed -n '6p' "$marker_launch" 2>/dev/null)
  launch_owner=$(sed -n '7p' "$marker_launch" 2>/dev/null)
  launch_parent=$(sed -n '8p' "$marker_launch" 2>/dev/null)
  launch_parent_start=$(sed -n '9p' "$marker_launch" 2>/dev/null)
  case "$launch_owner" in
    parent-v1)
      current_parent=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d '[:space:]')
      [ "$current_parent" = "$launch_parent" ] || return 1
      current_parent_start=$(ps -o lstart= -p "$launch_parent" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [ "$current_parent_start" = "$launch_parent_start" ] || return 1
      parent_args=$(ps -o args= -p "$launch_parent" 2>/dev/null)
      case "$parent_args" in *[/]fm-pi-launch.sh*) ;; *) return 1 ;; esac
      ;;
    migration-v1) ;;
    *) return 1 ;;
  esac
  [ "$launch_version" = "$marker_version" ] && [ "$launch_pid" = "$marker_pid" ] && [ "$launch_start" = "$marker_start" ] || return 1
  [ "$launch_cli" = "$marker_cli" ] || return 1
  case "$launch_extension" in "$expected_extension"|"$state_dir/.pi-launches/.migration-image."*) ;; *) return 1 ;; esac
  [ "$launch_image" = "$state_dir/.pi-launches/images/${launch_version#sha256:}.ts" ] || return 1
  [ -f "$launch_image" ] && [ ! -L "$launch_image" ] || return 1
  [ "sha256:$(fm_harness_file_sha256 "$launch_image")" = "$launch_version" ] || return 1
  fm_harness_pi_cli_canonical "$launch_cli" || return 1
  [ "$current_start" = "$launch_start" ]
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
