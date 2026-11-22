## カレンダーの段 1 つ（通常または VIP）。client_design.md 1-2・1-4。
##
## 目的: 見出し（「ログインボーナス」/「VIP ボーナス　VIP n」）と、行ごとの HBoxContainer（1 行 4 マス）に
##       CalendarCell を並べる。行数はマスターの周期の日数（cycle_days）から決まる（7 日なら 2 行）。
## 最終日のマスは行の残りの幅を使う（size_flags_stretch_ratio = 空き列数 + 1）。cycle_days が 4 の倍数なら伸ばさない。
## 引数: setup(CalendarStageView, icon_size) … 絵の一辺は通常 80・VIP 72（設計 1-4 の確定値）。
## タップ: 全ノード mouse_filter = IGNORE（閉じるタップを TapCatcher へ通す。1-1）。
class_name CalendarSection
extends VBoxContainer

const CELL_SCENE := preload("res://contexts/login/presentation/login_bonus/calendar_cell.tscn")
## 1 行のマスの数と、マス・行の間隔（1-4 の見積りの前提。幅 800 − 内側 2×24 の中で 1 マス 約 179）
const COLUMNS := 4
const CELL_GAP := 12

## 並べたマス（日の昇順。1 日目が先頭）。presenter が状態の適用・スタンプの再生に使う
var cells: Array[CalendarCell] = []

@onready var _header: Label = $HeaderLabel
@onready var _rows: VBoxContainer = $Rows


## 段を描く。呼ぶのは 1 回だけ（作り直しは新しい段を作る）。
func setup(stage: CalendarStageView, icon_size: int) -> void:
	_header.text = CalendarText.stage_header(stage.is_vip, stage.vip_level)
	# 再描画（render の 2 回目以降）で行・マスが重複しないよう、前の行を外して解放する
	# （remove_child で子の数をすぐ減らす。queue_free だけだとフレーム末まで残る）
	for old_row in _rows.get_children():
		_rows.remove_child(old_row)
		old_row.queue_free()
	cells.clear()
	var row: HBoxContainer = null
	var index := 0
	for view in stage.cells:
		# 4 マスごとに新しい行
		if index % COLUMNS == 0:
			row = _new_row()
		var cell: CalendarCell = CELL_SCENE.instantiate()
		row.add_child(cell)
		cell.setup(view, icon_size)
		# 最終日のマスだけ残りの幅を使う（行の空き列数 + 1 倍の幅）
		if index == stage.cells.size() - 1:
			var empty_columns := COLUMNS - (index % COLUMNS) - 1
			cell.size_flags_stretch_ratio = float(empty_columns + 1)
		cells.append(cell)
		index += 1
	# 状態は全マスを入れたあとに適用する（再生するマスだけ play = true）
	for i in range(cells.size()):
		cells[i].apply_state(stage.cells[i].state, stage.cells[i].play_stamp)


## 再生待ちのマスが 1 つでもあるか（開始の遅れを段ごとに決めるため）。
func has_waiting_stamp() -> bool:
	for cell in cells:
		if cell.is_waiting_stamp:
			return true
	return false


func _new_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", CELL_GAP)
	_rows.add_child(row)
	return row
