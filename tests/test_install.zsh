#!/bin/zsh

set -u
unsetopt BG_NICE
source "${0:A:h}/helpers.zsh"

typeset sandbox
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/mcps-installer-test.XXXXXX")
trap 'rm -rf "$sandbox"' EXIT

typeset bin_dir="$sandbox/bin"
mkdir -p "$bin_dir"
print -r -- "old unmanaged launcher" > "$bin_dir/mcps"
chmod 700 "$bin_dir/mcps"
ln -s /tmp/unmanaged "$bin_dir/mcp-playwright"
print -r -- "old unmanaged Skills command" > "$bin_dir/mcp-skills"

MCP_LAUNCHER_INSTALL_BIN_DIR="$bin_dir" "$TEST_ROOT/install.sh" >/dev/null

[[ -x "$bin_dir/mcps" ]] || fail "installed mcps is not executable"
cmp -s "$TEST_ROOT/bin/mcps" "$bin_dir/mcps" || fail "installed mcps differs from repository source"

typeset alias
for alias in mcp-chrome mcp-playwright mcp-playwright-head mcp-playwright-headless mcp-skills; do
  [[ -L "$bin_dir/$alias" ]] || {
    fail "$alias is not a symlink"
    continue
  }
  assert_eq "$(readlink "$bin_dir/$alias")" "mcps" "$alias must use a relocatable relative link"
done

typeset -a launcher_backups=("$bin_dir"/mcps.backup-*(N))
typeset -a alias_backups=("$bin_dir"/mcp-playwright.backup-*(N))
typeset -a skills_backups=("$bin_dir"/mcp-skills.backup-*(N))
assert_eq "${#launcher_backups}" "1" "conflicting launcher is backed up once"
assert_eq "${#alias_backups}" "1" "conflicting alias is backed up once"
assert_eq "${#skills_backups}" "1" "conflicting Skills command is backed up once"
if (( ${#launcher_backups} == 1 )); then
  assert_eq "$(< "$launcher_backups[1]")" "old unmanaged launcher" "launcher backup preserves content"
fi
if (( ${#alias_backups} == 1 )); then
  assert_eq "$(readlink "$alias_backups[1]")" "/tmp/unmanaged" "alias backup preserves link target"
fi
if (( ${#skills_backups} == 1 )); then
  assert_eq "$(< "$skills_backups[1]")" "old unmanaged Skills command" "Skills backup preserves content"
fi

MCP_LAUNCHER_INSTALL_BIN_DIR="$bin_dir" "$TEST_ROOT/install.sh" >/dev/null

launcher_backups=("$bin_dir"/mcps.backup-*(N))
alias_backups=("$bin_dir"/mcp-playwright.backup-*(N))
skills_backups=("$bin_dir"/mcp-skills.backup-*(N))
assert_eq "${#launcher_backups}" "1" "idempotent reinstall does not back up managed launcher"
assert_eq "${#alias_backups}" "1" "idempotent reinstall does not back up managed alias"
assert_eq "${#skills_backups}" "1" "idempotent reinstall does not duplicate Skills backup"

trap - EXIT
rm -rf "$sandbox"
finish_tests
