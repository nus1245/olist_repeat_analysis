USE olist_db;

DROP VIEW IF EXISTS customer_master_table;
DROP VIEW IF EXISTS delivered_view;
DROP VIEW IF EXISTS one_customer_table;


-- base 테이블: 주문_고객_테이블
-- grain: 1행 1고객(customer_unique_id 기준)

-- 포함 컬럼
-- 최근 customer_id(대표값), customer_unique_id
-- 최근 city, 최근 state, 최근 zip_code_prefix
-- 주문 시도 횟수(order_cnt)
-- 첫주문일(first_order), 마지막주문일(last_order)
-- 배송완료 주문 횟수(delivered_order_cnt)
-- 배송완료 기준 결제금액(sales)
-- 주문시도고객(attempt_customer: 주문 1회 이상)
-- 지속관심고객(interest_customer: 주문 2회 이상)
-- 활성고객(active_customer: 배송완료 1회 이상)
-- 재구매고객(repeat_customer: 배송완료 2회 이상)

-- 주의
-- 본 테이블은 주문 활동과 연결된 고객 식별값을 기준으로 생성
-- 비구매 고객을 포함한 전체 고객 마스터는 아님
-- 그래서 전체 고객 기준 전환율이 아니라
-- 주문 고객 내 행동 전환율(배송완료율, 반복시도율, 재구매율 등) 분석에 사용

-- 대표 지역값 선정 기준
-- customer_unique_id 안에서 지역 정보가 바뀐 경우
-- 가장 최근 주문 기준의 지역값을 대표값으로 사용


-- 같은 customer_unique_id 안에서 지역값이 달라지는 경우 있는지 확인
SELECT
    customer_unique_id,
    COUNT(DISTINCT state) AS state_cnt,
    COUNT(DISTINCT clean_city) AS city_cnt,
    COUNT(DISTINCT zip_code_prefix) AS zip_cnt
FROM customers
GROUP BY customer_unique_id
HAVING COUNT(DISTINCT state) > 1
    OR COUNT(DISTINCT clean_city) > 1
    OR COUNT(DISTINCT zip_code_prefix) > 1;


-- 고객 기준 1행으로 만드는 테이블
-- 최근 주문 기준 customer_id / 지역값 + 전체 주문 요약정보를 붙임
CREATE VIEW one_customer_table AS
WITH customer_join AS (
    SELECT
        c.customer_id,
        c.customer_unique_id,
        c.state,
        c.clean_city,
        c.zip_code_prefix,
        o.purchase_timestamp
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
),
customer_rnk AS (
    SELECT
        cj.customer_id,
        cj.customer_unique_id,
        cj.state,
        cj.clean_city,
        cj.zip_code_prefix,
        ROW_NUMBER() OVER (
            PARTITION BY cj.customer_unique_id
            ORDER BY cj.purchase_timestamp DESC, cj.customer_id DESC
        ) AS rnk
    FROM customer_join cj
),
rnk_view AS (
    SELECT
        cr.customer_id,
        cr.customer_unique_id,
        cr.state,
        cr.clean_city,
        cr.zip_code_prefix
    FROM customer_rnk cr
    WHERE cr.rnk = 1
),
customer_summary AS (
    SELECT
        c.customer_unique_id,
        COUNT(o.order_id) AS order_cnt,
        MIN(o.purchase_timestamp) AS first_order,
        MAX(o.purchase_timestamp) AS last_order
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    GROUP BY c.customer_unique_id
)
SELECT
    rv.customer_id,
    rv.customer_unique_id,
    rv.state,
    rv.clean_city,
    rv.zip_code_prefix,
    cs.order_cnt,
    cs.first_order,
    cs.last_order
FROM rnk_view rv
JOIN customer_summary cs
    ON rv.customer_unique_id = cs.customer_unique_id;


-- 1행 1고객 검증
SELECT
    COUNT(*) AS row_cnt,
    (SELECT COUNT(DISTINCT customer_unique_id) FROM one_customer_table) AS unique_customer_cnt
FROM one_customer_table;


-- 실질구매(배송완료) 정보 테이블
-- 배송완료 주문만 기준으로 고객별 주문수 / 매출 집계
CREATE VIEW delivered_view AS
WITH delivered_orders AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.purchase_timestamp
    FROM orders o
    WHERE o.status = 'delivered'
),
delivered_payment AS (
    SELECT
        do.order_id,
        do.customer_id,
        SUM(op.payment_value) AS payment_value
    FROM delivered_orders do
    JOIN order_payments op
        ON do.order_id = op.order_id
    GROUP BY do.order_id, do.customer_id
),
customer_sales AS (
    SELECT
        c.customer_unique_id,
        dp.order_id,
        dp.payment_value
    FROM delivered_payment dp
    JOIN customers c
        ON dp.customer_id = c.customer_id
)
SELECT
    customer_unique_id,
    COUNT(DISTINCT order_id) AS delivered_order_cnt,
    SUM(payment_value) AS sales
FROM customer_sales
GROUP BY customer_unique_id;


-- 최종 고객 마스터 테이블
-- one_customer_table + delivered_view 결합
-- 주문시도 / 배송완료 / 재구매 여부를 한 번에 보기 위한 베이스
CREATE VIEW customer_master_table AS
SELECT
    oct.customer_id,
    oct.customer_unique_id,
    oct.state,
    oct.clean_city,
    oct.zip_code_prefix,
    oct.order_cnt,
    oct.first_order,
    oct.last_order,
    IFNULL(dv.delivered_order_cnt, 0) AS delivered_order_cnt,
    IFNULL(dv.sales, 0) AS sales,
    CASE
        WHEN IFNULL(dv.delivered_order_cnt, 0) >= 1 THEN 1
        ELSE 0
    END AS active_customer,
    CASE
        WHEN IFNULL(dv.delivered_order_cnt, 0) >= 2 THEN 1
        ELSE 0
    END AS repeat_customer,
    CASE
        WHEN oct.order_cnt >= 2 THEN 1
        ELSE 0
    END AS interest_customer
FROM one_customer_table oct
LEFT JOIN delivered_view dv
    ON oct.customer_unique_id = dv.customer_unique_id;


-- 플래그값 잘 들어갔는지 확인
SELECT DISTINCT interest_customer
FROM customer_master_table;