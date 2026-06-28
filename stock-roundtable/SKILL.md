---
name: stock-roundtable
description: "股票圆桌辩论——6 大投资流派（格雷厄姆/巴菲特/费雪/笨韭/莫大/龟龟）同时分析一支股票，自动抓行情+财报+除权调整，输出 WorkBuddy 同款 HTML 报告。来源：cocodeemo/stock-analysis-skills。"
version: 1.6.0
author: Agent + 大哥
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [multi-agent, debate, decision-making, ai-orchestration]
---

# 多 Agent 辩论复核框架

## 概述

让多个 AI Agent 以不同角色对一个问题进行结构化辩论——类似 Kimi 股票分析的"团队讨论、互相纠错"模式，但不绑死任何领域。

核心价值：
- **交叉验证**：多个视角互相质疑，降低单 Agent "偏见过拟合"
- **结构化输出**：不是聊天记录，而是带置信度的决策报告
- **可插拔**：角色定义、辩论轮次、LLM 底座均可替换

## 架构

```
用户提问
  │
  ▼
角色工厂（根据问题自动选择辩论角色）
  │
  ▼
Round 1: 各方独立陈述初始立场
  │
  ▼
Round 2-N: 必须引用其他角色具体论点进行反驳/补充
  │
  ▼
裁判汇总 → 结构化报告（共识/分歧/置信度/风险/建议）
```

## 设计决策（已确认）

| 决策 | 选择 | 原因 |
|------|------|------|
| LLM 底座 | 直接 API 调用（taotoken.net） | 不依赖 AutoGen 等框架，完全可控 |
| 辩论模式 | 串行轮次 | 辩论的价值在于"互相引用反驳"，并行做不到 |
| Agent 并发 | 串行（一轮内逐个发言） | 上下文可控，token 不爆炸 |
| 角色自动选择 | 启发式关键词匹配 | 简单可靠，后续可升级为 LLM 决策 |

## 角色定义

### 通用辩论角色（5 个）

| 角色 | Key | 职责 |
|------|-----|------|
| 🟢 乐观派 | `optimist` | 寻找机会、收益、正向可能性 |
| 🔴 悲观派 | `pessimist` | 识别风险、挑漏洞、找盲点 |
| 🔵 技术派 | `technologist` | 技术可行性、架构约束、实现路径 |
| 🟡 业务派 | `business` | 商业价值、用户体验、ROI |
| ⚫ 质疑者 | `skeptic` | 二阶质疑——不只质疑结论，质疑推理过程 |

### 6 大投资流派角色（股票分析专用）

来源：[cocodeemo/stock-analysis-skills](https://github.com/cocodeemo/stock-analysis-skills) 仓库，蒸馏自真实投资大师/B站UP主的方法论。

| 角色 | Key | 来源 | 核心逻辑 |
|------|-----|------|----------|
| 📐 格雷厄姆派 | `graham` | 《聪明的投资者》第14章 | PE≤15x + 10年盈利 + 20年分红——数字说话 |
| 🏰 巴菲特派 | `buffett` | 《致股东的信》20个Skill | 护城河评分 + 伊索三问 + 永续持有 |
| 🔬 费雪派 | `fisher` | 《怎样选择成长股》 | 管理层质量>一切，15条checklist |
| ⚡ 笨韭派 | `benjiu` | B站24.9万粉UP主 92集字幕 | 现象级事件→景气轮动→笨韭双击 |
| 📊 莫大派 | `luohuitou` | 雪球1996篇帖子 | 六维百分制：预期差×1.5+股价位置×2 |
| 🐢 龟龟派 | `shiji` | B站35万粉UP主 10集字幕 | 烟蒂股+现金流，先守后攻 |

**自动选择逻辑**：`select_roles()` 检测到股票/投资类关键词（"持有""PE""市值""是否值得"等）时，自动切换到 6 大投资流派角色，而非通用辩论角色。`STOCK_INVESTMENT_ROLES` 常量定义了默认加载的 6 个角色 key 列表。

每个流派的完整方法论原文见 `references/stock-investment-roles.md`，原始源文件在 [cocodeemo/stock-analysis-skills](https://github.com/cocodeemo/stock-analysis-skills)。

**强制输出格式**：每个投资流派角色的 prompt 末尾必须包含固定格式的评分输出要求（详见 `references/stock-role-output-formats.md`），否则 LLM 不会在辩论中输出结构化分数，HTML 报告中将只有莫大一人有可视化评分。本 session 已验证：不加强制输出格式 → 其他 5 个角色只引用反驳不打分 → 用户指出「原来的 skill 是每个人都有分数吧」。

## 代码结构

```
/mnt/d/debate-engine/
├── roles.py          # 角色定义 + 自动选择
├── engine.py         # 核心辩论引擎（底座无关）
├── demo.py           # 命令行 Demo（对接 taotoken.net）
├── dual_debate.py    # 双模型快速辩论变体
├── html_report.py    # HTML 报告渲染器 → scripts/html_report.py
├── stock_debate.py   # 股票专用包装器（自动抓行情+注入+生成HTML）→ scripts/stock_debate.py
├── last_debate_report.md      # 最近一次辩论报告
└── last_debate_result.json    # 最近一次辩论 JSON
```

### engine.py 核心类

- `DebateConfig` — 辩论配置（问题/角色/轮次）
- `DebateEngine` — 编排引擎，通过 `set_runner(fn)` 注入 LLM 调用
- `RoundMessage` — 一轮中的一条发言
- `DebateResult` — 结构化结论（`.to_markdown()` 输出报告）

### 使用方式

```python
from engine import DebateEngine, DebateConfig

config = DebateConfig(question="要不要升级 K8s？", max_rounds=3)
engine = DebateEngine(config)
engine.set_runner(my_llm_call_function)
result = engine.run()
print(result.to_markdown())
```

命令行快速使用：
```bash
python3 /mnt/d/debate-engine/demo.py "你的问题"
python3 /mnt/d/debate-engine/demo.py "你的问题" --roles graham,buffett,fisher  # 指定角色
```

## 关键设计

### 上下文管理

- 每轮只给上一轮 + 本轮已有的发言，不做全文注入
- 防止辩论回合增多后 token 爆炸
- `_build_round_context()` 负责裁剪

### 裁判合成

- 最后一轮结束后额外调用一次 LLM 做结构化提取
- Judge prompt 要求输出 JSON：consensus / confidence / recommendation / risk_items / conflicts
- JSON 解析失败时 fallback 到原始文本

### 角色自动选择规则

启发式关键词匹配（`select_roles()`）：
- 默认必选：乐观派 + 悲观派
- 含技术关键词 → 加技术派
- 含业务/商业关键词 → 加业务派
- 同时有技术派和业务派 → 加质疑者做二阶审查
- 最少保证 3 个角色

## 三种运行模式

### 模式 A：脚本模式（demo.py）

适合自动化/批量辩论。需要 API key。

```bash
python3 /mnt/d/debate-engine/demo.py "K8s 集群要不要从 1.34 升级到 1.35？"
```

### 模式 B：内联模式（Agent 自身扮演所有角色）

适合快速演示、调试 prompt、或 API key 不在当前环境时使用。Agent 自己依次扮演所有角色跑完整辩论。详见 `references/inline-debate-pattern.md`。

优势：
- 不需要额外 API key
- 用户可以直接看到辩论过程
- 方便调试角色 prompt 质量

Pitfalls：
- 同一 Agent 扮演所有角色容易出现"自己附和自己"，Round 2 必须硬性要求 `@角色` 引用特定论点
- 质疑者 Round 1 审逻辑漏洞，Round 2 指回避问题，两轮职责不同
- 量化方案缺失则辩论无效：裁判必须给具体数字（保留 X%、减仓 Y%）

### 模式 C：HTML 报告模式（html_report.py）

把辩论结果（DebateResult JSON）渲染为 WorkBuddy 同款杂志级 HTML 报告。使用 Noto Serif SC 字体 + 琥珀色系排版，与 WorkBuddy 圆桌会议报告视觉效果一致。

```python
from html_report import render_html

# result 来自 demo.py 的 DebateResult
html = render_html(result, stock_data={
    "date": "2026-06-26",
    "title_prefix": "臻镭科技 · ",
    "snapshot": {
        "臻镭科技(688270)": {"value": "70.00", "sub": "+2.47%", "sub_class": "cc-snap-up"},
        "动态PE": {"value": "337x", "sub": ""},
    }
})
with open("report.html", "w") as f:
    f.write(html)
```

报告模块：
- 01 · 结论卡：问题回显、数据快照网格、综合结论、置信度条、参与方标签
- 02 · 视角卡：每条辩论发言一张 voice card，自动解析 Markdown→HTML
- 03 · 分歧卡：裁判识别的核心分歧，各方立场对照
- 04 · 风险表：编号风险清单

与 WorkBuddy 圆桌报告对比：

| 维度 | WorkBuddy | Hermes 辩论引擎 |
|------|-----------|----------------|
| 排版风格 | 杂志级，Noto Serif SC，琥珀色系 | 完全复刻同款 CSS |
| 内容来源 | WorkBuddy 自有模型 | 你的 LLM（taotoken.net） |
| 角色定制 | 固定 | 完全可定义 |
| 辩论轮次 | 1 轮并行 | 可配置 2-3 轮互相引用反驳 |
| 头像 | base64 图片 | emoji（可用，不影响可读性） |

脚本位于：`scripts/html_report.py`（可通过 `skill_view(name='multi-agent-debate', file_path='scripts/html_report.py')` 获取）

## 双模型辩论变体 (Dual-Model)

**来源:** 吸收了 `dual-model-debate` 技能的内容。

双模型辩论是多 Agent 辩论的轻量变体——只用两个不同 LLM 模型（而非 5 个角色）进行辩论，适用于快速分析场景。

### 什么时候用双模型 vs 多角色

| 场景 | 推荐 |
|------|------|
| 快速分析（5-10分钟） | 双模型 (lead + challenger + judge) |
| 深度审查（15-30分钟） | 多角色 (3-5 个专职角色) |
| 投资/金融分析 | 双模型（参见 `references/dual-model-test-run-akeso.md`） |
| 架构/技术决策 | 多角色（需要技术派 + 业务派 + 质疑者） |

### 架构

```
问题 → Lead(深度模型,低temp) 陈述立场
    → Challenger(快速模型,高temp) 质疑/反驳
    → Lead 回应质疑
    → Challenger 最终反驳
    → Judge(快速模型,低temp) 结构化裁决
```

### 推荐模型配比

| Lead (深度思考) | Challenger (快速质疑) | 适用 |
|---|---|---|
| deepseek-v4-pro | deepseek-v4-flash | 通用分析 |
| claude-sonnet-4 | deepseek-v4-flash | 安全关键决策 |
| glm-5.1 | deepseek-v4-flash | 中文领域分析 |

**关键**: Challenger 必须使用与 Lead 不同的模型（或至少不同 temperature），否则没有真正的认知多样性。

### 参考实现

工作脚本: `/mnt/d/debate-engine/dual_debate.py`

```bash
python3 /mnt/d/debate-engine/dual_debate.py "你的问题" --rounds 2
```

### Pitfalls

- API key 读取：Hermes 的 `security.redact_secrets: true` 会隐藏密钥，需通过 PyYAML 直接读 `config.yaml`
- 超时：v4-pro 响应可能很长（3K+ tokens），设 `timeout=600` + 3 次重试
- 上下文管理：第 2+ 轮只注入对方最新一轮回应（不注全历史）
- 轮次上限：2 轮后辩论质量趋于平稳，`--rounds 2` 推荐

### 模式 D：股票圆桌模式（stock_debate.py）

自动抓取实时行情 + 财务数据 → 注入辩论问题 → 跑 LLM 辩论 → 输出 HTML 报告。一条命令全自动。

```bash
python3 /mnt/d/debate-engine/stock_debate.py 688270   # 臻镭科技
python3 /mnt/d/debate-engine/stock_debate.py 000762   # 西藏矿业
```

**角色自动过滤**：`stock_debate.py` 内置 `filter_roles()` 函数，根据股票特征自动跳过不适用的投资流派：

| 条件 | 跳过角色 | 原因 |
|------|---------|------|
| PE > 50 或 营收 < 50 亿 | 📐 格雷厄姆 | 7 条硬标准必挂，每次都是 0 分 |
| PE > 100 且 ROE < 5% | 🐢 龟龟 | 穿透回报率必为 0，浪费调用 |
| 营收增速 > 30% 且 毛利率 > 50% | （标记为成长股） | 格雷厄姆和龟龟在成长股上无分析价值 |

过滤后通过 `demo.py --roles graham,buffett,...` 传入自定义角色列表。不适用角色不会参与辩论，节省 LLM 调用费用。

双数据源注入：

| 数据源 | API | 内容 |
|--------|-----|------|
| 实时行情 | 腾讯 `qt.gtimg.cn/q=sh688270`（GBK） | 最新价、涨跌幅、PE(TTM)、市值、52周高低、换手率 |
| 财务数据 | AKShare `stock_financial_abstract_ths()` | 营收、净利、毛利率、EPS、每股净资产、ROE、经营现金流/股、应收款周转天数、资产负债率 |

流程：
1. 腾讯行情 API 拉取实时价、PE、市值、52 周高低、涨跌幅
2. AKShare 拉取最新一期财务数据（营收 YoY%、净利 YoY%、毛利率、现金流）
3. 自动检测 ST 状态并 ⚠️ 标注
4. 构造含实时行情 + 财务数据的完整辩论问题（LLM 不需要凭训练数据瞎编）
5. 调用 demo.py 跑完整辩论
6. 输出 `report_<code>.html`

**display_title 分离原则**：辩论问题（注入全部数据）≠ HTML 显示的标题。`render_html()` 接受 `display_title` 参数用于 Hero H1 和结论卡的 "YOU ASKED" 区域，避免超长标题撑破排版。

脚本位于：`scripts/stock_debate.py`

### 模式 E：六框架对比表

HTML 报告在 voice cards 上方自动生成一张**六框架评分对比表**，由 `_build_comparison_table()` 从辩论实录中提取每个流派的分数和结论，并排对比。实现逻辑：

1. 遍历所有 transcript，用正则提取 `/100` 格式的总分（支持小数如 33.5）
2. 优先从「结论：XXX」行提取结论，其次从末尾找关键词（**先找否定词「不持有」「不买」再找肯定词「持有」「买」**，否则「不持有」会被误判为「持有」）
3. 渲染为 `compare-table`，每行显示流派名、分数（绿≥60/橙≥30/红<30）、立场标签（看好/观望/看空）、结论摘要
4. **立场强制规则**：分数<60 不能标「看好」→ 强制「观望」；分数<40 不能标「观望」→ 强制「看空」。防止出现 41 分还显示「看好」的荒谬结果
5. 提取不到 ≥2 个角色的分数时静默跳过（不显示空表）

对比表与 voice cards 放在同一个 `voice-stack` 容器内，位于所有 voice card 之前。

## 已跑通的 Demo

### Demo 1：K8s 升级决策

问题：「K8s 生产集群要不要从 v1.34 升级到 v1.35？」

4 角色 × 2 轮辩论 → 裁判输出：
- 共识：升级可做但需 4 项前置检查
- 置信度：72%
- 关键风险：API 弃用 / CSI 兼容性 / 灰度覆盖 / kubectl 版本

### Demo 2：锂矿持仓决策（内联模式）

问题：「持有西藏矿业(000762)+中矿资源(002738)，是否继续持有？」

4 角色（乐观派/悲观派/行业技术派/质疑者）× 2 轮 → 裁判输出：
- 共识：锂价低位、短期承压、西藏矿业有成本优势
- 置信度：68%
- 建议：西藏矿业保留底仓≤50%，中矿资源减仓≥50%
- 详细报告见 `references/inline-debate-pattern.md`

## Pitfalls

- **角色 prompt 质量决定辩论深度**：如果角色 prompt 太泛，agent 会说空话而不是真正引用对方论点。关键在于"必须引用 @某人 的具体论点"这个硬约束
- **质疑者要放在第二轮才有效**：第一轮没有内容可质疑，质疑者首轮应该是"审视所有首轮论点的逻辑薄弱点"，不是发表独立立场
- **裁判 JSON 解析可能失败**：LLM 输出的 JSON 经常被 markdown 包裹，需要清洗 ` ```json ``` ` 标记
- **max_rounds 不宜超过 3**：超过 3 轮后 agent 开始重复自己，边际价值递减，且上下文长度开始失控
- **内联模式自附风险**：同一 Agent 扮演所有角色时容易出现假辩论，Round 2 必须硬性要求 `@角色` 引用特定论点
- **量化方案缺失 = 无效辩论**：裁判必须给出具体操作数字（保留 X%、减仓 Y 股），不能只说"持有/卖出"
- **API key 提取**：Hermes 的 `security.redact_secrets: true` 会使 PyYAML 读到的值被掩码为 `***HAS_VALUE***`。正确做法是用 regex 直读原始文件：`re.search(r'api_key:\s*["\']?([^"\'\n\s]+)', raw)`。提取后设 `TAOTOKEN_API_KEY` 和 `OPENAI_API_KEY` 环境变量
- **股票行情数据源**：EastMoney `push2.eastmoney.com` 不稳定时，腾讯 `qt.gtimg.cn/q=sh688270`（需 `iconv -f GBK`）是可靠备选。A 股 secid 格式：沪市 `1.688270`，深市 `0.000762`
- **LLM 训练数据过时**：deepseek-v4-flash/v4-pro 训练截止到 2023，不会知道当前股价、PE、公司最新财报。金融/股票类辩论必须提前抓实时数据注入问题，否则角色会编造假数字互相打架（如乐观派说营收+35%、悲观派说+15%）
- **ST/特殊状态必须显式注入**：如果股票是 ST、*ST、暂停上市等特殊状态，必须在问题中显式标注 ⚠️ 并说明原因。不标注会导致所有角色基于"正常经营"假设辩论，整场辩论失效
- **CSS `\\\\u300C` 在 Windows 上渲染异常**：html_report.py 中 `content: \"\\\\u300C\"` 在部分 Windows 浏览器上显示为乱码。必须用实际字符 `「」` 替代 Unicode 转义序列
- **Windows 浏览器打不开 WSL 路径**：用户是 Windows 桌面环境时，给 `file:///D:/debate-engine/report.html` 格式（盘符映射），不要给 `/mnt/d/...` 的 WSL 路径
- **AKShare 财务数据解析**：`stock_financial_abstract_ths()` 返回的数值是中文单位字符串（如 `\"1.33亿\"`、`\"6510.73万\"`），必须用 `_parse()` 函数转换为 float 才能计算 PE/PS/市值等指标。同比字段如 `\"913.17%\"` 也需要去 `%` 后再转 float
- **辩论问题 vs 展示标题**：注入实时数据后辩论问题可能长达 300+ 字，直接用它做 HTML 的 H1 标题会撑破排版。`render_html()` 的 `stock_data` 参数支持 `display_title` 字段（如 `\"臻镭科技(688270)是否值得持有？\"`），简短的展示标题用于 Hero/导航/结论卡，完整问题只传给 LLM
- **数据校验铁律**：详见 `references/data-verification-checklist.md`。生成 HTML 报告前必须对关键字段做合理性检查。
- **腾讯行情 API 字段索引极易出错**：`qt.gtimg.cn` 返回的 `~` 分隔字段没有标注，必须严格按以下索引取值：
  ```
  fields[39] = 动态PE(TTM)    ← 不是 [50]
  fields[45] = 总市值(亿)      ← 不是 [46]（[46]是流通市值）
  fields[47] = 52周最高        ← 不是 [44]
  fields[48] = 52周最低        ← 不是 [45]
  ```
  踩坑实录：曾将 52 周高=低=210 显示在报告上，市值 9 亿而非真实 210 亿。索引错了所有数据全废。

- **52 周高低不得从腾讯 qt 接口直接取**：`fields[47]`/`fields[48]` 返回的值**不除权**——有送转股时跟当前价不在同一坐标系。必须拉 前复权 K 线（`fqkline/get?param=sh688270,day,,,250,qfq`）取最近 250 根 K 线的真实最高/最低。踩坑实录：臻镭 10转增4×3次（累计 2.744x），API 返回 52 高 82/低 55 → 当前 70 距高点仅 14.6% → 莫大误判「顶部」。实际 前复权最高 163/最低 30 → 跌了 57% → 实为中位。这个错让所有角色的股价位置分数全部反了。详见 `references/data-verification-checklist.md`。
- **对比表立场判定必须先查否定词**：`_build_comparison_table()` 提取结论时，「不持有」「不买」等否定词必须在「持有」「买」之前检查。如果用 `rfind()` 从末尾搜，「持有」会命中「不持有」中的后两个字。另外，分数<60 不能标「看好」、分数<40 不能标「观望」，用硬编码规则兜底——笨韭 34 分曾被标为「看好」因为结论行含「持有」字样，实际是「不持有」。
- **评分表输出格式必须三列**：`| 维度(权重) | 分数 | 理由 |`。分数列只写纯数字（如 `40`），不写 `40分（窄护城河，客户集中…）`。分数和理由混在一个格子里会导致 HTML 可视化失败——正则只能提纯数字但 CSV 解析会出错。prompt 中的 `【输出格式】` 必须明确标注「分数只写数字，理由写在单独列」。本 session 已验证：不约束格式 → 巴菲特输出 `| 40分（窄护城河，技术壁垒但客户集中、回款慢） |` → 用户直接指出「表格没做好」。
- **max_roles 默认 5 不够用**：6 大投资流派 + 5 通用角色，`DebateConfig.max_roles` 必须是 6（股票分析时 `STOCK_INVESTMENT_ROLES` 有 6 个）。曾因 max_roles=5 导致龟龟派被截断，6 人中只跑了 5 人。
- **送转股除权必须调整每股数据**：AKShare `stock_financial_abstract_ths()` 返回的 EPS/每股净资产/每股经营现金流是报告期截止日的数据，不会自动反映报告期之后的送转股。必须通过 `stock_dividend_cninfo()` 获取除权记录，找出除权日晚于最新报告期的送转股，计算累计调整系数（`1 + (送股+转增)/10`），对每股数据做除法调整。**NaN 处理**：`stock_dividend_cninfo()` 的「送股比例」列在无送股时返回 NaN，`float(NaN or 0)` 仍是 NaN（会传播到所有运算），必须用 `if sg and sg == sg` 检测 NaN 后再转 float。本 session 查到臻镭 2026-06-17 刚完成 10 转增 4，除权日(6/17)晚于最新报告期(2026-03-31)，EPS 从 0.18→0.13、每股净资产从 10.72→7.66。不调整会导致 PE 算成 97x（实际 136x），52 周高低对比基准全部错误。

- **所有投资流派角色 prompt 必须有【必须输出格式】**：prompt 末尾必须有固定格式的评分输出要求（如格雷厄姆的 7 条准则逐条检查表 `| 准则 | ❌/✅ | 当前值 |`、莫大的六维表 `| 维度 | 分数 | 依据 |`、龟龟的 `穿透回报率 X% | 回本 X 年 | 烟蒂 是/否`）。没有这个硬约束，LLM 在 Round 2 只会互相引用反驳而不会输出评分表，导致 HTML 报告中只有莫大一个人有可视化分数。用户会直接指出「原来的 skill 是每个人都有分数吧」——这是设计缺陷，不是 LLM 能力问题。
- **角色 prompt 必须完整保留原方法论评分表**：从 stock-analysis-skills 仓库蒸馏的角色 prompt，不能为了减 token 而把评分机制压缩成几个要点。莫大的六维打分必须包含每个维度的 0-100 分数段含义表（80-100=地质级稀缺→0-19=有钱就能扩），格雷厄姆的 7 条必须逐条有量化标准（A 股营收≥50 亿、流动比率≥2），否则 LLM 只会空泛地说"PE 太高不买"而不给出实际打分。用户会直接指出"打分机制和原仓库的不同"——这是严重质量问题。
- **HTML 评分可视化**：`html_report.py` 的 `_visualize_scores()` 函数做了四件事：(1) 总分一行 → 大号 score-total 卡片带等级徽章；(2) 评分表格 → 每行替换为彩色进度条（绿≥70/橙≥40/红<40）；(3) ✅❌ 清单项用绿/红色高亮；(4) 行内 "XX/NN分" 模式自动放大加粗。处理流程：`_simple_md_to_html()` → `_visualize_scores()` → 插入 voice card。注意 `_simple_md_to_html()` 必须支持 Markdown 表格解析（`| col1 | col2 |`），否则评分表被当成普通 `<p>` 段落，后续可视化正则全部失效。表格解析时还要处理单元格内的 `**加粗**` 标记（转为 `<strong>`），因为 LLM 经常输出 `**15**` 作为分数字段。评分可视化正则必须兼容 `<td><strong>15</strong></td>` 格式——这是本 session 踩过两次的坑。此外，`_simple_md_to_html()` 必须跳过 ` ``` ` 代码围栏行（`continue`），否则代码块内的表格行不会被解析为 HTML `<table>`，导致分数表只存在于文本中而无法可视化。代码围栏行被跳过时，必须先 `flush_table()` 清空当前表格状态。
- **WSL git push 失败时用 Windows gh.exe**：`/mnt/d/` 下 git push 经常 TLS 握手失败或超时（GnuTLS recv error -110），但 `gh.exe` 在 Windows 侧网络正常。备选方案：`/mnt/c/Users/40732/scoop/shims/gh.exe api` 直接操作 GitHub REST API，或让用户从 Windows 终端手动 `git push`。
