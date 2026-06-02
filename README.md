# systudy/skills

运维诊断技能库 — 跨 AI Agent 兼容的 Linux 服务器诊断指南。

## 目录

- [ssh-server-diagnostics](ssh-server-diagnostics/) — 通用 Linux 服务器 SSH 全栈诊断

  > 30+ 诊断能力，覆盖健康检查、磁盘、网络、CPU、内存、性能、安全。
  > 支持 Hermes Agent / Claude Code / OpenClaw / Cursor 等任何 AI 编程助手。

## 使用方法

每个 skill 包含：
- `SKILL.md` — 主指南（能力索引、工作流程、安全规则）
- `references/` — 各模块详细诊断步骤（按需加载）
- `scripts/` — 辅助脚本（可在目标服务器上直接运行）

### Hermes Agent

```bash
hermes skills install https://raw.githubusercontent.com/systudy/skills/main/ssh-server-diagnostics/SKILL.md --name ssh-server-diagnostics
# 或
hermes -s ssh-server-diagnostics
```

### Claude Code / OpenClaw / Cursor

直接加载对应 skill 的 Markdown 文件，AI 助手会自动读取 `references/` 目录下的详细文档并按指引执行诊断。
