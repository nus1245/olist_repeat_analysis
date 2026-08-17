# Olist 고객 분석: 매출 구조 진단부터 재구매 고객 RFM·BCG·A/B 테스트 설계까지

공개 이커머스 데이터셋(Olist)을 SQL로 분석한 전체 파이프라인입니다. 매출 퍼널·로렌츠 곡선 분석으로 시작해, 재구매 고객을 RFM·BCG 매트릭스로 세분화하고 통계 검정으로 검증된 타겟 카테고리를 골라 A/B 테스트 설계까지 이어집니다.

전체 분석 서사와 각 단계의 판단 근거는 Notion 문서에 정리했습니다:
**[Olist 재구매 고객 분석 & A/B 테스트 설계 (Notion)](https://app.notion.com/p/3be22de4a409819dac7cf589b891adea)**

## 구성

| 파일 | 내용 |
|---|---|
| `01_data_import.sql` | Olist 원본 CSV 8종 적재 |
| `02_data_cleaning.sql` | 카테고리 71개 → 10개 그룹 축소, 지역명 정제 |
| `03_base_table.sql` | 1행 1고객 기준 마스터 테이블 설계 (`customer_master_table`) |
| `04_customer_funnel_analysis.sql` | 주문시도 → 배송완료 → 재주문시도 → 재구매 퍼널, 병목 구간 발견 |
| `05_repeat_customer_behavior_analysis.sql` | 재구매 고객의 회차별 주문 간격·매출·카테고리 흐름 |
| `06_customer_value_segmentation.sql` | **로렌츠 곡선** 기반 Core/Mid/Low 세그먼트 |
| `07_customer_segment_behavior_analysis.sql` | 세그먼트별 카테고리·주문횟수 행동 차이 검증 |
| `08_category_sales_analysis.sql` | 카테고리별 주문량 vs 객단가 순위 역전 분석 |
| `09_core_customer_region_analysis.sql` | 핵심 고객 비중이 높은 지역 분석 |
| `10_first_purchase_category_analysis.sql` | 첫 구매 카테고리 분포 |
| `11_sales_trend_payment_analysis.sql` | 월별 매출 추이, 결제수단별 매출 구성 |
| `12_rfm_exploration.sql` | **[비즈니스 분석]** 재구매 고객 RFM 세분화 탐색 — R/F/M 축별 분포 진단, 세그먼트 정의, 페르소나 조합 |
| `13_rfm_bcg_refactored_views.sql` | 뷰 3단계로 리팩토링(`v_customer_delivered_orders`→`v_rfm_base`→`v_rfm_scored`), BCG 매트릭스(STAR/CASH_COW/QUESTION_MARK/DOG) |
| `14_star_category_significance_ab_baseline.sql` | STAR 고객 첫구매 카테고리 Lift 비교, one-time 고객 대비 상대비교, A/B 테스트 baseline 산정 |

`python/chi_square_and_power_analysis.py`에서 14번 쿼리 결과를 받아 카이제곱 독립성 검정·표준화잔차·본페로니 다중비교 보정·표본크기 산정까지 이어집니다.

## 핵심 결과

| 단계 | 결과 |
|---|---|
| 퍼널 분석 | 핵심 병목은 첫구매→재주문시도 구간 (전환율 3.12%) |
| 로렌츠 분석 | 상위 29.32% 고객이 매출의 63.95% 차지 |
| RFM·BCG 세분화 | 재구매 고객 2,801명 중 STAR(최근성+고액) 1,053명(37.6%) — one-time 고객 전환의 목표 프로필 |
| 카이제곱 검정 | χ²=50.68, df=9, p<0.000001 — Home & Living만 본페로니 보정 후에도 유의 |
| A/B 테스트 설계 | baseline 3.00% → 목표 3.60%(+20%), 그룹당 13,887명 필요 (α=0.05, power=0.80) |

## 실행 환경

- MySQL 8.0 (CTE, 윈도우 함수, `NTILE`, `WITH ROLLUP`)
- Python 3, `scipy`, `statsmodels`, `pandas`, `numpy`

```bash
pip install scipy statsmodels pandas numpy
```

## 데이터 출처

[Olist Brazilian E-Commerce Public Dataset (Kaggle)](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)

---

이 A/B 테스트는 실제로 실행된 것이 아니라, 정적 과거 데이터셋을 근거로 한 **설계 제안**입니다. 실제 실행·SRM/공변량 균형 검증 단계는 [King Coffee A/B 테스트 프로젝트](https://github.com/nus1245/a-b-test-simulation)에서 별도로 다뤘습니다.
