## 背景の月の表示値（BackgroundMoonView）を求める UseCase（client_design 2-1。F2・F8・F11）。
##
## 目的: 端末の現在時刻とタイムゾーンから、描画に渡す月の値を 1 回分作る。
## 流れ（handle）:
##   1. 月齢を決める: MoonOverride の age_days → unix → Clock の現在時刻 の順
##   2. 位相・照らされる割合・満ち欠けの向きを MoonPhase で求める
##   3. 半球を決める: MoonOverride の hemisphere → TimeZoneSource からの判定（Hemisphere）
##   4. 南半球なら光る側を反転して BackgroundMoonView にする（F8）。直近の値を override.last_view に書く
## why:
##   - 保存しない（D-3）。呼ぶたびに現在から決め直す（画面を開くたび。F11）
##   - サーバー時刻のオフセットは足さない（F3: 端末の現在時刻。通信しない）
##   - 失敗が無いので Result は使わず値を直接返す（GetStaminaDisplayUseCase と同じ）
##   - 置き場が core/domain なのは、auth・login・player の 3 コンテキストが共有する表示専用だから（A-1）
class_name GetBackgroundMoonUseCase
extends RefCounted

var _clock: Clock
var _time_zone: TimeZoneSource
var _override: MoonOverride


func _init(clock: Clock, time_zone: TimeZoneSource, override: MoonOverride) -> void:
	_clock = clock
	_time_zone = time_zone
	_override = override


## 今の月の値を作る。
func handle() -> BackgroundMoonView:
	var age_days: float
	if _override.has_age_days():
		age_days = fposmod(_override.age_days(), MoonPhase.SYNODIC_DAYS)
	elif _override.has_unix():
		age_days = MoonPhase.age_days_at(_override.unix())
	else:
		age_days = MoonPhase.age_days_at(_clock.now_unix())

	var phase := MoonPhase.phase_of_age(age_days)
	var waxing := MoonPhase.is_waxing(phase)

	var hemisphere: Hemisphere.Kind
	if _override.has_hemisphere():
		hemisphere = _override.hemisphere()
	else:
		hemisphere = Hemisphere.detect(_time_zone.zone_name(), _time_zone.bias_minutes())

	# 北半球は満ちていく間が右、欠けていく間が左。南半球は左右が逆
	var lit_on_right := waxing if hemisphere == Hemisphere.Kind.NORTH else not waxing

	var view := BackgroundMoonView.new(
		age_days, phase, MoonPhase.illumination_of_phase(phase), waxing, lit_on_right, hemisphere
	)
	_override.last_view = view
	return view
