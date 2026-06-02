---
name: health-check
description: 服务器全面健康检查——一次性采集所有关键指标，输出结构化健康报告。
version: 1.0.0
---

# 服务器全面健康检查

适用于用户说"看看这台服务器怎么样"时的默认诊断。覆盖系统信息、CPU、内存、磁盘、网络、进程、服务、日志等核心维度。

## 诊断步骤

### 步骤 1：验证连通性

```bash
# 快速验证服务器可达
hostname
uptime
```

### 步骤 2：采集系统概览

```bash
echo '========== 系统信息 ==========' && \
echo '主机名: '$(hostname) && \
echo 'OS: '$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"') && \
echo '版本: '$(cat /etc/os-release 2>/dev/null | grep VERSION_ID | cut -d= -f2 | tr -d '"') && \
echo '内核: '$(uname -r) && \
echo '架构: '$(uname -m) && \
echo '运行时间: '$(uptime -p) && \
echo '当前负载: '$(uptime | awk -F'load average:' '{print $2}')
```

### 步骤 3：CPU 状态

```bash
echo '========== CPU ==========' && \
echo '核数: '$(nproc) && \
lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core|MHz' | head -6 && \
echo '--- 1分钟负载趋势 ---' && \
uptime && \
echo '--- 每个 CPU 使用率 ---' && \
mpstat -P ALL 1 1 2>/dev/null | tail -n +4
```

### 步骤 4：内存状态

```bash
echo '========== 内存 ==========' && \
free -h && \
echo '--- 内存详细 ---' && \
cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Dirty'
```

### 步骤 5：磁盘状态

```bash
echo '========== 磁盘 ==========' && \
echo '--- 分区表 ---' && \
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null && \
echo '' && \
echo '--- 使用率 ---' && \
df -h && \
echo '' && \
echo '--- inode 使用率 ---' && \
df -i | head -5 && \
echo '' && \
echo '--- 磁盘 IO 健康 ---' && \
iostat -x 1 2 2>/dev/null | tail -10
```

### 步骤 6：网络状态

```bash
echo '========== 网络 ==========' && \
echo '--- 网卡 ---' && \
ip -br addr && \
echo '' && \
echo '--- 路由 ---' && \
ip route show default && \
echo '' && \
echo '--- 监听端口 ---' && \
ss -tlnp 2>/dev/null && \
echo '' && \
echo '--- DNS 配置 ---' && \
cat /etc/resolv.conf 2>/dev/null
```

### 步骤 7：进程与服务

```bash
echo '========== 进程与服务 ==========' && \
echo '总进程数: '$(ps aux | wc -l) && \
echo '--- 资源占用 Top 10 ---' && \
ps aux --sort=-%cpu | head -11 && \
echo '' && \
echo '--- 内存占用 Top 5 ---' && \
ps aux --sort=-%mem | head -6 && \
echo '' && \
echo '--- 僵尸进程 ---' && \
ps aux | awk '$8=="Z" || $8=="Z+"' | grep -v grep || echo '无僵尸进程' && \
echo '' && \
echo '--- 当前登录用户 ---' && \
w
```

### 步骤 8：系统日志与时间

```bash
echo '========== 系统日志与时间 ==========' && \
echo '--- 系统时间 ---' && \
date && \
echo '' && \
echo '--- NTP 同步状态 ---' && \
chronyc tracking 2>/dev/null | head -3 || ntpq -p 2>/dev/null | head -3 || echo 'NTP 未配置或不可用' && \
echo '' && \
echo '--- 内核错误日志（最近 20 条） ---' && \
dmesg -T 2>/dev/null | grep -iE 'error|fail|panic|oom|killed|hung' | tail -20 || dmesg | grep -iE 'error|fail|panic|oom|killed|hung' | tail -20 && \
echo '' && \
echo '--- 系统错误日志（最近 10 条） ---' && \
journalctl -p err -b --no-pager 2>/dev/null | tail -10 || echo 'journalctl 不可用'
```

### 步骤 9：Docker 容器（如有）

```bash
echo '========== Docker ==========' && \
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || echo 'Docker 未安装或未运行'
```

### 步骤 10：安全概览

```bash
echo '========== 安全概览 ==========' && \
echo '--- 最近登录 ---' && \
last -10 2>/dev/null | head -5 && \
echo '' && \
echo '--- 失败登录 ---' && \
lastb 2>/dev/null | head -5 || echo '无失败登录记录' && \
echo '' && \
echo '--- 防火墙状态 ---' && \
ufw status 2>/dev/null || systemctl is-active firewalld 2>/dev/null | xargs -I{} echo 'firewalld:'{} || echo '未检测到防火墙' && \
echo '' && \
echo '--- 关键服务状态 ---' && \
for s in sshd cron rsyslog systemd-journald docker; do \
  systemctl is-active $s 2>/dev/null | xargs -I{} echo "$s: {}"; \
done
```

## 输出解读

### 关键阈值

| 指标 | 正常 | 警告 | 异常 |
|------|------|------|------|
| CPU 负载 / 核数 | < 0.7 | 0.7 ~ 1.0 | > 1.0 |
| 内存使用率 | < 70% | 70% ~ 90% | > 90% |
| 磁盘使用率 | < 80% | 80% ~ 90% | > 90% |
| 磁盘 IO %util | < 30% | 30% ~ 70% | > 70% |
| inode 使用率 | < 70% | 70% ~ 90% | > 90% |
| Swap 使用率 | 0% | > 0% | > 50%（无 avail） |
| 僵尸进程 | 0 | — | ≥ 1 |

### 异常判断规则

- **CPU 高**：load average / 核数 > 0.7，且 %idle < 30%
- **内存不足**：available < 20%，或 Swap 大量使用且 available 低
- **磁盘满**：任意分区使用率 > 90%
- **磁盘 IO 瓶颈**：%util > 70% 且 await > 30ms
- **网络异常**：监听端口异常、默认路由丢失
- **时间不同步**：与标准时间偏差 > 5 秒

## 报告格式

```
## 服务器诊断报告 — <IP>

### 🟢 系统概览
| 项目 | 值 |
|------|-----|

### 🟢 CPU 状态
...

### 🟢 内存状态
...

### 🟡 磁盘状态
...

### 🟢 网络状态
...

### 🟢 进程与服务
...

### 🔴 发现的问题
1. xxx — 建议：xxx
2. xxx — 建议：xxx

### ✅ 总体评价
服务器整体状态 [良好/一般/存在问题]
```
