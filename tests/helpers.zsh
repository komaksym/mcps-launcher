#!/bin/zsh

set -u
unsetopt BG_NICE

readonly TEST_ROOT="${0:A:h:h}"
typeset -g TEST_SANDBOX=""
typeset -g TEST_FAILURES=0

fail() {
  print -u2 -r -- "FAIL: $*"
  TEST_FAILURES=$((TEST_FAILURES + 1))
}

assert_eq() {
  local actual=$1 expected=$2 message=${3:-"values differ"}
  [[ $actual == "$expected" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
  local actual=$1 expected=$2 message=${3:-"missing expected text"}
  [[ $actual == *"$expected"* ]] || fail "$message ('$expected')"
}

assert_not_contains() {
  local actual=$1 unexpected=$2 message=${3:-"found unexpected text"}
  [[ $actual != *"$unexpected"* ]] || fail "$message ('$unexpected')"
}

setup_sandbox() {
  TEST_SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/mcps-launcher-test.XXXXXX")
  mkdir -p "$TEST_SANDBOX/bin" "$TEST_SANDBOX/state" "$TEST_SANDBOX/profiles"
  cp "$TEST_ROOT/tests/fake-tunnel-client" "$TEST_SANDBOX/bin/tunnel-client"
  cp "$TEST_ROOT/tests/fake-ps" "$TEST_SANDBOX/bin/ps"
  chmod +x "$TEST_SANDBOX/bin/tunnel-client"
  chmod +x "$TEST_SANDBOX/bin/ps"
  ln -s "$TEST_ROOT/bin/mcps" "$TEST_SANDBOX/bin/mcps"
  ln -s mcps "$TEST_SANDBOX/bin/mcp-chrome"
  ln -s mcps "$TEST_SANDBOX/bin/mcp-playwright"
  ln -s mcps "$TEST_SANDBOX/bin/mcp-playwright-head"
  ln -s mcps "$TEST_SANDBOX/bin/mcp-playwright-headless"

  export MCP_LAUNCHER_STATE_DIR="$TEST_SANDBOX/state"
  export TUNNEL_CLIENT_PROFILE_DIR="$TEST_SANDBOX/profiles"
  export TUNNEL_CLIENT_BIN="$TEST_SANDBOX/bin/tunnel-client"
  export MCP_LAUNCHER_PS_BIN="$TEST_SANDBOX/bin/ps"
  export MCP_LAUNCHER_STARTUP_WAIT=0.5
  export MCP_LAUNCHER_SKIP_CHROME_OPEN=1
  export PLAYWRIGHT_MCP_USER_DATA_DIR="$TEST_SANDBOX/.playwright-spotify"
  export FAKE_TUNNEL_LOG="$TEST_SANDBOX/tunnel-args.log"
  export FAKE_PROCESS_DIR="$TEST_SANDBOX/processes"
  mkdir -p "$FAKE_PROCESS_DIR"
}

cleanup_sandbox() {
  if [[ -n $TEST_SANDBOX && -d $TEST_SANDBOX ]]; then
    local file pid
    for file in "$TEST_SANDBOX"/state/*.pid(N); do
      IFS= read -r pid < "$file" || true
      [[ $pid == <-> ]] && kill -TERM "$pid" 2>/dev/null || true
    done
    rm -rf "$TEST_SANDBOX"
  fi
}

run_launcher() {
  "$TEST_SANDBOX/bin/mcps" "$@"
}

run_alias() {
  local name=$1
  shift
  "$TEST_SANDBOX/bin/$name" "$@"
}

last_invocation() {
  local expected=${1:-1} i count
  for i in {1..60}; do
    if [[ -s $FAKE_TUNNEL_LOG ]]; then
      count=$(wc -l < "$FAKE_TUNNEL_LOG" | tr -d ' ')
      if (( count >= expected )); then
        tail -n 1 "$FAKE_TUNNEL_LOG"
        return
      fi
    fi
    sleep 0.05
  done
  return 1
}

fake_start_count() {
  [[ -f $FAKE_TUNNEL_LOG ]] || {
    print -r -- 0
    return
  }
  wc -l < "$FAKE_TUNNEL_LOG" | tr -d ' '
}

finish_tests() {
  if (( TEST_FAILURES > 0 )); then
    print -u2 -r -- "$TEST_FAILURES assertion(s) failed"
    return 1
  fi
  print -r -- "PASS"
}
