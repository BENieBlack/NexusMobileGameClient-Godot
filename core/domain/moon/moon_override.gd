## 月の計算を差し替えるデバッグ用の上書き（client_design 2-1。録画・e2e。F15）。
##
## 目的: 録画やテストで「この日・この月齢・この半球の月」を出すために、時刻・月齢・半球を差し替える。
##       未設定 = 上書きなし（UseCase は Clock とタイムゾーンの判定を使う）。
## 置き場の理由: 設定するのは debug/ だけだが、製品側（core）が debug/ を参照しないように、型は製品側に置く
##       （SystemClock.skew_seconds と同じ扱い）。製品では誰も設定しない。
## 優先順位（UseCase が決める）: age_days > unix > Clock。
##       現地の太陽時（傾き用）は local_hour > 時刻 + タイムゾーンの差。半球は hemisphere > タイムゾーンの判定。
## last_view: UseCase が直近に計算した BackgroundMoonView を書く、デバッグ観測用の値（e2e の `E2E:` 行用）。
##       判定には使わない・保存の意味も持たない（D-3 とは別）。
## 注意: 引数（--e2e-moon-*）の解釈はここではしない（debug/e2e_driver.gd の役目）。
class_name MoonOverride
extends RefCounted

## 直近に UseCase が計算した月の値（デバッグ観測用。未計算は null）
var last_view: BackgroundMoonView = null

var _unix := 0
var _has_unix := false
var _age_days := 0.0
var _has_age_days := false
var _hemisphere := Hemisphere.Kind.NORTH
var _has_hemisphere := false
var _local_hour := 0.0
var _has_local_hour := false


## 時刻（UTC の UNIX 秒）を上書きする。
func set_unix(value: int) -> void:
	_unix = value
	_has_unix = true


## 月齢（日）を直接指定する。時刻より優先される。
func set_age_days(value: float) -> void:
	_age_days = value
	_has_age_days = true


## 半球を上書きする。
func set_hemisphere(value: Hemisphere.Kind) -> void:
	_hemisphere = value
	_has_hemisphere = true


## 現地の太陽時（時。0 以上 24 未満）を直接指定する（傾きの計算用。録画で「18 時の上弦」を撮るため）。
func set_local_hour(value: float) -> void:
	_local_hour = value
	_has_local_hour = true


## 上書きをすべて外す（last_view は残す）。
func clear() -> void:
	_has_unix = false
	_has_age_days = false
	_has_hemisphere = false
	_has_local_hour = false


func has_unix() -> bool:
	return _has_unix


func has_age_days() -> bool:
	return _has_age_days


func has_hemisphere() -> bool:
	return _has_hemisphere


func unix() -> int:
	return _unix


func age_days() -> float:
	return _age_days


func hemisphere() -> Hemisphere.Kind:
	return _hemisphere


func has_local_hour() -> bool:
	return _has_local_hour


func local_hour() -> float:
	return _local_hour
