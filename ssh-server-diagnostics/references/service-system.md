---
name: service-system
description: 服务状态管理、计划任务检查、系统日志分析和安全审计。覆盖 systemctl、cron、journalctl、last、防火墙检查。
version: 1.0.0
---

# 服务、系统日志与安全审计

覆盖系统服务状态检查、计划任务、系统日志分析和安全审计。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动执行任何服务启停、规则修改或配置变更**。
>
> 重启服务、修改配置、关闭服务等操作仅作为参考提供给用户。

## 适用场景

### 用户可能的问题表述

**服务类**：
- "服务起不来了"、"nginx 启动失败"
- "看看哪些服务在运行"、"sshd 状态"
- "开机自启的配置"

**日志类**：
- "系统有报错"、"dmesg 报错"
- "看看日志"、"journalctl 查错误"
- "系统什么时候重启过"

**安全类**：
- "看看谁登录过"、"安全检查"
- "有没有人暴力破解"、"审计"
- "端口暴露"、"防火墙规则"

---

## 诊断步骤

### 步骤 1：关键服务状态

```bash
echo '=== 系统服务状态 ===' && \
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -20 && \
echo '' && \
echo '=== 指定的关键服务 ===' && \
for s in sshd rsyslog systemd-journald docker containerd crond cron nginx httpd mysqld; do \
  systemctl is-active $s 2>/dev/null | xargs -I{} echo "$s: {}"; \
done && \
echo '' && \
echo '=== 失败的服务 ===' && \
systemctl --failed --no-pager 2>/dev/null || echo '无失败服务'
```

### 步骤 2：开机自启状态

```bash
echo '=== 开机自启服务 ===' && \
systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null | head -20 && \
echo '' && \
echo '=== 最近启动耗时 ===' && \
systemd-analyze time 2>/dev/null && \
systemd-analyze blame 2>/dev/null | head -10
```

### 步骤 3：计划任务

```bash
echo '=== 用户 crontab ===' && \
for user in root $(ls /home/ 2>/dev/null); do \
  echo "--- $user ---" && \
  crontab -u $user -l 2>/dev/null || echo "无 crontab"; \
done && \
echo '' && \
echo '=== 系统 crontab ===' && \
ls /etc/cron.d/ 2>/dev/null | head -10 && \
cat /etc/crontab 2>/dev/null | grep -v '^#' | grep -v '^$' | head -10 && \
echo '' && \
echo '=== cron/anacron 服务状态 ===' && \
systemctl is-active crond 2>/dev/null | xargs -I{} echo 'crond: {}' && \
systemctl is-active cron 2>/dev/null | xargs -I{} echo 'cron: {}' || echo 'cron 未安装'
```

### 步骤 4：系统日志

```bash
echo '=== 内核错误（dmesg） ===' && \
dmesg -T 2>/dev/null | grep -iE 'error|fail|panic|call trace|segfault|hung_task|blocked for|bug|warning' | tail -15 || \
dmesg | grep -iE 'error|fail|panic' | tail -15 && \
echo '' && \
echo '=== systemd 错误日志 ===' && \
journalctl -p err -b --no-pager 2>/dev/null | tail -20 || echo 'journalctl 不可用' && \
echo '' && \
echo '=== SSH 登录失败记录 ===' && \
journalctl -u sshd --no-pager 2>/dev/null | grep -i 'Failed password' | tail -10 || \
grep 'Failed password' /var/log/secure 2>/dev/null | tail -10 || echo 'SSH 失败登录日志不可用' && \
echo '' && \
echo '=== 系统重启记录 ===' && \
last reboot 2>/dev/null | head -10 && \
echo '' && \
echo '=== 关键报错摘要 ===' && \
journalctl -p crit -b --no-pager 2>/dev/null | tail -5 || echo '无 crit 级别日志'
```

### 步骤 5：安全审计

```bash
echo '=== 最近登录记录 ===' && \
last -15 2>/dev/null && \
echo '' && \
echo '=== 失败登录记录 ===' && \
lastb 2>/dev/null | head -15 || echo '无失败登录记录' && \
echo '' && \
echo '=== 当前登录用户 ===' && \
w && \
echo '' && \
echo '=== 最近 su/sudo 记录 ===' && \
journalctl -u sudo --no-pager 2>/dev/null | tail -5 || \
grep -E 'sudo|su\b' /var/log/secure 2>/dev/null | tail -5 || echo 'sudo 日志不可用'
```

**输出解读**：
- `lastb` 显示大量失败登录 → 正在被暴力破解，建议修改端口或配置 fail2ban
- 异常来源 IP 值得注意
- 检查是否有不认识的用户登录过

### 步骤 6：防火墙安全

```bash
echo '=== iptables 默认策略 ===' && \
iptables -L -n --line-numbers 2>/dev/null | head -15 && \
echo '' && \
echo '=== 防火墙服务 ===' && \
systemctl is-active firewalld 2>/dev/null | xargs -I{} echo 'firewalld: {}' && \
echo '' && \
echo '=== SELinux 状态 ===' && \
getenforce 2>/dev/null || sestatus 2>/dev/null | head -1 || echo 'SELinux 未安装/不可用' && \
echo '' && \
echo '=== 禁止密码登录检查 ===' && \
grep '^PasswordAuthentication' /etc/ssh/sshd_config 2>/dev/null
```

### 步骤 7：软件包与更新

```bash
echo '=== 发行版与包管理器 ===' && \
cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"' && \
echo '' && \
echo '=== 可用安全更新 ===' && \
yum check-update --security 2>/dev/null | grep -E '^[a-Z]' | head -10 || \
dnf check-update --security 2>/dev/null | grep -E '^[a-Z]' | head -10 || \
apt list --upgradable 2>/dev/null | grep -i security | head -10 || echo '安全更新检查不可用'
```

---

## 报告格式

```
### 🟢 服务状态
| 服务 | 状态 |
|------|------|

### 🟢 / 🟡 / 🔴 系统日志
- 最近 N 小时内核无严重错误
- 或：发现 [条数] 条错误日志：[示例]

### 🟢 / 🔴 安全审计
- 最近登录：[正常/异常]
- 失败登录：[次数/来自 IP]
- 防火墙：[已启用/未配置]

### ✅ 建议
```
