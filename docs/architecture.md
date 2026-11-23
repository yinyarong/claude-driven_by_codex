# 架构

## 组件

```text
Windows
├─ Claude Code (claude.exe)
├─ CLIProxyAPI (:8317)          ← 路线 1 的桥
│    └─ OAuth credential: %USERPROFILE%\.cli-proxy-api\
├─ proxy-relay.js (:17897)       ← 只给 WSL 用的 TCP 中继
└─ Clash / HTTP proxy (:7897)    ← 所有 OpenAI 流量走这里

WSL2 (Ubuntu)
├─ claude (Linux, ~/.local/bin)
├─ codex  (Linux, ~/.local/bin)
├─ codex app-server (stdio JSON-RPC，clcd 拉起的子进程)
├─ clcd 的本地桥 (127.0.0.1:<随机端口>)
└─ ~/.codex/auth.json           ← 路线 2 的凭据（600 权限）
```

## 路线 1：`cdn`

```text
claude.exe
  ANTHROPIC_BASE_URL=http://127.0.0.1:8317
        │
        ▼
CLIProxyAPI (/v1/messages)
  · 把 Anthropic Messages 翻译成 OpenAI Responses
  · 用 its own ChatGPT OAuth token
  · 通过 requests.proxy-url 访问 chatgpt.com
        │
        ▼
https://chatgpt.com/backend-api/codex/responses
```

要点：

- Claude Code 认为自己在跟一个 Anthropic 兼容网关说话。
- CLIProxyAPI 自己持有凭据并自动刷新，不依赖 Codex CLI。
- 每条请求都由网关选择上游模型；Claude Code 侧的模型名只是路由别名。

## 路线 2：`clcd`

```text
Windows                          WSL
clcd.cmd ── wsl.exe ──────────► clcd-run ──► clcd (Bash)
                                              │
                                              ├─ socat TCP-LISTEN:127.0.0.1:<随机端口>
                                              ├─ codex app-server (stdio JSON-RPC)
                                              │    └─ getAuthStatus → access token
                                              └─ exec claude
                                                   ANTHROPIC_BASE_URL=http://127.0.0.1:<port>
```

请求路径：

```text
claude (WSL)
  → clcd 本地桥 (Anthropic Messages)
  → curl → chatgpt.com Responses (via HTTPS_PROXY → relay → Clash)
```

要点：

- 凭据从不复制到桥里：每次请求通过 `getAuthStatus` 从 codex app-server 取 token，短期有效。
- 桥用随机端口 + 随机 bearer token，只监听 `127.0.0.1`。
- `--setting-sources user` 防止项目目录的 `.claude/settings.json` 覆盖桥地址。

## 环境变量优先级（路线 2）

```text
CLAUDE_CONFIG_DIR=~/.claude-codex
  └─ 用户级 settings.json（theme 等）
      ▲
      │  只加载这一层（--setting-sources user）
      │
进程环境（clcd 导出）：
  ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN / ANTHROPIC_MODEL ...
```

如果不加 `--setting-sources user`，当前目录的 `.claude/settings.json`（项目级）会覆盖以上全部。

## 认证

| 路线 | 凭据位置 | 获取方式 | 刷新 |
| --- | --- | --- | --- |
| `cdn` | `%USERPROFILE%\.cli-proxy-api\codex-*.json` | `cli-proxy-api --codex-login` | 网关自动刷新 |
| `clcd` | WSL `~/.codex/auth.json` | 从路线 1 的凭据转换，或 `codex login` | codex CLI 自动刷新 |

两条路线共用同一个 ChatGPT OAuth 客户端，所以凭据可以互相转换；`install/install-wsl.sh --auth-json` 负责这件事，过程中不打印任何 token。

## 网络

```text
Windows 程序 → Clash 127.0.0.1:7897 → 上游
WSL 程序     → 172.x.x.1:17897 (relay) → Clash 127.0.0.1:7897 → 上游
```

- WSL 的默认网关就是 Windows 侧 vEthernet 的地址，每次重启可能变化，所以中继监听地址和 WSL 的代理地址都是动态得到的。
- `NO_PROXY=127.0.0.1,localhost` 保证 Claude Code 到本地桥的这一跳不走代理。

## 端口

| 端口 | 绑定 | 作用 |
| --- | --- | --- |
| 7897 | 127.0.0.1 | Clash 的 HTTP 代理（用户已有） |
| 8317 | 127.0.0.1 | CLIProxyAPI |
| 17897 | WSL 网卡地址 | 中继 |
| 随机 | 127.0.0.1 (WSL) | `clcd` 桥 |
| 1455 / 54545 | 127.0.0.1 | OAuth 回调（CLIProxyAPI 登录时临时使用） |
