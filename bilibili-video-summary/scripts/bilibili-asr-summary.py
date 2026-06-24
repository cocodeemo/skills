#!/usr/bin/env python3
"""
B站视频 ASR 总结 — 完整链路：获取音频 → faster-whisper 转写 → 输出文本

用法: python3 bilibili-asr-summary.py <BVID或B站链接>

依赖: pip install faster-whisper curl_cffi
      ffmpeg 系统自带
      国内需设 HF_ENDPOINT=https://hf-mirror.com 加速模型下载

验证环境: WSL2, Ubuntu 22.04, Python 3.10
验证视频: BV1ayLD6uERL (Harness 实践, 20min38s)
  - M4S 音频: 9.67 MB
  - WAV(16kHz): 37.75 MB
  - 转写耗时: 171s (CPU, base 模型)
  - 转写结果: 747 段
"""
import os, sys, re, hashlib, time, json, tempfile, subprocess

# 国内用户必设 HF 镜像
if 'HF_ENDPOINT' not in os.environ:
    os.environ['HF_ENDPOINT'] = 'https://hf-mirror.com'

from curl_cffi import requests

def extract_bvid(url_or_bvid: str) -> str:
    m = re.search(r'(BV[a-zA-Z0-9]{10})', url_or_bvid)
    if not m:
        raise ValueError(f"无法提取 BVID: {url_or_bvid}")
    return m.group(1)

def get_audio_url(bvid: str) -> tuple:
    """返回 (audio_url, title, duration_sec, cid)"""
    session = requests.Session()

    # 1. 获取视频信息 + cid
    resp = session.get(
        f'https://api.bilibili.com/x/web-interface/view?bvid={bvid}',
        headers={'Referer': 'https://www.bilibili.com/'},
        impersonate='chrome131', timeout=15
    )
    data = resp.json()['data']
    title = data['title']
    duration = data['duration']
    cid = data['cid']
    print(f"标题: {title}")
    print(f"UP主: {data['owner']['name']} | 时长: {duration//60}:{duration%60:02d}")

    # 2. 获取 WBI 签名密钥
    resp = session.get('https://api.bilibili.com/x/web-interface/nav', impersonate='chrome131', timeout=10)
    wbi = resp.json()['data']['wbi_img']
    img_key = wbi['img_url'].split('/')[-1].split('.')[0]
    sub_key = wbi['sub_url'].split('/')[-1].split('.')[0]
    mixin = (img_key + sub_key)[:32]

    # 3. 获取音频流 (playurl API, 非 player/wbi/v2)
    wts = int(time.time())
    to_sign = f'bvid={bvid}&cid={cid}&qn=0&fnver=0&fnval=4048&wts={wts}{mixin}'
    w_rid = hashlib.md5(to_sign.encode()).hexdigest()

    resp = session.get(
        f'https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=0&fnver=0&fnval=4048&wts={wts}&w_rid={w_rid}',
        headers={'Referer': f'https://www.bilibili.com/video/{bvid}/'},
        impersonate='chrome131', timeout=15
    )
    dash = resp.json()['data'].get('dash', {})
    audio_list = dash.get('audio', [])

    if not audio_list:
        # fallback: 尝试不带 WBI 签名
        resp2 = requests.get(
            f'https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=0&fnver=0&fnval=16',
            headers={'Referer': f'https://www.bilibili.com/video/{bvid}/'},
            impersonate='chrome131', timeout=15
        )
        audio_list = resp2.json()['data'].get('dash', {}).get('audio', [])

    if not audio_list:
        raise RuntimeError("无法获取音频流")

    # 选最高码率
    best = sorted(audio_list, key=lambda a: a.get('bandwidth', 0), reverse=True)[0]
    audio_url = best['baseUrl']
    print(f"音频码率: {best.get('bandwidth', 0)//1000}kbps")

    return session, audio_url, title, duration, cid

def download_audio(session, audio_url: str) -> str:
    """下载音频并转 WAV，返回 WAV 文件路径"""
    m4s_path = '/tmp/bilibili_audio.m4s'
    wav_path = '/tmp/bilibili_audio.wav'

    print("下载音频...")
    resp = session.get(
        audio_url,
        headers={'Referer': 'https://www.bilibili.com/', 'Origin': 'https://www.bilibili.com'},
        impersonate='chrome131', timeout=180
    )
    with open(m4s_path, 'wb') as f:
        f.write(resp.content)
    size_mb = os.path.getsize(m4s_path) / 1024 / 1024
    print(f"已下载: {size_mb:.1f} MB")

    print("转 WAV...")
    subprocess.run([
        'ffmpeg', '-y', '-i', m4s_path,
        '-ar', '16000', '-ac', '1', '-f', 'wav', wav_path
    ], capture_output=True, check=True)
    wav_mb = os.path.getsize(wav_path) / 1024 / 1024
    print(f"WAV: {wav_mb:.1f} MB")

    os.remove(m4s_path)
    return wav_path

def transcribe_audio(wav_path: str) -> str:
    """faster-whisper 转写，返回完整文本"""
    from faster_whisper import WhisperModel

    print("加载 whisper base 模型...")
    model = WhisperModel('base', device='cpu', compute_type='int8')

    print("转写中（20min 约需 3min）...")
    start = time.time()
    segments, info = model.transcribe(wav_path, language='zh', vad_filter=True)
    print(f"语言: {info.language} (置信度: {info.language_probability:.2f})")

    lines = []
    for seg in segments:
        lines.append(f"[{seg.start:.1f}s] {seg.text}")
        if len(lines) % 100 == 0:
            print(f"  {seg.start:.0f}s...")

    full_text = '\n'.join(lines)
    elapsed = time.time() - start
    print(f"转写完成: {len(lines)} 段, 耗时 {elapsed:.0f}s")

    os.remove(wav_path)
    return full_text

def main():
    if len(sys.argv) < 2:
        print("用法: python3 bilibili-asr-summary.py <BVID或B站链接>")
        sys.exit(1)

    bvid = extract_bvid(sys.argv[1])
    print(f"BVID: {bvid}\n")

    # 获取音频
    session, audio_url, title, duration, cid = get_audio_url(bvid)

    # 下载并转写
    wav_path = download_audio(session, audio_url)
    transcript = transcribe_audio(wav_path)

    # 输出
    out_path = f'/tmp/bilibili_{bvid}.txt'
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(f"# {title}\n")
        f.write(f"# BVID: {bvid} | 时长: {duration//60}:{duration%60:02d}\n\n")
        f.write(transcript)

    print(f"\n转写文本已保存到: {out_path}")
    print(f"字符数: {len(transcript)}")

    # 打印预览
    print("\n=== 预览 (前 300 字) ===")
    print(transcript[:300])

if __name__ == '__main__':
    main()
