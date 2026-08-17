USE olist_db;

-- 배송완료 주문 기준으로만 매출 흐름 보기
-- 여기서는 전체 실매출 규모, 월별 매출 추이, 결제수단별 매출 구성을 확인

-- 전체 배송완료 매출 합계
WITH delivered_sales AS (
    SELECT
        op.order_id,
        o.customer_id,
        o.status,
        o.purchase_timestamp,
        op.payment_type,
        op.payment_value
    FROM orders o
    JOIN order_payments op
        ON o.order_id = op.order_id
    WHERE o.status = 'delivered'
)
SELECT
    SUM(payment_value) AS total_sales
FROM delivered_sales;


-- 월별 매출 추이
-- 흐름만 보는 용도라 연-월 기준으로 집계
WITH delivered_sales AS (
    SELECT
        op.order_id,
        o.customer_id,
        o.status,
        o.purchase_timestamp,
        op.payment_type,
        op.payment_value
    FROM orders o
    JOIN order_payments op
        ON o.order_id = op.order_id
    WHERE o.status = 'delivered'
)
SELECT
    DATE_FORMAT(purchase_timestamp, '%Y-%m') AS year_m,
    SUM(payment_value) AS sales
FROM delivered_sales
GROUP BY DATE_FORMAT(purchase_timestamp, '%Y-%m')
ORDER BY year_m;


-- 월별 결제수단별 매출
-- payment_type별로 어떤 결제수단이 많이 쓰였는지 같이 보기
WITH delivered_sales AS (
    SELECT
        op.order_id,
        o.customer_id,
        o.status,
        o.purchase_timestamp,
        op.payment_type,
        op.payment_value
    FROM orders o
    JOIN order_payments op
        ON o.order_id = op.order_id
    WHERE o.status = 'delivered'
),
monthly_view AS (
    SELECT
        order_id,
        customer_id,
        status,
        purchase_timestamp,
        payment_type,
        payment_value,
        DATE_FORMAT(purchase_timestamp, '%Y-%m') AS year_m
    FROM delivered_sales
)
SELECT
    year_m,
    payment_type,
    SUM(payment_value) AS sales
FROM monthly_view
GROUP BY year_m, payment_type
ORDER BY year_m, sales DESC;