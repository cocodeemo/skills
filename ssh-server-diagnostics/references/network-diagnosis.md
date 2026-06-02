---
name: network-diagnosis
description: 网络连通性、端口状态与连接分析。覆盖 ping/dig/curl 测试、端口监听、连接数统计、防火墙检查。
version: 1.0.0
---

# 网络诊断

覆盖网络连通性测试、端口监听排查、连接状态分析和防火墙检查。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动执行任何网络配置变更**。
>
> 防火墙规则修改、路由配置变更、网络服务启停等操作仅作为参考提供给用户。

## 适用场景

### 用户可能的问题表述

**连通性类**：
- "网络不通"、"ping 不通"、"ssh 连不上"
- "上不了网了"、"外网不通"
- "curl 超时"、"端口不通"

**连接类**：
- "连接数太多"、"TIME_WAIT 太多"
- "端口被占了"、"80 端口被谁用了"
- "连接池满了"

**防火墙类**：
- "防火墙拦了"、"iptables 规则"
- "安全组是不是有问题"

---

## 诊断步骤

### 步骤 1：网络接口状态

```bash
echo '=== 网卡状态 ===' && \
ip -brief addr && \
echo '' && \
echo '=== 网卡详细信息 ===' && \
for nic in $(ip -o link show | awk -F': ' '{print $2}' | grep -v lo); do \
  echo "--- $nic ---" && \
  ethtool $nic 2>/dev/null | grep -E 'Speed|Duplex|Link detected' || echo 'ethtool 不支持'; \
done && \
echo '' && \
echo '=== 网卡错误统计 ===' && \
ip -s link show | grep -A5 -E '^[0-9]' | head -20
```

**输出解读**：
- `state UP` → 正常；`state DOWN` → 网卡未启用
- 网卡有大量错误（errors/dropped/overruns）→ 🟡 关注

### 步骤 2：路由检查

```bash
echo '=== 路由表 ===' && \
ip route show && \
echo '' && \
echo '=== 默认网关可达性 ===' && \
GW=$(ip route show default | awk '{print $3}' | head -1) && \
ping -c 2 -W 2 $GW 2>&1 | tail -3
```

**输出解读**：
- 没有 `default via` 行 → 无默认路由，出不了公网
- 默认网关 ping 不通 → 网络层或下层问题

### 步骤 3：连通性测试

```bash
echo '=== DNS 配置 ===' && \
cat /etc/resolv.conf 2>/dev/null && \
echo '' && \
echo '=== DNS 解析测试 ===' && \
nslookup baidu.com 2>/dev/null | head -5 || dig baidu.com +short 2>/dev/null | head -3 || echo 'DNS 工具不可用' && \
echo '' && \
echo '=== 外网连通性 ===' && \
ping -c 2 -W 3 114.114.114.114 2>&1 | tail -3 && \
ping -c 2 -W 3 baidu.com 2>&1 | tail -3
```

**输出解读**：
- **IP 通、域名不通** → DNS 问题
- **IP 不通、域名不通** → 网络出口问题
- **DNS 返回 100.100.x.x** → 阿里云内网 DNS，正常

### 步骤 4：监听端口与服务端口

```bash
echo '=== 所有监听端口 ===' && \
ss -tlnp 2>/dev/null && \
echo '' && \
echo '=== UDP 监听 ===' && \
ss -ulnp 2>/dev/null && \
echo '' && \
echo '=== UNIX Socket ===' && \
ss -xlp 2>/dev/null | head -10
```

**输出解读**：
- 异常端口监听应标记出来
- `*:22` 表示在所有接口上监听 SSH，正常
- `0.0.0.0:XXX` 表示暴露在所有网卡

### 步骤 5：连接状态统计

```bash
echo '=== 连接状态分布 ===' && \
ss -tan | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn && \
echo '' && \
echo '=== 各 IP 连接数 Top 10 ===' && \
ss -tan | awk 'NR>1 {print $5}' | cut -d: -f1 | sort | uniq -c | sort -rn | head -10 && \
echo '' && \
echo '=== 各端口连接数 ===' && \
ss -tan | awk 'NR>1 {print $4}' | cut -d: -f2 | sort | uniq -c | sort -rn | head -10
```

**输出解读**：

| 状态 | 正常范围 | 异常 |
|------|---------|------|
| ESTAB | < 1000 | > 2000 或远超基线 |
| TIME_WAIT | < 10000 | > 30000（短连接场景除外） |
| CLOSE_WAIT | 0 ~ 少数 | > 10 表示应用没正确关闭连接 |
| SYN_SENT | 0 | > 0 可能目标不可达 |

- **TIME_WAIT 太多** → 短连接场景正常，可通过 `net.ipv4.tcp_tw_reuse` 优化
- **CLOSE_WAIT 堆积** → 应用程序 bug，连接未正确 close

### 步骤 6：端口占用排查

```bash
echo '=== 指定端口占用 ===' && \
# 如果用户提到特定端口，替换 <PORT> 为目标端口
PORT=<PORT> && \
ss -tlnp | grep ":$PORT " && \
echo '' && \
echo '=== 哪个进程在用 ===' && \
fuser $PORT/tcp 2>/dev/null || lsof -i :$PORT 2>/dev/null || echo '需安装 lsof'
```

### 步骤 7：防火墙检查

```bash
echo '=== iptables 规则 ===' && \
iptables -L -n --line-numbers 2>/dev/null | head -20 && \
echo '' && \
echo '=== NAT 规则 ===' && \
iptables -t nat -L -n 2>/dev/null | head -10 && \
echo '' && \
echo '=== firewalld/ufw 状态 ===' && \
systemctl is-active firewalld 2>/dev/null | xargs -I{} echo 'firewalld: {}' || echo '' && \
ufw status 2>/dev/null | head -5 || echo 'ufw 未安装'
```

---

## 报告格式

```
### 🟢 网络整体状态
| 检查项 | 结果 |
|--------|------|

### 🟢 / 🟡 / 🔴 详细
...

### ✅ / ⚠️ 建议
```
