## LoginBonusPresenter（ログインボーナス画面。V3b = FROM_LOGIN）のテスト（client_design.md 1-1・1-3・3・6・9）。
##
## 確かめること: 段・報酬の行・再表示の旨の表示切り替え、文字の画面（今の build_text。受け取り済みの文・グレード・
## 名前の規則）、「読み込み中…」、TapCatcher のタップ（ホームへ 1 回・アニメーション中は飛ぶだけ）、
## 受け取りの枠（V3b は出さない）、マスターを引く窓口へ進捗を渡すこと。
extends GdUnitTestSuite

const FX := preload("res://tests/unit/contexts/login/presentation/login_bonus_screen_fixtures.gd")
const VBOX := "Margin/Center/Panel/VBox/"

var _router: ScreenTestDoubles.FakeRouter
var _repository: LocalLoginBonusRepository


func before_test() -> void:
	_router = ScreenTestDoubles.FakeRouter.new()
	_repository = LocalLoginBonusRepository.new()


## 画面を作り、描画（_ready の await 後）まで進める。
func _show(prepare_masters: LoginBonusStageMasters = null) -> LoginBonusPresenter:
	var masters := prepare_masters if prepare_masters != null else FX.masters()
	var made := FX.make(self, _router, masters, _repository)
	var presenter: LoginBonusPresenter = auto_free(made[0])
	await get_tree().process_frame
	return presenter


func _node(presenter: Node, path: String) -> Node:
	return presenter.get_node(VBOX + path)


func _tap(presenter: LoginBonusPresenter) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	presenter.get_node("TapCatcher").gui_input.emit(event)


# ------------------------------------------------ カレンダー表示 ----


## 前提: 通常・VIP が今日の段（3 日目・今配った）。報酬 2 行。
## 期待: 両方の段が出て 7 マス・見出しの文字・再表示の旨は出ない・報酬の行が 2 行・文字の画面は隠れる。
func test_calendar_shows_both_stages_and_rewards() -> void:
	FX.put_granted_now(_repository, 3)
	FX.put_rewards(_repository, 2)
	var p := await _show()
	var normal := _node(p, "NormalSection") as CalendarSection
	var vip := _node(p, "VipSection") as CalendarSection
	assert_bool(normal.visible).is_true()
	assert_bool(vip.visible).is_true()
	assert_int(normal.cells.size()).is_equal(7)
	assert_int(vip.cells.size()).is_equal(7)
	assert_str((normal.get_node("HeaderLabel") as Label).text).is_equal("ログインボーナス")
	assert_str((vip.get_node("HeaderLabel") as Label).text).is_equal("VIP ボーナス　VIP 3")
	assert_bool((_node(p, "NoticeLabel") as Label).visible).is_false()
	assert_bool((_node(p, "BonusBg") as Control).visible).is_false()
	assert_bool((_node(p, "RewardsHeader") as Label).visible).is_true()
	assert_int(_node(p, "RewardsList").get_child_count()).is_equal(2)
	assert_bool((_node(p, "StatusLabel") as Label).visible).is_false()


## 前提: 通常の段だけ（VIP の進捗なし）。期待: VIP の段は出ない（その段を出さない。T4）。
func test_vip_stage_hidden_when_absent() -> void:
	_repository.replace_calendars(
		LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 2, true, true))
	)
	var p := await _show()
	assert_bool((_node(p, "NormalSection") as Control).visible).is_true()
	assert_bool((_node(p, "VipSection") as Control).visible).is_false()


## 前提: 今日の段だが今配ったのではない（再表示）。報酬の行なし。
## 期待: 「本日のログインボーナスは受け取り済みです」が出る・報酬の行は出ない・今日のマスは最初から押印済み（待たない）。
func test_redisplay_shows_notice_and_stamped_today() -> void:
	_repository.replace_calendars(
		LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 4, true, false))
	)
	var p := await _show()
	var notice := _node(p, "NoticeLabel") as Label
	assert_bool(notice.visible).is_true()
	assert_str(notice.text).is_equal("本日のログインボーナスは受け取り済みです")
	assert_bool((_node(p, "RewardsHeader") as Label).visible).is_false()
	var today := (_node(p, "NormalSection") as CalendarSection).cells[3]
	assert_bool(today.is_stamp_visible()).is_true()
	assert_bool(today.is_waiting_stamp).is_false()


## 前提: 今日配ったばかり（3 日目）。期待: 今日のマスだけが押印待ち（play_stamp）で、過去のマスは押印済み・未来は無し。
func test_only_todays_cell_waits_for_stamp() -> void:
	FX.put_granted_now(_repository, 3, false)
	var p := await _show()
	var cells := (_node(p, "NormalSection") as CalendarSection).cells
	for i in range(cells.size()):
		assert_bool(cells[i].is_waiting_stamp or cells[i].is_stamp_visible()).is_equal(i <= 2)
		assert_bool(cells[i].is_waiting_stamp).is_equal(i == 2)


## 前提: 受け取りボタンの表示値が真（VIP の can_re_receive 真）。
## 期待: V3b ではボタンの枠 ReceiveSlot は出さない（V3c で足す）。画面の値には offer が残る。
func test_receive_slot_stays_hidden_in_v3b() -> void:
	_repository.replace_calendars(
		LoginBonusCalendars.new(
			LoginBonusCalendar.new("lb", 4, true, false),
			LoginBonusCalendar.new("vip", 4, true, false, true, 3)
		)
	)
	var p := await _show()
	assert_bool(p.current_screen.receive_offer.visible).is_true()
	assert_bool((_node(p, "ReceiveSlot") as Control).visible).is_false()
	assert_int(_node(p, "ReceiveSlot").get_child_count()).is_equal(0)


## 前提: 画面を開く。期待: マスターを引く窓口（Prepare）へメモリの進捗がそのまま渡る（通信は偽なのでしない）。
func test_prepare_receives_repository_calendars() -> void:
	FX.put_granted_now(_repository, 2)
	var made := FX.make(self, _router, FX.masters(), _repository)
	auto_free(made[0])
	await get_tree().process_frame
	var prepare: LoginBonusScreenFixtures.FakePrepare = made[2]
	assert_int(prepare.received.size()).is_equal(1)
	assert_object(prepare.received[0]).is_same(_repository.calendars())


## 前提: マスターを引く窓口が待っている（再取得中）。
## 期待: 「読み込み中…」が出て段・行は隠れ、終わると消えてカレンダーが出る。待っている間もタップでホームへ戻れる。
func test_loading_label_while_master_is_prepared() -> void:
	FX.put_granted_now(_repository, 2)
	var release := LoginBonusScreenFixtures.GateSource.new()
	var made := FX.make(self, _router, FX.masters(), _repository, release.opened)
	var p: LoginBonusPresenter = auto_free(made[0])
	await get_tree().process_frame
	var status := _node(p, "StatusLabel") as Label
	assert_bool(status.visible).is_true()
	assert_str(status.text).is_equal("読み込み中…")
	assert_bool((_node(p, "NormalSection") as Control).visible).is_false()
	release.opened.emit()
	await get_tree().process_frame
	assert_bool(status.visible).is_false()
	assert_bool((_node(p, "NormalSection") as Control).visible).is_true()


## 前提: render を 2 回呼ぶ（再描画。V3c の取り直しの想定）。
## 期待: 報酬の行・段の行・マスが重複せず、1 回目と同じ数のまま。
func test_render_twice_does_not_duplicate_children() -> void:
	FX.put_granted_now(_repository, 3)
	FX.put_rewards(_repository, 3)
	var p := await _show()
	p.render(p.current_screen)
	p.render(p.current_screen)
	await get_tree().process_frame
	assert_int(_node(p, "RewardsList").get_child_count()).is_equal(3)
	var normal := _node(p, "NormalSection") as CalendarSection
	assert_int(normal.get_node("Rows").get_child_count()).is_equal(2)
	assert_int(normal.cells.size()).is_equal(7)


# ------------------------------------------------ 文字の画面（今の build_text） ----


## 前提: 進捗なし・受取なし（旧サーバー・T4）。期待: 文字の画面で「受け取り済みです」・カレンダーは出ない。
func test_text_fallback_when_no_stage_empty() -> void:
	var p := await _show()
	var label := _node(p, "BonusBg/BonusLabel") as Label
	assert_str(label.text).contains("受け取り済みです")
	assert_bool((_node(p, "BonusBg") as Control).visible).is_true()
	assert_bool((_node(p, "NormalSection") as Control).visible).is_false()
	assert_bool(p.current_screen.use_text_fallback).is_true()


## 前提: 周期が 9 日（8 超）。期待: 画面全体を文字の画面にする（段は出ない）。報酬は文字に出る。
func test_text_fallback_when_cycle_over_eight() -> void:
	FX.put_granted_now(_repository, 3)
	FX.put_rewards(_repository, 1)
	var p := await _show(FX.masters(9, 7))
	assert_bool((_node(p, "NormalSection") as Control).visible).is_false()
	assert_bool((_node(p, "VipSection") as Control).visible).is_false()
	assert_str((_node(p, "BonusBg/BonusLabel") as Label).text).contains("x100")
	assert_bool((_node(p, "RewardsHeader") as Label).visible).is_false()


## 前提: 受取が 2 件（グレード付き / 無し）。期待: 種別・ID・数量が出て、グレードは付いている行だけ。
func test_text_shows_items_and_grade_only_when_present() -> void:
	var bonuses: Array[LoginBonus] = [
		LoginBonus.new("u1", "gold", "gold", 100, "", {"is_paid": true}),
		LoginBonus.new("u2", "unit", "7", 1, "", {"grade": 3}),
	]
	_repository.replace(bonuses)
	var p := await _show()
	var text := (_node(p, "BonusBg/BonusLabel") as Label).text
	assert_str(text).contains("ゴールド (ID:gold) x100")
	assert_str(text).contains("ユニット (ID:7) グレード3 x1")
	assert_str(text).not_contains("グレード1")


# ------------------------------------------------ タップ（閉じる操作） ----


## 前提: アニメーションの無い画面（再表示）。期待: タップでホームへ 1 回。連打しても 1 回。
func test_tap_goes_home_once() -> void:
	_repository.replace_calendars(
		LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 4, true, false))
	)
	var p := await _show()
	_tap(p)
	_tap(p)
	assert_array(_router.calls).is_equal(["home"])


## 前提: タッチのタップ。期待: マウスと同じくホームへ（押した瞬間だけ。離したときは無視）。
func test_touch_tap_goes_home() -> void:
	_repository.replace_calendars(
		LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 4, true, false))
	)
	var p := await _show()
	var up := InputEventScreenTouch.new()
	up.pressed = false
	p.get_node("TapCatcher").gui_input.emit(up)
	assert_array(_router.calls).is_empty()
	var down := InputEventScreenTouch.new()
	down.pressed = true
	p.get_node("TapCatcher").gui_input.emit(down)
	assert_array(_router.calls).is_equal(["home"])


## 前提: 右ボタンのクリック。期待: 閉じない（左ボタンだけ）。
func test_right_click_does_not_close() -> void:
	var p := await _show()
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_RIGHT
	event.pressed = true
	p.get_node("TapCatcher").gui_input.emit(event)
	assert_array(_router.calls).is_empty()


## 前提: スタンプのアニメーション中。期待: 最初のタップは最終状態へ飛ぶだけで閉じない。次のタップでホームへ（K4）。
func test_tap_during_animation_skips_then_closes() -> void:
	FX.put_granted_now(_repository, 3)
	var p := await _show()
	var cell := (_node(p, "NormalSection") as CalendarSection).cells[2]
	assert_bool(cell.is_waiting_stamp).is_true()
	_tap(p)
	assert_array(_router.calls).is_empty()
	assert_bool(cell.is_waiting_stamp).is_false()
	assert_bool(cell.is_stamp_visible()).is_true()
	_tap(p)
	assert_array(_router.calls).is_equal(["home"])


## 前提: 画面を読み込み中にホームへ戻った（タップ）。期待: 応答が来ても画面を触らず、落ちない。
func test_leaving_during_loading_does_not_render() -> void:
	FX.put_granted_now(_repository, 2)
	var release := LoginBonusScreenFixtures.GateSource.new()
	var made := FX.make(self, _router, FX.masters(), _repository, release.opened)
	var p: LoginBonusPresenter = auto_free(made[0])
	await get_tree().process_frame
	_tap(p)
	assert_array(_router.calls).is_equal(["home"])
	release.opened.emit()
	await get_tree().process_frame
	assert_object(p.current_screen).is_null()


# ------------------------------------------------ タップを通す規則（mouse_filter） ----


## 前提: シーン全体。期待: TapCatcher より後ろの子孫の Control は、Button・ScrollContainer 以外すべて IGNORE
## （1 つでも STOP が漏れると、その範囲のタップが TapCatcher に届かず閉じなくなる。1-1）。TapCatcher 自身は STOP。
## 描画後（マス・行ができた後）の木を走査する。
func test_mouse_filter_rule_for_nodes_in_front_of_tap_catcher() -> void:
	FX.put_granted_now(_repository, 3)
	FX.put_rewards(_repository, 3)
	var p := await _show()
	assert_int((p.get_node("TapCatcher") as Control).mouse_filter).is_equal(
		Control.MOUSE_FILTER_STOP
	)
	var violations: Array[String] = []
	var catcher_index := p.get_node("TapCatcher").get_index()
	for i in range(catcher_index + 1, p.get_child_count()):
		_collect_stop_controls(p.get_child(i), violations)
	assert_array(violations).is_empty()


func _collect_stop_controls(node: Node, violations: Array[String]) -> void:
	if node is Control and not (node is Button or node is ScrollContainer):
		if (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
			violations.append(str(node.get_path()))
	for child in node.get_children():
		_collect_stop_controls(child, violations)
