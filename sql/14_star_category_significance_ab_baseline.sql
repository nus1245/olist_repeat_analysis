use olist_db;

-- ============================================================
-- Olist STAR 고객 첫구매 카테고리 분석 & A/B 테스트 baseline
--
-- 전제: 13_rfm_bcg_refactored_views.sql 의 v_rfm_scored 뷰가 먼저 생성되어 있어야 함
-- 카이제곱 독립성 검정 / 표준화잔차 / 본페로니 보정 / 표본크기 산정은
-- python/chi_square_and_power_analysis.py 에서 이어짐
--
-- 구조:
--   VIEW 1) first_order    : 배송완료 고객 전체의 첫 주문 식별 (STAR/one-time 공용)
--   VIEW 2) star_customer  : v_rfm_scored에서 STAR(Recent x High) 고객만 필터링
-- ============================================================


-- ------------------------------------------------------------
-- VIEW 1. 배송완료 고객 전체의 첫 주문 식별
--    - STAR/one-time 양쪽 카테고리 분석에서 공용으로 재사용
--    - 먼저 만들어두면 이후 쿼리마다 첫구매 식별 로직을 다시 짤 필요가 없음
-- ------------------------------------------------------------
drop view if exists first_order;

create view first_order as
select c.customer_unique_id, o.order_id, o.purchase_timestamp,
       row_number() over (partition by c.customer_unique_id order by o.purchase_timestamp) as fo_num
from orders o
join customers c on o.customer_id = c.customer_id
where o.status = 'delivered';


-- ------------------------------------------------------------
-- VIEW 2. STAR 고객 (v_rfm_scored 기준 Recent x High)
-- ------------------------------------------------------------
drop view if exists star_customer;

create view star_customer as
select *
from v_rfm_scored
where r_segment in ('ACTIVE', 'WARM')
  and m_bucket in (3, 4);


-- ------------------------------------------------------------
-- 데이터 정합성 검증
--   STAR 1,053명 중 첫구매 상품-카테고리 매칭 실패 9명,
--   카테고리 2개 이상을 동시에 담은 첫구매 18건 확인
--   -> 아래 카테고리 비교 결과는 이 손실/중복을 감안하고 해석
-- ------------------------------------------------------------
with matched as (
    select fo.customer_unique_id,
           count(distinct cne.category_group) as category_cnt
    from first_order fo
    join star_customer sc on sc.customer_unique_id = fo.customer_unique_id
    join order_items oi on fo.order_id = oi.order_id
    join products p on oi.product_id = p.product_id
    join category_names_english cne on p.product_category = cne.product_category
    where fo.fo_num = 1
    group by fo.customer_unique_id
)
select
    (select count(*) from star_customer) as star_total,
    count(*) as matched_customers,
    (select count(*) from star_customer) - count(*) as lost_customers,
    sum(case when category_cnt > 1 then 1 else 0 end) as multi_category_customers,
    sum(category_cnt) as total_category_memberships,
    sum(category_cnt) - count(*) as excess_from_multi
from matched;


-- ------------------------------------------------------------
-- STAR vs one-time 고객 첫구매 카테고리 상대비교 (Lift)
--   - "STAR에서 원래 흔한 카테고리"와 "STAR에서 유독 많이 나타나는 카테고리"를
--     구분하기 위해 one-time 고객의 첫구매 카테고리 분포를 baseline으로 비교
--   - lift = STAR 비중 ÷ one-time 비중 (1보다 크면 STAR에서 과대표집)
--   - 이 표 하나로 STAR 단독/one-time 단독 분포까지 함께 확인 가능
-- ------------------------------------------------------------
with first_category as (
    select distinct fo.customer_unique_id, cne.category_group
    from first_order fo
    join order_items oi on fo.order_id = oi.order_id
    join products p on oi.product_id = p.product_id
    join category_names_english cne on p.product_category = cne.product_category
    where fo.fo_num = 1
),
tagged as (
    select fc.customer_unique_id,
           fc.category_group,
           case
               when sc.customer_unique_id is not null then 'STAR'
               when v.order_freq = 1 then 'ONE_TIME'
               else null
           end as group_type
    from first_category fc
    join v_customer_delivered_orders v on v.customer_unique_id = fc.customer_unique_id
    left join star_customer sc on sc.customer_unique_id = fc.customer_unique_id
)
select
    category_group,
    sum(case when group_type = 'STAR' then 1 else 0 end) as star_cnt,
    round(sum(case when group_type = 'STAR' then 1 else 0 end) * 100.0
          / (select count(*) from star_customer), 1) as star_pct,
    sum(case when group_type = 'ONE_TIME' then 1 else 0 end) as one_time_cnt,
    round(sum(case when group_type = 'ONE_TIME' then 1 else 0 end) * 100.0
          / (select count(*) from v_customer_delivered_orders where order_freq = 1), 1) as one_time_pct,
    round(
        (sum(case when group_type = 'STAR' then 1 else 0 end) * 100.0 / (select count(*) from star_customer))
        / nullif(sum(case when group_type = 'ONE_TIME' then 1 else 0 end) * 100.0
              / (select count(*) from v_customer_delivered_orders where order_freq = 1), 0)
    , 2) as lift
from tagged
where group_type is not null
group by category_group
order by lift desc;

-- ↑ 이 결과(category_group, star_cnt, one_time_cnt)를
--   python/chi_square_and_power_analysis.py 의 입력값으로 그대로 사용


-- ------------------------------------------------------------
-- A/B 테스트 baseline: 배송완료 고객 중 재구매(2회+) 전환율
--   -> 약 3.00%. 신규가입자 전체를 대상으로 한 encouragement design의
--      Control 자연 baseline으로 사용 (설계 상세는 Notion 참고)
-- ------------------------------------------------------------
select
    (select count(*) from v_rfm_base) / count(distinct c.customer_unique_id) as baseline_pct
from customers c
join orders o on c.customer_id = o.customer_id
where o.status = 'delivered';
