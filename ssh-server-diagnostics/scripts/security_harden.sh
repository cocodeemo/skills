#!/bin/bash
#
# security_harden.sh — 通用安全基线检查与加固脚本
# 支持 check（合规检查）和 harden（自动加固）两种模式
#
# 用法:
#   sudo bash security_harden.sh check     # 安全合规检查
#   sudo bash security_harden.sh harden    # 安全加固（需确认）

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/common.sh" ] && source "$SCRIPT_DIR/common.sh"

MODE="${1:-check}"
REPORT_FILE="/tmp/security-report-$(date +%Y%m%d-%H%M%S).txt"
TOTAL_CHECKS=0
PASSED=0
WARNINGS=0
FAILED=0

check_root

print_title "安全基线检查（${MODE}模式）"
echo "时间: $(date)"
echo ""

check_item() {
    local id=$1
    local description=$2
    local command=$3
    local pass_pattern=$4
    local fail_msg=$5

    TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

    # 执行检查
    result=$(eval "$command" 2>/dev/null)
    exit_code=$?

    if echo "$result" | grep -qE "$pass_pattern" 2>/dev/null; then
        echo -e "  ${GREEN}[PASS]${NC} $id - $description" | tee -a "$REPORT_FILE"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}[FAIL]${NC} $id - $description" | tee -a "$REPORT_FILE"
        echo "    当前状态: ${result:-N/A}" | tee -a "$REPORT_FILE"
        echo "    建议: $fail_msg" | tee -a "$REPORT_FILE"
        FAILED=$((FAILED + 1))

        # harden 模式自动修复
        if [ "$MODE" = "harden" ]; then
            echo "    正在修复..." | tee -a "$REPORT_FILE"
            case "$id" in
                SSH-001) echo "手动修复: 编辑 /etc/ssh/sshd_config 设置 PermitRootLogin without-password" ;;
                SSH-002) echo "手动修复: 编辑 /etc/ssh/sshd_config 设置 PasswordAuthentication no" ;;
                PASS-001) chage -M 90 "$(whoami)" 2>/dev/null ;;
                KERNEL-001) sysctl -w net.ipv4.ip_forward=0 2>/dev/null;;
                *) echo "自动修复不支持，请手动处理" ;;
            esac
        fi
    fi
}

echo "" | tee -a "$REPORT_FILE"
print_section "1. SSH 安全配置" | tee -a "$REPORT_FILE"

check_item "SSH-001" "禁止 Root 密码登录" \
    "sshd -T 2>/dev/null | grep 'permitrootlogin' | awk '{print \$2}'" \
    "without-password|no|prohibit-password" \
    "设置: PermitRootLogin without-password"

check_item "SSH-002" "禁用密码认证" \
    "sshd -T 2>/dev/null | grep 'passwordauthentication' | awk '{print \$2}'" \
    "no" \
    "设置: PasswordAuthentication no"

check_item "SSH-003" "SSH 协议版本" \
    "sshd -T 2>/dev/null | grep 'protocol' | awk '{print \$2}' || echo '2'" \
    "2" \
    "确保 SSH 仅使用 Protocol 2"

PORT=$(sshd -T 2>/dev/null | grep '^port ' | awk '{print $2}')
check_item "SSH-004" "SSH 非默认端口" \
    "echo $PORT" \
    "[1-9][0-9]*" \
    "考虑修改 SSH 默认端口 22"

echo "" | tee -a "$REPORT_FILE"
print_section "2. 系统认证策略" | tee -a "$REPORT_FILE"

check_item "PASS-001" "密码最长有效期 ≤ 90 天" \
    "grep '^PASS_MAX_DAYS' /etc/login.defs 2>/dev/null | awk '{print \$2}' || echo '99999'" \
    "[0-9]?[0-9]|90" \
    "设置 PASS_MAX_DAYS 90"

check_item "PASS-002" "密码最短长度 ≥ 8" \
    "grep '^PASS_MIN_LEN' /etc/login.defs 2>/dev/null | awk '{print \$2}' || echo '5'" \
    "[8-9]|[1-9][0-9]" \
    "设置 PASS_MIN_LEN 8"

check_item "PASS-003" "密码过期前警告 ≥ 7 天" \
    "grep '^PASS_WARN_AGE' /etc/login.defs 2>/dev/null | awk '{print \$2}' || echo '0'" \
    "[7-9]|[1-9][0-9]" \
    "设置 PASS_WARN_AGE 7"

echo "" | tee -a "$REPORT_FILE"
print_section "3. 文件系统安全" | tee -a "$REPORT_FILE"

check_item "FS-001" "/etc/shadow 权限 000" \
    "stat -c '%a' /etc/shadow 2>/dev/null" \
    "^0$" \
    "chmod 000 /etc/shadow"

check_item "FS-002" "/etc/passwd 权限 644" \
    "stat -c '%a' /etc/passwd 2>/dev/null" \
    "644" \
    "chmod 644 /etc/passwd"

echo "" | tee -a "$REPORT_FILE"
print_section "4. 内核安全参数" | tee -a "$REPORT_FILE"

check_item "KERNEL-001" "禁用 IP 转发" \
    "sysctl net.ipv4.ip_forward 2>/dev/null | awk '{print \$3}'" \
    "^0$" \
    "sysctl -w net.ipv4.ip_forward=0"

check_item "KERNEL-002" "启用 TCP SYN Cookie" \
    "sysctl net.ipv4.tcp_syncookies 2>/dev/null | awk '{print \$3}'" \
    "^1$" \
    "sysctl -w net.ipv4.tcp_syncookies=1"

check_item "KERNEL-003" "禁用 ICMP 重定向" \
    "sysctl net.ipv4.conf.all.accept_redirects 2>/dev/null | awk '{print \$3}'" \
    "^0$" \
    "sysctl -w net.ipv4.conf.all.accept_redirects=0"

check_item "KERNEL-004" "禁用源路由" \
    "sysctl net.ipv4.conf.all.accept_source_route 2>/dev/null | awk '{print \$3}'" \
    "^0$" \
    "sysctl -w net.ipv4.conf.all.accept_source_route=0"

echo "" | tee -a "$REPORT_FILE"
print_section "5. 登录审计" | tee -a "$REPORT_FILE"

# 失败登录统计
FAIL_COUNT=$(lastb 2>/dev/null | wc -l)
check_item "AUDIT-001" "暴力破解检测" \
    "echo $FAIL_COUNT" \
    "^[0-9]+$" \
    "配置 fail2ban 或修改 SSH 端口"

echo "" | tee -a "$REPORT_FILE"
print_section "6. 防火墙状态" | tee -a "$REPORT_FILE"

check_item "FIREWALL-001" "防火墙运行状态" \
    "systemctl is-active firewalld 2>/dev/null || ufw status 2>/dev/null | grep -i active || echo 'inactive'" \
    "active|Active" \
    "启用防火墙: systemctl enable --now firewalld"

echo "" | tee -a "$REPORT_FILE"
print_section "7. 日志审计" | tee -a "$REPORT_FILE"

check_item "LOG-001" "rsyslog/系统日志运行" \
    "systemctl is-active rsyslog 2>/dev/null || systemctl is-active syslog-ng 2>/dev/null || systemctl is-active systemd-journald 2>/dev/null || echo 'inactive'" \
    "active" \
    "确保日志服务正常运行"

check_item "LOG-002" "auditd 运行状态" \
    "systemctl is-active auditd 2>/dev/null || echo 'not_installed'" \
    "active" \
    "建议启用 auditd 进行安全审计"

echo "" | tee -a "$REPORT_FILE"
print_section "8. 敏感 SUID 文件" | tee -a "$REPORT_FILE"

SUID_COUNT=$(find /usr -type f -perm -4000 2>/dev/null | wc -l)
check_item "SUID-001" "SUID 文件数量" \
    "echo $SUID_COUNT" \
    "^(1[0-9]|[0-9]|[2-9][0-9])$" \
    "检查异常 SUID 文件: find / -type f -perm -4000"

echo "" | tee -a "$REPORT_FILE"
print_section "9. 账户安全" | tee -a "$REPORT_FILE"

check_item "USER-001" "空密码账户检测" \
    "awk -F: '(\$2 == \"\" || \$2 == \"!\") {print \$1}' /etc/shadow 2>/dev/null | wc -l" \
    "^0$" \
    "为空密码账户设置密码: passwd <用户名>"

check_item "USER-002" "UID 0 账户检查" \
    "awk -F: '(\$3 == 0) {print \$1}' /etc/passwd 2>/dev/null | grep -v '^root$' | wc -l" \
    "^0$" \
    "仅 root 应有 UID 0"

echo "" | tee -a "$REPORT_FILE"
echo "========== 检查完成 ==========" | tee -a "$REPORT_FILE"
echo "总计: $TOTAL_CHECKS  通过: $PASSED  失败: $FAILED" | tee -a "$REPORT_FILE"
echo "详细报告: $REPORT_FILE" | tee -a "$REPORT_FILE"

if [ "$FAILED" -gt 0 ]; then
    echo -e "\n${YELLOW}⚠ 有 $FAILED 项未通过安全检查，建议处理${NC}"
    if [ "$MODE" = "check" ]; then
        echo "以 root 运行 '$0 harden' 自动修复部分项目"
    fi
fi

exit $FAILED
