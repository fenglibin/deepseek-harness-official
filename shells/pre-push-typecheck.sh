#!/bin/sh
# Fork-local pre-push typecheck entry, referenced by lefthook-local.yml.
#
# Git hooks inherit the environment of whatever process runs `git push`. IDE and
# GUI git clients are started by launchd with PATH=/usr/bin:/bin:/usr/sbin:/sbin,
# so the nvm-managed node/pnpm that interactive shells load from ~/.zshrc are
# absent and `pnpm run typecheck` dies with `sh: pnpm: command not found`.
# This wrapper resolves node/pnpm explicitly so the hook behaves identically from
# any caller, then runs the same script the upstream hook runs.
set -eu

root=$(git rev-parse --show-toplevel)
cd "$root"

if command -v pnpm >/dev/null 2>&1 && command -v node >/dev/null 2>&1; then
  exec pnpm run typecheck
fi

# Prints the last usable candidate directory. nvm globs expand lexicographically
# (v22 before v24), so the last match is the newest install for the usual vNN
# naming, which keeps the repo's node >= 24.9.0 engine requirement satisfied.
usable_dir() {
  found=
  for candidate in "$@"; do
    if [ -x "$candidate/node" ] && [ -x "$candidate/pnpm" ]; then
      found=$candidate
    fi
  done
  printf '%s' "$found"
}

for directory in \
  "$(usable_dir "$HOME"/.nvm/versions/node/*/bin)" \
  "$(usable_dir /opt/homebrew/bin /usr/local/bin)" \
  "$(usable_dir "$HOME"/Library/pnpm "$HOME"/.local/share/pnpm "$HOME"/.volta/bin)"
do
  if [ -n "$directory" ]; then
    PATH="$directory:$PATH"
    export PATH
    exec pnpm run typecheck
  fi
done

echo "pre-push typecheck: pnpm is not on PATH and no node+pnpm pair was found in ~/.nvm, /opt/homebrew/bin, /usr/local/bin, ~/Library/pnpm, ~/.local/share/pnpm or ~/.volta/bin." >&2
echo "Install pnpm or export its bin directory; to bypass this check once: LEFTHOOK=0 git push" >&2
exit 127
