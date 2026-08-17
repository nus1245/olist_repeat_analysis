USE olist_db;

-- 재구매 고객만 따로 놓고 주문 패턴을 보는 쿼리
-- 주문 순서가 늘어날수록 간격이 줄어드는지
-- 매출이 커지는지
-- 어떤 카테고리를 주로 사는지 확인하려는 목적

-- 먼저 재구매 고객 주문을 주문단위로 다시 묶음
WITH repeat_customer_base AS (
    SELECT
        cm.customer_unique_id,
        o.order_id,
        o.purchase_timestamp,
        o.status,
        SUM(op.payment_value) AS order_sales
    FROM customer_master_table cm
    JOIN customers c
        ON cm.customer_unique_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    LEFT JOIN order_payments op
        ON o.order_id = op.order_id
    WHERE cm.repeat_customer = 1
    GROUP BY
        cm.customer_unique_id,
        o.order_id,
        o.purchase_timestamp,
        o.status
),

-- 고객별 주문 순서를 다시 매김
-- 이전 주문과 비교할 값도 같이 붙여둠
order_sequence AS (
    SELECT
        customer_unique_id,
        order_id,
        purchase_timestamp,
        status,
        order_sales,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_timestamp, order_id
        ) AS order_times,
        LAG(order_sales) OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_timestamp, order_id
        ) AS prev_order_sales,
        LAG(purchase_timestamp) OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_timestamp, order_id
        ) AS prev_purchase_timestamp,
        DATEDIFF(
            purchase_timestamp,
            LAG(purchase_timestamp) OVER (
                PARTITION BY customer_unique_id
                ORDER BY purchase_timestamp, order_id
            )
        ) AS days_from_prev_order,
        order_sales - LAG(order_sales) OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_timestamp, order_id
        ) AS diff_order_sales
    FROM repeat_customer_base
)

-- 주문 몇 번째인지에 따라 간격과 평균 매출 비교
SELECT
    order_times,
    COUNT(*) AS order_cnt,
    ROUND(AVG(days_from_prev_order), 2) AS avg_days_from_prev_order,
    MIN(days_from_prev_order) AS min_days_from_prev_order,
    MAX(days_from_prev_order) AS max_days_from_prev_order,
    ROUND(AVG(order_sales), 2) AS avg_order_sales
FROM order_sequence
GROUP BY order_times
ORDER BY order_times;



-- 재구매 고객의 주문 1~4회차 카테고리 분포
-- 첫 구매와 이후 주문에서 카테고리 흐름이 달라지는지 보기 위함
WITH repeat_customer_base AS (
    SELECT
        cm.customer_unique_id,
        o.order_id,
        o.purchase_timestamp,
        SUM(op.payment_value) AS order_sales
    FROM customer_master_table cm
    JOIN customers c
        ON cm.customer_unique_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    LEFT JOIN order_payments op
        ON o.order_id = op.order_id
    WHERE cm.repeat_customer = 1
    GROUP BY
        cm.customer_unique_id,
        o.order_id,
        o.purchase_timestamp
),
order_sequence AS (
    SELECT
        customer_unique_id,
        order_id,
        purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_timestamp, order_id
        ) AS order_times
    FROM repeat_customer_base
),
order_item_category AS (
    SELECT
        os.customer_unique_id,
        os.order_times,
        os.order_id,
        cne.category_group
    FROM order_sequence os
    JOIN order_items oi
        ON os.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    JOIN category_names_english cne
        ON p.product_category = cne.product_category
    WHERE os.order_times IN (1, 2, 3, 4)
)
SELECT
    order_times,
    category_group,
    COUNT(*) AS cnt,
    ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY order_times), 4) AS ratio
FROM order_item_category
GROUP BY order_times, category_group
ORDER BY order_times, ratio DESC;


-- 위 결과를 한 줄 비교 형태로 보려고 피벗
WITH repeat_customer_base AS (
    SELECT
        cm.customer_unique_id,
        o.order_id,
        o.purchase_timestamp
    FROM customer_master_table cm
    JOIN customers c
        ON cm.customer_unique_id = c.customer_unique_id
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE cm.repeat_customer = 1
),
order_sequence AS (
    SELECT
        customer_unique_id,
        order_id,
        ROW_NUMBER() OVER (
            PARTITION BY customer_unique_id
            ORDER BY purchase_timestamp, order_id
        ) AS order_times
    FROM repeat_customer_base
),
order_item_category AS (
    SELECT
        os.order_times,
        COALESCE(cne.category_group, 'Unknown') AS category_group
    FROM order_sequence os
    JOIN order_items oi
        ON os.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN category_names_english cne
        ON p.product_category = cne.product_category
    WHERE os.order_times IN (1, 2, 3, 4)
),
base AS (
    SELECT
        order_times,
        category_group,
        COUNT(*) AS cnt,
        COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (PARTITION BY order_times) AS ratio
    FROM order_item_category
    GROUP BY order_times, category_group
)
SELECT
    category_group,
    MAX(CASE WHEN order_times = 1 THEN ratio END) AS order_1,
    MAX(CASE WHEN order_times = 2 THEN ratio END) AS order_2,
    MAX(CASE WHEN order_times = 3 THEN ratio END) AS order_3,
    MAX(CASE WHEN order_times = 4 THEN ratio END) AS order_4
FROM base
GROUP BY category_group
ORDER BY order_1 DESC;