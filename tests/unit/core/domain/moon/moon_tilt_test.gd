## MoonTilt（月の傾きの近似。client_design 3-3 節）の単体テスト。
##
## 確認例（北緯 35 度の近似。式の符号の検証。許容幅つき）:
##   上弦が南中する 18 時は境界がほぼ上下（tilt ≈ 0）で右が光る / 同じ上弦の 21 時は右が下へ傾く /
##   宵の三日月（19 時）は右下を向く / 明け方の下弦（6 時）は南中で tilt ≈ 0（左が光る）。
extends GdUnitTestSuite

## 許容幅（度）。式の符号と大きさの検証用
const TOL_DEG := 3.0


func _tilt_deg(phase: float, hours: float, southern: bool, lit_on_right: bool) -> float:
	return rad_to_deg(MoonTilt.tilt_radians(phase, hours, southern, lit_on_right))


## 前提: 上弦（位相 0.25）の 18 時（月が南中）。期待: 傾きほぼ 0（境界は上下）。
func test_first_quarter_at_meridian_is_upright() -> void:
	assert_float(_tilt_deg(0.25, 18.0, false, true)).is_equal_approx(0.0, TOL_DEG)


## 前提: 上弦の 21 時（月は南西の空）。期待: 右が下向きに傾く（負。約 -45 度）。
func test_first_quarter_evening_tilts_right_side_down() -> void:
	var tilt := _tilt_deg(0.25, 21.0, false, true)
	assert_float(tilt).is_between(-60.0, -30.0)


## 前提: 上弦の 15 時（月は南東の空、昼間）。期待: 21 時と逆の向き（正）に傾く。
func test_first_quarter_afternoon_tilts_the_other_way() -> void:
	assert_float(_tilt_deg(0.25, 15.0, false, true)).is_greater(30.0)


## 前提: 新月後 3 日（位相 0.1015）の 19 時の宵の三日月。期待: 明るい縁が右下を向く（負）。
func test_evening_crescent_points_lower_right() -> void:
	var tilt := _tilt_deg(3.0 / MoonPhase.SYNODIC_DAYS, 19.0, false, true)
	assert_float(tilt).is_between(-80.0, -10.0)


## 前提: 欠けていく下弦（位相 0.75）の 6 時（月が南中）。期待: 傾きほぼ 0（左が光る側の基準で）。
func test_last_quarter_at_dawn_meridian_is_upright() -> void:
	assert_float(_tilt_deg(0.75, 6.0, false, false)).is_equal_approx(0.0, TOL_DEG)


## 前提: 欠けていく下弦（位相 0.75）の 3 時（H_月 = -45 度。月は南東の空）、基準は左が光る。
## 期待: 手計算で約 +45 度（左が下がる向き。左基準の符号の取り違えを拾う）。
func test_last_quarter_before_dawn_tilts_left_side_down() -> void:
	assert_float(_tilt_deg(0.75, 3.0, false, false)).is_equal_approx(45.3, TOL_DEG)


## 前提: 南半球（緯度 -35 度）の上弦 21 時（基準は左が光る）。期待: 北半球の同じ時刻と傾きが同じ大きさで逆向き
## （緯度の符号が変わると、画面の上下の傾きが鏡映になる）。光る側の左右の反転は lit_on_right（基準）で表す。
func test_southern_hemisphere_mirrors_tilt() -> void:
	var north := _tilt_deg(0.25, 21.0, false, true)
	var south := _tilt_deg(0.25, 21.0, true, false)
	assert_float(south).is_equal_approx(-north, 0.5)


## 前提: 満月・新月（位相 0・0.5）と全時刻。期待: 値が有限で -π〜π に収まる（破綻しない）。
func test_new_and_full_moon_do_not_break() -> void:
	for phase in [0.0, 0.5, 0.999, 0.001]:
		for hours in [0.0, 6.0, 12.0, 18.0, 23.9]:
			for southern in [false, true]:
				var t := MoonTilt.tilt_radians(phase, hours, southern, true)
				assert_bool(is_finite(t)).is_true()
				assert_float(t).is_between(-PI - 0.0001, PI + 0.0001)


## 前提: 位相が上弦から満月へ細かく動く。期待: 傾きが連続（隣り合う値の差が小さい）。
func test_tilt_is_continuous_in_phase() -> void:
	var prev := MoonTilt.tilt_radians(0.3, 20.0, false, true)
	for i in range(1, 100):
		var phase := 0.3 + 0.2 * i / 100.0
		var t := MoonTilt.tilt_radians(phase, 20.0, false, true)
		assert_float(absf(angle_difference(prev, t))).is_less(0.1)
		prev = t


## 前提: 満ちていく側と欠けていく側の境（満月）をまたぐ。期待: 基準の向きが反転しても傾きは連続。
func test_tilt_is_continuous_across_full_moon() -> void:
	var before := MoonTilt.tilt_radians(0.4999, 20.0, false, true)
	var after := MoonTilt.tilt_radians(0.5001, 20.0, false, false)
	assert_float(absf(angle_difference(before, after))).is_less(0.05)


## 前提: UNIX 秒とタイムゾーンの差。期待: 現地の太陽時 = UTC + 差（0〜24 に折り返す）。
func test_local_solar_hours() -> void:
	# 1970-01-01 00:00 UTC + JST(540 分) = 9 時
	assert_float(MoonTilt.local_solar_hours(0, 540)).is_equal_approx(9.0, 0.0001)
	# 西（-300 分）で日付をまたぐ: 02:00 UTC - 5h = 21 時
	assert_float(MoonTilt.local_solar_hours(2 * 3600, -300)).is_equal_approx(21.0, 0.0001)
