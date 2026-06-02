---
name: package-audit
description: 软件包版本管理、软件源审计、安全更新检查和系统组件版本确认。
version: 1.0.0
---

# 软件包版本与软件源审计

覆盖软件包版本查询、软件源配置检查、安全更新可用性、内核版本和关键组件版本确认。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动执行任何软件包安装或升级**。

## 适用场景

- "检查一下软件版本"、"看看装了哪些包"
- "有没有安全更新"、"yum update 安全吗"
- "内核版本是多少"、"软件源配的什么"
- "nginx 版本"、"检查一下各组件的版本"

---

## 诊断步骤

### 步骤 1：发行版与内核版本

```bash
echo '=== 发行版 ===' && \
cat /etc/os-release 2>/dev/null | grep -E 'PRETTY_NAME|VERSION_ID|VERSION_CODENAME' && \
echo '' && \
echo '=== 内核版本 ===' && \
uname -a && \
echo '' && \
echo '=== 内核启动参数 ===' && \
cat /proc/cmdline 2>/dev/null && \
echo '' && \
echo '=== 内核模块 ===' && \
lsmod | head -20
```

### 步骤 2：软件源配置

```bash
echo '=== yum/dnf 源 ===' && \
yum repolist 2>/dev/null | head -10 || \
dnf repolist 2>/dev/null | head -10 || \
echo 'yum/dnf 不可用' && \
echo '' && \
echo '=== apt 源 ===' && \
cat /etc/apt/sources.list 2>/dev/null | grep -v '^#' | grep -v '^$' | head -10 || \
ls /etc/apt/sources.list.d/ 2>/dev/null | head -5 || echo 'apt 不可用'
```

### 步骤 3：已安装包数量与安全更新

```bash
echo '=== 已安装包总数 ===' && \
rpm -qa 2>/dev/null | wc -l || \
dpkg -l 2>/dev/null | wc -l || echo '包管理器不可用' && \
echo '' && \
echo '=== 可用安全更新 ===' && \
yum check-update --security 2>/dev/null | grep -E '^[a-Z]' | head -15 || \
dnf check-update --security 2>/dev/null | grep -E '^[a-Z]' | head -15 || \
apt list --upgradable 2>/dev/null | grep -i security | head -10 || echo '安全更新检查不可用'
```

### 步骤 4：关键组件版本

```bash
echo '=== 关键组件版本 ===' && \
echo "SSH: $(sshd --version 2>&1 | head -1)" && \
echo "OpenSSL: $(openssl version 2>/dev/null)" && \
echo "curl: $(curl --version 2>/dev/null | head -1)" && \
echo "Python: $(python3 --version 2>/dev/null || python --version 2>/dev/null)" && \
echo "Git: $(git --version 2>/dev/null)" && \
echo "Docker: $(docker --version 2>/dev/null)" && \
echo "Nginx: $(nginx -v 2>&1)" && \
echo "MySQL: $(mysql --version 2>/dev/null)" && \
echo "Node: $(node --version 2>/dev/null)" && \
echo "Go: $(go version 2>/dev/null)" && \
echo "Java: $(java -version 2>&1 | head -1)" && \
echo "K8s kubectl: $(kubectl version --client 2>/dev/null | head -1)"
```

### 步骤 5：系统服务与版本关联

```bash
echo '=== 各服务版本 ===' && \
for srv in nginx httpd mysqld mariadb postgresql redis-server redis php-fpm; do \
  $srv --version 2>/dev/null | head -1 | xargs -I{} echo "$srv: {}" ; \
done
```

### 步骤 6：CVE 风险快速检查（已知高危版本）

```bash
echo '=== 已知高危版本检测 ===' && \
# OpenSSL < 1.1.1 (CVE-2022-3786 等)
openssl version 2>/dev/null | grep -qE '1\.0\.[0-9]|1\.1\.0' && echo '⚠️ OpenSSL 版本过低，建议升级' || echo '✅ OpenSSL 版本正常' && \
# SSH < 7.x
sshd -V 2>&1 | grep -oP 'OpenSSH_\K[0-9]+\.[0-9]+' | awk '{if ($1 < 7.4) print "⚠️ SSH 版本过低, 当前: OpenSSH_"$1; else print "✅ SSH 版本正常"}' || echo '✅ SSH 版本检查通过' && \
# curl < 7.80
curl --version 2>/dev/null | grep -oP 'curl \K[0-9]+\.[0-9]+' | awk '{if ($1 < 7.8) print "⚠️ curl 版本过低"; else print "✅ curl 版本正常"}'
```

---

## 报告格式

```
### 🟢 系统版本
发行版: xxx 内核: x.x.x

### 🟢 / 🟡 安全更新
可用安全更新: xxx 个（建议更新）

### 🟢 关键组件
| 组件 | 版本 | 状态 |
|------|------|------|

### ✅ 建议
```
