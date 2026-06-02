#!/bin/bash
#
# fs-latency-collect.sh — 文件系统延迟采集脚本
# 收集文件系统 IO 延迟数据，排查 fsync/sync 慢、ext4/xfs 性能问题
#
# 用法:
#   sudo bash fs-latency-collect.sh [-d 目录] [-t 秒数]

set -o pipefail

TARGET_DIR="${TARGET_DIR:-/}"
DURATION=10
LOG_DIR="/var/log/fs-latency"
mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/fs-latency"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="$LOG_DIR/fs-latency-$TIMESTAMP.log"

echo "========== 文件系统延迟采集 ==========" | tee "$LOG_FILE"
echo "目标目录: $TARGET_DIR" | tee -a "$LOG_FILE"
echo "采集时长: ${DURATION}秒" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# 1. 挂载点信息
echo "--- 1. 挂载点信息 ---" | tee -a "$LOG_FILE"
mount | grep -E "^/dev|^$TARGET_DIR" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 2. 文件系统类型和参数
echo "--- 2. 文件系统类型 ---" | tee -a "$LOG_FILE"
df -T "$TARGET_DIR" | head -5 >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 3. 文件系统挂载参数
echo "--- 3. 挂载参数 ---" | tee -a "$LOG_FILE"
mount | grep " $TARGET_DIR " >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 4. IO 延迟采集
echo "--- 4. IO 延迟统计 (连续采样 ${DURATION}秒) ---" | tee -a "$LOG_FILE"
iostat -x 1 "$DURATION" 2>/dev/null | tail -20 >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 5. 文件系统日志状态
echo "--- 5. 文件系统日志状态 ---" | tee -a "$LOG_FILE"
dmesg -T 2>/dev/null | grep -iE 'EXT[0-9]-fs|XFS|BTRFS|f2fs|JBD2|journal' | tail -15 >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 6. 内核 IO 栈信息
echo "--- 6. 页缓存与脏页 ---" | tee -a "$LOG_FILE"
{
    echo "脏页统计:"
    cat /proc/vmstat | grep -E 'nr_dirty|nr_writeback|pgpgin|pgpgout|pswpin|pswpout'
    echo ""
    echo "Dirty 比例配置:"
    sysctl vm.dirty_ratio 2>/dev/null
    sysctl vm.dirty_background_ratio 2>/dev/null
    sysctl vm.dirty_expire_centisecs 2>/dev/null
    sysctl vm.dirty_writeback_centisecs 2>/dev/null
} >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

# 7. 文件系统缓存使用
echo "--- 7. Slab 缓存 ---" | tee -a "$LOG_FILE"
cat /proc/meminfo | grep -E 'Slab|SReclaimable|SUnreclaim' >> "$LOG_FILE"
echo "" >> "$LOG_FILE"

echo "========== 采集完成 ==========" | tee -a "$LOG_FILE"
echo "日志: $LOG_FILE"
cat "$LOG_FILE"
