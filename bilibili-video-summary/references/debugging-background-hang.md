# 后台挂死诊断经验（2025-06，BV1BFjS65E6B 会话）

## 症状

`terminal(background=true)` 跑 ASR 管线脚本，8 分钟零输出，`process poll` 和 `process log` 均为空。

## 诊断过程

1. **进程在跑但 CPU 为 0%** → 卡在网络 I/O 等待（curl_cffi 下载）
2. **零输出** → stdout 全缓冲：Python 在非 TTY 后台模式下 stdout 完全缓冲，缓冲区未满或进程未退出时不 flush
3. **下载超时** → curl_cffi 第一次 120s timeout 触发 `curl: (28) Operation timed out`，但脚本无重试逻辑，静默失败

## 根因（双重）

| 层 | 问题 |
|----|------|
| I/O 层 | Python stdout 在 `terminal(background=true)` 下完全缓冲 |
| 网络层 | B站 CDN 对该视频限速 ~25KB/s（18MB 需 ~720s），120s 只收到 3MB |
| 脚本层 | 原脚本无超时重试，失败即停止，但因缓冲无输出，无从诊断 |

## 修复方案

1. **stderr 输出进度**：`print(..., file=sys.stderr, flush=True)` — stderr 永远无缓冲
2. **双超时退避**：120s → 600s → 失败后 curl `-C -` 续传 900s
3. **调用时加 `2>&1`**：Hermes 的 `process poll` 只看 stdout，`2>&1` 合并 stderr
4. **每步带时间戳**：`[HH:MM:SS]` 格式，ASR 每 30s 报告段落进度

## 验证结果

### 测试 1：BV1BFjS65E6B（CDN 限速场景）

```
[10:29:56] 步骤1/5: 获取视频元数据...
[10:29:56]   标题: -13，多重利空叙事引发跳水
[10:29:56] 步骤2/5: 获取 WBI 签名密钥...
[10:29:56] 步骤3/5: 获取音频流 URL...
[10:29:56] 步骤4/5: 下载音频（自动超时重试）...
[10:29:56]   下载尝试 1/2 (timeout=120s)...
[10:31:56]   尝试 1 失败: Timeout (已收 3024KB)
[10:31:56]   切换到长超时 (600s) 重试...
```

✅ 实时可见进度，自动重试。但因 CDN 带宽极低（~25KB/s），600s 仍不够，后续需 curl `-C -` 续传 900s 兜底。

### 测试 2：BV1VrQBB8Edc（瞬时连接故障场景）

```
[10:46:18] 步骤1/5: 获取视频元数据...
[10:46:18]   标题: IT面试高分必须先准备好场景
[10:46:18]   时长: 14:03
[10:46:18] 步骤4/5: 下载音频（自动超时重试）...
[10:46:18]   下载尝试 1/2 (timeout=120s)...
[10:46:29]   尝试 1 失败: ConnectionError
[10:46:29]   切换到长超时 (600s) 重试...
[10:46:34]   下载完成: 7.9 MB
[10:46:34]   转 WAV (16kHz mono)...
[10:46:36]   WAV 完成: 25.7 MB
[10:46:36] 步骤5/5: ASR 转写 (faster-whisper tiny)...
[10:48:00]   转写完成: 603 段, 14726 字符, 耗时 82s
```

✅ 瞬时 `ConnectionError` 被重试 5 秒内恢复。全流程 14:03 视频仅用 ~100s 完成。

## 两种失败模式对比

| 模式 | 错误类型 | 重试效果 | 出现概率 |
|------|---------|---------|---------|
| CDN 限速 | `curl: (28) Operation timed out` + 部分字节 | 需长超时或 curl `-C -` 续传 | 低频（特定 CDN 节点） |
| 瞬时连接故障 | `ConnectionError`（0 字节） | 立即重试通常秒级恢复 | 中频（B站反爬波动） |

## curl_cffi timeout 错误特征

```
Failed to perform, curl: (28) Operation timed out after 120000 milliseconds
with 3096576 out of 18708350 bytes received.
```

关键信息：`out of` 后面的总字节数可估算 CDN 带宽。此处 3MB/120s ≈ 25KB/s，需 720s 完整下载。
