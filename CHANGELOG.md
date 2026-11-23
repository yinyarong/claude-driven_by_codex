# Changelog

## 0.1.0 — 2026-11-23

- 首次发布。
- 路线 1：`cdn` 通过 CLIProxyAPI 在 Windows 原生 Claude Code 中使用 Codex 订阅。
- 路线 2：`clcd` 在 WSL 中运行上游 `claude-driven-ai-providers` 的 Bash 桥，含 Linux 补丁脚本。
- Windows → WSL 的 TCP 中继，仅绑定 WSL 虚拟网卡。
- 两个启动器都使用 `--setting-sources user`，避免项目级 `.claude/settings.json` 覆盖网关配置。
- 无密钥安装：本地客户端密钥由安装器生成，只写入仓库外的私有文件。
- 支持从 CLIProxyAPI 凭据导入 Codex CLI 的 `auth.json`。
