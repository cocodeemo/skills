#!/usr/bin/env python3
"""
parse_oom_events.py — OOM Killer 事件解析器

解析 dmesg/journalctl 中的 OOM 日志，输出结构化诊断报告。

用法:
    python3 parse_oom_events.py <日志文件或目录>
    python3 parse_oom_events.py /var/log/oom-collector/oom-20250101-120000/
    python3 parse_oom_events.py dmesg-oom.log
"""

import re
import sys
import json
from pathlib import Path
from datetime import datetime


def parse_oom_log(text):
    """从日志文本中提取 OOM 事件"""
    events = []

    # OOM Killer 事件模式
    patterns = [
        # 标准 OOM kill 日志
        r'(?P<timestamp>\w+\s+\w+\s+\d+\s+\d+:\d+:\d+).*?(?:out of memory|oom-killer|Killed process|invoked oom-killer)',
        # dmesg -T 格式
        r'\[(?P<ts2>[^\]]+)\]\s+.*?(?:Out of memory|oom-killer|Killed process)',
        # journalctl 格式
        r'(?P<ts3>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}).*?(?:oom|out of memory|killed)',
    ]

    lines = text.split('\n')
    current_event = {}
    in_oom_block = False

    for line in lines:
        line_lower = line.lower()

        # 检测 OOM 事件开始
        if any(kw in line_lower for kw in ['oom-killer', 'invoked oom-killer', 'out of memory']):
            if current_event:
                events.append(current_event)
            current_event = {
                'raw_line': line.strip(),
                'timestamp': extract_timestamp(line),
                'type': 'oom_killer'
            }
            in_oom_block = True
            continue

        # 检测 Killed process 行
        kill_match = re.search(
            r'Killed process\s+(?P<pid>\d+)\s+\((?P<name>[^)]+)\)',
            line
        )
        if kill_match and in_oom_block:
            current_event['killed_pid'] = int(kill_match.group('pid'))
            current_event['killed_process'] = kill_match.group('name')

            # 提取内存信息
            mem_match = re.search(
                r'total-vm:(\d+)kB,\s*anon-rss:(\d+)kB,\s*file-rss:(\d+)kB',
                line
            )
            if mem_match:
                current_event['total_vm_kb'] = int(mem_match.group(1))
                current_event['anon_rss_kb'] = int(mem_match.group(2))
                current_event['file_rss_kb'] = int(mem_match.group(3))
            continue

        # 提取内存信息摘要行
        if 'oom' in line_lower and 'memory' in line_lower:
            meminfo_match = re.search(
                r'\[.*?\]\s+(?P<name>\w+?):\s+.*?active_anon:\s*(?P<active_anon>\d+)',
                line
            )
            if meminfo_match:
                current_event['oom_meminfo'] = line.strip()

        # 提取 cgroup 信息
        if 'memory cgroup' in line_lower or 'cgroup' in line_lower:
            cg_match = re.search(r'cgroup\s+(?:out of memory|OOM)', line, re.IGNORECASE)
            if cg_match:
                current_event['type'] = 'cgroup_oom'
                current_event['cgroup_info'] = line.strip()

    if current_event:
        events.append(current_event)

    return events


def extract_timestamp(line):
    """从日志行提取时间戳"""
    # dmesg -T 格式: [Thu Oct  9 15:29:56 2025]
    ts_match = re.search(r'\[(\w+\s+\w+\s+\d+\s+\d+:\d+:\d+\s+\d{4})\]', line)
    if ts_match:
        try:
            dt = datetime.strptime(ts_match.group(1), '%a %b %d %H:%M:%S %Y')
            return dt.isoformat()
        except ValueError:
            pass

    # journalctl 格式: 2025-10-09 15:29:56
    ts_match = re.search(r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})', line)
    if ts_match:
        return ts_match.group(1)

    return 'unknown'


def diagnose_root_cause(event):
    """分析 OOM 根因"""
    causes = []

    # 检查 cgroup OOM
    if event.get('type') == 'cgroup_oom':
        causes.append('Cgroup 内存限制触发，容器/进程组达到上限')

    # 检查 Swap
    if event.get('total_vm_kb', 0) > 0:
        total_gb = event['total_vm_kb'] / 1024 / 1024
        anon_gb = event.get('anon_rss_kb', 0) / 1024 / 1024
        if total_gb > 1:
            causes.append(f'进程 {event.get("killed_process", "?")} 虚拟内存: {total_gb:.1f}GB')

    if not causes:
        causes.append('系统物理内存耗尽')

    return causes


def generate_report(events, output_format='text'):
    """生成诊断报告"""
    if not events:
        return "未发现 OOM 事件。"

    if output_format == 'json':
        return json.dumps(events, indent=2, ensure_ascii=False)

    report = []
    report.append("=" * 60)
    report.append(f"OOM 事件诊断报告 — 发现 {len(events)} 个事件")
    report.append("=" * 60)
    report.append("")

    for i, event in enumerate(events, 1):
        report.append(f"--- 事件 #{i} ---")
        report.append(f"  时间: {event.get('timestamp', 'unknown')}")
        report.append(f"  类型: {event.get('type', 'unknown')}")

        if event.get('killed_process'):
            report.append(f"  被杀进程: {event['killed_process']} (PID: {event.get('killed_pid', '?')})")

        if event.get('anon_rss_kb'):
            report.append(f"  匿名 RSS: {event['anon_rss_kb'] / 1024:.1f} MB")
            report.append(f"  文件 RSS: {event['file_rss_kb'] / 1024:.1f} MB")

        report.append(f"  原始日志: {event.get('raw_line', 'N/A')[:120]}")

        # 根因分析
        causes = diagnose_root_cause(event)
        report.append(f"  根因分析:")
        for cause in causes:
            report.append(f"    → {cause}")

        report.append("")

    report.append("=" * 60)
    report.append("建议:")
    report.append("  1. 检查被杀进程的内存配置（Xmx、buffer_pool 等）")
    report.append("  2. 如果 cgroup OOM，增加容器/进程组限制")
    report.append("  3. 考虑增加系统物理内存或配置 Swap")
    report.append("  4. 检查是否有内存泄漏（参考内存泄漏采集脚本）")
    report.append("=" * 60)

    return '\n'.join(report)


def main():
    if len(sys.argv) < 2:
        print("用法: python3 parse_oom_events.py <日志文件或目录>")
        print("  python3 parse_oom_events.py dmesg-oom.log")
        print("  python3 parse_oom_events.py /var/log/oom-collector/")
        sys.exit(1)

    path = Path(sys.argv[1])
    text = ""

    if path.is_file():
        text = path.read_text(errors='ignore')
    elif path.is_dir():
        for f in sorted(path.glob('*')):
            if f.is_file():
                text += f.read_text(errors='ignore') + '\n'
    else:
        print(f"错误: 路径不存在 — {path}")
        sys.exit(1)

    events = parse_oom_log(text)
    report = generate_report(events)
    print(report)


if __name__ == '__main__':
    main()
