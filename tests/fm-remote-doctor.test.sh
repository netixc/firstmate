#!/usr/bin/env bash
# Pi-only remote secondmate readiness tests.
set -eu

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TMP_ROOT=$(fm_test_tmproot fm-remote-doctor-pi)
DOCTOR="$ROOT/bin/fm-remote-doctor.sh"

make_tool() {
  local bin=$1 name=$2
  cat > "$bin/$name" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
  --version|-v|-V) printf '0.2.4\n' ;;
  get) [ "${2:-}" = --help ] && printf 'Usage: treehouse get [--lease]\n' ;;
  update) [ "${2:-}" = --help ] && printf 'usage: tasks-axi update <id> --archive-body\n' ;;
  mv) [ "${2:-}" = --help ] && printf 'usage: tasks-axi mv <dest> [<id>...]\n' ;;
esac
exit 0
SH
  chmod +x "$bin/$name"
}

run_probe() {
  local bin=$1 home=$2
  PATH="$bin:/usr/bin:/bin:/usr/sbin:/sbin" HOME="$home" FM_ROOT_OVERRIDE="$ROOT" FM_REMOTE_JOB_ACTIVE=1 \
    "$DOCTOR" --worker-tool-probe 2>&1
}

test_remote_doctor_requires_pi() {
  local bin="$TMP_ROOT/bin" home="$TMP_ROOT/home" out rc=0 tool
  mkdir -p "$bin" "$home"
  for tool in git jq herdr tasks-axi treehouse pi; do make_tool "$bin" "$tool"; done
  out=$(run_probe "$bin" "$home") || rc=$?
  [ "$rc" -eq 0 ] || fail "Pi-ready remote probe failed: $out"
  assert_contains "$out" "required harness=pi:$bin/pi" "remote doctor did not report Pi requirement"
  rm -f "$bin/pi"
  out=$(run_probe "$bin" "$home") || rc=$?
  assert_contains "$out" 'required harness=MISSING' "remote doctor did not report missing Pi"
  pass "remote secondmate doctor requires Pi and no alternate worker runtime"
}

test_remote_doctor_requires_pi
