#!/bin/zsh

set -eu

readonly ROOT="${0:A:h:h}"
cd "$ROOT"

readonly -a ZSH_FILES=(
  bin/mcps
  install.sh
  scripts/check.zsh
  tests/fake-ps
  tests/fake-tunnel-client
  tests/helpers.zsh
  tests/test_install.zsh
  tests/test_mcps.zsh
)

print -r -- "CHECK syntax"
zsh -n "${ZSH_FILES[@]}"

print -r -- "CHECK launcher"
zsh tests/test_mcps.zsh

print -r -- "CHECK installer"
zsh tests/test_install.zsh

print -r -- "CHECK documentation"
[[ -f README.md ]] || {
  print -u2 -r -- "README.md is required"
  exit 1
}

print -r -- "CHECK repository hygiene"
if rg -n -i \
  '(api[_-]?key|token|secret|password)[[:space:]]*=[[:space:]]*[^$<{[:space:]]' \
  --glob '!docs/**' \
  --glob '!README.md' \
  --glob '!scripts/check.zsh' \
  .; then
  print -u2 -r -- "Potential credential assignment found"
  exit 1
fi

typeset tracked
tracked=$(git ls-files)
if print -r -- "$tracked" | rg -n \
  '(^|/)([^/]+\.(pid|log)|[^/]+-health\.url|playwright\.mode|\.playwright-spotify)(/|$)'; then
  print -u2 -r -- "Runtime state must not be tracked"
  exit 1
fi

print -r -- "CHECK diff"
git diff --check

print -r -- "PASS: all checks"
