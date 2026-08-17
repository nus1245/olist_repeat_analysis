USE olist_db;

-- 배송완료 기준으로 고객의 첫 구매 주문만 따로 잡아서 보기
-- 첫 주문에서 어떤 카테고리로 들어오는지 확인하려는 목적

-- 고객별 첫 배송완료 주문의 상품 테이블
-- 첫 주문에 상품이 여러 개면 여러 행이 생김
WITH order_deli AS (
    SELECT
        o.order_id,
        c.customer_id,
        c.customer_unique_id,
        o.purchase_timestamp
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE o.status = 'delivered'
),
unique_first AS (
    SELECT
        od.order_id,
        od.customer_id,
        od.customer_unique_id,
        od.purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY od.customer_unique_id
            ORDER BY od.purchase_timestamp, od.order_id
        ) AS rn
    FROM order_deli od
),
customer_first_order AS (
    SELECT
        uf.order_id,
        uf.customer_id,
        uf.customer_unique_id,
        uf.purchase_timestamp AS first_day
    FROM unique_first uf
    WHERE uf.rn = 1
),
customer_first_delivered_order_items AS (
    SELECT
        cfo.customer_unique_id,
        cfo.first_day,
        oi.order_id,
        oi.product_id,
        p.product_category,
        cne.clean_category,
        cne.category_group
    FROM customer_first_order cfo
    JOIN order_items oi
        ON cfo.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    JOIN category_names_english cne
        ON p.product_category = cne.product_category
)
SELECT *
FROM customer_first_delivered_order_items;


-- 첫 배송완료 주문에서 상품 1개만 산 고객만 따로 보기
-- 여러 개 같이 산 경우보다 첫 진입 카테고리를 해석하기 편해서 따로 분리
WITH order_deli AS (
    SELECT
        o.order_id,
        c.customer_id,
        c.customer_unique_id,
        o.purchase_timestamp
    FROM customers c
    JOIN orders o
        ON c.customer_id = o.customer_id
    WHERE o.status = 'delivered'
),
unique_first AS (
    SELECT
        od.order_id,
        od.customer_id,
        od.customer_unique_id,
        od.purchase_timestamp,
        ROW_NUMBER() OVER (
            PARTITION BY od.customer_unique_id
            ORDER BY od.purchase_timestamp, od.order_id
        ) AS rn
    FROM order_deli od
),
customer_first_order AS (
    SELECT
        uf.order_id,
        uf.customer_id,
        uf.customer_unique_id,
        uf.purchase_timestamp AS first_day
    FROM unique_first uf
    WHERE uf.rn = 1
),
customer_first_delivered_order_items AS (
    SELECT
        cfo.customer_unique_id,
        cfo.first_day,
        oi.order_id,
        oi.product_id,
        p.product_category,
        cne.clean_category,
        cne.category_group
    FROM customer_first_order cfo
    JOIN order_items oi
        ON cfo.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    JOIN category_names_english cne
        ON p.product_category = cne.product_category
),
one_item_customer AS (
    SELECT
        customer_unique_id,
        first_day,
        COUNT(product_id) AS product_cnt
    FROM customer_first_delivered_order_items
    GROUP BY customer_unique_id, first_day
    HAVING COUNT(product_id) = 1
),
one_item_category AS (
    SELECT
        cfd.customer_unique_id,
        cfd.clean_category,
        cfd.category_group
    FROM customer_first_delivered_order_items cfd
    JOIN one_item_customer oic
        ON cfd.customer_unique_id = oic.customer_unique_id
       AND cfd.first_day = oic.first_day
)
SELECT
    category_group,
    COUNT(*) AS cnt,
    ROUND(COUNT(*) * 1.0 / SUM(COUNT(*)) OVER (), 4) AS ratio
FROM one_item_category
GROUP BY category_group
ORDER BY cnt DESC;