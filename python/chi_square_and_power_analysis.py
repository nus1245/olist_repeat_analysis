# -*- coding: utf-8 -*-
"""
Olist 재구매 고객 분석 - 통계 검증 & A/B 테스트 표본크기 산정

입력: cross_tab.csv (sql/14_star_category_significance_ab_baseline.sql 의
      "STAR vs one-time 첫구매 카테고리 Lift 비교" 쿼리 결과를 그대로 export)
"""

import numpy as np
import pandas as pd
from scipy.stats import chi2_contingency
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize


# ============================================================
# 1) 카이제곱 독립성 검정
# ============================================================

data = pd.read_csv("cross_tab.csv")
data_chi = data.set_index("category_group")[["star_cnt", "one_time_cnt"]]

chi2, p, dof, expected = chi2_contingency(data_chi)

print("=" * 60)
print("1) 카이제곱 독립성 검정")
print("=" * 60)
print(f"chi2 = {chi2:.2f}, dof = {dof}, p-value = {p:.6f}")


# ============================================================
# 2) 표준화잔차 + 다중비교(본페로니) 보정
#    - category_group을 index로 고정해뒀기 때문에, 정렬해도
#      값과 카테고리명이 항상 같이 움직여서 라벨이 어긋날 수 없음
# ============================================================

expected_df = pd.DataFrame(expected, index=data_chi.index, columns=data_chi.columns)
std_resid = (data_chi - expected_df) / np.sqrt(expected_df)

m = len(data_chi)  # 동시 검정하는 카테고리 수
alpha = 0.05
from scipy.stats import norm
z_uncorrected = norm.ppf(1 - alpha / 2)
z_bonferroni = norm.ppf(1 - (alpha / m) / 2)

print("\n" + "=" * 60)
print("2) 표준화잔차 & 본페로니 보정")
print("=" * 60)
print(f"단순 기준 z 임계값 = {z_uncorrected:.3f}")
print(f"본페로니 보정 z 임계값 (m={m}) = {z_bonferroni:.3f}")

result = pd.DataFrame({
    "star_resid": std_resid["star_cnt"],
    "one_time_resid": std_resid["one_time_cnt"],
    "significant_bonferroni": std_resid["star_cnt"].abs() > z_bonferroni,
}).sort_values("star_resid", ascending=False)

print(result.round(2))


# ============================================================
# 3) A/B 테스트 표본크기 산정 (정규근사, Cohen's h)
#    baseline: 전체 신규가입자 자연 재구매율 (v_rfm_base 인원 / 배송완료 고객 수, 약 3.00%)
# ============================================================

p1 = 0.03
relative_lifts = [0.10, 0.15, 0.20, 0.30]
alpha, power = 0.05, 0.80

print("\n" + "=" * 60)
print(f"3) 표본크기 산정 (baseline p1 = {p1:.4f})")
print("=" * 60)

for relative_lift in relative_lifts:
    p2 = p1 * (1 + relative_lift)
    effect_size = proportion_effectsize(p2, p1)
    n_per_group = NormalIndPower().solve_power(
        effect_size=effect_size, alpha=alpha, power=power,
        ratio=1.0, alternative="two-sided",
    )
    print(
        f"상대개선 {relative_lift*100:>3.0f}% "
        f"(p1={p1*100:.2f}% -> p2={p2*100:.2f}%): "
        f"그룹당 {np.ceil(n_per_group):>7,.0f}명 / "
        f"총 {np.ceil(n_per_group)*2:>8,.0f}명"
    )

# ------------------------------------------------------------
# 최종 채택안 (+20%)
# 대상: 신규 진입 고객 (첫 구매 이전 시점) - Home & Living 노출 유도(encouragement design)
# 배정: 랜덤 2분할, treatment/control 각 13,887명 이상
# 가설: 카테고리 노출 유도가 baseline 3.00% -> 3.60%(+20%) 이상으로
#       재구매 전환율을 유의하게 높인다
# 유의수준: α=0.05, 검정력: 80%
# (실행되지 않은 설계 제안 - 자세한 배경은 Notion 문서 참고)
# ------------------------------------------------------------
