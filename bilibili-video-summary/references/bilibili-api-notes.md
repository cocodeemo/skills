# Bilibili API 访问技术要点

## curl_cffi 绕过 412

B 站对非浏览器 HTTP 请求返回 HTTP 412 Precondition Failed。解决方案：

```python
from curl_cffi import requests

# 必须：伪装 Chrome 131
resp = requests.get(url, impersonate='chrome131', timeout=15)
```

不要用标准 `urllib` 或 `requests`——100% 触发 412。

`pip install curl_cffi` 即可，无需额外依赖。

## 为什么不需要 playwright/selenium

`curl_cffi` 在 TLS 层面模拟浏览器指纹，不需要启动浏览器进程。比 playwright 轻 100 倍，适合脚本化调用。

## WBI 签名（仅高级 API）

部分 B 站 API 需要 WBI 签名（`x/player/wbi/v2` 等）。签名密钥从页面 HTML 提取：

```python
import re, hashlib, time

# 提取密钥（从页面中的 JS 配置）
m = re.search(r'"wbi_img":\s*\{[^}]*"img_key":"(\w+)","sub_key":"(\w+)"', html)
mixin = (img_key + sub_key)[:32]

wts = int(time.time())
w_rid = hashlib.md5(f'params&wts={wts}{mixin}'.encode()).hexdigest()
url = f'https://api.bilibili.com/x/...?params&wts={wts}&w_rid={w_rid}'
```

注意：WBI 密钥会定期轮换，不要缓存。

## AI 字幕的 API 盲区

B 站播放器展示的 AI 字幕（CC 按钮→AI 字幕）无法通过公开 API 获取。`x/player/v2` 只返回手动上传的字幕。AI 字幕需要浏览器 JS 执行后才能拿到。

**已知可行方案**：
1. 装 `openai-whisper` → 下载音频流 → ASR 转文字（约 1.5GB 模型）
2. 用户在浏览器里复制字幕文本 → 粘贴给 AI 总结
3. 如果视频描述足够详细，直接基于描述+标题做总结

## yt-dlp 不可靠

B 站反爬升级频繁，yt-dlp（即使最新版）经常 412。不推荐作为主方案。

## bilibili-api-python 的坑

该库依赖 `curl_cffi` 的内部 SPI endpoint 获取 buvid3 cookie，在 WSL/某些网络环境下超时。绕过方法——直接用原生 `curl_cffi` 调用 API，不依赖库的封装。
