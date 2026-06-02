#!/bin/bash
#
# sched-latency-monitor.sh — 进程调度延迟监控脚本
# 监控进程调度延迟、上下文切换频率和 CPU 排队状况
#
# 用法:
#   sudo bash sched-latency-monitor.sh -d 3 -p <PID>

set -o pipefail

# 默认参数
DURATION_HOURS=24
TARGET_PID=""
MONITOR_ALL=false
INTERVAL=60

while getopts "d:p:ai:h" opt; do
    case $opt in
        d) DURATION_HOURS="$OPTARG" ;;
        p) TARGET_PID="$OPTARG" ;;
        a) MONITOR_ALL=true ;;
        i) INTERVAL="$OPTARG" ;;
        h)
            echo "用法: $0 [-d 小时] [-p PID] [-a] [-i 间隔秒]"
            exit 0
            ;;
        *) echo "未知参数"; exit 1 ;;
    esac
done

LOG_DIR="/var/log/sched-latency-monitor"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/sched-latency-monitor"
mkdir -p "$LOG_DIR"

LOG_FILE="$LOG_DIR/sched-$(date +%Y%m%d-%H%M%S).log"

echo "========== 调度延迟监控启动 ==========" | tee "$LOG_FILE"
echo "时间: $(date)" | tee -a "$LOG_FILE"
echo "监控时长: ${DURATION_HOURS}小时" | tee -a "$LOG_FILE"
[ -n "$TARGET_PID" ] && echo "监控 PID: $TARGET_PID" | tee -a "$LOG_FILE"
echo "日志: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

END_TIME=$(( $(date +%s) + DURATION_HOURS * 3600 ))
SAMPLE_COUNT=0
MAX_SCHED_DELAY=0

while [ "$(date +%s)" -lt "$END_TIME" ]; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    SAMPLE_COUNT=$((SAMPLE_COUNT + 1))

    echo "--- [$TIMESTAMP] 采样 #$SAMPLE_COUNT ---" >> "$LOG_FILE"

    # 系统上下文切换
    if [ -f /proc/schedstat ]; then
        awk '{print "CPU等待时间: " $2 "ns"}' /proc/schedstat | head -4 >> "$LOG_FILE"
    fi

    # 运行队列长度
    if [ -f /proc/loadavg ]; then
        LOAD=$(cat /proc/loadavg | awk '{print $1, $2, $3}')
        echo "系统负载: $LOAD" >> "$LOG_FILE"
    fi

    # vmstat 队列
    vmstat 1 2 2>/dev/null | tail -1 | \
      awk '{printf "运行队列: %d  阻塞队列: %d  上下文切换: %d/s\n", $1, $2, $12}' >> "$LOG_FILE"

    # 指定 PID 或 -a
    if [ -n "$TARGET_PID" ]; then
        if [ -d "/proc/$TARGET_PID" ]; then
            cat "/proc/$TARGET_PID/sched" 2>/dev/null | grep -E 'nr_switches|wait_sum|se.statistics' >> "$LOG_FILE"
            ps -p "$TARGET_PID" -o pid,state,%cpu,%mem,comm --no-headers 2>/dev/null >> "$LOG_FILE"
        else
            echo "PID $TARGET_PID 不存在" >> "$LOG_FILE"
        fi
    fi

    if [ "$MONITOR_ALL" = true ]; then
        # D 状态进程
        D_PROCS=$(ps aux | awk '$8 ~ /^[Dd]/' | grep -v grep | wc -l)
        echo "D 状态进程数: $D_PROCS" >> "$LOG_FILE"

        # 上下文切换 Top 5
        pidstat -w 1 1 2>/dev/null | tail -6 >> "$LOG_FILE"
    fi

    sleep "$INTERVAL"
done

# 汇总
echo "" >> "$LOG_FILE"
echo "========== 监控结束 ==========" >> "$LOG_FILE"
echo "总采样数: $SAMPLE_COUNT" >> "$LOG_FILE"
echo "日志文件: $LOG_FILE" >> "$LOG_FILE"
echo ""
echo "监控完成。日志: $LOG_FILE"
