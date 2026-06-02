#!/bin/bash
#
# file-io-trace.sh — 文件 IO 追踪脚本
# 采集进程文件 IO 信息，诊断 IO 瓶颈和文件描述符泄漏
#
# 用法:
#   sudo bash file-io-trace.sh [-p PID] [-t 秒数]

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$SCRIPT_DIR/common.sh" ] && source "$SCRIPT_DIR/common.sh"

DURATION=30
TARGET_PID=""
MONITOR_ALL=true

while getopts "p:t:ah" opt; do
    case $opt in
        p) TARGET_PID="$OPTARG"; MONITOR_ALL=false ;;
        t) DURATION="$OPTARG" ;;
        a) MONITOR_ALL=true ;;
        h)
            echo "用法: $0 [-p PID] [-t 采集时长秒] [-a 全部进程]"
            exit 0 ;;
        *) echo "未知参数"; exit 1 ;;
    esac
done

LOG_DIR="/var/log/file-io-trace"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/file-io-trace"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOG_DIR/io-trace-$TIMESTAMP.log"

echo "========== 文件 IO 追踪 ==========" | tee "$LOG_FILE"
echo "时间: $(date)" | tee -a "$LOG_FILE"
echo "采集时长: ${DURATION}秒" | tee -a "$LOG_FILE"
echo "日志: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 1. 系统 IO 概览
echo "--- 1. 系统 IO 概览 ---" | tee -a "$LOG_FILE"
iostat -x 1 3 2>/dev/null | tail -15 >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 2. IO 等待进程
echo "--- 2. 进程 IO 统计 ---" | tee -a "$LOG_FILE"
pidstat -d 1 3 2>/dev/null | tail -15 >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 3. 文件描述符分析
echo "--- 3. 文件描述符分析 ---" | tee -a "$LOG_FILE"
if [ -n "$TARGET_PID" ]; then
    # 指定 PID
    if [ -d "/proc/$TARGET_PID" ]; then
        FD_COUNT=$(ls /proc/$TARGET_PID/fd 2>/dev/null | wc -l)
        echo "PID $TARGET_PID FD 数: $FD_COUNT" | tee -a "$LOG_FILE"
        echo "打开文件类型分布:" >> "$LOG_FILE"
        ls -la /proc/$TARGET_PID/fd 2>/dev/null | awk '{print $NF}' | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10 >> "$LOG_FILE"
    else
        echo "PID $TARGET_PID 不存在" | tee -a "$LOG_FILE"
    fi
fi

if [ "$MONITOR_ALL" = true ]; then
    echo "FD 数 Top 15 进程:" >> "$LOG_FILE"
    for pid_dir in /proc/[0-9]*/; do
        pid=$(basename "$pid_dir")
        fd=$(ls "$pid_dir/fd" 2>/dev/null | wc -l)
        cmd=$(cat "$pid_dir/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 60)
        echo "$fd|$pid|$cmd"
    done 2>/dev/null | sort -rn | head -15 >> "$LOG_FILE"
fi
echo "" >> "$LOG_FILE"

# 4. IO 延迟跟踪（带 D 状态检测）
echo "--- 4. IO 阻塞进程（D 状态）---" | tee -a "$LOG_FILE"
ps aux | awk '$8 ~ /^[Dd]/' | grep -v grep >> "$LOG_FILE"
D_COUNT=$(ps aux | awk '$8 ~ /^[Dd]/' | grep -v grep | wc -l)
echo "D 状态进程数: $D_COUNT" | tee -a "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 5. 磁盘错误
echo "--- 5. 磁盘错误日志 ---" | tee -a "$LOG_FILE"
dmesg -T 2>/dev/null | grep -iE 'I/O error|buffer error|disk error|medium error' | tail -10 >> "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 6. 文件系统缓存状态
echo "--- 6. 文件系统缓存 ---" | tee -a "$LOG_FILE"
cat /proc/meminfo | grep -E 'Dirty|Writeback|NFS_Unstable|PageTables' >> "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

echo "========== 采集完成 ==========" | tee -a "$LOG_FILE"
echo "日志: $LOG_FILE"
