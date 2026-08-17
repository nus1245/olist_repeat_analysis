USE olist_db;

DROP VIEW IF EXISTS cl_order_product;

-- 주문상품 기준으로 카테고리 분석할 때 쓰는 뷰
-- order_item 단위라 주문 1건이 여러 행으로 늘어날 수 있음
-- 그래서 주문 수는 DISTINCT order_id 기준으로 봐야 함
CREATE VIEW cl_order_product AS
WITH product_category AS (
    SELECT
        p.product_id,
        p.product_category,
        cne.product_category_eng,
        cne.clean_category,
        cne.category_group
    FROM products p
    JOIN category_names_english cne
        ON p.product_category = cne.product_category
)
SELECT
    oi.order_id,
    oi.product_id,
    pc.clean_category,
    pc.category_group,
    oi.price
FROM order_items oi
JOIN product_category pc
    ON oi.product_id = pc.product_id;


-- category_group별 주문 수
-- 어떤 카테고리가 많이 팔리는지 먼저 보기
SELECT
    category_group,
    COUNT(DISTINCT order_id) AS order_cnt
FROM cl_order_product
GROUP BY category_group
ORDER BY order_cnt DESC;


-- clean_category를 category_group으로 묶은 결과 확인
SELECT
    COUNT(DISTINCT clean_category) AS clean_category_cnt,
    COUNT(DISTINCT category_group) AS category_group_cnt
FROM cl_order_product;


-- 카테고리별 주문량 순위
WITH category_summary AS (
    SELECT
        category_group,
        COUNT(DISTINCT order_id) AS order_cnt
    FROM cl_order_product
    GROUP BY category_group
)
SELECT
    category_group,
    order_cnt,
    DENSE_RANK() OVER (ORDER BY order_cnt DESC) AS order_cnt_rnk
FROM category_summary
ORDER BY order_cnt DESC;


-- 카테고리별 총매출 순위
-- 주문량 순위랑 매출 순위가 비슷한지 같이 비교
WITH category_summary AS (
    SELECT
        category_group,
        SUM(price) AS sales
    FROM cl_order_product
    GROUP BY category_group
)
SELECT
    category_group,
    sales,
    DENSE_RANK() OVER (ORDER BY sales DESC) AS sales_rnk
FROM category_summary
ORDER BY sales DESC;


-- 주문당 평균매출
-- 많이 팔리는 카테고리와 객단가 높은 카테고리가 같은지 확인
WITH category_summary AS (
    SELECT
        category_group,
        COUNT(DISTINCT order_id) AS order_cnt,
        SUM(price) AS sales,
        ROUND(SUM(price) * 1.0 / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS avg_sales_per_order
    FROM cl_order_product
    GROUP BY category_group
)
SELECT
    category_group,
    order_cnt,
    sales,
    avg_sales_per_order,
    RANK() OVER (ORDER BY avg_sales_per_order DESC) AS avg_order_value_rnk,
    RANK() OVER (ORDER BY order_cnt DESC) AS order_cnt_rnk,
    RANK() OVER (ORDER BY sales DESC) AS sales_rnk
FROM category_summary
ORDER BY avg_sales_per_order DESC;


-- 상품 row 기준 평균 판매단가
-- 주문 단위 말고 상품 단위로도 가격 차이가 있는지 확인
WITH category_summary AS (
    SELECT
        category_group,
        COUNT(DISTINCT order_id) AS order_cnt,
        COUNT(*) AS item_cnt,
        SUM(price) AS sales,
        ROUND(SUM(price) * 1.0 / NULLIF(COUNT(*), 0), 2) AS avg_price_per_item_row
    FROM cl_order_product
    GROUP BY category_group
)
SELECT
    category_group,
    order_cnt,
    item_cnt,
    sales,
    avg_price_per_item_row,
    RANK() OVER (ORDER BY avg_price_per_item_row DESC) AS item_price_rnk,
    RANK() OVER (ORDER BY order_cnt DESC) AS order_cnt_rnk,
    RANK() OVER (ORDER BY sales DESC) AS sales_rnk
FROM category_summary
ORDER BY avg_price_per_item_row DESC;