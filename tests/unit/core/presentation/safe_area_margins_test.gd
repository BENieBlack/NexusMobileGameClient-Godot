## SafeAreaMargins（物理ピクセル → ビューポート座標）の単体テスト。
extends GdUnitTestSuite


## 前提: 物理 1170x2532、ビューポート 1080x1920（キープ幅想定で軸ごとの比）。上 141・下 102 物理ピクセル。
## 期待: 比を掛けた値（そのまま足さない）。
func test_converts_physical_pixels_to_viewport() -> void:
	var safe := Rect2i(0, 141, 1170, 2532 - 141 - 102)
	var m := SafeAreaMargins.to_viewport(safe, Vector2i(1170, 2532), Vector2(1080, 1920))
	assert_float(m["top"]).is_equal_approx(141 * 1920.0 / 2532.0, 0.001)
	assert_float(m["bottom"]).is_equal_approx(102 * 1920.0 / 2532.0, 0.001)
	assert_float(m["left"]).is_equal(0.0)
	assert_float(m["right"]).is_equal(0.0)


## 前提: 左右にも余白（横向き相当）。期待: 左は position.x、右は window.x − end.x を比で変換。
func test_left_and_right() -> void:
	var safe := Rect2i(100, 0, 1800, 1080)
	var m := SafeAreaMargins.to_viewport(safe, Vector2i(2000, 1080), Vector2(1000, 540))
	assert_float(m["left"]).is_equal_approx(50.0, 0.001)
	assert_float(m["right"]).is_equal_approx(50.0, 0.001)


## 前提: 全面と同じ（デスクトップ）。期待: 余白 0。
func test_full_area_is_zero() -> void:
	var m := SafeAreaMargins.to_viewport(
		Rect2i(0, 0, 540, 960), Vector2i(540, 960), Vector2(1080, 1920)
	)
	assert_float(m["top"] + m["bottom"] + m["left"] + m["right"]).is_equal(0.0)


## 前提: 値が取れない（大きさ 0）・はみ出し。期待: すべて 0（負にしない）。
func test_invalid_inputs_are_zero() -> void:
	var zero := SafeAreaMargins.to_viewport(Rect2i(), Vector2i(540, 960), Vector2(1080, 1920))
	assert_float(zero["top"]).is_equal(0.0)
	var no_window := SafeAreaMargins.to_viewport(
		Rect2i(0, 0, 10, 10), Vector2i.ZERO, Vector2(1080, 1920)
	)
	assert_float(no_window["bottom"]).is_equal(0.0)
	var over := SafeAreaMargins.to_viewport(
		Rect2i(-10, -10, 600, 1000), Vector2i(540, 960), Vector2(1080, 1920)
	)
	assert_float(over["left"]).is_equal(0.0)
	assert_float(over["bottom"]).is_equal(0.0)


## HomeText: 桁区切り・時間の書式。
func test_format_number_and_duration() -> void:
	assert_str(HomeText.format_number(0)).is_equal("0")
	assert_str(HomeText.format_number(999)).is_equal("999")
	assert_str(HomeText.format_number(1000)).is_equal("1,000")
	assert_str(HomeText.format_number(999999999)).is_equal("999,999,999")
	assert_str(HomeText.format_number(-1234)).is_equal("-1,234")
	assert_str(HomeText.format_duration(272)).is_equal("04:32")
	assert_str(HomeText.format_duration(3600)).is_equal("1:00:00")
	assert_str(HomeText.format_duration(3725)).is_equal("1:02:05")


## 前提: 座標系の取り違えで巨大な値（デスクトップの作業領域のずれなど）。期待: 1 辺 20% に収める。
func test_extreme_values_are_clamped() -> void:
	var safe := Rect2i(740, 1600, 300, 100)
	var m := SafeAreaMargins.to_viewport(safe, Vector2i(1080, 1920), Vector2(1080, 1920))
	assert_float(m["left"]).is_equal_approx(216.0, 0.001)
	assert_float(m["top"]).is_equal_approx(384.0, 0.001)


## セーフエリアを使うのはモバイルだけ。
func test_safe_area_platform() -> void:
	assert_bool(HomePresenter.is_safe_area_platform("iOS")).is_true()
	assert_bool(HomePresenter.is_safe_area_platform("Android")).is_true()
	assert_bool(HomePresenter.is_safe_area_platform("macOS")).is_false()
	assert_bool(HomePresenter.is_safe_area_platform("Windows")).is_false()
