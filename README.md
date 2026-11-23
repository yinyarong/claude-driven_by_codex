# claude-driven_by_codex

在 **Windows 10/11** 上用 **ChatGPT / Codex 订阅**驱动 **Claude Code** 的两条可运行路线。

Claude Code 只会说 Anthropic Messages 协议，而 Codex 订阅只接受 OpenAI Responses 协议，所以中间必须有一个本地桥做协议翻译。协议实现参考了 [xiaolai/claude-driven-ai-providers](https://github.com/xiaolai/claude-driven-ai-providers)，但它是 macOS 专用的；本仓库把它和另一条更轻的路线一起移植到了 Windows。

---

## 两条路线

| 命令 | 方案 | Claude Code 跑在哪 | 特点 |
| --- | --- | --- | --- |
| `cdn` | [CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)（Go 单文件网关） | Windows 原生 | 启动快，不依赖 WSL 运行时 |
| `clcd` | 上游仓库的 `clcd` Bash 桥 | WSL（Ubuntu） | 保留上游的隔离 profile、模型映射、`clai doctor` |

两者共用同一个 ChatGPT 登录态和同一个本地代理，互不影响。`clai` 用来管理 WSL 侧的运行时（`list` / `doctor` / `config` / `models` / `probe` / `map`）。

## 前置条件

- Windows 10 1903+ 或 Windows 11，已启用 WSL2，装有 Ubuntu
- Node.js 18+（Windows 侧，用于本地中继）
- Claude Code 已安装（`claude` 在 PATH）
- 一个 ChatGPT 账号（免费档可用，但可用模型受限）
- 一个本地 HTTP 代理（Clash / Mihomo 等），默认假设 `127.0.0.1:7897`

不需要预先安装 Codex CLI：路线 1 由 CLIProxyAPI 自己完成 OAuth；路线 2 会在 WSL 内安装 codex。

## 快速开始

### 1. Windows 侧

在仓库根目录打开 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File .\install\install.ps1 -Proxy http://127.0.0.1:7897
```

它会：

- 下载并校验 CLIProxyAPI（已存在则跳过）
- 生成一份含本地客户端密钥的私有 `config.yaml`
- 安装 `cdn` / `clcd` / `clai` 到 `%USERPROFILE%\.local\bin`
- 安装并启动 WSL 代理中继

### 2. 登录 ChatGPT（一次）

```powershell
& "$env:USERPROFILE\Tools\CLIProxyAPI\app-8.1.1\cli-proxy-api.exe" --config "$env:USERPROFILE\Tools\CLIProxyAPI\config.yaml" --codex-login --login-proxy http://127.0.0.1:7897
```

浏览器会打开授权页，完成后凭据保存在 `%USERPROFILE%\.cli-proxy-api\`。

> 如果账号提示“设备码登录未启用”，不要用 `--codex-device-login`，用上面的标准 OAuth 即可。

### 3. WSL 侧

```powershell
wsl -d Ubuntu -- bash "/mnt/d/个人/claude-driven_by_codex/install/install-wsl.sh" --auth-json "/mnt/c/Users/<你>/.cli-proxy-api/codex-*.json"
```

它会：安装 Node 22、codex、Claude Code、jq、socat（全部在 `~/.local`，不需要 sudo），拉取上游运行时、打 Linux 补丁、导入 Codex 凭据、安装 WSL 包装脚本。

### 4. 使用

```powershell
cd D:\你的项目
cdn     # 或 clcd
```

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `cdn` | 用 CLIProxyAPI 在 Windows 原生 Claude Code 里跑 Codex 模型 |
| `clcd` | 用上游 `clcd` 桥在 WSL 里跑 Claude Code |
| `cdn -c` / `clcd -c` | 继续上次会话 |
| `clai list` | 列出上游支持的所有 provider |
| `clai doctor codex --network` | 诊断 Codex 路线 |
| `clai config show codex` | 查看当前模型、上下文等设置 |
| `clai config set codex model <id>` | 切换模型 |
| `clai probe codex` / `clai map codex --strategy balanced` | 探测模型并生成角色映射 |

交互模式里用 `/model` 查看网关可用模型，`/status` 查看当前 API 地址。

## 关键设计

### 为什么启动器都带 `--setting-sources user`

Claude Code 会把**当前目录**的 `.claude/settings.json` 当成项目级配置，而项目级 `env` 的优先级高于进程环境变量。如果你的用户目录本身就是工作目录，它里面的 `ANTHROPIC_BASE_URL` 会把启动器注入的桥地址覆盖掉，请求会悄悄回到原来的第三方 API。

`--setting-sources user` 让 Claude Code 只加载用户级配置（即 `CLAUDE_CONFIG_DIR` 下的 `settings.json`），忽略项目级和本地级。代价是项目自己的 hooks 和权限规则也不再生效。

### 为什么 WSL 需要一个 TCP 中继

WSL2 默认是 NAT 网络，Linux 侧访问不到 Windows 的 `127.0.0.1`。`relay/proxy-relay.js` 监听在 WSL 虚拟网卡的地址上（例如 `172.21.16.1:17897`），转发到 Clash 的 `127.0.0.1:7897`。它只绑 WSL 网卡，不会暴露给局域网。WSL 每次重启后网关 IP 可能变化，`~/.clcd-env.sh` 会在启动时动态计算。

### 为什么 WSL 里要改上游源码

上游脚本是 macOS 优先的，有三处 Linux 不兼容：

- `stat -f '%Lp'` / `stat -f '%u'`：BSD 语法，GNU 是 `stat -c '%a'` / `stat -c '%u'`
- `lockf -s -t 30 9`：macOS 专有锁，Linux 用 `flock -w 30 9`

`install/patch-upstream.sh` 会幂等地完成替换，并把原文件保存为 `*.macos.bak`。上游更新后重跑一次即可。

## 安全与隐私

- 仓库里**没有任何密钥**。`config.yaml`、`route.env.cmd`、`~/.codex/auth.json`、`~/.cli-proxy-api/` 都在仓库外，且已被 `.gitignore` 覆盖。
- CLIProxyAPI 只监听 `127.0.0.1`；中继只监听 WSL 网卡。
- 通过订阅驱动第三方客户端属于非官方用法，可能触及 OpenAI 的使用条款，风险自负。
- 默认不开启 `bypassPermissions`。需要完全免确认时，安装时加 `-BypassPermissions`。

## 目录结构

```text
bin/            Windows 启动器（cdn / clcd / clai）与 WSL 包装脚本
config/         CLIProxyAPI 配置模板
docs/           架构与故障排查
install/        Windows / WSL 安装脚本、上游补丁、凭据导入
relay/          暴露给 WSL 的本地 TCP 中继
```

## 更新

- 上游运行时更新：重新拉取 `xiaolai/claude-driven-ai-providers`，然后执行 `install/patch-upstream.sh`
- CLIProxyAPI 升级：下载新版本到 `%USERPROFILE%\Tools\CLIProxyAPI\app-<版本>`，修改 `route.env.cmd` 里的 `CDR_CPA_EXE`
- 本项目更新：`git pull` 后重跑 `install.ps1`（不会覆盖已有 `config.yaml` 和密钥）

## 许可证与致谢

MIT。协议实现与 `clcd` 设计来自 [xiaolai/claude-driven-ai-providers](https://github.com/xiaolai/claude-driven-ai-providers)；网关来自 [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)。
