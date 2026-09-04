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
- `nc` for Chrome bridge readiness checks
- `tunnel-client` installed at `/usr/local/bin/tunnel-client`, or
  `TUNNEL_CLIENT_BIN` pointing to it
- existing tunnel-client profiles named `chrome-browser-mcp`,
  `chrome-browser-mcp-2`, `chrome-browser-mcp-3`, and `playwright`
- dedicated tunnel-client profiles named `chatgpt-chat-skills-mcp`,
  `chatgpt-chat-skills-mcp-2`, and `chatgpt-chat-skills-mcp-3`
- Node.js with `npx` available to tunnel-client
- the Chrome Browser MCP extension/native bridge for Chrome commands
- the installed Chrome topology at
  `$HOME/Library/Application Support/Chrome Browser MCP/instances.json`
  (created by Chrome Browser MCP's `npm run install:mac`), or an explicit
  `CHROME_MCP_INSTANCES_FILE` override
- a built checkout of `chatgpt-chat-skills-mcp` (Node.js 20 or newer)

### Control-plane API key

The launcher reads one shared control-plane API key from the macOS Keychain
when it starts a tunnel. This matches the existing single-profile setup and
supports the profile references `CONTROL_PLANE_API_KEY`,
`CONTROL_PLANE_API_KEY_2`, `CONTROL_PLANE_API_KEY_AGENT`, and the legacy
`CONTROL_PLANE_API_KEY_ACCT2` name.

Store or update the key once (the command prompts for the value):

```zsh
security add-generic-password -U \
  -a "$USER" \
  -s "CONTROL_PLANE_OPENAI_API_KEY" \
  -w
```

No separate OpenAI tunnel token is needed for each profile. Each tunnel still
needs its own unique tunnel ID, while all six routes can use this one API key.
The launcher also accepts an already-exported alias and verifies that multiple
aliases do not contain conflicting values. Override the Keychain lookup with
`MCP_LAUNCHER_KEYCHAIN_SERVICE`, `MCP_LAUNCHER_KEYCHAIN_ACCOUNT`, or
`MCP_LAUNCHER_SECURITY_BIN` when needed.

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
mcp-chrome                   # Chrome MCP (profile 1, :2091)
mcp-chrome2                  # Chrome MCP 2 (profile 2, :2093)
mcp-chrome3                  # Chrome MCP 3 (agent profile, :2095)
mcp-playwright-head          # Playwright with a visible browser
mcp-playwright-headless      # Playwright in the background
mcp-playwright               # backward-compatible headless alias
mcp-skills                   # Skills loopback server + tunnel
mcp-skills2                  # only the second Skills tunnel (shared server)
mcp-skills3                  # only the agent Skills tunnel (shared server)
mcps both                    # Chrome + headless Playwright (backward compatible)
mcps all                     # all three Chrome tunnels + Playwright + Skills

mcps status
mcps stop chrome
mcps stop chrome2
mcps stop chrome3
mcps stop playwright
mcps stop skills
mcps stop both
mcps stop all

mcps restart chrome
mcps restart chrome2
mcps restart chrome3
mcps restart playwright-head
mcps restart playwright-headless
mcps restart skills
mcps restart both
mcps restart all

mcps logs chrome
mcps logs chrome2
mcps logs chrome3
mcps logs playwright
mcps logs skills
```

Status distinguishes the active Playwright mode:

```text
Chrome MCP: stopped
Chrome MCP 2: stopped
Chrome MCP 3: stopped
Playwright MCP: running (headed, PID 12345)
Skills MCP server: running (PID 12346)
Skills MCP (current): running (PID 12347)
Skills MCP (new subscription): running (PID 12348)
Skills MCP (agent): running (PID 12349)
Skills MCP: running (server PID 12346, 3 tunnels)
```

Chrome status checks both the tunnel process and its configured local bridge.
If the tunnel is alive but Chrome has stopped listening, status reports the
degraded route explicitly instead of claiming that Chrome MCP is usable:

```text
Chrome MCP: tunnel running, upstream stopped (127.0.0.1:2091)
```

## Configure Chrome MCP

The launcher expects the Chrome Browser MCP extension/native bridge from its
repository. Run its `npm run install:mac` after every checkout update so the
native hosts and launcher topology file are current. Load exactly one matching
extension flavor in each Chrome profile.
The fixed bridge mapping is current `:2091`, subscription `:2093`, and agent
`:2095`, each with its own tunnel profile:

```zsh
tunnel-client init \
  --profile chrome-browser-mcp-2 \
  --tunnel-id '<second-tunnel-id>' \
  --mcp-server-url http://127.0.0.1:2093/mcp \
  --control-plane-api-key-ref env:CONTROL_PLANE_API_KEY_2

tunnel-client init \
  --profile chrome-browser-mcp-3 \
  --tunnel-id '<agent-tunnel-id>' \
  --mcp-server-url http://127.0.0.1:2095/mcp \
  --control-plane-api-key-ref env:CONTROL_PLANE_API_KEY_AGENT
```

`mcps all` then starts all three Chrome tunnels together; the launcher checks
each named profile before starting it. Set `CHROME_MCP_INSTANCES_FILE` only when
the topology was installed somewhere other than the default path. Each Chrome
profile must keep exactly one matching extension flavor enabled so tabs never
cross accounts.

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
  --mcp-server-url http://127.0.0.1:2092/mcp \
  --control-plane-api-key-ref env:CONTROL_PLANE_API_KEY

tunnel-client init \
  --profile chatgpt-chat-skills-mcp-2 \
  --tunnel-id '<second-tunnel-id>' \
  --mcp-server-url http://127.0.0.1:2092/mcp \
  --control-plane-api-key-ref env:CONTROL_PLANE_API_KEY_2

tunnel-client init \
  --profile chatgpt-chat-skills-mcp-3 \
  --tunnel-id '<agent-tunnel-id>' \
  --mcp-server-url http://127.0.0.1:2092/mcp \
  --control-plane-api-key-ref env:CONTROL_PLANE_API_KEY_AGENT
```

All three clients use the same stateless Skills service on `:2092`; only the
tunnel identity and runtime-key reference differ. The launcher supplies the
loopback MCP URL at runtime and removes an ambient `CONTROL_PLANE_TUNNEL_ID`
override, so each selected profile remains the source of tunnel identity. It
never prints profile contents or credentials.

## Runtime files

The launcher stores operator state under
`$HOME/.local/state/mcp-launcher/`:

- `chrome.pid`, `chrome2.pid`, `chrome3.pid`, `playwright.pid`,
  `skills.pid`, `skills2.pid`, `skills3.pid`, and `skills-server.pid`
- matching per-process `.log` and health URL files
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
prevention, topology-file loading, three Chrome routes, three Skills routes, installer
backups/idempotency, repository hygiene, and whitespace errors.

## Troubleshooting

### A command is not found

Confirm `$HOME/.local/bin` is already on `PATH`:

```zsh
print -r -- $path
```

The installer deliberately does not edit shell configuration.

### Chrome MCP is not ready

Open Google Chrome and enable the matching Chrome Browser MCP extension. The
local bridge must listen on `127.0.0.1:2091`, `:2093`, or `:2095` before its
tunnel starts. If a profile is missing, create it with the exact instance
mapping above; do not repoint a profile to another port.

### Playwright fails to start

Inspect:

```zsh
mcps status
mcps logs playwright
tunnel-client doctor --profile playwright --explain
```

The launcher removes only `CONTROL_PLANE_TUNNEL_ID` from the child environment
so an ambient override cannot replace the tunnel ID stored in the selected
profile. It resolves the shared API key immediately before each tunnel child
starts and never prints configuration values or credentials.

### Spotify asks for login again

Stop Playwright, run `mcp-playwright-head`, and confirm the visible browser was
started with the expected local profile. Authenticate there, then run
`mcp-playwright-headless` again.
