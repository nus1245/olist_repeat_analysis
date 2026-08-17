use olist_db;


## 총 주문 처리 수 99441건 -> 주문완료 96478건(97%) -> one-time 주문 고객 90556건(93%가 단발성 고객)
select sum(t.cnt) from (select count(*) cnt from orders o join customers c on
o.customer_id = c.customer_id
where o.status='delivered'
GROUP BY c.customer_unique_id
HAVING count(o.order_id) < 2) t
;

#재주문과 one-time 고객 빈도, 평균 매출, 빈도, 최근 주문 (rfm)  (데이터셋 상 가장 최근일 2018-11-12일 기준)
with customer_orders as (
    select c.customer_unique_id,
           count(o.order_id) as order_cnt,
           max(o.purchase_timestamp) as last_order,
           sum(op.order_payment_total) as total_sales
    from customers c
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
)
select 
    case when order_cnt > 1 then '재구매' else '1회구매' end as customer_type,
    count(*) as customer_cnt,
    round(avg(total_sales), 0) as avg_sales,
    round(avg(order_cnt), 2) as avg_order_freq,
    round(avg(datediff('2018-11-12', last_order)), 0) as avg_recency
from customer_orders
group by customer_type;

## 재주문 고객의 특성파악 먼저 분석함  대표적인 세분화로 RFM 방식으로 세분화
with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           max(o.purchase_timestamp) as last_order,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
           count(o.order_id) as order_freq,
           sum(op.order_payment_total) as total_sales,
           sum(op.order_payment_total) /count(o.order_id) as per_sales
    from customers c 
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
)
select rt.*
from rfm_table rt 
join re_filter rf on rt.customer_unique_id = rf.customer_unique_id
order by rt.last_diff_days asc ;

## 고객 세분화 흐름 
## rfm 기반 페르소나 유형 구분, 이후 총 총점 내 페르소나 유형 확인
## f(빈도) 재구매이상 고객 분포 확인 2회 91.9% 3회 6.5% 4회 1%
## 2회 f-low(재구매 엔트리) 3,4회 f-mid 5회 이상 f-high(헤비 유저) 
with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           max(o.purchase_timestamp) as last_order,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
           count(o.order_id) as order_freq,
           sum(op.order_payment_total) as total_sales,
           sum(op.order_payment_total) /count(o.order_id) as per_sales
    from customers c 
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
), rfm_final as(
select rt.*
from rfm_table rt 
join re_filter rf on rt.customer_unique_id = rf.customer_unique_id
order by rt.last_diff_days asc)
select order_freq, count(*) as cnt,
       round(count(*) * 100.0 / sum(count(*)) over (), 1) as pct
from rfm_final
group by order_freq
order by order_freq;



### recently(최근 분포 확인)
## 등간격 분포 확인
#Q1 29%, Q2 45% ,Q3 22% ,Q4 0.04% (장기 이탈자 외 균등 분포)
#Q1 ACTIVE , Q2 WARM , Q3 WATCHING, Q4 OUTED
with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
),
rfm_final as (
    select rt.*
    from rfm_table rt 
    join re_filter rf on rt.customer_unique_id = rf.customer_unique_id
),
max_val as (
    select max(last_diff_days) as max_d from rfm_final
)
select recency_bucket,cnt,
cnt/sum(cnt) over() pct
from (select 
    case
        when rfm_final.last_diff_days <= max_val.max_d * 0.25 then 'Q1'
        when rfm_final.last_diff_days <= max_val.max_d * 0.5  then 'Q2'
        when rfm_final.last_diff_days <= max_val.max_d * 0.75 then 'Q3'
        else 'Q4'
    end as recency_bucket,
    count(*) as cnt
from rfm_final
cross join max_val
group by recency_bucket
order by recency_bucket) t;
      

## M(충성도) 구체화 
## 1 재구매 고객들의 평균 지출액과 중앙값을 비교하여 소수 매출 쏠림 현상 파악
## 평균 지출: 308 중앙값 :225 평균 > 중앙값 보다 많으므로 소수 매출이 비중 매출 견인 현상 의심,
## 등간격 분할 시 상위 아웃라이어로 구간 경계 왜곡을 방지하기 위해 인원기준 균등 분할인 ntitle로 구분
# 1 : light, 2 :standrd ,3:'over', 4:'heavy'
with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           max(o.purchase_timestamp) as last_order,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
           count(o.order_id) as order_freq,
           sum(op.order_payment_total) as total_sales,
           sum(op.order_payment_total) /count(o.order_id) as per_sales
    from customers c 
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
), rfm_final as(
select rt.*
from rfm_table rt 
join re_filter rf on rt.customer_unique_id = rf.customer_unique_id)
select 
    (select avg(total_sales) from rfm_final) as sales_avg,
    (select avg(total_sales) from (
         select total_sales,row_number() over (order by total_sales) as rn,count(*) over () as cnt
         from rfm_final) t
     where rn in (floor((cnt+1)/2), ceil((cnt+1)/2))
    ) as sales_median;
    
with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           max(o.purchase_timestamp) as last_order,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
           count(o.order_id) as order_freq,
           sum(op.order_payment_total) as total_sales,
           sum(op.order_payment_total) /count(o.order_id) as per_sales
    from customers c 
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
), rfm_final as(
select rt.*
from rfm_table rt 
join re_filter rf on rt.customer_unique_id = rf.customer_unique_id)
select m_bucket,
       count(*) as cnt,
       min(total_sales) as min_sales,
       max(total_sales) as max_sales,
       round(avg(total_sales), 0) as avg_sales
from (
    select total_sales,
           ntile(4) over (order by total_sales asc) as m_bucket
    from rfm_final
) t
group by m_bucket
order by m_bucket;




### rfm 세분 규칙에 따른 최종 세그먼츠 테이블
with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
           count(o.order_id) as order_freq,
           sum(op.order_payment_total) as total_sales
    from customers c 
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
),
rfm_final as (
    select rt.*
    from rfm_table rt 
    join re_filter rf on rt.customer_unique_id = rf.customer_unique_id
),
max_val as (
    select max(last_diff_days) as max_d from rfm_final
),
scored as (
    select rfm_final.customer_unique_id,
           rfm_final.last_diff_days,
           rfm_final.order_freq,
           rfm_final.total_sales,
           case
               when rfm_final.last_diff_days <= max_val.max_d * 0.25 then 'ACTIVE'
               when rfm_final.last_diff_days <= max_val.max_d * 0.5  then 'WARM'
               when rfm_final.last_diff_days <= max_val.max_d * 0.75 then 'WATCHING'
               else 'OUTED'
           end as r_segment,
           case
               when rfm_final.order_freq = 2 then 'F_LOW'
               when rfm_final.order_freq between 3 and 4 then 'F_MID'
               else 'F_HIGH'
           end as f_segment,
           ntile(4) over (order by rfm_final.total_sales asc) as m_bucket
    from rfm_final
    cross join max_val
)
select *,
CONCAT(R_SEGMENT,"-",F_SEGMENT,"-",case m_bucket 
            when 1 then 'LIGHT' 
            when 2 then 'STANDARD' 
            when 3 then 'OVER' 
            when 4 then 'HEAVY'END ) AS PERSONA
from scored;


### 페르소나별 분포 확인하기 (4*3*4 = 48 그룹 중 36군 페르소나 관측)
with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
           count(o.order_id) as order_freq,
           sum(op.order_payment_total) as total_sales
    from customers c 
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
),
rfm_final as (
    select rt.*
    from rfm_table rt 
    join re_filter rf on rt.customer_unique_id = rf.customer_unique_id
),
max_val as (
    select max(last_diff_days) as max_d from rfm_final
),
scored as (
    select rfm_final.customer_unique_id,
           rfm_final.last_diff_days,
           rfm_final.order_freq,
           rfm_final.total_sales,
           case
               when rfm_final.last_diff_days <= max_val.max_d * 0.25 then 'ACTIVE'
               when rfm_final.last_diff_days <= max_val.max_d * 0.5  then 'WARM'
               when rfm_final.last_diff_days <= max_val.max_d * 0.75 then 'WATCHING'
               else 'OUTED'
           end as r_segment,
           case
               when rfm_final.order_freq = 2 then 'F_LOW'
               when rfm_final.order_freq between 3 and 4 then 'F_MID'
               else 'F_HIGH'
           end as f_segment,
           ntile(4) over (order by rfm_final.total_sales asc) as m_bucket
    from rfm_final
    cross join max_val
),PRESONA_TABLE AS(
select *,
CONCAT(R_SEGMENT,"-",F_SEGMENT,"-",case m_bucket 
            when 1 then 'LIGHT' 
            when 2 then 'STANDARD' 
            when 3 then 'OVER' 
            when 4 then 'HEAVY'END ) AS PERSONA
from scored)
SELECT PERSONA,COUNT(*) CNT
FROM PRESONA_TABLE
GROUP BY PERSONA
ORDER BY CNT DESC;


### BCG 메트릭스 착안 : STAR,DOG,CASH_COW,? 구분
## RFM 중 F(빈도) 91.9% 2회 구매로 쏠림으로 빈도축은 보조지표로 활용하고, R*M 축으로 BCG 메트릭스 구분
## 현재 R,M의 4가지 구분을 2가지로 병합하여 LOW/HIGH , RECENT/NON_RECENT 집단으로 나눔
# STAR : RECENT 및 HIGH
# CASH_COW : NON_RECENT 및 HIGH
# ?: RECENT 및 LOW
# DOG : NON_RECENT 및 LOW


with re_filter as (
    select customer_unique_id
    from customers c 
    join orders o on c.customer_id = o.customer_id
    where o.status = 'delivered'
    group by c.customer_unique_id
    having count(o.order_id) > 1
),
rfm_table as (
    select c.customer_unique_id,
           datediff('2018-11-12', max(o.purchase_timestamp)) as last_diff_days,
           count(o.order_id) as order_freq,
           sum(op.order_payment_total) as total_sales
    from customers c 
    join orders o on c.customer_id = o.customer_id
    join (
        select order_id, sum(payment_value) as order_payment_total
        from order_payments
        group by order_id
    ) op on o.order_id = op.order_id
    where o.status = 'delivered'
    group by c.customer_unique_id
),
rfm_final as (
    select rt.*
    from rfm_table rt 
    join re_filter rf on rt.customer_unique_id = rf.customer_unique_id
),
max_val as (
    select max(last_diff_days) as max_d from rfm_final
),
scored as (
    select rfm_final.customer_unique_id,
           rfm_final.last_diff_days,
           rfm_final.order_freq,
           rfm_final.total_sales,
           case
               when rfm_final.last_diff_days <= max_val.max_d * 0.25 then 'ACTIVE'
               when rfm_final.last_diff_days <= max_val.max_d * 0.5  then 'WARM'
               when rfm_final.last_diff_days <= max_val.max_d * 0.75 then 'WATCHING'
               else 'OUTED'
           end as r_segment,
           case
               when rfm_final.order_freq = 2 then 'F_LOW'
               when rfm_final.order_freq between 3 and 4 then 'F_MID'
               else 'F_HIGH'
           end as f_segment,
           ntile(4) over (order by rfm_final.total_sales asc) as m_bucket
    from rfm_final
    cross join max_val
    ),
    bcg_matrix as (
    select customer_unique_id,
           case when r_segment in ('ACTIVE','WARM') then 'Recent' else 'NotRecent' end as r_group,
           case when m_bucket in (3,4) then 'High' else 'Low' end as m_group,
           f_segment
    from scored
)
select 
    case
        when r_group='Recent'    and m_group='High' then 'STAR'
        when r_group='Recent'    and m_group='Low'  then 'QUESTION_MARK'
        when r_group='NotRecent' and m_group='High' then 'CASH_COW'
        else 'DOG'
    end as bcg_quadrant,
    count(*) as cnt
from bcg_matrix
group by bcg_quadrant
order by cnt desc;