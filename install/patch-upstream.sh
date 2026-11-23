#!/bin/bash
# Make the upstream claude-driven-ai-providers runtime work on GNU/Linux (WSL).
# The upstream scripts are macOS-first: BSD stat and lockf.
set -euo pipefail

DIR=${1:?usage: patch-upstream.sh UPSTREAM_DIR}
cd "$DIR"
[ -f clai ] && [ -f clcd ] || { echo "not a claude-driven-ai-providers checkout: $DIR" >&2; exit 1; }

if ! grep -q "stat -f" clai clcd 2>/dev/null; then
  echo "already patched"
  exit 0
fi

[ -f clai.macos.bak ] || cp clai clai.macos.bak
[ -f clcd.macos.bak ] || cp clcd clcd.macos.bak

sed -i "s/stat -f '%Lp'/stat -c '%a'/g; s/stat -f '%u'/stat -c '%u'/g" clai clcd
sed -i 's/lockf -s -t 30 9/flock -w 30 9/g' clcd
sed -i 's/for tool in codex lockf/for tool in codex flock/g' clai
sed -i 's/required_tools="\$required_tools lockf codex"/required_tools="$required_tools flock codex"/g' clcd

bash -n clai
bash -n clcd

echo "patched: stat -f -> stat -c, lockf -> flock"
