# 故障排查

## 请求又回到了第三方 API（DeepSeek / GLM / 中转站）

**症状**：`cdn` / `clcd` 能用，但 `/model` 或回答风格明显不是 Codex；日志里出现 `deepseek-flash[1m]` 之类的 `unrecognized_model`。

**原因**：当前目录的 `.claude/settings.json` 里有 `env.ANTHROPIC_BASE_URL`。项目级配置优先级高于进程环境变量。

**处理**：

1. 确认启动器带 `--setting-sources user`（本仓库默认带）。
2. 确认没有把 `CLAUDE_CONFIG_DIR` 指回默认的 `~/.claude`。
3. 临时验证：把项目里的 `.claude/settings.json` 改名后重试。

## `unsupported_country_region_territory` / 403

**原因**：直连 OpenAI，没有走代理。

**处理**：

- CLIProxyAPI 的 `config.yaml` 里必须有 `requests.proxy-url: "http://127.0.0.1:7897"`（端口按实际改）。
- 登录时要带 `--login-proxy http://127.0.0.1:7897`。
- WSL 侧确认 `~/.clcd-env.sh` 里的 `HTTPS_PROXY` 指向 `172.x.x.1:17897`，且中继在跑。

## 设备码登录提示“未启用”

```
Enable device code sign-in for Codex ... then run `codex login --device-auth` again.
```

**处理**：不要用 `--codex-device-login`。用标准 OAuth：

```powershell
cli-proxy-api.exe --config config.yaml --codex-login --login-proxy http://127.0.0.1:7897
```

## `cdn` 报 “CLIProxyAPI did not start”

1. 手动运行，看真实错误：

```powershell
& "$env:USERPROFILE\Tools\CLIProxyAPI\app-8.1.1\cli-proxy-api.exe" --config "$env:USERPROFILE\Tools\CLIProxyAPI\config.yaml"
```

2. 常见原因：8317 被占用、`config.yaml` 格式错误、代理端口不对。

## WSL 里 `curl` 报连接超时 / `proxy relay is not reachable`

1. Windows 侧确认中继在跑：

```powershell
Get-NetTCPConnection -LocalPort 17897 -State Listen
```

2. 没有就启动：

```powershell
node "$env:USERPROFILE\Tools\CLIProxyAPI\proxy-relay.js"
```

3. 确认 Clash 在 `127.0.0.1:7897` 监听。改了端口就同步改 `route.env.cmd` 和 `~/.clcd-env.sh`（重新跑 install-wsl.sh）。

## `clcd: provider check failed` / HTTP 400

多为模型不可用。检查：

```powershell
clai config show codex
clai doctor codex --network
```

ChatGPT 账号能用的模型有限（免费档通常只有 `gpt-6-luna` 一系）。用 `clai config set codex model gpt-6-luna` 切换。

## `clcd` 启动后仍提示登录

1. 确认 `~/.codex/auth.json` 存在且权限 600。
2. `codex login status` 应显示 `Logged in using ChatGPT`。
3. 若 token 过期：从 CLIProxyAPI 的凭据重新导入，或重新登录。

## WSL 里命令找不到（`jq` / `socat` / `codex`）

新开的登录 shell 才会包含 `~/.local/bin`。确认：

```bash
echo $PATH | tr ':' '\n' | grep .local
```

包装脚本 `clcd-run` / `clai-run` 会自己 source `~/.clcd-env.sh` 并补 PATH，不依赖交互式 shell。

## 项目文件读写很慢

`clcd` 里的 Claude Code 是 Linux 程序，访问 `/mnt/c`、`/mnt/d` 走 9p 文件系统，比 WSL 原生文件系统慢。长期项目建议放在 `~/projects` 下，用 VS Code 的 WSL 远程模式打开。

## 上游更新后 `clcd` 报语法/命令错误

重新打补丁：

```bash
bash /mnt/d/个人/claude-driven_by_codex/install/patch-upstream.sh ~/claude-driven-ai-providers
```

## 凭据与配额

- 两条路线的配额都算在同一个 ChatGPT 账号上。
- `429` 表示额度用尽，等窗口恢复。
- 查看用量以 ChatGPT/Codex 官方页面为准；网关侧不提供准确计费。
