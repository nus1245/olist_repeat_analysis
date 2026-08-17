USE olist_db;

-- 핵심 고객 비중이 높은 지역 찾기
-- 단순 주문 수가 아니라
-- 구조적으로 핵심 고객이 많은지, 평균 이상 매출 고객이 많은지를 같이 봄

WITH customer_segment AS (
    SELECT
        customer_unique_id,
        CASE WHEN customer_ratio <= 0.7067 THEN 0 ELSE 1 END AS structure_segment,
        CASE WHEN lorenz_slope >= 1 THEN 1 ELSE 0 END AS avg_segment
    FROM customer_lorenz
),
join_customer_table AS (
    SELECT
        cm.customer_unique_id,
        cm.state,
        cm.clean_city,
        cm.sales,
        cs.structure_segment,
        cs.avg_segment
    FROM customer_segment cs
    JOIN customer_master_table cm
        ON cs.customer_unique_id = cm.customer_unique_id
    WHERE cm.delivered_order_cnt >= 1
)
SELECT
    state,
    clean_city,
    SUM(structure_segment) AS core_cnt,
    ROUND(SUM(structure_segment) * 1.0 / COUNT(*), 4) AS core_ratio,
    SUM(avg_segment) AS above_avg_cnt,
    ROUND(SUM(avg_segment) * 1.0 / COUNT(*), 4) AS above_avg_ratio,
    SUM(sales) AS sales
FROM join_customer_table
GROUP BY state, clean_city
ORDER BY sales DESC;