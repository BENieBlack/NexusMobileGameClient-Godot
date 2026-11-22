## LoginBonusPresenter の FROM_HOME 入口・受け取りボタンの表示と二重送信のテスト（client_design.md 1-1・1-5・3-2・9。V3c）。
##
## 確かめること:
##   - FROM_HOME の流れ（読み込み中 → list → 描画。アニメーションなし・行なし）と、list 失敗のエラー文＋再試行・ホームへ戻れること
##   - 受け取りボタンの表示条件（can_re_receive のときだけ。両方の入口）・受け取り中・二重送信防止・受け取り中は閉じない
##   - 表示されるラベル・ボタンが幅 0 に潰れていない（V3b の教訓。新しい状態ごと）
## 方法: 本物の LoginBonusPresenter・UseCase を使い、API（ScriptedCalendar）・マスターの窓口・遷移・Toast だけ偽物にする。
extends GdUnitTestSuite

const FX := preload("res://tests/unit/contexts/login/presentation/login_bonus_screen_fixtures.gd")
const VBOX := "Margin/Center/Panel/VBox/"

var _router: ScreenTestDoubles.FakeRouter
var _toast: ScreenTestDoubles.FakeToast
var _repository: LocalLoginBonusRepository
var _calendar: LoginBonusScreenFixtures.ScriptedCalendar


func before_test() -> void:
	_router = ScreenTestDoubles.FakeRouter.new()
	_toast = ScreenTestDoubles.FakeToast.new()
	_repository = LocalLoginBonusRepository.new()
	_calendar = LoginBonusScreenFixtures.ScriptedCalendar.new()


## 画面を作って描画まで進める。戻り値: [presenter, player_repository]。
func _open(from_home: bool) -> Array:
	var made := FX.make_full(self, _router, _toast, _repository, _calendar, from_home)
	auto_free(made[0])
	# 描画 → レイアウト確定のため 2 フレーム
	await get_tree().process_frame
	await get_tree().process_frame
	return made


func _node(presenter: Node, path: String) -> Node:
	return presenter.get_node(VBOX + path)


func _button(presenter: Node) -> Button:
	return _node(presenter, "ReceiveSlot/ReceiveButton") as Button


func _tap(presenter: Node) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	presenter.get_node("TapCatcher").gui_input.emit(event)


## 表示中（見えている）の Label / Button が、潰れていない（幅・高さ 8 以上）ことを確かめる。
func _assert_visible_and_not_collapsed(control: Control) -> void:
	assert_bool(control.is_visible_in_tree()).is_true()
	assert_float(control.size.x).is_greater_equal(8.0)
	assert_float(control.size.y).is_greater_equal(8.0)


func _vip_cell(presenter: Node) -> CalendarCell:
	return (_node(presenter, "VipSection") as CalendarSection).cells[3]


func _normal_cell(presenter: Node) -> CalendarCell:
	return (_node(presenter, "NormalSection") as CalendarSection).cells[3]


# ------------------------------------------------ FROM_HOME の流れ ----


## 前提: FROM_HOME。list の応答が来るまで待たせる。
## 期待: 「読み込み中…」が見えて（潰れない）カレンダー・ボタンは隠れ、応答後に消えてカレンダーが出る（list は 1 回）。
func test_from_home_shows_loading_then_calendar() -> void:
	var gate := FX.GateSource.new()
	_calendar.fetch_gate = gate.opened
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(false))]
	var made := FX.make_full(self, _router, _toast, _repository, _calendar, true)
	var p: LoginBonusPresenter = auto_free(made[0])
	await get_tree().process_frame
	await get_tree().process_frame
	var status := _node(p, "StatusLabel") as Label
	_assert_visible_and_not_collapsed(status)
	assert_str(status.text).is_equal("読み込み中…")
	assert_bool((_node(p, "NormalSection") as Control).visible).is_false()
	gate.opened.emit()
	await get_tree().process_frame
	assert_bool(status.visible).is_false()
	assert_bool((_node(p, "NormalSection") as Control).visible).is_true()
	assert_int(_calendar.fetch_count).is_equal(1)


## 前提: FROM_HOME・今日の段（再受け取り不可）。
## 期待: アニメーションなし（今日のマスは押印済みで待たない）・「受け取り済みです」の旨・報酬の行なし・ボタンなし。
func test_from_home_has_no_animation_no_rows_no_button() -> void:
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(false))]
	var made := await _open(true)
	var p: LoginBonusPresenter = made[0]
	var today := _vip_cell(p)
	assert_bool(today.is_stamp_visible()).is_true()
	assert_bool(today.is_waiting_stamp).is_false()
	assert_bool(_normal_cell(p).is_waiting_stamp).is_false()
	assert_bool((_node(p, "NoticeLabel") as Label).visible).is_true()
	assert_bool((_node(p, "RewardsHeader") as Label).visible).is_false()
	assert_bool((_node(p, "ReceiveSlot") as Control).visible).is_false()


## 前提: FROM_HOME・list が通信断。
## 期待: エラー文と「再試行」が出る（潰れない）・カレンダーは出ない。再試行を押すと list をやり直し、成功で消えてカレンダーが出る。
func test_from_home_list_failure_shows_error_and_retry() -> void:
	_calendar.fetch_results = [
		FX.failed_fetch(AppError.Kind.NETWORK), FX.fetched(FX.offer_calendars(false))
	]
	var made := await _open(true)
	var p: LoginBonusPresenter = made[0]
	var status := _node(p, "StatusLabel") as Label
	var retry := _node(p, "RetryButton") as Button
	_assert_visible_and_not_collapsed(status)
	_assert_visible_and_not_collapsed(retry)
	assert_str(status.text).is_equal(ErrorMessages.text(AppError.new(AppError.Kind.NETWORK)))
	assert_bool((_node(p, "NormalSection") as Control).visible).is_false()
	retry.pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_calendar.fetch_count).is_equal(2)
	assert_bool(retry.visible).is_false()
	assert_bool(status.visible).is_false()
	assert_bool((_node(p, "NormalSection") as Control).visible).is_true()


## 前提: FROM_HOME・list の失敗中。期待: タップでホームへ戻れる（1 回だけ）。
func test_from_home_can_go_home_while_error() -> void:
	_calendar.fetch_results = [FX.failed_fetch(AppError.Kind.NETWORK)]
	var made := await _open(true)
	_tap(made[0])
	_tap(made[0])
	assert_array(_router.calls).is_equal(["home"])


## 前提: FROM_HOME・list の応答待ちの間にホームへ戻る。期待: 応答が来ても画面を触らず落ちない（描画しない）。
func test_from_home_leaving_during_fetch_does_not_render() -> void:
	var gate := FX.GateSource.new()
	_calendar.fetch_gate = gate.opened
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(false))]
	var made := FX.make_full(self, _router, _toast, _repository, _calendar, true)
	var p: LoginBonusPresenter = auto_free(made[0])
	await get_tree().process_frame
	_tap(p)
	gate.opened.emit()
	await get_tree().process_frame
	assert_array(_router.calls).is_equal(["home"])
	assert_object(p.current_screen).is_null()


## 前提: FROM_HOME・list が SESSION_EXPIRED。期待: 文を見せてタイトルへ戻る（再試行は出さない）。
func test_from_home_session_expired_goes_to_title() -> void:
	_calendar.fetch_results = [FX.failed_fetch(AppError.Kind.SESSION_EXPIRED)]
	var made := FX.make_full(self, _router, _toast, _repository, _calendar, true)
	auto_free(made[0])
	await get_tree().process_frame
	assert_bool((_node(made[0], "RetryButton") as Button).visible).is_false()
	assert_str((_node(made[0], "StatusLabel") as Label).text).contains("無効")
	await await_millis(2300)
	assert_array(_router.calls).is_equal(["title"])


# ------------------------------------------------ 受け取りボタンの表示条件 ----


## 前提: FROM_LOGIN・VIP の can_re_receive が真。
## 期待: ボタンが出て（「受け取る」・潰れない）、押せる。通常の段だけ・can_re_receive 偽ならボタンは出ない。
func test_button_visible_only_when_can_re_receive_from_login() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	var made := await _open(false)
	var button := _button(made[0])
	_assert_visible_and_not_collapsed(button)
	assert_str(button.text).is_equal("受け取る")
	assert_bool(button.disabled).is_false()
	assert_bool((_node(made[0], "ReceiveSlot") as Control).visible).is_true()


func test_button_hidden_when_cannot_re_receive_from_login() -> void:
	_repository.replace_calendars(FX.offer_calendars(false))
	var made := await _open(false)
	assert_bool(_button(made[0]).visible).is_false()
	assert_bool((_node(made[0], "ReceiveSlot") as Control).visible).is_false()


## 前提: FROM_HOME・list の結果で can_re_receive が真。期待: ボタンが出る（FROM_HOME にも出る。Q30）。
func test_button_visible_from_home() -> void:
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(true))]
	var made := await _open(true)
	_assert_visible_and_not_collapsed(_button(made[0]))


## 前提: ボタンの STOP と他の mouse_filter。期待: ボタンは STOP（タップが貫通して閉じない）、枠・メッセージは IGNORE。
func test_button_blocks_tap_and_slot_ignores() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	var made := await _open(false)
	assert_int(_button(made[0]).mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_int((_node(made[0], "ReceiveSlot") as Control).mouse_filter).is_equal(
		Control.MOUSE_FILTER_IGNORE
	)
	(
		assert_int((_node(made[0], "ReceiveSlot/ReceiveMessageLabel") as Control).mouse_filter)
		. is_equal(Control.MOUSE_FILTER_IGNORE)
	)


# ------------------------------------------------ 受け取り中・二重送信 ----


## 前提: 受け取りの応答待ち。連打する。
## 期待: ボタンは無効で「受け取り中…」（潰れない）・送信は 1 回だけ・タップでも閉じない。応答後は閉じられる。
func test_receiving_disables_button_and_blocks_double_send_and_close() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	var gate := FX.GateSource.new()
	_calendar.receive_gate = gate.opened
	_calendar.receive_results = [FX.received()]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	var button := _button(p)
	button.pressed.emit()
	button.pressed.emit()
	button.pressed.emit()
	await get_tree().process_frame
	assert_int(_calendar.receive_calls.size()).is_equal(1)
	assert_bool(button.disabled).is_true()
	assert_str(button.text).is_equal("受け取り中…")
	_assert_visible_and_not_collapsed(button)
	_tap(p)
	assert_array(_router.calls).is_empty()
	gate.opened.emit()
	await get_tree().process_frame
	assert_int(_calendar.receive_calls.size()).is_equal(1)
	_tap(p)
	_tap(p)
	assert_array(_router.calls).is_equal(["home"])


## 前提: 受け取りの応答待ち。画面を解放する。期待: 応答が来ても何も触らず落ちない。
func test_freed_during_receive_does_not_touch_screen() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	var gate := FX.GateSource.new()
	_calendar.receive_gate = gate.opened
	_calendar.receive_results = [FX.received()]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	remove_child(p)
	p.queue_free()
	await get_tree().process_frame
	gate.opened.emit()
	await get_tree().process_frame
	assert_int(_calendar.receive_calls.size()).is_equal(1)
