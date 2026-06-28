#!/usr/bin/env python3
"""
股票圆桌辩论 —— 自动抓取实时行情 + 注入辩论引擎 + 生成 HTML 报告

用法:
    python3 stock_debate.py 688270
    python3 stock_debate.py 000762  # 西藏矿业
"""

import sys, os, re, json, urllib.request, subprocess
from datetime import datetime

# ── 1. 获取实时行情 ──

def fetch_stock_quote(code: str) -> dict:
    """从腾讯行情 API 拉取实时数据"""
    # 判断交易所
    if code.startswith(('6', '9')):
        full_code = f"sh{code}"
    else:
        full_code = f"sz{code}"

    url = f"https://qt.gtimg.cn/q={full_code}"
    req = urllib.request.Request(url, headers={
        'User-Agent': 'Mozilla/5.0',
        'Referer': 'https://finance.qq.com/'
    })

    try:
        with urllib.request.urlopen(req, timeout=8) as resp:
            raw = resp.read()
            # 腾讯 API 返回 GBK 编码
            text = raw.decode('gbk', errors='replace')
    except Exception as e:
        print(f"❌ 行情获取失败: {e}")
        return {}

    # 解析: v_sh688270="1~ST臻镭~688270~70.00~..."
    m = re.search(r'="(.+)"', text)
    if not m:
        return {}

    fields = m.group(1).split('~')
    if len(fields) < 50:
        print(f"⚠️ 数据字段不足 (got {len(fields)})")
        return {}

    # 腾讯行情 API 字段索引 (腾讯 qt 接口标准格式)
    # 参考: https://cloud.tencent.com/developer/article/1200614
    name = fields[1]
    price = float(fields[3]) if fields[3] else 0
    prev_close = float(fields[4]) if fields[4] else 0
    change = float(fields[31]) if fields[31] else 0
    change_pct = float(fields[32]) if fields[32] else 0
    high = float(fields[33]) if fields[33] else 0
    low = float(fields[34]) if fields[34] else 0
    volume = int(fields[6]) if fields[6] else 0
    pe_ttm = float(fields[39]) if fields[39] else 0        # 动态市盈率
    market_cap = float(fields[45]) if fields[45] else 0     # 总市值(亿)
    high_52w = float(fields[47]) if fields[47] else 0       # 52周最高
    low_52w = float(fields[48]) if fields[48] else 0        # 52周最低

    # ST 检测
    is_st = 'ST' in name or '*ST' in name

    return {
        'code': code,
        'name': name,
        'price': price,
        'prev_close': prev_close,
        'change': change,
        'change_pct': change_pct,
        'high': high,
        'low': low,
        'volume': volume,
        'pe_ttm': pe_ttm,
        'high_52w': high_52w,
        'low_52w': low_52w,
        'market_cap': market_cap,
        'is_st': is_st,
        'date': datetime.now().strftime('%Y-%m-%d %H:%M'),
    }


# ── 2. 获取财务数据 ──

def fetch_financial_data(code: str) -> dict:
    """通过 AKShare 获取最新财务数据"""
    try:
        import akshare as ak
        df = ak.stock_financial_abstract_ths(symbol=code, indicator='按报告期')
        if df is None or df.empty:
            return {}

        # 取最近 3 期
        recent = df.tail(3)
        latest = recent.iloc[-1].to_dict()
        prev = recent.iloc[-2].to_dict() if len(recent) >= 2 else {}

        def _parse(v):
            """解析 akshare 的数值（可能是 "1.33亿" 字符串）"""
            if v is None:
                return 0
            if isinstance(v, (int, float)):
                return v
            s = str(v).replace(',', '').replace('%', '')
            if '亿' in s:
                return float(s.replace('亿', '')) * 1e8
            if '万' in s:
                return float(s.replace('万', '')) * 1e4
            try:
                return float(s)
            except ValueError:
                return 0

        return {
            'report_date': latest.get('报告期', ''),
            'revenue': _parse(latest.get('营业总收入')),
            'revenue_yoy': float(str(latest.get('营业总收入同比增长率', '0')).replace('%', '')),
            'net_profit': _parse(latest.get('净利润')),
            'net_profit_yoy': float(str(latest.get('净利润同比增长率', '0')).replace('%', '')),
            'gross_margin': float(str(latest.get('销售毛利率', '0')).replace('%', '')),
            'net_margin': float(str(latest.get('销售净利率', '0')).replace('%', '')),
            'eps': float(str(latest.get('基本每股收益', '0'))),
            'bps': float(str(latest.get('每股净资产', '0'))),
            'roe': float(str(latest.get('净资产收益率', '0')).replace('%', '')),
            'ocf_per_share': float(str(latest.get('每股经营现金流', '0'))),
            'debt_ratio': float(str(latest.get('资产负债率', '0')).replace('%', '')),
            'receivable_days': float(str(latest.get('应收账款周转天数', '0'))),
            'prev_revenue': _parse(prev.get('营业总收入')) if prev else 0,
            'prev_net_profit': _parse(prev.get('净利润')) if prev else 0,
        }
    except Exception as e:
        print(f"   ⚠️ 财务数据获取失败: {e}")
        return {}


# ── 3. 构造带实时数据的辩论问题 ──

def build_question(quote: dict, fin: dict = None) -> str:
    """把实时数据注入问题"""

    st_warning = ""
    if quote.get('is_st'):
        st_warning = "⚠️ 该股当前处于 ST（风险警示）状态。"

    fin_section = ""
    if fin and fin.get('revenue'):
        fin_section = f"""
【最新财务数据 · {fin.get('report_date', '')}】
- 营业总收入：{fin['revenue']/1e8:.2f}亿（同比{fin['revenue_yoy']:+.1f}%）
- 净利润：{fin['net_profit']/1e8:.2f}亿（同比{fin['net_profit_yoy']:+.1f}%）
- 毛利率：{fin['gross_margin']:.1f}% | 净利率：{fin['net_margin']:.1f}%
- EPS：{fin['eps']:.4f}元 | 每股净资产：{fin['bps']:.2f}元
- ROE：{fin['roe']:.1f}% | 资产负债率：{fin['debt_ratio']:.1f}%
- 经营现金流/股：{fin['ocf_per_share']:.2f}元
- 应收账款周转天数：{fin['receivable_days']:.0f}天"""

    q = f"""{quote['name']}({quote['code']})目前是否值得持有？

【实时行情 · {quote.get('date', '')}】
- 最新价：{quote['price']}元
- 涨跌幅：{quote['change_pct']:+.2f}%
- 今日振幅：{quote['high']}-{quote['low']}
- PE(TTM)：{quote['pe_ttm']:.0f}倍
- 总市值：约{quote['market_cap']:.0f}亿
- 52周高低：{quote['high_52w']}-{quote['low_52w']}
{st_warning}{fin_section}

【背景】
它是军工电子/半导体企业，科创板上市，主营射频微波芯片和SIP模组。

请各角色基于以上数据进行分析辩论，重点关注：估值是否合理？军工电子行业景气度如何？ST状态意味着什么风险？财务数据揭示了哪些问题？"""

    return q


# ── 3. 构造 HTML 快照 ──

def build_snapshot(quote: dict, fin: dict = None) -> dict:
    def fmt(v, unit=''):
        if isinstance(v, float):
            return f"{v:.2f}{unit}" if v else '-'
        return str(v) if v else '-'

    pct_class = 'cc-snap-up' if quote.get('change_pct', 0) >= 0 else 'cc-snap-down'

    snap = {
        f'{quote["name"]}({quote["code"]})': {
            'value': fmt(quote.get('price')),
            'sub': f'{quote.get("change_pct", 0):+.2f}%',
            'sub_class': pct_class,
        },
        'PE(TTM)': {
            'value': f'{quote.get("pe_ttm", 0):.0f}x',
            'sub': '',
            'sub_class': '',
        },
        '总市值': {
            'value': f'{quote.get("market_cap", 0):.0f}亿',
            'sub': '',
            'sub_class': '',
        },
        '52周区间': {
            'value': f'{quote.get("high_52w", 0):.0f}',
            'sub': f'最低{quote.get("low_52w", 0):.0f}',
            'sub_class': '',
        },
    }

    if quote.get('is_st'):
        snap['⚠️ 风险警示'] = {
            'value': 'ST',
            'sub': '特别处理',
            'sub_class': 'cc-snap-up',
        }

    if fin and fin.get('revenue'):
        snap.update({
            '营收(最新期)': {
                'value': f'{fin["revenue"]/1e8:.2f}亿',
                'sub': f'同比{fin["revenue_yoy"]:+.0f}%',
                'sub_class': 'cc-snap-up' if fin['revenue_yoy'] > 0 else 'cc-snap-down',
            },
            '净利润': {
                'value': f'{fin["net_profit"]/1e8:.2f}亿',
                'sub': f'同比{fin["net_profit_yoy"]:+.0f}%',
                'sub_class': 'cc-snap-up' if fin['net_profit_yoy'] > 0 else 'cc-snap-down',
            },
            '毛利率/ROE': {
                'value': f'{fin["gross_margin"]:.0f}%',
                'sub': f'ROE {fin["roe"]:.1f}%',
                'sub_class': '',
            },
            '经营现金流/股': {
                'value': f'{fin["ocf_per_share"]:.2f}元',
                'sub': '负值=现金流出' if fin['ocf_per_share'] < 0 else '',
                'sub_class': 'cc-snap-down' if fin['ocf_per_share'] < 0 else '',
            },
        })

    return snap


# ── 4. 主流程 ──

def main():
    if len(sys.argv) < 2:
        print("用法: python3 stock_debate.py <股票代码>")
        print("示例: python3 stock_debate.py 688270")
        sys.exit(1)

    code = sys.argv[1]

    # 获取 API key
    with open(os.path.expanduser('~/.hermes/config.yaml')) as f:
        raw = f.read()
    m = re.search(r'api_key:\s*["\']?([^"\'\n\s]+)["\']?', raw)
    api_key = m.group(1) if m else ""
    if not api_key:
        print("❌ 未找到 taotoken API key")
        sys.exit(1)

    # 拉行情
    print(f"📡 获取 {code} 实时行情...")
    quote = fetch_stock_quote(code)
    if not quote or not quote.get('price'):
        print("❌ 行情数据获取失败，退出")
        sys.exit(1)

    print(f"   {quote['name']}: {quote['price']}元 | PE={quote['pe_ttm']:.0f}x | 市值≈{quote['market_cap']:.0f}亿")
    if quote.get('is_st'):
        print("   ⚠️ ST 风险警示股！")

    # 拉财报
    print(f"📊 获取 {code} 财务数据...")
    fin = fetch_financial_data(code)
    if fin:
        print(f"   {fin.get('report_date','')}: 营收{fin['revenue']/1e8:.2f}亿(YoY{fin['revenue_yoy']:+.0f}%) 净利{fin['net_profit']/1e8:.2f}亿 毛利率{fin['gross_margin']:.0f}% ROE{fin['roe']:.1f}%")
    else:
        print("   ⚠️ 未获取到财务数据，将仅使用行情数据")

    # 构造问题
    question = build_question(quote, fin)
    print(f"\n🎭 启动圆桌辩论...\n")

    # 跑辩论
    script_dir = os.path.dirname(os.path.abspath(__file__))
    os.chdir(script_dir)

    result = subprocess.run(
        [sys.executable, 'demo.py', question],
        capture_output=True, text=True, timeout=300,
        env={**os.environ, 'TAOTOKEN_API_KEY': api_key, 'OPENAI_API_KEY': api_key},
    )

    print(result.stdout)
    if result.stderr:
        print("⚠️ STDERR:", result.stderr[:1000])

    if result.returncode != 0:
        print(f"❌ 辩论引擎退出码: {result.returncode}")
        sys.exit(1)

    # 生成 HTML 报告
    print("\n📄 生成 HTML 报告...")
    from html_report import render_html

    json_path = 'last_debate_result.json'
    with open(json_path, encoding='utf-8') as f:
        debate_result = json.load(f)

    # 清理角色名中的 emoji 前缀
    name = quote['name'].replace('*', '').replace('ST', '').strip()
    snapshot = build_snapshot(quote, fin)
    date_str = quote.get('date', datetime.now().strftime('%Y-%m-%d'))
    display_title = f"{quote['name']}({code})是否值得持有？"

    html = render_html(debate_result, stock_data={
        'date': date_str,
        'title_prefix': f'{name} · ',
        'display_title': display_title,
        'snapshot': snapshot,
    })

    out_path = f'report_{code}.html'
    with open(out_path, 'w', encoding='utf-8') as f:
        f.write(html)

    print(f"\n✅ 报告已生成: file:///{script_dir.replace(chr(92), '/')}/{out_path}")
    print(f"   文件大小: {len(html)} 字符")


if __name__ == '__main__':
    main()
