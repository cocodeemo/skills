#!/usr/bin/env python3
"""Bilibili 视频元数据+字幕提取 — 轻量，不下载视频"""
import sys, re, json

try:
    from curl_cffi import requests
except ImportError:
    print("需要 curl_cffi: pip install curl_cffi")
    sys.exit(1)

def get_video_info(url_or_bvid: str):
    m = re.search(r'(BV[a-zA-Z0-9]{10})', url_or_bvid)
    if not m:
        print("错误: 无法提取 BVID")
        return None
    bvid = m.group(1)

    # 1. 元数据
    resp = requests.get(
        f'https://api.bilibili.com/x/web-interface/view?bvid={bvid}',
        headers={'Referer': 'https://www.bilibili.com/'},
        impersonate='chrome131', timeout=15
    )
    info = resp.json()['data']

    print(f"标题: {info['title']}")
    print(f"UP主: {info['owner']['name']} | 时长: {info['duration']//60}:{info['duration']%60:02d}")
    print(f"播放: {info['stat']['view']} | 弹幕: {info['stat']['danmaku']}")
    print(f"简介: {info['desc'][:300]}")
    print()

    # 2. 字幕
    cid = info['cid']
    resp2 = requests.get(
        f'https://api.bilibili.com/x/player/v2?bvid={bvid}&cid={cid}',
        headers={'Referer': f'https://www.bilibili.com/video/{bvid}/'},
        impersonate='chrome131', timeout=15
    )
    subs = resp2.json()['data'].get('subtitle', {}).get('subtitles', [])

    if not subs:
        print("⚠️ 该视频无可用字幕（API 不返回 AI 字幕）")
        print("   选项：装 openai-whisper 做 ASR，或手动复制字幕文本")
        return {'bvid': bvid, 'title': info['title'], 'text': None}

    # 首选中文 AI 字幕，次选手动字幕
    sub = None
    for s in subs:
        ai = 'AI' if s.get('ai_type') == 1 else '手动'
        print(f'  字幕: {s.get("lan_doc")} ({ai})')
        if 'zh' in s.get('lan', '').lower() and not sub:
            sub = s
    if not sub:
        sub = subs[0]

    # 下载字幕内容
    sub_url = sub['subtitle_url']
    if sub_url.startswith('//'):
        sub_url = 'https:' + sub_url
    resp3 = requests.get(sub_url, headers={'Referer': 'https://www.bilibili.com/'}, timeout=15)
    sub_data = resp3.json()
    body = sub_data.get('body', [])

    full_text = '\n'.join([f"[{item['from']:.1f}s] {item['content']}" for item in body])
    print(f"\n=== 字幕全文 ({len(body)} 条, {len(full_text)} 字符) ===")
    print(full_text)

    return {'bvid': bvid, 'title': info['title'], 'text': full_text}

if __name__ == '__main__':
    url = sys.argv[1] if len(sys.argv) > 1 else input('输入B站链接: ')
    get_video_info(url.strip())
