#!/usr/bin/env bash
# Tighten permissions on copied secrets and agent state. Never prints file contents.
source "$(dirname "$0")/lib.sh"

private_dirs=(.ssh .config/k-migration .claude .codex .agents .config/opencode .config/gh .aws .cloudflared)
for d in "${private_dirs[@]}"; do
  [[ -d "$HOME/$d" ]] && run chmod 700 "$HOME/$d"
done
if [[ -d "$HOME/.ssh" ]]; then
  # private keys and config 600, public keys 644
  while IFS= read -r -d '' f; do
    case "$f" in *.pub) run chmod 644 "$f" ;; *) run chmod 600 "$f" ;; esac
  done < <(find "$HOME/.ssh" -maxdepth 1 -type f -print0)
fi
[[ -f "$HOME/.claude.json" ]] && run chmod 600 "$HOME/.claude.json"

# Check: each private dir is 700 and each private key is 600.
((CHECK_ONLY)) || for d in "${private_dirs[@]}"; do
  [[ -d "$HOME/$d" ]] || continue
  [[ "$(stat -c %a "$HOME/$d")" == 700 ]] || die "$d is not mode 700"
done
((CHECK_ONLY)) || while IFS= read -r -d '' f; do
  [[ "$(stat -c %a "$f")" == 600 ]] || die "$f is not mode 600"
done < <(find "$HOME/.ssh" -maxdepth 1 -type f ! -name '*.pub' -print0 2>/dev/null)
log "permissions OK"
log "done. Next: scripts/20-apps.sh"
