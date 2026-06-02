#!/usr/bin/env python3
"""
parse_memory_leak.py — 内存泄漏分析工具

分析 collect_memory_leak.sh 采集的 CSV 数据，判定是否存在内存泄漏。

用法:
    python3 parse_memory_leak.py <CSV文件>
    python3 parse_memory_leak.py /var/log/memory-leak/memory-leak-20250101-120000.csv
"""

import csv
import sys
import json
from pathlib import Path
from collections import defaultdict


def load_csv(filepath):
    """加载 CSV 数据"""
    data = []
    with open(filepath) as f:
        reader = csv.DictReader(f)
        for row in reader:
            row['rss_kb'] = int(row.get('rss_kb', 0))
            row['vsz_kb'] = int(row.get('vsz_kb', 0))
            row['fd_count'] = int(row.get('fd_count', 0))
            row['threads'] = int(row.get('threads', 0))
            data.append(row)
    return data


def analyze_process(pid, samples):
    """分析单个进程的内存趋势"""
    if len(samples) < 3:
        return {"pid": pid, "status": "样本不足", "samples": len(samples)}

    rss_values = [s['rss_kb'] for s in samples]
    initial_rss = rss_values[0]
    final_rss = rss_values[-1]
    max_rss = max(rss_values)
    min_rss = min(rss_values)
    growth = final_rss - initial_rss

    # 简单线性回归判断趋势
    n = len(rss_values)
    x_avg = (n - 1) / 2
    y_avg = sum(rss_values) / n
    numerator = sum((i - x_avg) * (v - y_avg) for i, v in enumerate(rss_values))
    denominator = sum((i - x_avg) ** 2 for i in range(n))

    slope = numerator / denominator if denominator != 0 else 0

    # FD 趋势
    fd_values = [s['fd_count'] for s in samples]
    fd_growth = fd_values[-1] - fd_values[0] if len(fd_values) > 1 else 0

    # 判定泄漏
    threshold_kb = 10240  # 10MB
    verdict = "正常"

    if slope > 10 and growth > threshold_kb:
        verdict = "疑似泄漏"
    elif growth > threshold_kb:
        verdict = "关注（增长较大）"
    elif slope > 5:
        verdict = "轻微增长"

    if fd_growth > 100:
        verdict += " + FD 异常增长（疑似 FD 泄漏）"
    elif fd_growth > 20:
        verdict += " + FD 有增长趋势"

    name = samples[0].get('name', '?')

    return {
        "pid": pid,
        "name": name,
        "samples": n,
        "initial_rss_kb": initial_rss,
        "final_rss_kb": final_rss,
        "max_rss_kb": max_rss,
        "growth_kb": growth,
        "growth_mb": round(growth / 1024, 1),
        "slope": round(slope, 1),
        "fd_growth": fd_growth,
        "verdict": verdict,
    }


def generate_report(results, output_format='text'):
    """生成诊断报告"""
    if output_format == 'json':
        return json.dumps(results, indent=2, ensure_ascii=False)

    lines = []
    lines.append("=" * 60)
    lines.append("内存泄漏分析报告")
    lines.append("=" * 60)
    lines.append("")

    leaks = [r for r in results if '泄漏' in r['verdict']]
    warnings = [r for r in results if r not in leaks and '关注' in r['verdict']]
    normal = [r for r in results if r not in leaks and r not in warnings]

    if leaks:
        lines.append(f"🔴 疑似泄漏 ({len(leaks)} 个):")
        lines.append("-" * 40)
        for r in leaks:
            lines.append(f"  PID {r['pid']} ({r['name']})")
            lines.append(f"    增长: {r['growth_mb']}MB ({r['initial_rss_kb']/1024:.0f}MB → {r['final_rss_kb']/1024:.0f}MB)")
            lines.append(f"    斜率: {r['slope']} KB/采样")
            lines.append(f"    判定: {r['verdict']}")
        lines.append("")

    if warnings:
        lines.append(f"🟡 需要关注 ({len(warnings)} 个):")
        lines.append("-" * 40)
        for r in warnings:
            lines.append(f"  PID {r['pid']} ({r['name']}): 增长 {r['growth_mb']}MB")
        lines.append("")

    if normal:
        lines.append(f"🟢 正常 ({len(normal)} 个):")
        lines.append("-" * 40)
        for r in normal:
            lines.append(f"  PID {r['pid']} ({r['name']}): 增长 {r['growth_mb']}MB")
        lines.append("")

    lines.append("=" * 60)
    lines.append("建议:")
    lines.append("  1. 对疑似泄漏的进程，用 jmap / pmap 分析堆内存")
    lines.append("  2. 检查文件描述符泄漏: ls -la /proc/<PID>/fd")
    lines.append("  3. 检查 /proc/<PID>/smaps 查看内存段")
    lines.append("  4. 考虑配置 -Xmx / ulimit 限制")
    lines.append("=" * 60)

    return '\n'.join(lines)


def main():
    if len(sys.argv) < 2:
        print("用法: python3 parse_memory_leak.py <CSV文件>")
        sys.exit(1)

    filepath = Path(sys.argv[1])
    if not filepath.exists():
        print(f"错误: 文件不存在 — {filepath}")
        sys.exit(1)

    data = load_csv(filepath)

    # 按 PID 分组
    by_pid = defaultdict(list)
    for row in data:
        by_pid[row['pid']].append(row)

    # 分析每个进程
    results = []
    for pid, samples in sorted(by_pid.items()):
        # 按时间排序
        samples.sort(key=lambda x: x['timestamp'])
        result = analyze_process(pid, samples)
        results.append(result)

    # 按严重程度排序
    results.sort(key=lambda r: r['growth_kb'], reverse=True)

    report = generate_report(results)
    print(report)


if __name__ == '__main__':
    main()
