## ホーム画面の presenter（client_design.md 1-2・3-4）。
##
## 目的: プレイヤー（名前・ID・レベル）・スタミナ・通貨（コイン・ダイヤの合計）を出す。
##       計算・判定はしない。UseCase を呼んで、結果を HomeText で文字にしてラベルへ反映するだけ。
## 流れ:
##   1. ホームを開いたとき（_ready）と master_data_loaded のとき: GetHomeSummaryUseCase で表示値の束を作り直し、
##      全ラベルを反映する（マスターはこのときだけ読む）
##   2. スタミナの更新: StaminaTimer（1 秒）の tick と、バックグラウンドからの復帰
##      （NOTIFICATION_APPLICATION_RESUMED / FOCUS_IN）で GetStaminaDisplayUseCase を呼び、スタミナのラベルだけ更新する。
##      表示値は毎回「その時点の now」から求めるので、タイマーが遅れても積み上がらない
##   3. 残り時間が無い（最大値・計算不能・行なし）ときはタイマーを止める。状態が変われば（復帰・マスター更新）再開する
##   4. ホームを離れるとき（_exit_tree）はタイマーを止め、シグナルを切る
## 値の横のアイコン: スタミナ・コイン・ダイヤの値ラベルの左に ItemIcon（48）を置く（ItemIcon は core/presentation の共通部品）。
## 導線ボタン（メール・お知らせ）は枠だけで、押しても何も起きない（pressed を接続しない。P3）。
## セーフエリア: 端末のセーフエリアを SafeAreaMargins でビューポート座標へ直し、Margin の余白に足す。
## 依存: UseCase 2 つ（テストは setup で渡す）。
class_name HomePresenter
extends Control

## Margin の基本の余白（ビューポート座標）。セーフエリアの分をこれに足す
const BASE_MARGIN_SIDE := 48
const BASE_MARGIN_VERTICAL := 96

## 値の横のアイコンの一辺（ビューポート単位。要件 I10 のホームの大きさ）
const ICON_SIZE := 48

var _get_home_summary: GetHomeSummaryUseCase
var _get_stamina_display: GetStaminaDisplayUseCase
var _master_data_loaded: Signal
var _is_configured: bool = false
var _summary: HomeSummary = HomeSummary.new()

@onready var _margin: MarginContainer = $Margin
@onready var _name_label: Label = $Margin/Root/PlayerPanel/VBox/NameLabel
@onready var _id_label: Label = $Margin/Root/PlayerPanel/VBox/Row/IdLabel
@onready var _level_label: Label = $Margin/Root/PlayerPanel/VBox/Row/LevelLabel
@onready var _stamina_value_label: Label = $Margin/Root/StaminaPanel/VBox/ValueRow/StaminaValueLabel
@onready var _stamina_remain_label: Label = $Margin/Root/StaminaPanel/VBox/StaminaRemainLabel
@onready var _coin_label: Label = $Margin/Root/CurrencyRow/CoinPanel/VBox/ValueRow/CoinValueLabel
@onready
var _diamond_label: Label = $Margin/Root/CurrencyRow/DiamondPanel/VBox/ValueRow/DiamondValueLabel
@onready var _stamina_icon: ItemIcon = $Margin/Root/StaminaPanel/VBox/ValueRow/StaminaIcon
@onready var _coin_icon: ItemIcon = $Margin/Root/CurrencyRow/CoinPanel/VBox/ValueRow/CoinIcon
@onready
var _diamond_icon: ItemIcon = $Margin/Root/CurrencyRow/DiamondPanel/VBox/ValueRow/DiamondIcon
@onready var _timer: Timer = $StaminaTimer


## UseCase と master_data_loaded の購読元を渡す。_ready より前に呼ぶとその値を使い、呼ばなければ
## _ready がオートロードから取る。master_data_loaded は Signal() を渡せば購読しない。
func setup(
	get_home_summary: GetHomeSummaryUseCase,
	get_stamina_display: GetStaminaDisplayUseCase,
	master_data_loaded: Signal = Signal()
) -> void:
	_get_home_summary = get_home_summary
	_get_stamina_display = get_stamina_display
	_master_data_loaded = master_data_loaded
	_is_configured = true


func _ready() -> void:
	if not _is_configured:
		setup(
			AppContext.get_home_summary_use_case(),
			AppContext.get_stamina_display_use_case(),
			AppContext.check_master_data_use_case().master_data_loaded
		)
	_timer.wait_time = 1.0
	_timer.one_shot = false
	_timer.timeout.connect(_on_timer_timeout)
	if not _master_data_loaded.is_null():
		_master_data_loaded.connect(_on_master_data_loaded)
	_apply_safe_area()
	_setup_icons()
	reload()


func _exit_tree() -> void:
	# ホームを離れたら、タイマーを止めてマスター更新の購読を外す（離れた後に画面を触らないため）
	if _timer != null:
		_timer.stop()
	if (
		not _master_data_loaded.is_null()
		and _master_data_loaded.is_connected(_on_master_data_loaded)
	):
		_master_data_loaded.disconnect(_on_master_data_loaded)


## バックグラウンドからの復帰（モバイル）とウィンドウのフォーカス復帰で、その場で計算し直す（P4）。
## 経過した分は now から求めるので、一度に反映される。
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if _is_ready_for_update():
			refresh_stamina()


## 表示値の束を作り直して全ラベルを反映する（ホームを開いたときとマスター更新のとき）。
func reload() -> void:
	_summary = _get_home_summary.handle()
	_name_label.text = HomeText.name_text(_summary)
	_id_label.text = HomeText.id_text(_summary)
	_level_label.text = HomeText.level_text(_summary)
	_coin_label.text = HomeText.coin_text(_summary)
	_diamond_label.text = HomeText.diamond_text(_summary)
	refresh_stamina()


## 値の横のアイコン 3 つを出す（client_design.md 5-5）。ホームは master_data を使わず固定の ID で引く
## （絵は同梱の items/ に必ず在るので mst_item_type は渡さない）。無償ダイヤは「合計」を指すが、
## 合計用の絵は作らず free_diamond の絵を使う（D-1）。絵は値が変わっても変わらないので、開くとき 1 回だけ設定する。
func _setup_icons() -> void:
	_stamina_icon.setup("item", PlayerResourceIds.STAMINA_ICON_ITEM_ID, "", ICON_SIZE)
	_coin_icon.setup("item", PlayerResourceIds.COIN, "", ICON_SIZE)
	_diamond_icon.setup("item", PlayerResourceIds.FREE_DIAMOND, "", ICON_SIZE)


## スタミナのラベルだけ更新する。残り時間が無ければタイマーを止め、あれば（止まっていれば）再開する。
func refresh_stamina() -> void:
	var display := _get_stamina_display.handle(_summary.stamina_source)
	_stamina_value_label.text = HomeText.stamina_text(_summary, display)
	_stamina_remain_label.text = HomeText.remain_text(display)
	if display.seconds_to_next < 0:
		_timer.stop()
	elif _timer.is_stopped():
		_timer.start()


func _on_timer_timeout() -> void:
	refresh_stamina()


func _on_master_data_loaded() -> void:
	reload()


## _ready の前に通知が来ても落ちないようにする（@onready 変数と UseCase が揃っているか）。
func _is_ready_for_update() -> bool:
	return is_node_ready() and _get_stamina_display != null


## 端末のセーフエリアを Margin の余白に反映する。値は仮置きで、実機・シミュレーターで調整する（E6）。
## モバイル（iOS・Android）だけで適用する。デスクトップの get_display_safe_area() は「画面（モニター）座標の
## 作業領域」（メニューバー・Dock を除く）で、ウィンドウの位置・大きさと一致しないため、そのまま余白にすると
## 内容が画面の端へ押し出されて見切れる（実際に起きた）。デスクトップの余白は 0。
func _apply_safe_area() -> void:
	if not is_safe_area_platform(OS.get_name()):
		return
	var window_size := DisplayServer.window_get_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	var margins := SafeAreaMargins.to_viewport(safe, window_size, viewport_size)
	_margin.add_theme_constant_override("margin_left", BASE_MARGIN_SIDE + int(margins["left"]))
	_margin.add_theme_constant_override("margin_right", BASE_MARGIN_SIDE + int(margins["right"]))
	_margin.add_theme_constant_override("margin_top", BASE_MARGIN_VERTICAL + int(margins["top"]))
	_margin.add_theme_constant_override(
		"margin_bottom", BASE_MARGIN_VERTICAL + int(margins["bottom"])
	)


## セーフエリアを使う OS か（OS.get_name() の値を受ける純粋関数）。ノッチ・ホームバーがあるモバイルだけ。
static func is_safe_area_platform(os_name: String) -> bool:
	return SafeAreaMargins.is_safe_area_platform(os_name)
