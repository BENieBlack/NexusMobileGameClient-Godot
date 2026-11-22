## 「今日配られた報酬」の 1 行（client_design.md 1-2）: ItemIcon（56）＋「名前 x数量」。
##
## 名前の規則は今の build_text のまま（LoginBonusPresenter.build_row_text）。
## タップ: 全ノード mouse_filter = IGNORE（閉じるタップを TapCatcher へ通す。1-1）。
class_name RewardRow
extends HBoxContainer

## 行の絵の一辺（設計 1-4 の確定値。要件の目安 72 から縮めた）
const ICON_SIZE := 56

@onready var _icon: ItemIcon = $ItemIcon
@onready var _label: Label = $TextLabel


func setup(display: LoginBonusDisplay) -> void:
	_icon.setup(display.icon_type, display.bonus.id, display.item_type, ICON_SIZE)
	_label.text = LoginBonusPresenter.build_row_text(display)
