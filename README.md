# cocodeemo/skills

运维与效率工具技能库 — 跨 AI Agent 兼容的实用技能集合。

> A collection of practical, reusable skills for AI coding agents — DevOps, diagnostics, stock analysis, and more.

---

## 📂 目录 · Contents

### 🔧 运维诊断 · DevOps Diagnostics

- **[ssh-server-diagnostics](ssh-server-diagnostics/)** — 通用 Linux 服务器 SSH 全栈诊断
  > 30+ 诊断能力，覆盖健康检查、磁盘、网络、CPU、内存、性能、安全。
  > 支持 Hermes Agent / Claude Code / OpenClaw / Cursor 等任何 AI 编程助手。
  >
  > *30+ diagnostic capabilities: health check, disk, network, CPU, memory, performance, security. Works with any AI coding assistant.*

### ⚡ 效率工具 · Productivity

- **[bilibili-video-summary](bilibili-video-summary/)** — B 站视频 AI 总结
  > 输入 B 站链接 → 自动下载音频 → faster-whisper ASR 转写 → AI 深度总结。
  > 内置双超时退避 + 断点续传，实时进度输出。
  >
  > *Bilibili video → audio download → Whisper ASR → AI summary. Dual timeout fallback + resume.*

### 📊 股票分析 · Stock Analysis

- **[cocodeemo/stock-roundtable](https://github.com/cocodeemo/stock-roundtable)** — 股票圆桌辩论（独立 repo）
  > 6 大投资流派同时分析一支股票，自动抓行情+财报+产业链格局，输出杂志级 HTML 报告。
  > 已从本仓库迁移至独立 repo，请移步获取最新版本。
  >
  > *6 investment schools debate a stock with real-time data + industry context. Moved to independent repo.*

---

## 🚀 使用方法 · Usage

每个 skill 包含 · Each skill contains：
- `SKILL.md` — 主指南 · Main guide
- `references/` — 参考资料与踩坑记录 · References & pitfalls
- `scripts/` — 可直接运行的脚本 · Runnable scripts

### Hermes Agent

```bash
# 安装 · Install
hermes skills install https://raw.githubusercontent.com/cocodeemo/skills/main/<skill-name>/SKILL.md --name <skill-name>
```

### Claude Code / Cursor

直接加载对应 skill 的 Markdown 文件，AI 助手会自动读取 `references/` 目录下的文档并执行。

*Load the skill's Markdown file — the AI assistant will auto-discover references/ and scripts/.*

---

<p align="center">
  <sub>⚠️ Demo 报告由 AI 自动生成，仅供参考，不构成投资建议。</sub><br>
  <sub>⚠️ Demo reports are AI-generated for reference only. Not investment advice.</sub>
</p>
