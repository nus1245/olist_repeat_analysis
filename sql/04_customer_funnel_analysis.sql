USE olist_db;

-- 주문 고객 기준으로 어디서 가장 많이 이탈하는지 보기 위한 쿼리
-- 주문시도 -> 배송완료 -> 재시도 -> 재구매 흐름으로 확인

-- 보는 값
-- order_customer_cnt : 주문 고객 수
-- delivered_customer_cnt : 배송완료 고객 수
-- repeat_customer_cnt : 재구매 고객 수
-- repeated_attempt_customer_cnt : 주문을 2번 이상 시도한 고객 수

-- 해석할 때는
-- 배송완료율이 높은지
-- 재구매율이 낮은지
-- 주문을 여러 번 시도한 고객이 실제 재구매로 이어지는지
-- 이 세 가지를 같이 보면 됨
SELECT
    COUNT(*) AS order_customer_cnt,
    SUM(active_customer) AS delivered_customer_cnt,
    SUM(repeat_customer) AS repeat_customer_cnt,
    SUM(interest_customer) AS repeated_attempt_customer_cnt,
    ROUND(SUM(active_customer) * 1.0 / COUNT(*), 4) AS delivered_customer_rate,
    ROUND(SUM(repeat_customer) * 1.0 / NULLIF(SUM(active_customer), 0), 4) AS repeat_rate,
    ROUND(SUM(interest_customer) * 1.0 / COUNT(*), 4) AS repeated_attempt_rate,
    ROUND(SUM(repeat_customer) * 1.0 / NULLIF(SUM(interest_customer), 0), 4) AS interest_to_repeat_rate
FROM customer_master_table;


-- 퍼널 차트용으로 바로 쓸 수 있게 단계별 고객 수만 따로 뽑음
SELECT 'order_customers' AS stage, 1 AS stage_order, COUNT(*) AS customer_cnt
FROM customer_master_table
UNION ALL
SELECT 'delivered_customers', 2, SUM(active_customer)
FROM customer_master_table
UNION ALL
SELECT 'repeat_attempt_customers', 3, SUM(interest_customer)
FROM customer_master_table
UNION ALL
SELECT 'repeat_customers', 4, SUM(repeat_customer)
FROM customer_master_table;