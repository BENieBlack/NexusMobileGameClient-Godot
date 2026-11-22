## 背景の月を描くために画面へ渡す値のまとまり（client_design 2-1）。
##
## 目的: UseCase の計算結果（月齢・位相・照らされる割合・光る側・半球）を 1 つにまとめて、
##       描画側（BackgroundMoon）が計算を知らずに受け取れるようにする。保持するだけで計算はしない。
## 値:
##   age_days     月齢（日）。新月が 0
##   phase        位相（0〜1。0.5 が満月）
##   illumination 照らされている割合（0〜1）。にじみ・霧の強さにも使う
##   waxing       満ちていく途中か
##   lit_on_right 右側が光るか。北半球は waxing と同じ、南半球は反転（F8・F10）
##   hemisphere   判定に使った半球（Hemisphere.Kind）
##   tilt_radians 明るい縁の向きの傾き（基準の向き［右が光るなら右・左なら左］から、画面で反時計回りが正。
##                MoonTilt が時刻と位相から近似する。満月・新月では見えない）
class_name BackgroundMoonView
extends RefCounted

var age_days: float
var phase: float
var illumination: float
var waxing: bool
var lit_on_right: bool
var hemisphere: Hemisphere.Kind
var tilt_radians: float


func _init(
	p_age_days: float,
	p_phase: float,
	p_illumination: float,
	p_waxing: bool,
	p_lit_on_right: bool,
	p_hemisphere: Hemisphere.Kind,
	p_tilt_radians: float = 0.0
) -> void:
	age_days = p_age_days
	phase = p_phase
	illumination = p_illumination
	waxing = p_waxing
	lit_on_right = p_lit_on_right
	hemisphere = p_hemisphere
	tilt_radians = p_tilt_radians
