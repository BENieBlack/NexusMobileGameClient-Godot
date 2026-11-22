## HomePresenter（ホーム画面）の表示のテスト（client_design.md 1-3 の状態表・3-4）。
## UseCase には本物を使い、Repository と時計だけ偽物にする（時計は固定）。
extends GdUnitTestSuite

const HOME_SCENE := "res://contexts/player/presentation/home/home.tscn"
const T0 := 1_800_000_000
const LAST_AT := "2027-01-15 08:00:00"
const NAME := "Margin/Root/PlayerPanel/VBox/NameLabel"
const ID := "Margin/Root/PlayerPanel/VBox/Row/IdLabel"
const LEVEL := "Margin/Root/PlayerPanel/VBox/Row/LevelLabel"
const STAMINA := "Margin/Root/StaminaPanel/VBox/ValueRow/StaminaValueLabel"
const REMAIN := "Margin/Root/StaminaPanel/VBox/StaminaRemainLabel"
const COIN := "Margin/Root/CurrencyRow/CoinPanel/VBox/ValueRow/CoinValueLabel"
const DIAMOND := "Margin/Root/CurrencyRow/DiamondPanel/VBox/ValueRow/DiamondValueLabel"

var _clock: FakeMstRepositories.FixedClock
var _levels: FakeMstRepositories.Level
var _config: FakeMstRepositories.Config
var _repository: LocalPlayerRepository
var _loaded := Signal()


func before_test() -> void:
	_clock = FakeMstRepositories.FixedClock.new()
	_clock.now = ServerDatetime.parse_to_unix(LAST_AT)
	_levels = FakeMstRepositories.Level.new()
	_levels.rows[1] = 50
	_config = FakeMstRepositories.Config.new()
	_config.put_int("stamina_recovery_interval_seconds", "300")
	_repository = LocalPlayerRepository.new()


func _login(sys_player: Dictionary, lists: Dictionary, diamond: Dictionary = {}) -> void:
	_repository.replace(PlayerState.new(sys_player, lists, diamond))


func _stamina(current: int) -> Dictionary:
	return {
		"trx_stamina_list":
		[
			{
				"type": "normal",
				"current_stamina": current,
				"last_recovery_at": LAST_AT,
				"recovery_rate_multiplier": "1.00",
			}
		]
	}


func _show_home(master_loaded: Signal = Signal()) -> HomePresenter:
	var screen: HomePresenter = load(HOME_SCENE).instantiate()
	screen.setup(
		GetHomeSummaryUseCase.new(_repository, _levels, _config),
		GetStaminaDisplayUseCase.new(_repository, _clock),
		master_loaded
	)
	add_child(auto_free(screen))
	await get_tree().process_frame
	return screen


func _text(screen: Node, path: String) -> String:
	return (screen.get_node(path) as Label).text


## 前提: 全項目が揃った新規ユーザー（スタミナ 50 / 50・コイン 1000・ダイヤ 50）。期待: 設計 8-3 のケース 1 の表示。
func test_shows_full_player() -> void:
	var lists := _stamina(50)
	lists["trx_wallet_list"] = [{"mst_item_id": "coin", "free_amount": 1000}]
	lists["trx_item_list"] = [{"mst_item_id": "free_diamond", "free_amount": 50}]
	_login({"my_id": "ABCD1234", "name": "taro", "level": 1}, lists)
	var screen := await _show_home()
	assert_str(_text(screen, NAME)).is_equal("taro")
	assert_str(_text(screen, ID)).is_equal("ID: ABCD1234")
	assert_str(_text(screen, LEVEL)).is_equal("Lv.1")
	assert_str(_text(screen, STAMINA)).is_equal("50 / 50")
	assert_str(_text(screen, REMAIN)).is_equal("")
	assert_str(_text(screen, COIN)).is_equal("1,000")
	assert_str(_text(screen, DIAMOND)).is_equal("50")
	assert_bool((screen.get_node("StaminaTimer") as Timer).is_stopped()).is_true()


## 前提: 未ログイン。期待: 名前の位置に「ログインしていません」、ほかは「-」。タイマーは止まる。
func test_not_logged_in() -> void:
	var screen := await _show_home()
	assert_str(_text(screen, NAME)).is_equal("ログインしていません")
	for path in [ID, LEVEL, STAMINA, COIN, DIAMOND]:
		assert_str(_text(screen, path)).is_equal("-")
	assert_bool((screen.get_node("StaminaTimer") as Timer).is_stopped()).is_true()


## 前提: 名前が null / 空・level なし・Coin 行なし。期待: 「名前なし」・「Lv.-」・コイン 0。
func test_name_missing_level_missing_no_coin_row() -> void:
	_login({"my_id": "a", "name": null}, {})
	var screen := await _show_home()
	assert_str(_text(screen, NAME)).is_equal("名前なし")
	assert_str(_text(screen, LEVEL)).is_equal("Lv.-")
	assert_str(_text(screen, COIN)).is_equal("0")
	assert_str(_text(screen, DIAMOND)).is_equal("0")
	assert_str(_text(screen, STAMINA)).is_equal("-")


## 前提: 起点から 100 秒経過・42 / 50。期待: 「42 / 50」と残り 200 秒（03:20）。タイマーが動く。
func test_recovering_shows_remaining_time_and_runs_timer() -> void:
	_clock.now += 100
	_login({"my_id": "a", "level": 1}, _stamina(42))
	var screen := await _show_home()
	assert_str(_text(screen, STAMINA)).is_equal("42 / 50")
	assert_str(_text(screen, REMAIN)).is_equal("次の回復まで 03:20")
	assert_bool((screen.get_node("StaminaTimer") as Timer).is_stopped()).is_false()


## 前提: 回復中に時間が進み、最大値に達する。期待: tick で増え、50 / 50 で残り時間が消えてタイマーが止まる。
func test_tick_updates_and_stops_at_max() -> void:
	_login({"my_id": "a", "level": 1}, _stamina(49))
	var screen := await _show_home()
	_clock.now += 300
	screen.refresh_stamina()
	assert_str(_text(screen, STAMINA)).is_equal("50 / 50")
	assert_str(_text(screen, REMAIN)).is_equal("")
	assert_bool((screen.get_node("StaminaTimer") as Timer).is_stopped()).is_true()


## 前提: 現在値 55 > 最大 50。期待: 「55 / 50」（丸めない）で、残り時間なし・タイマー停止。
func test_over_max() -> void:
	_clock.now += 100000
	_login({"my_id": "a", "level": 1}, _stamina(55))
	var screen := await _show_home()
	assert_str(_text(screen, STAMINA)).is_equal("55 / 50")
	assert_bool((screen.get_node("StaminaTimer") as Timer).is_stopped()).is_true()


## 前提: 最大値が分からない（mst_player_level なし）。期待: 「42 / --」・回復なし・タイマー停止。
func test_max_unknown() -> void:
	_levels.rows.clear()
	_clock.now += 100000
	_login({"my_id": "a", "level": 1, "name": "x"}, _stamina(42))
	var screen := await _show_home()
	assert_str(_text(screen, STAMINA)).is_equal("42 / --")
	assert_str(_text(screen, REMAIN)).is_equal("")
	assert_str(_text(screen, NAME)).is_equal("x")
	assert_bool((screen.get_node("StaminaTimer") as Timer).is_stopped()).is_true()


## 前提: 回復間隔が分からない（mst_config なし）。期待: 「42 / 50」のまま増えない・残り時間なし。
func test_interval_unknown() -> void:
	_config.rows.clear()
	_clock.now += 100000
	_login({"my_id": "a", "level": 1}, _stamina(42))
	var screen := await _show_home()
	assert_str(_text(screen, STAMINA)).is_equal("42 / 50")
	assert_str(_text(screen, REMAIN)).is_equal("")


## 前提: 最大値が分からない状態で開き、その後マスターが更新される（master_data_loaded）。
## 期待: 通知で表示値を作り直し、「42 / 50」になって回復が動き出す。
func test_master_update_reloads() -> void:
	var holder := CheckMasterDataUseCaseHolder.new()
	_levels.rows.clear()
	_login({"my_id": "a", "level": 1}, _stamina(42))
	var screen := await _show_home(holder.master_data_loaded)
	assert_str(_text(screen, STAMINA)).is_equal("42 / --")
	_levels.rows[1] = 50
	holder.master_data_loaded.emit()
	assert_str(_text(screen, STAMINA)).is_equal("42 / 50")
	assert_bool((screen.get_node("StaminaTimer") as Timer).is_stopped()).is_false()


## 前提: ホームを閉じる（ツリーから外れる）。期待: タイマーが止まり、master_data_loaded の購読が外れる。
func test_exit_tree_cleans_up() -> void:
	var holder := CheckMasterDataUseCaseHolder.new()
	_login({"my_id": "a", "level": 1}, _stamina(42))
	var screen := await _show_home(holder.master_data_loaded)
	var timer := screen.get_node("StaminaTimer") as Timer
	assert_bool(timer.is_stopped()).is_false()
	remove_child(screen)
	assert_bool(timer.is_stopped()).is_true()
	assert_int(holder.master_data_loaded.get_connections().size()).is_equal(0)
	screen.free()


## 復帰通知（RESUMED / FOCUS_IN）。期待: 経過した分をその場で一度に反映する。
func test_resume_recalculates_immediately() -> void:
	_login({"my_id": "a", "level": 1}, _stamina(40))
	var screen := await _show_home()
	_clock.now += 300 * 3
	screen.notification(NOTIFICATION_APPLICATION_RESUMED)
	assert_str(_text(screen, STAMINA)).is_equal("43 / 50")
	_clock.now += 300
	screen.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_str(_text(screen, STAMINA)).is_equal("44 / 50")


## 前提: 導線ボタン。期待: 「メール」「お知らせ」と、数字のないバッジ枠（子の Label なし）。押下の接続はなし。
func test_nav_buttons_and_badges() -> void:
	_login({"my_id": "a"}, {})
	var screen := await _show_home()
	var mail := screen.get_node("Margin/Root/NavRow/MailButton") as Button
	var notice := screen.get_node("Margin/Root/NavRow/NoticeButton") as Button
	assert_str(mail.text).is_equal("メール")
	assert_str(notice.text).is_equal("お知らせ")
	assert_int(mail.pressed.get_connections().size()).is_equal(0)
	assert_int(notice.pressed.get_connections().size()).is_equal(0)
	assert_int(mail.get_node("MailBadge").get_child_count()).is_equal(0)
	assert_int(notice.get_node("NoticeBadge").get_child_count()).is_equal(0)
	assert_float(mail.custom_minimum_size.y).is_greater_equal(160.0)


## master_data_loaded と同じ形のシグナルを持つだけの入れ物（CheckMasterDataUseCase を組み立てずに済ませる）。
class CheckMasterDataUseCaseHolder:
	extends RefCounted
	signal master_data_loaded


## レイアウト: 1080x1920 と 720x1280 のビューポートで、全項目が画面内に収まり、互いに重ならず、
## 左右の余白が一定。注意: ヘッドレスのレイアウトは実機と差が出うる（フォントの実寸など）。最終確認は画面で行う。
## このテストは実機の確認の代わりにならない（長い名前・大きな数字の折り返しは実機のフォントで確かめる）。
## 過去の見切れ（デスクトップの get_display_safe_area がモニター座標を返した）も、このテストでは検出できなかった。
func test_layout_fits_in_viewport() -> void:
	var lists := _stamina(42)
	lists["trx_wallet_list"] = [{"mst_item_id": "coin", "free_amount": 999999999}]
	lists["trx_item_list"] = [{"mst_item_id": "free_diamond", "free_amount": 999999999}]
	_login({"my_id": "ABCD1234", "name": "ながいなまえのひと", "level": 100}, lists)
	for size in [Vector2i(1080, 1920), Vector2i(720, 1280)]:
		var viewport := SubViewport.new()
		viewport.size = size
		viewport.disable_3d = true
		add_child(auto_free(viewport))
		var screen: HomePresenter = load(HOME_SCENE).instantiate()
		screen.setup(
			GetHomeSummaryUseCase.new(_repository, _levels, _config),
			GetStaminaDisplayUseCase.new(_repository, _clock)
		)
		viewport.add_child(screen)
		for i in range(3):
			await get_tree().process_frame
		var bounds := Rect2(Vector2.ZERO, Vector2(size))
		var paths := [
			"Margin/Root/PlayerPanel",
			"Margin/Root/StaminaPanel",
			"Margin/Root/CurrencyRow/CoinPanel",
			"Margin/Root/CurrencyRow/DiamondPanel",
			"Margin/Root/NavRow/MailButton",
			"Margin/Root/NavRow/NoticeButton",
			"Margin/Root/NavRow/LoginBonusButton",
			"Margin/Root/NavRow/MailButton/MailBadge",
			"Margin/Root/NavRow/NoticeButton/NoticeBadge",
		]
		var rects: Dictionary = {}
		for path in paths:
			var rect := (screen.get_node(path) as Control).get_global_rect()
			rects[path] = rect
			(
				assert_bool(bounds.encloses(rect))
				. override_failure_message("%s が画面外: %s (%s)" % [path, rect, size])
				. is_true()
			)
		# 縦に並ぶ 4 つ（プレイヤー・スタミナ・通貨・導線）は重ならず、上から順
		var column := [rects[paths[0]], rects[paths[1]], rects[paths[2]], rects[paths[4]]]
		for i in range(column.size() - 1):
			assert_float(column[i].end.y).is_less_equal(column[i + 1].position.y)
		# 左右の余白が一定（プレイヤーパネルの左端 = 48、右端 = 幅 - 48）
		assert_float(rects[paths[0]].position.x).is_equal_approx(48.0, 0.5)
		assert_float(rects[paths[0]].end.x).is_equal_approx(size.x - 48.0, 0.5)
		assert_float(rects[paths[4]].size.y).is_greater_equal(160.0)
		viewport.queue_free()


## 前提: ログイン済みのホーム。期待: スタミナ・コイン・ダイヤの値の横に ItemIcon が 1 つずつ在り、固定の ID の絵が入って
## 大きさは 48（client_design.md 5-5。無償ダイヤは合計用の絵を作らず free_diamond）。値の文字は従来のまま。
func test_value_icons_are_shown_with_fixed_ids() -> void:
	var lists := _stamina(50)
	lists["trx_wallet_list"] = [{"mst_item_id": "coin", "free_amount": 1000}]
	_login({"my_id": "a", "level": 1}, lists)
	var screen := await _show_home()
	var expected := {
		"Margin/Root/StaminaPanel/VBox/ValueRow/StaminaIcon": "items/stamina_50",
		"Margin/Root/CurrencyRow/CoinPanel/VBox/ValueRow/CoinIcon": "items/coin",
		"Margin/Root/CurrencyRow/DiamondPanel/VBox/ValueRow/DiamondIcon": "items/free_diamond",
	}
	for path: String in expected:
		var icon := screen.get_node(path) as ItemIcon
		assert_object(icon).is_not_null()
		assert_str(icon.resolved_key).is_equal(expected[path])
		assert_vector(icon.custom_minimum_size).is_equal(Vector2(48, 48))
	assert_str(_text(screen, COIN)).is_equal("1,000")


## 前提: 未ログインのホーム。期待: アイコンは出たまま（絵は値に依らない）で、値は「-」。
func test_value_icons_shown_when_not_logged_in() -> void:
	var screen := await _show_home()
	var icon := (
		screen.get_node("Margin/Root/CurrencyRow/CoinPanel/VBox/ValueRow/CoinIcon") as ItemIcon
	)
	assert_object(icon.texture).is_not_null()
	assert_str(_text(screen, COIN)).is_equal("-")


## 前提: ログイン済みのホーム（コイン 1000・ダイヤ 50・スタミナ 50）。操作: ツリーに入れて描画を 2 フレーム回す
## （ヘッドレスでもコンテナのレイアウトは計算される）。期待: 3 つの値ラベルが表示中・幅が文字の幅以上・高さも 0 でなく、
## 文字が期待どおりで、同じ行の ItemIcon の右に並ぶ。
## なぜ必要か: 値ラベルは text_overrun_behavior=trim（最小幅 0）で、ValueRow（HBox）の中で横に広げる指定が無いと
## 幅 1 に潰れ、文字が消えていた（値は取れているのに画面に出ない）。テキストの一致だけでは検出できなかった。
func test_value_labels_have_nonzero_size_beside_icons() -> void:
	var lists := _stamina(50)
	lists["trx_wallet_list"] = [{"mst_item_id": "coin", "free_amount": 1000}]
	lists["trx_item_list"] = [{"mst_item_id": "free_diamond", "free_amount": 50}]
	_login({"my_id": "a", "level": 1}, lists)
	var screen := await _show_home()
	# 親が Control でないテストでは画面の大きさが 0 のままなので、実機と同じ 1080x1920 にして並べ直す
	screen.size = Vector2(1080, 1920)
	await get_tree().process_frame
	await get_tree().process_frame
	var pairs := {
		STAMINA: ["Margin/Root/StaminaPanel/VBox/ValueRow/StaminaIcon", "50 / 50"],
		COIN: ["Margin/Root/CurrencyRow/CoinPanel/VBox/ValueRow/CoinIcon", "1,000"],
		DIAMOND: ["Margin/Root/CurrencyRow/DiamondPanel/VBox/ValueRow/DiamondIcon", "50"],
	}
	for label_path: String in pairs:
		var label := screen.get_node(label_path) as Label
		var icon := screen.get_node(pairs[label_path][0]) as ItemIcon
		assert_bool(label.is_visible_in_tree()).is_true()
		# 幅は文字が収まる大きさ（trim の最小幅は 1 で、0 より大きいだけでは「消えている」を見逃す）
		var text_width := (
			label
			. get_theme_font("font")
			. get_string_size(
				label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.get_theme_font_size("font_size")
			)
			. x
		)
		assert_float(label.size.x).is_greater_equal(text_width)
		assert_float(label.size.y).is_greater(0.0)
		assert_str(label.text).is_equal(pairs[label_path][1])
		# 同じ行: 縦の範囲が重なり、ラベルはアイコンの右にある
		var label_rect := label.get_global_rect()
		var icon_rect := icon.get_global_rect()
		assert_float(label_rect.position.x).is_greater_equal(icon_rect.end.x - 0.5)
		(
			assert_bool(
				label_rect.position.y < icon_rect.end.y and icon_rect.position.y < label_rect.end.y
			)
			. is_true()
		)


# ------------------------------------------------ ログインボーナスのボタン（V3c。H1） ----


## 前提: ルーターを渡したホーム。期待: ボタン「ログインボーナス」が出ていて（幅・高さが潰れない）、
## 押すと FROM_HOME の画面へ 1 回だけ遷移する（連打しても 1 回）。メール・お知らせを押しても何も起きない（P3）。
func test_login_bonus_button_goes_to_from_home_once() -> void:
	_login({"my_id": "A", "name": "taro", "level": 1}, _stamina(50))
	var router := ScreenTestDoubles.FakeRouter.new()
	var screen: HomePresenter = load(HOME_SCENE).instantiate()
	screen.setup(
		GetHomeSummaryUseCase.new(_repository, _levels, _config),
		GetStaminaDisplayUseCase.new(_repository, _clock),
		Signal(),
		router
	)
	add_child(auto_free(screen))
	for i in range(3):
		await get_tree().process_frame
	var button := screen.get_node("Margin/Root/NavRow/LoginBonusButton") as Button
	# 1 行では幅（約 290）に収まらないので、「ログイン」「ボーナス」の 2 行にしてある（改行を除くと「ログインボーナス」）
	assert_str(button.text.replace("\n", "")).is_equal("ログインボーナス")
	assert_bool(button.is_visible_in_tree()).is_true()
	assert_float(button.size.x).is_greater(100.0)
	assert_float(button.size.y).is_greater(100.0)
	# 「ボタンの文字が切れず収まる」: 折り返し後の最小の高さがボタンの高さ以内
	assert_float(button.get_minimum_size().y).is_less_equal(button.size.y)
	# メール・お知らせの隣（同じ行）で、バッジは付けない
	var mail := screen.get_node("Margin/Root/NavRow/MailButton") as Button
	assert_float(button.global_position.y).is_equal_approx(mail.global_position.y, 0.5)
	assert_object(button.get_node_or_null("Badge")).is_null()
	(screen.get_node("Margin/Root/NavRow/MailButton") as Button).pressed.emit()
	(screen.get_node("Margin/Root/NavRow/NoticeButton") as Button).pressed.emit()
	assert_array(router.calls).is_empty()
	button.pressed.emit()
	button.pressed.emit()
	assert_array(router.calls).is_equal(["login_bonus_from_home"])


## 前提: ルーターを渡さない（既存の呼び出し）。期待: ボタンを押しても落ちない。
func test_login_bonus_button_without_router_is_safe() -> void:
	_login({"my_id": "A", "name": "taro", "level": 1}, _stamina(50))
	var screen := await _show_home()
	(screen.get_node("Margin/Root/NavRow/LoginBonusButton") as Button).pressed.emit()
	assert_bool(is_instance_valid(screen)).is_true()


## SceneRouter の定数: FROM_HOME のシーンが実在し、LOGIN_BONUS_SCENE と別で、entry が FROM_HOME。
func test_scene_router_from_home_scene_exists_with_entry() -> void:
	var router_script: GDScript = load("res://app/scene_router.gd")
	var path: String = router_script.get_script_constant_map()["LOGIN_BONUS_FROM_HOME_SCENE"]
	assert_bool(ResourceLoader.exists(path)).is_true()
	assert_str(path).is_not_equal(router_script.get_script_constant_map()["LOGIN_BONUS_SCENE"])
	var scene: LoginBonusPresenter = auto_free(load(path).instantiate())
	assert_int(scene.entry).is_equal(LoginBonusPresenter.Entry.FROM_HOME)
	var base: LoginBonusPresenter = auto_free(
		load(router_script.get_script_constant_map()["LOGIN_BONUS_SCENE"]).instantiate()
	)
	assert_int(base.entry).is_equal(LoginBonusPresenter.Entry.FROM_LOGIN)
