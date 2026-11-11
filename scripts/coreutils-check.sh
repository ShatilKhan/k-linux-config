#!/usr/bin/env bash
# Check every coreutils form these scripts use. Ubuntu 25.10+ ships the Rust coreutils
# (uutils), whose behavior can differ from GNU between versions (on 26.04, locale-aware sort
# broke comm). Run by 00-preflight.sh before anything changes. Writes only to a temp dir.
set -uo pipefail
T="$(mktemp -d)"; trap 'rm -r "$T"' EXIT
fails=0
t() { # name command...
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then echo "PASS coreutils  $name"; else echo "FAIL coreutils  $name"; fails=$((fails + 1)); fi
}

t "install -D -m 644 /dev/stdin" bash -c "install -D -m 644 /dev/stdin '$T/a/b/x.conf' <<<hello && grep -qx hello '$T/a/b/x.conf'"
t "install -d -m 0710"          bash -c "install -d -m 0710 '$T/d1' && [[ \$(stat -c %a '$T/d1') == 710 ]]"
t "install -m 644 file"         install -m 644 /etc/hostname "$T/h"
t "date -Is"                    bash -c "date -Is | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'"
t "df -h --output=avail"        bash -c "df -h --output=avail / | tail -1 | grep -qE '[0-9]'"
t "sort -V 0.9.5 < 0.10.0"      bash -c "[[ \$(printf '0.10.0\n0.9.5\n' | LC_ALL=C sort -V | head -1) == 0.9.5 ]]"
t "sort -V 2.97.0 < 2.103.3"    bash -c "[[ \$(printf '2.103.3\n2.97.0\n' | LC_ALL=C sort -V | head -1) == 2.97.0 ]]"
t "sort -V 595.58 < 595.71.05"  bash -c "[[ \$(printf '595.71.05\n595.58\n' | LC_ALL=C sort -V | head -1) == 595.58 ]]"
t "LC_ALL=C sort -u + comm -23" bash -c "[[ \$(LC_ALL=C comm -23 <(printf 'B\na\n.c\nDesktop\n.config/x\n' | LC_ALL=C sort -u) <(printf 'a\n')) == \$(printf '.c\n.config/x\nB\nDesktop') ]]"
t "stat -c %a"                  bash -c "[[ \$(stat -c %a /etc/hostname) =~ ^[0-7]{3}$ ]]"
t "chmod 600 + stat"            bash -c "touch '$T/k' && chmod 600 '$T/k' && [[ \$(stat -c %a '$T/k') == 600 ]]"
t "env -i login shell"          env -i HOME="$HOME" PATH=/usr/bin:/bin bash -lc "command -v ls"
t "env -u"                      env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS true
t "timeout stops a command"     bash -c "! timeout 1 sleep 3"
t "timeout passes exit 0"       timeout 2 true
t "mktemp -d"                   bash -c "d=\$(mktemp -d) && [[ -d \$d ]] && rmdir \$d"
t "cp -a keeps mode"            bash -c "chmod 640 '$T/h' && cp -a '$T/h' '$T/h2' && [[ \$(stat -c %a '$T/h2') == 640 ]]"
t "ls -A"                       ls -A /tmp
t "tail -n +2"                  bash -c "[[ \$(printf 'a\nb\n' | tail -n +2) == b ]]"
t "tee -a"                      bash -c "echo x | tee -a '$T/t' >/dev/null && grep -qx x '$T/t'"
t "wc -l"                       bash -c "[[ \$(printf 'a\nb\n' | wc -l | tr -d ' ') == 2 ]]"
t "cut -d/ -f1"                 bash -c "[[ \$(echo a/b | cut -d/ -f1) == a ]]"
t "cut -c1-3"                   bash -c "[[ \$(echo abcdef | cut -c1-3) == abc ]]"
t "seq"                         bash -c "[[ \$(seq 3 | tail -1) == 3 ]]"
t "head -1 on a pipe"           bash -c "[[ \$(seq 5 | head -1) == 1 ]]"
t "basename .sh"                bash -c "[[ \$(basename /x/10-migrate.sh .sh) == 10-migrate ]]"
t "dirname"                     bash -c "[[ \$(dirname /x/y/z) == /x/y ]]"

((fails == 0)) && echo "coreutils: all checks PASS" || echo "coreutils: $fails checks FAIL"
exit $((fails > 0))
