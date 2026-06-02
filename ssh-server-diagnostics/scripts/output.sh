#!/bin/bash
# 输出格式化工具库
# source 后用 format_* 函数统一输出报告

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# 输出分隔线
print_separator() {
    echo ""
    echo "────────────────────────────────────────────────────"
    echo ""
}

# 输出标题
print_title() {
    local title=$1
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    printf "║  %-48s ║\n" "$title"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
}

# 输出二级标题
print_section() {
    local section=$1
    echo ""
    echo "━━━ $section ━━━"
    echo ""
}

# 输出键值对
print_kv() {
    local key=$1
    local value=$2
    printf "  %-30s %s\n" "$key:" "$value"
}

# 输出表格行
print_table_row() {
    printf "  %-20s %-15s %s\n" "$1" "$2" "$3"
}

print_table_header() {
    print_table_row "检查项" "结果" "说明"
    print_table_row "--------" "------" "------"
}

# 输出状态
print_status() {
    local status=$1
    case "$status" in
        OK|ok|正常|yes|pass)
            echo -e "  ${GREEN}✅${NC} $2"
            ;;
        WARN|warn|警告)
            echo -e "  ${YELLOW}⚠️${NC} $2"
            ;;
        FAIL|fail|异常|no)
            echo -e "  ${RED}❌${NC} $2"
            ;;
        INFO|info)
            echo -e "  ${BLUE}ℹ️${NC} $2"
            ;;
        *)
            echo "    $2"
            ;;
    esac
}

# 输出健康报告头
print_report_header() {
    local ip=$1
    local time
    time=$(date '+%Y-%m-%d %H:%M:%S')
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    printf "║  服务器诊断报告                                 ║\n"
    printf "║  IP: %-41s ║\n" "$ip"
    printf "║  时间: %-38s ║\n" "$time"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
}

# 输出总结
print_summary() {
    local total=$1
    local passed=$2
    local warns=$3
    local failed=$4
    echo ""
    echo "━━━ 检查总结 ━━━"
    echo ""
    echo "  总计: $total  通过: $passed  警告: $warns  异常: $failed"
    if [ "$failed" -gt 0 ]; then
        echo -e "  ${RED}总体评价: 存在问题，建议处理异常项${NC}"
    elif [ "$warns" -gt 0 ]; then
        echo -e "  ${YELLOW}总体评价: 基本正常，注意警告项${NC}"
    else
        echo -e "  ${GREEN}总体评价: 良好${NC}"
    fi
    echo ""
}

# JSON 输出模式
print_json() {
    local json="$1"
    if command -v python3 &> /dev/null; then
        python3 -m json.tool 2>/dev/null <<< "$json"
    elif command -v python &> /dev/null; then
        python -m json.tool 2>/dev/null <<< "$json"
    else
        echo "$json"
    fi
}
