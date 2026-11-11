#!/usr/bin/env bash
# Shared helpers. Source this file; do not run it.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_TSV="$REPO_DIR/config/tools.tsv"
REPORT="${VERIFY_REPORT:-$HOME/verify-report.md}"
CHECK_ONLY=0
for a in "$@"; do [[ "$a" == "--check" ]] && CHECK_ONLY=1; done

# Every run is also written to ~/.local/state/k-setup/<script>.log, so an agent can read
# the result of a script the owner ran in another terminal.
STATE_DIR="$HOME/.local/state/k-setup"
mkdir -p "$STATE_DIR"
exec > >(tee -a "$STATE_DIR/$(basename "$0" .sh).log") 2>&1

# owner_sudo: stop before any change when sudo cannot ask for a password (no terminal,
# for example an agent's Bash tool). The owner then runs the script in a terminal.
owner_sudo() {
  ((CHECK_ONLY)) && return 0
  [[ "${SELF_TEST:-0}" == 1 ]] && return 0
  [[ -t 0 ]] && return 0
  sudo -n true 2>/dev/null && return 0
  printf 'OWNER-RUN: this step needs sudo. Run it in a terminal:\n  cd %s && scripts/%s %s\n' \
    "$REPO_DIR" "$(basename "$0")" "${*:-}"
  exit 3
}

# mark_done: record that this script finished with all checks passing (not in --check mode).
mark_done() {
  ((CHECK_ONLY)) && return 0
  date -Is >"$STATE_DIR/$(basename "$0" .sh).done"
  log "PASS: marked done in $STATE_DIR"
}

log()  { printf '\033[1m[%s]\033[0m %s\n' "$(basename "$0" .sh)" "$*"; }
warn() { printf '\033[33m[%s] WARN:\033[0m %s\n' "$(basename "$0" .sh)" "$*" >&2; }
die()  { printf '\033[31m[%s] FAIL:\033[0m %s\n' "$(basename "$0" .sh)" "$*" >&2; exit 1; }

# run <cmd...>: execute, or only print it in --check mode.
run() { if ((CHECK_ONLY)); then log "would run: $*"; else "$@"; fi; }

# ver_ge A B: true when version A >= version B.
ver_ge() { [[ "$(printf '%s\n%s\n' "$1" "$2" | LC_ALL=C sort -V | head -1)" == "$2" ]]; }

# first x.y[.z] number in a string
ver_of() { grep -oE '[0-9]+(\.[0-9]+)+' <<<"$1" | head -1 || true; }

report() { printf '%s\n' "$*" >>"$REPORT"; }

# Add a block of text to a file once, between marker lines.
add_block() { # file marker text
  local f="$1" m="$2" t="$3"
  touch "$f"
  grep -qF "# >>> $m >>>" "$f" && return 0
  if ((CHECK_ONLY)); then log "would add block '$m' to $f"; return 0; fi
  printf '\n# >>> %s >>>\n%s\n# <<< %s <<<\n' "$m" "$t" "$m" >>"$f"
}

# verify_tool <name>: checks one row of config/tools.tsv.
# Columns: name  command  version_cmd  rule(>=|==|any)  version  service
# Prints PASS/FAIL and returns 1 on FAIL.
verify_tool() {
  local name="$1" row cmd vcmd rule want svc out have status=PASS why=""
  row="$(awk -F'\t' -v n="$name" '$1==n' "$TOOLS_TSV")"
  [[ -n "$row" ]] || die "no row for '$name' in tools.tsv"
  IFS=$'\t' read -r _ cmd vcmd rule want svc <<<"$row"

  if ! command -v "$cmd" >/dev/null 2>&1; then status=FAIL; why="not on PATH (interactive)"
  # Claude Code and GUI apps start programs from a login shell without a terminal.
  elif ! env -i HOME="$HOME" USER="$USER" PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash -lc "command -v '$cmd'" >/dev/null 2>&1; then
    status=FAIL; why="not on PATH for non-interactive login shells (~/.profile)"
  else
    out="$(bash -c "$vcmd" 2>&1 | head -5 || true)"; have="$(ver_of "$out")"
    case "$rule" in
      ">=") ver_ge "${have:-0}" "$want" || { status=FAIL; why="version ${have:-?} < $want"; } ;;
      "==") [[ "$have" == "$want" ]] || { status=FAIL; why="version ${have:-?} != $want"; } ;;
    esac
  fi
  if [[ "$status" == PASS && "$svc" != "-" ]]; then
    systemctl is-active --quiet "$svc" || { status=FAIL; why="service $svc not active"; }
  fi
  printf '%-4s %-26s %s\n' "$status" "$name" "${have:-} ${why}"
  report "| $status | $name | ${have:-} | ${why} |"
  [[ "$status" == PASS ]]
}

# verify_rows <name...>: verify several rows, report all, fail if any failed.
verify_rows() { local rc=0; for n in "$@"; do verify_tool "$n" || rc=1; done; return $rc; }

need_ubuntu_2604() {
  # shellcheck disable=SC1091
  . /etc/os-release
  [[ "${VERSION_ID:-}" == "26.04" ]] || die "expected Ubuntu 26.04, found ${PRETTY_NAME:-unknown}"
}

# Write a file through sudo, only when content differs.
sudo_write() { # path content
  local p="$1" c="$2"
  if [[ -f "$p" ]] && [[ "$(sudo cat "$p")" == "$c" ]]; then return 0; fi
  run sudo install -D -m 644 /dev/stdin "$p" <<<"$c"
}

# ---- old home partition (read-only) ----
OLD_MNT="${OLD_MNT:-/mnt/oldhome}"
OLD_HOME="${OLD_HOME:-$OLD_MNT/$USER}"
LISTS="${LISTS:-$OLD_HOME/.config/k-migration}"

# Find the old /home partition: an unmounted ext4 partition that holds
# <user>/.config/k-migration. Prints the device path.
find_old_home() {
  local dev tmp
  tmp="$(mktemp -d)"
  while read -r dev; do
    findmnt -rn -S "$dev" >/dev/null && continue
    sudo mount -o ro "$dev" "$tmp" 2>/dev/null || continue
    if [[ -d "$tmp/$USER/.config/k-migration" ]]; then sudo umount "$tmp"; rmdir "$tmp"; echo "$dev"; return 0; fi
    sudo umount "$tmp"
  done < <(lsblk -rpno NAME,FSTYPE | awk '$2=="ext4"{print $1}')
  rmdir "$tmp"; return 1
}

# Mount the old home read-only at $OLD_MNT (never added to fstab).
mount_old() {
  # SELF_TEST=1 OLD_HOME=$HOME: dry-run the scripts on the old machine against itself.
  [[ "${SELF_TEST:-0}" == 1 ]] && return 0
  if findmnt -rn "$OLD_MNT" >/dev/null; then
    findmnt -rno OPTIONS "$OLD_MNT" | grep -qw ro || die "$OLD_MNT is mounted read-write; unmount it first"
    return 0
  fi
  local dev="${OLD_DEV:-}"
  [[ -n "$dev" ]] || dev="$(find_old_home)" || die "old home partition not found; pass OLD_DEV=/dev/nvmeXnYpZ"
  sudo mkdir -p "$OLD_MNT"
  sudo mount -o ro "$dev" "$OLD_MNT"
  log "mounted $dev read-only at $OLD_MNT"
  [[ -d "$LISTS" ]] || die "private lists not found at $LISTS"
}

umount_old() { findmnt -rn "$OLD_MNT" >/dev/null && sudo umount "$OLD_MNT" && log "unmounted $OLD_MNT" || true; }

# Read a list file: drop comments and blank lines.
read_list() { grep -vE '^\s*(#|$)' "$1" || true; }

# rsync options shared by the copy and the copy check.
RSYNC_OPTS=(-aHAXS --numeric-ids --relative)
# Always skipped: login tokens (fresh logins on the new machine).
ALWAYS_SKIP=(--exclude=/.claude/.credentials.json --exclude=/.codex/auth.json)

# count <find args...>: number of matches; 0 (not an error) when the path is missing.
count() { { find "$@" 2>/dev/null || true; } | wc -l; }

# executor_ram: memory of the executor user service in MB ("?" when not running).
executor_ram() {
  local b; b="$(systemctl --user show executor -p MemoryCurrent --value 2>/dev/null || true)"
  [[ "$b" =~ ^[0-9]+$ ]] && echo "$((b / 1024 / 1024)) MB" || echo "?"
}

# verify_pkgs <deb...>: every apt package must be installed. Prints PASS/FAIL per package.
verify_pkgs() {
  local p rc=0
  for p in "$@"; do
    if [[ "$(dpkg-query -W -f '${db:Status-Status}' "$p" 2>/dev/null)" == installed ]]; then
      printf 'PASS apt  %s\n' "$p"; report "| PASS | apt $p | | |"
    else printf 'FAIL apt  %s not installed\n' "$p"; report "| FAIL | apt $p | | not installed |"; rc=1; fi
  done
  return $rc
}

# copy_diffs <path>: files under <path> that are missing or older in $HOME than in $OLD_HOME.
# -u: files changed on the new machine after the copy do not count.
copy_diffs() {
  rsync "${RSYNC_OPTS[@]}" -nu --checksum --itemize-changes "${ALWAYS_SKIP[@]}" \
    --exclude-from="$LISTS/skip-list.txt" "$OLD_HOME/./$1" "$HOME/" | grep -vE '^\.d' | grep -c . || true
}
