"""
Olist 재구매 고객 분석 - 통계 검증 & A/B 테스트 표본크기 산정

입력: sql/12_RFM_refactored.sql 의 "STAR vs one-time 첫구매 카테고리" 쿼리 결과
      (category_group, star_cnt, one_time_cnt)

이 스크립트는 세 단계로 구성됩니다:
  1) 카이제곱 독립성 검정 - 카테고리와 재구매 그룹(STAR/ONE_TIME)이 무관한지 검정
  2) 표준화잔차 + 본페로니 다중비교 보정 - 어느 카테고리가 유의성을 견인했는지 확인
  3) 정규근사 표본크기 산정 (Cohen's h) - A/B 테스트에 필요한 표본 수 계산
"""

import numpy as np
import pandas as pd
from scipy.stats import chi2_contingency, norm
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import proportion_effectsize


# ============================================================
# 1) 카이제곱 독립성 검정
# ============================================================

# SQL 쿼리 결과를 그대로 옮긴 값 (sql/12_RFM_refactored.sql 마지막 쿼리 참고)
data = {
    "category_group": [
        "Home & Living", "Sports & Leisure", "Others", "Fashion & Accessories",
        "Beauty & Health", "Auto & Industrial", "Electronics & Digital",
        "Food & Beverage", "Books & Media", "Baby & Kids",
    ],
    "star_cnt": [383, 189, 24, 95, 113, 56, 146, 8, 29, 19],
    "one_time_cnt": [25392, 13987, 2031, 8277, 11089, 5521, 15993, 880, 3831, 2672],
}
df = pd.DataFrame(data).set_index("category_group")

contingency = df[["star_cnt", "one_time_cnt"]]
chi2, p, dof, expected = chi2_contingency(contingency)

print("=" * 60)
print("1) 카이제곱 독립성 검정")
print("=" * 60)
print(f"chi2 = {chi2:.2f}, dof = {dof}, p-value = {p:.6f}")


# ============================================================
# 2) 표준화잔차 + 다중비교(본페로니) 보정
# ============================================================

expected_df = pd.DataFrame(expected, index=contingency.index, columns=contingency.columns)
std_resid = (contingency - expected_df) / np.sqrt(expected_df)

m = len(df)  # 동시 검정하는 카테고리 수
alpha = 0.05
z_uncorrected = norm.ppf(1 - alpha / 2)
z_bonferroni = norm.ppf(1 - (alpha / m) / 2)

print("\n" + "=" * 60)
print("2) 표준화잔차 & 본페로니 보정")
print("=" * 60)
print(f"단순 기준 z 임계값 = {z_uncorrected:.3f}")
print(f"본페로니 보정 z 임계값 (m={m}) = {z_bonferroni:.3f}")

result = pd.DataFrame({
    "star_resid": std_resid["star_cnt"],
    "significant_uncorrected": std_resid["star_cnt"].abs() > z_uncorrected,
    "significant_bonferroni": std_resid["star_cnt"].abs() > z_bonferroni,
}).sort_values("star_resid", ascending=False)

print(result.round(2))


# ============================================================
# 3) A/B 테스트 표본크기 산정 (정규근사, Cohen's h)
# ============================================================

# baseline: 전체 신규가입자 자연 재구매율 (2,801 / 93,357)
p1 = 2801 / 93357

alpha, power = 0.05, 0.80

print("\n" + "=" * 60)
print("3) 표본크기 산정 (baseline p1 = {:.4f})".format(p1))
print("=" * 60)

for relative_lift in [0.10, 0.15, 0.20, 0.30]:
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
