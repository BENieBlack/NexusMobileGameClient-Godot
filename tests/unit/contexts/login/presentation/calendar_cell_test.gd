## CalendarCell（カレンダーの 1 マス）のテスト（client_design.md 1-3・6・9）。
##
## 状態（TODAY・RECEIVED・FUTURE・NEUTRAL）ごとの、スタンプ・「今日」の印・暗さ、play の真偽、文字（N 日目・数量・＋n）を確かめる。
extends GdUnitTestSuite

const CELL_SCENE := "res://contexts/login/presentation/login_bonus/calendar_cell.tscn"


func _cell(view: CalendarCellView = null) -> CalendarCell:
	var cell: CalendarCell = load(CELL_SCENE).instantiate()
	add_child(auto_free(cell))
	var v := view if view != null else _view()
	cell.setup(v, 80)
	return cell


func _view(day: int = 3, quantity: int = 1500, extra: int = 0) -> CalendarCellView:
	var view := CalendarCellView.new()
	view.day = day
	view.is_empty = false
	view.quantity = quantity
	view.extra_count = extra
	view.icon_type = "item"
	view.icon_id = "coin"
	return view


func _badge(cell: Node) -> Label:
	return cell.get_node("Content/DayRow/TodayBadge") as Label


## 前提: 数量 1500・追加 2 件の日。期待: 「3 日目」「x1,500」「＋2」が出る。
func test_texts() -> void:
	var cell := _cell(_view(3, 1500, 2))
	assert_str((cell.get_node("Content/DayRow/DayLabel") as Label).text).is_equal("3 日目")
	assert_str((cell.get_node("Content/AmountRow/QuantityLabel") as Label).text).is_equal("x1,500")
	var extra := cell.get_node("Content/AmountRow/ExtraLabel") as Label
	assert_str(extra.text).is_equal("＋2")
	assert_bool(extra.visible).is_true()


## 前提: 報酬が無い日（is_empty）。期待: 数量は出さず（unknown の絵のみ）、「＋n」も出ない。
func test_empty_day_shows_unknown_icon_without_quantity() -> void:
	var view := CalendarCellView.new()
	view.day = 2
	var cell := _cell(view)
	assert_str((cell.get_node("Content/AmountRow/QuantityLabel") as Label).text).is_equal("")
	assert_bool((cell.get_node("Content/AmountRow/ExtraLabel") as Label).visible).is_false()
	assert_str((cell.get_node("Content/IconHolder/ItemIcon") as ItemIcon).resolved_key).is_equal(
		"fallback/unknown"
	)


## 前提: TODAY を play = false（再表示）。期待: 最初から押印済み・「今日」の印あり・再生待ちでない。
func test_today_without_play_is_stamped_immediately() -> void:
	var cell := _cell()
	cell.apply_state(CalendarCellView.State.TODAY, false)
	assert_bool(cell.is_stamp_visible()).is_true()
	assert_bool(cell.is_waiting_stamp).is_false()
	assert_bool(_badge(cell).visible).is_true()
	assert_str(_badge(cell).text).is_equal("今日")


## 前提: TODAY を play = true。期待: スタンプはまだ出ず（押される前）、再生待ち。「今日」の印は出ている。
func test_today_with_play_waits_for_stamp() -> void:
	var cell := _cell()
	cell.apply_state(CalendarCellView.State.TODAY, true)
	assert_bool(cell.is_stamp_visible()).is_false()
	assert_bool(cell.is_waiting_stamp).is_true()
	assert_bool(_badge(cell).visible).is_true()


## 前提: RECEIVED。期待: 押印済み（アニメーションなし）・印なし・少し暗い（明るさ 0.8）。
func test_received_is_stamped_and_dim() -> void:
	var cell := _cell()
	cell.apply_state(CalendarCellView.State.RECEIVED, false)
	assert_bool(cell.is_stamp_visible()).is_true()
	assert_bool(_badge(cell).visible).is_false()
	var content := cell.get_node("Content") as Control
	assert_float(content.modulate.r).is_equal_approx(0.8, 0.001)


## 前提: FUTURE。期待: スタンプなし・印なし・RECEIVED より暗い。鍵・ロックの部品は無い。
func test_future_is_dark_without_stamp() -> void:
	var cell := _cell()
	cell.apply_state(CalendarCellView.State.FUTURE, false)
	assert_bool(cell.is_stamp_visible()).is_false()
	assert_bool(_badge(cell).visible).is_false()
	assert_float((cell.get_node("Content") as Control).modulate.r).is_less(0.8)


## 前提: NEUTRAL（今日の段でない段）。期待: 強調もスタンプも暗さも無い（通常の色）。
func test_neutral_has_no_emphasis() -> void:
	var cell := _cell()
	cell.apply_state(CalendarCellView.State.NEUTRAL, false)
	assert_bool(cell.is_stamp_visible()).is_false()
	assert_bool(_badge(cell).visible).is_false()
	(
		assert_bool((cell.get_node("Content") as Control).modulate.is_equal_approx(Color.WHITE))
		. is_true()
	)


## 前提: play = true で待っているマスを play = false で呼び直す（スキップ）。
## 期待: 最終状態（押印済み・縮尺 1・不透明）へ即時に飛ぶ。
func test_apply_state_false_jumps_to_final_state() -> void:
	var cell := _cell()
	cell.apply_state(CalendarCellView.State.TODAY, true)
	cell.prepare_stamp_animation()
	cell.apply_state(CalendarCellView.State.TODAY, false)
	var stamp := cell.stamp_node()
	assert_bool(stamp.visible).is_true()
	assert_vector(stamp.scale).is_equal(Vector2.ONE)
	assert_float(stamp.modulate.a).is_equal(1.0)
