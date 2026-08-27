# MCPs Launcher

A small macOS/zsh launcher for Chrome, Playwright, and ChatGPT Skills MCP
tunnels. It adds explicit visible and background Playwright modes while
preserving the same persistent browser profile between them, and manages the
Skills loopback server together with its tunnel.

## Why two Playwright modes?

Spotify authentication needs a visible browser. Normal MCP use is usually more
convenient in the background. Both commands point Playwright at
`$HOME/.playwright-spotify`, so the browser state created during a visible
login is reused later:

```mermaid
flowchart LR
    A["mcp-playwright-head"] --> B["Visible Playwright browser"]
    B --> C["Authenticate with Spotify"]
    C --> D["$HOME/.playwright-spotify"]
    D --> E["mcp-playwright-headless"]
    E --> F["Background Playwright MCP"]
```

The browser profile is local runtime data. It is never copied into this
repository.

## Requirements

- macOS with zsh
- `curl` for Skills server readiness checks
- `tunnel-client` installed at `/usr/local/bin/tunnel-client`, or
  `TUNNEL_CLIENT_BIN` pointing to it
- existing tunnel-client profiles named `chrome-browser-mcp` and `playwright`
- a dedicated tunnel-client profile named `chatgpt-chat-skills-mcp`
- Node.js with `npx` available to tunnel-client
- the Chrome Browser MCP extension/native bridge for Chrome commands
- a built checkout of `chatgpt-chat-skills-mcp` (Node.js 20 or newer)

## Install

```zsh
./install.sh
```

The installer writes to `$HOME/.local/bin` by default. It creates timestamped
backups before replacing conflicting files or links and does not modify
`.zshrc` or any tunnel profile.

To test an isolated installation directory:

```zsh
MCP_LAUNCHER_INSTALL_BIN_DIR=/tmp/mcps-bin ./install.sh
```

## Authenticate Spotify

Start Playwright with a visible browser:

```zsh
mcp-playwright-head
```

Open Spotify in that Playwright browser and sign in yourself. Do not put
credentials in this repository or launcher configuration. When authentication
is complete, switch to the background mode:

```zsh
mcp-playwright-headless
```

Starting the opposite mode automatically stops the currently running
Playwright tunnel before starting its replacement. Only one Playwright tunnel
is allowed at a time.

## Commands

```zsh
mcps                         # interactive menu; starts nothing by itself
mcp-chrome                   # Chrome MCP only
mcp-playwright-head          # Playwright with a visible browser
mcp-playwright-headless      # Playwright in the background
mcp-playwright               # backward-compatible headless alias
mcp-skills                   # Skills loopback server + tunnel
mcps all                     # Chrome + headless Playwright + Skills
mcps both                    # backward-compatible alias for all

mcps status
mcps stop chrome
mcps stop playwright
mcps stop skills
mcps stop all

mcps restart chrome
mcps restart playwright-head
mcps restart playwright-headless
mcps restart skills
mcps restart all

mcps logs chrome
mcps logs playwright
mcps logs skills
```

Status distinguishes the active Playwright mode:

```text
Chrome MCP: stopped
Playwright MCP: running (headed, PID 12345)
Skills MCP: running (server PID 12346, tunnel PID 12347)
```

## Configure Skills MCP

Build the Skills service first:

```zsh
cd /path/to/chatgpt-chat-skills-mcp
npm install
npm run build
```

The launcher defaults to
`$HOME/.local/share/chatgpt-chat-skills-mcp/dist/main.js`. Either place or link
the checkout there, or set `SKILLS_MCP_SERVER_ENTRY` to the absolute built
entry point. `SKILLS_MCP_NODE_BIN` can select a specific Node.js executable,
and `SKILLS_MCP_PORT` overrides the loopback port `2092`.

Create the dedicated machine-local profile with the tunnel ID from the OpenAI
tunnel settings. Keep the runtime API key in your local environment; do not put
it in this repository or shell history.

```zsh
tunnel-client init \
  --profile chatgpt-chat-skills-mcp \
  --tunnel-id '<tunnel-id>' \
  --mcp-server-url http://127.0.0.1:2092/mcp
```

The launcher supplies the loopback MCP URL at runtime and removes an ambient
`CONTROL_PLANE_TUNNEL_ID` override, so the selected profile remains the source
of tunnel identity. It never prints profile contents or credentials.

## Runtime files

The launcher stores operator state under
`$HOME/.local/state/mcp-launcher/`:

- `chrome.pid`, `playwright.pid`, `skills.pid`, and `skills-server.pid`
- `chrome.log`, `playwright.log`, `skills.log`, and `skills-server.log`
- per-process health URL files
- `playwright.mode`

Tunnel configuration remains under `$HOME/.config/tunnel-client/`. The
persistent Playwright browser profile remains at `$HOME/.playwright-spotify`.
None of these machine-specific files belong in Git.

## Validation

Run the complete dependency-free check:

```zsh
zsh scripts/check.zsh
```

This checks zsh syntax, launcher lifecycle, mode switching, duplicate
prevention, Chrome regression behavior, installer backups/idempotency,
repository hygiene, and whitespace errors.

## Troubleshooting

### A command is not found

Confirm `$HOME/.local/bin` is already on `PATH`:

```zsh
print -r -- $path
```

The installer deliberately does not edit shell configuration.

### Chrome MCP is not ready

Open Google Chrome and enable the Chrome Browser MCP extension. The local
bridge must listen on `127.0.0.1:2091` before its tunnel starts.

### Playwright fails to start

Inspect:

```zsh
mcps status
mcps logs playwright
tunnel-client doctor --profile playwright --explain
```

The launcher removes only `CONTROL_PLANE_TUNNEL_ID` from the child environment
so an ambient override cannot replace the tunnel ID stored in the selected
profile. It never prints configuration values.

### Spotify asks for login again

Stop Playwright, run `mcp-playwright-head`, and confirm the visible browser was
started with the expected local profile. Authenticate there, then run
`mcp-playwright-headless` again.
