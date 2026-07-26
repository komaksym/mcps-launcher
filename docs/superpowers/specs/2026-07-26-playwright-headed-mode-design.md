# Playwright MCP Headed Mode Design

## Summary

Move the existing macOS MCP launcher from an untracked installed script into a
dedicated `mcps-launcher` repository. Preserve the Chrome launcher and existing
Playwright command while adding explicit headed and headless Playwright
commands that share one persistent browser profile.

## Goals

- Provide `mcp-playwright-head` for interactive authentication in a visible
  browser.
- Provide `mcp-playwright-headless` for normal background operation.
- Preserve `mcp-playwright` as a backward-compatible alias for headless mode.
- Reuse `$HOME/.playwright-spotify` in both modes so a login performed in the
  visible browser remains available in headless sessions.
- Guarantee that only one Playwright tunnel is active at a time.
- Keep existing Chrome MCP behavior unchanged.
- Make the repository the source of truth for installation and future changes.

## Non-goals

- Managing Spotify credentials or automating the Spotify login.
- Committing tunnel-client profiles, tunnel IDs, API keys, logs, PID files, or
  browser profile data.
- Changing the Chrome MCP implementation or tunnel configuration.
- Adding production dependencies.

## Command interface

The installed commands are:

```text
mcps
mcp-chrome
mcp-playwright
mcp-playwright-head
mcp-playwright-headless
```

`mcp-playwright` and `mcp-playwright-headless` both select headless mode.
`mcp-playwright-head` selects headed mode.

The `mcps` command also accepts explicit non-interactive targets:

```text
mcps chrome
mcps playwright
mcps playwright-head
mcps playwright-headless
mcps both
```

The interactive menu exposes separate entries for headed and headless
Playwright startup. Status output reports whether Playwright is stopped,
headed, or headless.

## Architecture

The repository contains:

- `bin/mcps`: the zsh launcher and process lifecycle logic.
- `install.sh`: an idempotent macOS installer that creates timestamped backups
  before replacing installed launcher files or links.
- `tests/`: dependency-free shell tests that run against temporary state,
  profile, and binary directories.
- `README.md`: installation, command, authentication, and troubleshooting
  documentation.

The launcher continues to use the existing `chrome-browser-mcp` and
`playwright` tunnel-client profiles for account-bound tunnel configuration.
For Playwright, it overrides only `mcp.command` at runtime:

```text
headed:
  npx -y @playwright/mcp@latest --user-data-dir=$HOME/.playwright-spotify

headless:
  npx -y @playwright/mcp@latest --headless --user-data-dir=$HOME/.playwright-spotify
```

The shell passes the persistent profile path as a literal command argument
after expanding the user's home directory; it does not source `.zshrc`.

## Mode switching and process state

Chrome and Playwright retain separate PID, health URL, and log files.
Playwright additionally records the selected mode in a small state file only
after the tunnel process has started successfully.

When a Playwright start is requested:

1. If the requested mode is already healthy, report the existing PID and do
   nothing.
2. If the opposite mode is running, terminate it through the existing bounded
   graceful-stop flow.
3. Start tunnel-client with the requested Playwright command.
4. Record the mode after startup succeeds.
5. If startup fails, remove stale PID, health, and mode state and show the tail
   of the Playwright log.

The process check validates both the tunnel-client profile and, for
Playwright, the expected headed/headless command. It never trusts a PID file
alone.

`mcps both` starts Chrome and headless Playwright to preserve the existing
background-oriented behavior.

## Error handling and safety

- Reject unknown commands and modes with exit status 2.
- Refuse to launch when `tunnel-client` is missing or non-executable.
- Preserve Chrome's local bridge readiness check.
- Clean invalid or stale PID and mode files.
- Use bounded graceful termination followed by a targeted forced termination
  only for a PID proven to belong to the expected launcher process.
- Never print environment values or profile contents.
- Quote paths so spaces in `$HOME` and configured directories remain safe.
- The installer changes only the five launcher paths it owns and backs up
  existing non-matching files before replacement.

## Testing

Tests use a fake `tunnel-client` executable and temporary directories. They
must prove:

- bare `mcps` shows the menu and starts nothing;
- every command name dispatches to the expected mode;
- headed command generation omits `--headless`;
- headless command generation includes `--headless`;
- both modes use the same persistent user-data directory;
- duplicate starts in the same mode are prevented;
- switching modes stops the old process before starting the new one;
- status reports the active mode;
- stop and restart behavior works;
- stale and malformed PID/mode state is cleaned safely;
- logs are created;
- Chrome launch behavior remains unchanged;
- installer backups, links, idempotency, and fresh-zsh resolution work.

Validation before release:

1. zsh syntax checks.
2. Focused shell test suite.
3. Installer test in an isolated temporary home.
4. `tunnel-client doctor` for the existing profiles without printing secrets.
5. Live headed Playwright startup and visible browser confirmation.
6. Live headed-to-headless switch using the shared persistent profile.
7. Final diff and credential-pattern audit.

The live authentication itself remains a user action. Completion requires
proving that the headed browser opens with the expected persistent profile and
that the same profile is passed to headless mode.

## Repository and publication

The local repository is named `mcps-launcher`. After validation, create a
private GitHub repository with the same name, commit the complete verified
implementation using a concise subject and detailed commit body, and push the
default branch. The initial repository must contain no machine-specific
account configuration or generated runtime state.

