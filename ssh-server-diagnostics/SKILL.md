---
name: ssh-server-diagnostics
description: >
  通用 Linux 服务器全栈诊断——通过 SSH 连接任意 Linux 服务器，进行全面健康检查、
  磁盘分析、网络诊断、性能分析、内存分析和安全审计。支持任何发行版（Ubuntu/CentOS/Debian/Alibaba Cloud Linux 等），
  覆盖 30+ 诊断能力，按需加载。
  
  触发词：ssh、服务器、机器、主机、检查、诊断、看看、状态、健康、远程、
  磁盘、内存、CPU、网络、端口、容器、Docker、安全、日志、进程。
version: 2.1.0
agent: any
---

# 通用 Linux 服务器 SSH 全栈诊断

> **跨 AI Agent 兼容**：本指南适用于 Hermes Agent、Claude Code、OpenClaw、Cursor 等
> 任何能通过 SSH 执行命令的 AI 编程助手。所有参考文档在仓库的 `references/` 目录下，
> 助手工具应直接读取对应文件获取完整诊断步骤。
>
> 使用方法：
> - **Hermes Agent**: `hermes -s ssh-server-diagnostics` 或 `/skill ssh-server-diagnostics`
> - **Claude Code / OpenClaw / Cursor**: 直接加载此 Markdown 文件，按指引读取 `references/` 目录
>   下的具体模块文档，通过终端执行 SSH 命令对远程服务器进行诊断。

通过 SSH 连接任意 Linux 服务器进行全栈运维诊断，输出结构化健康报告。

## 前置条件

用户提供 SSH 连接信息（IP/域名 + 端口 + 用户名 + 认证方式）。连接格式：

```bash
ssh -i <密钥路径> -p <端口> <用户名>@<IP> "<command>"
```

**用户需要提供**：
- 服务器 IP 或域名
- SSH 端口（默认 22）
- 用户名（默认 root）
- 认证方式（密钥路径或密码）

## 工作流程

### Step 0: 确认连接信息

如果用户没有指定完整连接信息，逐一询问：
1. IP 或域名
2. SSH 端口（默认 22）
3. 用户名（默认 root）
4. 密钥路径（如果有）

如果用户之前已经提供过，优先复用历史连接信息。

### Step 1: 验证连通性

正式诊断前，先执行一次快速连接验证：

```bash
ssh -i <KEY> -p <PORT> -o ConnectTimeout=10 <USER>@<IP> "hostname && uptime"
```

如果连接失败，告知用户错误原因并停止。

### Step 2: 理解用户意图

分析用户的自然语言请求，从下方 **能力索引表** 中匹配 1~3 个最相关的模块。

**匹配策略**：
1. 根据关键词缩小到大类
2. 在子模块中定位具体能力
3. 如果用户意图模糊（如"看看这台服务器"），默认执行 `health-check` 全面检查

### Step 3: 加载模块详细文档

找到目标模块后，读取仓库中对应的 `references/` 文件（如 `references/health-check.md`），获取完整的诊断步骤和命令。

### Step 4: 执行诊断

按照模块文档中的诊断步骤执行。所有命令通过 SSH 发送到远程服务器。

#### 安全原则 ⚠️

**以下操作 AI 禁止直接执行，仅提供命令文本供用户参考**：

| 类别 | 禁止直接执行的命令 |
|------|-------------------|
| 重启/关机 | `reboot` `shutdown` `poweroff` `init 0` |
| 磁盘操作 | `mkfs.*` `fdisk -w` `parted` 写操作、`pvremove` `lvremove` `vgremove` |
| 文件删除 | `rm -rf` 删除非临时目录 |
| 防火墙修改 | `iptables -F` `ufw disable` `firewall-cmd` 写操作 |
| 服务停用 | `systemctl stop/disable` 关键服务 |
| 配置修改 | 修改系统配置文件、grub、网络配置 |

### Step 5: 输出结果

按模块文档中的报告格式输出诊断结论。报告格式：

```
## 服务器诊断报告 — <IP>

### 🟢 正常 / 🟡 警告 / 🔴 异常 项

| 检查项 | 结果 | 详情 |
|--------|------|------|

### ✅ 建议 / ⚠️ 注意事项
```

**发行版差异自适应**：遇到命令不可用时，自动尝试替代方案（如 `yum` vs `dnf`、`netstat` vs `ss`、`service` vs `systemctl`）。

---

## 能力索引

### 全面体检（1 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `health-check` | 服务器全面健康检查 | 看看、检查、状态、健康、体检、全部 | `references/health-check.md` |

### 磁盘与存储（3 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `disk-analysis` | 磁盘空间、IO 与文件系统 | 磁盘满、空间不足、No space、分区、df、iostat、IO高、iowait、inode、挂载、fstab、只读 | `references/disk-analysis.md` |
| `disk-depth` | LVM 逻辑卷与磁盘健康 | LVM、扩容、pvcreate、vg、lv、SMART、坏块、磁盘健康 | `references/disk-depth.md` |
| `disk-partition` | 磁盘分区与文件系统管理 | 分区、fdisk、parted、格式化、挂载、新磁盘 | `references/disk-depth.md` |

### 网络诊断（3 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `network-basic` | 网络连通性与延迟 | ping不通、端口不通、延迟、丢包、连通性、DNS、curl | `references/network-diagnosis.md` |
| `network-connection` | 连接状态与端口分析 | 连接数、TIME_WAIT、端口占用、ss、netstat、防火墙 | `references/network-diagnosis.md` |
| `latency-diagnostics` | 网络延迟与丢包深度排查 | 延迟高、丢包、TCP重传、网络卡、mtr、ethtool、Ring Buffer、softnet、conntrack | `references/latency-diagnostics.md` |

### CPU 与进程（2 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `cpu-analysis` | CPU 使用率与负载 | CPU 高、负载高、top、load average、mpstat | `references/cpu-analysis.md` |
| `process-analysis` | 进程/线程深度分析 | 进程、僵尸、D 状态、卡住、top、ps、lsof | `references/cpu-analysis.md` |

### 性能深度分析（4 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `flamegraph` | CPU 火焰图与热点采样 | 火焰图、CPU热点、perf、调用栈、采样 | `references/performance-depth.md` |
| `syscall-analysis` | 系统调用与调度延迟 | 系统调用、strace、上下文切换、调度延迟、sched | `references/performance-depth.md` |
| `irq-analysis` | 中断均衡与软中断 | 中断不均衡、软中断、NET_RX、ksoftirqd、irqbalance | `references/performance-depth.md` |
| `io-trace` | 文件 IO 延迟与进程 IO 追踪 | 文件IO、fsync、iotop、pidstat、文件描述符泄漏、FD泄漏 | `references/performance-depth.md` |

### 内存分析（2 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `memory-usage` | 内存使用与泄漏 | 内存不足、内存高、swap、free、缓存、泄漏 | `references/memory-analysis.md` |
| `oom-diagnosis` | OOM 事件诊断 | OOM、进程被杀、oom-killer、内存溢出、dmesg | `references/memory-analysis.md` |

### 服务与系统（2 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `service-check` | 服务/计划任务/系统日志 | 服务、systemctl、cron、journalctl、dmesg | `references/service-system.md` |
| `security-audit` | 安全审计与登录检查 | 安全、登录、last、ssh、审计、端口暴露 | `references/service-system.md` |

### 安全基线（2 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `security-hardening` | 安全基线检查与加固 | 等保、安全基线、密码策略、SSH加固、SELinux、文件权限 | `references/security-hardening.md` |
| `security-logs` | 异常检测与入侵排查 | 异常登录、暴力破解、rootkit、隐藏进程、后门 | `references/security-hardening.md` |

### 软件审计（2 项）

| 模块 ID | 能力 | 匹配关键词 | 文档 |
|---------|------|-----------|------|
| `package-audit` | 软件包版本与安全更新 | 软件版本、安全更新、yum update、已安装包、组件版本 | `references/package-audit.md` |
| `cve-check` | CVE 漏洞快速筛查 | CVE、漏洞、高危、已知漏洞、openssl、ssh | `references/package-audit.md` |

---

## 场景快速导航

| 问题现象 | 首选模块 | 备选模块 |
|---------|---------|---------|
| "看看这台服务器怎么样" | `health-check` | — |
| "磁盘满了" | `disk-analysis` | `disk-depth` |
| "磁盘IO高/很慢" | `disk-analysis`（IO 部分） | `io-trace` |
| "新加的磁盘看不到" | `disk-depth` | `disk-partition` |
| "LVM 扩容" | `disk-depth` | `disk-partition` |
| "网络不通/端口不通" | `network-basic` | — |
| "连接数太多" | `network-connection` | — |
| "网络延迟高/丢包" | `latency-diagnostics` | `network-basic` |
| "TCP 重传很多" | `latency-diagnostics` | — |
| "CPU 100%/负载高" | `cpu-analysis` | `process-analysis` |
| "CPU 热点在哪里" | `flamegraph` | `syscall-analysis` |
| "系统调用很慢" | `syscall-analysis` | `flamegraph` |
| "进程卡住了/死掉了" | `process-analysis` | `memory-usage` |
| "内存不够/很高" | `memory-usage` | `oom-diagnosis` |
| "进程被杀了/OOM" | `oom-diagnosis` | `memory-usage` |
| "软中断很高" | `irq-analysis` | — |
| "文件 IO 慢" | `io-trace` | `disk-analysis` |
| "文件描述符泄漏" | `io-trace` | — |
| "系统日志/报错" | `service-check` | — |
| "安全审计/登录记录" | `security-audit` | `security-hardening` |
| "等保/安全加固" | `security-hardening` | — |
| "检查软件版本" | `package-audit` | — |
| "安全更新/漏洞" | `cve-check` | `package-audit` |

---

## SSH 命令模板

所有诊断命令使用以下 SSH 模板：

```bash
ssh -i <KEY> -p <PORT> -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 <USER>@<IP> "<command>"
```

多命令合并：

```bash
ssh -i <KEY> -p <PORT> <USER>@<IP> "\
echo '=== title ===' && \
cmd1 && \
echo '=== title2 ===' && \
cmd2"
```

---

## 发行版差异速查

| 操作 | CentOS/RHEL 7 | CentOS/RHEL 8+ | Ubuntu/Debian |
|------|--------------|---------------|---------------|
| 包管理器 | `yum` | `dnf`（`yum` 别名） | `apt` |
| 防火墙 | `iptables`/`firewalld` | `firewalld` | `ufw` |
| 网络管理 | `network-scripts` | `NetworkManager` | `netplan`/`ifupdown` |
| 连接查看 | `netstat` | `ss` | `ss`（apt 装 netstat） |
| 日志轮转 | cron 触发 | systemd timer | logrotate |
