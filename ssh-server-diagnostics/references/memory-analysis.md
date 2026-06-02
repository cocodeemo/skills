---
name: memory-analysis
description: 内存使用分析与 OOM 事件诊断。覆盖内存泄漏排查、Swap 分析、OOM Killer 事件定位。
version: 1.0.0
---

# 内存分析与 OOM 诊断

覆盖内存使用排查、内存泄漏判定、Swap 分析和 OOM 事件诊断。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动执行任何内存清理或进程终止操作**。
>
> 清理 cache、kill 进程等操作仅作为参考提供给用户。

## 适用场景

### 用户可能的问题表述

**内存不足类**：
- "内存不够了"、"内存满了"
- "内存泄漏"、"内存持续增长"
- "swap 用了很多"

**OOM 类**：
- "进程被杀了"、"OOM 了"
- "服务器异常重启"、"oom-killer"
- "dmesg 看到 out of memory"

---

## 诊断步骤

### 步骤 1：内存总览

```bash
echo '=== 内存与 Swap 总览 ===' && \
free -h && \
echo '' && \
echo '=== 内存详细指标 ===' && \
cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|SwapCached|Dirty|Writeback|AnonPages|Mapped|PageTables|Slab|SReclaimable|SUnreclaim|KernelStack' && \
echo '' && \
echo '=== NUMA 内存分配 ===' && \
numastat 2>/dev/null || echo 'NUMA 不可用'
```

**输出解读**：

| 指标 | 正常 | 警告 | 异常 |
|------|------|------|------|
| MemAvailable | > 20% of total | 10% ~ 20% | < 10% |
| Swap 使用 | 0 | > 0 少量 | > 50% + 可用内存低 |
| SUnreclaim (Slab) | < 2G | 2G ~ 5G | > 5G 且持续增长 |
| Dirty | < 1% of total | 1% ~ 5% | > 5%（IO 瓶颈） |

**关键判断**：
- **available 充足，used 高** → 大部分是 Cache/Buffer，正常
- **available 低 + Swap 高** → 🔴 真正内存不足
- **SUnreclaim 持续增长** → 内核 slab 泄漏
- **AnonPages 持续增长** → 应用内存泄漏

### 步骤 2：进程内存消耗详情

```bash
echo '=== RSS 内存占用 Top 10 ===' && \
ps aux --sort=-%mem | head -11 && \
echo '' && \
echo '=== 按用户聚合内存 ===' && \
ps aux | awk 'NR>1 {arr[$1]+=$6} END {for(i in arr) printf "%-20s %.1f MB\n", i, arr[i]/1024}' | sort -rn -k2 | head -10 && \
echo '' && \
echo '=== 共享内存 ===' && \
ipcs -m 2>/dev/null | head -15
```

**输出解读**：
- **RSS 持续高** → 进程实际占用物理内存
- **VSZ 高但 RSS 低** → 已分配但未实际使用的虚拟内存，通常无害
- 按用户聚合可以快速定位是哪个应用占用最多内存

### 步骤 3：内存泄漏排查

```bash
echo '=== 进程内存增长趋势（需连续采集） ===' && \
# 第一次采集
ps -eo pid,rss,vsz,cmd --sort=-rss | head -10 && \
echo '等待 5 秒...' && \
sleep 5 && \
# 第二次采集
ps -eo pid,rss,vsz,cmd --sort=-rss | head -10
```

> 对比两次采集中的 RSS 值，如果某个进程 RSS 持续增长且不回落，可能内存泄漏。

进一步确认：
```bash
echo '=== /proc/<PID>/smaps 摘要 ===' && \
# 对可疑 PID 查看内存段
PID=<可疑PID> && \
cat /proc/$PID/status 2>/dev/null | grep -E 'VmRSS|VmSize|VmPeak|Threads' && \
echo '' && \
echo '=== 进程打开文件数 ===' && \
ls -l /proc/$PID/fd 2>/dev/null | wc -l
```

### 步骤 4：OOM 事件诊断

```bash
echo '=== dmesg OOM 日志 ===' && \
dmesg -T 2>/dev/null | grep -iE 'oom|out of memory|killed' | tail -20 || \
dmesg | grep -iE 'oom|out of memory|killed' | tail -20 && \
echo '' && \
echo '=== journalctl OOM 日志 ===' && \
journalctl -k 2>/dev/null | grep -iE 'oom|out of memory|killed' | tail -20 || echo 'journalctl 不可用'
```

**OOM 日志解读**：
```
[timestamp] Out of memory: Killed process <PID> (进程名)
  total-vm:xxxkB, anon-rss:xxxkB, file-rss:xxxkB, shmem-rss:xxxkB
  oom_score_adj: 0
```
- `Killed process` → 被杀的进程名
- `anon-rss` → 匿名页 RSS（实际使用物理内存）
- `oom_score_adj` → 调整因子，正值更易被 kill

### 步骤 5：Swap 分析（有 Swap 时）

```bash
echo '=== Swap 使用详情 ===' && \
swapon --show 2>/dev/null && \
echo '' && \
echo '=== Swap 占用进程 Top 10 ===' && \
for pid in $(ls /proc/ | grep -E '^[0-9]+$' | sort -n); do \
  swap=$(awk '/Swap:/ {print $2}' /proc/$pid/status 2>/dev/null); \
  if [ -n "$swap" ] && [ "$swap" -gt 0 ] 2>/dev/null; then \
    cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' | head -c 80); \
    echo "$swap kB - PID $pid - $cmd"; \
  fi; \
done 2>/dev/null | sort -rn | head -10
```

---

## 报告格式

```
### 🟢 内存状态
| 指标 | 值 | 判定 |
|------|-----|------|

### 🔴 / 🟡 发现问题
- 进程 xxx RSS 持续增长

### 🟢 / 🔴 OOM 事件
- 最近 N 天无 OOM 事件
- 或：在 [时间] OOM 杀死了进程 [xxx]，原因：[xxx]

### ✅ 建议
```
