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
  assert_contains "$(last_invocation 3)" "--headless" "both selects background Playwright mode"
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

case ${1:-all} in
  command_generation) test_command_generation ;;
  lifecycle) test_lifecycle ;;
  menu_chrome_and_errors) test_menu_chrome_and_errors ;;
  all)
    test_command_generation
    test_lifecycle
    test_menu_chrome_and_errors
    ;;
  *) print -u2 -r -- "Unknown test group: $1"; exit 2 ;;
esac

finish_tests
