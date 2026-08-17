USE olist_db;

-- 앞에서 나눈 세그먼트가 실제로 행동 차이가 있는지 확인
-- 여기서는 카테고리 분포랑 주문 횟수 분포를 같이 봄

-- 1) Pareto 세그먼트별 카테고리 분포
-- Core / Mid / Low 고객이 어떤 카테고리를 주로 사는지 비교
WITH customer_segment AS (
    SELECT
        customer_unique_id,
        CASE WHEN customer_ratio <= 0.7067 THEN 0 ELSE 1 END AS structure_segment,
        CASE WHEN lorenz_slope >= 1 THEN 1 ELSE 0 END AS avg_segment,
        CASE
            WHEN revenue_ratio >= 0.8 THEN 'Core'
            WHEN revenue_ratio >= 0.5 THEN 'Mid'
            ELSE 'Low'
        END AS pareto_segment
    FROM customer_lorenz
),
segment_order_product AS (
    SELECT
        st.customer_unique_id,
        st.pareto_segment,
        st.structure_segment,
        cne.category_group
    FROM customer_segment st
    JOIN customers c
        ON st.customer_unique_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    JOIN category_names_english cne
        ON p.product_category = cne.product_category
)
SELECT
    pareto_segment,
    category_group,
    COUNT(*) AS cnt,
    ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY pareto_segment), 4) AS ratio
FROM segment_order_product
GROUP BY pareto_segment, category_group
ORDER BY pareto_segment, ratio DESC;


-- 2) Pareto 세그먼트별 주문 횟수 분포
-- 많이 기여하는 고객이 진짜 주문도 많이 하는지 보기
WITH customer_segment AS (
    SELECT
        customer_unique_id,
        CASE
            WHEN revenue_ratio >= 0.8 THEN 'Core'
            WHEN revenue_ratio >= 0.5 THEN 'Mid'
            ELSE 'Low'
        END AS pareto_segment
    FROM customer_lorenz
),
segment_order_count AS (
    SELECT
        st.customer_unique_id,
        st.pareto_segment,
        COUNT(o.order_id) AS order_count
    FROM customer_segment st
    JOIN customers c
        ON st.customer_unique_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    GROUP BY st.customer_unique_id, st.pareto_segment
)
SELECT
    pareto_segment,
    order_count,
    COUNT(*) AS customer_cnt,
    ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY pareto_segment), 4) AS ratio
FROM segment_order_count
GROUP BY pareto_segment, order_count
ORDER BY pareto_segment, order_count;


-- 3) structure 세그먼트별 주문 횟수 분포
-- 로렌츠 기준으로 나눈 핵심 구간이 실제 주문 행동 차이도 보이는지 확인
WITH customer_segment AS (
    SELECT
        customer_unique_id,
        CASE WHEN customer_ratio <= 0.7067 THEN 0 ELSE 1 END AS structure_segment
    FROM customer_lorenz
),
segment_order_count AS (
    SELECT
        st.customer_unique_id,
        st.structure_segment,
        COUNT(o.order_id) AS order_count
    FROM customer_segment st
    JOIN customers c
        ON st.customer_unique_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    GROUP BY st.customer_unique_id, st.structure_segment
)
SELECT
    structure_segment,
    order_count,
    COUNT(*) AS customer_cnt,
    ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY structure_segment), 4) AS ratio
FROM segment_order_count
GROUP BY structure_segment, order_count
ORDER BY structure_segment, order_count;


-- 4) 비교 기준으로 전체 배송완료 고객 주문 횟수도 같이 봄
WITH delivered_order_count AS (
    SELECT
        cm.customer_unique_id,
        COUNT(o.order_id) AS delivered_order_count
    FROM customer_master_table cm
    JOIN customers c
        ON cm.customer_unique_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE o.status = 'delivered'
    GROUP BY cm.customer_unique_id
)
SELECT
    delivered_order_count AS order_count,
    COUNT(*) AS customer_cnt,
    ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (), 4) AS ratio
FROM delivered_order_count
GROUP BY delivered_order_count
ORDER BY delivered_order_count;