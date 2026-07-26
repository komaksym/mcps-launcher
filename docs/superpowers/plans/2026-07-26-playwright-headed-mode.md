# Playwright MCP Headed Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish a tested macOS launcher that switches one Playwright MCP tunnel between explicit headed and headless modes while sharing one persistent Spotify browser profile.

**Architecture:** A dependency-free zsh launcher owns process lifecycle, dispatch, mode state, logs, and command construction. A separate installer backs up and installs the launcher plus aliases. Tests inject a fake tunnel-client and temporary filesystem roots so every lifecycle behavior is deterministic before the installed launcher is exercised live.

**Tech Stack:** zsh, standard macOS command-line tools, tunnel-client, `npx @playwright/mcp`, Git, GitHub CLI

## Global Constraints

- Commands are exactly `mcps`, `mcp-chrome`, `mcp-playwright`, `mcp-playwright-head`, and `mcp-playwright-headless`.
- `mcp-playwright` remains a backward-compatible headless alias.
- Both Playwright modes use `$HOME/.playwright-spotify`.
- Only one Playwright mode may run at a time.
- Chrome MCP behavior remains unchanged.
- No production dependencies.
- Never commit or print tunnel IDs, API keys, tunnel profiles, logs, PID files, mode files, or browser profile data.
- The GitHub repository is private and named `mcps-launcher`.

---

## File map

- `bin/mcps`: command dispatch, menu, process ownership checks, mode switching, logs, status, and tunnel-client invocation.
- `install.sh`: isolated, timestamped, idempotent installation into a configurable bin directory.
- `tests/helpers.zsh`: assertions, temporary sandbox creation, fake process cleanup, and launcher execution helpers.
- `tests/fake-tunnel-client`: test double that records arguments, writes requested PID/health files, traps termination, and stays alive.
- `tests/test_mcps.zsh`: launcher behavior and regression tests.
- `tests/test_install.zsh`: installer backup, symlink, and idempotency tests.
- `scripts/check.zsh`: syntax, test, and repository hygiene checks.
- `.gitignore`: runtime/build exclusions.
- `README.md`: installation, usage, Spotify authentication, safety, and troubleshooting.

### Task 1: Launcher mode lifecycle

**Files:**
- Create: `tests/helpers.zsh`
- Create: `tests/fake-tunnel-client`
- Create: `tests/test_mcps.zsh`
- Create: `bin/mcps`

**Interfaces:**
- Consumes: environment overrides `MCP_LAUNCHER_STATE_DIR`, `TUNNEL_CLIENT_PROFILE_DIR`, `TUNNEL_CLIENT_BIN`, `MCP_LAUNCHER_STARTUP_WAIT`, `MCP_LAUNCHER_SKIP_CHROME_OPEN`, and `PLAYWRIGHT_MCP_USER_DATA_DIR`.
- Produces: `mcps [chrome|playwright|playwright-head|playwright-headless|both|status|stop TARGET|restart TARGET|logs TARGET]` plus basename dispatch for all installed aliases.

- [ ] **Step 1: Write the failing command-generation and alias tests**

Add tests that invoke symlinks named `mcp-playwright-head`,
`mcp-playwright-headless`, and `mcp-playwright`, then read only the fake
tunnel-client argument log:

```zsh
assert_contains "$headed_args" "@playwright/mcp@latest"
assert_contains "$headed_args" "--user-data-dir=$sandbox/.playwright-spotify"
assert_not_contains "$headed_args" "--headless"
assert_contains "$headless_args" "--headless"
assert_contains "$headless_args" "--user-data-dir=$sandbox/.playwright-spotify"
assert_eq "$legacy_args" "$headless_args"
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `zsh tests/test_mcps.zsh command_generation`

Expected: FAIL because `bin/mcps` and the new aliases do not exist.

- [ ] **Step 3: Implement minimal dispatch and command construction**

In `bin/mcps`, define:

```zsh
playwright_command() {
  local mode=$1
  local -a args=(npx -y @playwright/mcp@latest)
  [[ $mode == headless ]] && args+=(--headless)
  args+=("--user-data-dir=$PLAYWRIGHT_USER_DATA_DIR")
  print -r -- "${(q)args}"
}
```

Map `mcp-playwright-head` to `start_playwright headed`, and map both
`mcp-playwright` and `mcp-playwright-headless` to
`start_playwright headless`. Pass the generated string using
`--mcp.command`.

- [ ] **Step 4: Run the focused test and verify GREEN**

Run: `zsh tests/test_mcps.zsh command_generation`

Expected: PASS with separate headed/headless argument records and the same
profile path.

- [ ] **Step 5: Write failing lifecycle tests**

Cover:

```zsh
assert_eq "$(count_fake_processes)" "1"
assert_contains "$(run_launcher status)" "Playwright MCP: running (headed"
run_launcher playwright-headless
assert_eq "$(count_fake_processes)" "1"
assert_contains "$(run_launcher status)" "Playwright MCP: running (headless"
run_launcher playwright-headless
assert_eq "$(fake_start_count)" "2"
run_launcher stop playwright
assert_contains "$(run_launcher status)" "Playwright MCP: stopped"
```

Also create malformed and dead PID files and assert they are removed without
signalling an unrelated live PID.

- [ ] **Step 6: Run lifecycle tests and verify RED**

Run: `zsh tests/test_mcps.zsh lifecycle`

Expected: FAIL because mode switching, mode status, and stale-state cleanup are
not implemented.

- [ ] **Step 7: Implement minimal lifecycle behavior**

Add:

```zsh
mode_file() { print -r -- "$STATE_DIR/playwright.mode"; }
read_mode() { [[ -f $(mode_file) ]] && IFS= read -r REPLY < "$(mode_file)" && [[ $REPLY == headed || $REPLY == headless ]] && print -r -- "$REPLY"; }
```

Validate a recorded PID with `kill -0` plus the process command containing
both `tunnel-client` and the expected profile. For Playwright, compare the
requested mode with the recorded mode. A same-mode start is a no-op; an
opposite-mode start calls the bounded Playwright stop before launch. Write the
mode file only after successful startup, and clear it on stop or failed
startup.

- [ ] **Step 8: Run lifecycle tests and verify GREEN**

Run: `zsh tests/test_mcps.zsh lifecycle`

Expected: PASS for duplicate prevention, switching, status, stop, and stale
state.

- [ ] **Step 9: Add menu, Chrome, logs, and invalid-input regression tests**

Assert bare `mcps` prints headed and headless menu entries without starting a
process; `mcps both` starts Chrome plus headless Playwright; Chrome still
checks port 2091 unless bypassed for tests; log files exist; invalid targets
exit 2.

- [ ] **Step 10: Run the complete launcher suite and keep it GREEN**

Run: `zsh tests/test_mcps.zsh`

Expected: PASS for every named case with no leftover fake process.

- [ ] **Step 11: Commit**

```bash
git add bin/mcps tests/helpers.zsh tests/fake-tunnel-client tests/test_mcps.zsh
git commit -m "feat: add Playwright modes" \
  -m "Add explicit headed and headless aliases, shared persistent profile command construction, safe single-process switching, mode-aware status, and lifecycle regression coverage."
```

### Task 2: Safe installer

**Files:**
- Create: `tests/test_install.zsh`
- Create: `install.sh`

**Interfaces:**
- Consumes: repository `bin/mcps`; optional `MCP_LAUNCHER_INSTALL_BIN_DIR`.
- Produces: executable `mcps` and four relative symlinks in the target bin directory.

- [ ] **Step 1: Write the failing installer test**

In a temporary bin directory, pre-create an unrelated `mcps` file and assert:

```zsh
assert_file "$bin_dir/mcps.backup-$timestamp"
assert_executable "$bin_dir/mcps"
assert_link_target "$bin_dir/mcp-chrome" "mcps"
assert_link_target "$bin_dir/mcp-playwright" "mcps"
assert_link_target "$bin_dir/mcp-playwright-head" "mcps"
assert_link_target "$bin_dir/mcp-playwright-headless" "mcps"
```

Run the installer twice and assert the second run leaves the correct install
intact without backing up its own identical managed files.

- [ ] **Step 2: Run installer tests and verify RED**

Run: `zsh tests/test_install.zsh`

Expected: FAIL because `install.sh` does not exist.

- [ ] **Step 3: Implement the minimal installer**

Resolve the repository root from `${0:A:h}`, create the target directory,
compare existing regular files before replacement, back up conflicting paths
with `YYYYMMDD-HHMMSS` suffixes, install `bin/mcps` with mode `0755`, and
create relative aliases using `ln -s mcps`.

- [ ] **Step 4: Run installer tests and verify GREEN**

Run: `zsh tests/test_install.zsh`

Expected: PASS for backups, executable mode, all aliases, and idempotency.

- [ ] **Step 5: Commit**

```bash
git add install.sh tests/test_install.zsh
git commit -m "feat: add safe installer" \
  -m "Install the tracked launcher and aliases idempotently while preserving conflicting local files with timestamped backups."
```

### Task 3: Documentation and automated checks

**Files:**
- Create: `README.md`
- Create: `.gitignore`
- Create: `scripts/check.zsh`
- Modify: `PLANS.md`

**Interfaces:**
- Consumes: commands and installer from Tasks 1–2.
- Produces: `zsh scripts/check.zsh` as the single local validation entry point.

- [ ] **Step 1: Write the check script before documentation**

The script must run:

```zsh
zsh -n bin/mcps install.sh tests/helpers.zsh tests/test_mcps.zsh tests/test_install.zsh scripts/check.zsh
zsh tests/test_mcps.zsh
zsh tests/test_install.zsh
git diff --check
```

It must also fail if tracked files contain credential-shaped assignments or
runtime paths such as `.playwright-spotify`, except for documented literal
path references.

- [ ] **Step 2: Run checks and verify the documentation gate fails**

Run: `zsh scripts/check.zsh`

Expected: FAIL because required README sections are absent.

- [ ] **Step 3: Write the README and ignore rules**

Document exact installation and authentication:

```zsh
./install.sh
mcp-playwright-head
# Sign in to Spotify in the visible Playwright browser.
mcps stop playwright
mcp-playwright-headless
```

Explain shared browser state, the legacy alias, Chrome prerequisites, status,
logs, stop/restart commands, local file locations, and that browser state and
tunnel profiles are never stored in the repository. Ignore test scratch,
runtime logs, PID/health/mode files, and OS metadata.

- [ ] **Step 4: Run all checks and verify GREEN**

Run: `zsh scripts/check.zsh`

Expected: syntax, launcher tests, installer tests, diff check, documentation
gate, and hygiene audit all pass.

- [ ] **Step 5: Mark implementation milestones complete and commit**

```bash
git add README.md .gitignore scripts/check.zsh PLANS.md
git commit -m "docs: add launcher operations" \
  -m "Document installation, Spotify authentication, mode switching, runtime state, troubleshooting, and the complete local validation command."
```

### Task 4: Local installation and live verification

**Files:**
- Installed copy: `$HOME/.local/bin/mcps`
- Installed links: `$HOME/.local/bin/mcp-chrome`
- Installed links: `$HOME/.local/bin/mcp-playwright`
- Installed links: `$HOME/.local/bin/mcp-playwright-head`
- Installed links: `$HOME/.local/bin/mcp-playwright-headless`

**Interfaces:**
- Consumes: verified repository and existing `chrome-browser-mcp`/`playwright` tunnel profiles.
- Produces: working local commands and live evidence for both Playwright modes.

- [ ] **Step 1: Re-run repository checks**

Run: `zsh scripts/check.zsh`

Expected: PASS before touching the installed launcher.

- [ ] **Step 2: Inspect profiles without exposing values**

Run `tunnel-client doctor --profile chrome-browser-mcp --explain` and
`tunnel-client doctor --profile playwright --explain`. Record only PASS/FAIL
check names and the detected MCP command shape; never print keys or complete
profile contents.

- [ ] **Step 3: Install the verified launcher**

Run: `./install.sh`

Expected: timestamped backup of a conflicting prior `mcps`, five installed
commands, and no profile changes.

- [ ] **Step 4: Verify fresh-shell resolution**

Run:

```zsh
/bin/zsh -lic 'whence -p mcps mcp-chrome mcp-playwright mcp-playwright-head mcp-playwright-headless'
```

Expected: all commands resolve under `$HOME/.local/bin`.

- [ ] **Step 5: Start headed Playwright**

Run: `mcp-playwright-head`

Expected: tunnel-client becomes ready, its child Playwright command omits
`--headless`, includes the shared user-data directory, and a visible browser
window opens. Leave authentication to the user if Spotify prompts for it.

- [ ] **Step 6: Verify mode status and duplicate prevention**

Run `mcps status`, then `mcp-playwright-head` again.

Expected: status says headed and the second start reports the existing PID
without creating another tunnel process.

- [ ] **Step 7: Switch to headless**

Run: `mcp-playwright-headless`

Expected: the headed tunnel stops, exactly one replacement tunnel becomes
ready, the child command includes `--headless`, and it uses the identical
user-data directory.

- [ ] **Step 8: Verify stop and cleanup**

Run: `mcps stop playwright`, then `mcps status`.

Expected: Playwright is stopped and PID, health, and mode state are absent.

- [ ] **Step 9: Run final verification**

Run:

```zsh
zsh scripts/check.zsh
git status --short
git log --oneline --decorate -5
```

Expected: all checks pass and only intentional plan milestone updates remain.

### Task 5: Private GitHub publication

**Files:**
- Modify: `PLANS.md`

**Interfaces:**
- Consumes: clean verified local `main` branch.
- Produces: private `komaksym/mcps-launcher` repository with `main` pushed.

- [ ] **Step 1: Confirm GitHub authentication**

Run: `gh auth status`

Expected: authenticated account is `komaksym`.

- [ ] **Step 2: Mark all milestones complete**

Change every milestone in `PLANS.md` to `[x]`, run
`zsh scripts/check.zsh`, and commit:

```bash
git add PLANS.md
git commit -m "chore: complete launcher rollout" \
  -m "Record successful automated checks, local installation, headed/headless live verification, cleanup, and publication readiness."
```

- [ ] **Step 3: Create the private repository**

Run:

```bash
gh repo create mcps-launcher --private --source=. --remote=origin --push
```

Expected: private GitHub repository created, `origin` added, and `main`
published.

- [ ] **Step 4: Verify the remote**

Run:

```bash
git status --short --branch
git ls-remote --heads origin main
gh repo view komaksym/mcps-launcher --json url,visibility,defaultBranchRef
```

Expected: clean branch tracking `origin/main`, matching local/remote commit,
visibility `PRIVATE`, and default branch `main`.

