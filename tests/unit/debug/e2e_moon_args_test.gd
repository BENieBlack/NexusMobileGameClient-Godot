## E2eMoonArgs（背景の月の e2e 引数の解釈・E2E 行の書式）の単体テスト。
extends GdUnitTestSuite

# --- 背景の月の引数（--e2e-moon-*。client_design 5 節） ---


## 前提: 日付だけ（時刻なし）。期待: 12:00 UTC の UNIX 秒になる（2026-11-22T12:00Z = 1795348800）。
func test_moon_date_without_time_is_noon_utc() -> void:
	var result: Dictionary = E2eMoonArgs.parse({"e2e-moon-date": "2026-11-22"})
	assert_str(result["error"]).is_empty()
	assert_int(result["unix"]).is_equal(1795348800)


## 前提: 日時つき。期待: その時刻（UTC）。2000-01-06T18:14Z は第 1 段の基準の新月（947182440）。
func test_moon_date_with_time() -> void:
	var result: Dictionary = E2eMoonArgs.parse({"e2e-moon-date": "2000-01-06T18:14"})
	assert_str(result["error"]).is_empty()
	assert_int(result["unix"]).is_equal(947182440)


## 前提: 書式・範囲・存在しない日が不正な日付。期待: どれも error（Z 付き・2 月 30 日・13 月・25 時を含む）。
func test_moon_date_invalid_is_error() -> void:
	for text in [
		"2026/11/22",
		"2026-11-22Z",
		"2026-11-22T12:00Z",
		"2026-02-30",
		"2025-02-29",
		"2026-13-01",
		"2026-11-22T25:00",
		"2026-11-22T12:60",
		"abc",
		""
	]:
		var result: Dictionary = E2eMoonArgs.parse({"e2e-moon-date": text})
		assert_str(result["error"]).is_not_empty()


## 前提: うるう年の 2 月 29 日。期待: 受け付ける。
func test_moon_date_leap_day() -> void:
	var result: Dictionary = E2eMoonArgs.parse({"e2e-moon-date": "2024-02-29"})
	assert_str(result["error"]).is_empty()


## 前提: 月齢の指定。期待: 範囲内（0 と 29.52）は受け付け、負・29.53 以上・数値でない・値なしは error。
func test_moon_age_range() -> void:
	var ok: Dictionary = E2eMoonArgs.parse({"e2e-moon-age": "7.38"})
	assert_str(ok["error"]).is_empty()
	assert_float(ok["age_days"]).is_equal_approx(7.38, 0.0001)
	for text in ["0", "29.52"]:
		assert_str(E2eMoonArgs.parse({"e2e-moon-age": text})["error"]).is_empty()
	for bad in ["-0.1", "29.53", "30", "abc", ""]:
		assert_str(E2eMoonArgs.parse({"e2e-moon-age": bad})["error"]).is_not_empty()
	assert_str(E2eMoonArgs.parse({"e2e-moon-age": true})["error"]).is_not_empty()


## 前提: date と age の同時指定。期待: error（どちらが効くか曖昧になるため）。
func test_moon_date_and_age_conflict() -> void:
	var result: Dictionary = E2eMoonArgs.parse({"e2e-moon-date": "2026-11-22", "e2e-moon-age": "3"})
	assert_str(result["error"]).is_equal("date-and-age-conflict")


## 前提: 半球の指定。期待: north / south は対応する値、それ以外は error。
func test_moon_hemisphere_values() -> void:
	var north: Dictionary = E2eMoonArgs.parse({"e2e-moon-hemisphere": "north"})
	var south: Dictionary = E2eMoonArgs.parse({"e2e-moon-hemisphere": "south"})
	assert_int(north["hemisphere"]).is_equal(Hemisphere.Kind.NORTH)
	assert_int(south["hemisphere"]).is_equal(Hemisphere.Kind.SOUTH)
	var bad: Dictionary = E2eMoonArgs.parse({"e2e-moon-hemisphere": "East"})
	assert_str(bad["error"]).is_not_empty()


## 前提: 月の引数なし（他の e2e 引数だけ）。期待: error なし・上書きの項目なし（上書きなし）。
func test_moon_args_absent_means_no_override() -> void:
	var result: Dictionary = E2eMoonArgs.parse({"e2e-dwell": "2"})
	assert_str(result["error"]).is_empty()
	assert_int(result.size()).is_equal(1)


## 前提: 北半球の上弦と南半球の下弦の値。期待: E2E 行の書式（age・phase・illumination・lit・hemisphere）。
func test_format_moon_line() -> void:
	var north := BackgroundMoonView.new(7.38, 0.25, 0.5, true, true, Hemisphere.Kind.NORTH)
	assert_str(E2eMoonArgs.format_line(north)).is_equal(
		"E2E: moon age=7.38 phase=0.250 illumination=0.500 lit=right hemisphere=north tilt=0.0"
	)
	var south := BackgroundMoonView.new(
		22.15, 0.75, 0.5, false, true, Hemisphere.Kind.SOUTH, deg_to_rad(-45.0)
	)
	assert_str(E2eMoonArgs.format_line(south)).is_equal(
		"E2E: moon age=22.15 phase=0.750 illumination=0.500 lit=right hemisphere=south tilt=-45.0"
	)


## 前提: --e2e-moon-hour。期待: 0 以上 24 未満の小数は受け付け（local_hour）、範囲外・数値でない・値なしは error。
func test_moon_hour() -> void:
	var ok := E2eMoonArgs.parse({"e2e-moon-hour": "21.5"})
	assert_str(ok["error"]).is_empty()
	assert_float(ok["local_hour"]).is_equal_approx(21.5, 0.0001)
	assert_str(E2eMoonArgs.parse({"e2e-moon-hour": "0"})["error"]).is_empty()
	for bad in ["24", "-1", "abc", ""]:
		assert_str(E2eMoonArgs.parse({"e2e-moon-hour": bad})["error"]).is_not_empty()
	assert_str(E2eMoonArgs.parse({"e2e-moon-hour": true})["error"]).is_not_empty()
