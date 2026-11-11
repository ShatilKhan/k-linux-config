#!/usr/bin/env bash
# Two GitHub accounts (personal + work) on one machine, chosen by folder:
#   - ~/.gitconfig holds the personal identity and SSH key (the default).
#   - [includeIf "gitdir:<work dir>/"] loads ~/.gitconfig-work: work identity + work key.
#   - Plain git@github.com: remotes work everywhere; no SSH host aliases needed.
#   - gh keeps both accounts in the keyring; ghp / ghw switch the active one.
# Private values come from ~/.config/k-migration/git.env and work-dirs.txt.
source "$(dirname "$0")/lib.sh"
P="$HOME/.config/k-migration"
[[ -f "$P/git.env" && -f "$P/work-dirs.txt" ]] || die "missing $P/git.env or work-dirs.txt (run 10-migrate.sh)"
# shellcheck disable=SC1091
source "$P/git.env"
: "${PERSONAL_NAME:?}" "${PERSONAL_EMAIL:?}" "${PERSONAL_KEY:?}" "${PERSONAL_GH_USER:?}"
: "${WORK_NAME:?}" "${WORK_EMAIL:?}" "${WORK_KEY:?}" "${WORK_GH_USER:?}"
[[ -f "$HOME/.ssh/$PERSONAL_KEY" && -f "$HOME/.ssh/$WORK_KEY" ]] || die "SSH keys missing in ~/.ssh"

fill() { # template -> stdout, replacing @VAR@ with the shell variable of that name
  local s; s="$(cat "$1")"
  for v in PERSONAL_NAME PERSONAL_EMAIL PERSONAL_KEY WORK_NAME WORK_EMAIL WORK_KEY; do
    s="${s//@$v@/${!v}}"
  done
  printf '%s\n' "${s//@INCLUDES@/$INCLUDES}"
}

INCLUDES=""
while read -r d; do
  d="${d/#\~/$HOME}"; d="${d%/}"
  INCLUDES+=$'\n'"[includeIf \"gitdir:$d/\"]"$'\n'$'\t'"path = ~/.gitconfig-work"
done < <(read_list "$P/work-dirs.txt")

for f in .gitconfig .gitconfig-work; do
  [[ -f "$HOME/$f" && ! -f "$HOME/$f.bak-k" ]] && run cp -a "$HOME/$f" "$HOME/$f.bak-k"
done
if ((CHECK_ONLY)); then log "would write ~/.gitconfig and ~/.gitconfig-work"
else
  fill "$REPO_DIR/config/gitconfig.template" >"$HOME/.gitconfig"
  fill "$REPO_DIR/config/gitconfig-work.template" >"$HOME/.gitconfig-work"
fi

# Rewrite remotes that use the old SSH host alias (worktrees share the main repo config).
if [[ -n "${OLD_SSH_ALIAS:-}" ]]; then
  while read -r d; do
    d="${d/#\~/$HOME}"
    while IFS= read -r -d '' g; do
      r="$(dirname "$g")"
      while read -r name url; do
        [[ "$url" == *"@$OLD_SSH_ALIAS:"* ]] || continue
        run git -C "$r" remote set-url "$name" "${url/@$OLD_SSH_ALIAS:/@github.com:}"
      done < <(git -C "$r" remote -v | awk '$3=="(fetch)"{print $1, $2}')
    done < <(find "$d" -maxdepth 6 -name .git -type d -not -path '*/node_modules/*' -print0)
  done < <(read_list "$P/work-dirs.txt")
fi

add_block "$HOME/.bashrc" gh-accounts "ghp() { gh auth switch --hostname github.com --user $PERSONAL_GH_USER; }
ghw() { gh auth switch --hostname github.com --user $WORK_GH_USER; }"

# gh logins need a browser; the owner runs them.
for u in "$PERSONAL_GH_USER" "$WORK_GH_USER"; do
  gh auth status --hostname github.com 2>&1 | matches "account $u" ||
    echo "LOGIN-NEEDED gh $u:  gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web"
done

# Checks
((CHECK_ONLY)) && exit 0
rc=0
ssh_user() { ssh -F /dev/null -i "$HOME/.ssh/$1" -o IdentitiesOnly=yes -o BatchMode=yes -T git@github.com 2>&1 | sed -nE 's/^Hi ([^!]+)!.*/\1/p'; }
[[ "$(ssh_user "$PERSONAL_KEY")" == "$PERSONAL_GH_USER" ]] || { warn "personal SSH key does not authenticate as $PERSONAL_GH_USER"; rc=1; }
[[ "$(ssh_user "$WORK_KEY")" == "$WORK_GH_USER" ]] || { warn "work SSH key does not authenticate as $WORK_GH_USER"; rc=1; }
first_work_repo="$(read_list "$P/work-dirs.txt" | head -1)"; first_work_repo="${first_work_repo/#\~/$HOME}"
r="$(find "$first_work_repo" -maxdepth 4 -name .git -not -path '*/node_modules/*' -printf '%h\n' 2>/dev/null | head -1)"
if [[ -n "$r" ]]; then
  [[ "$(git -C "$r" config user.email)" == "$WORK_EMAIL" ]] || { warn "work identity not applied in $r"; rc=1; }
fi
[[ "$(git -C "$HOME" config user.email 2>/dev/null || git config --global user.email)" == "$PERSONAL_EMAIL" ]] || { warn "personal identity is not the default"; rc=1; }
((rc == 0)) || die "git checks failed"
mark_done
log "git identities PASS. Next: scripts/90-verify.sh"
