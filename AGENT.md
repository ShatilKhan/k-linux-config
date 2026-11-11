# Instructions for the Claude Code session

You set up this laptop. The owner installed Ubuntu 26.04 (see `docs/install.md`) and ran
`bootstrap.sh`. It cloned this repo to `~/k-linux-config` and ran `00-preflight`, `10-migrate`,
and `15-secure` before starting you.

## Where to start

1. List `~/.local/state/k-setup/`. A `<script>.done` file means that script passed all its checks.
   A `<script>.log` file holds the output of its last run, including runs the owner made in
   another terminal.
2. Continue with the first script in the `README.md` order that has no `.done` file.
3. If `00-preflight`, `10-migrate`, or `15-secure` has no `.done` file, stop. Ask the owner to run
   `bootstrap.sh` again. Do not copy `~/.claude` or `~/.claude.json` while you are running.

## sudo

`sudo` cannot ask for a password in your Bash tool, and there is no passwordless sudo.
- Scripts that use sudo: `20-apps`, `30-gpu`, `35-net-check --hold`, `40-docker`, `50-mise-tools`,
  `90-verify`. For these:
  1. Run the script with `--check` yourself and show the owner what it will change.
  2. Ask the owner to run it in a terminal: `cd ~/k-linux-config && scripts/NN-name.sh`.
  3. When the owner says it finished, read `~/.local/state/k-setup/NN-name.log` and check for
     `NN-name.done`. On a FAIL, find the cause, fix it, and ask for a rerun.
- Scripts with no sudo: `60-agents`, `65-executor`, `70-git`. Run these yourself.
- Any other command that needs sudo: give the owner the exact command to run.

## Rules

1. Run the scripts in the order in `README.md`. Run one script at a time.
2. Before each script, run it with `--check`. Show the owner what it will change.
3. Run the script (or have the owner run it, see "sudo"). Read its output or log. Each script
   checks its own installs at the end.
4. If a script reports FAIL, stop. Find the cause, fix it, and run the script again.
   Do not continue to the next script with a FAIL.
5. Never print, read, or copy the contents of secret files: `~/.ssh/*`, `*.env`,
   `~/.config/k-migration/git.env`, token files, or keyrings. Names and permissions only.
6. Never write private names (repos, orgs, clients, people, emails) into this repo.
   The pre-commit hook blocks them. Do not bypass it.
7. Never format, repartition, or write to the old disk. The scripts mount it read-only.
8. Logins need the owner. When a check says LOGIN-NEEDED, give the owner the exact command.
9. A reboot or log-out is needed after `30-gpu.sh` and after `40-docker.sh`. Tell the owner to
   do it, then to run `claude --continue` in `~/k-linux-config`. Then start again at "Where to start".

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
