## e2e ドライバーのクリック入力の組み立てのテスト（debug/e2e_driver.gd の static 関数）。
##
## 規約画面の同意ボタンが押せなかった原因は、ウィンドウが画面に収まらず縮んだとき（1080x1920 が 1832 の高さ）、
## ビューポート座標をそのまま送ると、ウィンドウの外（y=1856）を押していたこと。座標変換と、
## 実際のマウスに近いイベント（移動・押下・解放）の組み立てを確かめる。ドライバーはオートロードなので
## インスタンスは作らず、スクリプトの static 関数を直接呼ぶ。
extends GdUnitTestSuite

const DRIVER := "res://debug/e2e_driver.gd"


## 前提: stretch で 0.95 倍に縮み、左に 25px 余白がある変換（実際に出た値）。操作: 変換。
## 期待: ビューポートの (540, 1856) が、ウィンドウの高さ 1832 の内側に入る（押せる位置になる）。
func test_to_window_position_applies_stretch_transform() -> void:
	var transform := Transform2D(Vector2(0.953704, 0), Vector2(0, 0.954167), Vector2(25, 0))
	var position: Vector2 = load(DRIVER).to_window_position(Vector2(540, 1856), transform)
	assert_float(position.y).is_less(1832.0)
	assert_float(position.x).is_equal_approx(540 * 0.953704 + 25, 0.01)


## 前提: 変換なし（録画時などウィンドウ = ビューポート）。期待: 座標は変わらない。
func test_to_window_position_identity() -> void:
	var position: Vector2 = load(DRIVER).to_window_position(Vector2(540, 960), Transform2D.IDENTITY)
	assert_vector(position).is_equal(Vector2(540, 960))


## 前提: 押下と解放のイベントを作る。期待: 左ボタン・指定位置で、押下は button_mask に左が立ち、
## 解放は 0（実機の入力と同じ。Button は mask 付きの押下の後の解放で pressed を出す）。
func test_button_events_match_real_mouse() -> void:
	var down: InputEventMouseButton = load(DRIVER).make_button(Vector2(10, 20), true)
	var up: InputEventMouseButton = load(DRIVER).make_button(Vector2(10, 20), false)
	assert_int(down.button_index).is_equal(MOUSE_BUTTON_LEFT)
	assert_bool(down.pressed).is_true()
	assert_int(down.button_mask).is_equal(MOUSE_BUTTON_MASK_LEFT)
	assert_vector(down.position).is_equal(Vector2(10, 20))
	assert_bool(up.pressed).is_false()
	assert_int(up.button_mask).is_equal(0)


## 前提: 移動イベントを作る。期待: ボタンを押していない移動（ホバーのため、押下の前に送る）。
func test_motion_event_has_no_buttons() -> void:
	var motion: InputEventMouseMotion = load(DRIVER).make_motion(Vector2(5, 6))
	assert_vector(motion.position).is_equal(Vector2(5, 6))
	assert_int(motion.button_mask).is_equal(0)


## 前提: エラー表示（再試行ボタン）が見え始め → 見え続け → 消える（押して再試行中）→ 再び見える。
## 期待: 見え始めは 0、続けば delta ずつ増え、消えたら -1、再び見えたら 0 から数え直す
## （失敗が続いても毎回 dwell 秒見せられる。dwell 前に押さないための経過秒の根拠）。
func test_next_error_time_restarts_for_each_error() -> void:
	var driver: GDScript = load(DRIVER)
	var t: float = driver.next_error_time(-1.0, true, 0.1)
	assert_float(t).is_equal(0.0)
	t = driver.next_error_time(t, true, 0.5)
	t = driver.next_error_time(t, true, 0.5)
	assert_float(t).is_equal_approx(1.0, 0.0001)
	t = driver.next_error_time(t, false, 0.5)
	assert_float(t).is_equal(-1.0)
	assert_float(driver.next_error_time(t, true, 0.5)).is_equal(0.0)


## 前提: --e2e-case 付きの引数。操作: debug ビルドか否かで判定。
## 期待: debug ビルドでは有効、製品ビルド（debug でない）では引数があっても無効（混入しても動かない）。
func test_is_enabled_only_in_debug_build() -> void:
	var args := {"e2e-case": "probe"}
	assert_bool(load(DRIVER).is_enabled(args, true)).is_true()
	assert_bool(load(DRIVER).is_enabled(args, false)).is_false()
	assert_bool(load(DRIVER).is_enabled({"e2e": true}, true)).is_true()


## 前提: --e2e 系でない引数（--e2e-reset だけ）か、引数なし。期待: debug ビルドでも無効（通常起動は何もしない）。
func test_is_enabled_requires_e2e_argument() -> void:
	assert_bool(load(DRIVER).is_enabled({}, true)).is_false()
	assert_bool(load(DRIVER).is_enabled({"e2e-reset": true}, true)).is_false()


## --e2e-home-hold: 秒の値を読む。無い・値なし（true）・数値でない・負は 0。
func test_home_hold_seconds() -> void:
	var driver: GDScript = load(DRIVER)
	assert_float(driver.home_hold_seconds({"e2e-home-hold": "5"})).is_equal(5.0)
	assert_float(driver.home_hold_seconds({"e2e-home-hold": "2.5"})).is_equal(2.5)
	assert_float(driver.home_hold_seconds({})).is_equal(0.0)
	assert_float(driver.home_hold_seconds({"e2e-home-hold": true})).is_equal(0.0)
	assert_float(driver.home_hold_seconds({"e2e-home-hold": "abc"})).is_equal(0.0)
	assert_float(driver.home_hold_seconds({"e2e-home-hold": "-3"})).is_equal(0.0)


## --e2e-clock-skew: 整数の秒（負も可）。無い・値なし・整数でないは 0。
func test_clock_skew_seconds() -> void:
	var driver: GDScript = load(DRIVER)
	assert_int(driver.clock_skew_seconds({"e2e-clock-skew": "3600"})).is_equal(3600)
	assert_int(driver.clock_skew_seconds({"e2e-clock-skew": "-3600"})).is_equal(-3600)
	assert_int(driver.clock_skew_seconds({})).is_equal(0)
	assert_int(driver.clock_skew_seconds({"e2e-clock-skew": true})).is_equal(0)
	assert_int(driver.clock_skew_seconds({"e2e-clock-skew": "1.5"})).is_equal(0)


## E2E_RESULT の行: 設計 8-2 の項目を、スタミナありと最大値不明・行なしの両方で出す。
func test_format_home_result() -> void:
	var driver: GDScript = load(DRIVER)
	var summary := HomeSummary.new()
	summary.player_id = "ABCD1234"
	summary.player_name = "taro"
	summary.level = 1
	summary.coin = 1000
	summary.diamond_total = 50
	var line: String = driver.format_home_result(
		summary, StaminaDisplay.new(46, 50, 12, true), 45, 45, "0"
	)
	assert_str(line).is_equal(
		(
			"E2E_RESULT: OK player_id=ABCD1234 name=taro level=1 stamina=46/50 remain=12 coin=1000"
			+ " diamond=50 login_stamina=45 open_stamina=45 offset=0"
		)
	)
	var unknown: String = driver.format_home_result(
		summary, StaminaDisplay.new(42, -1, -1, true), 42, 42, "none"
	)
	assert_str(unknown).contains("stamina=42/-- remain=none")
	assert_str(unknown).contains("offset=none")
	var absent: String = driver.format_home_result(summary, StaminaDisplay.new(), 0, 0, "none")
	assert_str(absent).contains("stamina=none")


# ------------------------------------------------ ログインボーナスの引数・結果（V3c） ----


## 前提: --e2e-receive の値。期待: home / login だけ有効。値なし（true）・他の値・引数なしは ""（押さない。設計 11-1）。
func test_receive_entry_accepts_only_home_or_login() -> void:
	var driver: GDScript = load(DRIVER)
	assert_str(driver.receive_entry({"e2e-receive": "home"})).is_equal("home")
	assert_str(driver.receive_entry({"e2e-receive": "login"})).is_equal("login")
	assert_str(driver.receive_entry({"e2e-receive": true})).is_equal("")
	assert_str(driver.receive_entry({"e2e-receive": "both"})).is_equal("")
	assert_str(driver.receive_entry({})).is_equal("")


## 前提: 通常 3 日目が今日（今配った）・VIP が今日（押し直しの再生あり）・ボタンあり・報酬 2 行の画面の値。
## 期待: マスの状態の並び（T=今日・R=受け取り済み・F=未来、再生するマスに !）・ボタン・行数が空白なしの 1 つの文字列になる。
func test_format_bonus_state() -> void:
	var driver: GDScript = load(DRIVER)
	var screen := LoginBonusScreen.new()
	screen.normal = _stage([1, 0, 2], -1)
	screen.vip = _stage([3, 3], 1)
	screen.rewards = [
		LoginBonusDisplay.new(LoginBonus.new("u", "item", "a", 1)),
		LoginBonusDisplay.new(LoginBonus.new("u", "item", "b", 1)),
	]
	var text: String = driver.format_bonus_state(screen, true)
	assert_str(text).is_equal("normal[R,T,F]/vip[N,N!]/button=yes/rows=2")
	assert_bool(text.contains(" ")).is_false()


## 前提: 段が無い画面・文字の画面。期待: none / text_fallback で出る（落ちない）。
func test_format_bonus_state_without_stage_and_text_fallback() -> void:
	var driver: GDScript = load(DRIVER)
	var screen := LoginBonusScreen.new()
	assert_str(driver.format_bonus_state(screen, false)).is_equal(
		"normal[none]/vip[none]/button=no/rows=0"
	)
	screen.use_text_fallback = true
	assert_str(driver.format_bonus_state(screen, false)).is_equal("text_fallback/button=no/rows=0")


## 前提: 入口ごとの状態と受け取りの結果。期待: 開いた入口だけ bonus_<入口>= を出し、末尾に receive=。
## ログインボーナス画面に一度も入っていない（記録が空）ときは空文字（従来の E2E_RESULT: OK の行のまま）。
func test_bonus_result_suffix() -> void:
	var driver: GDScript = load(DRIVER)
	assert_str(driver.bonus_result_suffix({}, "none")).is_equal("")
	assert_str(driver.bonus_result_suffix({"home": "X"}, "ok")).is_equal(" bonus_home=X receive=ok")
	assert_str(driver.bonus_result_suffix({"home": "H", "login": "L"}, "none")).is_equal(
		" bonus_login=L bonus_home=H receive=none"
	)


## states: マスの状態の整数（CalendarCellView.State の値）の並び。play_index はスタンプを再生するマスの位置（-1 なし）。
func _stage(states: Array, play_index: int) -> CalendarStageView:
	var stage := CalendarStageView.new()
	for i in range(states.size()):
		var cell := CalendarCellView.new()
		cell.state = states[i]
		cell.play_stamp = i == play_index
		stage.cells.append(cell)
	return stage
