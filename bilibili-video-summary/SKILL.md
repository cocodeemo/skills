---
name: bilibili-video-summary
description: 获取 B 站视频元数据/字幕/音频并做 AI 总结。优先 CC 字幕，无字幕时走 ASR 音频转文字。触发条件：用户发 B 站链接要求总结/分析/看看视频内容。
version: 2.1.0
platforms: [linux]
metadata:
  hermes:
    tags: [bilibili, video, summary, asr, whisper, transcript, chinese]
    category: devops
    requires_toolsets: [terminal]
    related_skills: [bilibili-subtitle-analysis]
---

# B 站视频总结

输入 B 站链接，获取视频内容并生成结构化 AI 总结。

## 用户偏好

- **简洁第一**：不要下载视频文件，不要逐帧分析
- **ASR 可接受**：音频下载 (~9MB/20min) 可以，不装重型依赖（torch/CUDA toolkit）
- **速度优先**：默认 `tiny` 模型，追求质量才用 `base`
- **总结必须深度**：不要只出大纲——提取具体观点、案例、数据。过滤口水话（"对吧""是不是"），按主题分段，标注时间戳
- **必须清理**：总结完成后删除 .m4s 和 .wav，保留 .txt 供查阅

## 工作流（按优先级尝试）

### 第一步：提取元数据（总是可用，< 1 秒）

```python
from curl_cffi import requests

resp = requests.get(
    f'https://api.bilibili.com/x/web-interface/view?bvid={bvid}',
    headers={'Referer': 'https://www.bilibili.com/'},
    impersonate='chrome131', timeout=15
)
data = resp.json()['data']
# data['title'], data['owner']['name'], data['duration'], data['desc'], data['cid']
```

**关键**：必须 `curl_cffi` + `impersonate='chrome131'`，标准 `urllib`/`requests` 触发 HTTP 412。

### 第二步：尝试 CC 字幕（成功率 ~1%）

```python
resp2 = requests.get(
    f'https://api.bilibili.com/x/player/v2?bvid={bvid}&cid={cid}',
    headers={'Referer': f'https://www.bilibili.com/video/{bvid}/'},
    impersonate='chrome131', timeout=15
)
subs = resp2.json()['data'].get('subtitle', {}).get('subtitles', [])
# ai_type == 1 → AI 字幕, 0 → 手动字幕
```

**残酷现实**：绝大多数 B 站视频 `subtitles` 为空数组。即使用户在播放器里能看到 AI 字幕，公开 API 也不返回——AI 字幕需浏览器 JS 动态加载。此步骤仅作为快速尝试。

### 第三步：ASR 音频转文字（核心能力，已完整验证）

当字幕为空时，走 ASR 路线。**推荐使用 `scripts/bilibili-ai-summary.py` 一键完成**（已内置超时重试 + stderr 进度输出），调用时必须加 `2>&1` 合并 stderr 到可见输出。

```bash
python3 scripts/bilibili-ai-summary.py <BVID> 2>&1
# 前台跑即可，600s 超时足够绝大多数视频
# 全程带时间戳进度：[10:29:56] 步骤1/5: 获取视频元数据...
```

**兜底策略**（仅当脚本整体失败时用于排查）——分三步前台执行：

#### 3a. 获取 WBI 签名密钥
```python
session = requests.Session()
resp = session.get('https://api.bilibili.com/x/web-interface/nav', impersonate='chrome131', timeout=10)
wbi = resp.json()['data']['wbi_img']
img_key = wbi['img_url'].split('/')[-1].split('.')[0]
sub_key = wbi['sub_url'].split('/')[-1].split('.')[0]
mixin = (img_key + sub_key)[:32]
```

#### 3b. 获取音频流（用旧版 playurl，非 WBI player/v2）
```python
import hashlib, time
wts = int(time.time())
to_sign = f'bvid={bvid}&cid={cid}&qn=0&fnver=0&fnval=4048&wts={wts}{mixin}'
w_rid = hashlib.md5(to_sign.encode()).hexdigest()

resp = session.get(
    f'https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=0&fnver=0&fnval=4048&wts={wts}&w_rid={w_rid}',
    headers={'Referer': f'https://www.bilibili.com/video/{bvid}/'},
    impersonate='chrome131', timeout=15
)
audio_url = resp.json()['data']['dash']['audio'][0]['baseUrl']
# 可选 65/75/94kbps 三种码率
```

**关键发现**：`playurl`（旧版）返回完整 DASH 音频流，`player/wbi/v2`（新版 WBI）返回空。选`playurl`，不选`player/wbi/v2`。

#### 3c. 下载音频
```python
resp2 = session.get(
    audio_url,
    headers={'Referer': 'https://www.bilibili.com/', 'Origin': 'https://www.bilibili.com'},
    impersonate='chrome131', timeout=120
)
with open('/tmp/audio.m4s', 'wb') as f:
    f.write(resp2.content)
# 20min 视频 ~9MB，1h ~28MB
```

#### 3d. 转 WAV
```bash
ffmpeg -y -i /tmp/audio.m4s -ar 16000 -ac 1 -f wav /tmp/audio.wav
# 20min → ~38MB WAV
```

#### 3e. ASR 转写（faster-whisper，非 openai-whisper）
```python
import os
os.environ['HF_ENDPOINT'] = 'https://hf-mirror.com'  # 国内必设

from faster_whisper import WhisperModel
model = WhisperModel('tiny', device='cpu', compute_type='int8')  # 默认 tiny，快
segments, info = model.transcribe('/tmp/audio.wav', language='zh', vad_filter=True)
# tiny 模型：77min 视频 ~200s。base 模型 3-4x 慢但更准
```

**默认用 `tiny`——用户偏好速度**。教程/正式内容可手动加 `--model base`。

**为什么 faster-whisper 而非 openai-whisper**：
- faster-whisper 不需 PyTorch（免去 532MB torch + 366MB CUDA toolkit）
- faster-whisper 使用 CTranslate2，CPU 推理更快
- 相同模型质量，更小安装体积

#### 3f. AI 总结
把转写文本（747 段/20min）喂给 LLM，生成结构化总结。

### 第四步：输出格式 + 清理

**总结质量标准**（用户明确要求）：
- ❌ **禁止只出大纲**——必须提取具体观点、案例、数据、金句
- ❌ **禁止保留口水话**——"对吧""是不是""那个那个" 等填充词必须过滤
- ✅ 按主题分段，即使原作是即兴直播
- ✅ 标注关键时间戳
- ✅ 格式：核心观点 → 分段详解 → 金句摘录 → 一句话总结

**必须清理**：
```bash
rm -f /tmp/bilibili-summary/{BVID}.m4s /tmp/bilibili-summary/{BVID}.wav
# 保留 .txt 供用户查阅
```

## 依赖

| 依赖 | 用途 | 大小 |
|------|------|------|
| `curl_cffi` | B 站反爬绕过 | ~2MB |
| `faster-whisper` | ASR 语音转文字 | ~20MB（不含模型） |
| `ffmpeg` | 音频格式转换 | 系统自带 |
| whisper base 模型 | 语音识别 | ~140MB（首次自动下载） |

**安装**：
```bash
pip install faster-whisper curl_cffi
# ffmpeg 通常已安装
```

## 踩坑表

| 问题 | 原因 | 解法 |
|------|------|------|
| HTTP 412 | B 站 WAF 检测非浏览器 | `curl_cffi` + `impersonate='chrome131'` |
| player/wbi/v2 返回空 DASH | 新版 API 不返回音频 | 用旧版 **`playurl`** API |
| player/v2 返回空字幕 | 公开 API 不返回 AI 字幕 | 走 ASR 路线 |
| `bilibili-api-python` 超时 | SPI endpoint 不通 | 直接用原生 `curl_cffi` |
| openai-whisper 安装超大 | 依赖 torch+CUDA（~900MB） | 用 `faster-whisper` |
| HF 模型下载超时 | HuggingFace 国内慢 | `HF_ENDPOINT=https://hf-mirror.com` |
| CPU 转写慢 | 正常，tiny ~1:20，base ~1:6 | 77min 视频 tiny ~200s。默认 tiny 即可 |
| B站 CDN 限速 | 部分视频 CDN 节点带宽 ~10-25KB/s，18MB 需要 700s+ | 新脚本自带双超时退避 + curl `-C -` 续传兜底（900s） |
| 调用脚本无输出 | stderr 在 Hermes 后台模式独立捕获，poll 只看 stdout | 调用时**必须加 `2>&1`** 把 stderr 合并到 stdout |

> 📖 详细诊断记录见 `references/debugging-background-hang.md`

## 快速模式（仅元数据+CC 字幕，无 ASR）

当用户说"简单总结一下"、"先看看有没有字幕"、或不需要完整 ASR 时，走轻量路径：

```python
import urllib.request, json

headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
           'Referer': 'https://www.bilibili.com/'}

# 1. 元数据
resp = urllib.request.Request(f'https://api.bilibili.com/x/web-interface/view?bvid={bvid}', headers=headers)
with urllib.request.urlopen(resp, timeout=10) as r:
    info = json.loads(r.read())['data']
# info['title'], info['owner']['name'], info['duration'], info['desc'], info['cid']

# 2. 字幕
resp2 = urllib.request.Request(f'https://api.bilibili.com/x/player/v2?bvid={bvid}&cid={cid}', headers=headers)
with urllib.request.urlopen(resp2, timeout=10) as r:
    subs = json.loads(r.read())['data'].get('subtitle', {}).get('subtitles', [])
```

**如果无字幕**（~99% 情况）：报告"该视频无 CC 字幕，仅有标题和简介可参考"。不主动提视频下载或 ASR，除非用户明确要求。

**此模式不含 curl_cffi 依赖**，纯标准库即可运行。不走 WBI 签名、不下载音频、不做 ASR。

> 此模式承接自原 `bilibili-video` 技能（已归档）。

## 执行策略（重要：让用户看到进度）

**Hermes Agent 必须用前台模式调用 ASR 脚本**，这样用户才能在 Web UI 看到实时进度：

```
terminal(command="python3 scripts/bilibili-ai-summary.py <BVID> 2>&1", timeout=600)
```

- ✅ **前台模式**：输出实时流式展示，用户看到 `[HH:MM:SS] 步骤N/5...`
- ❌ **禁止后台模式**：输出进 buffer，用户什么也看不到，只能问"好了吗"
- 20 分钟视频全程约 3-5 分钟（下载 ~30s + ASR ~200s），600s 超时足够

## 辅助脚本

- **`scripts/bilibili-ai-summary.py`** — 🔧 **主脚本（推荐）**：完整 ASR 一键链路。内置 stderr 实时进度（`[HH:MM:SS] 步骤N/5...`）、下载双超时退避（120s→600s）、curl `-C -` 断点续传兜底（900s）、ASR 每 30s 进度报告。调用时加 `2>&1` 确保后台也能看到输出
- `scripts/bilibili-summary.py` — 快速模式：元数据+CC 字幕（无 ASR）
- `scripts/bilibili-asr-summary.py` — 旧版 ASR（保留兼容）

### 关键改进（2025-06 修复）

| 问题 | 原因 | 修复 |
|------|------|------|
| 后台跑 8 分钟零输出，不知卡在哪 | Python stdout 全缓冲（后台无 TTY） | **所有进度输出到 stderr**（永远无缓冲），调用时加 `2>&1` |
| 下载卡死需手动 kill 排查 | curl_cffi 超时后无重试 | **双超时退避**（120s→600s）+ curl `-C -` 断点续传兜底（900s） |
| 每次都要问"好了吗" | 零进度输出 | 每步带时间戳日志（`[HH:MM:SS]`），ASR 每 30s 报告进度 |
| B站 CDN 限速（~25KB/s） | 部分视频 CDN 节点带宽极低 | curl 兜底用 `--max-time 900 --retry 3` + `-C -` 续传 |
