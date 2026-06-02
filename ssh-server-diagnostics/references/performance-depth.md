---
name: performance-depth
description: 性能深度分析——CPU 火焰图、系统调用热点、调度延迟、中断均衡、文件 IO 追踪。
version: 1.0.0
---

# 性能深度分析

覆盖 CPU 火焰图采样、系统调用热点分析、调度延迟排查、中断均衡分析和文件 IO 追踪。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析）。安装 perf/bcc 等工具不影响系统运行，但执行采样会消耗少量 CPU。

## 适用场景

- "CPU 热点在哪里"、"perf 分析"
- "系统调用很慢"、"strace 分析"
- "进程响应慢"、"调度延迟"
- "软中断很高"、"中断不均衡"
- "文件 IO 慢"、"fsync 慢"

---

## 诊断步骤

### 步骤 1：安装诊断工具

```bash
echo '=== 检查性能工具 ===' && \
for cmd in perf strace iostat mpstat pidstat; do \
  which $cmd 2>/dev/null | xargs -I{} echo "$cmd: {}" || echo "$cmd: 未安装"; \
done
```

### 步骤 2：CPU 热点采样（perf）

```bash
echo '=== CPU 采样热点 Top 20（10 秒） ===' && \
perf record -a -g --sleep 10 -- 2>/dev/null && \
perf report -n --stdio 2>/dev/null | head -30 || \
echo 'perf 不可用，尝试安装: sudo yum install -y perf 或 sudo apt install -y linux-tools-$(uname -r)'
```

**输出解读**：
- `Children` 列高的函数 → 调用链上的热点
- 内核函数如 `tcp_v4_rcv` 高 → 网络密集型
- 用户态函数高 → 应用层瓶颈

### 步骤 3：系统调用热点

```bash
echo '=== 系统调用频率 Top 10 ===' && \
perf top -e syscalls:sys_enter_* -a -b --stdio 2>/dev/null | head -15 || \
strace -c -p 1 -S time 2>&1 &
sleep 5 && kill %1 2>/dev/null || echo 'strace 不可用' && \
echo '' && \
echo '=== 系统调用耗时 Top ===' && \
perf stat -e syscalls:sys_enter_*,syscalls:sys_exit_* -a -- sleep 3 2>&1 | tail -10 || echo ''
```

### 步骤 4：调度延迟和上下文切换

```bash
echo '=== 上下文切换统计 ===' && \
vmstat 1 3 | tail -2 && \
echo '' && \
echo '=== 进程上下文切换 Top 10 ===' && \
pidstat -w 1 3 2>/dev/null | tail -12 && \
echo '' && \
echo '=== 进程抢占、迁移统计 ===' && \
cat /proc/sched_debug 2>/dev/null | grep -E 'nr_switches|nr_voluntary_switches|nr_involuntary_switches' | head -5 || echo 'sched_debug 不可用' && \
echo '' && \
echo '=== 可运行队列等待 ===' && \
cat /proc/schedstat 2>/dev/null | awk '{print "CPU等待时间: " $2 " ns"}' | head -4 || echo 'schedstat 不可用'
```

### 步骤 5：中断均衡分析

```bash
echo '=== 中断分布 ===' && \
cat /proc/interrupts | head -20 && \
echo '' && \
echo '=== 软中断分布 ===' && \
cat /proc/softirqs | head -15 && \
echo '' && \
echo '=== 哪个 CPU 处理软中断多 ===' && \
cat /proc/softirqs | head -1 && \
cat /proc/softirqs | grep -iE 'NET_RX|NET_TX' | head -3
```

**输出解读**：
- 所有中断集中在 CPU0 → 中断不均衡
- `NET_RX` 在某 CPU 上特别高 → 网卡队列 RSS 配置不合理
- 可安装 `irqbalance` 服务自动均衡

### 步骤 6：文件 IO 追踪

```bash
echo '=== IO 等待进程 Top 10 ===' && \
iotop -b -n 1 2>/dev/null | head -12 || echo 'iotop 未安装' && \
echo '' && \
echo '=== 文件 IO 延迟进程 ===' && \
pidstat -d 1 3 2>/dev/null | tail -12 && \
echo '' && \
echo '=== 各进程文件描述符数 ===' && \
for pid in $(ps -eo pid --sort=-pid | head -20 | tail -10); do \
  fd_count=$(ls /proc/$pid/fd 2>/dev/null | wc -l); \
  cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' | head -c 60); \
  echo "PID $pid FD=$fd_count $cmd"; \
done | sort -t= -k2 -rn | head -10
```

**输出解读**：
- FD 数 > 1000 且持续增长 → 文件描述符泄漏
- `pidstat -d` 的 `kB_rd/s` 和 `kB_wr/s` 高 → IO 密集进程

---

## 报告格式

```
### 🟢 性能概况
工具可用性: perf ✓ / strace ✓ / iotop ✗

### 🔴 / 🟡 发现问题
- CPU 热点: xxx 函数占 xx%
- 中断集中在 CPU0
- 进程 PID xxx FD 数异常

### ✅ 建议
```
