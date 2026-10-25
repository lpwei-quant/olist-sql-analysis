# Olist 电商订单分析：SQL、指标口径与经营看板

基于 8 张公开数据表、99,441 笔订单的电商经营分析。12 项 SQL 查询覆盖 GMV、复购、次月回流、RFM、履约与评价，配套 HTML 看板、PDF 报告，并用独立的 Python 脚本从原始 CSV 复核结果。

## 数据与口径

- 数据发布方：[Olist / Kaggle](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)，覆盖 2016-09 至 2018-10。下载其中 8 个 CSV 至 `data/`，文件名和本次运行 SHA-256 见 [source-manifest.json](results/source-manifest.json)。不需要 geolocation 表。
- 原始数据不随仓库分发；本次运行的字段、规模与内部关联已核对，SHA-256 记录在 source-manifest.json 中供复现比对。
- 金额统一为商品价格 + 运费，单位 **BRL**；月份、地区、品类、卖家和 RFM 均剔除 canceled / unavailable。该 GMV 是项目自定义口径，不是净收入或已结算收入。
- 用户使用 `customer_unique_id`。全期重复下单率和次月回流包含所有订单状态，因此不能称为成交复购率。
- 配送分析每单保留最新答复评价，再排除无签收时间、负配送天数和非法评分；差评定义为 1–2 分。分桶为 [0,7]、(7,14]、(14,21]、(21,+∞) 天。
- 时间戳覆盖率描述订单履约进度，不是访客 / 点击转化漏斗。

## 关键结果

| delivery_bucket | orders | avg_score | bad_review_pct |
| --- | --- | --- | --- |
| 0-7天 | 25933 | 4.42 | 7.45 |
| (7,14]天 | 40000 | 4.31 | 8.96 |
| (14,21]天 | 17582 | 4.14 | 11.68 |
| 21天以上 | 12315 | 3.12 | 38.21 |

- 签收时间戳覆盖率 **97.02%**。
- 全期重复下单率 **3.12%**；观察长度因用户首单日期不同而不同。
- 有效订单口径下 Top10 卖家贡献 **12.85%** 的含运费 GMV，涉及 3053 个卖家。
- 配送超过 21 天的订单差评率是 7 天内订单的 5 倍以上，履约时效是改善评价的优先方向；落地预警或召回策略前，可通过实验估计效果与成本。

## 12 个查询

数据质量（q11）、州金额（q01）、重复下单（q02）、最近订单（q03）、下单间隔（q04）、月度及累计金额（q05）、履约时间戳覆盖（q06）、固定次月回流（q07）、RFM（q08）、配送评价（q09）、品类金额（q10）、卖家集中度（q12）。

RFM 的 R/M 使用 NTILE(5)，并列值以用户标识确定顺序，仅作探索性等人数分层；F 按真实下单次数 1、2、3、4、≥5 分层，避免把同为一次购买的用户强行排成不同频次档。输出保留 R/F/M 三维，不能凭分数断言某群体召回成本最低。

次月回流按首单后下一自然月计算，只保留首单月份不晚于 2018-07 的 cohort；选 2018-08 为分析末月是针对末端稀疏数据的分析决定，不是来源方确认的数据完备性保证。

## 复现

需要 Node.js 24（已核验 24.14.0，无 npm 依赖）；独立原始 CSV 核验使用 Python 3.12 标准库。

```sh
node run.mjs
node dashboard/build-dashboard.mjs
node dashboard/export-for-tableau.mjs
python verify.py
```

下载 CSV 后按以上顺序运行。缺少输入、CSV 列异常或 SQL 失败会报错退出。`node run.mjs` 只构建数据库与结果；看板和 Tableau CSV 需运行后两条命令。

- [完整 SQL](sql/queries.sql) / [自动结果](results/results.md)
- [HTML 看板](dashboard/index.html)：下载仓库后双击打开；GitHub 文件页不直接运行 HTML。
- [PDF 报告](report/Olist电商数据分析报告.pdf) / [审计记录](AUDIT.md)
- 报告源码 `report/report.tex` 中的数值对应本次冻结结果；修改数据后需同步正文，进入 report 目录执行 `xelatex -jobname=Olist电商数据分析报告 report.tex`。
- Tableau 版本提供导出 CSV 与[重建指南](dashboard/Tableau重建指南.md)。

## 设计要点

- 复购按 `customer_unique_id` 计算：`customer_id` 每单一个，按它算会把复购率压成 0。
- 评价表先按订单去重，避免“一单多评价”重复计数。
- GMV、品类、地区、卖家统一同一订单过滤条件，保证 SQL 结果、导出表和看板口径一致。
- 次月回流采用固定自然月窗口，减少不同 cohort 观察期长短不一造成的偏差。
- SQL 为 SQLite 方言，迁移 MySQL 8 只需改写 `julianday` / `strftime` 等日期函数。

<sub>使用 AI 编程工具辅助开发，指标口径设计、结果核验与结论由本人负责。</sub>
