# Instructions for the Claude Code session

You set up this laptop. The owner already installed Ubuntu 26.04 (see `docs/install.md`)
and cloned this repo to `~/k-linux-config`.

## Rules

1. Run the scripts in the order in `README.md`. Run one script at a time.
2. Before each script, run it with `--check`. Show the owner what it will change.
3. Run the script. Read its output. Each script checks its own installs at the end.
4. If a script reports FAIL, stop. Find the cause, fix it, and run the script again.
   Do not continue to the next script with a FAIL.
5. Never print, read, or copy the contents of secret files: `~/.ssh/*`, `*.env`,
   `~/.config/k-migration/git.env`, token files, or keyrings. Names and permissions only.
6. Never write private names (repos, orgs, clients, people, emails) into this repo.
   The pre-commit hook blocks them. Do not bypass it.
7. Never format, repartition, or write to the old disk. The scripts mount it read-only.
8. Logins need the owner. When a check says LOGIN-NEEDED, give the owner the exact command.
9. A reboot or log-out is needed after `30-gpu.sh` and after `40-docker.sh`. Tell the owner,
   then continue in a new session. Read `~/verify-report.md` and this file again.

## Steps that need the owner

- After `30-gpu.sh`: reboot. Then run `scripts/30-gpu.sh --check`.
- After `35-net-check.sh`: the owner does the manual test list in its output.
- After `40-docker.sh`: log out and in. Start Docker Desktop once. Then run
  `scripts/40-docker.sh --desktop-settings`.
- `20-apps.sh` prints three manual app installs (Claude Desktop, ChatGPT/Codex app, Hubstaff).
- `70-git.sh` prints `gh auth login` commands, one per GitHub account.
- CLI logins: `railway login`, `vercel login`, `aws configure sso` or `aws configure`,
  `codex login`, `infisical login`, `sentry-cli login`.
- MCP servers that show LOGIN-NEEDED: run `/mcp` in Claude Code and log in.
- After `65-executor.sh`: the owner connects accounts in the Executor dashboard (`executor`).
  Remove an old MCP entry only after the owner confirms that service works through Executor.
- After `70-git.sh`: install the herdsman skill if `60-agents.sh` printed LOGIN-NEEDED for it.
- Hubstaff CLI: the owner creates a NEW personal access token at developer.hubstaff.com and puts it in
  `~/.env` as `HUBSTAFF_PERSONAL_ACCESS_TOKEN`. Then run, without printing the token:
  `TOK=$(grep -E '^(export )?HUBSTAFF_PERSONAL_ACCESS_TOKEN=' ~/.env | tail -1 | cut -d= -f2-); hubstaff config set-pat "$TOK" >/dev/null`

## Finish

1. Run `scripts/90-verify.sh`. Show the owner the summary in `~/verify-report.md`.
2. Read `~/migrate-leftovers.txt` with the owner. Each entry needs a decision: copy or drop.
3. Tell the owner that the old partitions can be deleted only if the report says
   **COPY VERIFIED**. Do not delete them yourself.
