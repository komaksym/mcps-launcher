#!/bin/zsh

set -u
source "${0:A:h}/helpers.zsh"

test_command_generation() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  run_alias mcp-playwright-head >/dev/null
  local headed
  headed=$(last_invocation 1)
  assert_contains "$headed" "@playwright/mcp@latest" "headed mode launches Playwright MCP"
  assert_contains "$headed" "--user-data-dir=$TEST_SANDBOX/.playwright-spotify" "headed mode uses persistent profile"
  assert_not_contains "$headed" "--headless" "headed mode must show a browser"
  run_launcher stop playwright >/dev/null

  run_alias mcp-playwright-headless >/dev/null
  local headless
  headless=$(last_invocation 2)
  assert_contains "$headless" "--headless" "headless alias selects headless mode"
  assert_contains "$headless" "--user-data-dir=$TEST_SANDBOX/.playwright-spotify" "headless mode shares persistent profile"
  run_launcher stop playwright >/dev/null

  run_alias mcp-playwright >/dev/null
  local legacy
  legacy=$(last_invocation 3)
  assert_eq "$legacy" "$headless" "legacy alias remains equivalent to headless mode"

  cleanup_sandbox
  trap - EXIT
}

test_lifecycle() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  run_launcher playwright-head >/dev/null
  assert_contains "$(run_launcher status)" "Playwright MCP: running (headed" "status reports headed mode"
  assert_eq "$(fake_start_count)" "1" "headed mode starts one tunnel"

  run_launcher playwright-head >/dev/null
  assert_eq "$(fake_start_count)" "1" "same-mode duplicate start is prevented"

  run_launcher playwright-headless >/dev/null
  assert_contains "$(run_launcher status)" "Playwright MCP: running (headless" "switch updates active mode"
  assert_eq "$(fake_start_count)" "2" "switch replaces the tunnel exactly once"

  run_launcher stop playwright >/dev/null
  assert_contains "$(run_launcher status)" "Playwright MCP: stopped" "stop clears active Playwright state"
  [[ ! -e "$TEST_SANDBOX/state/playwright.pid" ]] || fail "stop leaves a PID file"
  [[ ! -e "$TEST_SANDBOX/state/playwright.mode" ]] || fail "stop leaves a mode file"

  sleep 30 &
  local unrelated=$!
  print -r -- "$unrelated" > "$TEST_SANDBOX/state/playwright.pid"
  print -r -- "headed" > "$TEST_SANDBOX/state/playwright.mode"
  assert_contains "$(run_launcher status)" "Playwright MCP: stopped" "unrelated PID is treated as stale"
  kill -0 "$unrelated" 2>/dev/null || fail "stale cleanup signalled an unrelated process"
  [[ ! -e "$TEST_SANDBOX/state/playwright.pid" ]] || fail "stale PID file was not removed"
  [[ ! -e "$TEST_SANDBOX/state/playwright.mode" ]] || fail "stale mode file was not removed"
  kill -TERM "$unrelated" 2>/dev/null || true

  cleanup_sandbox
  trap - EXIT
}

test_menu_chrome_and_errors() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  local menu
  menu=$(print -r -- q | run_launcher)
  assert_contains "$menu" "Start Playwright MCP (headed)" "menu exposes headed mode"
  assert_contains "$menu" "Start Playwright MCP (headless)" "menu exposes headless mode"
  assert_eq "$(fake_start_count)" "0" "bare menu starts nothing"

  run_alias mcp-chrome >/dev/null
  assert_contains "$(last_invocation 1)" "--profile chrome-browser-mcp" "Chrome alias preserves its tunnel profile"
  assert_contains "$(run_launcher status)" "Chrome MCP: running" "status reports Chrome"
  run_launcher stop chrome >/dev/null

  run_launcher both >/dev/null
  local all_args
  all_args=$(< "$FAKE_TUNNEL_LOG")
  assert_contains "$all_args" "--profile chrome-browser-mcp" "both starts Chrome"
  assert_contains "$all_args" "--headless" "both selects background Playwright mode"
  [[ -f "$TEST_SANDBOX/state/chrome.log" ]] || fail "Chrome log was not created"
  [[ -f "$TEST_SANDBOX/state/playwright.log" ]] || fail "Playwright log was not created"

  run_launcher restart playwright-head >/dev/null
  assert_contains "$(run_launcher status)" "Playwright MCP: running (headed" "restart accepts an explicit Playwright mode"

  run_launcher stop both >/dev/null
  assert_contains "$(run_launcher status)" "Chrome MCP: stopped" "stop both stops Chrome"
  assert_contains "$(run_launcher status)" "Playwright MCP: stopped" "stop both stops Playwright"

  run_launcher nonsense >/dev/null 2>&1
  assert_eq "$?" "2" "unknown command exits 2"
  run_launcher stop nonsense >/dev/null 2>&1
  assert_eq "$?" "2" "unknown stop target exits 2"

  cleanup_sandbox
  trap - EXIT
}

test_skills_lifecycle() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  run_alias mcp-skills >/dev/null
  assert_contains "$(< "$FAKE_SKILLS_LOG")" "$SKILLS_MCP_SERVER_ENTRY PORT=2092" "Skills alias starts the configured loopback server"
  assert_contains "$(last_invocation 1)" "--profile chatgpt-chat-skills-mcp" "Skills uses its dedicated tunnel profile"
  assert_contains "$(last_invocation 1)" "url=http://127.0.0.1:2092/mcp,channel=main" "Skills tunnel targets the configured loopback endpoint"
  assert_contains "$(run_launcher status)" "Skills MCP: running" "status reports Skills only when its lifecycle is active"
  [[ -f "$TEST_SANDBOX/state/skills.pid" ]] || fail "Skills tunnel PID file was not created"
  [[ -f "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "Skills server PID file was not created"
  assert_eq "$(< "$TEST_SANDBOX/state/skills-server-health.url")" "http://127.0.0.1:2092/healthz" "Skills server health URL follows the loopback convention"

  run_launcher skills >/dev/null
  assert_eq "$(fake_start_count)" "1" "duplicate Skills start does not replace its tunnel"
  assert_eq "$(wc -l < "$FAKE_SKILLS_LOG" | tr -d ' ')" "1" "duplicate Skills start does not replace its server"

  print -r -- "skills lifecycle log" >> "$TEST_SANDBOX/state/skills.log"
  assert_contains "$(run_launcher logs skills)" "skills lifecycle log" "Skills logs use the Skills tunnel log"

  run_launcher restart skills >/dev/null
  assert_contains "$(run_launcher status)" "Skills MCP: running" "restart restores Skills lifecycle"
  assert_eq "$(fake_start_count)" "2" "restart replaces the Skills tunnel once"

  run_launcher stop skills >/dev/null
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "stop clears Skills lifecycle"
  [[ ! -e "$TEST_SANDBOX/state/skills.pid" ]] || fail "Skills stop leaves a tunnel PID file"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "Skills stop leaves a server PID file"
  [[ ! -e "$TEST_SANDBOX/state/skills-health.url" ]] || fail "Skills stop leaves a tunnel health URL"
  [[ ! -e "$TEST_SANDBOX/state/skills-server-health.url" ]] || fail "Skills stop leaves a server health URL"

  sleep 30 &
  local unrelated=$!
  print -r -- "$unrelated" > "$TEST_SANDBOX/state/skills-server.pid"
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "unrelated Skills server PID is stale"
  kill -0 "$unrelated" 2>/dev/null || fail "Skills stale cleanup signalled an unrelated process"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "Skills stale server PID was not removed"
  kill -TERM "$unrelated" 2>/dev/null || true

  cleanup_sandbox
  trap - EXIT
}

test_skills_combined_startup() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  run_launcher both >/dev/null
  local all_args
  all_args=$(< "$FAKE_TUNNEL_LOG")
  assert_contains "$all_args" "--profile chrome-browser-mcp" "combined startup preserves Chrome"
  assert_contains "$all_args" "--profile playwright" "combined startup preserves Playwright"
  assert_contains "$all_args" "--profile chatgpt-chat-skills-mcp" "combined startup includes Skills"
  assert_contains "$(run_launcher status)" "Skills MCP: running" "combined status includes Skills"

  run_launcher stop both >/dev/null
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "combined stop includes Skills"

  cleanup_sandbox
  trap - EXIT
}

case ${1:-all} in
  command_generation) test_command_generation ;;
  lifecycle) test_lifecycle ;;
  menu_chrome_and_errors) test_menu_chrome_and_errors ;;
  skills_lifecycle) test_skills_lifecycle ;;
  skills_combined_startup) test_skills_combined_startup ;;
  all)
    test_command_generation
    test_lifecycle
    test_menu_chrome_and_errors
    test_skills_lifecycle
    test_skills_combined_startup
    ;;
  *) print -u2 -r -- "Unknown test group: $1"; exit 2 ;;
esac

finish_tests
