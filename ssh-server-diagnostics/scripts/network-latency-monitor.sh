#!/bin/bash
#
# network-latency-monitor.sh — 网络丢包和延迟长期监控脚本
# 通用版本，适用于任何 Linux 发行版
#
# 用法:
#   sudo bash network-latency-monitor.sh -t <目标地址> -d 7 -L 1 -R 100
#
# 参数:
#   -t TARGET    目标 IP 或域名（必填）
#   -d DAYS      监控天数（默认 1）
#   -L LOSS      丢包告警阈值 %（默认 1）
#   -R RTT       RTT 告警阈值 ms（默认 100）
#   -i INTERVAL  Ping 间隔秒（默认 30）
#   -c COUNT     每轮 ping 包数（默认 10）

set -o pipefail

# 默认参数
TARGET="${TARGET:-}"
DURATION_DAYS="${DURATION_DAYS:-1}"
LOSS_THRESHOLD="${LOSS_THRESHOLD:-1}"
RTT_THRESHOLD="${RTT_THRESHOLD:-100}"
LOG_DIR="/var/log/network-latency-monitor"
PING_INTERVAL=30
PING_COUNT=10
NIC=""

# 解析参数
while getopts "t:d:L:R:i:c:n:h" opt; do
    case $opt in
        t) TARGET="$OPTARG" ;;
        d) DURATION_DAYS="$OPTARG" ;;
        L) LOSS_THRESHOLD="$OPTARG" ;;
        R) RTT_THRESHOLD="$OPTARG" ;;
        i) PING_INTERVAL="$OPTARG" ;;
        c) PING_COUNT="$OPTARG" ;;
        n) NIC="$OPTARG" ;;
        h)
            echo "用法: $0 [-t 目标地址] [-d 天数] [-L 丢包阈值%%] [-R RTT阈值ms]"
            echo "       [-i 间隔秒] [-c ping包数] [-n 网卡名]"
            exit 0
            ;;
        *) echo "未知参数: -$OPTARG"; exit 1 ;;
    esac
done

# 检查必要参数
if [ -z "$TARGET" ]; then
    echo "错误: 必须指定目标地址 (-t)"
    exit 1
fi

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 创建日志目录
mkdir -p "$LOG_DIR" || {
    LOG_DIR="/tmp/network-latency-monitor"
    mkdir -p "$LOG_DIR"
}

# 自动检测出口网卡
if [ -z "$NIC" ]; then
    NIC=$(ip route show default | awk '{print $5}' | head -1)
fi

LOG_FILE="$LOG_DIR/latency-$(date +%Y%m%d-%H%M%S).log"
SUMMARY_FILE="$LOG_DIR/summary-$(date +%Y%m%d-%H%M%S).txt"

echo "==========================================" | tee -a "$LOG_FILE"
echo "网络延迟监控启动" | tee -a "$LOG_FILE"
echo "目标: $TARGET" | tee -a "$LOG_FILE"
echo "监控天数: $DURATION_DAYS" | tee -a "$LOG_FILE"
echo "丢包阈值: ${LOSS_THRESHOLD}%" | tee -a "$LOG_FILE"
echo "RTT阈值: ${RTT_THRESHOLD}ms" | tee -a "$LOG_FILE"
echo "网卡: $NIC" | tee -a "$LOG_FILE"
echo "日志: $LOG_FILE" | tee -a "$LOG_FILE"
echo "==========================================" | tee -a "$LOG_FILE"
echo ""

END_TIME=$(( $(date +%s) + DURATION_DAYS * 86400 ))
TOTAL_LOSS=0
TOTAL_COUNT=0
RTT_SUM=0
ALERT_COUNT=0

# 主循环
while [ "$(date +%s)" -lt "$END_TIME" ]; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

    # Ping 测试
    PING_OUTPUT=$(ping -c "$PING_COUNT" -W 3 -q "$TARGET" 2>&1)
    PING_EXIT=$?

    if [ $PING_EXIT -ne 0 ]; then
        echo -e "${RED}[$TIMESTAMP]❌ Ping 失败${NC}" | tee -a "$LOG_FILE"
        echo "$TIMESTAMP|FAIL|100|0" >> "$LOG_FILE"
    else
        LOSS=$(echo "$PING_OUTPUT" | grep -oP '\d+(?=% packet loss)')
        RTT=$(echo "$PING_OUTPUT" | grep -oP '(?<=avg = )\d+\.?\d*')
        RTT_INT=$(echo "$RTT" | cut -d. -f1)

        TOTAL_LOSS=$((TOTAL_LOSS + LOSS))
        TOTAL_COUNT=$((TOTAL_COUNT + 1))
        RTT_SUM=$(echo "$RTT_SUM + $RTT" | bc 2>/dev/null || echo "$RTT_SUM")

        if [ "$LOSS" -ge "$LOSS_THRESHOLD" ] || [ "$RTT_INT" -ge "$RTT_THRESHOLD" ]; then
            ALERT_COUNT=$((ALERT_COUNT + 1))
            echo -e "${YELLOW}⚠ [$TIMESTAMP] 丢包=${LOSS}% RTT=${RTT}ms${NC}" | tee -a "$LOG_FILE"
        else
            echo -e "${GREEN}✓ [$TIMESTAMP] 丢包=${LOSS}% RTT=${RTT}ms${NC}" | tee -a "$LOG_FILE"
        fi
        echo "$TIMESTAMP|$LOSS|$RTT" >> "$LOG_FILE"
    fi

    sleep "$PING_INTERVAL"
done

# 生成汇总报告
echo "" | tee -a "$SUMMARY_FILE"
echo "========== 网络延迟监控报告 ==========" | tee -a "$SUMMARY_FILE"
echo "目标: $TARGET" | tee -a "$SUMMARY_FILE"
echo "监控时长: $DURATION_DAYS 天" | tee -a "$SUMMARY_FILE"
echo "总轮次: $TOTAL_COUNT" | tee -a "$SUMMARY_FILE"
echo "告警次数: $ALERT_COUNT" | tee -a "$SUMMARY_FILE"
if [ $TOTAL_COUNT -gt 0 ]; then
    AVG_LOSS=$((TOTAL_LOSS / TOTAL_COUNT))
    AVG_RTT=$(echo "scale=1; $RTT_SUM / $TOTAL_COUNT" | bc 2>/dev/null)
    echo "平均丢包率: ${AVG_LOSS}%" | tee -a "$SUMMARY_FILE"
    echo "平均 RTT: ${AVG_RTT}ms" | tee -a "$SUMMARY_FILE"
fi
echo "日志文件: $LOG_FILE" | tee -a "$SUMMARY_FILE"
echo "========================================" | tee -a "$SUMMARY_FILE"

echo ""
echo "监控完成。报告已保存至: $SUMMARY_FILE"
