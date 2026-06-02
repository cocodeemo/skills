---
name: latency-diagnostics
description: 网络延迟与丢包深度排查——使用 ping/mtr/tcpdump/ethtool 等工具诊断网络质量。
version: 1.0.0
---

# 网络延迟与丢包深度排查

覆盖网络延迟高、丢包严重、TCP 重传等场景的深度诊断。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动执行网络配置变更**。

## 适用场景

- "网络很卡"、"延迟高"、"丢包严重"
- "TCP 重传很多"、"网络抖动"
- "ssh 很卡"、"传文件很慢"

---

## 诊断步骤

### 步骤 1：基础延迟测试

```bash
echo '=== 目标延迟 ===' && \
TARGET="${TARGET:-114.114.114.114}" && \
ping -c 10 -W 3 $TARGET 2>&1 | tail -6 && \
echo '' && \
echo '=== 多目标对比 ===' && \
for ip in 114.114.114.114 223.5.5.5 8.8.8.8; do \
  ping -c 3 -W 2 $ip 2>&1 | tail -1; \
done
```

**输出解读**：
```
rtt min/avg/max/mdev = 1.234/2.345/5.678/0.123 ms
```
- `avg` → 平均延迟
- `mdev` → 抖动，> 10ms 说明网络不稳定
- 丢包率 > 0% → 🟡 关注，> 5% → 🔴

### 步骤 2：逐跳延迟（mtr）

```bash
echo '=== 逐跳延迟 ===' && \
mtr -r -c 5 -n 114.114.114.114 2>/dev/null | head -15 || \
traceroute -n 114.114.114.114 2>/dev/null | head -15 || echo 'mtr/traceroute 不可用'
```

**输出解读**：
- 某跳延迟突然升高 → 该节点可能是瓶颈
- 某跳 `???` 或 `*` → 该节点禁 ping，不一定有问题
- 最后一跳延迟高 → 目标服务器或最后一公里问题

### 步骤 3：网卡队列与 Ring Buffer

```bash
echo '=== Ring Buffer 大小 ===' && \
for nic in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do \
  echo "--- $nic ---" && \
  ethtool -g $nic 2>/dev/null | grep -E 'RX|TX' | head -4 || echo 'ethtool 不支持'; \
done && \
echo '' && \
echo '=== 网卡队列数 ===' && \
for nic in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do \
  echo "--- $nic ---" && \
  ethtool -l $nic 2>/dev/null | grep -E 'RX|TX|Combined' | head -4 || echo 'ethtool 不支持'; \
done
```

### 步骤 4：网卡错误与丢包统计

```bash
echo '=== 网卡丢包统计 ===' && \
ip -s link show | grep -A8 -E '^[0-9]' | head -30 && \
echo '' && \
echo '=== 网卡详细错误 ===' && \
NIC=$(ip route show default | awk '{print $5}' | head -1) && \
ethtool -S $NIC 2>/dev/null | grep -iE 'drop|error|miss|over|fail|buf' | head -15 || echo 'ethtool -S 不可用'
```

### 步骤 5：网络栈丢包点排查

```bash
echo '=== softnet 统计 ===' && \
cat /proc/net/softnet_stat | awk '{print "CPU" NR-1 ": dropped=" strtonum("0x" substr($2,1,8)) " squeezed=" strtonum("0x" substr($3,1,8))}' && \
echo '' && \
echo '=== conntrack 状态 ===' && \
conntrack -C 2>/dev/null || echo 'conntrack 不可用' && \
sysctl net.netfilter.nf_conntrack_max 2>/dev/null && \
sysctl net.netfilter.nf_conntrack_count 2>/dev/null || echo 'conntrack 未加载'
```

### 步骤 6：TCP 重传与拥塞

```bash
echo '=== TCP 重传统计 ===' && \
nstat -az 2>/dev/null | grep -iE 'retrans|Loss|Sack|FastRetran' | head -8 && \
echo '' && \
echo '=== TCP 拥塞算法 ===' && \
sysctl net.ipv4.tcp_congestion_control 2>/dev/null && \
echo '' && \
echo '=== TCP 内存配置 ===' && \
sysctl net.ipv4.tcp_mem 2>/dev/null
```

---

## 报告格式

```
### 🟡 网络延迟
目标 114.114.114.114: avg=5ms loss=0%

### 🔴 / 🟡 发现问题
- 网卡有丢包
- softnet 丢包

### ✅ 优化建议
```
