## GetLoginBonusScreenUseCase の単体テスト（中核。client_design.md 1-3 の表の全行と要件 T1〜T5）。
## 偽の MstItemRepository・本物のメモリ保持（LocalLoginBonusRepository）で、段の状態・スタンプ・再表示の旨・
## 受け取りボタン・文字の画面への落とし方・報酬の並び・名前とアイコンの引きを確かめる。
extends GdUnitTestSuite


## 偽の mst_item。items は ID → {type, is_wallet, name}。引いた ID を記録する。
class FakeItems:
	extends MstItemRepository
	var items: Dictionary = {}
	var asked: Array[String] = []

	func get_by_id(id: String) -> MstItem:
		asked.append(id)
		if not items.has(id):
			return null
		var item := MstItem.new()
		item.id = id
		item.type = items[id].get("type", "")
		item.is_wallet = items[id].get("is_wallet", false)
		item.name = items[id].get("name", "")
		return item


var _repository: LocalLoginBonusRepository
var _items: FakeItems
var _use_case: GetLoginBonusScreenUseCase


func before_test() -> void:
	_repository = LocalLoginBonusRepository.new()
	_items = FakeItems.new()
	var displays := GetLoginBonusDisplaysUseCase.new(
		GetLoginBonusesUseCase.new(_repository), _items
	)
	_use_case = GetLoginBonusScreenUseCase.new(_repository, displays)


## 7 日の通常の段（各日 1 件の item）と、VIP の段（日数 vip_days）のマスターの束を作る。
func _masters(
	with_normal: bool = true, with_vip: bool = true, cycle: int = 7, vip_days: int = 7
) -> LoginBonusStageMasters:
	var masters := LoginBonusStageMasters.new()
	if with_normal:
		masters.normal = _stage(cycle, "a")
	if with_vip:
		masters.vip = _stage(vip_days, "v")
	return masters


func _stage(cycle: int, prefix: String) -> LoginBonusStageMaster:
	var entries: Array[Dictionary] = []
	for day in range(1, cycle + 1):
		entries.append(
			{
				"day": day,
				"type": "item",
				"id": "%s%d" % [prefix, day],
				"quantity": day * 10,
				"metadata": {}
			}
		)
	return LoginBonusStageMasterReader.build_stage(cycle, entries)


func _put_calendars(normal: LoginBonusCalendar, vip: LoginBonusCalendar = null) -> void:
	_repository.replace_calendars(LoginBonusCalendars.new(normal, vip))


func _states(stage: CalendarStageView) -> Array:
	var states := []
	for cell in stage.cells:
		states.append(cell.state)
	return states


# ------------------------------------------------ 今日の段（T1・T2） ----


## 前提: 今日の段（is_granted_today 真）で last_day が 1・中間・最終日。
## 期待: last_day のマスが TODAY、それ以前が RECEIVED、それより後が FUTURE。
func test_today_stage_marks_today_received_and_future() -> void:
	for last_day in [1, 4, 7]:
		_put_calendars(LoginBonusCalendar.new("lb1", last_day, true))
		var stage := _use_case.handle(_masters(), true, true).normal
		assert_bool(stage.is_today_stage).is_true()
		assert_int(stage.cells.size()).is_equal(7)
		for cell in stage.cells:
			var expected := CalendarCellView.State.FUTURE
			if cell.day == last_day:
				expected = CalendarCellView.State.TODAY
			elif cell.day < last_day:
				expected = CalendarCellView.State.RECEIVED
			assert_int(cell.state).is_equal(expected)


## 前提: 今日の段でない（is_granted_today 偽。last_day は過去の値のまま）。
## 期待: 全マス NEUTRAL（強調・スタンプ・未来の暗さ無し）。段は隠さない（T2）。
func test_not_today_stage_is_all_neutral_and_not_hidden() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 3, false, false))
	var screen := _use_case.handle(_masters(), false, true)
	assert_object(screen.normal).is_not_null()
	assert_bool(screen.normal.is_today_stage).is_false()
	for state in _states(screen.normal):
		assert_int(state).is_equal(CalendarCellView.State.NEUTRAL)
	for cell in screen.normal.cells:
		assert_bool(cell.play_stamp).is_false()


## 前提: is_granted_today が真でも last_day が範囲外（0・8・周期を縮めた直後）。期待: 今日の段でない扱い。
func test_out_of_range_last_day_is_not_today_stage() -> void:
	for last_day in [0, 8, 100]:
		_put_calendars(LoginBonusCalendar.new("lb1", last_day, true, true))
		var stage := _use_case.handle(_masters(), true, true).normal
		assert_bool(stage.is_today_stage).is_false()
		for cell in stage.cells:
			assert_int(cell.state).is_equal(CalendarCellView.State.NEUTRAL)
			assert_bool(cell.play_stamp).is_false()


## 前提: サイクルが 1 周した後（last_day = 1。前のサイクルの 7 日目の後）。
## 期待: 前サイクルのスタンプを引き継がず、1 日目だけ今日で他は未来。
func test_after_cycle_wrap_does_not_carry_previous_stamps() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true, true))
	var cells := _use_case.handle(_masters(), true, true).normal.cells
	assert_int(cells[0].state).is_equal(CalendarCellView.State.TODAY)
	for i in range(1, 7):
		assert_int(cells[i].state).is_equal(CalendarCellView.State.FUTURE)


# ------------------------------------------------ スタンプ（T5） ----


## 前提: is_granted_now の真・偽、再生の許可の有無。
## 期待: play_stamp は「今日の段 かつ is_granted_now かつ今日のマス かつ許可」のときだけ、今日のマスだけ真。
func test_play_stamp_only_on_today_cell_when_granted_now_and_allowed() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 3, true, true))
	var cells := _use_case.handle(_masters(), true, true).normal.cells
	for cell in cells:
		assert_bool(cell.play_stamp).is_equal(cell.day == 3)
	# FROM_HOME の最初の描画（許可なし）では再生しない
	for cell in _use_case.handle(_masters(), false, false).normal.cells:
		assert_bool(cell.play_stamp).is_false()
	# is_granted_now が偽（再表示）なら今日のマスも押印済みで再生しない
	_put_calendars(LoginBonusCalendar.new("lb1", 3, true, false))
	for cell in _use_case.handle(_masters(), true, true).normal.cells:
		assert_bool(cell.play_stamp).is_false()


## 前提: 再受け取りの成功後の描画（VIP だけ is_granted_now。通常も login で真のまま）。
## 期待: play_stamp_normal = false で通常の段は再生せず、VIP の今日のマスだけ再生する。
func test_play_stamp_normal_flag_keeps_normal_stage_silent() -> void:
	_put_calendars(
		LoginBonusCalendar.new("lb1", 2, true, true), LoginBonusCalendar.new("vip5", 2, true, true)
	)
	var screen := _use_case.handle(_masters(), true, true, false)
	for cell in screen.normal.cells:
		assert_bool(cell.play_stamp).is_false()
	assert_bool(screen.vip.cells[1].play_stamp).is_true()
	assert_bool(screen.vip.cells[0].play_stamp).is_false()


# ------------------------------------------------ 段の有無・文字の画面 ----


## 前提: 通常だけ・VIP だけ・両方。期待: 無い段は null、ある段だけ表示値になる。VIP の見出しのレベルが入る。
func test_normal_only_vip_only_and_both() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true))
	var normal_only := _use_case.handle(_masters(true, false), true, true)
	assert_object(normal_only.normal).is_not_null()
	assert_object(normal_only.vip).is_null()
	assert_bool(normal_only.use_text_fallback).is_false()

	_put_calendars(null, LoginBonusCalendar.new("vip5", 2, true, false, false, 5))
	var vip_only := _use_case.handle(_masters(false, true), true, true)
	assert_object(vip_only.normal).is_null()
	assert_bool(vip_only.vip.is_vip).is_true()
	assert_int(vip_only.vip.vip_level).is_equal(5)

	_put_calendars(
		LoginBonusCalendar.new("lb1", 1, true),
		LoginBonusCalendar.new("vip5", 2, true, false, false, 5)
	)
	var both := _use_case.handle(_masters(), true, true)
	assert_object(both.normal).is_not_null()
	assert_object(both.vip).is_not_null()
	assert_int(both.normal.vip_level).is_equal(0)


## 前提: どちらの段も無い（T4・旧サーバー）。期待: 文字の画面（NO_STAGE）。login_bonus_list は文字用に載る。
func test_no_stage_falls_back_to_text_with_rewards() -> void:
	var bonuses: Array[LoginBonus] = [LoginBonus.new("u", "gold", "gold", 100)]
	_repository.replace(bonuses)
	var screen := _use_case.handle(_masters(false, false), true, true)
	assert_bool(screen.use_text_fallback).is_true()
	assert_int(screen.fallback_reason).is_equal(LoginBonusScreen.FallbackReason.NO_STAGE)
	assert_int(screen.rewards.size()).is_equal(1)


## 前提: 周期の日数が 8 超・1 未満（片方の段だけでも）。期待: 画面全体を文字の画面にする（段ごとには落とさない）。
func test_cycle_out_of_range_falls_back_whole_screen() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true), LoginBonusCalendar.new("vip5", 1, true))
	var screen := _use_case.handle(_masters(true, true, 7, 9), true, true)
	assert_bool(screen.use_text_fallback).is_true()
	assert_int(screen.fallback_reason).is_equal(LoginBonusScreen.FallbackReason.CYCLE_OUT_OF_RANGE)
	assert_object(screen.normal).is_null()
	var zero := _use_case.handle(_masters(true, true, 0, 7), true, true)
	assert_int(zero.fallback_reason).is_equal(LoginBonusScreen.FallbackReason.CYCLE_OUT_OF_RANGE)


## 前提: 両段の進捗があり、片方のマスターだけ引ける。期待: 引けた段だけ表示し、引けない段は出さない
## （VIP を引けないなら受け取りボタンも出さない）。文字の画面にはしない。
func test_only_stage_with_master_is_shown() -> void:
	_put_calendars(
		LoginBonusCalendar.new("lb1", 1, true),
		LoginBonusCalendar.new("vip5", 1, true, false, true, 5)
	)
	var normal_only := _use_case.handle(_masters(true, false), true, true)
	assert_bool(normal_only.use_text_fallback).is_false()
	assert_object(normal_only.normal).is_not_null()
	assert_object(normal_only.vip).is_null()
	assert_bool(normal_only.receive_offer.visible).is_false()
	var vip_only := _use_case.handle(_masters(false, true), true, true)
	assert_bool(vip_only.use_text_fallback).is_false()
	assert_object(vip_only.normal).is_null()
	assert_object(vip_only.vip).is_not_null()
	assert_bool(vip_only.receive_offer.visible).is_true()


## 前提: 進捗のある段のマスターが両方引けない・masters が null。期待: 文字の画面（MASTER_UNAVAILABLE）。
## 片方の進捗だけで、その段が引けないときも出せる段が無いので文字の画面。
func test_no_displayable_stage_falls_back_to_text() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true), LoginBonusCalendar.new("vip5", 1, true))
	var screen := _use_case.handle(_masters(false, false), true, true)
	assert_bool(screen.use_text_fallback).is_true()
	assert_int(screen.fallback_reason).is_equal(LoginBonusScreen.FallbackReason.MASTER_UNAVAILABLE)
	assert_bool(_use_case.handle(null, true, true).use_text_fallback).is_true()
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true))
	assert_bool(_use_case.handle(_masters(false, true), true, true).use_text_fallback).is_true()


# ------------------------------------------------ 再表示の旨（T3・U-3）・行・ボタン ----


## 前提: 今日の段でどの段も is_granted_now が偽 → 旨を出す。is_granted_now が真 → 出さない。
## どの段も今日の段でない → 出さない。片方が今日の段（もう片方は今日でない）→ 出す。
func test_received_notice_conditions() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 2, true, false))
	(
		assert_bool(_use_case.handle(_masters(true, false), false, false).show_received_notice)
		. is_true()
	)
	_put_calendars(LoginBonusCalendar.new("lb1", 2, true, true))
	assert_bool(_use_case.handle(_masters(true, false), true, true).show_received_notice).is_false()
	_put_calendars(
		LoginBonusCalendar.new("lb1", 2, false), LoginBonusCalendar.new("vip5", 2, false)
	)
	assert_bool(_use_case.handle(_masters(), false, false).show_received_notice).is_false()
	_put_calendars(
		LoginBonusCalendar.new("lb1", 2, true, false), LoginBonusCalendar.new("vip5", 2, false)
	)
	assert_bool(_use_case.handle(_masters(), false, false).show_received_notice).is_true()
	# 通常が今回配られた（真）ときは、VIP が再表示でも旨を出さない（どの段も is_granted_now が偽、ではない）
	_put_calendars(
		LoginBonusCalendar.new("lb1", 2, true, true), LoginBonusCalendar.new("vip5", 2, true, false)
	)
	assert_bool(_use_case.handle(_masters(), true, true).show_received_notice).is_false()


## 前提: login_bonus_list が非空（カムバックだけ配った日を含む）。
## 期待: FROM_LOGIN（include 真）は全行を受け取った順で出す。FROM_HOME（偽）は出さない。
## 再表示の判定は login_bonus_list の空・非空に依存しない（T3）。
func test_rewards_rows_follow_include_flag_and_not_the_notice() -> void:
	var bonuses: Array[LoginBonus] = [
		LoginBonus.new("u1", "item", "comeback", 1),
		LoginBonus.new("u2", "item", "a2", 20),
	]
	_repository.replace(bonuses)
	_put_calendars(LoginBonusCalendar.new("lb1", 2, true, false))
	var login := _use_case.handle(_masters(true, false), true, true)
	assert_int(login.rewards.size()).is_equal(2)
	assert_str(login.rewards[0].bonus.id).is_equal("comeback")
	assert_str(login.rewards[1].bonus.id).is_equal("a2")
	# カムバックだけ配った日でも、今日の段で is_granted_now が偽なら再表示の旨は出る
	assert_bool(login.show_received_notice).is_true()
	assert_array(_use_case.handle(_masters(true, false), false, false).rewards).is_empty()


## 前提: VIP の can_re_receive が真・偽・段の ID が空。期待: 真で ID があるときだけボタンが出て、ID を持つ。
func test_receive_offer_only_when_can_re_receive() -> void:
	_put_calendars(
		LoginBonusCalendar.new("lb1", 1, true),
		LoginBonusCalendar.new("vip5", 1, true, false, true, 5)
	)
	var offer := _use_case.handle(_masters(), true, true).receive_offer
	assert_bool(offer.visible).is_true()
	assert_str(offer.mst_vip_login_bonus_id).is_equal("vip5")
	_put_calendars(
		LoginBonusCalendar.new("lb1", 1, true),
		LoginBonusCalendar.new("vip5", 1, true, false, false, 5)
	)
	assert_bool(_use_case.handle(_masters(), true, true).receive_offer.visible).is_false()
	# 通常の段には can_re_receive の概念が無い（VIP が無ければボタンも無い）
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true, false, true))
	(
		assert_bool(_use_case.handle(_masters(true, false), true, true).receive_offer.visible)
		. is_false()
	)


# ------------------------------------------------ マスの中身 ----


## 前提: 1 日に複数の報酬（マスターの並び = sort_desc 降順）。期待: 先頭が絵と数量、「＋n」は件数 − 1。
## 報酬の無い日は is_empty（絵なし・数量 0）。
func test_cell_uses_first_reward_and_counts_extras() -> void:
	var entries: Array[Dictionary] = [
		{"day": 1, "type": "item", "id": "first", "quantity": 7, "metadata": {}},
		{"day": 1, "type": "wallet", "id": "gold", "quantity": 9, "metadata": {}},
		{"day": 1, "type": "unit", "id": "u", "quantity": 1, "metadata": {}},
	]
	var masters := LoginBonusStageMasters.new()
	masters.normal = LoginBonusStageMasterReader.build_stage(2, entries)
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true))
	var cells := _use_case.handle(masters, true, true).normal.cells
	assert_str(cells[0].icon_id).is_equal("first")
	assert_int(cells[0].quantity).is_equal(7)
	assert_int(cells[0].extra_count).is_equal(2)
	assert_int(cells[0].rewards.size()).is_equal(3)
	assert_bool(cells[0].is_empty).is_false()
	assert_bool(cells[1].is_empty).is_true()
	assert_int(cells[1].quantity).is_equal(0)
	assert_str(cells[1].icon_id).is_empty()


## 前提: マスターの報酬が item（mst_item あり）・wallet（is_wallet の行）・unit・未知の種別。
## 期待: item・wallet は mst_item を引いて type・is_wallet・名前を載せる。unit は引かない。
## 未知の種別も報酬として残る（画面が unknown の絵で出す）。
func test_cell_rewards_look_up_mst_item_for_item_and_wallet_only() -> void:
	_items.items = {
		"potion": {"type": "recovery", "name": "ポーション"},
		"gold": {"type": "currency", "is_wallet": true, "name": "ゴールド"},
	}
	var entries: Array[Dictionary] = [
		{"day": 1, "type": "item", "id": "potion", "quantity": 1, "metadata": {}},
		{"day": 2, "type": "wallet", "id": "gold", "quantity": 500, "metadata": {}},
		{"day": 3, "type": "unit", "id": "u1", "quantity": 1, "metadata": {}},
		{"day": 4, "type": "mystery", "id": "m", "quantity": 1, "metadata": {}},
	]
	var masters := LoginBonusStageMasters.new()
	masters.normal = LoginBonusStageMasterReader.build_stage(4, entries)
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true))
	var cells := _use_case.handle(masters, true, true).normal.cells
	assert_str(cells[0].icon_mst_item_type).is_equal("recovery")
	assert_str(cells[0].rewards[0].item_name).is_equal("ポーション")
	assert_str(cells[1].icon_type).is_equal("wallet")
	assert_str(cells[1].icon_mst_item_type).is_equal("currency")
	assert_bool(cells[1].rewards[0].is_wallet).is_true()
	# wallet の行も、報酬の行（今日配られた報酬）と同じく mst_item の名前を載せる（「(ID:…)」は引けないときだけ）
	assert_str(cells[1].rewards[0].item_name).is_equal("ゴールド")
	assert_str(cells[2].icon_mst_item_type).is_empty()
	assert_bool(_items.asked.has("u1")).is_false()
	assert_str(cells[3].icon_type).is_equal("mystery")


## 前提: FROM_LOGIN（login の行 1 件）に、再受け取りの報酬 2 件を extra_rewards で渡す。
## 期待: 行は login の 1 件の後ろに 2 件足されて 3 件（受け取った順）。メモリの login_bonus_list は変わらない。
func test_extra_rewards_are_appended_after_login_rows() -> void:
	var bonuses: Array[LoginBonus] = [LoginBonus.new("u", "item", "a", 100)]
	_repository.replace(bonuses)
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true, true), null)
	var extra: Array[LoginBonus] = [
		LoginBonus.new("", "item", "b", 200), LoginBonus.new("", "item", "c", 300)
	]
	var screen := _use_case.handle(_masters(), true, true, false, extra)
	assert_int(screen.rewards.size()).is_equal(3)
	assert_str(screen.rewards[0].bonus.id).is_equal("a")
	assert_str(screen.rewards[2].bonus.id).is_equal("c")
	assert_int(_repository.calendars().normal.last_day).is_equal(1)


## 前提: FROM_HOME（include 偽）で extra_rewards を渡す。期待: 行は再受け取りの報酬だけ（Q-3）。
func test_extra_rewards_alone_when_from_home() -> void:
	_put_calendars(LoginBonusCalendar.new("lb1", 1, true, false), null)
	var extra: Array[LoginBonus] = [LoginBonus.new("", "item", "b", 200)]
	var screen := _use_case.handle(_masters(), false, true, false, extra)
	assert_int(screen.rewards.size()).is_equal(1)
	assert_str(screen.rewards[0].bonus.id).is_equal("b")
