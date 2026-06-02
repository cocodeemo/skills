#!/bin/bash
#
# collect_oom_info.sh — OOM Killer 事件采集脚本
# 收集 dmesg、journalctl 中的 OOM 事件，采集当时的内存快照
#
# 用法:
#   sudo bash collect_oom_info.sh

LOG_DIR="/var/log/oom-collector"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/oom-collector"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
OUTPUT_DIR="$LOG_DIR/oom-$TIMESTAMP"
mkdir -p "$OUTPUT_DIR"

echo "========== OOM 信息采集 =========="
echo "输出目录: $OUTPUT_DIR"
echo ""

# 1. dmesg OOM 日志
echo "[1/5] 采集 dmesg OOM 日志..."
dmesg -T 2>/dev/null | grep -iE 'oom|out of memory|killed|invoked oom-killer' > "$OUTPUT_DIR/dmesg-oom.log" || \
dmesg | grep -iE 'oom|out of memory|killed' > "$OUTPUT_DIR/dmesg-oom.log"
echo "  → $(wc -l < "$OUTPUT_DIR/dmesg-oom.log") 条记录"

# 2. journalctl OOM 日志
if command -v journalctl &> /dev/null; then
    echo "[2/5] 采集 journalctl OOM 日志..."
    journalctl -k --no-pager 2>/dev/null | grep -iE 'oom|out of memory|killed' > "$OUTPUT_DIR/journal-oom.log" 2>/dev/null
    echo "  → $(wc -l < "$OUTPUT_DIR/journal-oom.log") 条记录"
else
    echo "[2/5] journalctl 不可用，跳过"
fi

# 3. 当前内存快照
echo "[3/5] 采集当前内存快照..."
{
    echo "=== 内存总览 ==="
    free -h
    echo ""
    echo "=== MemInfo 详细 ==="
    cat /proc/meminfo | grep -E 'MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|Dirty|AnonPages|Mapped|PageTables'
    echo ""
    echo "=== 内存占用 Top 20 ==="
    ps aux --sort=-%mem | head -21
} > "$OUTPUT_DIR/memory-snapshot.txt"
echo "  → 快照已保存"

# 4. 进程内存详情
echo "[4/5] 采集进程内存详情..."
{
    echo "=== 进程 RSS Top 20 ==="
    ps -eo pid,rss,vsz,%mem,cmd --sort=-rss | head -21
    echo ""
    echo "=== 各用户内存占用 ==="
    ps aux | awk 'NR>1 {arr[$1]+=$6} END {for(i in arr) printf "%-20s %.1f MB\n", i, arr[i]/1024}' | sort -rn -k2 | head -10
    echo ""
    echo "=== Swap 使用进程 ==="
    for pid_dir in /proc/[0-9]*/; do
        pid=$(basename "$pid_dir")
        swap=$(awk '/Swap:/ {print $2}' "$pid_dir/status" 2>/dev/null)
        if [ -n "$swap" ] && [ "$swap" -gt 0 ] 2>/dev/null; then
            cmd=$(cat "$pid_dir/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 80)
            echo "PID $pid Swap=${swap}kB $cmd"
        fi
    done 2>/dev/null | sort -t= -k2 -rn | head -10
    echo ""
    echo "=== OOM score 调整值 Top 10 ==="
    for pid_dir in /proc/[0-9]*/; do
        pid=$(basename "$pid_dir")
        score=$(cat "$pid_dir/oom_score" 2>/dev/null)
        adj=$(cat "$pid_dir/oom_score_adj" 2>/dev/null)
        cmd=$(cat "$pid_dir/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 60)
        echo "PID $pid oom_score=$score adj=$adj $cmd"
    done 2>/dev/null | sort -t= -k2 -rn | head -15
} > "$OUTPUT_DIR/process-memory.txt"
echo "  → 进程详情已保存"

# 5. 系统日志关键报错
echo "[5/5] 采集系统关键报错..."
journalctl -p err -b --no-pager 2>/dev/null | tail -50 > "$OUTPUT_DIR/system-errors.log" 2>/dev/null
dmesg -T 2>/dev/null | grep -iE 'error|fail|panic' | tail -30 > "$OUTPUT_DIR/kernel-errors.log" 2>/dev/null || \
dmesg | grep -iE 'error|fail|panic' | tail -30 > "$OUTPUT_DIR/kernel-errors.log"
echo "  → 完成"

echo ""
echo "========== 采集完成 =========="
echo "输出目录: $OUTPUT_DIR"
echo "使用以下命令分析: python3 parse_oom_events.py $OUTPUT_DIR"
