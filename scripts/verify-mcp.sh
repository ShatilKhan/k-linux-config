#!/usr/bin/env bash
# Check MCP servers against the private list ~/.config/k-migration/mcp-expected.txt.
# Line format (tab-separated):  user|project  <dir or ->  <server name>
# `claude mcp list` health-checks every server (it starts stdio servers and calls
# initialize), so its status is the install check for both stdio and HTTP servers.
source "$(dirname "$0")/lib.sh"
EXP="${MCP_EXPECTED:-$HOME/.config/k-migration/mcp-expected.txt}"
[[ -f "$EXP" ]] || die "missing $EXP"
command -v claude >/dev/null || die "claude not installed"

declare -A cache
status_of() { # dir name
  local dir="$1" name="$2" line
  if [[ -z "${cache[$dir]+x}" ]]; then
    cache[$dir]="$(cd "$dir" && timeout 180 claude mcp list 2>/dev/null)"
  fi
  line="$(grep -F -- "$name: " <<<"${cache[$dir]}" | head -1)"
  case "$line" in
    "") echo MISSING ;;
    *Connected*) echo PASS ;;
    *"Needs authentication"*) echo LOGIN-NEEDED ;;
    *) echo FAIL ;;
  esac
}

rc=0
report ""; report "## MCP servers"; report "| status | scope | dir | server |"; report "|---|---|---|---|"
while IFS=$'\t' read -r scope dir name; do
  [[ "$dir" == "-" ]] && dir="$HOME"; dir="${dir/#\~/$HOME}"
  [[ -d "$dir" ]] || { printf 'FAIL %-8s %s (dir missing)\n' "$scope" "$name"; rc=1; continue; }
  st="$(status_of "$dir" "$name")"
  printf '%-12s %-8s %-28s %s\n' "$st" "$scope" "$name" "${dir/#$HOME/\~}"
  report "| $st | $scope | ${dir/#$HOME/\~} | $name |"
  [[ "$st" == PASS || "$st" == LOGIN-NEEDED ]] || rc=1
done < <(read_list "$EXP")
((rc == 0)) && log "MCP: all expected servers present (log in to any LOGIN-NEEDED ones)" || warn "MCP: some servers missing or failing"
exit $rc
