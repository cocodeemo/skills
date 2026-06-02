---
name: disk-analysis
description: 磁盘空间、IO 性能与文件系统深度分析。覆盖空间排查、大文件定位、IO 瓶颈检测、文件系统挂载检查。
version: 1.0.0
---

# 磁盘深度分析

覆盖磁盘空间使用排查、大文件定位、磁盘 IO 性能检测和文件系统挂载检查。

## 安全原则

> ⚠️ **重要**：AI 只执行诊断命令（查看、分析），**不自动执行任何删除、格式化、分区操作**。
> 
> 清理/扩容/修复命令仅作为参考提供给用户，由用户自行判断和手动执行。

## 适用场景

### 用户可能的问题表述

**空间不足类**：
- "磁盘满了"、"No space left on device"
- "空间不够了"、"根目录满了"
- "/var 目录占用太大"

**IO 性能类**：
- "磁盘很慢"、"IO 很高"、"iowait 高"
- "服务器卡顿，怀疑是磁盘问题"
- "读写速度慢"

**文件系统类**：
- "挂载不上"、"fstab 有问题"
- "文件系统只读了"、"mount 异常"
- "新加的磁盘看不到"

---

## 诊断步骤

### 步骤 1：空间使用概览

```bash
echo '=== 分区使用率 ===' && \
df -h && \
echo '' && \
echo '=== inode 使用率 ===' && \
df -i | head -10 && \
echo '' && \
echo '=== 分区表 ===' && \
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT
```

**输出解读**：
- 使用率 > 80% → 🟡 关注
- 使用率 > 90% → 🔴 需立即处理
- inode 使用率 > 80% → 小文件过多，即使空间还有也可能写不了文件

### 步骤 2：找到大目录/大文件

```bash
echo '=== 根目录下各目录大小 ===' && \
du -sh /* 2>/dev/null | sort -rh | head -15 && \
echo '' && \
echo '=== /var 下各目录大小 ===' && \
du -sh /var/* 2>/dev/null | sort -rh | head -10 && \
echo '' && \
echo '=== /home 下各目录大小 ===' && \
du -sh /home/* 2>/dev/null | sort -rh | head -5 && \
echo '' && \
echo '=== 根目录下大于 100M 的文件 ===' && \
find / -xdev -type f -size +100M -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -10
```

**输出解读**：
- 重点关注 `du -sh /*` 中占用最大的目录
- `/var/log/` 日志目录持续增长可能是日志未轮转
- `/var/lib/docker/` Docker 数据目录可能很大
- `/tmp/` 临时文件堆积

### 步骤 3：Docker 磁盘占用（如有 Docker）

```bash
echo '=== Docker 磁盘占用 ===' && \
docker system df 2>/dev/null || echo 'Docker 不可用' && \
echo '' && \
echo '=== 各容器数据大小 ===' && \
docker ps -q 2>/dev/null | xargs docker inspect --format='{{.Name}} {{.SizeRootFs}}' 2>/dev/null || true
```

### 步骤 4：磁盘 IO 性能检测

```bash
echo '=== IO 统计（连续采集 3 次间隔 1s） ===' && \
iostat -x 1 3 2>/dev/null || iostat -x 3 1 2>/dev/null && \
echo '' && \
echo '=== IO 等待的进程 ===' && \
iotop -b -n 1 2>/dev/null | head -10 || echo 'iotop 未安装' && \
echo '' && \
echo '=== 磁盘 I/O 队列深度 ===' && \
cat /sys/block/*/queue/nr_requests 2>/dev/null | head -3 && \
echo '' && \
echo '=== 磁盘调度器 ===' && \
cat /sys/block/*/queue/scheduler 2>/dev/null | head -3
```

**输出解读**：

| 指标 | 正常 | 警告 | 异常 |
|------|------|------|------|
| %util | < 30% | 30% ~ 70% | > 70% |
| await | < 10ms | 10ms ~ 30ms | > 30ms |
| svctm | < 5ms | 5ms ~ 10ms | > 10ms |
| r_await / w_await | < 10ms | 10ms ~ 30ms | > 30ms |
| avgqu-sz | < 1 | 1 ~ 5 | > 5 |

- **%util 高 + await 正常** → 设备能力到了上限，考虑升级
- **%util 不高 + await 高** → 可能是磁盘硬件问题或有 IO 排队
- **r_await >> w_await** → 读性能差（可能是 HDD，或磁盘有坏道）

### 步骤 5：文件系统与挂载检查

```bash
echo '=== 挂载信息 ===' && \
mount | column -t && \
echo '' && \
echo '=== fstab ===' && \
cat /etc/fstab 2>/dev/null && \
echo '' && \
echo '=== 已挂载 vs fstab 对比 ===' && \
echo 'fstab 中配置的分区:' && \
awk '!/^#/ && NF>0 {print $1,$2}' /etc/fstab 2>/dev/null && \
echo '' && \
echo '当前已挂载:' && \
mount | awk '{print $1,$3}' | sort && \
echo '' && \
echo '=== 文件系统只读检测 ===' && \
mount | grep -E 'ro,' | head -5 || echo '无只读挂载' && \
echo '' && \
echo '=== 磁盘错误 ===' && \
dmesg -T 2>/dev/null | grep -iE 'I/O error|buffer error|disk error|medium error' | tail -5 || echo '无磁盘错误日志'
```

**输出解读**：
- 检查 fstab 中的分区是否都已挂载
- 出现 `ro,`（只读挂载）→ 通常意味着文件系统有严重错误
- dmesg 中出现 `I/O error` → 磁盘可能有硬件问题

### 步骤 6：SMART 磁盘健康（物理机或支持直通时）

```bash
echo '=== SMART 信息 ===' && \
smartctl -H /dev/vda 2>/dev/null || echo 'SMART 不支持（云盘通常不支持）'
```

**注意**：阿里云 ECS 的云盘通常不支持 SMART，会返回不支持信息，这是正常的。

---

## 报告格式

```
### 🟢 磁盘整体状态
| 指标 | 值 | 判定 |
|------|-----|------|
| 最大使用率 | xx% (/dev/vda1) | 🟢 正常 |

### 🟢 / 🟡 / 🔴 详细信息
...

### ✅ / ⚠️ 建议
- xxx
```
