## 月の傾き（空での月の明るい縁の向き）を、時刻と位相から近似する純関数（client_design 3-3 節）。
##
## 目的: 半月の明暗の境界が、いつも完全に上下になるのではなく、時刻（月の高さ・方角）に応じて
##       斜めになるようにする。位置情報は使わず、観測緯度は固定の近似値（±LATITUDE_DEG）。
## 結果: BackgroundMoonView.tilt_radians（明るい縁の向きを、基準の向き［右が光るなら右、左なら左］から
##       回した角。画面で反時計回りが正。正なら上向き寄り、負なら下向き寄り）。シェーダーが明暗だけを回す。
## 仮定（要件 F16。人の決定 2026-11-22）:
##   1. 太陽と月の赤緯は 0（天の赤道上）。季節・月の軌道の傾き（約 5 度）による違いは無視する
##   2. 観測緯度は北半球 +35 度、南半球 -35 度で固定。経度は現地時刻から近似する（現地平均太陽時 =
##      UTC + タイムゾーンの差。夏時間を含む時計のずれ・均時差は無視する。最大で 1 時間強 = 15 度ほどのずれ）
##   3. 月の位置（位相と太陽の時角）から、月の高度・方角を求めて傾きを出す。月の明るい縁は太陽の方を向く
## 式（導出）: 観測者の座標を x=東・y=北・z=天頂とする。赤緯 0・時角 H の天体の向き r と、時角が増える
##   向き（天の赤道に沿った西向き）w は、緯度 φ のとき
##     r = (-sin H, -cos H sin φ, cos H cos φ)      w = dr/dH = (-cos H, sin H sin φ, -sin H cos φ)
##   月の位置で見た画面の「上」u は、天頂 z から r 方向の成分を引いて正規化した向き（天頂に向かう向き）、
##   「右」は r × u（月を見る向きに対する右手側）。太陽は月の東に離角 E = 位相×360 度の所にあるので
##   H_月 = H_太陽 - E、H_太陽 = (現地太陽時 - 12 時)×15 度。明るい縁は赤道に沿って太陽の方を向く:
##   満ちていく間（E < 180 度）は西向き w、欠けていく間は東向き -w。その画面上の向き
##   (d・右, d・上) の角が ψ。基準の向き（右が光る = +x、左 = -x）からの回転が tilt。
##   φ = -35 度（南半球）を入れると、光る側の左右の反転も含めて、そのまま南半球の見え方になる。
## 検算（北緯 35 度）: 上弦が南中する 18 時は tilt ≈ 0（境界は上下・右が光る）、同じ上弦の 21 時は
##   右が下向きに約 45 度傾く、欠けていく下弦の 6 時は南中で tilt ≈ 0（左が光る）。
## 限界: 赤緯 0 の近似・固定の緯度・平均太陽時の近似のため、実際の月の傾きと数十度ずれることがある。
##   満月・新月は明るい縁が見えない（シェーダー側で影響しない）ので、値は任意（ここでは連続な値を返す）。
## 注意: `Time` や `OS` を使わない（core/domain は RefCounted だけ）。
class_name MoonTilt
extends RefCounted

## 固定の観測緯度（度。北半球は +、南半球は -）
const LATITUDE_DEG := 35.0


## 現地の太陽時（時。0 以上 24 未満）。UNIX 秒（UTC）にタイムゾーンの差（分。東が正）を足した 1 日の中の時刻。
static func local_solar_hours(unix: int, bias_minutes: int) -> float:
	return fposmod((float(unix) + float(bias_minutes) * 60.0) / 3600.0, 24.0)


## 傾き（ラジアン。-π〜π）。
## phase: 位相（0〜1）。local_hours: 現地の太陽時（時）。
## southern: 南半球か（緯度の符号）。lit_on_right: 基準の向きが右か（UseCase が半球で決めた値）。
static func tilt_radians(
	phase: float, local_hours: float, southern: bool, lit_on_right: bool
) -> float:
	var latitude := deg_to_rad(-LATITUDE_DEG if southern else LATITUDE_DEG)
	var elongation := TAU * phase
	var hour_angle_sun := deg_to_rad((local_hours - 12.0) * 15.0)
	var h := hour_angle_sun - elongation

	var sin_lat := sin(latitude)
	var cos_lat := cos(latitude)
	# 月の向き r と、時角が増える向き（西向き）w
	var r := Vector3(-sin(h), -cos(h) * sin_lat, cos(h) * cos_lat)
	var w := Vector3(-cos(h), sin(h) * sin_lat, -sin(h) * cos_lat)
	# 画面の上（天頂に向かう向き）と右（月を見る向きに対する右手側）
	var up := Vector3(0.0, 0.0, 1.0) - r * r.z
	if up.length() < 0.000001:
		# 月が天頂（または天底）にあって上が決まらない: 傾きなし
		return 0.0
	up = up.normalized()
	var right := r.cross(up)

	# 満ちていく間は西向き、欠けていく間は東向きに明るい縁がある（sin(離角) の符号。満月・新月で連続に 0 を跨ぐ）
	var direction := w if sin(elongation) >= 0.0 else -w
	var sign_base := 1.0 if lit_on_right else -1.0
	return atan2(sign_base * direction.dot(up), sign_base * direction.dot(right))
