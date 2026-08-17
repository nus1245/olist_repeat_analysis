use olist_db;

-- ============================================================
-- Olist 재구매 고객 RFM 분석 
--
-- 구조:
--   VIEW 1) v_customer_delivered_orders : 배송완료 고객별 기초 집계 (전체 고객)
--   VIEW 2) v_rfm_base                  : 위에서 재구매 고객(2회+)만 필터링
--   VIEW 3) v_rfm_scored                : R/F/M 세그먼트 라벨링까지 완료
-- 이후 페르소나 조합 / BCG 매트릭스는 v_rfm_scored 하나만 보고 조회하면 됨.
-- 기준일: 데이터셋 상 가장 최근 주문일 2018-11-12
-- ============================================================


-- ------------------------------------------------------------
-- 0. 전체 주문 현황 파악
--    총 주문 99,441건 -> 배송완료 96,478건(97%)
-- ------------------------------------------------------------
select count(*) as total_orders from orders;
select count(*) as delivered_orders from orders where status = 'delivered';


-- ------------------------------------------------------------
-- VIEW 1. 배송완료 기준 고객별 기초 집계 (전체 고객 대상)
--    - order_payments는 order_id 기준 1:N(분할결제)이라 먼저 order_id 단위로
--      집계한 뒤 orders와 조인해서 fan-out(행 뻥튀기)을 방지함
-- ------------------------------------------------------------
drop view if exists v_customer_delivered_orders;

create view v_customer_delivered_orders as
select 
    c.customer_unique_id,
    count(o.order_id) as order_freq,
    max(o.purchase_timestamp) as last_order,
    datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
    sum(op.order_payment_total) as total_sales
from customers c
join orders o on c.customer_id = o.customer_id
join (
    select order_id, sum(payment_value) as order_payment_total
    from order_payments
    group by order_id
) op on o.order_id = op.order_id
where o.status = 'delivered'
group by c.customer_unique_id;


-- 배송완료 고객 중 one-time 고객 수 확인 -> 90,556명 (배송완료 고객의 93%가 단발성)
select count(*) as one_time_customers
from v_customer_delivered_orders
where order_freq = 1;


-- ------------------------------------------------------------
-- 1회구매 vs 재구매 고객 특성 비교
--   avg_sales 161(1회) vs 309(재구매), avg_recency 313일 vs 295일
--   -> 재구매 고객이 매출/빈도는 더 높지만, 최근성은 큰 차이 없음
--      (재구매 고객도 로열티가 있다기보단, 결국 오래전 마지막 구매인 경우가 많음)
-- ------------------------------------------------------------
select 
    case when order_freq > 1 then '재구매' else '1회구매' end as customer_type,
    count(*) as customer_cnt,
    round(avg(total_sales), 0) as avg_sales,
    round(avg(order_freq), 2) as avg_order_freq,
    round(avg(last_diff_days), 0) as avg_recency
from v_customer_delivered_orders
group by customer_type;


-- ------------------------------------------------------------
-- VIEW 2. 재구매 고객(2회 이상)만 필터링한 RFM 베이스 테이블
--    -> 재주문 고객의 특성 파악을 위한 RFM 분석의 출발점 (2,801명)
-- ------------------------------------------------------------
drop view if exists v_rfm_base;

create view v_rfm_base as
select *
from v_customer_delivered_orders
where order_freq > 1;


-- ============================================================
-- 세그먼트 분할 방식 결정을 위한 분포 진단
--   -> 축마다 분포 특성이 달라서, 축별로 다른 분할법을 적용함
-- ============================================================

-- [F] 빈도 분포 확인 -> 2회 91.9% / 3회 6.5% / 4회 1% / 5회+ 0.6%
--     한쪽에 극단적으로 쏠려있어 등간격/NTILE 둘 다 부적합
--     -> 수동 구간: 2회=F_LOW(재구매 엔트리) / 3~4회=F_MID / 5회+=F_HIGH(헤비유저)
select order_freq, count(*) as cnt,
       round(count(*) * 100.0 / sum(count(*)) over (), 1) as pct
from v_rfm_base
group by order_freq
order by order_freq;


-- [R] 최근성 등간격 분포 확인 -> Q1 29% / Q2 45% / Q3 22% / Q4 4%
--     F만큼 쏠리진 않아서 등간격(4분위) 그대로 사용
--     -> Q1=ACTIVE / Q2=WARM / Q3=WATCHING / Q4=OUTED
with max_val as (select max(last_diff_days) as max_d from v_rfm_base)
select recency_bucket, cnt, round(cnt / sum(cnt) over (), 3) as pct
from (
    select 
        case
            when v.last_diff_days <= mv.max_d * 0.25 then 'Q1'
            when v.last_diff_days <= mv.max_d * 0.5  then 'Q2'
            when v.last_diff_days <= mv.max_d * 0.75 then 'Q3'
            else 'Q4'
        end as recency_bucket,
        count(*) as cnt
    from v_rfm_base v
    cross join max_val mv
    group by recency_bucket
) t
order by recency_bucket;


-- [M] 평균 vs 중앙값 비교 -> 평균 308.59 > 중앙값 225.55 (우측 꼬리 분포)
--     소수 고액 구매자가 평균을 견인하는 것으로 판단
--     -> 등간격 대신 인원 기준 균등분할이 가능한 NTILE(4) 채택
select 
    (select avg(total_sales) from v_rfm_base) as sales_avg,
    (select avg(total_sales)
     from (
         select total_sales,
                row_number() over (order by total_sales) as rn,
                count(*) over () as cnt
         from v_rfm_base
     ) t
     where rn in (floor((cnt + 1) / 2), ceil((cnt + 1) / 2))
    ) as sales_median;


-- [M] NTILE(4) 구간별 실제 범위 확인 -> 인원 701/700/700/700, 4구간 폭이 압도적으로 넓음(361~7571)
--     -> 1=LIGHT / 2=STANDARD / 3=OVER / 4=HEAVY
select m_bucket, count(*) as cnt,
       min(total_sales) as min_sales,
       max(total_sales) as max_sales,
       round(avg(total_sales), 0) as avg_sales
from (
    select total_sales, ntile(4) over (order by total_sales asc) as m_bucket
    from v_rfm_base
) t
group by m_bucket
order by m_bucket;


-- ------------------------------------------------------------
-- VIEW 3. R/F/M 세그먼트 라벨링 완료 테이블
--    이후 모든 분석(페르소나, BCG 매트릭스)은 이 뷰 하나로 처리
-- ------------------------------------------------------------
drop view if exists v_rfm_scored;

create view v_rfm_scored as
with max_val as (
    select max(last_diff_days) as max_d from v_rfm_base
),
bucketed as (
    select v.*,
           mv.max_d,
           ntile(4) over (order by v.total_sales asc) as m_bucket
    from v_rfm_base v
    cross join max_val mv
)
select
    customer_unique_id,
    last_order,
    last_diff_days,
    order_freq,
    total_sales,
    case
        when last_diff_days <= max_d * 0.25 then 'ACTIVE'
        when last_diff_days <= max_d * 0.5  then 'WARM'
        when last_diff_days <= max_d * 0.75 then 'WATCHING'
        else 'OUTED'
    end as r_segment,
    case
        when order_freq = 2 then 'F_LOW'
        when order_freq between 3 and 4 then 'F_MID'
        else 'F_HIGH'
    end as f_segment,
    m_bucket,
    case m_bucket
        when 1 then 'LIGHT'
        when 2 then 'STANDARD'
        when 3 then 'OVER'
        when 4 then 'HEAVY'
    end as m_segment
from bucketed;


-- ------------------------------------------------------------
-- 페르소나별 분포 확인 (4 x 3 x 4 = 48 조합 중 36개 조합 실관측)
--   -> WARM-F_LOW 계열이 41.6%로 압도적 다수 (재구매 고객의 baseline)
--   -> ACTIVE/WARM-F_HIGH-HEAVY(진성 챔피언)는 17명(0.6%)뿐
-- ------------------------------------------------------------
select concat(r_segment, '-', f_segment, '-', m_segment) as persona,
       count(*) as cnt
from v_rfm_scored
group by persona
order by cnt desc;


-- ------------------------------------------------------------
-- BCG 매트릭스 착안 세그먼트 (R x M 2축)
--   - F는 91.9%가 2회에 쏠린 사실상 이진변수라 주축에서 제외, 보조지표로만 확인
--   - R 4분위 -> Recent(ACTIVE+WARM) / NotRecent(WATCHING+OUTED) 로 병합 (중앙값 기준 2분할)
--   - M 4분위 -> High(OVER+HEAVY) / Low(LIGHT+STANDARD) 로 병합 (median split)
--
--   STAR          : Recent + High  -> 최근에도 활발 + 고액, one-time 전환의 목표 프로필
--   QUESTION_MARK : Recent + Low   -> 최근성은 있으나 아직 저액, 업셀/크로스셀 대상
--   CASH_COW      : NotRecent + High -> 과거 큰손, 최근엔 조용함 -> 윈백(재활성화) 대상
--   DOG           : NotRecent + Low  -> 최근성/가치 둘 다 낮음, 우선순위 낮음
-- ------------------------------------------------------------
select
    case
        when r_segment in ('ACTIVE','WARM')    and m_bucket in (3,4) then 'STAR'
        when r_segment in ('ACTIVE','WARM')    and m_bucket in (1,2) then 'QUESTION_MARK'
        when r_segment in ('WATCHING','OUTED') and m_bucket in (3,4) then 'CASH_COW'
        else 'DOG'
    end as bcg_quadrant,
    count(*) as cnt,
    round(avg(order_freq), 2) as avg_f   -- F는 여기서 보조지표로만 확인
from v_rfm_scored
group by bcg_quadrant
order by cnt desc;