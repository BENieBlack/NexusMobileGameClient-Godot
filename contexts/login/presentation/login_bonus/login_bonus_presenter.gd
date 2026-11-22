## ログインボーナス画面の presenter（client_design.md 1-2・3・6。V3b = login 直後の入口 FROM_LOGIN）。
##
## 目的: 直近の login で配られたログインボーナスを、カレンダー（通常の段・VIP の段・今日の強調・スタンプ）と
##       「今日配られた報酬」の行で見せ、ボタン以外のタップでホームへ進む。業務の判断はしない
##       （UseCase の結果 LoginBonusScreen を描くだけ）。この画面は通常通信しない。
## 流れ（_ready）:
##   1. 「読み込み中…」を出す（カレンダー・行は隠す）。マスターを引けないときだけ再取得の通信が入る（2-4）ので、
##      通常は同じフレームで消える
##   2. メモリの進捗（LoginBonusRepository.calendars()）で PrepareLoginBonusMasterUseCase.handle() を await
##      （古いマスターなら 1 回だけ再取得して引き直す）
##   3. GetLoginBonusScreenUseCase.handle(masters, true, true) が LoginBonusScreen を返す（同期。
##      引数は include_login_bonus_list・play_stamp_allowed）
##   4. 描画: use_text_fallback なら今の文字の画面（build_text）、そうでなければ段・再表示の旨・報酬の行。
##      今日のマス（is_granted_now の段）だけスタンプのアニメーション（通常 0.3 秒・VIP 0.5 秒開始。6 節）
## 閉じる操作（H5・1-1）: 背面の TapCatcher（全画面・mouse_filter = STOP）の gui_input でタップ（マウス左・タッチ）を
##   受けてホームへ。前面の表示専用ノードは全て mouse_filter = IGNORE（tests が走査して守る）。
##   アニメーション中のタップは最終状態へ飛ぶだけで閉じない（K4）。連打しても遷移は 1 回（_is_leaving）。
## 受け取りの枠（V3b では出さない）: LoginBonusScreen.receive_offer を _receive_offer に保持し、ボタンの置き場 ReceiveSlot
##   （VIP の段の下・報酬の行の上。常に非表示）を用意してある。V3c がここに受け取りボタンを足す。
## 安全領域: SafeAreaMargins（core/presentation）で Margin の余白に足す（モバイルのみ。基本の余白は上下 48。1-4）。
## 依存: LoginBonusRepository（進捗）・PrepareLoginBonusMasterUseCase・GetLoginBonusScreenUseCase。
##       遷移は既定ではオートロードの SceneRouter（テストは setup で偽物を渡す）。
class_name LoginBonusPresenter
extends Control

## 画面の入口。V3b は login 直後（FROM_LOGIN）だけ。ホームから開く FROM_HOME は V3c で足す
## （継承シーン login_bonus_from_home.tscn が @export の entry だけ変える。1-1）
enum Entry { FROM_LOGIN }

## この画面の基本の余白（ビューポート座標）。安全領域の分をこれに足す。
## 上下 48 は「ホームの 96 では 1512 が収まらない」ための値（1-4）
const BASE_MARGIN_SIDE := 48
const BASE_MARGIN_VERTICAL := 48
## マスの絵の一辺（1-4 の確定値。通常 80・VIP 72）
const NORMAL_ICON_SIZE := 80
const VIP_ICON_SIZE := 72
const REWARD_ROW_SCENE := preload("res://contexts/login/presentation/login_bonus/reward_row.tscn")

@export var entry: Entry = Entry.FROM_LOGIN

## 最後に描いた画面の値（テストと確認用）
var current_screen: LoginBonusScreen = null

var _repository: LoginBonusRepository
var _prepare_master: PrepareLoginBonusMasterUseCase
var _get_screen: GetLoginBonusScreenUseCase
var _router: Object
var _is_configured: bool = false
var _is_leaving: bool = false
## 受け取りボタンの表示値（V3b は保持するだけ。V3c がボタンを出す）
var _receive_offer: ReceiveOffer = ReceiveOffer.new()
var _stamp_player: StampPlayer = null

@onready var _tap_catcher: Control = $TapCatcher
@onready var _margin: MarginContainer = $Margin
@onready var _notice_label: Label = $Margin/Center/Panel/VBox/NoticeLabel
@onready var _status_label: Label = $Margin/Center/Panel/VBox/StatusLabel
@onready var _normal_section: CalendarSection = $Margin/Center/Panel/VBox/NormalSection
@onready var _vip_section: CalendarSection = $Margin/Center/Panel/VBox/VipSection
@onready var _receive_slot: VBoxContainer = $Margin/Center/Panel/VBox/ReceiveSlot
@onready var _rewards_header: Label = $Margin/Center/Panel/VBox/RewardsHeader
@onready var _rewards_list: VBoxContainer = $Margin/Center/Panel/VBox/RewardsList
@onready var _bonus_bg: PanelContainer = $Margin/Center/Panel/VBox/BonusBg
@onready var _bonus_label: Label = $Margin/Center/Panel/VBox/BonusBg/BonusLabel
@onready var _tap_label: Label = $Margin/Center/Panel/VBox/TapBg/TapLabel


## UseCase・遷移の相手を渡す。_ready より前に呼ぶとその値を使い、呼ばなければ _ready がオートロードから取る。
func setup(
	repository: LoginBonusRepository,
	prepare_master: PrepareLoginBonusMasterUseCase,
	get_screen: GetLoginBonusScreenUseCase,
	router: Object
) -> void:
	_repository = repository
	_prepare_master = prepare_master
	_get_screen = get_screen
	_router = router
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(
			AppContext.login_bonus_repository(),
			AppContext.prepare_login_bonus_master_use_case(),
			AppContext.get_login_bonus_screen_use_case(),
			SceneRouter
		)
	_tap_label.text = "タップして続ける"
	_tap_catcher.gui_input.connect(_on_tap_catcher_input)
	_stamp_player = StampPlayer.new(self)
	_apply_safe_area()
	# --- 1. 読み込み中（再取得が要るときだけ見える） ---
	_show_loading()
	# --- 2. マスターを引く（古ければ 1 回だけ再取得。名前・絵の引きは画面を開くとき 1 回だけ） ---
	var prepared := await _prepare_master.handle(_repository.calendars())
	# 待っている間にホームへ戻った（画面が解放済み）なら、何も触らない（1-5 の 4）
	if _is_leaving or not is_inside_tree():
		return
	# --- 3. 表示モデルを作って描く（FROM_LOGIN は login_bonus_list の行を出し、スタンプを再生する） ---
	render(_get_screen.handle(prepared.masters, true, true))


func _exit_tree() -> void:
	# 画面を離れたら、再生中のスタンプの Tween を止める（離れた後にマスを触らない）
	if _stamp_player != null:
		_stamp_player.kill_all()


## 画面を描く（_ready と、V3c の取り直しから呼ぶ）。
func render(screen: LoginBonusScreen) -> void:
	current_screen = screen
	_receive_offer = screen.receive_offer
	_status_label.visible = false
	if screen.use_text_fallback:
		_render_text_fallback(screen)
	else:
		_render_calendar(screen)
	_render_receive_slot()


## 「読み込み中…」。カレンダー・行・文字の画面は隠す（背景動画・タイトル・タップの案内は出す）。
func _show_loading() -> void:
	_status_label.text = CalendarText.LOADING
	_status_label.visible = true
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
func _render_calendar(screen: LoginBonusScreen) -> void:
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
	_play_stamps(_vip_section, StampPlayer.VIP_DELAY)


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


## 受け取りボタンの置き場。V3b ではボタンを出さない（常に非表示）。
## V3c: _receive_offer.visible が真のとき ReceiveSlot にボタンを足して visible にする
## （押下で受け取り → スタンプの押し直し。3-2）。構造だけ先に決めておく。
func _render_receive_slot() -> void:
	_receive_slot.visible = false


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
	if _is_leaving:
		return
	if _stamp_player != null and _stamp_player.is_running():
		_stamp_player.finish_all()
		return
	_is_leaving = true
	_router.goto_home()
