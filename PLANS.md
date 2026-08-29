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
