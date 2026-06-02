# SSH 服务器全栈诊断

> 跨 AI Agent 通用的 Linux 服务器全栈诊断指南。适用于 Hermes Agent、Claude Code、OpenClaw、Cursor 等任何能通过 SSH 执行命令的 AI 编程助手。

通过 SSH 连接任意 Linux 服务器，进行全面健康检查、磁盘分析、网络诊断、性能分析、内存分析和安全审计。支持任何发行版（Ubuntu/CentOS/Debian/Alibaba Cloud Linux 等），覆盖 30+ 诊断能力。

## 使用方法

### 工作流

1. 用户提供 SSH 连接信息（IP、端口、用户名、密钥）
2. 阅读 [`SKILL.md`](SKILL.md) 了解整体流程和能力索引
3. 根据需求选择对应模块，读取 `references/` 下的详细诊断文档
4. 按模块文档执行 SSH 诊断命令

### 能力索引

| 模块 | 文件 | 场景 |
|------|------|------|
| 全面体检 | `references/health-check.md` | "看看服务器怎么样" |
| 磁盘分析 | `references/disk-analysis.md` | 磁盘满、IO 高 |
| 磁盘深度 | `references/disk-depth.md` | LVM、SMART、分区 |
| 网络诊断 | `references/network-diagnosis.md` | 连通性、端口、连接数 |
| 延迟诊断 | `references/latency-diagnostics.md` | 延迟高、丢包、TCP重传 |
| CPU/进程 | `references/cpu-analysis.md` | CPU 高、僵尸进程、D状态 |
| 内存/OOM | `references/memory-analysis.md` | 内存泄漏、OOM |
| 性能深度 | `references/performance-depth.md` | 火焰图、系统调用、中断 |
| 服务/日志 | `references/service-system.md` | 服务状态、安全审计 |
| 安全基线 | `references/security-hardening.md` | 等保、安全加固 |
| 软件审计 | `references/package-audit.md` | 版本、CVE、安全更新 |

### 辅助脚本

`scripts/` 目录下包含可直接在目标服务器上运行的诊断脚本：

| 脚本 | 用途 |
|------|------|
| `common.sh` | 共享工具函数库 |
| `output.sh` | 输出格式化 |
| `install-deps.sh` | 自动安装诊断工具依赖 |
| `network-latency-monitor.sh` | 网络延迟长期监控 |
| `sched-latency-monitor.sh` | 进程调度延迟监控 |
| `file-io-trace.sh` | 文件 IO 追踪 |
| `fs-latency-collect.sh` | 文件系统延迟采集 |
| `collect_memory_leak.sh` | 内存泄漏数据采集 |
| `collect_oom_info.sh` | OOM 事件信息采集 |
| `parse_oom_events.py` | OOM 日志解析器 |
| `parse_memory_leak.py` | 内存泄漏分析器 |
| `security_harden.sh` | 安全基线检查与加固 |

## 安全原则

所有诊断命令设计为**只读操作**——仅查看、分析，不执行任何破坏性操作。以下操作 AI 禁止直接执行，仅提供命令文本供用户参考：

- 重启/关机 (`reboot`, `shutdown`)
- 磁盘写操作 (`mkfs`, `fdisk -w`, `parted`)
- 文件删除 (`rm -rf`)
- 防火墙修改 (`iptables -F`, `ufw disable`)
- 服务停用 (`systemctl stop/disable` 关键服务)
- 系统配置修改

## 依赖

目标服务器需要安装以下工具（可通过 `install-deps.sh` 自动安装）：

- 核心：`sysstat`, `iproute2`, `openssh-client`, `curl`, `wget`
- 网络：`dnsutils`, `traceroute`, `mtr`
- 存储：`smartmontools`, `iotop`
- 性能：`perf`, `strace`
