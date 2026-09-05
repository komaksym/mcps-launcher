#!/bin/zsh

set -eu

readonly ROOT="${0:A:h}"
readonly SOURCE="$ROOT/bin/mcps"
readonly BIN_DIR="${MCP_LAUNCHER_INSTALL_BIN_DIR:-$HOME/.local/bin}"
readonly STAMP="$(date +%Y%m%d-%H%M%S)"
readonly -a ALIASES=(
  mcp-chrome
  mcp-chrome2
  mcp-playwright
  mcp-playwright-head
  mcp-playwright-headless
  mcp-skills
  mcp-skills2
)

[[ -f $SOURCE ]] || {
  print -u2 -r -- "Launcher source not found: $SOURCE"
  exit 1
}

mkdir -p "$BIN_DIR"

backup_path() {
  local target=$1 backup
  local suffix=1
  backup="$target.backup-$STAMP"
  while [[ -e $backup || -L $backup ]]; do
    backup="$target.backup-$STAMP-$suffix"
    (( suffix++ ))
  done
  mv "$target" "$backup"
  print -r -- "Backed up $target to $backup"
}

typeset installed="$BIN_DIR/mcps"
if [[ -e $installed || -L $installed ]]; then
  if [[ ! -f $installed ]] || ! cmp -s "$SOURCE" "$installed"; then
    backup_path "$installed"
  fi
fi
install -m 0755 "$SOURCE" "$installed"

typeset alias target
for alias in "${ALIASES[@]}"; do
  target="$BIN_DIR/$alias"
  if [[ -L $target && $(readlink "$target") == mcps ]]; then
    continue
  fi
  if [[ -e $target || -L $target ]]; then
    backup_path "$target"
  fi
  ln -s mcps "$target"
done

print -r -- "Installed MCP launcher commands in $BIN_DIR:"
print -r -- "  mcps"
for alias in "${ALIASES[@]}"; do
  print -r -- "  $alias"
done
