-- @query: q11_data_quality
-- Long form: each missing count is named, rather than reusing unrelated column names.
SELECT 'orders' AS table_name, 'order_delivered_customer_date' AS field, COUNT(*) AS rows_cnt,
       SUM(order_delivered_customer_date IS NULL) AS missing
FROM orders
UNION ALL
SELECT 'orders', 'order_approved_at', COUNT(*), SUM(order_approved_at IS NULL) FROM orders
UNION ALL
SELECT 'order_reviews', 'review_comment_message', COUNT(*), SUM(review_comment_message IS NULL)
FROM order_reviews
UNION ALL
SELECT 'order_reviews', 'review_comment_title', COUNT(*), SUM(review_comment_title IS NULL) FROM order_reviews
UNION ALL
SELECT 'products', 'product_category_name', COUNT(*), SUM(product_category_name IS NULL)
FROM products;

-- @query: q01_state_gmv
-- 多表 JOIN：各州成交金额、订单量与客单价
SELECT c.customer_state AS state,
       ROUND(SUM(oi.price + oi.freight_value), 2) AS gmv,
       COUNT(DISTINCT o.order_id) AS orders,
       ROUND(SUM(oi.price + oi.freight_value) / COUNT(DISTINCT o.order_id), 2) AS aov
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 1
ORDER BY gmv DESC
LIMIT 10;

-- @query: q02_repeat_users
-- 复购用户占比：按 customer_unique_id 聚合（注意 customer_id 是每单一个，不是人）
WITH per_user AS (
  SELECT c.customer_unique_id AS uid, COUNT(*) AS n_orders
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
  GROUP BY 1
)
SELECT COUNT(*) AS total_users,
       SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) AS repeat_users,
       ROUND(100.0 * SUM(CASE WHEN n_orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct,
       ROUND(AVG(n_orders), 3) AS avg_orders_per_user
FROM per_user;

-- @query: q03_last_order_per_user
-- 窗口函数 ROW_NUMBER：每个用户最近一笔订单
WITH ranked AS (
  SELECT c.customer_unique_id AS uid,
         o.order_id,
         o.order_status,
         o.order_purchase_timestamp AS ts,
         ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp DESC) AS rn
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
)
SELECT uid, order_id, order_status, ts
FROM ranked
WHERE rn = 1
ORDER BY ts DESC
LIMIT 5;

-- @query: q04_repeat_interval
-- 窗口函数 LAG：复购间隔天数
WITH seq AS (
  SELECT c.customer_unique_id AS uid,
         o.order_purchase_timestamp AS ts,
         LAG(o.order_purchase_timestamp) OVER (
           PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp
         ) AS prev_ts
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
)
SELECT COUNT(*) AS repeat_pairs,
       ROUND(AVG(julianday(ts) - julianday(prev_ts)), 1) AS avg_days_between_orders,
       ROUND(MIN(julianday(ts) - julianday(prev_ts)), 1) AS min_days,
       ROUND(MAX(julianday(ts) - julianday(prev_ts)), 1) AS max_days
FROM seq
WHERE prev_ts IS NOT NULL;

-- @query: q05_monthly_gmv_cum
-- 窗口函数 SUM OVER：月度 GMV 与累计 GMV
WITH m AS (
  SELECT strftime('%Y-%m', o.order_purchase_timestamp) AS ym,
         SUM(oi.price + oi.freight_value) AS gmv
  FROM orders o
  JOIN order_items oi ON oi.order_id = o.order_id
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY 1
)
SELECT ym,
       ROUND(gmv, 2) AS gmv,
       ROUND(SUM(gmv) OVER (ORDER BY ym), 2) AS cum_gmv
FROM m
ORDER BY ym;

-- @query: q06_funnel
-- 订单漏斗：下单 → 支付通过 → 发货 → 签收
SELECT COUNT(*) AS placed,
       SUM(CASE WHEN order_approved_at IS NOT NULL THEN 1 ELSE 0 END) AS approved,
       SUM(CASE WHEN order_delivered_carrier_date IS NOT NULL THEN 1 ELSE 0 END) AS shipped,
       SUM(CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) AS delivered,
       ROUND(100.0 * SUM(CASE WHEN order_delivered_customer_date IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 2) AS delivered_rate_pct
FROM orders;

-- @query: q07_cohort_return
-- Fixed next-calendar-month return. All placed orders, matching q02.
-- Exclude cohorts whose next month is beyond the chosen complete-month cutoff.
WITH first_order AS (
  SELECT c.customer_unique_id AS uid,
         MIN(strftime('%Y-%m', o.order_purchase_timestamp)) AS cohort_month
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
  GROUP BY 1
),
user_months AS (
  SELECT DISTINCT c.customer_unique_id AS uid,
         strftime('%Y-%m', o.order_purchase_timestamp) AS ym
  FROM orders o
  JOIN customers c ON c.customer_id = o.customer_id
)
SELECT f.cohort_month,
       COUNT(DISTINCT f.uid) AS cohort_users,
       COUNT(DISTINCT CASE WHEN um.ym = strftime('%Y-%m', date(f.cohort_month || '-01', '+1 month')) THEN um.uid END) AS returned_users,
       ROUND(100.0 * COUNT(DISTINCT CASE WHEN um.ym = strftime('%Y-%m', date(f.cohort_month || '-01', '+1 month')) THEN um.uid END)
             / COUNT(DISTINCT f.uid), 2) AS return_rate_pct
FROM first_order f
LEFT JOIN user_months um ON um.uid = f.uid
WHERE f.cohort_month <= '2018-07'
GROUP BY 1
ORDER BY 1;

-- @query: q08_rfm
-- R/M use quintiles; F uses actual order frequency so ties are not split.
WITH base AS (
  SELECT c.customer_unique_id AS uid,
         MAX(o.order_purchase_timestamp) AS last_order,
         COUNT(DISTINCT o.order_id) AS freq,
         SUM(oi.price + oi.freight_value) AS monetary
  FROM valid_orders o
  JOIN customers c ON c.customer_id = o.customer_id
  JOIN order_items oi ON oi.order_id = o.order_id
  GROUP BY 1
),
scored AS (
  SELECT uid,
         NTILE(5) OVER (ORDER BY julianday(last_order), uid) AS r_score,
         CASE WHEN freq >= 5 THEN 5 ELSE freq END AS f_score,
         NTILE(5) OVER (ORDER BY monetary, uid) AS m_score
  FROM base
)
SELECT r_score, f_score, m_score, COUNT(*) AS users
FROM scored
GROUP BY 1, 2, 3
ORDER BY users DESC
;

-- @query: q09_delivery_vs_review
-- 配送时长与差评率的关系
WITH d AS (
  SELECT o.order_id,
         julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp) AS days,
         r.review_score
  FROM orders o
  JOIN latest_reviews r ON r.order_id = o.order_id
  WHERE o.order_delivered_customer_date IS NOT NULL
    AND julianday(o.order_delivered_customer_date) >= julianday(o.order_purchase_timestamp)
    AND r.review_score BETWEEN 1 AND 5
)
SELECT CASE
         WHEN days <= 7 THEN '0-7天'
         WHEN days <= 14 THEN '(7,14]天'
         WHEN days <= 21 THEN '(14,21]天'
         ELSE '21天以上'
       END AS delivery_bucket,
       COUNT(*) AS orders,
       ROUND(AVG(days), 1) AS avg_days,
       ROUND(AVG(review_score), 2) AS avg_score,
       ROUND(100.0 * SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 2) AS bad_review_pct
FROM d
GROUP BY 1
ORDER BY MIN(days);

-- @query: q10_category_share
-- 品类 GMV Top10 与占比（窗口函数算占比）
WITH p AS (
  SELECT COALESCE(t.product_category_name_english, pr.product_category_name, 'unknown') AS category,
         oi.price + oi.freight_value AS v
  FROM order_items oi
  JOIN valid_orders o ON o.order_id = oi.order_id
  JOIN products pr ON pr.product_id = oi.product_id
  LEFT JOIN category_translation t ON t.product_category_name = pr.product_category_name
)
SELECT category,
       ROUND(SUM(v), 2) AS gmv,
       ROUND(100.0 * SUM(v) / (SELECT SUM(v) FROM p), 2) AS gmv_share_pct
FROM p
GROUP BY 1
ORDER BY gmv DESC
LIMIT 10;

-- @query: q12_seller_concentration
-- 卖家集中度：头部卖家贡献了多少 GMV
WITH s AS (
  SELECT oi.seller_id, SUM(oi.price + oi.freight_value) AS gmv
  FROM order_items oi
  JOIN valid_orders o ON o.order_id = oi.order_id
  GROUP BY 1
),
ranked AS (
  SELECT seller_id, gmv,
         ROW_NUMBER() OVER (ORDER BY gmv DESC) AS rn,
         SUM(gmv) OVER () AS total_gmv
  FROM s
)
SELECT ROUND(SUM(CASE WHEN rn <= 10 THEN gmv ELSE 0 END), 2) AS top10_gmv,
       ROUND(100.0 * SUM(CASE WHEN rn <= 10 THEN gmv ELSE 0 END) / MAX(total_gmv), 2) AS top10_share_pct,
       COUNT(*) AS sellers
FROM ranked;
