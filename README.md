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

- **[stock-roundtable](stock-roundtable/)** — 股票圆桌辩论
  > 6 大投资流派（格雷厄姆/巴菲特/费雪/笨韭/莫大/龟龟）同时分析一支股票。
  > 自动抓腾讯行情 + AKShare 财报 + 东财交叉验证 + 送转股除权 + 52 周前复权 K 线。
  > 产业链格局注入（v4-pro 自动分析供给瓶颈/需求爆发）。
  > 输出 WorkBuddy 同款 HTML 报告，含六框架评分对比表 + 彩色进度条 + 数据校验警告 + 跳过角色提示。
  > 支持 A 股/港股、`--rounds`、`--model` 参数。
  >
  > *6 investment schools debate a stock. Auto-fetches real-time quotes (Tencent+EastMoney), financials (AKShare), dividend adjustments, industry context (LLM). Magazine-grade HTML report.*

  #### 🎭 Demo

  | Demo | 股票 | 看点 · Highlight |
  |------|------|-----------------|
  | [中际旭创 (300308)](stock-roundtable/demos/中际旭创_圆桌辩论报告.html) | AI 光模块龙头 | 6 框架分裂：费雪 82 分力挺 vs 格雷厄姆 0 分淘汰。同一个事实，不同哲学完全不同结论 |
  | | AI optical module leader | Fisher 82 vs Graham 0 — same facts, six different conclusions |
  | [九丰能源 (605090)](stock-roundtable/demos/九丰能源_圆桌辩论报告.html) | LNG 能源贸易商 | 6 框架一致看空，均分仅 39 分。当所有人说不时的威力 |
  | | LNG energy trader | All 6 schools agree: don't buy (avg 39/100). The power of consensus |

  > 💡 下载 HTML 文件后在浏览器中打开（GitHub 不渲染自定义 HTML）
  >
  > 💡 *Download the HTML file and open it in your browser. GitHub does not render custom HTML.*

---

## 🚀 使用方法 · Usage

每个 skill 包含 · Each skill contains：
- `SKILL.md` — 主指南 · Main guide
- `references/` — 参考资料与踩坑记录 · References & pitfalls
- `scripts/` — 可直接运行的脚本 · Runnable scripts
- `demos/` — HTML 报告示例 · Demo reports *(stock-roundtable only)*

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
