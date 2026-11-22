## 背景の月の e2e 引数（--e2e-moon-date / -age / -hemisphere）の解釈と、E2E 行の書式（client_design 5 節）。
##
## 目的: E2EDriver が大きくなりすぎないよう、月の引数の解釈を純関数としてここへ分ける。状態を持たない。
## 使い方: E2EDriver が parse の結果を AppContext.debug_moon_override()（MoonOverride）へ設定する。
class_name E2eMoonArgs
extends RefCounted

## --e2e-moon-age の上限（これ未満。設計 5 節の 29.53）
const AGE_MAX := 29.53


## 月の引数（--e2e-moon-date / -age / -hemisphere）を解釈する純関数。
## 戻り値: {"error": String（空なら正常）} に、指定されたものだけ "unix"（int）・"age_days"（float）・
##   "hemisphere"（Hemisphere.Kind）・"local_hour"（float。現地の太陽時。傾きの計算用）を足した辞書。
##   date と age の同時指定・不正な値は error に理由を入れる。
static func parse(args: Dictionary) -> Dictionary:
	var result := {"error": ""}
	if args.has("e2e-moon-date") and args.has("e2e-moon-age"):
		result["error"] = "date-and-age-conflict"
		return result
	if args.has("e2e-moon-date"):
		var unix: Variant = date_to_unix(str(args["e2e-moon-date"]))
		if unix == null:
			result["error"] = "bad-date %s" % str(args["e2e-moon-date"])
			return result
		result["unix"] = unix
	if args.has("e2e-moon-age"):
		var text := str(args["e2e-moon-age"])
		var age := text.to_float()
		if not text.is_valid_float() or age < 0.0 or age >= AGE_MAX:
			result["error"] = "bad-age %s" % text
			return result
		result["age_days"] = age
	if args.has("e2e-moon-hour"):
		var hour_text := str(args["e2e-moon-hour"])
		var hour := hour_text.to_float()
		if not hour_text.is_valid_float() or hour < 0.0 or hour >= 24.0:
			result["error"] = "bad-hour %s" % hour_text
			return result
		result["local_hour"] = hour
	if args.has("e2e-moon-hemisphere"):
		var text := str(args["e2e-moon-hemisphere"])
		if text == "north":
			result["hemisphere"] = Hemisphere.Kind.NORTH
		elif text == "south":
			result["hemisphere"] = Hemisphere.Kind.SOUTH
		else:
			result["error"] = "bad-hemisphere %s" % text
	return result


## `YYYY-MM-DD` または `YYYY-MM-DDTHH:MM`（UTC）を UNIX 秒にする。時刻を省くと 12:00。
## 書式・範囲・存在しない日（2 月 30 日など）は null。
static func date_to_unix(text: String) -> Variant:
	var regex := RegEx.create_from_string("^(\\d{4})-(\\d{2})-(\\d{2})(?:T(\\d{2}):(\\d{2}))?$")
	var m := regex.search(text)
	if m == null:
		return null
	var year := m.get_string(1).to_int()
	var month := m.get_string(2).to_int()
	var day := m.get_string(3).to_int()
	var hour := 12 if m.get_string(4) == "" else m.get_string(4).to_int()
	var minute := 0 if m.get_string(5) == "" else m.get_string(5).to_int()
	if month < 1 or month > 12 or hour > 23 or minute > 59:
		return null
	if day < 1 or day > _days_in_month(year, month):
		return null
	return Time.get_unix_time_from_datetime_dict(
		{"year": year, "month": month, "day": day, "hour": hour, "minute": minute, "second": 0}
	)


static func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
		return 29 if leap else 28
	return 30 if month in [4, 6, 9, 11] else 31


## `E2E: moon age=… phase=… illumination=… lit=right|left hemisphere=north|south`（設計 5 節）。
static func format_line(view: BackgroundMoonView) -> String:
	return (
		"E2E: moon age=%.2f phase=%.3f illumination=%.3f lit=%s hemisphere=%s tilt=%.1f"
		% [
			view.age_days,
			view.phase,
			view.illumination,
			"right" if view.lit_on_right else "left",
			"south" if view.hemisphere == Hemisphere.Kind.SOUTH else "north",
			rad_to_deg(view.tilt_radians) + 0.0,
		]
	)
