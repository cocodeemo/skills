#!/bin/bash
# 共享工具函数库
# 所有脚本可以 source 这个文件使用通用函数
# 适用于任意 Linux 发行版

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 打印信息函数
info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

step() {
    echo -e "${CYAN}[STEP]${NC} $*"
}

# 检查命令是否存在
check_command() {
    local cmd=$1
    if ! command -v "$cmd" &> /dev/null; then
        error "Command '$cmd' not found."
        return 1
    fi
    return 0
}

# 检查多个命令
check_commands() {
    local missing=0
    for cmd in "$@"; do
        if ! command -v "$cmd" &> /dev/null; then
            warning "Command '$cmd' not found."
            missing=$((missing + 1))
        fi
    done
    return $missing
}

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        error "This script must be run as root."
        exit 1
    fi
}

# 获取系统类型
get_os_type() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif command -v lsb_release &> /dev/null; then
        lsb_release -is | tr '[:upper:]' '[:lower:]'
    else
        echo "unknown"
    fi
}

get_os_version() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$VERSION_ID"
    else
        echo "unknown"
    fi
}

# 包管理器命令
pkg_install() {
    case $(get_os_type) in
        ubuntu|debian)
            apt-get install -y "$@" 2>/dev/null
            ;;
        centos|rhel|anolis|alinux|tencentos|openeuler)
            yum install -y "$@" 2>/dev/null || dnf install -y "$@" 2>/dev/null
            ;;
        *)
            error "Unsupported OS: $(get_os_type)"
            return 1
            ;;
    esac
}

pkg_check() {
    case $(get_os_type) in
        ubuntu|debian)
            dpkg -l "$1" 2>/dev/null | grep -q '^ii'
            ;;
        centos|rhel|anolis|alinux|tencentos|openeuler)
            rpm -q "$1" 2>/dev/null | grep -q "$1"
            ;;
        *)
            return 1
            ;;
    esac
}

# 确认执行
confirm() {
    local msg="${1:-确认继续？}"
    echo -en "${YELLOW}[?]${NC} ${msg} [y/N] "
    read -r response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# 创建临时目录
make_temp_dir() {
    mktemp -d /tmp/ssh-diagnostics-XXXXXX
}

# 清理旧日志
cleanup_logs() {
    local dir=$1
    local days=${2:-30}
    if [ -d "$dir" ]; then
        find "$dir" -name "*.log" -type f -mtime +$days -delete 2>/dev/null
        find "$dir" -name "*.gz" -type f -mtime +$days -delete 2>/dev/null
    fi
}

# 判定阈值颜色
threshold_color() {
    local value=$1
    local warn=$2
    local crit=$3
    if [ "$(echo "$value >= $crit" | bc 2>/dev/null)" = "1" ]; then
        echo -e "${RED}${value}${NC}"
    elif [ "$(echo "$value >= $warn" | bc 2>/dev/null)" = "1" ]; then
        echo -e "${YELLOW}${value}${NC}"
    else
        echo -e "${GREEN}${value}${NC}"
    fi
}
