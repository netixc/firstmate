#!/usr/bin/env bash
# fm-pi-admission.sh - the sole owner of Pi user-message admission receipts.
#
# A generated per-task Pi extension calls `record` from Pi's accepted
# `message_start` lifecycle event after reducing one user message to an
# unambiguous single text block. The extension computes SHA-256 and UTF-8 byte
# length in-process and passes only those values here; instruction text is never
# written to state or placed in this helper's argv.
#
# Receipt journal: state/<id>.pi-admission, mode 0600, at most 128 lines:
#
#   v1 gen=<busy-gen> seq=<uint> sha256=<64-lower-hex> bytes=<uint> ts=<epoch-ms>
#
# `record` binds every append to state/<id>.busy-gen under a bounded per-task
# writer lock, advances a strictly increasing per-generation sequence, and
# publishes the bounded journal by atomic replacement. A stale extension
# generation is rejected. Relaunch retires the old journal before arming its
# replacement.
#
# `snapshot` prints the current generation's monotonic sequence boundary, or 0
# when no current-generation receipt exists. `match` succeeds only when the
# complete journal is a safe ordinary file containing a strictly ordered,
# current-generation record newer than the supplied boundary with the exact
# digest and byte length. Missing, mixed-generation, malformed, unreadable,
# oversized, truncated, symlinked, hardlinked, or otherwise unsafe journals
# never prove admission. Receipt failures never authorize retrying message text.
#
# `hash` reads the exact payload from stdin and prints
# `<sha256><TAB><utf8-bytes>`. `retire` removes only the named current generation
# while holding both the exact-task send boundary and writer lock; an unsafe
# leaf symlink is unlinked rather than followed. All commands reject unsafe
# state directories and task ids.
#
# Usage:
#   fm-pi-admission.sh hash
#   fm-pi-admission.sh record <state-dir> <id> --gen G --sha256 H --bytes N --ts MS
#   fm-pi-admission.sh snapshot <state-dir> <id> --gen G
#   fm-pi-admission.sh match <state-dir> <id> --gen G --after N --sha256 H --bytes N
#   fm-pi-admission.sh retire <state-dir> <id> --gen G
set -u

usage() {
  cat >&2 <<'EOF'
usage:
  fm-pi-admission.sh hash
  fm-pi-admission.sh record <state-dir> <id> --gen G --sha256 H --bytes N --ts MS
  fm-pi-admission.sh snapshot <state-dir> <id> --gen G
  fm-pi-admission.sh match <state-dir> <id> --gen G --after N --sha256 H --bytes N
  fm-pi-admission.sh retire <state-dir> <id> --gen G
See the header comment for the receipt format and proof contract.
EOF
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD=${1:-}
[ -n "$CMD" ] || usage
shift || true

if [ "$CMD" = hash ]; then
  [ "$#" -eq 0 ] || usage
  command -v node >/dev/null 2>&1 || exit 1
  node -e '
    const { createHash } = require("node:crypto");
    const chunks = [];
    process.stdin.on("data", (chunk) => chunks.push(chunk));
    process.stdin.on("end", () => {
      const body = Buffer.concat(chunks);
      process.stdout.write(createHash("sha256").update(body).digest("hex") + "\t" + body.length + "\n");
    });
  '
  exit $?
fi

case "$CMD" in record|snapshot|match|retire) : ;; *) usage ;; esac
STATE=${1:-}
ID=${2:-}
[ -n "$STATE" ] && [ -n "$ID" ] || usage
shift 2
case "$ID" in ''|*[!A-Za-z0-9._-]*) echo "error: invalid task id" >&2; exit 1 ;; esac
[ -d "$STATE" ] && [ ! -L "$STATE" ] || { echo "error: unsafe state directory" >&2; exit 1; }
STATE_REAL=$(CDPATH='' cd -- "$STATE" 2>/dev/null && pwd -P) || { echo "error: unreadable state directory" >&2; exit 1; }
# Resolve harmless parent aliases such as macOS /tmp -> /private/tmp once, then
# construct every receipt, generation, temp, and lock leaf beneath that exact
# canonical directory. The state directory itself may not be a symlink.
STATE=$STATE_REAL

GEN=
SHA=
BYTES=
TS=
AFTER=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --gen) GEN=${2:-}; shift 2 || usage ;;
    --sha256) SHA=${2:-}; shift 2 || usage ;;
    --bytes) BYTES=${2:-}; shift 2 || usage ;;
    --ts) TS=${2:-}; shift 2 || usage ;;
    --after) AFTER=${2:-}; shift 2 || usage ;;
    *) usage ;;
  esac
done

# shellcheck source=bin/fm-busy-lib.sh
. "$SCRIPT_DIR/fm-busy-lib.sh"
fm_busy_token_valid "$GEN" || { echo "error: invalid generation" >&2; exit 1; }

uint_valid() {  # <value> [allow-zero]
  local value=${1:-} allow_zero=${2:-1}
  case "$value" in ''|*[!0-9]*) return 1 ;; esac
  [ "${#value}" -le 15 ] || return 1
  if [ "$value" = 0 ]; then
    [ "$allow_zero" = 1 ]
  else
    case "$value" in 0*) return 1 ;; esac
  fi
}

sha_valid() {
  [ "${#1}" -eq 64 ] || return 1
  case "$1" in *[!0-9a-f]*) return 1 ;; esac
}

case "$CMD" in
  record)
    if ! sha_valid "$SHA" || ! uint_valid "$BYTES" 1 || ! uint_valid "$TS" 0; then
      echo "error: invalid receipt metadata" >&2
      exit 1
    fi
    [ -z "$AFTER" ] || usage
    ;;
  snapshot|retire)
    [ -z "$SHA$BYTES$TS$AFTER" ] || usage
    ;;
  match)
    if ! sha_valid "$SHA" || ! uint_valid "$BYTES" 1 || ! uint_valid "$AFTER" 1; then
      echo "error: invalid receipt match" >&2
      exit 1
    fi
    [ -z "$TS" ] || usage
    ;;
esac

REC="$STATE/$ID.pi-admission"
GEN_FILE=$(fm_busy_gen_path "$STATE" "$ID")
LOCK="$STATE/.$ID.pi-admission.lock"
SEND_LOCK="$STATE/.$ID.pi-admission-send.lock"
SEND_LOCK_HELD=0
FM_PI_ADMISSION_MAX_BYTES=65536
FM_PI_ADMISSION_MAX_RECORDS=128

path_nlink() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %l "$1" 2>/dev/null
  else
    stat -c %h "$1" 2>/dev/null
  fi
}

path_size() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %z "$1" 2>/dev/null
  else
    stat -c %s "$1" 2>/dev/null
  fi
}

path_mode() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %Lp "$1" 2>/dev/null
  else
    stat -c %a "$1" 2>/dev/null
  fi
}

path_owner() {
  if [ "$(uname)" = Darwin ]; then
    stat -f %u "$1" 2>/dev/null
  else
    stat -c %u "$1" 2>/dev/null
  fi
}

safe_regular() {  # <path>
  local path=$1 links size mode owner
  [ -f "$path" ] && [ ! -L "$path" ] && [ -r "$path" ] || return 1
  links=$(path_nlink "$path") || return 1
  [ "$links" = 1 ] || return 1
  mode=$(path_mode "$path") || return 1
  [ "$mode" = 600 ] || return 1
  owner=$(path_owner "$path") || return 1
  [ "$owner" = "$(id -u)" ] || return 1
  size=$(path_size "$path") || return 1
  uint_valid "$size" 1 || return 1
  [ "$size" -le "$FM_PI_ADMISSION_MAX_BYTES" ] || return 1
}

SAFE_REGULAR_CONTENT=
safe_regular_read() {  # <path>
  local path=$1 raw
  raw=$(node - "$path" "$FM_PI_ADMISSION_MAX_BYTES" <<'JS'
const fs = require("node:fs");
const path = process.argv[2];
const max = Number(process.argv[3]);
let fd;
try {
  fd = fs.openSync(path, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  const before = fs.fstatSync(fd);
  if (!before.isFile() || before.nlink !== 1 || (before.mode & 0o777) !== 0o600 ||
      before.uid !== process.getuid() || before.size > max) process.exit(1);
  const body = Buffer.alloc(before.size);
  let offset = 0;
  while (offset < body.length) {
    const read = fs.readSync(fd, body, offset, body.length - offset, offset);
    if (read === 0) process.exit(1);
    offset += read;
  }
  const after = fs.fstatSync(fd);
  if (after.dev !== before.dev || after.ino !== before.ino || after.size !== before.size ||
      after.nlink !== 1 || (after.mode & 0o777) !== 0o600 || after.uid !== process.getuid() ||
      body.length === 0 || body[body.length - 1] !== 10 || body.includes(0)) process.exit(1);
  process.stdout.write(body);
  process.stdout.write(".");
} catch (_) {
  process.exit(1);
} finally {
  if (fd !== undefined) fs.closeSync(fd);
}
JS
  ) || return 1
  case "$raw" in *$'\n'.) : ;; *) return 1 ;; esac
  raw=${raw%.}
  SAFE_REGULAR_CONTENT=${raw%$'\n'}
}

current_gen_exact() {
  local current
  safe_regular_read "$GEN_FILE" || return 1
  current=$SAFE_REGULAR_CONTENT
  fm_busy_token_valid "$current" || return 1
  [ "$current" = "$GEN" ]
}

R_GEN=
R_SEQ=
R_SHA=
R_BYTES=
R_TS=
parse_line() {  # <line>
  local line=$1 ver f_gen f_seq f_sha f_bytes f_ts extra
  IFS=' ' read -r ver f_gen f_seq f_sha f_bytes f_ts extra <<EOF
$line
EOF
  [ "$ver" = v1 ] && [ -z "$extra" ] || return 1
  case "$f_gen" in gen=*) R_GEN=${f_gen#gen=} ;; *) return 1 ;; esac
  case "$f_seq" in seq=*) R_SEQ=${f_seq#seq=} ;; *) return 1 ;; esac
  case "$f_sha" in sha256=*) R_SHA=${f_sha#sha256=} ;; *) return 1 ;; esac
  case "$f_bytes" in bytes=*) R_BYTES=${f_bytes#bytes=} ;; *) return 1 ;; esac
  case "$f_ts" in ts=*) R_TS=${f_ts#ts=} ;; *) return 1 ;; esac
  fm_busy_token_valid "$R_GEN" || return 1
  uint_valid "$R_SEQ" 0 || return 1
  sha_valid "$R_SHA" || return 1
  uint_valid "$R_BYTES" 1 || return 1
  uint_valid "$R_TS" 0 || return 1
}

JOURNAL_GEN=
JOURNAL_LAST_SEQ=0
JOURNAL_COUNT=0
JOURNAL_MATCHED=0
JOURNAL_CONTENT=
scan_journal() {  # [match]
  local mode=${1:-scan} line last_seq=0 count=0
  JOURNAL_GEN=
  JOURNAL_LAST_SEQ=0
  JOURNAL_COUNT=0
  JOURNAL_MATCHED=0
  safe_regular_read "$REC" || return 1
  JOURNAL_CONTENT=$SAFE_REGULAR_CONTENT
  [ -n "$JOURNAL_CONTENT" ] || return 1
  while IFS= read -r line; do
    count=$((count + 1))
    [ "$count" -le "$FM_PI_ADMISSION_MAX_RECORDS" ] || return 1
    parse_line "$line" || return 1
    if [ -z "$JOURNAL_GEN" ]; then
      JOURNAL_GEN=$R_GEN
    else
      [ "$R_GEN" = "$JOURNAL_GEN" ] || return 1
    fi
    [ "$R_SEQ" -gt "$last_seq" ] || return 1
    last_seq=$R_SEQ
    if [ "$mode" = match ] && [ "$R_GEN" = "$GEN" ] \
      && [ "$R_SEQ" -gt "$AFTER" ] && [ "$R_SHA" = "$SHA" ] \
      && [ "$R_BYTES" = "$BYTES" ]; then
      JOURNAL_MATCHED=1
    fi
  done <<EOF
$JOURNAL_CONTENT
EOF
  [ "$count" -gt 0 ] || return 1
  JOURNAL_LAST_SEQ=$last_seq
  JOURNAL_COUNT=$count
}

# Every read, append, and retirement shares one robust pid/identity lock.
# Readers hold it only for one bounded journal scan, so a receipt event racing a
# match is observed either in this read or in fm-send's next bounded poll.
# Retirement first joins fm-send's exact-task boundary, then takes this writer
# lock in the same order as a send, so relaunch and cleanup cannot retire an
# incarnation halfway through its attributable proof.
FM_STATE_OVERRIDE=$STATE
# shellcheck source=bin/fm-wake-lib.sh
. "$SCRIPT_DIR/fm-wake-lib.sh"
# shellcheck disable=SC2329 # Invoked by the EXIT and record cleanup traps.
release_lock() {
  local status=$?
  fm_lock_release "$LOCK" || true
  if [ "$SEND_LOCK_HELD" = 1 ]; then
    SEND_LOCK_HELD=0
    fm_lock_release "$SEND_LOCK" || true
  fi
  return "$status"
}
trap release_lock EXIT
FM_PI_ADMISSION_LOCK_ATTEMPTS=${FM_PI_ADMISSION_LOCK_ATTEMPTS:-50}
FM_PI_ADMISSION_LOCK_SLEEP=${FM_PI_ADMISSION_LOCK_SLEEP:-0.1}
if [ "$CMD" = retire ]; then
  fm_lock_acquire_bounded "$SEND_LOCK" "$FM_PI_ADMISSION_LOCK_ATTEMPTS" "$FM_PI_ADMISSION_LOCK_SLEEP" || exit 1
  SEND_LOCK_HELD=1
fi
fm_lock_acquire_bounded "$LOCK" "$FM_PI_ADMISSION_LOCK_ATTEMPTS" "$FM_PI_ADMISSION_LOCK_SLEEP" || exit 1

if [ "$CMD" = snapshot ]; then
  current_gen_exact || exit 1
  if [ ! -e "$REC" ] && [ ! -L "$REC" ]; then
    printf '0\n'
    exit 0
  fi
  scan_journal || exit 1
  if [ "$JOURNAL_GEN" = "$GEN" ]; then
    printf '%s\n' "$JOURNAL_LAST_SEQ"
  else
    printf '0\n'
  fi
  exit 0
fi

if [ "$CMD" = match ]; then
  current_gen_exact || exit 1
  scan_journal match || exit 1
  [ "$JOURNAL_GEN" = "$GEN" ] && [ "$JOURNAL_MATCHED" = 1 ]
  exit $?
fi

current_gen_exact || { echo "error: stale admission generation" >&2; exit 1; }

if [ "$CMD" = retire ]; then
  if [ -L "$REC" ]; then
    rm -f -- "$REC" || exit 1
  elif [ -e "$REC" ]; then
    safe_regular "$REC" || { echo "error: unsafe admission receipt" >&2; exit 1; }
    rm -f -- "$REC" || exit 1
  fi
  exit 0
fi

# record
old_seq=0
keep_existing=0
if [ -e "$REC" ] || [ -L "$REC" ]; then
  scan_journal || { echo "error: malformed or unsafe admission receipt" >&2; exit 1; }
  if [ "$JOURNAL_GEN" = "$GEN" ]; then
    old_seq=$JOURNAL_LAST_SEQ
    keep_existing=1
  fi
fi
[ "$old_seq" -lt 999999999999999 ] || { echo "error: admission sequence exhausted" >&2; exit 1; }
next_seq=$((old_seq + 1))
tmp=$(umask 077; mktemp "$STATE/.$ID.pi-admission.XXXXXX") || exit 1
# shellcheck disable=SC2329 # Invoked by the record cleanup trap.
cleanup_tmp() { rm -f -- "$tmp" 2>/dev/null || true; }
trap 'status=$?; cleanup_tmp; release_lock; exit $status' EXIT HUP INT TERM
if [ "$keep_existing" = 1 ] && [ "$JOURNAL_COUNT" -ge "$FM_PI_ADMISSION_MAX_RECORDS" ]; then
  printf '%s\n' "$JOURNAL_CONTENT" | tail -n $((FM_PI_ADMISSION_MAX_RECORDS - 1)) > "$tmp" || exit 1
elif [ "$keep_existing" = 1 ]; then
  printf '%s\n' "$JOURNAL_CONTENT" > "$tmp" || exit 1
fi
printf 'v1 gen=%s seq=%s sha256=%s bytes=%s ts=%s\n' \
  "$GEN" "$next_seq" "$SHA" "$BYTES" "$TS" >> "$tmp" || exit 1
chmod 600 "$tmp" || exit 1
if [ -L "$REC" ] || { [ -e "$REC" ] && ! safe_regular "$REC"; }; then
  echo "error: admission receipt changed to an unsafe path" >&2
  exit 1
fi
mv -f -- "$tmp" "$REC" || exit 1
tmp=
exit 0
