## MoonPhase（月齢・位相・照らされる割合）の単体テスト（client_design 8 節）。
##
## 方針: 基準の新月・半月ごとの時刻を式から組み立て、境界の値を固定する。
##       暦の参考値は「実際の新月・満月との差が 1 日以内」（F12）だけを見る。
extends GdUnitTestSuite

const EPS := 0.0001
const DAY := 86400


## 基準の新月から n 日後（小数）の UNIX 秒。
func _unix_after_days(days: float) -> int:
	return MoonPhase.REFERENCE_NEW_MOON_UNIX + int(round(days * DAY))


## 前提: 基準の新月ちょうど。期待: 月齢 0・位相 0・illumination 0。
func test_new_moon_at_reference() -> void:
	var age := MoonPhase.age_days_at(MoonPhase.REFERENCE_NEW_MOON_UNIX)
	assert_float(age).is_equal_approx(0.0, EPS)
	assert_float(MoonPhase.illumination_of_phase(MoonPhase.phase_of_age(age))).is_equal_approx(
		0.0, EPS
	)


## 前提: 基準 + 朔望月の整数倍（fposmod の折り返し）。期待: 月齢はほぼ 0（または朔望月の直前）で、照らされる割合は 0。
func test_new_moon_after_whole_cycles() -> void:
	for n in [1, 5, 100]:
		var unix := _unix_after_days(MoonPhase.SYNODIC_DAYS * n)
		var phase := MoonPhase.phase_of_age(MoonPhase.age_days_at(unix))
		assert_float(MoonPhase.illumination_of_phase(phase)).is_less(0.0001)


## 前提: 基準 + 朔望月の半分。期待: 位相 0.5・illumination 1（満月）。
func test_full_moon() -> void:
	var age := MoonPhase.age_days_at(_unix_after_days(MoonPhase.SYNODIC_DAYS / 2.0))
	var phase := MoonPhase.phase_of_age(age)
	assert_float(phase).is_equal_approx(0.5, 0.0001)
	assert_float(MoonPhase.illumination_of_phase(phase)).is_equal_approx(1.0, 0.0001)


## 前提: 位相 0.25。期待: illumination 0.5・満ちていく途中（上弦）。
func test_first_quarter() -> void:
	assert_float(MoonPhase.illumination_of_phase(0.25)).is_equal_approx(0.5, EPS)
	assert_bool(MoonPhase.is_waxing(0.25)).is_true()


## 前提: 位相 0.75。期待: illumination 0.5・欠けていく途中（下弦）。
func test_last_quarter() -> void:
	assert_float(MoonPhase.illumination_of_phase(0.75)).is_equal_approx(0.5, EPS)
	assert_bool(MoonPhase.is_waxing(0.75)).is_false()


## 前提: 位相 0.5 ちょうど。期待: 欠ける側（waxing は 0.5 未満だけ真）。
func test_waxing_boundary() -> void:
	assert_bool(MoonPhase.is_waxing(0.4999)).is_true()
	assert_bool(MoonPhase.is_waxing(0.5)).is_false()


## 前提: 月齢 7.38 日（上上弦）。期待: 位相 約 0.25。
func test_phase_of_age() -> void:
	assert_float(MoonPhase.phase_of_age(MoonPhase.SYNODIC_DAYS / 4.0)).is_equal_approx(0.25, EPS)
	# 範囲外は折り返す
	assert_float(MoonPhase.phase_of_age(MoonPhase.SYNODIC_DAYS + 1.0)).is_equal_approx(
		1.0 / MoonPhase.SYNODIC_DAYS, EPS
	)


## 前提: 位相を細かく動かす。期待: 新月→満月で単調増加、満月→新月で単調減少（連続。F9）。
func test_illumination_is_monotonic() -> void:
	var previous := MoonPhase.illumination_of_phase(0.0)
	for i in range(1, 101):
		var value := MoonPhase.illumination_of_phase(0.5 * i / 100.0)
		assert_float(value).is_greater_equal(previous)
		previous = value
	for i in range(1, 101):
		var value := MoonPhase.illumination_of_phase(0.5 + 0.5 * i / 100.0)
		assert_float(value).is_less_equal(previous)
		previous = value


## 前提: 基準より前の時刻（経過が負）。期待: 月齢は 0 以上 朔望月未満に収まる。
func test_age_before_reference_stays_in_range() -> void:
	for days in [-0.5, -1.0, -29.0, -1000.3, -20000.0]:
		var age := MoonPhase.age_days_at(_unix_after_days(days))
		assert_float(age).is_greater_equal(0.0)
		assert_float(age).is_less(MoonPhase.SYNODIC_DAYS)


## 前提: 実際の新月・満月の時刻（UTC。米国の天文台・NASA などの公表で広く知られた値。
##       権威ある暦での再確認は S5 の確認事項）。期待: 式の月齢との差が 1 日以内（F12）。
func test_ephemeris_reference_within_one_day() -> void:
	# [年, 月, 日, 時, 分, 本来の月齢（新月 0・満月 半周期）]
	var half := MoonPhase.SYNODIC_DAYS / 2.0
	var cases := [
		[2024, 4, 8, 18, 21, 0.0],
		[2024, 12, 30, 22, 27, 0.0],
		[2024, 4, 23, 23, 49, half],
		[2025, 1, 13, 22, 27, half],
	]
	for c in cases:
		var unix := Time.get_unix_time_from_datetime_dict(
			{"year": c[0], "month": c[1], "day": c[2], "hour": c[3], "minute": c[4], "second": 0}
		)
		var age := MoonPhase.age_days_at(int(unix))
		# 朔望月で折り返した差（0 付近で 29.5 側に出ても小さい差として測る）
		var diff := fposmod(age - float(c[5]) + half, MoonPhase.SYNODIC_DAYS) - half
		assert_float(absf(diff)).is_less(1.0)
