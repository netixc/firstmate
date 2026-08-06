#!/usr/bin/env bash
# tests/secondmate-helpers.sh - shared fixtures and mocks for the secondmate
# suites (fm-secondmate-lifecycle-e2e and fm-secondmate-safety).
#
# These mocks encode secondmate-lifecycle behavior with a hermetic Herdr CLI,
# a fake Treehouse that leases and returns homes, and a fake no-mistakes client.
# They live here rather than in the generic tests/lib.sh because the fixtures own lifecycle semantics.

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# A fake Herdr CLI plus a fake Treehouse with durable lease behavior.
# Runtime calls are logged to FM_FAKE_HERDR_LOG and pane capture comes from FM_FAKE_HERDR_CAPTURE.
# Treehouse records its lease holder in FM_FAKE_TREEHOUSE_LEASE_FILE and removes the target on return unless failure is requested.
make_fake_herdr() {
  local dir=$1 fakebin capture
  fakebin=$(fm_fakebin "$dir")
  capture="$dir/pane.txt"
  printf '╭────╮\n│ >  │\n╰────╯\n' > "$capture"
  cat > "$fakebin/herdr" <<'SH'
#!/usr/bin/env bash
set -u
log=${FM_FAKE_HERDR_LOG:-/dev/null}
capture=${FM_FAKE_HERDR_CAPTURE:-/dev/null}
printf '%s\n' "$*" >> "$log"
write_composer() {
  printf '╭────────╮\n│ > %s │\n╰────────╯\n' "$1" > "$capture"
}
case "${1:-} ${2:-}" in
  'status --json')
    printf '{"client":{"version":"0.7.5","protocol":16},"server":{"running":true}}\n'
    ;;
  'session list')
    printf '{"sessions":[{"name":"default","running":true,"socket_path":"/tmp/fm-secondmate-helper.sock"},{"name":"firstmate","running":true,"socket_path":"/tmp/fm-secondmate-helper-firstmate.sock"}]}\n'
    ;;
  'workspace list')
    printf '{"result":{"workspaces":[{"workspace_id":"w1","label":"firstmate"}]}}\n'
    ;;
  'workspace create')
    printf '{"result":{"workspace":{"workspace_id":"w2"},"tab":{"tab_id":"w2:t0"},"root_pane":{"pane_id":"w2:p0"}}}\n'
    ;;
  'tab list')
    printf '{"result":{"tabs":[]}}\n'
    ;;
  'tab create')
    workspace=w1
    previous=
    for argument in "$@"; do
      [ "$previous" != --workspace ] || workspace=$argument
      previous=$argument
    done
    printf '{"result":{"tab":{"tab_id":"%s:t1"},"root_pane":{"pane_id":"%s:p1"}}}\n' "$workspace" "$workspace"
    ;;
  'pane list')
    printf '{"result":{"panes":[]}}\n'
    ;;
  'pane get')
    [ "${FM_FAKE_HERDR_PANE_ALIVE:-1}" = 1 ] || { printf '{"error":{"code":"pane_not_found"}}\n'; exit 1; }
    pane=${3:-w1:p1}
    [ ! -f "$capture.closed.$pane" ] || { printf '{"error":{"code":"pane_not_found"}}\n'; exit 1; }
    workspace=${pane%%:*}
    printf '{"result":{"pane":{"pane_id":"%s","tab_id":"%s:t1","workspace_id":"%s","foreground_cwd":"%s"}}}\n' \
      "$pane" "$workspace" "$workspace" "${FM_FAKE_HERDR_PANE_PATH:-$PWD}"
    ;;
  'pane read')
    cat "$capture" 2>/dev/null
    ;;
  'pane run')
    printf 'run %s\n' "${4:-}" >> "$log"
    ;;
  'pane send-text')
    [ "${FM_FAKE_HERDR_FAIL_LITERAL:-0}" != 1 ] || exit 1
    write_composer "${4:-}"
    ;;
  'pane send-keys')
    case "${4:-}" in enter) write_composer '' ;; esac
    ;;
  'pane close')
    : > "$capture.closed.${3:-w1:p1}"
    ;;
  'agent get')
    case "${FM_FAKE_HERDR_AGENT_STATE:-alive}" in
      missing) exit 1 ;;
      dead) printf '{"error":{"code":"agent_not_found"}}\n' ;;
      unreadable) printf 'not-json\n' ;;
      *) printf '{"result":{"agent":{"agent_status":"working"}}}\n' ;;
    esac
    ;;
  *) exit 0 ;;
esac
SH
  cat > "$fakebin/treehouse" <<'SH'
#!/usr/bin/env bash
set -u
printf 'treehouse %s\n' "$*" >> "${FM_FAKE_HERDR_LOG:-/dev/null}"
case "${1:-}" in
  get)
    # Durable lease: print only the worktree path to stdout (banners to stderr),
    # and record the lease holder so tests can assert it is set and later cleared.
    shift
    holder=
    while [ $# -gt 0 ]; do
      case "$1" in
        --lease) ;;
        --lease-holder) shift; holder=${1:-} ;;
        --lease-holder=*) holder=${1#--lease-holder=} ;;
      esac
      shift
    done
    if [ -n "${FM_FAKE_TREEHOUSE_HOME:-}" ]; then
      mkdir -p "$FM_FAKE_TREEHOUSE_HOME"
      [ -n "${FM_FAKE_TREEHOUSE_LEASE_FILE:-}" ] && printf '%s\n' "$holder" > "$FM_FAKE_TREEHOUSE_LEASE_FILE"
      printf 'leased worktree for %s\n' "${holder:-unknown}" >&2
      printf '%s\n' "$FM_FAKE_TREEHOUSE_HOME"
    fi
    exit 0
    ;;
  return)
    shift
    target=
    while [ $# -gt 0 ]; do
      case "$1" in
        --force) ;;
        *) target=$1 ;;
      esac
      shift
    done
    [ -z "${FM_FAKE_TREEHOUSE_RETURN_FAIL:-}" ] || exit 17
    [ -n "${FM_FAKE_TREEHOUSE_LEASE_FILE:-}" ] && rm -f "$FM_FAKE_TREEHOUSE_LEASE_FILE"
    [ -n "$target" ] && rm -rf -- "$target"
    exit 0
    ;;
esac
exit 0
SH
  chmod +x "$fakebin/herdr"
  chmod +x "$fakebin/treehouse"
  : > "$dir/herdr.log"
  printf '%s\n' "$fakebin"
}

# A fake no-mistakes that touches .no-mistakes-init / .no-mistakes-doctor markers.
make_fake_no_mistakes() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -eu
case "${1:-}" in
  init) touch .no-mistakes-init ;;
  doctor) touch .no-mistakes-doctor ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fakebin/no-mistakes"
  printf '%s\n' "$fakebin"
}

# A fake no-mistakes that records each "<pwd>\t<verb>" call to
# FM_FAKE_NO_MISTAKES_LOG and fails for the project named FM_FAKE_NO_MISTAKES_FAIL_PROJECT.
make_recording_no_mistakes() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/no-mistakes" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\t%s\n' "$PWD" "${1:-}" >> "$FM_FAKE_NO_MISTAKES_LOG"
if [ "$(basename "$PWD")" = "${FM_FAKE_NO_MISTAKES_FAIL_PROJECT:-}" ]; then
  exit 1
fi
case "${1:-}" in
  init) touch .no-mistakes-init ;;
  doctor) touch .no-mistakes-doctor ;;
  *) exit 2 ;;
esac
SH
  chmod +x "$fakebin/no-mistakes"
  printf '%s\n' "$fakebin"
}

# Make a directory look like a minimal firstmate home (AGENTS.md + bin/).
mark_firstmate_home() {
  local home=$1
  mkdir -p "$home/bin"
  printf '# Firstmate\n' > "$home/AGENTS.md"
}

# A firstmate home that is also a real git repo (so it can host detached
# worktrees for teardown/lease tests).
make_firstmate_git_root() {
  local home=$1
  mkdir -p "$home/bin"
  printf '# Firstmate\n' > "$home/AGENTS.md"
  cat > "$home/bin/fm-guard.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
  chmod +x "$home/bin/fm-guard.sh"
  git -C "$home" init -q
  git -C "$home" add AGENTS.md bin/fm-guard.sh
  git -C "$home" -c user.name='Firstmate Tests' -c user.email='tests@example.invalid' commit -qm initial
}

# Scaffold a filled secondmate charter brief under <home>/data/<id>/brief.md.
# Args: home id charter [project...]
scaffold_secondmate_charter() {
  local home=$1 id=$2 charter=$3
  shift 3
  FM_HOME="$home" FM_SECONDMATE_CHARTER="$charter" "$ROOT/bin/fm-brief.sh" "$id" --secondmate "$@" >/dev/null
}

# Make a directory look like a genuine seeded secondmate home (for handoff tests).
seed_secondmate_home_marker() {
  local home=$1 id=$2
  mark_firstmate_home "$home"
  mkdir -p "$home/data"
  printf '%s\n' "$id" > "$home/.fm-secondmate-home"
}

# Wait up to <limit> 0.1s ticks while <pid> stays alive. Returns 1 if it dies.
wait_live() {
  local pid=$1 limit=${2:-30} i=0
  while [ "$i" -lt "$limit" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 1
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 0
}
