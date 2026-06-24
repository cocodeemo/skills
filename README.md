# cocodeemo/skills

运维与效率工具技能库 — 跨 AI Agent 兼容的实用技能集合。

## 目录

### 运维诊断

- [ssh-server-diagnostics](ssh-server-diagnostics/) — 通用 Linux 服务器 SSH 全栈诊断

  > 30+ 诊断能力，覆盖健康检查、磁盘、网络、CPU、内存、性能、安全。
  > 支持 Hermes Agent / Claude Code / OpenClaw / Cursor 等任何 AI 编程助手。

### 效率工具

- [bilibili-video-summary](bilibili-video-summary/) — B 站视频 AI 总结

  > 输入 B 站链接 → 自动下载音频 → faster-whisper ASR 转写 → AI 深度总结。
  > 内置双超时退避 + 断点续传，实时进度输出，无需人工盯进度。

## 使用方法

每个 skill 包含：
- `SKILL.md` — 主指南（能力索引、工作流程、执行策略）
- `references/` — 参考资料与踩坑记录
- `scripts/` — 可直接运行的 Python 脚本

### Hermes Agent

```bash
# 安装技能
hermes skills install https://raw.githubusercontent.com/cocodeemo/skills/main/<skill-name>/SKILL.md --name <skill-name>
```

### Claude Code / Cursor

直接加载对应 skill 的 Markdown 文件，AI 助手会自动读取 `references/` 目录下的文档并执行。
