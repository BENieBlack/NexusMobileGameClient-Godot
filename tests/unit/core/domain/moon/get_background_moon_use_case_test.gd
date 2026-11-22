## GetBackgroundMoonUseCase の単体テスト（client_design 8 節）。
##
## 方針: Clock・TimeZoneSource を偽の実装に差し替え、時刻とタイムゾーンを固定して値を検査する。
extends GdUnitTestSuite

const EPS := 0.001
const DAY := 86400


## 固定の時刻を返す偽の Clock。テスト中に now を書き換えられる
class FakeClock:
	extends Clock
	var now := 0

	func now_unix() -> int:
		return now


## 固定のタイムゾーンを返す偽の TimeZoneSource
class FakeZone:
	extends TimeZoneSource
	var zone := ""
	var bias := 0

	func zone_name() -> String:
		return zone

	func bias_minutes() -> int:
		return bias


var _clock: FakeClock
var _zone: FakeZone
var _override: MoonOverride
var _use_case: GetBackgroundMoonUseCase


func before_test() -> void:
	_clock = FakeClock.new()
	_zone = FakeZone.new()
	_zone.zone = "JST"
	_zone.bias = 540
	_override = MoonOverride.new()
	_use_case = GetBackgroundMoonUseCase.new(_clock, _zone, _override)


## 月齢（日）に当たる UNIX 秒を Clock にセットする。
func _set_age(days: float) -> void:
	_clock.now = MoonPhase.REFERENCE_NEW_MOON_UNIX + int(round(days * DAY))


## 前提: 新月（北）。期待: illumination 0・waxing 真（位相 0）。
func test_new_moon() -> void:
	_set_age(0.0)
	var v := _use_case.handle()
	assert_float(v.illumination).is_equal_approx(0.0, EPS)
	assert_bool(v.waxing).is_true()
	assert_int(v.hemisphere).is_equal(Hemisphere.Kind.NORTH)


## 前提: 満月（北）。期待: illumination 1。
func test_full_moon() -> void:
	_set_age(MoonPhase.SYNODIC_DAYS / 2.0)
	var v := _use_case.handle()
	assert_float(v.illumination).is_equal_approx(1.0, EPS)
	assert_float(v.phase).is_equal_approx(0.5, EPS)


## 前提: 上弦（北）。期待: 右が光る・waxing 真・illumination 0.5。
func test_first_quarter_north() -> void:
	_set_age(MoonPhase.SYNODIC_DAYS * 0.25)
	var v := _use_case.handle()
	assert_float(v.illumination).is_equal_approx(0.5, EPS)
	assert_bool(v.waxing).is_true()
	assert_bool(v.lit_on_right).is_true()


## 前提: 下弦（北）。期待: 左が光る・waxing 偽・illumination 0.5。
func test_last_quarter_north() -> void:
	_set_age(MoonPhase.SYNODIC_DAYS * 0.75)
	var v := _use_case.handle()
	assert_float(v.illumination).is_equal_approx(0.5, EPS)
	assert_bool(v.waxing).is_false()
	assert_bool(v.lit_on_right).is_false()


## 前提: 南半球の略称（AEDT）。期待: 上弦・下弦で光る側が北と逆（F8）。waxing・illumination は変わらない。
func test_south_inverts_lit_side() -> void:
	_zone.zone = "AEDT"
	_zone.bias = 660
	_set_age(MoonPhase.SYNODIC_DAYS * 0.25)
	var first := _use_case.handle()
	assert_int(first.hemisphere).is_equal(Hemisphere.Kind.SOUTH)
	assert_bool(first.waxing).is_true()
	assert_bool(first.lit_on_right).is_false()
	_set_age(MoonPhase.SYNODIC_DAYS * 0.75)
	var last := _use_case.handle()
	assert_bool(last.waxing).is_false()
	assert_bool(last.lit_on_right).is_true()


## 前提: 名前が空・bias が表に無い（判別不能）。期待: 北半球固定（満ちていく間は右）。
func test_undetermined_zone_is_north() -> void:
	_zone.zone = ""
	_zone.bias = 0
	_set_age(MoonPhase.SYNODIC_DAYS * 0.1)
	var v := _use_case.handle()
	assert_int(v.hemisphere).is_equal(Hemisphere.Kind.NORTH)
	assert_bool(v.lit_on_right).is_true()


## 前提: MoonOverride の unix。期待: Clock より優先。
func test_override_unix_beats_clock() -> void:
	_set_age(0.0)
	_override.set_unix(MoonPhase.REFERENCE_NEW_MOON_UNIX + int(MoonPhase.SYNODIC_DAYS / 2.0 * DAY))
	assert_float(_use_case.handle().illumination).is_equal_approx(1.0, EPS)


## 前提: unix と age_days の両方を上書き。期待: age_days が優先。
func test_override_age_beats_unix() -> void:
	_override.set_unix(MoonPhase.REFERENCE_NEW_MOON_UNIX)
	_override.set_age_days(MoonPhase.SYNODIC_DAYS / 2.0)
	var v := _use_case.handle()
	assert_float(v.illumination).is_equal_approx(1.0, EPS)
	assert_float(v.age_days).is_equal_approx(MoonPhase.SYNODIC_DAYS / 2.0, EPS)


## 前提: 北のタイムゾーンで hemisphere を南に上書き。期待: 上書きが優先。
func test_override_hemisphere_beats_zone() -> void:
	_set_age(MoonPhase.SYNODIC_DAYS * 0.25)
	_override.set_hemisphere(Hemisphere.Kind.SOUTH)
	var v := _use_case.handle()
	assert_int(v.hemisphere).is_equal(Hemisphere.Kind.SOUTH)
	assert_bool(v.lit_on_right).is_false()


## 前提: 上書きを外す。期待: Clock と判定に戻る。
func test_clear_override_returns_to_clock() -> void:
	_set_age(0.0)
	_override.set_age_days(MoonPhase.SYNODIC_DAYS / 2.0)
	_override.clear()
	assert_float(_use_case.handle().illumination).is_equal_approx(0.0, EPS)


## 前提: 計算のたびに last_view が更新される。期待: handle の返り値と同じ。
func test_last_view_is_recorded() -> void:
	_set_age(3.0)
	var v := _use_case.handle()
	assert_object(_override.last_view).is_same(v)


## 前提: Clock を変えて 2 回呼ぶ。期待: 結果が変わる（保存しない。F11・D-3）。
func test_recomputed_every_call() -> void:
	_set_age(0.0)
	var first := _use_case.handle().illumination
	_set_age(MoonPhase.SYNODIC_DAYS / 2.0)
	var second := _use_case.handle().illumination
	assert_float(second).is_greater(first)


## 前提: 日付またぎ（同じ日の 23:59 UTC と翌日 00:01 UTC）。期待: 月齢が連続に進む（約 2 分ぶん・飛ばない）。
func test_continuous_across_midnight() -> void:
	var midnight := MoonPhase.REFERENCE_NEW_MOON_UNIX + 10 * DAY + 20 * 3600  # 適当な日の 00:00 UTC 付近
	midnight -= midnight % DAY
	_clock.now = midnight - 60
	var before := _use_case.handle().age_days
	_clock.now = midnight + 60
	var after := _use_case.handle().age_days
	assert_float(after - before).is_equal_approx(120.0 / DAY, 0.0001)


## 前提: 時刻の上書きなし・北半球。基準の新月の 7 日 17 時間 46 分後（月齢 約 7.74・位相 0.262）で、JST（+9 時間）の
## 現地 21 時ちょうど。期待: Clock とタイムゾーンの差から現地の太陽時が決まり、右が下がる傾き 約 -43 度（検算した値）。
func test_tilt_uses_clock_and_time_zone() -> void:
	_clock.now = MoonPhase.REFERENCE_NEW_MOON_UNIX + 7 * DAY + 17 * 3600 + 46 * 60
	_zone.zone = "JST"
	_zone.bias = 540
	var view := _use_case.handle()
	assert_bool(view.lit_on_right).is_true()
	assert_float(rad_to_deg(view.tilt_radians)).is_equal_approx(-42.9, 3.0)


## 前提: local_hour を上書き。期待: 時刻・タイムゾーンより優先される（18 時の上弦は傾きほぼ 0）。
func test_local_hour_override_wins() -> void:
	_zone.zone = "JST"
	_zone.bias = 540
	_override.set_age_days(7.38)
	_override.set_local_hour(18.0)
	assert_float(rad_to_deg(_use_case.handle().tilt_radians)).is_equal_approx(0.0, 3.0)
	_override.set_local_hour(21.0)
	assert_float(rad_to_deg(_use_case.handle().tilt_radians)).is_less(-30.0)


## 前提: 南半球を上書き。期待: 北半球と同じ時刻で傾きの符号が逆（緯度 -35 度。光る側も反転）。
func test_southern_tilt_is_mirrored() -> void:
	_override.set_age_days(7.38)
	_override.set_local_hour(21.0)
	_override.set_hemisphere(Hemisphere.Kind.NORTH)
	var north := _use_case.handle()
	_override.set_hemisphere(Hemisphere.Kind.SOUTH)
	var south := _use_case.handle()
	assert_bool(south.lit_on_right).is_not_equal(north.lit_on_right)
	assert_float(south.tilt_radians).is_equal_approx(-north.tilt_radians, 0.01)
