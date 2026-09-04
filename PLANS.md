# Implementation Milestones

## Summary

Create a repository-backed macOS launcher with explicit headed and headless
Playwright MCP commands, one shared persistent Spotify browser profile, safe
mode switching, repeatable installation, and end-to-end verification.

## Milestones

- [x] Build the launcher lifecycle through failing shell tests.
- [x] Add and test the idempotent installer.
- [x] Document the authentication and operating workflow.
- [x] Install locally and verify real headed/headless tunnel behavior.
- [x] Create the private GitHub repository and push the verified default branch.

Detailed execution steps are in
`docs/superpowers/plans/2026-07-26-playwright-headed-mode.md`.

## Milestone — Issue #11: Skills MCP lifecycle

Summary: extend the public launcher seam with one Skills service whose local
loopback server and dedicated tunnel are managed as a single operator target.

```text
mcp-skills / mcps skills
          |
          v
 Skills server (127.0.0.1:2092)
          |
          v
 chatgpt-chat-skills-mcp tunnel profile
```

1. Specify Skills command, lifecycle, stale-state, combined-startup, and
   installer behavior through the existing shell test harness.
2. Add the minimum server-and-tunnel orchestration needed to make those public
   behaviors pass without changing Chrome or Playwright internals.
 3. Document machine-local server and tunnel setup, then run the full repository
   check before review.

## Milestone — Dual Chrome MCPs: chrome2 on :2093 joins `all`

## TLDR

1. Scope: new `chrome2` service (tunnel profile `chrome-browser-mcp-2`,
   loopback `:2093`) managed exactly like `chrome`; `mcps all`,
   `stop all`, `restart all`, `status`, `logs`, and `mcp-chrome2` cover it.
   One command starts both Chrome tunnels — no per-profile picking.
2. Out of scope: changing `both` (stays Chrome-1 + Playwright for backward
   compat, locked by `test_both_compatibility`); creating the second tunnel
   profile (operator runs `tunnel-client init` once, documented in README).
3. Deferred: per-profile Chrome auto-open (launcher still only ensures the
   loopback ports answer; the user keeps both profiles' extensions enabled).

## High-Level Flow

```text
mcps all
  +-- chrome  ->TunnelProfile chrome-browser-mcp   -> 127.0.0.1:2091 (profile 1 bridge)
  +-- chrome2 ->TunnelProfile chrome-browser-mcp-2 -> 127.0.0.1:2093 (profile 2 bridge)
  +-- playwright (headless) + skills (unchanged)
```

## Milestone — Three Chrome profiles and Skills tunnel fan-out

## Milestone — Truthful Chrome bridge readiness

The launcher must distinguish a live tunnel-client process from a reachable
Chrome MCP bridge. Chrome status and successful startup will probe each
configured loopback bridge port, so stale tunnel processes cannot be reported
as usable Chrome MCP routes.

```text
mcps status / mcp-chrome*
             |
             v
 tunnel process + :209x bridge probe
             |
             +--> usable route
             `--> tunnel alive, upstream stopped
```

1. Add a loopback bridge probe for each Chrome instance.
2. Require the probe before reporting a Chrome route started or running.
3. Cover both healthy and stale-upstream behavior through the public launcher
   test seam.

## Summary

Manage three fixed Chrome bridge instances and multiple account-bound Skills
tunnels with one shared stateless Skills server. Chrome routing is fixed by
instance; Skills routing is fixed by tunnel profile, with every Skills tunnel
targeting the same validated loopback service unless a separate corpus is
explicitly configured.

## System-level completion DAG

```text
mcps all
  +--> chrome-current -> :2091 -> tunnel profile current
  +--> chrome-new     -> :2093 -> tunnel profile new
  +--> chrome-agent   -> :2095 -> tunnel profile agent
  +--> skills-server  -> :2092
          +--> skills-current tunnel -> :2092
          +--> skills-new     tunnel -> :2092
          +--> skills-agent   tunnel -> :2092
```

## Milestones

1. Replace hardcoded Chrome-1/Chrome-2 dispatch with a validated instance
   table; assign unique PID, log, health, tunnel profile, port, and expected
   extension identity to each instance.
2. Add Skills tunnel fan-out while keeping exactly one shared Skills server;
   make readiness and stale-state checks per tunnel, not global.
3. Use distinct runtime-key references per account/org without printing or
   storing key material; make `status` report each route independently.
4. Add deterministic lifecycle tests, update the installer/README, install the
   new launcher copy, and run the complete shell check suite.
