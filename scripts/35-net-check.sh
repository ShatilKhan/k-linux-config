#!/usr/bin/env bash
# Wi-Fi (MediaTek MT7921, mt7921e) and Bluetooth (btusb 13d3:3563) checks.
# --hold   keep the running kernel: hold its packages so updates cannot remove it.
source "$(dirname "$0")/lib.sh"

K="$(uname -r)"; log "kernel $K"
# Kernels with reported MT7921 Wi-Fi regressions on 26.04 (update this list as bugs close).
case "$K" in
  7.0.0-27-*|7.0.0-30-*) warn "kernel $K has a reported MT7921 Wi-Fi regression; consider the previous kernel" ;;
esac

rc=0
lsmod | matches '^mt7921e' && log "Wi-Fi driver mt7921e loaded" || { warn "mt7921e not loaded"; rc=1; }
nmcli -t -f TYPE,STATE device 2>/dev/null | matches '^wifi:connected' && log "Wi-Fi connected" || warn "Wi-Fi not connected"
verify_tool bluetooth || rc=1
bluetoothctl show 2>/dev/null | matches 'Powered: yes' && log "Bluetooth powered" || { warn "Bluetooth adapter not powered"; rc=1; }
rfkill list 2>/dev/null | matches 'Soft blocked: yes' && warn "a radio is soft-blocked (rfkill unblock all)"

if [[ " $* " == *" --hold "* ]]; then
  owner_sudo "$@"
  run sudo apt-mark hold "linux-image-$K" "linux-modules-$K" "linux-modules-extra-$K" 2>/dev/null || true
  log "held kernel $K. Undo later with: sudo apt-mark unhold linux-image-$K linux-modules-$K"
fi

cat <<'TXT'

Manual test list (do each 5 times):
  [ ] Close the lid, wait 30 s, open it: screen is locked, laptop did not sleep
  [ ] Lock the screen (Super+L), let the display blank, wake it
  [ ] Pair and use a Bluetooth headset; toggle Bluetooth off and on
  [ ] Wi-Fi still works after each of the above
If any test fails, reboot into the previous kernel (GRUB > Advanced options),
repeat the test, and if it passes run: scripts/35-net-check.sh --hold
TXT
((rc == 0)) || die "network checks failed"
mark_done
log "Next: scripts/40-docker.sh"
