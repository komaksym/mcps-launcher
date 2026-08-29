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

  run_launcher all >/dev/null
  local all_args
  all_args=$(< "$FAKE_TUNNEL_LOG")
  assert_contains "$all_args" "--profile chrome-browser-mcp" "all starts Chrome"
  assert_contains "$all_args" "--headless" "all selects background Playwright mode"
  [[ -f "$TEST_SANDBOX/state/chrome.log" ]] || fail "Chrome log was not created"
  [[ -f "$TEST_SANDBOX/state/playwright.log" ]] || fail "Playwright log was not created"

  run_launcher restart playwright-head >/dev/null
  assert_contains "$(run_launcher status)" "Playwright MCP: running (headed" "restart accepts an explicit Playwright mode"

  run_launcher stop all >/dev/null
  assert_contains "$(run_launcher status)" "Chrome MCP: stopped" "stop all stops Chrome"
  assert_contains "$(run_launcher status)" "Playwright MCP: stopped" "stop all stops Playwright"

  run_launcher nonsense >/dev/null 2>&1
  assert_eq "$?" "2" "unknown command exits 2"
  run_launcher stop nonsense >/dev/null 2>&1
  assert_eq "$?" "2" "unknown stop target exits 2"

  cleanup_sandbox
  trap - EXIT
}

# Preserves the pre-Skills Chrome + headless Playwright combined target.
test_both_compatibility() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  run_launcher both >/dev/null
  local both_args
  both_args=$(< "$FAKE_TUNNEL_LOG")
  assert_eq "$(fake_start_count)" "2" "both starts exactly Chrome and Playwright"
  assert_contains "$both_args" "--profile chrome-browser-mcp" "both preserves Chrome"
  assert_contains "$both_args" "--profile playwright" "both preserves Playwright"
  assert_not_contains "$both_args" "--profile chatgpt-chat-skills-mcp" "both does not silently add Skills"
  assert_contains "$(run_launcher status)" "Playwright MCP: running (headless" "both preserves headless Playwright mode"
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "both leaves Skills stopped"

  run_launcher stop both >/dev/null
  assert_contains "$(run_launcher status)" "Chrome MCP: stopped" "stop both stops Chrome"
  assert_contains "$(run_launcher status)" "Playwright MCP: stopped" "stop both stops Playwright"

  run_launcher restart both >/dev/null
  assert_contains "$(run_launcher status)" "Chrome MCP: running" "restart both restores Chrome"
  assert_contains "$(run_launcher status)" "Playwright MCP: running (headless" "restart both restores headless Playwright"
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "restart both leaves Skills stopped"

  cleanup_sandbox
  trap - EXIT
}

# Verifies every successful Skills command through the public launcher seam.
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

# Verifies one configured port is used consistently across the complete Skills seam.
test_skills_configured_port() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  export SKILLS_MCP_PORT=3092
  run_launcher skills >/dev/null

  assert_contains "$(< "$FAKE_SKILLS_LOG")" "PORT=3092" "Skills server receives configured port"
  assert_contains "$(< "$FAKE_CURL_LOG")" "http://127.0.0.1:3092/healthz" "Skills health probe uses configured port"
  assert_eq "$(< "$TEST_SANDBOX/state/skills-server-health.url")" "http://127.0.0.1:3092/healthz" "Skills health state uses configured port"
  assert_contains "$(last_invocation 1)" "url=http://127.0.0.1:3092/mcp,channel=main" "Skills tunnel uses configured port"

  cleanup_sandbox
  trap - EXIT
}

# Verifies combined startup adds Skills without removing existing services.
test_skills_combined_startup() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  run_launcher all >/dev/null
  local all_args
  all_args=$(< "$FAKE_TUNNEL_LOG")
  assert_contains "$all_args" "--profile chrome-browser-mcp" "combined startup preserves Chrome"
  assert_contains "$all_args" "--profile playwright" "combined startup preserves Playwright"
  assert_contains "$all_args" "--profile chatgpt-chat-skills-mcp" "combined startup includes Skills"
  assert_contains "$(run_launcher status)" "Skills MCP: running" "combined status includes Skills"

  run_launcher stop all >/dev/null
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "combined stop includes Skills"

  cleanup_sandbox
  trap - EXIT
}

# Verifies failed and partial Skills starts roll back only managed processes.
test_skills_failures() {
  setup_sandbox
  trap cleanup_sandbox EXIT

  export FAKE_SKILLS_SERVER_EXIT=1
  run_launcher skills >/dev/null 2>&1
  assert_eq "$?" "1" "server launch failure exits non-zero"
  assert_eq "$(fake_start_count)" "0" "server launch failure does not start a tunnel"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "server launch failure leaves a PID file"

  export FAKE_SKILLS_SERVER_EXIT=0
  export FAKE_HEALTH_STATUS=failure
  run_launcher skills >/dev/null 2>&1
  assert_eq "$?" "1" "health failure exits non-zero"
  assert_eq "$(fake_start_count)" "0" "health failure does not start a tunnel"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "health failure leaves the server running"

  export FAKE_HEALTH_STATUS=success
  export FAKE_HEALTH_BODY='{"status":"wrong"}'
  run_launcher skills >/dev/null 2>&1
  assert_eq "$?" "1" "wrong health body exits non-zero"
  assert_eq "$(fake_start_count)" "0" "wrong health body does not start a tunnel"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "wrong health body leaves the server running"

  export FAKE_HEALTH_BODY='{"status":"ok"}'
  export FAKE_TUNNEL_EXIT=1
  run_launcher skills >/dev/null 2>&1
  assert_eq "$?" "1" "tunnel launch failure exits non-zero"
  [[ ! -e "$TEST_SANDBOX/state/skills.pid" ]] || fail "tunnel launch failure leaves a tunnel PID"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "tunnel launch failure leaves the server running"

  export FAKE_TUNNEL_EXIT=0
  run_launcher skills >/dev/null
  local tunnel_pid
  tunnel_pid=$(< "$TEST_SANDBOX/state/skills.pid")
  kill -TERM "$tunnel_pid" 2>/dev/null || true
  local i
  for i in {1..20}; do
    kill -0 "$tunnel_pid" 2>/dev/null || break
    sleep 0.1
  done
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "partial lifecycle is cleaned up"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "partial cleanup leaves the server running"

  run_launcher skills >/dev/null
  local server_pid
  server_pid=$(< "$TEST_SANDBOX/state/skills-server.pid")
  kill -TERM "$server_pid" 2>/dev/null || true
  for i in {1..20}; do
    kill -0 "$server_pid" 2>/dev/null || break
    sleep 0.1
  done
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "server-only failure cleans up its tunnel"
  [[ ! -e "$TEST_SANDBOX/state/skills.pid" ]] || fail "server-only failure leaves the tunnel running"

  sleep 30 &
  local unrelated=$!
  print -r -- "editor $SKILLS_MCP_SERVER_ENTRY" > "$FAKE_PROCESS_DIR/$unrelated.command"
  print -r -- "$unrelated" > "$TEST_SANDBOX/state/skills-server.pid"
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "entry-only process match is rejected"
  kill -0 "$unrelated" 2>/dev/null || fail "entry-only stale cleanup killed an unrelated process"
  kill -TERM "$unrelated" 2>/dev/null || true

  sleep 30 &
  unrelated=$!
  print -r -- "editor $SKILLS_MCP_SERVER_ENTRY" > "$FAKE_PROCESS_DIR/$unrelated.command"
  print -r -- "$unrelated" > "$TEST_SANDBOX/state/skills-server.pid"
  export SKILLS_MCP_NODE_BIN=""
  local missing_node_status\n  missing_node_status=$(PATH=/bin:/usr/bin run_launcher status)\n  assert_contains "$missing_node_status" "Skills MCP: stopped" "missing Node identity cannot own an entry-only process"
  kill -0 "$unrelated" 2>/dev/null || fail "missing Node identity stale cleanup killed an unrelated process"
  [[ ! -e "$TEST_SANDBOX/state/skills-server.pid" ]] || fail "missing Node identity leaves a stale server PID"
  export SKILLS_MCP_NODE_BIN="$TEST_SANDBOX/bin/skills-server"
  kill -TERM "$unrelated" 2>/dev/null || true

  sleep 30 &
  unrelated=$!
  print -r -- "tunnel-client run --profile playwright" > "$FAKE_PROCESS_DIR/$unrelated.command"
  print -r -- "$unrelated" > "$TEST_SANDBOX/state/skills.pid"
  assert_contains "$(run_launcher status)" "Skills MCP: stopped" "wrong-profile tunnel PID is stale"
  kill -0 "$unrelated" 2>/dev/null || fail "stale tunnel cleanup killed an unrelated process"
  kill -TERM "$unrelated" 2>/dev/null || true

  cleanup_sandbox
  trap - EXIT
}

case ${1:-all} in
  command_generation) test_command_generation ;;
  lifecycle) test_lifecycle ;;
  menu_chrome_and_errors) test_menu_chrome_and_errors ;;
  both_compatibility) test_both_compatibility ;;
  skills_lifecycle) test_skills_lifecycle ;;
  skills_configured_port) test_skills_configured_port ;;
  skills_combined_startup) test_skills_combined_startup ;;
  skills_failures) test_skills_failures ;;
  all)
    test_command_generation
    test_lifecycle
    test_menu_chrome_and_errors
    test_both_compatibility
    test_skills_lifecycle
    test_skills_configured_port
    test_skills_combined_startup
    test_skills_failures
    ;;
  *) print -u2 -r -- "Unknown test group: $1"; exit 2 ;;
esac

finish_tests
