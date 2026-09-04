#!/bin/zsh

set -eu

readonly ROOT="${0:A:h:h}"
cd "$ROOT"

readonly -a ZSH_FILES=(
  bin/mcps
  install.sh
  scripts/check.zsh
  tests/fake-ps
  tests/fake-curl
  tests/fake-skills-server
  tests/fake-tunnel-client
  tests/helpers.zsh
  tests/test_install.zsh
  tests/test_mcps.zsh
)

print -r -- "CHECK syntax"
print -r -- "CHECK launcher structure"
typeset launcher_case_count skills_server_count
launcher_case_count=$(rg -c '^case "\$\{0:t\}" in$' bin/mcps || true)
skills_server_count=$(rg -c '^start_skills_server\(\) \{$' bin/mcps || true)
[[ $launcher_case_count == 1 && $skills_server_count == 1 ]] || {
  print -u2 -r -- "bin/mcps contains duplicated launcher sections"
  exit 1
}
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
typeset tracked
tracked=$(git ls-files)

if print -r -- "$tracked" | rg -n \
  '(^|/)(\.env($|\.)|[^/]+\.(pem|key|p12|pfx)$|id_(rsa|ed25519)(\.|$)|(credentials?|secrets?)(\.[^/]*)?\.json$|\.npmrc$|\.pypirc$|\.netrc$|\.aws(/|$)|\.ssh(/|$)|(\.config/)?tunnel-client(/|$)|[^/]+\.(pid|log)$|[^/]+-health\.url$|playwright\.mode$|\.playwright-spotify(/|$))'; then
  print -u2 -r -- "Sensitive or runtime file must not be tracked"
  exit 1
fi

if git grep -n -I -i -E \
  -e '-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'ASIA[0-9A-Z]{16}' \
  -e 'gh[pousr]_[A-Za-z0-9]{20,}' \
  -e 'github_pat_[A-Za-z0-9_]{20,}' \
  -e 'sk-[A-Za-z0-9_-]{20,}' \
  -e 'sk_(live|test)_[A-Za-z0-9]{16,}' \
  -e 'xox[baprs]-[A-Za-z0-9-]{10,}' \
  -e 'AIza[0-9A-Za-z_-]{35}' \
  -e '(api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|passwd|secret)[[:space:]]*[:=][[:space:]]*[^$<{[:space:]]{8,}' \
  -- .; then
  print -u2 -r -- "Potential credential material found"
  exit 1
fi

print -r -- "CHECK diff"
git diff --check

print -r -- "PASS: all checks"
