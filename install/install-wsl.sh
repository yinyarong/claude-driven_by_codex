#!/bin/bash
# Install the WSL side: Node, codex, Claude Code, jq, socat, the patched upstream
# runtime, and the Windows-callable wrappers.
#
# Run from WSL:
#   bash /mnt/d/.../claude-driven_by_codex/install/install-wsl.sh --auth-json "/mnt/c/Users/<you>/.cli-proxy-api/codex-*.json"
set -euo pipefail

RELAY_PORT=17897
CLASH_PORT=7897
UPSTREAM_DIR="$HOME/claude-driven-ai-providers"
TARBALL=""
AUTH_JSON=""
SKIP_NPM=0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

while [ $# -gt 0 ]; do
  case "$1" in
    --relay-port)   RELAY_PORT=$2; shift 2;;
    --clash-port)   CLASH_PORT=$2; shift 2;;
    --upstream-dir) UPSTREAM_DIR=$2; shift 2;;
    --tarball)      TARBALL=$2; shift 2;;
    --auth-json)    AUTH_JSON=$2; shift 2;;
    --skip-npm)     SKIP_NPM=1; shift;;
    -h|--help)      sed -n '2,12p' "$0"; exit 0;;
    *) echo "unknown option: $1" >&2; exit 2;;
  esac
done

HOST_IP=$(ip route | awk '/^default/ {print $3; exit}')
export HTTPS_PROXY="http://$HOST_IP:$RELAY_PORT"
export HTTP_PROXY="$HTTPS_PROXY"
export NO_PROXY=127.0.0.1,localhost
export no_proxy="$NO_PROXY"

echo "[wsl] host=$HOST_IP relay=$RELAY_PORT clash=$CLASH_PORT"
proxy_ok=0
for _ in 1 2 3 4 5; do
  if curl -s -o /dev/null --max-time 5 -x "$HTTPS_PROXY" https://api.openai.com/v1/models; then
    proxy_ok=1
    break
  fi
  sleep 2
done
if [ "$proxy_ok" = 0 ]; then
  echo "[wsl] WARNING: proxy relay is not reachable at $HTTPS_PROXY" >&2
  echo "[wsl] start it on Windows first: node \"%USERPROFILE%\\Tools\\CLIProxyAPI\\proxy-relay.js\"" >&2
fi

mkdir -p "$HOME/.local/bin"

# ---------- Node ----------
if [ ! -x "$HOME/.local/node/bin/node" ]; then
  VER=$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c "import sys,json;d=json.load(sys.stdin);print(next(x['version'] for x in d if x['version'].startswith('v22.')))")
  echo "[wsl] installing node $VER"
  curl -fsSL "https://nodejs.org/dist/$VER/node-$VER-linux-x64.tar.xz" -o /tmp/node.tar.xz
  mkdir -p "$HOME/.local/node"
  tar -xJf /tmp/node.tar.xz -C "$HOME/.local/node" --strip-components=1
  rm -f /tmp/node.tar.xz
fi
export PATH="$HOME/.local/bin:$HOME/.local/node/bin:$PATH"

# ---------- jq / socat ----------
if ! command -v jq >/dev/null 2>&1; then
  echo "[wsl] installing jq"
  curl -fsSL -o "$HOME/.local/bin/jq" https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64
  chmod +x "$HOME/.local/bin/jq"
fi
if ! command -v socat >/dev/null 2>&1; then
  echo "[wsl] installing socat"
  curl -fsSL -o "$HOME/.local/bin/socat" https://github.com/andrew-d/static-binaries/raw/master/binaries/linux/x86_64/socat
  chmod +x "$HOME/.local/bin/socat"
fi
command -v flock >/dev/null 2>&1 || echo "[wsl] WARNING: flock is missing (install util-linux)" >&2

# ---------- codex / claude ----------
if [ "$SKIP_NPM" = 0 ]; then
  if ! command -v codex >/dev/null 2>&1 || ! command -v claude >/dev/null 2>&1; then
    echo "[wsl] installing codex and claude-code"
    npm config set prefix "$HOME/.local"
    npm i -g @openai/codex @anthropic-ai/claude-code
  fi
fi

# ---------- upstream runtime ----------
if [ -f "$UPSTREAM_DIR/clcd" ]; then
  echo "[wsl] using existing $UPSTREAM_DIR"
elif [ -n "$TARBALL" ]; then
  [ -f "$TARBALL" ] || { echo "[wsl] tarball not found: $TARBALL" >&2; exit 1; }
  echo "[wsl] extracting $TARBALL"
  mkdir -p "$UPSTREAM_DIR"
  tar -xzf "$TARBALL" -C "$UPSTREAM_DIR" --strip-components=1
else
  echo "[wsl] cloning upstream"
  rm -rf "$UPSTREAM_DIR"
  git clone --depth 1 https://github.com/xiaolai/claude-driven-ai-providers.git "$UPSTREAM_DIR"
fi
bash "$ROOT/install/patch-upstream.sh" "$UPSTREAM_DIR"

# ---------- environment and wrappers ----------
sed "s/__RELAY_PORT__/$RELAY_PORT/g" "$ROOT/bin/wsl/clcd-env.sh.template" > "$HOME/.clcd-env.sh"
chmod 600 "$HOME/.clcd-env.sh"
install -m 755 "$ROOT/bin/wsl/clcd-run" "$HOME/.local/bin/clcd-run"
install -m 755 "$ROOT/bin/wsl/clai-run" "$HOME/.local/bin/clai-run"

# ---------- Codex credential ----------
if [ -n "$AUTH_JSON" ]; then
  python3 - "$AUTH_JSON" <<'PY'
import glob, json, os, sys

paths = [p for p in glob.glob(sys.argv[1]) if not p.endswith(".lock")]
if not paths:
    raise SystemExit("no credential file matched")
data = json.load(open(paths[0]))
missing = [k for k in ("access_token", "refresh_token", "account_id") if not data.get(k)]
if missing:
    raise SystemExit("credential missing fields: " + ",".join(missing))
auth = {
    "OPENAI_API_KEY": None,
    "tokens": {
        "id_token": data.get("id_token"),
        "access_token": data["access_token"],
        "refresh_token": data["refresh_token"],
        "account_id": data["account_id"],
    },
    "last_refresh": data.get("last_refresh"),
}
home = os.path.expanduser("~")
os.makedirs(os.path.join(home, ".codex"), mode=0o700, exist_ok=True)
out = os.path.join(home, ".codex", "auth.json")
fd = os.open(out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as f:
    json.dump(auth, f, indent=2)
print("wrote", out, "mode 600")
PY
elif [ ! -f "$HOME/.codex/auth.json" ]; then
  echo "[wsl] no ~/.codex/auth.json; run 'codex login' inside WSL, or pass --auth-json"
fi

echo
echo "[wsl] done"
printf '  codex:  %s\n' "$(command -v codex || echo MISSING)"
printf '  claude: %s\n' "$(command -v claude || echo MISSING)"
printf '  clcd:   %s\n' "$UPSTREAM_DIR/clcd"
echo "  next:   run 'clcd' from Windows (the relay must be running)"
