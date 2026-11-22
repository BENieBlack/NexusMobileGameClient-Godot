## ログインボーナス画面の表示用の値を作る UseCase（client_design.md 3-3）。
##
## 目的: 直近の login の受取（GetLoginBonusesUseCase）に、type が item の行の名前（mst_item の l10n）を
##       添えて返す。presenter が Repository を直接触らないための窓口。
## 流れ:
##   1. 受取の一覧を取る
##   2. 行ごとに、unit・equipment・stamina 以外は MstItemRepository を引く（item_type・is_wallet のため）。
##      名前（item_name）は type が item のときだけ入れる
##   3. 名前が引けない（行なし・name が空・Repository が null）は item_name を空にする。例外にしない
## display_of は 1 件分だけ作る入口（カレンダーのマスの報酬も同じ規則で作る）。
## 行数は数件なのでキャッシュは持たない。言語は Repository が持つ（この UseCase は知らない）。
class_name GetLoginBonusDisplaysUseCase
extends RefCounted

## mst_item の行ではない type（枠のアイコンの対象外・名前も別の規則。引かない）
const NON_ITEM_TYPES: Array[String] = ["unit", "equipment", "stamina"]

## 絵の引き方（ItemIconResolver）が「id で引く」type は item・wallet だけ。login_bonus_list の wallet 系の行は
## type が通貨の種類（gold・coin・food など。サーバーの ResourceType）で来るので、これらは item として id で引く
const WALLET_TYPES: Array[String] = ["gold", "coin", "food", "wood", "stone", "iron"]

var _get_login_bonuses: GetLoginBonusesUseCase
var _mst_item_repository: MstItemRepository


func _init(
	get_login_bonuses: GetLoginBonusesUseCase, mst_item_repository: MstItemRepository
) -> void:
	_get_login_bonuses = get_login_bonuses
	_mst_item_repository = mst_item_repository


## 表示用の値の一覧を返す（受取と同じ順）。
func handle() -> Array[LoginBonusDisplay]:
	var displays: Array[LoginBonusDisplay] = []
	for bonus in _get_login_bonuses.handle():
		displays.append(display_of(bonus))
	return displays


## 1 件分の表示用の値を作る。
func display_of(bonus: LoginBonus) -> LoginBonusDisplay:
	# 絵の type: item・wallet・wallet 系の通貨 type（gold など）は item として id で引く。
	# それ以外（unit・equipment・stamina・paid_diamond・未知）はそのまま（ItemIconResolver が unknown にする）
	var by_id := (
		bonus.type == LoginBonus.TYPE_ITEM or bonus.type == "wallet" or WALLET_TYPES.has(bonus.type)
	)
	# item・wallet は元の type のまま（どちらも id で引く）。gold などの通貨 type だけ item に読み替える
	var icon_type := LoginBonus.TYPE_ITEM if WALLET_TYPES.has(bonus.type) else bonus.type
	var item := _lookup_item(bonus)
	if item == null:
		return LoginBonusDisplay.new(bonus, "", "", false, icon_type)
	# 名前は id で引く行の mst_item の name（マスのグリッドと同じ引き方）。「(ID:…)」は引けないときだけ
	var item_name := item.name if by_id else ""
	return LoginBonusDisplay.new(bonus, item_name, item.type, item.is_wallet, icon_type)


## mst_item を引く（item・wallet・その他の未知の type。unit・equipment・stamina は mst_item の行ではないので引かない）。
## 引けない・ID が空・Repository が null は null。
func _lookup_item(bonus: LoginBonus) -> MstItem:
	if _mst_item_repository == null or bonus.id == "":
		return null
	if NON_ITEM_TYPES.has(bonus.type):
		return null
	return _mst_item_repository.get_by_id(bonus.id)
