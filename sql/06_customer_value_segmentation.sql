USE olist_db;

DROP VIEW IF EXISTS customer_lorenz;

-- 배송완료 고객만 놓고 매출 기준 세그먼트를 만들기 위한 베이스
-- 고객 비중 대비 매출 비중이 얼마나 따라오는지 보려고 로렌츠용 값들을 계산함
CREATE VIEW customer_lorenz AS
SELECT
    customer_unique_id,
    sales,
    SUM(sales) OVER (ORDER BY sales ASC) AS cum_sales,
    SUM(sales) OVER (ORDER BY sales ASC) / SUM(sales) OVER () AS revenue_ratio,
    ROW_NUMBER() OVER (ORDER BY sales ASC) AS customer_cnt,
    ROW_NUMBER() OVER (ORDER BY sales ASC) / COUNT(*) OVER () AS customer_ratio,
    sales / AVG(sales) OVER () AS lorenz_slope,
    ROW_NUMBER() OVER (ORDER BY sales ASC) / COUNT(*) OVER ()
      - SUM(sales) OVER (ORDER BY sales ASC) / SUM(sales) OVER () AS distance
FROM customer_master_table
WHERE delivered_order_cnt >= 1;


-- 고객 비중 대비 매출 비중 차이가 가장 큰 지점
-- 여기서 구조적으로 매출 편중이 가장 많이 드러난다고 볼 수 있음
SELECT
    customer_unique_id,
    sales,
    customer_ratio,
    revenue_ratio,
    lorenz_slope,
    distance
FROM customer_lorenz
ORDER BY distance DESC
LIMIT 1;


-- 실제 분석에서는 세 가지 기준으로 같이 나눠서 봄
-- structure_segment : 로렌츠 기준으로 나눈 구조 구간
-- avg_segment : 평균 매출 이상인지
-- pareto_segment : 누적 매출 기준으로 Core / Mid / Low 구간
WITH customer_segment AS (
    SELECT
        customer_unique_id,
        sales,
        customer_ratio,
        revenue_ratio,
        lorenz_slope,
        distance,
        CASE WHEN customer_ratio <= 0.7067 THEN 0 ELSE 1 END AS structure_segment,
        CASE WHEN lorenz_slope >= 1 THEN 1 ELSE 0 END AS avg_segment,
        CASE
            WHEN revenue_ratio >= 0.8 THEN 'Core'
            WHEN revenue_ratio >= 0.5 THEN 'Mid'
            ELSE 'Low'
        END AS pareto_segment
    FROM customer_lorenz
)
SELECT *
FROM customer_segment;