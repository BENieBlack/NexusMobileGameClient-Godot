## 端末のタイムゾーンから、南半球か北半球かを推定する純関数（client_design 4 節。F8・U-1）。
##
## 目的: 南半球では月の光る側が北半球と左右逆に見えるので、描画に渡す前に半球を決める。
## 背景: 取れる情報は bias（現在の UTC からの差・分。東が正。夏時間込み）と name（略称。IANA 名ではない）
##       だけで、場所（緯度）は使えない。bias は同じ値が南北にまたがる（例: UTC+10 は豪東部〔南〕も
##       ロシア極東〔北〕も使う）ので、bias だけでは決めきれない。
## 方式（案 C）: 上から順に、最初に当たったもので決める。
##   1. 名前（略称）が南の確定表に当たる → 南
##   2. 名前が IANA 名の形で、南の接頭辞（Australia/ など）で始まる → 南
##   3. bias が「南半球にしか無い」確定表に当たる → 南
##   4. それ以外（判別不能・赤道付近・南北混在）→ 北
## why: 「確実に南と言えるものだけ南、迷ったら北」にして、要件の既定（判別できないときは北）を守る。
##       確実でないものを誤って南にすることが無い。表への一致だけで決めるので夏時間の有無は結果に影響しない。
## 限界: 略称が返らない・数字の略称（例 `-03`）の環境では、UTC+10・+11・+12・-3:00 の南半球の地域は
##       北になる（client_design 4-3）。ブラジルなどの -3:00 を南にする案は採らない（U-1a）。
class_name Hemisphere
extends RefCounted

enum Kind { NORTH, SOUTH }

## 南半球の地域だけが使う略称
const SOUTH_NAMES: Array[String] = [
	"AEST",
	"AEDT",
	"ACST",
	"ACDT",
	"AWST",  # オーストラリア
	"NZST",
	"NZDT",  # ニュージーランド
	"CHAST",
	"CHADT",  # チャタム
	"LHST",
	"LHDT",  # ロード・ハウ
	"SAST",  # 南アフリカ・レソト・エスワティニ
]

## IANA 名の形（`/` を含む）のときの、南半球だけの接頭辞。IANA 名が返る環境があれば効き、無ければ使われない
const SOUTH_NAME_PREFIXES: Array[String] = ["Australia/", "Antarctica/"]

## 南半球の地域だけが使う UTC からの差（分）。端数の分を持つオフセットなど、地域が限られるもの。
## +10:00・+11:00・+12:00・-3:00 などは南北にまたがるので入れない
const SOUTH_BIAS_MINUTES: Array[int] = [525, 570, 630, 690, 765, 825, 780, -570]


## 名前（略称）と bias（分）から半球を決める。上の方式の順に判定する。
## 名前が空・不明、bias が表に無い、のときは北。
static func detect(zone_name: String, bias_minutes: int) -> Kind:
	if zone_name in SOUTH_NAMES:
		return Kind.SOUTH
	for prefix in SOUTH_NAME_PREFIXES:
		if zone_name.begins_with(prefix):
			return Kind.SOUTH
	if bias_minutes in SOUTH_BIAS_MINUTES:
		return Kind.SOUTH
	return Kind.NORTH
