## ログインボーナス画面の単体プレビュー（debug 専用。製品の複製には入らない。client_design.md 11-3・V3b の目視確認）。
##
## 目的: マスターの配信ファイルやサーバーが無い環境でも、カレンダー画面を実際に描いて画像に撮る。
##       本物の LoginBonusPresenter・GetLoginBonusScreenUseCase を使い、差し替えるのは「マスターを引く窓口」
##       （偽の PrepareLoginBonusMasterUseCase）と mst_item の名前の引き（偽の MstItemRepository）だけ。
## 使い方:
##   godot --path . res://debug/login_bonus_preview.tscn -- --preview=<名前> [--shot=<PNG>]
##   名前: normal（通常だけ・3 日目）/ both（通常＋VIP・報酬 2 行）/ text（周期 9 日 = 文字の画面）/
##         max（通常 7＋VIP 7＋報酬 5 行 = 最大構成）/ received（再表示。押印済み・受け取り済みの旨）
##   V3c（再受け取り。偽の API を差し込んだ FROM_HOME / FROM_LOGIN。ボタンを押す操作は --press-after 秒後に自動で行う）:
##         home_offer（FROM_HOME・受け取りボタンあり）/ home_receiving（押した直後の「受け取り中…」で止める）/
##         home_received（再受け取りの成功後。VIP のスタンプの押し直し・行・ボタン消去）/
##         home_refreshed（業務エラー → 取り直し。ボタンが消え Toast「状態を更新しました」）/
##         home_error（list が失敗。エラー文＋再試行）/ login_received（FROM_LOGIN で押した後。行が後ろに足される）/
##         home（ホーム画面そのもの。「ログインボーナス」ボタンの位置の確認。所持数は偽の値）
##   --shot=<パス>  アニメーションが終わった頃に画面を PNG に保存して終了（ヘッドレスでは描画されず撮れない）
##   --probe=<秒>   画面が出てから指定秒、描画の指標（FrameProbe。7 節）を集めて `E2E_PROBE:` の行を出し終了する
##                  （ウィンドウありで測る。スタンプのアニメーション中を含む。V2 の測り方に揃える）
##   --no-safe      iPhone X 相当の安全領域（上 127・下 98。ビューポート単位）を足さない
##   --press-after=<秒> V3c のモードで、受け取りボタンを押すまでの秒数（既定 0.5）
## 注意: 本番のコードから参照されない（T1）。ホームへの遷移は偽のルーター（何もしない）。

extends Control

## 撮影までの待ち（秒）。VIP のスタンプが終わる 1.0 秒より後
const SHOT_DELAY := 1.4
## iPhone X の安全領域（設計 1-4 の見積り。ビューポート単位）
const FrameProbe := preload("res://debug/frame_probe.gd")
const IPHONE_X_SAFE := {"left": 0.0, "top": 127.0, "right": 0.0, "bottom": 98.0}
const PRESENTER_SCENE := "res://contexts/login/presentation/login_bonus/login_bonus.tscn"
const FROM_HOME_SCENE := "res://contexts/login/presentation/login_bonus/login_bonus_from_home.tscn"
const HOME_SCENE := "res://contexts/player/presentation/home/home.tscn"
const RECEIVE_BUTTON_PATH := "Margin/Center/Panel/VBox/ReceiveSlot/ReceiveButton"
## 押す操作を自動で行うモード（V3c）と、各モードの撮影までの待ち（秒。押す時刻 + 見せたい状態が整うまで）
const PRESS_MODES: Array[String] = [
	"home_receiving", "home_received", "home_refreshed", "login_received"
]
## 絵の ID（assets/icons/items/ に在るもの）を日ごとに回す
const ITEM_IDS: Array[String] = [
	"coin", "free_diamond", "item_heal_001", "item_exp_001", "item_boost_001", "item_material_001"
]


## 偽の router。ホームへの遷移を数えるだけ。
class PreviewRouter:
	extends RefCounted
	var home_count: int = 0

	func goto_home() -> void:
		home_count += 1

	func goto_title() -> void:
		pass


## 「待たせる」ための signal の持ち主（発火しなければ永遠に待つ。「受け取り中…」の撮影用）。
class GateSource:
	extends RefCounted
	signal opened


## 偽の API（POST /login_bonus/list・receive）。モードごとに結果を決めて渡す。
## list: 1 回目は list_first、2 回目以降（業務エラー後の取り直し）は list_after。
## receive: receive_error が null なら成功（報酬 2 件・VIP の段は今日受け取り済み・updated_resources つき）。
class PreviewCalendar:
	extends LoginBonusCalendarRepository
	var list_first: LoginBonusCalendars = LoginBonusCalendars.new()
	var list_after: LoginBonusCalendars = LoginBonusCalendars.new()
	var list_error: AppError = null
	var receive_error: AppError = null
	var receive_gate: Signal
	var fetch_count: int = 0

	func fetch_calendars() -> FetchLoginBonusCalendarsResult:
		fetch_count += 1
		if list_error != null:
			return FetchLoginBonusCalendarsResult.new(list_error)
		return FetchLoginBonusCalendarsResult.new(
			null, list_first if fetch_count == 1 else list_after
		)

	func receive_vip(_id: String, _key: String) -> ReceiveVipLoginBonusResult:
		if not receive_gate.is_null():
			await receive_gate
		if receive_error != null:
			return ReceiveVipLoginBonusResult.new(receive_error)
		var rewards: Array[LoginBonus] = [
			LoginBonus.new("", "gold", "gold", 6000), LoginBonus.new("", "item", "free_diamond", 50)
		]
		var vip := LoginBonusCalendar.new("vip", 3, true, true, false, 4)
		return (
			ReceiveVipLoginBonusResult
			. new(
				null,
				rewards,
				vip,
				{
					"trx_wallet_list": [{"mst_item_id": "coin", "free_amount": 16000}],
					"trx_item_list": [{"mst_item_id": "free_diamond", "free_amount": 250}],
				}
			)
		)


## 偽の「マスターを引く窓口」。決めておいた束をそのまま返す（再取得の通信をしない）。
class FakePrepare:
	extends PrepareLoginBonusMasterUseCase
	var fixed: LoginBonusStageMasters

	func _init(masters: LoginBonusStageMasters) -> void:
		fixed = masters

	func handle(_calendars: LoginBonusCalendars) -> PrepareLoginBonusMasterResult:
		return PrepareLoginBonusMasterResult.new(fixed, true)


## 偽の mst_item。ITEM_IDS の ID に名前とカテゴリを返す。
class FakeItems:
	extends MstItemRepository

	func get_by_id(id: String) -> MstItem:
		if not ITEM_IDS.has(id) and id != "gold":
			return null
		var item := MstItem.new()
		item.id = id
		item.name = "ゴールド" if id == "gold" else "アイテム " + id
		item.type = "recovery"
		return item


var _shot_path: String = ""
var _elapsed: float = 0.0
var _shot_done: bool = false
## 描画の指標の記録（--probe）。無ければ null
var _probe: RefCounted = null
var _probe_label: String = ""
## V3c: 撮影の待ち（モードで決まる）・受け取りボタンを押す時刻・押したか・対象の画面
var _shot_delay: float = SHOT_DELAY
var _press_after: float = 0.5
var _pressed: bool = false
var _mode: String = ""
var _presenter: LoginBonusPresenter = null
var _gate: GateSource = null


func _ready() -> void:
	var args := _parse_args()
	_shot_path = str(args.get("shot", ""))
	_mode = str(args.get("preview", "both"))
	_press_after = float(args.get("press-after", 0.5))
	if args.has("probe"):
		_probe = FrameProbe.new(float(args["probe"]))
		_probe_label = "login_bonus_" + _mode
	if _mode == "home":
		_show_home()
		return
	var repository := LocalLoginBonusRepository.new()
	var masters := _build(_mode, repository)
	var displays := GetLoginBonusDisplaysUseCase.new(
		GetLoginBonusesUseCase.new(repository), FakeItems.new()
	)
	var get_screen := GetLoginBonusScreenUseCase.new(repository, displays)
	var is_v3c := _mode.begins_with("home_") or _mode == "login_received"
	var presenter: LoginBonusPresenter
	if is_v3c:
		presenter = _make_v3c_presenter(repository, masters, get_screen)
	else:
		presenter = load(PRESENTER_SCENE).instantiate()
		presenter.setup(repository, FakePrepare.new(masters), get_screen, PreviewRouter.new())
	_presenter = presenter
	add_child(presenter)
	if not args.has("no-safe"):
		presenter.apply_safe_margins(IPHONE_X_SAFE)


## V3c のモード用の画面を作る。偽の API（PreviewCalendar）・本物の UseCase・本物の Toast（「状態を更新しました」の撮影用）。
func _make_v3c_presenter(
	repository: LocalLoginBonusRepository,
	masters: LoginBonusStageMasters,
	get_screen: GetLoginBonusScreenUseCase
) -> LoginBonusPresenter:
	var calendar := PreviewCalendar.new()
	var offer := LoginBonusCalendars.new(
		LoginBonusCalendar.new("lb", 3, true, false),
		LoginBonusCalendar.new("vip", 3, true, false, true, 4)
	)
	var no_offer := LoginBonusCalendars.new(
		LoginBonusCalendar.new("lb", 3, true, false),
		LoginBonusCalendar.new("vip", 3, true, false, false, 4)
	)
	calendar.list_first = offer
	calendar.list_after = no_offer
	match _mode:
		"home_receiving":
			# signal の持ち主を保持しておく（RefCounted なので、参照が切れると解放されて signal も無効になる）
			_gate = GateSource.new()
			calendar.receive_gate = _gate.opened
			_shot_delay = _press_after + 0.9
		"home_received":
			_shot_delay = _press_after + 1.6
		"home_refreshed":
			var error := AppError.new(AppError.Kind.BUSINESS)
			error.error_code = 26001
			calendar.receive_error = error
			_shot_delay = _press_after + 0.9
		"home_error":
			calendar.list_error = AppError.new(AppError.Kind.NETWORK)
		"login_received":
			_shot_delay = _press_after + 1.6
	var presenter: LoginBonusPresenter = (
		load(PRESENTER_SCENE if _mode == "login_received" else FROM_HOME_SCENE).instantiate()
	)
	presenter.setup(
		repository,
		FakePrepare.new(masters),
		get_screen,
		PreviewRouter.new(),
		FetchLoginBonusCalendarsUseCase.new(calendar, repository),
		ReceiveVipLoginBonusUseCase.new(
			calendar, repository, ApplyUpdatedResourcesUseCase.new(LocalPlayerRepository.new())
		),
		Toast
	)
	return presenter


## ホーム画面そのもの（「ログインボーナス」ボタンの位置の確認）。所持数は AppContext の保持に偽の値を入れる。
func _show_home() -> void:
	(
		AppContext
		. apply_updated_resources_use_case()
		. handle(
			{
				"trx_wallet_list": [{"mst_item_id": "coin", "free_amount": 12000}],
				"trx_item_list": [{"mst_item_id": "free_diamond", "free_amount": 200}],
				"trx_stamina_list":
				[
					{
						"type": "normal",
						"current_stamina": 42,
						"last_recovery_at": "2027-01-15 08:00:00",
						"recovery_rate_multiplier": "1.00"
					}
				],
			}
		)
	)
	add_child(load(HOME_SCENE).instantiate())


func _process(delta: float) -> void:
	_elapsed += delta
	# --- V3c: 受け取りボタンを指定の秒数後に 1 回押す（人の操作の代わり） ---
	if PRESS_MODES.has(_mode) and not _pressed and _elapsed >= _press_after and _presenter != null:
		var button := _presenter.get_node_or_null(RECEIVE_BUTTON_PATH) as Button
		if button != null and button.is_visible_in_tree():
			_pressed = true
			button.pressed.emit()
	if _probe != null:
		if _probe.advance(delta):
			print(
				FrameProbe.format_line(
					_probe_label, _probe.frames(), _probe.result(), FrameProbe.is_headless()
				)
			)
			get_tree().quit(0)
		return
	if _shot_path == "" or _shot_done or _elapsed < _shot_delay:
		return
	_shot_done = true
	DirAccess.make_dir_recursive_absolute(_shot_path.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(_shot_path)
	print("PREVIEW: 保存 ", _shot_path, " (", error, ")")
	get_tree().quit(0 if error == OK else 1)


## 名前に応じて、メモリの進捗と login_bonus_list を repository に入れ、段のマスターの束を返す。
func _build(name: String, repository: LocalLoginBonusRepository) -> LoginBonusStageMasters:
	var masters := LoginBonusStageMasters.new()
	masters.normal = _stage(7, 2)
	masters.vip = _stage(7, 1)
	var rewards_count := 2
	match name:
		"normal":
			# 通常だけ。VIP の段は無い（null）
			repository.replace_calendars(
				LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 3, true, true))
			)
			rewards_count = 1
		"login_received":
			# FROM_LOGIN: 今配ったばかり（通常 3 日目）。VIP は今日の段で再受け取り可能。login の行は 2 件
			repository.replace_calendars(
				LoginBonusCalendars.new(
					LoginBonusCalendar.new("lb", 3, true, true),
					LoginBonusCalendar.new("vip", 3, true, true, true, 3)
				)
			)
			rewards_count = 2
		"home_offer", "home_receiving", "home_received", "home_refreshed", "home_error":
			# FROM_HOME: 進捗は list の応答で入る（偽の API）。行は出さない
			rewards_count = 0
		"text":
			# 周期 9 日（8 超）→ 文字の画面
			masters.normal = _stage(9, 1)
			repository.replace_calendars(
				LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 3, true, true))
			)
		"received":
			repository.replace_calendars(
				LoginBonusCalendars.new(
					LoginBonusCalendar.new("lb", 4, true, false),
					LoginBonusCalendar.new("vip", 4, true, false, false, 3)
				)
			)
			rewards_count = 0
		_:
			# both / max: 両方の段が今日の段で、今日配ったばかり（スタンプが押される）
			repository.replace_calendars(
				LoginBonusCalendars.new(
					LoginBonusCalendar.new("lb", 3, true, true),
					LoginBonusCalendar.new("vip", 3, true, true, false, 3)
				)
			)
			rewards_count = 5 if name == "max" else 2
	var list: Array[LoginBonus] = []
	for i in range(rewards_count):
		# 1 行目はサーバーの実際の形（wallet は type=gold・id=gold で来る）にして、行の絵・名前の引きを確かめる
		if i == 0:
			list.append(LoginBonus.new("u0", "gold", "gold", 4000))
			continue
		list.append(LoginBonus.new("u%d" % i, "item", ITEM_IDS[i % ITEM_IDS.size()], 100 * (i + 1)))
	repository.replace(list)
	return masters


## cycle 日の段のマスター。日ごとに 1 件、last_multi 日目（最終日）だけ 2 件にして「＋1」も出す。
func _stage(cycle: int, last_multi: int) -> LoginBonusStageMaster:
	var entries: Array[Dictionary] = []
	for day in range(1, cycle + 1):
		var count := 2 if (day == cycle and last_multi == 2) else 1
		for k in range(count):
			entries.append(
				{
					"day": day,
					"type": "item",
					"id": ITEM_IDS[(day + k) % ITEM_IDS.size()],
					"quantity": day * 100 if day % 2 == 0 else day * 10,
					"metadata": {}
				}
			)
	return LoginBonusStageMasterReader.build_stage(cycle, entries)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not arg.begins_with("--"):
			continue
		var body: String = arg.substr(2)
		var separator := body.find("=")
		if separator < 0:
			result[body] = true
		else:
			result[body.substr(0, separator)] = body.substr(separator + 1)
	return result
