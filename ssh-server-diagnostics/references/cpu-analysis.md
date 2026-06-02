---
name: cpu-analysis
description: CPU 使用率、进程负载与进程状态分析。覆盖 CPU 高排查、load 分析、进程状态诊断、僵尸进程清理。
version: 1.0.0
---

# CPU 与进程分析

覆盖 CPU 使用率排查、系统负载分析、进程状态诊断和僵尸进程检查。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动 kill 进程或修改进程参数**。
>
> 杀掉进程、调整进程优先级等操作仅作为参考提供给用户。

## 适用场景

### 用户可能的问题表述

**CPU 高类**：
- "CPU 100%"、"CPU 满了"
- "负载很高"、"load average 很高"
- "服务器很卡"、"响应慢"

**进程类**：
- "进程卡住了"、"D 状态进程"
- "有僵尸进程"、"进程杀不掉"
- "进程占 CPU 很高"、"哪个进程在吃 CPU"

---

## 诊断步骤

### 步骤 1：CPU 总体状态

```bash
echo '=== CPU 基本信息 ===' && \
echo '核数: '$(nproc) && \
lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core|MHz' | head -6 && \
echo '' && \
echo '=== 最近 1/5/15 分钟负载 ===' && \
uptime && \
echo '' && \
echo '=== 各 CPU 核心使用率 ===' && \
mpstat -P ALL 1 1 2>/dev/null && \
echo '' && \
echo '=== CPU 时间分布 ===' && \
cat /proc/stat | head -1
```

**输出解读**：

| 指标 | 正常 | 警告 | 异常 |
|------|------|------|------|
| load / 核数 | < 0.7 | 0.7 ~ 1.0 | > 1.0 |
| %idle | > 70% | 30% ~ 70% | < 30% |
| %iowait | < 5% | 5% ~ 15% | > 15% |
| %steal | < 5% | 5% ~ 10% | > 10%（云主机被超卖） |

- **%usr 高** → 应用层 CPU 密集
- **%sys 高** → 内核/系统调用密集
- **%iowait 高** → 磁盘 IO 是瓶颈（参考 disk-analysis）
- **%steal 高** → 宿主机超卖，云主机性能受影响
- **%soft 高** → 网络中断/软中断密集

### 步骤 2：CPU 消耗 Top 进程

```bash
echo '=== CPU 占用 Top 15 ===' && \
ps aux --sort=-%cpu | head -16 && \
echo '' && \
echo '=== 按用户聚合 CPU ===' && \
ps aux | awk 'NR>1 {arr[$1]+=$3} END {for(i in arr) printf "%-20s %.1f%%\n", i, arr[i]}' | sort -rn -k2 | head -10 && \
echo '' && \
echo '=== 线程级 CPU 占用 ===' && \
top -b -n 1 -H | head -20
```

**输出解读**：
- 单个进程 CPU > 80%（单核场景）或 > 核数*80%（多核）→ 🔴 关注
- Java 进程通常用多线程，`top -H` 看每个线程
- 聚合 CPU 可以看出哪个用户占资源最多

### 步骤 3：进程状态分布

```bash
echo '=== 进程状态分布 ===' && \
ps aux | awk 'NR>1 {arr[$8]++} END {for(i in arr) printf "%s: %d\n", i, arr[i]}' | sort -rn -k2 && \
echo '' && \
echo '=== D 状态进程 ===' && \
ps aux | awk '$8 ~ /^[Dd]/' | grep -v grep || echo '无 D 状态进程' && \
echo '' && \
echo '=== 僵尸进程 ===' && \
ps aux | awk '$8 ~ /^[Zz]/' | grep -v grep || echo '无僵尸进程' && \
echo '' && \
echo '=== R 状态进程 ===' && \
ps aux | awk '$8 ~ /^[Rr]/' | grep -v grep | head -10 || echo '无 R 状态进程'
```

**进程状态说明**：

| 状态 | 含义 | 正常？ |
|------|------|--------|
| R (Running) | 正在运行或可运行 | ✅ 正常，过多则 CPU 压力大 |
| S (Sleeping) | 休眠，可中断 | ✅ 大多数进程处于此状态 |
| D (Uninterruptible) | 不可中断休眠（等待 IO） | ⚠️ 持续存在表示 IO 瓶颈 |
| Z (Zombie) | 僵尸进程 | 🔴 需要清理 |
| T (Stopped) | 已停止 | ⚠️ 被信号暂停 |
| Sl | 休眠 + 多线程 | ✅ 常见 |

### 步骤 4：僵尸进程清理方法（如有）

如果发现僵尸进程：
```bash
# 确认僵尸进程的父进程
ps -o pid,ppid,state,cmd -p $(ps aux | awk '$8 ~ /^[Zz]/ {print $2}' | tr '\n' ',' | sed 's/,$//')

# 尝试 kill 父进程（由用户手动执行）
# kill -HUP <父PID>
# 或 kill -9 <父PID>
```

### 步骤 5：进程内存占用量

```bash
echo '=== 内存占用 Top 10 ===' && \
ps aux --sort=-%mem | head -11 && \
echo '' && \
echo '=== 各进程 RSS 排序 ===' && \
ps aux | awk 'NR>1 {print $6/1024 " MB - " $11}' | sort -rn | head -10
```

---

## 报告格式

```
### 🟢 CPU 状态
| 指标 | 值 | 判定 |
|------|-----|------|
| 负载/核 | x.xx | 🟢 正常 |

### 🔴 / 🟡 发现问题
- 进程 xxx CPU 占用 xxx%

### ✅ 建议
```
