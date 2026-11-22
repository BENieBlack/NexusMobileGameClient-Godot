## LoginBonusPresenter の再受け取りの成功・失敗のテスト（client_design.md 3-2〜3-4・6・9。V3c）。
## 入口・ボタンの表示・二重送信は login_bonus_receive_test。
##
## 確かめること:
##   - 成功後の再描画（VIP のスタンプの押し直し・通常は再生しない・行の追加が重複しない・ボタンが消える・所持数の反映）
##   - 失敗: 業務エラー（26001〜）はコードで分岐せず取り直す（「状態を更新しました」・新しい冪等キー）、通信断は同じキーで再送
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


# ------------------------------------------------ 成功 ----


## 前提: FROM_LOGIN（login の行 2 件・通常は今配った）。VIP の再受け取りに成功（報酬 1 件）。
## 期待: ボタンが消える・VIP の今日のマスのスタンプが外れて押し直し待ち（再生）・通常の今日のマスは再生しない・
##       行は login の 2 件の後ろに 1 件足して 3 件・冪等キーは作り直し・送ったキーと ID が正しい。
func test_success_from_login_restamps_vip_and_appends_row() -> void:
	FX.put_rewards(_repository, 2)
	_repository.replace_calendars(
		LoginBonusCalendars.new(
			LoginBonusCalendar.new("lb", 4, true, true),
			LoginBonusCalendar.new("vip", 4, true, true, true, 3)
		)
	)
	_calendar.receive_results = [FX.received(1)]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_calendar.receive_calls.size()).is_equal(1)
	assert_str(_calendar.receive_calls[0]["id"]).is_equal("vip")
	assert_str(_calendar.receive_calls[0]["key"]).is_not_empty()
	assert_bool(_button(p).visible).is_false()
	assert_bool((_node(p, "ReceiveSlot") as Control).visible).is_false()
	var vip_cell := _vip_cell(p)
	assert_bool(vip_cell.is_waiting_stamp).is_true()
	assert_bool(vip_cell.stamp_node().visible).is_true()
	assert_float(vip_cell.stamp_node().modulate.a).is_equal(0.0)
	assert_bool(_normal_cell(p).is_waiting_stamp).is_false()
	assert_bool(_normal_cell(p).is_stamp_visible()).is_true()
	assert_int(_node(p, "RewardsList").get_child_count()).is_equal(3)
	assert_bool((_node(p, "NoticeLabel") as Label).visible).is_false()


## 前提: 上の続き。期待: 押し直しの時間が過ぎると VIP のマスは押印済みになり、待ちが解ける（外れて → 押される）。
func test_restamp_finishes_with_stamp_visible() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.received()]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var cell := _vip_cell(p)
	assert_bool(cell.is_waiting_stamp).is_true()
	# 開始 0.3 秒 + スタンプ 0.4 秒 + 着地 0.1 秒の後
	await await_millis(1000)
	assert_bool(cell.is_waiting_stamp).is_false()
	assert_bool(cell.is_stamp_visible()).is_true()
	assert_float(cell.stamp_node().modulate.a).is_equal(1.0)


## 前提: FROM_HOME・再受け取りに成功。期待: 行は再受け取りの報酬だけ（FROM_HOME は行が無かったので新しく出る）。
func test_success_from_home_shows_only_new_rewards() -> void:
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(true))]
	_calendar.receive_results = [FX.received(2)]
	var made := await _open(true)
	var p: LoginBonusPresenter = made[0]
	assert_bool((_node(p, "RewardsHeader") as Label).visible).is_false()
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool((_node(p, "RewardsHeader") as Label).visible).is_true()
	assert_int(_node(p, "RewardsList").get_child_count()).is_equal(2)
	assert_bool(_button(p).visible).is_false()
	# 作り直しても段・マスが重複しない
	assert_int((_node(p, "VipSection") as CalendarSection).cells.size()).is_equal(7)
	assert_int((_node(p, "VipSection/Rows") as Control).get_child_count()).is_equal(2)


## 前提: 成功した後の「今日配られた報酬」の行・ヘッダー。期待: 表示され、潰れない（V3b の教訓）。
func test_success_labels_not_collapsed() -> void:
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(true))]
	_calendar.receive_results = [FX.received(1)]
	var made := await _open(true)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_visible_and_not_collapsed(_node(p, "RewardsHeader") as Control)
	var row := _node(p, "RewardsList").get_child(0)
	for child in row.get_children():
		if child is Label:
			_assert_visible_and_not_collapsed(child)


## 前提: 再受け取りの応答に updated_resources（コインの wallet・無償ダイヤの item・スタミナ）。
## 期待: 本物の ApplyUpdatedResourcesUseCase で PlayerRepository（ホームの所持数の元）に反映される（Q31）。
func test_success_applies_updated_resources_to_player() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	var result := FX.received()
	result.updated_resources = {
		"trx_wallet_list": [{"mst_item_id": "coin", "free_amount": 1500}],
		"trx_item_list": [{"mst_item_id": "free_diamond", "free_amount": 70}],
		"trx_stamina_list": [{"type": "normal", "current_stamina": 40}],
	}
	_calendar.receive_results = [result]
	var made := await _open(false)
	_button(made[0]).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var player: LocalPlayerRepository = made[1]
	var state := player.current()
	assert_int(int(state.trx_list("trx_wallet_list")[0]["free_amount"])).is_equal(1500)
	assert_int(int(state.trx_list("trx_item_list")[0]["free_amount"])).is_equal(70)
	assert_int(int(state.trx_list("trx_stamina_list")[0]["current_stamina"])).is_equal(40)


# ------------------------------------------------ 失敗 ----


## 前提: 受け取りが業務エラー（26001）。取り直し（list）では can_re_receive が偽になる。
## 期待: コードで分岐せず取り直す（list 1 回）・ボタンが消える・Toast「状態を更新しました」・アニメーションなし・
##       画面は壊れない（段・今日のマスは押印済み）。
func test_business_error_refreshes_and_hides_button() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.failed_receive(AppError.Kind.BUSINESS, 26001)]
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(false))]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_calendar.fetch_count).is_equal(1)
	assert_bool(_button(p).visible).is_false()
	assert_array(_toast.toasts).is_equal(["状態を更新しました"])
	assert_bool(_vip_cell(p).is_waiting_stamp).is_false()
	assert_bool(_vip_cell(p).is_stamp_visible()).is_true()
	# 画面を閉じられる（受け取り中のままにならない）
	_tap(p)
	assert_array(_router.calls).is_equal(["home"])


## 前提: 業務エラーの後、取り直しでも can_re_receive が真（別レベルの分など）。
## 期待: ボタンが出し直され、次の送信は前と違う冪等キー（299 は保存されるので同じキーでは古いエラーが返り続ける。3-4）。
func test_business_error_then_resend_uses_new_key() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.failed_receive(AppError.Kind.BUSINESS, 26001), FX.received()]
	_calendar.fetch_results = [FX.fetched(FX.offer_calendars(true))]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_button(p).visible).is_true()
	assert_bool(_button(p).disabled).is_false()
	_button(p).pressed.emit()
	await get_tree().process_frame
	assert_int(_calendar.receive_calls.size()).is_equal(2)
	assert_str(_calendar.receive_calls[1]["key"]).is_not_equal(_calendar.receive_calls[0]["key"])


## 前提: 業務エラーの後の取り直し（list）も失敗する。
## 期待: 今の表示は維持しつつボタンを消す（古い状態で押させない）・エラー文が出る（潰れない）・list に冪等キー無し（Fake は引数なし）。
func test_business_error_and_refresh_failure_hides_button_with_message() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.failed_receive(AppError.Kind.BUSINESS, 26002)]
	_calendar.fetch_results = [FX.failed_fetch(AppError.Kind.NETWORK)]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_button(p).visible).is_false()
	var message := _node(p, "ReceiveSlot/ReceiveMessageLabel") as Label
	_assert_visible_and_not_collapsed(message)
	assert_str(message.text).is_equal(ErrorMessages.text(AppError.new(AppError.Kind.NETWORK)))
	assert_bool((_node(p, "NormalSection") as Control).visible).is_true()
	assert_array(_toast.toasts).is_empty()


## 前提: 受け取りが通信断。期待: エラー文が出て（潰れない）ボタンが有効に戻り、再タップは同じキーで再送する
## （応答が届かなかっただけかもしれない。サーバーが先に処理していても二重に配らない。3-4）。その後成功すれば行が足される。
func test_network_error_keeps_key_and_resend_succeeds() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.failed_receive(AppError.Kind.NETWORK), FX.received()]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	var message := _node(p, "ReceiveSlot/ReceiveMessageLabel") as Label
	_assert_visible_and_not_collapsed(message)
	assert_str(message.text).is_equal(ErrorMessages.text(AppError.new(AppError.Kind.NETWORK)))
	assert_bool(_button(p).visible).is_true()
	assert_bool(_button(p).disabled).is_false()
	assert_str(_button(p).text).is_equal("受け取る")
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_calendar.receive_calls.size()).is_equal(2)
	assert_str(_calendar.receive_calls[1]["key"]).is_equal(_calendar.receive_calls[0]["key"])
	assert_bool(_button(p).visible).is_false()
	assert_bool(message.visible).is_false()
	assert_int(_calendar.fetch_count).is_equal(0)


## 前提: 受け取りが 503（SERVER_BUSY）。期待: 取り直さずエラー文＋ボタン有効（再試行できる失敗は同じキーのまま）。
func test_server_busy_does_not_refetch() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.failed_receive(AppError.Kind.SERVER_BUSY)]
	var made := await _open(false)
	_button(made[0]).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_calendar.fetch_count).is_equal(0)
	assert_bool(_button(made[0]).disabled).is_false()
	assert_array(_toast.toasts).is_empty()


## 受け取りの応答が SESSION_EXPIRED。期待: ボタンが消えて文が出る・待っている間は閉じるタップもボタンも効かない
## （ホームへ行かない）・待ち時間の後にタイトルへ 1 回だけ戻る（取得の失敗と同じ経路）。
func test_session_expired_on_receive_goes_to_title_without_home() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.failed_receive(AppError.Kind.SESSION_EXPIRED)]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	p.session_notice_sec = 0.3
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_button(p).visible).is_false()
	var message := _node(p, "ReceiveSlot/ReceiveMessageLabel") as Label
	_assert_visible_and_not_collapsed(message)
	assert_str(message.text).is_equal(
		ErrorMessages.text(AppError.new(AppError.Kind.SESSION_EXPIRED))
	)
	_tap(p)
	_button(p).pressed.emit()
	assert_array(_router.calls).is_empty()
	assert_int(_calendar.receive_calls.size()).is_equal(1)
	await await_millis(500)
	assert_array(_router.calls).is_equal(["title"])


## 業務エラーの後の取り直し（list）が SESSION_EXPIRED。期待: 受け取りの SESSION_EXPIRED と同じく、文を見せて
## ホームへは行かずタイトルへ戻る（ボタンを消すだけで止まらない）。
func test_session_expired_on_refresh_goes_to_title() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [FX.failed_receive(AppError.Kind.BUSINESS, 26001)]
	_calendar.fetch_results = [FX.failed_fetch(AppError.Kind.SESSION_EXPIRED)]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	p.session_notice_sec = 0.3
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_button(p).visible).is_false()
	assert_str((_node(p, "ReceiveSlot/ReceiveMessageLabel") as Label).text).contains("無効")
	_tap(p)
	assert_array(_router.calls).is_empty()
	await await_millis(500)
	assert_array(_router.calls).is_equal(["title"])
	assert_array(_toast.toasts).is_empty()


func _rate_limited(seconds: int) -> ReceiveVipLoginBonusResult:
	var error := AppError.new(AppError.Kind.RATE_LIMITED)
	error.retry_after = seconds
	return ReceiveVipLoginBonusResult.new(error)


## 429（retry_after 1 秒）。期待: ボタンが待ち時間だけ無効（文が出る）・その間に signal を直接出しても送らない・
## 待った後は有効に戻り、同じ冪等キーで再送できる（受け取り中のフラグとは競合しない）。
func test_rate_limit_locks_button_then_unlocks() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [_rate_limited(1), FX.received()]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_bool(_button(p).disabled).is_true()
	assert_bool(_button(p).visible).is_true()
	assert_str((_node(p, "ReceiveSlot/ReceiveMessageLabel") as Label).text).is_not_empty()
	_button(p).pressed.emit()
	assert_int(_calendar.receive_calls.size()).is_equal(1)
	await await_millis(1300)
	assert_bool(_button(p).disabled).is_false()
	_button(p).pressed.emit()
	await get_tree().process_frame
	assert_int(_calendar.receive_calls.size()).is_equal(2)
	assert_str(_calendar.receive_calls[1]["key"]).is_equal(_calendar.receive_calls[0]["key"])


## 429 のロック中に画面を離れる（解放）。期待: タイマーが切れても何も触らず落ちない。
func test_leaving_during_rate_limit_lock_is_safe() -> void:
	_repository.replace_calendars(FX.offer_calendars(true))
	_calendar.receive_results = [_rate_limited(1)]
	var made := await _open(false)
	var p: LoginBonusPresenter = made[0]
	_button(p).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	remove_child(p)
	p.queue_free()
	await await_millis(1300)
	assert_int(_calendar.receive_calls.size()).is_equal(1)
