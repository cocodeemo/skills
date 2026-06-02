#!/bin/bash
#
# collect_memory_leak.sh — 用户态内存泄漏数据采集脚本
# 持续监控可疑进程的内存使用趋势，辅助泄漏判定
#
# 用法:
#   sudo bash collect_memory_leak.sh [-p PID] [-d 采集时长秒] [-i 间隔秒]

set -o pipefail

MONITOR_PID=""
DURATION=300
INTERVAL=30
LOG_DIR="/var/log/memory-leak"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/memory-leak"
mkdir -p "$LOG_DIR"

while getopts "p:d:i:h" opt; do
    case $opt in
        p) MONITOR_PID="$OPTARG" ;;
        d) DURATION="$OPTARG" ;;
        i) INTERVAL="$OPTARG" ;;
        h)
            echo "用法: $0 [-p PID] [-d 时长秒] [-i 间隔秒]"
            echo "  不指定 PID 则监控内存占用 Top 5 进程"
            exit 0 ;;
        *) echo "未知参数"; exit 1 ;;
    esac
done

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOG_DIR/memory-leak-$TIMESTAMP.csv"
SUMMARY_FILE="$LOG_DIR/memory-leak-$TIMESTAMP-summary.txt"

# CSV 头
echo "timestamp,pid,name,rss_kb,vsz_kb,fd_count,threads" > "$LOG_FILE"

END_TIME=$(( $(date +%s) + DURATION ))
SAMPLES=0
declare -A INITIAL_RSS
declare -A MAX_RSS

echo "========== 内存泄漏监控启动 ==========" | tee "$SUMMARY_FILE"
echo "时间: $(date)" | tee -a "$SUMMARY_FILE"
echo "监控时长: ${DURATION}秒" | tee -a "$SUMMARY_FILE"
echo "采样间隔: ${INTERVAL}秒" | tee -a "$SUMMARY_FILE"
echo "PID: ${MONITOR_PID:-全部 Top 5}" | tee -a "$SUMMARY_FILE"
echo "日志: $LOG_FILE" | tee -a "$SUMMARY_FILE"
echo "" | tee -a "$SUMMARY_FILE"

while [ "$(date +%s)" -lt "$END_TIME" ]; do
    TIMESTAMP_NOW=$(date '+%Y-%m-%d %H:%M:%S')
    SAMPLES=$((SAMPLES + 1))

    if [ -n "$MONITOR_PID" ]; then
        # 监控指定 PID
        if [ ! -d "/proc/$MONITOR_PID" ]; then
            echo "PID $MONITOR_PID 已退出，停止监控" | tee -a "$SUMMARY_FILE"
            break
        fi
        RSS=$(awk '/VmRSS/{print $2}' /proc/$MONITOR_PID/status 2>/dev/null)
        VSZ=$(awk '/VmSize/{print $2}' /proc/$MONITOR_PID/status 2>/dev/null)
        FD=$(ls /proc/$MONITOR_PID/fd 2>/dev/null | wc -l)
        THR=$(awk '/Threads/{print $2}' /proc/$MONITOR_PID/status 2>/dev/null)
        NAME=$(cat /proc/$MONITOR_PID/comm 2>/dev/null)
        echo "$TIMESTAMP_NOW,$MONITOR_PID,$NAME,${RSS:-0},${VSZ:-0},${FD:-0},${THR:-0}" >> "$LOG_FILE"

        if [ -z "${INITIAL_RSS[$MONITOR_PID]}" ]; then
            INITIAL_RSS[$MONITOR_PID]=${RSS:-0}
        fi
        if [ "${RSS:-0}" -gt "${MAX_RSS[$MONITOR_PID]:-0}" ]; then
            MAX_RSS[$MONITOR_PID]=${RSS:-0}
        fi
    else
        # 监控 Top 5 RSS 进程
        for pid in $(ps -eo pid --sort=-rss 2>/dev/null | head -6 | tail -5); do
            if [ -d "/proc/$pid" ]; then
                RSS=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
                VSZ=$(awk '/VmSize/{print $2}' /proc/$pid/status 2>/dev/null)
                FD=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
                THR=$(awk '/Threads/{print $2}' /proc/$pid/status 2>/dev/null)
                NAME=$(cat /proc/$pid/comm 2>/dev/null)
                echo "$TIMESTAMP_NOW,$pid,$NAME,${RSS:-0},${VSZ:-0},${FD:-0},${THR:-0}" >> "$LOG_FILE"

                if [ -z "${INITIAL_RSS[$pid]}" ]; then
                    INITIAL_RSS[$pid]=${RSS:-0}
                fi
                if [ "${RSS:-0}" -gt "${MAX_RSS[$pid]:-0}" 2>/dev/null ]; then
                    MAX_RSS[$pid]=${RSS:-0}
                fi
            fi
        done
    fi

    echo "[$TIMESTAMP_NOW] 采样 #$SAMPLES 完成" | tee -a "$SUMMARY_FILE"
    sleep "$INTERVAL"
done

# 生成分析报告
echo "" | tee -a "$SUMMARY_FILE"
echo "========== 内存趋势分析 ==========" | tee -a "$SUMMARY_FILE"
echo "总采样数: $SAMPLES" | tee -a "$SUMMARY_FILE"
echo "" | tee -a "$SUMMARY_FILE"
echo "进程内存变化:" | tee -a "$SUMMARY_FILE"

for pid in "${!INITIAL_RSS[@]}"; do
    INIT=${INITIAL_RSS[$pid]:-0}
    MAX=${MAX_RSS[$pid]:-0}
    GROWTH=$((MAX - INIT))
    NAME=$(cat /proc/$pid/comm 2>/dev/null || echo "已退出")
    echo "  PID $pid ($NAME): 初始=${INIT}KB 峰值=${MAX}KB 增长=${GROWTH}KB" | tee -a "$SUMMARY_FILE"

    if [ "$GROWTH" -gt 102400 ]; then
        echo "    ⚠️ 疑似泄漏: RSS 增长超过 100MB" | tee -a "$SUMMARY_FILE"
    elif [ "$GROWTH" -gt 10240 ]; then
        echo "    🟡 关注: RSS 增长超过 10MB" | tee -a "$SUMMARY_FILE"
    else
        echo "    ✅ 正常范围内" | tee -a "$SUMMARY_FILE"
    fi
done

echo "" | tee -a "$SUMMARY_FILE"
echo "原始数据: $LOG_FILE" | tee -a "$SUMMARY_FILE"
echo "分析完成" | tee -a "$SUMMARY_FILE"
cat "$SUMMARY_FILE"
