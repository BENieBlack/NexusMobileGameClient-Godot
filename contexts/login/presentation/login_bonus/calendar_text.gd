## カレンダー画面の固定文字を作る静的関数（client_design.md 1-3・1-2）。
##
## 目的: 「N 日目」「＋n」「VIP ボーナス　VIP n」などの文字を 1 か所に置き、presenter・部品・テストが同じ文字を使う。
##       言語は ja 固定（overview 7 節 h）。数量の桁区切りは NumberText（ホームと同じ規則）。
## 名前はマスに出さない（C3）。名前は「今日配られた報酬」の行だけ（LoginBonusPresenter.build_row_text）。
class_name CalendarText
extends RefCounted

const NORMAL_HEADER := "ログインボーナス"
const VIP_HEADER := "VIP ボーナス"
const RECEIVED_NOTICE := "本日のログインボーナスは受け取り済みです"
const REWARDS_HEADER := "今日配られた報酬"
const LOADING := "読み込み中…"
const TODAY_BADGE := "今日"


## 「N 日目」。
static func day_text(day: int) -> String:
	return "%d 日目" % day


## マスの数量。例: 1500 → "x1,500"（報酬の行の「名前 x数量」と記号を揃える）。
static func quantity_text(quantity: int) -> String:
	return "x" + NumberText.format_number(quantity)


## 1 日に複数の報酬があるときの「＋n」（n = 件数 − 1。Q14）。全角のプラス。
static func extra_text(extra_count: int) -> String:
	return "＋%d" % extra_count


## 段の見出し。VIP は「VIP ボーナス　VIP n」（n はサーバーが返す対象レベル。0 なら「VIP ボーナス」だけ）。
static func stage_header(is_vip: bool, vip_level: int) -> String:
	if not is_vip:
		return NORMAL_HEADER
	if vip_level <= 0:
		return VIP_HEADER
	# 区切りは全角スペース（設計 1-2 の表記）
	return "%s　VIP %d" % [VIP_HEADER, vip_level]
