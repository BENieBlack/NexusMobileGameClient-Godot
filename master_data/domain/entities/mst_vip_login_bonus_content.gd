## VIP ログインボーナスの報酬 1 行（mst_vip_login_bonus_content）の読み取りモデル。
##
## 列（実スキーマ）: id（文字列。形はサーバーの設計に従う。ここでは値を解釈しない）・
##   mst_vip_login_bonus_id・day・content_type・content_mst_id・
##   content_option（JSON）・content_quantity・amount（報酬の倍率）・sort_desc。
## 通常の行と違い deploy_key・is_paid は無い。判断は持たない。
class_name MstVipLoginBonusContent
extends RefCounted

var id: String = ""
var mst_vip_login_bonus_id: String = ""
var day: int = 0
var content_type: String = ""
var content_mst_id: String = ""
var content_option: Dictionary = {}
var content_quantity: int = 0
## 報酬の倍率（VIP の行）
var amount: int = 0
var sort_desc: int = 0


## 実際の数量 = content_quantity × amount（サーバーと同じ式）。
func total_quantity() -> int:
	return content_quantity * amount
