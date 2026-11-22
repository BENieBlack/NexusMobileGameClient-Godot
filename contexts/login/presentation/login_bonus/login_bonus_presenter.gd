## ログインボーナス画面の presenter（client_design.md 1-2・3・6。入口は FROM_LOGIN と FROM_HOME）。
##
## 目的: ログインボーナスを、カレンダー（通常の段・VIP の段・今日の強調・スタンプ）と「今日配られた報酬」の行で見せ、
##       ボタン以外のタップでホームへ進む。VIP の再受け取りボタンも持つ。業務の判断はしない
##       （UseCase の結果 LoginBonusScreen を描くだけ）。
## 入口（1-1。継承シーン login_bonus_from_home.tscn が @export の entry だけ FROM_HOME にする）:
##   FROM_LOGIN  login 直後。通信しない（メモリの進捗）。今回配った段のマスにスタンプのアニメーションを再生する
##   FROM_HOME   ホームのボタンから。開くたびに POST /login_bonus/list で状態を取り、アニメーションなしで確認だけ見せる
## 流れ（_ready）:
##   1. 「読み込み中…」を出す（カレンダー・行は隠す）
##   2. FROM_HOME だけ FetchLoginBonusCalendarsUseCase（冪等キーなし）。失敗は ErrorView（エラー文＋「再試行」。
##      SESSION_EXPIRED は文を見せてタイトルへ）。タップでホームへ戻れる
##   3. PrepareLoginBonusMasterUseCase.handle() を await（古いマスターなら 1 回だけ再取得して引き直す）
##   4. GetLoginBonusScreenUseCase.handle(...) が LoginBonusScreen を返す（同期。FROM_LOGIN は行あり・再生あり、
##      FROM_HOME は行なし・再生なし）
##   5. 描画: use_text_fallback なら今の文字の画面（build_text）、そうでなければ段・再表示の旨・報酬の行・受け取りボタン。
##      今日のマス（再生するマス）だけスタンプのアニメーション（通常 0.3 秒・VIP 0.5 秒開始。6 節）
## 受け取りボタン（3-2。FROM_LOGIN・FROM_HOME 共通。can_re_receive が真のときだけ ReceiveSlot に出す）:
##   押す → _is_receiving を立ててボタンを無効にし「受け取り中…」→ ReceiveVipLoginBonusUseCase（冪等キーつき）
##   成功: 画面を作り直す（VIP の今日のマスだけスタンプを外して押し直す。通常の段は再生しない）・ボタンが消える・
##         「今日配られた報酬」の行に再受け取りの報酬を足す（所持数は UseCase が反映済み）
##   失敗: BUSINESS（26001〜26003 など）はコードで分岐せず、キーを作り直して FetchLoginBonusCalendarsUseCase で状態を取り直し、
##         ボタンを出し直して Toast「状態を更新しました」。取り直しも失敗したらボタンを消してエラー文
##         それ以外（通信断・409・503 など）はエラー文を出してボタンを戻す。再送は同じキー（成功済みを二重にしない）
##   二重送信の防止: _is_receiving の間は押しても何もしない。受け取り中はタップでも閉じない（所持数の反映前に戻らない）
## 閉じる操作（H5・1-1）: 背面の TapCatcher（全画面・mouse_filter = STOP）の gui_input でタップ（マウス左・タッチ）を
##   受けてホームへ。前面の表示専用ノードは全て mouse_filter = IGNORE（tests が走査して守る）。ボタンのタップは閉じない。
##   アニメーション中のタップは最終状態へ飛ぶだけで閉じない（K4）。連打しても遷移は 1 回（_is_leaving）。
## 画面の破棄: await から戻ったとき、離れた・ツリーの外なら何も触らない（1-5 の 4）。
## 安全領域: SafeAreaMargins（core/presentation）で Margin の余白に足す（モバイルのみ。基本の余白は上下 48。1-4）。
## 依存: LoginBonusRepository（進捗）・各 UseCase。遷移・Toast は既定ではオートロードの SceneRouter・Toast
##       （テストは setup で偽物を渡す）。
class_name LoginBonusPresenter
extends Control

## 画面の入口。FROM_LOGIN = login 直後（既定）、FROM_HOME = ホームのボタンから
## （継承シーン login_bonus_from_home.tscn が @export の entry だけ変える。1-1）
enum Entry { FROM_LOGIN, FROM_HOME }

## この画面の基本の余白（ビューポート座標）。安全領域の分をこれに足す。
## 上下 48 は「ホームの 96 では 1512 が収まらない」ための値（1-4）
const BASE_MARGIN_SIDE := 48
const BASE_MARGIN_VERTICAL := 48
## マスの絵の一辺（1-4 の確定値。通常 80・VIP 72）
const NORMAL_ICON_SIZE := 80
const VIP_ICON_SIZE := 72
## 再受け取りの押印の開始の遅れ（秒）。応答を受けた瞬間にスタンプを外し、0.3 秒後に押す（6 節。着地 0.7・終了 0.8 秒）
const RE_RECEIVE_DELAY := 0.3
const RECEIVE_LABEL := "受け取る"
const RECEIVING_LABEL := "受け取り中…"
const REFRESHED_TOAST := "状態を更新しました"
## SESSION_EXPIRED の文を見せてからタイトルへ戻るまでの秒数の既定（agreement と同じ）
const SESSION_NOTICE_SEC := 2.0
const REWARD_ROW_SCENE := preload("res://contexts/login/presentation/login_bonus/reward_row.tscn")

@export var entry: Entry = Entry.FROM_LOGIN

## SESSION_EXPIRED の文を見せてからタイトルへ戻るまでの秒数（テストで短くできるよう変数にしてある）
var session_notice_sec: float = SESSION_NOTICE_SEC
## 最後に描いた画面の値（テストと確認用）
var current_screen: LoginBonusScreen = null

var _repository: LoginBonusRepository
var _prepare_master: PrepareLoginBonusMasterUseCase
var _get_screen: GetLoginBonusScreenUseCase
var _fetch_calendars: FetchLoginBonusCalendarsUseCase
var _receive_vip: ReceiveVipLoginBonusUseCase
var _router: Object
var _toast: Object
var _is_configured: bool = false
var _is_leaving: bool = false
## 受け取りボタンの表示値（VIP の can_re_receive が真のときだけ visible）
var _receive_offer: ReceiveOffer = ReceiveOffer.new()
var _stamp_player: StampPlayer = null
## 最後に引いたマスターの束（受け取り成功後の作り直しに使う。取り直したら引き直す）
var _masters: LoginBonusStageMasters = null
## 受け取り中か（二重送信の防止。応答が戻るまで立つ）
var _is_receiving: bool = false
## 受け取りの冪等キー（3-4）。空なら次の送信で作る。通信断・409・503 の再送は同じキー、成功・BUSINESS の後は新しいキー
var _receive_key: String = ""

@onready var _tap_catcher: Control = $TapCatcher
@onready var _margin: MarginContainer = $Margin
@onready var _notice_label: Label = $Margin/Center/Panel/VBox/NoticeLabel
@onready var _status_label: Label = $Margin/Center/Panel/VBox/StatusLabel
@onready var _retry_button: Button = $Margin/Center/Panel/VBox/RetryButton
@onready var _normal_section: CalendarSection = $Margin/Center/Panel/VBox/NormalSection
@onready var _vip_section: CalendarSection = $Margin/Center/Panel/VBox/VipSection
@onready var _receive_slot: VBoxContainer = $Margin/Center/Panel/VBox/ReceiveSlot
@onready var _receive_button: Button = $Margin/Center/Panel/VBox/ReceiveSlot/ReceiveButton
@onready var _receive_message: Label = $Margin/Center/Panel/VBox/ReceiveSlot/ReceiveMessageLabel
@onready var _rewards_header: Label = $Margin/Center/Panel/VBox/RewardsHeader
@onready var _rewards_list: VBoxContainer = $Margin/Center/Panel/VBox/RewardsList
@onready var _bonus_bg: PanelContainer = $Margin/Center/Panel/VBox/BonusBg
@onready var _bonus_label: Label = $Margin/Center/Panel/VBox/BonusBg/BonusLabel
@onready var _tap_label: Label = $Margin/Center/Panel/VBox/TapBg/TapLabel


## UseCase・遷移の相手を渡す。_ready より前に呼ぶとその値を使い、呼ばなければ _ready がオートロードから取る。
## fetch_calendars・receive_vip・toast は省略できる（FROM_LOGIN の表示だけを見るテスト用。省略時は null で、
## FROM_HOME の取得・受け取りボタンの押下は何もしない）。
func setup(
	repository: LoginBonusRepository,
	prepare_master: PrepareLoginBonusMasterUseCase,
	get_screen: GetLoginBonusScreenUseCase,
	router: Object,
	fetch_calendars: FetchLoginBonusCalendarsUseCase = null,
	receive_vip: ReceiveVipLoginBonusUseCase = null,
	toast: Object = null
) -> void:
	_repository = repository
	_prepare_master = prepare_master
	_get_screen = get_screen
	_router = router
	_fetch_calendars = fetch_calendars
	_receive_vip = receive_vip
	_toast = toast
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(
			AppContext.login_bonus_repository(),
			AppContext.prepare_login_bonus_master_use_case(),
			AppContext.get_login_bonus_screen_use_case(),
			SceneRouter,
			AppContext.fetch_login_bonus_calendars_use_case(),
			AppContext.receive_vip_login_bonus_use_case(),
			Toast
		)
	_tap_label.text = "タップして続ける"
	_tap_catcher.gui_input.connect(_on_tap_catcher_input)
	_retry_button.pressed.connect(_on_retry_pressed)
	_receive_button.pressed.connect(_on_receive_pressed)
	_stamp_player = StampPlayer.new(self)
	_apply_safe_area()
	await _load_screen()


## 画面を出す（_ready と、FROM_HOME の「再試行」から呼ぶ）。FROM_HOME は list で状態を取ってから、
## どちらの入口もマスターを引いて描く。
func _load_screen() -> void:
	# --- 1. 読み込み中（再取得・通信が要るときだけ見える） ---
	_show_loading()
	# --- 2. FROM_HOME は進捗を取り直す（login 応答は古くなりうる。H2）。冪等キーは付けない（3-4） ---
	if entry == Entry.FROM_HOME and _fetch_calendars != null:
		var fetched := await _fetch_calendars.handle()
		# 待っている間にホームへ戻った（画面が解放済み）なら、何も触らない（1-5 の 4）
		if _is_leaving or not is_inside_tree():
			return
		if not fetched.ok:
			await _show_load_error(fetched.error)
			return
	# --- 3. マスターを引く（古ければ 1 回だけ再取得。名前・絵の引きは画面を開くとき 1 回だけ） ---
	var prepared := await _prepare_master.handle(_repository.calendars())
	if _is_leaving or not is_inside_tree():
		return
	_masters = prepared.masters
	# --- 4. 表示モデルを作って描く。FROM_LOGIN は login_bonus_list の行を出しスタンプを再生する。
	#        FROM_HOME は行なし・再生なし（確認のみ。H3） ---
	var is_login := entry == Entry.FROM_LOGIN
	render(_get_screen.handle(_masters, is_login, is_login))


func _exit_tree() -> void:
	# 画面を離れたら、再生中のスタンプの Tween を止める（離れた後にマスを触らない）
	if _stamp_player != null:
		_stamp_player.kill_all()


## 画面を描く（_ready・再試行・受け取りの成功後・取り直しから呼ぶ）。
## vip_delay: VIP の段のスタンプの開始の遅れ（秒）。login 直後は 0.5、再受け取りの押し直しは 0.3（6 節）。
func render(screen: LoginBonusScreen, vip_delay: float = StampPlayer.VIP_DELAY) -> void:
	current_screen = screen
	_receive_offer = screen.receive_offer
	_status_label.visible = false
	ErrorView.hide_retry(_retry_button)
	if screen.use_text_fallback:
		_render_text_fallback(screen)
	else:
		_render_calendar(screen, vip_delay)
	_render_receive_slot()


## 「読み込み中…」。カレンダー・行・文字の画面・受け取りボタンは隠す（背景動画・タイトル・タップの案内は出す）。
func _show_loading() -> void:
	_status_label.text = CalendarText.LOADING
	_status_label.visible = true
	ErrorView.hide_retry(_retry_button)
	_receive_slot.visible = false
	_set_receive_message("")
	_notice_label.visible = false
	_normal_section.visible = false
	_vip_section.visible = false
	_rewards_header.visible = false
	_rewards_list.visible = false
	_bonus_bg.visible = false


## 今の文字の画面（build_text。login_bonus_list が空なら「受け取り済み」の文）。
func _render_text_fallback(screen: LoginBonusScreen) -> void:
	_bonus_label.text = build_text(screen.rewards)
	_bonus_bg.visible = true


## カレンダー表示。段・再表示の旨・報酬の行を出し、今日のマスのスタンプを始める。
func _render_calendar(screen: LoginBonusScreen, vip_delay: float) -> void:
	# --- 再表示の旨（いずれかの段が今日の段で、どの段も今日配ったばかりでないとき。T3） ---
	_notice_label.text = CalendarText.RECEIVED_NOTICE
	_notice_label.visible = screen.show_received_notice
	# --- 段（null の段は出さない。T4） ---
	_setup_section(_normal_section, screen.normal, NORMAL_ICON_SIZE)
	_setup_section(_vip_section, screen.vip, VIP_ICON_SIZE)
	# --- 「今日配られた報酬」の行（FROM_LOGIN で非空のときだけ） ---
	_render_rewards(screen.rewards)
	# --- スタンプ。通常が先（0.3 秒）、VIP が後（0.5 秒）。再生するマスだけ（K1） ---
	_play_stamps(_normal_section, StampPlayer.NORMAL_DELAY)
	_play_stamps(_vip_section, vip_delay)


func _setup_section(section: CalendarSection, stage: CalendarStageView, icon_size: int) -> void:
	section.visible = stage != null
	if stage != null:
		section.setup(stage, icon_size)


func _render_rewards(rewards: Array[LoginBonusDisplay]) -> void:
	var has_rewards := not rewards.is_empty()
	_rewards_header.text = CalendarText.REWARDS_HEADER
	_rewards_header.visible = has_rewards
	_rewards_list.visible = has_rewards
	# 再描画で行が重複しないよう、前の行を外して解放する（remove_child で数をすぐ減らす）
	for old_row in _rewards_list.get_children():
		_rewards_list.remove_child(old_row)
		old_row.queue_free()
	for display in rewards:
		var row: RewardRow = REWARD_ROW_SCENE.instantiate()
		_rewards_list.add_child(row)
		row.setup(display)


func _play_stamps(section: CalendarSection, delay: float) -> void:
	for cell in section.cells:
		_stamp_player.play(cell, delay)


## 取得（FROM_HOME の list）の失敗を出す。エラー文＋「再試行」（429 は待ち）。タップでホームへ戻れる（TapCatcher は常に有効）。
## SESSION_EXPIRED は agreement と同じく、文を見せてからタイトルへ戻る。
func _show_load_error(error: AppError) -> void:
	_status_label.visible = true
	if error.kind == AppError.Kind.SESSION_EXPIRED:
		_status_label.text = ErrorMessages.text(error)
		await _go_title_after_notice()
		return
	await ErrorView.show_error(_status_label, _retry_button, error)


## SESSION_EXPIRED の共通の終わり方（取得・受け取り・取り直しのどれでも同じ）: 文を見せ、session_notice_sec 秒後に
## タイトルへ戻る。待つ前に _is_leaving を立てるので、その間はボタンも閉じるタップ（ホームへ戻る）も効かない。
func _go_title_after_notice() -> void:
	_is_leaving = true
	await get_tree().create_timer(session_notice_sec).timeout
	if not is_inside_tree():
		return
	_router.goto_title()


func _on_retry_pressed() -> void:
	# 押した直後にボタンを隠して多重に押せないようにする（_load_screen の _show_loading が隠す）
	_load_screen()


## 受け取りボタンの置き場（VIP の段の下・報酬の行の上）。_receive_offer.visible が真のときだけボタンを出す。
## 押せない状態の印（灰色のボタンなど）は出さない（H4）。メッセージ（失敗の文）だけ残るときは枠だけ出す。
func _render_receive_slot() -> void:
	_receive_button.visible = _receive_offer.visible
	_receive_button.disabled = _is_receiving
	_receive_button.text = RECEIVING_LABEL if _is_receiving else RECEIVE_LABEL
	_receive_slot.visible = _receive_offer.visible or _receive_message.visible


## 受け取りボタンの下のメッセージ（失敗の文）。空文字なら隠す。
func _set_receive_message(text: String) -> void:
	_receive_message.text = text
	_receive_message.visible = text != ""


## 受け取りボタンが押された（3-2）。二重送信を防ぎ、成功・失敗で画面を更新する。
func _on_receive_pressed() -> void:
	# 連打・受け取り中の再タップ・ボタンが出ていない（古い値）・UseCase 未設定のときは何もしない。
	# _is_receiving は await の前に同期で立てるので、同じフレームの 2 回目は弾かれる
	# ボタンが無効（受け取り中・429 の待ち）のときも送らない（signal を直接出されても弾く）
	if (
		_is_receiving
		or _is_leaving
		or _receive_button.disabled
		or not _receive_offer.visible
		or _receive_vip == null
	):
		return
	_is_receiving = true
	_set_receive_message("")
	_render_receive_slot()
	# --- 冪等キー: 空なら作る。通信断・409・503 の再送は前のキーのまま（3-4） ---
	if _receive_key == "":
		_receive_key = IdempotencyKey.generate()
	var result := await _receive_vip.handle(_receive_offer.mst_vip_login_bonus_id, _receive_key)
	# 待っている間に画面が破棄された（ホームへ戻った等）なら、何も触らない（1-5 の 4）
	if _is_leaving or not is_inside_tree():
		return
	_is_receiving = false
	if result.ok:
		_on_receive_succeeded(result)
	else:
		await _on_receive_failed(result.error)


## 成功: 画面の値を作り直して描く。VIP の今日のマスだけスタンプを外して押し直し（Q-5）、通常の段は再生しない。
## 「今日配られた報酬」には再受け取りの報酬を足す（FROM_LOGIN は login の行の後ろ、FROM_HOME はこの報酬だけ。Q-3）。
## 所持数は UseCase が ApplyUpdatedResourcesUseCase で反映済み。
func _on_receive_succeeded(result: ReceiveVipLoginBonusResult) -> void:
	# 成功の後は新しいキー（同じキーだと保存済みの応答が返るだけ。3-4）
	_receive_key = ""
	_set_receive_message("")
	# 再生中のスタンプがあれば止める（作り直しでマスが入れ替わり、解放済みのマスを Tween が触らないように）
	_stamp_player.kill_all()
	var is_login := entry == Entry.FROM_LOGIN
	var screen := _get_screen.handle(_masters, is_login, true, false, result.rewards)
	render(screen, RE_RECEIVE_DELAY)


## 失敗: BUSINESS は状態を取り直す。それ以外はエラー文を出してボタンを戻す。
func _on_receive_failed(error: AppError) -> void:
	match error.kind:
		AppError.Kind.SESSION_EXPIRED:
			await _expire_session(error)
		AppError.Kind.BUSINESS:
			await _refresh_after_business_error()
		_:
			# 通信断・409・503・429 など。キーは変えず（応答が届いていないだけかもしれない）、文を出してボタンを戻す
			_set_receive_message(ErrorMessages.text(error))
			_render_receive_slot()
			_lock_button_for_rate_limit(error)


## 受け取り・取り直しの SESSION_EXPIRED: ボタンを消して文を出し、タイトルへ戻る（取得の失敗と同じ経路）。
func _expire_session(error: AppError) -> void:
	_is_receiving = false
	_receive_offer = ReceiveOffer.new()
	_set_receive_message(ErrorMessages.text(error))
	_render_receive_slot()
	await _go_title_after_notice()


## 429 のときは retry_after の間だけボタンを無効にする（ErrorView と同じ。自動では再送しない）。
func _lock_button_for_rate_limit(error: AppError) -> void:
	var seconds := ErrorMessages.retry_lock_seconds(error)
	if seconds <= 0:
		return
	_receive_button.disabled = true
	await get_tree().create_timer(float(seconds)).timeout
	if _is_leaving or not is_inside_tree() or _is_receiving:
		return
	_receive_button.disabled = false


## 業務エラー（26001〜26003 など。コードでは分岐しない）の後: キーを作り直し、状態を取り直して画面を更新する。
## ボタンは取得結果で出し直す（もう受け取れないなら消える）。取り直しに失敗したら、表示は維持したままボタンを消してエラー文。
func _refresh_after_business_error() -> void:
	# 業務エラーも保存される（HTTP 299 が 24 時間再生される）ので、同じキーで再送すると古いエラーが返り続ける（3-4）
	_receive_key = IdempotencyKey.generate()
	_is_receiving = true  # 取り直しの間も二重に押せない・閉じない
	_render_receive_slot()
	var fetched: FetchLoginBonusCalendarsResult = null
	if _fetch_calendars != null:
		fetched = await _fetch_calendars.handle()
	if _is_leaving or not is_inside_tree():
		return
	if fetched != null and not fetched.ok and fetched.error.kind == AppError.Kind.SESSION_EXPIRED:
		await _expire_session(fetched.error)
		return
	if fetched == null or not fetched.ok:
		_is_receiving = false
		# 古い状態でボタンを押させない（ボタンを消し、今の画面の表示は維持）
		_receive_offer = ReceiveOffer.new()
		_set_receive_message(ErrorMessages.text(fetched.error if fetched != null else null))
		_render_receive_slot()
		return
	# 取り直した進捗の段の ID（VIP のレベルが変わると ID も変わる）でマスターを引き直す
	var prepared := await _prepare_master.handle(_repository.calendars())
	if _is_leaving or not is_inside_tree():
		return
	_is_receiving = false
	_masters = prepared.masters
	_stamp_player.kill_all()
	# アニメーションなし（確認のみ）。FROM_LOGIN は login の行を残す
	var screen := _get_screen.handle(_masters, entry == Entry.FROM_LOGIN, false)
	_set_receive_message("")
	render(screen)
	if _toast != null:
		_toast.show_toast(REFRESHED_TOAST, "")


## 端末の安全領域を Margin の余白に足す（モバイルのみ。デスクトップは基本の余白だけ）。
func _apply_safe_area() -> void:
	var margins := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if SafeAreaMargins.is_safe_area_platform(OS.get_name()):
		margins = SafeAreaMargins.to_viewport(
			DisplayServer.get_display_safe_area(),
			DisplayServer.window_get_size(),
			get_viewport().get_visible_rect().size
		)
	apply_safe_margins(margins)


## 安全領域の余白（SafeAreaMargins.to_viewport の戻り値の形）を、基本の余白に足して Margin へ反映する。
## 実機以外で「安全領域つき」の高さを確かめるため（tests・debug のプレビュー）に public にしている。
func apply_safe_margins(margins: Dictionary) -> void:
	_margin.add_theme_constant_override("margin_left", BASE_MARGIN_SIDE + int(margins["left"]))
	_margin.add_theme_constant_override("margin_right", BASE_MARGIN_SIDE + int(margins["right"]))
	_margin.add_theme_constant_override("margin_top", BASE_MARGIN_VERTICAL + int(margins["top"]))
	_margin.add_theme_constant_override(
		"margin_bottom", BASE_MARGIN_VERTICAL + int(margins["bottom"])
	)


## 表示する文を組み立てる。受取なしなら受け取り済みの文言。
static func build_text(displays: Array[LoginBonusDisplay]) -> String:
	if displays.is_empty():
		return "本日のログインボーナス\nは受け取り済みです"
	var lines: Array[String] = ["ログインボーナス!"]
	for display in displays:
		lines.append(_build_item_label(display))
	return "\n".join(lines)


## 1 件分の行。metadata に grade があるときだけグレードを添える
## （課金ボーナスの metadata は {"is_paid": true} などで、grade があるとは限らない）。
## 名前が決まる行（マスターの名前・無償ダイヤの固定名）は「名前 x数量」、それ以外は「種別 (ID:…) x数量」。
static func _build_item_label(display: LoginBonusDisplay) -> String:
	return "  " + build_row_text(display)


## 報酬 1 件の文字（先頭の字下げなし）。文字の画面の 1 行と、「今日配られた報酬」の行（reward_row）が共用する。
static func build_row_text(display: LoginBonusDisplay) -> String:
	var bonus := display.bonus
	var name := _display_name(display)
	# 名前がある行は ID を出さない（ID のままより読みやすいため。設計 3-2）
	var head := name if name != "" else "%s (ID:%s)" % [_resource_type_label(bonus.type), bonus.id]
	if bonus.has_grade():
		return "%s グレード%d x%d" % [head, int(bonus.metadata["grade"]), bonus.amount]
	return "%s x%d" % [head, bonus.amount]


## 名前で出せる行の名前を返す。出せない行は空文字（種別と ID の形で出す）。
## 優先: マスターの名前 → 無償ダイヤの固定名（マスターが同梱 DB・名前行なしでも「アイテム (ID:free_diamond)」にしない）。
static func _display_name(display: LoginBonusDisplay) -> String:
	if display.item_name != "":
		return display.item_name
	if display.bonus.is_free_diamond():
		return LoginBonus.FREE_DIAMOND_FALLBACK_NAME
	return ""


## リソースの種別を表示用の文字にする。未知の種別（旧 diamond・paid_diamond を含む）はそのまま出す
## （旧クライアント互換の特別扱いはしない。設計 3-2・P3）。
static func _resource_type_label(type: String) -> String:
	match type:
		"gold":
			return "ゴールド"
		"stamina":
			return "スタミナ"
		"unit":
			return "ユニット"
		"equipment":
			return "装備"
		"item":
			return "アイテム"
		_:
			return type


## TapCatcher（背面）に届いたタップ（マウスの左ボタン・タッチ）。ボタン以外のタップだけがここへ来る。
func _on_tap_catcher_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_screen_tapped()
	elif event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_on_screen_tapped()


## 画面がタップされた。アニメーション中なら最終状態へ飛ぶだけ（K4）、そうでなければホームへ（1 回だけ）。
func _on_screen_tapped() -> void:
	# 閉じ済み、または受け取り中は閉じない（所持数の反映前にホームへ戻らない。3-2 の 5）
	if _is_leaving or _is_receiving:
		return
	if _stamp_player != null and _stamp_player.is_running():
		_stamp_player.finish_all()
		return
	_is_leaving = true
	_router.goto_home()
