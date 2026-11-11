#!/usr/bin/env bash
# Final check. Writes ~/verify-report.md. The old partition may be deleted only when
# the report ends with "COPY VERIFIED".
# Compares the new /home against the old one (mounted read-only): files, git repos,
# worktrees, Claude state; then re-checks every tool, MCP server, plugin and login.
source "$(dirname "$0")/lib.sh"
owner_sudo "$@"
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
mount_old
COPY="$LISTS/copy-list.txt"; SKIP="$LISTS/skip-list.txt"
: >"$REPORT"
report "# Verify report $(date -Is)"; report ""; report "Old home: $OLD_HOME (read-only)"
copy_ok=1

# ---- 1. Files: nothing on the old side is missing or newer on the new side ----
report ""; report "## Files"; report "| path | old files | new files | differences |"; report "|---|---|---|---|"
while read -r p; do
  [[ -e "$OLD_HOME/$p" ]] || continue
  # -u: files changed on the new machine after the copy are not differences.
  diffs="$(copy_diffs "$p")"
  o="$(count "$OLD_HOME/$p" -type f)"; n="$(count "$HOME/$p" -type f)"
  # skip-list entries inside this path lower the expected count, so compare differences only
  report "| $p | $o | $n | $diffs |"
  printf '%-4s files %-40s old=%s new=%s diffs=%s\n' "$([[ $diffs == 0 ]] && echo PASS || echo FAIL)" "$p" "$o" "$n" "$diffs"
  [[ "$diffs" == 0 ]] || copy_ok=0
done < <(read_list "$COPY")

# ---- 2. Git repos and worktrees ----
report ""; report "## Git repositories"; report "| status | repo | note |"; report "|---|---|---|"
export GIT_OPTIONAL_LOCKS=0
while IFS= read -r -d '' g; do
  rel="${g#"$OLD_HOME"/}"; rel="${rel%/.git}"
  # skip repos under skip-list paths
  skip=0; while read -r s; do s="${s#/}"; s="${s%/}"; [[ "$rel" == "$s" || "$rel" == "$s/"* ]] && skip=1; done < <(read_list "$SKIP")
  ((skip)) && continue
  new="$HOME/$rel"; st=PASS; note=""
  if [[ ! -e "$new/.git" ]]; then st=FAIL; note="missing"
  elif ! git -C "$new" fsck --no-dangling --no-progress >/dev/null 2>&1; then st=FAIL; note="fsck failed"
  elif [[ "$(git -C "$OLD_HOME/$rel" -c safe.directory='*' status --porcelain 2>/dev/null)" != "$(git -C "$new" status --porcelain)" ]]; then st=FAIL; note="status differs"
  elif [[ "$(git -C "$OLD_HOME/$rel" -c safe.directory='*' stash list 2>/dev/null)" != "$(git -C "$new" stash list)" ]]; then st=FAIL; note="stash differs"
  fi
  if [[ -d "$new/.git" ]]; then  # main repo: every registered worktree must exist
    while read -r wt; do [[ -d "$wt" ]] || { st=FAIL; note+=" worktree missing: $wt"; }; done \
      < <(git -C "$new" worktree list --porcelain | sed -n 's/^worktree //p')
  fi
  report "| $st | ~/$rel | $note |"; printf '%-4s git   ~/%s %s\n' "$st" "$rel" "$note"
  [[ "$st" == PASS ]] || copy_ok=0
done < <(find "$OLD_HOME/dev" -maxdepth 6 -name .git -not -path '*/node_modules/*' -print0 2>/dev/null)

# ---- 3. Claude and agent state ----
report ""; report "## Agent state"
cnt() { count "$@"; }
set -f   # the find patterns below must not glob-expand
for spec in "projects dirs|.claude/projects|-mindepth 1 -maxdepth 1 -type d" \
            "session files|.claude/projects|-name *.jsonl" \
            "memory dirs|.claude/projects|-type d -name memory" \
            "codex sessions|.codex/sessions|-type f"; do
  IFS='|' read -r label path args <<<"$spec"
  # shellcheck disable=SC2086
  o="$(cnt "$OLD_HOME/$path" $args)"
  # shellcheck disable=SC2086
  n="$(cnt "$HOME/$path" $args)"
  st=PASS; ((n >= o)) || { st=FAIL; copy_ok=0; }
  report "- $st $label: old $o, new $n"; printf '%-4s state %s old=%s new=%s\n' "$st" "$label" "$o" "$n"
done
removed=(-name 'flutter-*' -o -name 'dart-*' -o -name 'playwright-cli')
for sd in .claude/skills .agents/skills; do
  o="$(count "$OLD_HOME/$sd" -mindepth 1 -maxdepth 1 ! \( "${removed[@]}" \))"
  n="$(count "$HOME/$sd" -mindepth 1 -maxdepth 1)"
  left="$(count "$HOME/$sd" -mindepth 1 -maxdepth 1 \( "${removed[@]}" \))"
  # new skills (herdsman, synced ones) may add to the count; removed ones must be gone
  st=PASS; ((n >= o && left == 0)) || { st=FAIL; copy_ok=0; }
  report "- $st skills in ~/$sd: expected at least $o, found $n, removed-but-present $left"
  printf '%-4s skills ~/%s expected>=%s found=%s removed-present=%s\n' "$st" "$sd" "$o" "$n" "$left"
done
set +f

# ---- 4. Tools (every row of tools.tsv) ----
report ""; report "## Tools"; report "| status | tool | version | note |"; report "|---|---|---|---|"
tools_ok=1
while IFS=$'\t' read -r name _; do verify_tool "$name" || tools_ok=0; done < <(tail -n +2 "$TOOLS_TSV")
[[ "$(docker --context default info -f '{{.DockerRootDir}}' 2>/dev/null)" == /home/docker ]] || { warn "Docker data-root is not /home/docker"; tools_ok=0; }
systemctl show ollama -p Environment | matches "OLLAMA_MODELS=$HOME/dev/models" || { warn "Ollama models path"; tools_ok=0; }
dpkg -s claude-desktop >/dev/null 2>&1 || report "- MANUAL-NEEDED: claude-desktop"
# Executor runs all day; revisit (on-demand start) if this goes above ~300 MB.
report "- Executor RAM: $(executor_ram)"; log "Executor RAM: $(executor_ram)"

# ---- 5. MCP servers ----
"$REPO_DIR/scripts/verify-mcp.sh" || tools_ok=0

# ---- 6. Logins (exit codes only; output discarded, tokens never printed) ----
report ""; report "## Logins"
# Checks must never start a login: no stdin, no display or session bus (no browser can open),
# CI mode for CLIs that prompt, and a 20 s limit.
login() { local label="$1"; shift
  if timeout 20 env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS CI=1 BROWSER=true "$@" \
    </dev/null >/dev/null 2>&1; then s=PASS; else s=LOGIN-NEEDED; fi
  printf '%-12s login %s\n' "$s" "$label"; report "- $s $label"; }
login "railway" railway whoami
login "aws" aws sts get-caller-identity
login "codex" codex login status
login "infisical" infisical user get token
login "sentry-cli" sentry-cli info
login "hubstaff" hubstaff users me
gh auth status --hostname github.com 2>&1 | grep -c 'Logged in' | matches '^2$' && login "gh (2 accounts)" true || login "gh (2 accounts)" false

# ---- Summary ----
report ""
if ((copy_ok)); then
  report "**COPY VERIFIED.** Files, git repos, worktrees and agent state match the old home."
  report "You may unmount ($OLD_MNT) and delete the old Linux partitions."
  log "COPY VERIFIED"
else
  report "**COPY NOT VERIFIED.** Do not delete the old partitions. Fix the FAIL rows and run again."
  warn "COPY NOT VERIFIED"
fi
((tools_ok)) && report "Tools and MCP: all PASS." || report "Tools or MCP: some rows FAIL (see above)."
log "report: $REPORT"
((copy_ok && tools_ok)) || exit 1
mark_done
