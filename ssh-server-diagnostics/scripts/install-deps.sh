#!/bin/bash
#
# install-deps.sh — 诊断工具依赖自动安装脚本
# 自动检测发行版并安装所有诊断所需工具
#
# 用法:
#   sudo bash install-deps.sh          # 安装全部工具
#   sudo bash install-deps.sh minimal  # 仅安装核心工具

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/common.sh" ] && source "$SCRIPT_DIR/common.sh"

MODE="${1:-full}"

check_root

print_title "诊断工具依赖安装"
echo "模式: $MODE"
echo ""

# 核心工具 — 无论什么模式都装
CORE_TOOLS=""
# 性能分析工具
PERF_TOOLS=""
# 网络工具
NET_TOOLS=""
# 存储工具
STORAGE_TOOLS=""
# 调试工具
DEBUG_TOOLS=""

# 根据发行版选择包名
OS_TYPE=$(get_os_type)
OS_VERSION=$(get_os_version)

echo "检测到系统: $OS_TYPE $OS_VERSION"
echo ""

case $OS_TYPE in
    ubuntu|debian)
        CORE_TOOLS="sysstat procps iproute2 openssh-client curl wget"
        PERF_TOOLS="linux-tools-common linux-tools-$(uname -r) linux-tools-generic strace"
        NET_TOOLS="dnsutils iputils-ping netcat-openbsd traceroute mtr-tiny"
        STORAGE_TOOLS="smartmontools fio iotop"
        DEBUG_TOOLS="lsof iotop htop"
        INSTALL_CMD="apt-get install -y"
        ;;
    centos|rhel|anolis|alinux|tencentos|openeuler|rocky|almalinux)
        CORE_TOOLS="sysstat procps-ng iproute openssh-clients curl wget"
        PERF_TOOLS="perf strace"
        NET_TOOLS="bind-utils iputils nmap-ncat traceroute mtr"
        STORAGE_TOOLS="smartmontools fio iotop"
        DEBUG_TOOLS="lsof iotop htop"
        INSTALL_CMD="yum install -y"
        # CentOS 8+ / Anolis 8+ 用 dnf
        if [ "${OS_VERSION%%.*}" -ge 8 ] 2>/dev/null; then
            INSTALL_CMD="dnf install -y"
        fi
        ;;
    *)
        echo "未知发行版，尝试 yum..."
        CORE_TOOLS="sysstat procps iproute curl wget"
        PERF_TOOLS="perf strace"
        NET_TOOLS="bind-utils traceroute mtr"
        STORAGE_TOOLS="smartmontools iotop"
        DEBUG_TOOLS="lsof iotop"
        INSTALL_CMD="yum install -y"
        ;;
esac

install_group() {
    local name=$1
    shift
    local pkgs=("$@")
    echo "--- 安装 ${name} 工具 ---"
    for pkg in "${pkgs[@]}"; do
        echo -n "  $pkg ... "
        if pkg_check "$pkg" 2>/dev/null; then
            echo "已安装"
        else
            $INSTALL_CMD "$pkg" &>/dev/null && echo "✓" || echo "✗ 安装失败"
        fi
    done
    echo ""
}

# 核心工具
install_group "核心" ${CORE_TOOLS[@]}

# 网路工具
install_group "网络诊断" ${NET_TOOLS[@]}

# PERF 工具
if [ "$MODE" = "full" ]; then
    install_group "性能分析" ${PERF_TOOLS[@]}
    install_group "存储诊断" ${STORAGE_TOOLS[@]}
    install_group "调试" ${DEBUG_TOOLS[@]}
fi

# 检查安装结果
echo "========== 安装检查 =========="
MISSING=0
for cmd in iostat mpstat pidstat dstat ss curl ping nslookup iotop lsof; do
    if command -v "$cmd" &> /dev/null; then
        echo -e "  ${GREEN}✓${NC} $cmd"
    else
        echo -e "  ${RED}✗${NC} $cmd"
        MISSING=$((MISSING + 1))
    fi
done

echo ""
if [ "$MISSING" -gt 0 ]; then
    echo -e "${YELLOW}有 $MISSING 个工具未安装。部分诊断功能受限。${NC}"
else
    echo -e "${GREEN}所有核心诊断工具已就绪。${NC}"
fi
