## ログインボーナス 1 件の表示用の値（client_design.md 3-3）。
##
## 目的: 受取内容（LoginBonus）と、マスターから引いたアイテム名を 1 組にして presenter へ渡す。
## 項目:
##   bonus      受取内容そのもの
##   item_name  type が item で名前が引けたときだけ入る。それ以外（他の種別・引けない・空）は空文字
##   item_type  引けた mst_item.type（アイコンのカテゴリの絵に使う）。引けなければ空
##   is_wallet  引けた mst_item.is_wallet。引けなければ偽
##   icon_type  ItemIcon.setup に渡す type。login_bonus_list の wallet 系の行は type が gold・coin など
##              （サーバーの ResourceType）で来るが、絵は mst_item の id で引くので item に読み替えた値（空なら bonus.type）
## 名前が空のときの代替の文字は presenter が LoginBonus の定数から決める（ここは値だけ持つ）。
class_name LoginBonusDisplay
extends RefCounted

var bonus: LoginBonus
var item_name: String = ""
var item_type: String = ""
var is_wallet: bool = false
var icon_type: String = ""


func _init(
	p_bonus: LoginBonus = null,
	p_item_name: String = "",
	p_item_type: String = "",
	p_is_wallet: bool = false,
	p_icon_type: String = ""
) -> void:
	bonus = p_bonus
	item_name = p_item_name
	item_type = p_item_type
	is_wallet = p_is_wallet
	icon_type = p_icon_type if p_icon_type != "" else (p_bonus.type if p_bonus != null else "")
