## 月齢・位相・照らされている割合を求める純関数（background-moon-phase client_design 3 節。F2・F9・F12）。
##
## 目的: 「UNIX 秒 → 月がどれだけ満ちているか」を、状態を持たない静的関数だけで計算する。
##       描画（シェーダー）や UseCase はこの値を使うだけで、式はここに 1 か所だけ置く。
## 流れ: UNIX 秒 → age_days_at（月齢・日）→ phase_of_age（位相 0〜1）→ illumination_of_phase（照らされる割合）
## 方式: 平均朔望月による近似。基準の新月からの経過日数を朔望月で割った余りを月齢とする。
##       実際の新月・満月から最大で半日強（目安 0.6 日前後）ずれるが、要件 F12 の「約 1 日以内」に収まる。
##       天文学的な厳密さは対象外（精度が要るときは周期項を足す。後の改善）。
## 注意: `Time` や `OS` を使わない（core/domain は RefCounted だけ。単体テストを軽くするため）。
class_name MoonPhase
extends RefCounted

## 朔望月の平均（日）。新月から次の新月までの平均の長さ
const SYNODIC_DAYS := 29.530588853

## 基準の新月（UNIX 秒）。2000-01-06 18:14 UTC。一般に平均の新月の基準として使われる値
const REFERENCE_NEW_MOON_UNIX := 947182440

## 1 日の秒数
const SECONDS_PER_DAY := 86400.0


## UNIX 秒（UTC）の月齢（日）。新月が 0 で、0 以上 SYNODIC_DAYS 未満。秒まで反映した連続値（F12）。
## fposmod を使う理由: 基準より前の時刻（経過が負）でも 0〜朔望月に折り返すため。
static func age_days_at(unix: int) -> float:
	var elapsed_days := float(unix - REFERENCE_NEW_MOON_UNIX) / SECONDS_PER_DAY
	return fposmod(elapsed_days, SYNODIC_DAYS)


## 月齢（日）から位相（0〜1）を求める。0 と 1 が新月、0.5 が満月、0.25 が上弦、0.75 が下弦。
## 範囲外の月齢が来ても 0〜1 に折り返す（e2e の指定値の端での丸め誤差に備える）。
static func phase_of_age(age_days: float) -> float:
	return fposmod(age_days, SYNODIC_DAYS) / SYNODIC_DAYS


## 位相から、照らされている割合（0〜1）を求める。(1 - cos(2π・位相)) / 2。
## 新月 0、上弦・下弦 0.5、満月 1。位相に対して連続（F9）。
## 光のにじみ・霧の強さと、月の見た目の明るい面積の両方がこの値に従う。
static func illumination_of_phase(phase: float) -> float:
	return (1.0 - cos(TAU * phase)) / 2.0


## 満ちていく途中か（新月 → 満月 = 位相 0.5 未満）。欠けていく途中は 0.5 以上（満月ちょうどは欠ける側）。
static func is_waxing(phase: float) -> bool:
	return phase < 0.5
