## CalendarText（カレンダーの固定文字）のテスト（client_design.md 1-3・1-2）。
extends GdUnitTestSuite


## 前提: 日数・数量・件数。期待: 設計の文字（N 日目・x桁区切り・全角プラスの＋n）。
func test_basic_texts() -> void:
	assert_str(CalendarText.day_text(7)).is_equal("7 日目")
	assert_str(CalendarText.quantity_text(20000)).is_equal("x20,000")
	assert_str(CalendarText.quantity_text(0)).is_equal("x0")
	assert_str(CalendarText.extra_text(2)).is_equal("＋2")


## 前提: 通常・VIP（レベルあり・なし）。期待: 見出しの文字。VIP は全角スペース区切り、レベル 0 は「VIP ボーナス」だけ。
func test_stage_header() -> void:
	assert_str(CalendarText.stage_header(false, 0)).is_equal("ログインボーナス")
	assert_str(CalendarText.stage_header(true, 3)).is_equal("VIP ボーナス　VIP 3")
	assert_str(CalendarText.stage_header(true, 0)).is_equal("VIP ボーナス")
