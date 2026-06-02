---
name: disk-depth
description: 磁盘深度管理——LVM 逻辑卷管理、磁盘分区扩容、SMART 磁盘健康检测、文件系统修复检查。
version: 1.0.0
---

# 磁盘深度管理

覆盖 LVM 逻辑卷管理、磁盘分区与扩容、SMART 磁盘健康检测和文件系统完整性检查。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动执行任何磁盘写操作**。
>
> 分区创建、LVM 操作、格式化、扩容等命令仅作为参考提供给用户。

## 适用场景

### 用户可能的问题表述

- "磁盘怎么扩容"、"LVM 怎么加硬盘"
- "新加的磁盘看不到"、"pvcreate 怎么用"
- "磁盘是不是快坏了"、"SMART 检测"
- "文件系统坏了"、"fsck 检查"

---

## 诊断步骤

### 步骤 1：磁盘与分区总览

```bash
echo '=== 所有块设备 ===' && \
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL 2>/dev/null && \
echo '' && \
echo '=== 磁盘详细信息 ===' && \
fdisk -l 2>/dev/null | grep -E 'Disk /dev|Disk model|sectors|bytes' | head -15
```

### 步骤 2：LVM 检查（如有）

```bash
echo '=== PV 物理卷 ===' && \
pvs 2>/dev/null || echo '无 LVM 物理卷' && \
echo '' && \
echo '=== VG 卷组 ===' && \
vgs 2>/dev/null || echo '无 LVM 卷组' && \
echo '' && \
echo '=== LV 逻辑卷 ===' && \
lvs 2>/dev/null || echo '无 LVM 逻辑卷' && \
echo '' && \
echo '=== LVM 概况 ===' && \
lvdisplay 2>/dev/null | grep -E 'LV Path|LV Size|LV Status' | head -10
```

**LVM 状态解读**：
- `pvs` 显示 PV 列表，`PFree` 列显示未分配空间
- `vgs` 显示 VG 容量和剩余，`VFree` > 0 说明可扩容
- `lvs` 显示 LV 大小

### 步骤 3：磁盘健康检测（SMART）

```bash
echo '=== SMART 健康状态 ===' && \
for disk in $(lsblk -ndo NAME 2>/dev/null | grep -v loop); do \
  echo "--- /dev/$disk ---" && \
  smartctl -H /dev/$disk 2>/dev/null | grep -E 'SMART overall-health|SMART Health|PASSED|FAILED' || echo 'SMART 不支持（云盘正常）'; \
done && \
echo '' && \
echo '=== 磁盘错误计数 ===' && \
cat /sys/block/*/device/iorequest_cnt 2>/dev/null | head -3 && \
echo '' && \
echo '=== 磁盘介质错误 ===' && \
dmesg -T 2>/dev/null | grep -iE 'medium error|I/O error|disk failure|uncorrectable|bad sector' | tail -10 || echo '无磁盘介质错误'
```

**注意**：阿里云/腾讯云等云主机 VBD 盘通常不支持 SMART，返回"不支持"是正常的。

### 步骤 4：文件系统检查

```bash
echo '=== 已挂载文件系统类型 ===' && \
df -T | head -15 && \
echo '' && \
echo '=== fstab 配置 ===' && \
cat /etc/fstab 2>/dev/null && \
echo '' && \
echo '=== 文件系统只读检测 ===' && \
mount | grep -E 'ro,' | head -5 || echo '无只读挂载' && \
echo '' && \
echo '=== 文件系统错误 ===' && \
dmesg -T 2>/dev/null | grep -iE 'EXT[0-9]-fs error|xfs.*error|corruption|journal error' | tail -10 || echo '无文件系统错误'
```

### 步骤 5：磁盘性能基准（快速测试）

```bash
echo '=== 顺序读测试（5秒） ===' && \
dd if=/dev/vda of=/dev/null bs=1M count=512 2>&1 | tail -1 || dd if=/dev/sda of=/dev/null bs=1M count=512 2>&1 | tail -1 || echo 'dd 测试跳过' && \
echo '' && \
echo '=== 磁盘缓存状态 ===' && \
cat /proc/meminfo | grep -E 'Dirty|Writeback|NFS_Unstable'
```

> **注意**：dd 测试会影响 IO，生产环境谨慎执行。

---

## 报告格式

```
### 🟢 磁盘设备
| 设备 | 大小 | 类型 | 挂载点 |
|------|------|------|--------|

### 🟢 LVM 状态
PV: 已配置 / 未使用
VG 剩余空间: xxx GB

### 🟢 磁盘健康
SMART: 正常 / 不支持（云盘）

### ⚠️ 建议
```
