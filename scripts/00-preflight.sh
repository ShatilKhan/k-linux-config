#!/usr/bin/env bash
# Check that this machine matches what the other scripts expect. Changes nothing.
source "$(dirname "$0")/lib.sh"
rc=0
need_ubuntu_2604 && log "Ubuntu 26.04 OK"
[[ "$USER" == k ]] || { warn "user is '$USER'; Claude session paths need user 'k' (/home/k/...)"; rc=1; }
[[ "$(id -u)" == 1000 ]] || warn "uid is $(id -u); old files are owned by uid 1000"
[[ "$(findmnt -rno TARGET /home)" == /home ]] && log "/home is a separate partition" || { warn "/home is not a separate partition"; rc=1; }
[[ -d /sys/firmware/efi ]] && log "UEFI boot OK" || warn "not booted in UEFI mode"
log "root free: $(df -h --output=avail / | tail -1 | tr -d ' ')   home free: $(df -h --output=avail /home | tail -1 | tr -d ' ')"
swapon --show=NAME,SIZE --noheadings | while read -r n s; do log "swap $n $s"; done
if ! swapon --show=SIZE --bytes --noheadings | awk '{t+=$1} END{exit !(t>=15*1024^3)}'; then
  warn "swap below 16G. Fix: sudo swapoff /swap.img && sudo fallocate -l 16G /swap.img && sudo chmod 600 /swap.img && sudo mkswap /swap.img && sudo swapon /swap.img"
  if [[ " $* " == *" --fix-swap "* ]]; then
    run sudo swapoff /swap.img; run sudo fallocate -l 16G /swap.img; run sudo chmod 600 /swap.img
    run sudo mkswap /swap.img; run sudo swapon /swap.img
    grep -q '^/swap.img' /etc/fstab || run sudo bash -c "echo '/swap.img none swap sw 0 0' >> /etc/fstab"
  fi
fi
curl -fsS -o /dev/null https://github.com && log "internet OK" || { warn "no internet"; rc=1; }
dev="$(find_old_home || true)"
[[ -n "$dev" ]] && log "old home partition found: $dev" || { warn "old home partition not found (needed by 10-migrate.sh)"; rc=1; }
((rc == 0)) || die "preflight failed"
log "preflight PASS. Next: scripts/10-migrate.sh"
