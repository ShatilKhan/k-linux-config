#!/usr/bin/env bash
# Copy user data from the old /home partition (mounted read-only) into this /home.
# Paths come from the private lists, never from this repo:
#   $LISTS/copy-list.txt   paths relative to the old home, one per line
#   $LISTS/skip-list.txt   rsync exclude patterns, anchored with a leading /
# Usage: scripts/10-migrate.sh [--check]     (OLD_DEV=/dev/... to skip auto-detect)
source "$(dirname "$0")/lib.sh"
owner_sudo "$@"

[[ "$(id -u)" -ne 0 ]] || die "run as the normal user, not root"
mount_old

COPY="$LISTS/copy-list.txt"; SKIP="$LISTS/skip-list.txt"
[[ -f "$COPY" && -f "$SKIP" ]] || die "copy-list.txt or skip-list.txt missing in $LISTS"

DRY=(--info=progress2); ((CHECK_ONLY)) && DRY=(--dry-run --itemize-changes)
n=0
while read -r p; do
  [[ -e "$OLD_HOME/$p" || -L "$OLD_HOME/$p" ]] || { warn "missing on old side: $p"; continue; }
  log "copy $p"
  rsync "${RSYNC_OPTS[@]}" "${DRY[@]}" "${ALWAYS_SKIP[@]}" --exclude-from="$SKIP" \
    "$OLD_HOME/./$p" "$HOME/"
  if ((!CHECK_ONLY)); then  # check this path right after copying it
    d="$(copy_diffs "$p")"
    [[ "$d" == 0 ]] && log "PASS copy $p" || die "copy of $p has $d differences; run this script again"
  fi
  n=$((n + 1))
done < <(read_list "$COPY")
log "copied and checked $n paths"

# Old shell dotfiles go to ~/old-dotfiles for manual merge; the scripts write fresh ones.
run mkdir -p "$HOME/old-dotfiles"
for f in .bashrc .profile .bash_aliases .bash_history .gitconfig .zshrc; do
  [[ -f "$OLD_HOME/$f" ]] && run cp -a "$OLD_HOME/$f" "$HOME/old-dotfiles/"
done

run mkdir -p "$HOME/dev/models"   # Ollama models live here, not on /

# Leftover report: entries in the old home that the lists do not mention. It checks the
# top level, and inside every parent of a nested list entry (for example .config, .local/bin).
LEFT="$HOME/migrate-leftovers.txt"
listed="$( { read_list "$COPY"; read_list "$SKIP" | sed 's#^/##; s#/$##'; } | sort -u)"
# every ancestor of a nested entry (a, a/b for a/b/c) gets expanded one level
# (ancestors that are listed themselves, like dev for dev/<skipped>, are already covered)
parents="$(comm -23 \
  <(printf '%s\n' "$listed" | awk -F/ 'NF>1{p=$1; print p; for(i=2;i<NF;i++){p=p"/"$i; print p}}' | sort -u) \
  <(printf '%s\n' "$listed"))"
{
  echo "# Entries in the old home that were not copied and not in skip-list."
  echo "# Review before deleting the old partition."
  for dir in . $parents; do
    while IFS= read -r e; do
      if [[ "$dir" == . ]]; then rel="$e"; else rel="$dir/$e"; fi
      grep -qxF "$rel" <<<"$listed" && continue    # copied or skipped
      grep -qxF "$rel" <<<"$parents" && continue   # expanded separately
      echo "$rel"
    done < <(cd "$OLD_HOME/$dir" 2>/dev/null && find . -mindepth 1 -maxdepth 1 -printf '%P\n' | sort)
  done
} >"$LEFT"
log "leftover report: $LEFT ($(($(wc -l <"$LEFT") - 2)) entries)"
mark_done
log "done. Next: scripts/15-secure.sh"
