# Tableau 看板重建指南（尚未完成）

当前完成的是 HTML 看板和 CSV 导出；没有 Tableau 工作簿或已发布链接。实际完成并核验后，才在简历中写 Tableau 项目。

先在仓库根目录运行 `node run.mjs` 和 `node dashboard/export-for-tableau.mjs`。

| 数据源 | 行数（当前快照） | 用法 |
| --- | --- | --- |
| monthly_gmv.csv | 23 | month 为有序月份，gmv 为 BRL，折线图 |
| delivery_review.csv | 4 | bucket、orders、bad_review_pct，柱图，保持配送时间顺序 |
| funnel.csv | 4 | stage、orders，按 step_order 排序，时间戳覆盖描述 |
| category_gmv.csv | 10 | category、gmv，降序横条图 |
| state_gmv.csv | 10 | state、gmv，降序横条图 |
| cohort_return.csv | 22 | cohort_month、return_rate_pct，固定次月回流 |
| kpi_summary.csv | 1 | 四张指标卡：total_gmv、delivered_rate_pct、repeat_rate_pct、late_delivery_bad_review_pct |

七个 CSV 应作为独立数据源使用；不要把不同粒度的汇总表横向 JOIN 成明细表。先分别建工作表，再加入 Dashboard。

数据口径：GMV 为商品价+运费，排除取消/不可用订单；月度图与 KPI 金额仅展示 2018-09 以前。重复下单使用所有订单状态；配送评价每单只留最新答复；cohort 为首单之后下一自然月，末 cohort 为 2018-07。

CSV 的百分比已经是 0–100 数值，直接显示并附加 % 符号，避免再次乘 100。月份可保留 YYYY-MM 文本以保持字典序。只展示汇总，不上传原始评论等非必要内容。

在 Tableau 中完成连接、图表、排版与保存后，打开实际分享链接确认公众能看到，再记录版本、截图和链接。具体菜单因 Tableau 版本而异，本次未实操验证。
