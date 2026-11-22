## カレンダーの 1 マス（client_design.md 1-2・1-3・6）。
##
## 目的: CalendarCellView（1 日分の表示値）を、「N 日目」・ItemIcon・数量・「＋n」・「今日」の印・縁取り・
##       スタンプで描く。状態の切り替えの入口は apply_state(state, play) の 1 つ（引数は常にこの 2 つ）。
## 状態の見た目（1-3 の表）:
##   TODAY    明るさそのまま・太い縁取り・「今日」の印。スタンプは play が偽なら押印済み、真なら押される前（隠れている）
##   RECEIVED 少し暗く（0.8）・押印済み
##   FUTURE   彩度・明るさを落とす（目安。modulate の色で近似。シェーダは使わない＝60fps の軽量化）
##   NEUTRAL  通常。強調・スタンプなし
## play = true のとき、このマスはスタンプのアニメーション待ち。スタンプを実際に押すのは StampPlayer
## （Tween はホストの Node から作るため。6 節）。play = false が「最終状態へ即時に飛ぶ」入口
## （再表示・過去のマス・アニメーション中のタップによるスキップ）。
## 負荷（7 節）: マスに影つきの PanelContainer を使わない。枠は影なしの StyleBoxFlat の Panel 1 枚だけ。
## タップ: 全ノードが mouse_filter = IGNORE（閉じるタップを TapCatcher へ通す。1-1 の規則）。
class_name CalendarCell
extends Control

## 状態ごとの Content（絵と文字）の色。受け取り済みは明るさ 0.8、未来は彩度 0.5・明るさ 0.7 を近似する
## （modulate は掛け算なので、彩度の低下は「青灰色への寄せ」で表す。設計の「目安」。実装時に画面で調整する仮置き）
const COLOR_NORMAL := Color(1, 1, 1, 1)
const COLOR_RECEIVED := Color(0.8, 0.8, 0.8, 1)
const COLOR_FUTURE := Color(0.72, 0.74, 0.82, 1)
## 「今日」の縁取り（黄〜橙・太さ 4。仮置き）と、通常の縁取り
const BORDER_TODAY := Color(1.0, 0.55, 0.1, 1)
const BORDER_NORMAL := Color(1.0, 0.9, 0.4, 0.55)
const BORDER_TODAY_WIDTH := 4
const BORDER_NORMAL_WIDTH := 2
## 「今日」の脈動（C4）。周期 1.2 秒・拡大は 1.04 倍まで（押印前だけ。6 節）
const PULSE_SCALE := 1.04
const PULSE_PERIOD := 1.2
## スタンプの一辺。マスの 5〜6 割（設計の「7〜8 割」より小さい）。「N 日目」「今日」と数量の文字を押印後も
## 読めるよう、絵（マスの上から 46〜134）の位置に収める（レビュー指摘。理由は設計 6 節の注記）。tscn の offset と合わせる
const STAMP_SIZE := 88.0

var state: CalendarCellView.State = CalendarCellView.State.NEUTRAL
## スタンプのアニメーション待ち（apply_state(state, true) で真。押印後・最終状態へ飛ぶと偽）
var is_waiting_stamp: bool = false

var _pulse_tween: Tween = null

@onready var _frame: Panel = $Frame
@onready var _content: VBoxContainer = $Content
@onready var _day_label: Label = $Content/DayRow/DayLabel
@onready var _icon_holder: CenterContainer = $Content/IconHolder
@onready var _icon: ItemIcon = $Content/IconHolder/ItemIcon
@onready var _amount_row: HBoxContainer = $Content/AmountRow
@onready var _quantity_label: Label = $Content/AmountRow/QuantityLabel
@onready var _extra_label: Label = $Content/AmountRow/ExtraLabel
@onready var _today_badge: Label = $Content/DayRow/TodayBadge
@onready var _stamp: TextureRect = $Stamp


func _ready() -> void:
	# 枠の押しつぶされない最低限のサイズ。縮尺（脈動）の中心を枠の中央に保つ
	_frame.resized.connect(_update_frame_pivot)
	_stamp.pivot_offset = Vector2(STAMP_SIZE, STAMP_SIZE) / 2.0
	_stamp.texture = ItemIconTable.texture_of("ui/stamp_check")
	_stamp.visible = false


## 1 日分の中身（文字・絵）を入れる。状態は apply_state で別に切り替える。
## icon_size: 絵の一辺（通常 80・VIP 72）。
func setup(view: CalendarCellView, icon_size: int) -> void:
	_day_label.text = CalendarText.day_text(view.day)
	_icon.setup(view.icon_type, view.icon_id, view.icon_mst_item_type, icon_size)
	# 報酬の無い日は数量なし（unknown の絵のみ。1-3）。行ごと隠すと高さが揃わなくなるので、
	# 数量の行は見えなくするだけにして高さを保つ
	_quantity_label.text = "" if view.is_empty else CalendarText.quantity_text(view.quantity)
	_extra_label.text = "" if view.extra_count <= 0 else CalendarText.extra_text(view.extra_count)
	_extra_label.visible = view.extra_count > 0
	_today_badge.text = CalendarText.TODAY_BADGE
	# 高さは中身から決める（絵が通常 80・VIP 72 で変わるため。上下の余白 6×2 を足す）
	custom_minimum_size.y = _content.get_combined_minimum_size().y + 12.0


## 状態を切り替える。play が偽なら最終状態（押印済み・縁取りの強調）へ即時、真なら
## 「押される前」の状態にして StampPlayer の再生を待つ（6 節）。
func apply_state(new_state: CalendarCellView.State, play: bool) -> void:
	state = new_state
	_stop_pulse()
	# --- 1. 絵・文字の明るさ・彩度 ---
	match new_state:
		CalendarCellView.State.RECEIVED:
			_content.modulate = COLOR_RECEIVED
		CalendarCellView.State.FUTURE:
			_content.modulate = COLOR_FUTURE
		_:
			_content.modulate = COLOR_NORMAL
	# --- 2. 縁取りと「今日」の印 ---
	var is_today := new_state == CalendarCellView.State.TODAY
	_today_badge.visible = is_today
	_frame.add_theme_stylebox_override("panel", _make_frame_style(is_today))
	# --- 3. スタンプ ---
	# 押印済みになるのは今日（play が偽）と受け取り済み。再生待ちのときは隠し、StampPlayer が押す
	var stamped := new_state == CalendarCellView.State.RECEIVED or (is_today and not play)
	is_waiting_stamp = is_today and play
	_set_stamp_final(stamped)
	# 再生するマスだけ、押される前に脈動する（押印後・再表示では止める。60fps の軽量化の第 1 段）
	if is_waiting_stamp and is_inside_tree():
		_start_pulse()
	# 即時に最終状態へ飛ぶときは、アニメーション中だった明るさ・縮尺も戻す
	modulate = Color(1, 1, 1, 1)
	_frame.scale = Vector2.ONE


## スタンプを最終状態（表示 or 非表示。表示なら縮尺 1・不透明）にする。
func _set_stamp_final(stamped: bool) -> void:
	_stamp.visible = stamped
	_stamp.scale = Vector2.ONE
	_stamp.modulate.a = 1.0


## StampPlayer が押す直前に呼ぶ: 脈動を止め、スタンプを「縮尺 2.0・透明度 0」の初期状態で出す。
func prepare_stamp_animation() -> void:
	_stop_pulse()
	_stamp.visible = true
	_stamp.scale = Vector2(2.0, 2.0)
	_stamp.modulate.a = 0.0


## 再受け取り用（V3c が使う）: 押印済みのスタンプを一度外して初期状態に戻す。
func reset_stamp() -> void:
	prepare_stamp_animation()


## スタンプの Control（StampPlayer が Tween の対象にする）。
func stamp_node() -> TextureRect:
	return _stamp


## 押印の完了（StampPlayer が呼ぶ）。再生待ちを解く。
func mark_stamped() -> void:
	is_waiting_stamp = false


func is_stamp_visible() -> bool:
	return _stamp.visible


func _make_frame_style(is_today: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	# 受け取り前後が見分けられるよう、背景は暗めの半透明（パネルの黄色の上で絵が浮く）
	style.bg_color = Color(0.35, 0.2, 0.02, 0.55)
	style.set_corner_radius_all(16)
	var width := BORDER_TODAY_WIDTH if is_today else BORDER_NORMAL_WIDTH
	style.set_border_width_all(width)
	style.border_color = BORDER_TODAY if is_today else BORDER_NORMAL
	# 影は付けない（7 節。影は描画コストが高く、14 マスぶんになるため）
	return style


func _update_frame_pivot() -> void:
	_frame.pivot_offset = _frame.size / 2.0


func _start_pulse() -> void:
	_update_frame_pivot()
	_pulse_tween = create_tween().set_loops()
	# 1.0 → 1.04 → 1.0 を周期 1.2 秒で（点滅ではなく拡大縮小。3 回/秒を超えない）
	_pulse_tween.tween_property(_frame, "scale", Vector2.ONE * PULSE_SCALE, PULSE_PERIOD / 2.0)
	_pulse_tween.tween_property(_frame, "scale", Vector2.ONE, PULSE_PERIOD / 2.0)


func _stop_pulse() -> void:
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	_pulse_tween = null
