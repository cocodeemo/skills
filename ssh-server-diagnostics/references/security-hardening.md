---
name: security-hardening
description: 安全基线检查——登录审计、密码策略、SSH 加固、文件权限、内核参数安全、异常进程检测。
version: 1.0.0
---

# 安全基线检查

覆盖登录审计、SSH 安全配置、密码策略、文件权限、内核参数安全和异常进程检测。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动修改任何安全配置**。
>
> 所有加固命令仅作为参考提供给用户。

## 适用场景

- "做一下安全检测"、"基线检查"
- "SSH 安全吗"、"密码策略检查"
- "看看有没有被入侵"、"异常检测"
- "等保检查"、"安全加固"

---

## 诊断步骤

### 步骤 1：登录审计

```bash
echo '=== 最近登录记录 ===' && \
last -20 2>/dev/null && \
echo '' && \
echo '=== 登录失败统计 ===' && \
lastb 2>/dev/null | head -20 && \
echo '' && \
echo '=== 当前登录用户 ===' && \
w && \
echo '' && \
echo '=== 登录失败的 IP Top 10 ===' && \
lastb 2>/dev/null | awk 'NR>2 {print $3}' | sort | uniq -c | sort -rn | head -10
```

**输出解读**：
- 失败登录太多 → 正在被暴力破解
- 不认识的 IP 登录成功过 → 🚨 安全事件

### 步骤 2：SSH 安全配置

```bash
echo '=== SSH 端口 ===' && \
grep -E '^Port ' /etc/ssh/sshd_config 2>/dev/null || echo 'Port 22 (默认)' && \
echo '' && \
echo '=== SSH 认证方式 ===' && \
grep -E '^PasswordAuthentication|^PubkeyAuthentication|^PermitRootLogin|^AllowUsers|^DenyUsers' /etc/ssh/sshd_config 2>/dev/null && \
echo '' && \
echo '=== SSH 协议版本 ===' && \
grep '^Protocol' /etc/ssh/sshd_config 2>/dev/null || echo 'Protocol 2 (默认)' && \
echo '' && \
echo '=== SSH 免密登录文件 ===' && \
ls -la ~/.ssh/authorized_keys 2>/dev/null | awk '{print "权限: "$1" 大小: "$5}'
```

**安全建议**：
- `PasswordAuthentication yes` → 建议改为 `no`，仅密钥登录
- `PermitRootLogin yes` → 建议改为 `without-password` 或 `no`
- 建议配置 `AllowUsers` 限制登录用户

### 步骤 3：密码策略检查

```bash
echo '=== 密码过期策略 ===' && \
cat /etc/login.defs 2>/dev/null | grep -E '^PASS_MAX_DAYS|^PASS_MIN_DAYS|^PASS_WARN_AGE' | head -5 && \
echo '' && \
echo '=== 用户密码状态 ===' && \
for user in root $(ls /home/ 2>/dev/null); do \
  passwd -S $user 2>/dev/null | awk '{print $1": "$2" (上次修改: "$3")"}'; \
done
```

### 步骤 4：文件权限检查

```bash
echo '=== 敏感文件权限 ===' && \
ls -la /etc/passwd /etc/shadow /etc/sudoers 2>/dev/null && \
echo '' && \
echo '=== 全局可写文件 ===' && \
find /etc/ -type f -perm -o+w 2>/dev/null | head -10 && \
echo '' && \
echo '=== 无主文件 ===' && \
find / -nouser -o -nogroup 2>/dev/null | head -10 || echo '无无主文件' && \
echo '' && \
echo '=== SUID 文件 ===' && \
find /usr -type f -perm -4000 2>/dev/null | head -15
```

### 步骤 5：异常进程检测

```bash
echo '=== 网络连接进程 ===' && \
ss -tanp 2>/dev/null | grep ESTAB | awk '{print $6}' | sort | uniq | head -15 && \
echo '' && \
echo '=== 高 CPU 但无终端进程 ===' && \
ps aux --sort=-%cpu | awk '$7=="?" && $3>10.0' | head -5 || echo '无非终端高 CPU 进程' && \
echo '' && \
echo '=== 隐藏进程检查 ===' && \
ps aux 2>/dev/null | wc -l && \
ls /proc/ 2>/dev/null | grep -E '^[0-9]+$' | wc -l || echo ''
```

### 步骤 6：SELinux/AppArmor 状态

```bash
echo '=== SELinux 状态 ===' && \
getenforce 2>/dev/null || sestatus 2>/dev/null | head -2 || echo 'SELinux 未启用' && \
echo '' && \
echo '=== AppArmor 状态 ===' && \
aa-status 2>/dev/null | head -5 || echo 'AppArmor 未启用'
```

### 步骤 7：内核参数安全

```bash
echo '=== 网络参数安全 ===' && \
sysctl net.ipv4.ip_forward 2>/dev/null && \
sysctl net.ipv4.conf.all.accept_source_route 2>/dev/null && \
sysctl net.ipv4.conf.all.accept_redirects 2>/dev/null && \
sysctl net.ipv4.conf.all.secure_redirects 2>/dev/null && \
sysctl net.ipv4.tcp_syncookies 2>/dev/null
```

---

## 报告格式

```
### 🟢 / 🔴 安全概览
| 检查项 | 状态 | 建议 |
|--------|------|------|

### 🔴 高风险
1. 密码登录已开启 → 建议改为密钥登录
2. 失败登录 xxx 次 → 建议配置 fail2ban

### 🟡 中风险
...

### ✅ 加固建议汇总
```
