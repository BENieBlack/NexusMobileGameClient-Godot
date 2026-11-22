## 背景の月（満ち欠けする月・光のにじみ・霧の月明かり）を描く共通部品（client_design 1 節。F5・F14）。
##
## 目的: タイトル・ログインボーナス・ホームの 3 画面が、BgVideo の直後に 1 ノードずつ置いて使う。
##       月は動画に焼き込まず、画面を開いたときの現在（端末時刻とタイムゾーン）から決めて重ね描きする。
## 流れ:
##   1. _ready で AppContext の GetBackgroundMoonUseCase から BackgroundMoonView を 1 回受け取る（F11。
##      画面は開くたびに作り直されるので、開くたびに決め直しになる。開いたままでは更新しない）
##   2. apply(view) が、子 3 つ（FogLight・Glow・Moon）の矩形とシェーダーの値を設定する
##   3. 矩形の大きさが変わったら（resized）、割合で持っている位置・半径から矩形を置き直す
## 月の見た目の調整値（暗い側の地球照・模様・陰影の濃さ）は moon.gdshader の uniform（名前とコメント付き）。
## 描く順: 子の並び（FogLight → Glow → Moon）。UI はこのノードより後ろにあるので月の上に出る。
## 位置・大きさ（旧動画の月の値が由来。tools/bg_video/generate_bg_video.py の旧版 make_base の
##   mx, my, r = 0.78W, 0.115H, 125px を、旧動画と同じ見た目に保つため引き継いだ。F4）:
##   - 中心 = このノードの矩形の (横 78%, 縦 11.5%)。BgVideo と同じ全面の矩形に対する割合なので、
##     動画と同じ座標系になり、画面の比率が違っても動画に付いてくる（1-2）
##   - 半径 = 幅の 125/1080（幅 1080 のとき 125px）
## 製品では動かない処理を持たない: _process は無い。値は画面を開いたときと resized のときだけ設定する。
class_name BackgroundMoon
extends Control

## 月の中心の位置（このノードの矩形に対する割合。旧動画の 0.78W・0.115H）
const CENTER_RATIO := Vector2(0.78, 0.115)
## 月の半径（幅に対する割合。旧動画の 125px / 1080px）
const RADIUS_PER_WIDTH := 125.0 / 1080.0
## 月の矩形の半辺 / 半径（縁のぼかし 1.5px がはみ出さない余白）
const MOON_RECT_SCALE := 1.1
## 光のにじみ（Glow）のガウスの広がり（半径の倍率。旧動画の 1.7r）
const GLOW_SIGMA_PER_RADIUS := 1.7
## 光のにじみの強さ（満月のとき。旧動画の 0.28）と色（旧動画の (150,150,190)）
const GLOW_STRENGTH := 0.28
const GLOW_COLOR := Color(150.0 / 255.0, 150.0 / 255.0, 190.0 / 255.0)
## 霧の月明かり（FogLight）のガウスの広がり（幅に対する割合。旧動画の 380px / 1080px）
const FOG_SIGMA_PER_WIDTH := 380.0 / 1080.0
## 霧の月明かりの強さ（満月のとき）と色（旧動画の明るい色 (205,205,235)）。
## 旧実装は「雲のある所だけが明るい色へ寄る」式（強さ 0.75）で、雲の位置を知らない重ね描きでは
## 再現できない。そこで全面の加算光の近似にし、強さは旧動画（git の履歴の月入り）と新しい合成を
## 同じコマで見比べて決めた値にしている（client_design 1-3・U-6）。決め方: 旧動画のコマから、月なしで
## 作り直した動画のコマと光のにじみ（Glow）の分を引いた残りを、ガウス（380px・色 FOG_COLOR）で最小二乗に
## 当てはめた（0〜18 秒の 8 コマで 0.031〜0.065、平均 約 0.046）
const FOG_STRENGTH := 0.05
const FOG_COLOR := Color(205.0 / 255.0, 205.0 / 255.0, 235.0 / 255.0)
## 光の矩形の半辺 / ガウスの広がり。3 倍以上でガウスは 0.01% 未満（halo.gdshader が縁をさらに 0 へ落とす）
const HALO_RECT_PER_SIGMA := 3.2

## 偽なら _ready で月の値を取りに行かない（テストが apply へ値を直接渡すため）
@export var load_on_ready := true

@onready var _fog_light: ColorRect = $FogLight
@onready var _glow: ColorRect = $Glow
@onready var _moon: ColorRect = $Moon


func _ready() -> void:
	resized.connect(_layout)
	_layout()
	if load_on_ready:
		apply(AppContext.get_background_moon_use_case().handle())


## 月の値をシェーダーに設定する。矩形も置き直す（公開。テストは AppContext を通さず直接呼ぶ）。
func apply(view: BackgroundMoonView) -> void:
	# 暗い側と明るい側の境目の式の値。位相 0 が新月（cos = 1）、0.5 が満月（cos = -1）
	var moon_material := _moon.material as ShaderMaterial
	moon_material.set_shader_parameter("cos_phase", cos(TAU * view.phase))
	# 光る側。右 = +1・左 = -1（南半球の反転は UseCase が lit_on_right に反映済み）
	moon_material.set_shader_parameter("lit_sign", 1.0 if view.lit_on_right else -1.0)
	# 明るい縁の傾き（時刻と位相から MoonTilt が近似。明暗の境目だけを回す）
	moon_material.set_shader_parameter("tilt", view.tilt_radians)
	moon_material.set_shader_parameter("rect_scale", MOON_RECT_SCALE)

	# 光のにじみ・霧の月明かりは、照らされている割合に比例（新月でほぼ消え、満月で最大。F13）
	_set_halo(_glow.material as ShaderMaterial, GLOW_COLOR, GLOW_STRENGTH * view.illumination)
	_set_halo(_fog_light.material as ShaderMaterial, FOG_COLOR, FOG_STRENGTH * view.illumination)
	_layout()


## 子 3 つの矩形と、画面のピクセルに依存するシェーダーの値を、今の矩形の大きさから置き直す。
func _layout() -> void:
	if _moon == null:
		return
	var center := Vector2(size.x * CENTER_RATIO.x, size.y * CENTER_RATIO.y)
	var radius := size.x * RADIUS_PER_WIDTH

	# 月: 半径の MOON_RECT_SCALE 倍の半辺を持つ正方形
	_place_centered(_moon, center, radius * MOON_RECT_SCALE)
	(_moon.material as ShaderMaterial).set_shader_parameter("radius_px", radius)

	# 光のにじみ・霧の月明かり: ガウスの広がりの HALO_RECT_PER_SIGMA 倍の半辺を持つ正方形
	var glow_sigma := radius * GLOW_SIGMA_PER_RADIUS
	var fog_sigma := size.x * FOG_SIGMA_PER_WIDTH
	_place_halo(_glow, center, glow_sigma)
	_place_halo(_fog_light, center, fog_sigma)


func _place_halo(rect: ColorRect, center: Vector2, sigma: float) -> void:
	var half := sigma * HALO_RECT_PER_SIGMA
	_place_centered(rect, center, half)
	var halo_material := rect.material as ShaderMaterial
	halo_material.set_shader_parameter("sigma_px", sigma)
	halo_material.set_shader_parameter("half_size_px", half)


func _set_halo(halo_material: ShaderMaterial, color: Color, strength: float) -> void:
	halo_material.set_shader_parameter("light_color", Vector3(color.r, color.g, color.b))
	halo_material.set_shader_parameter("strength", strength)


## center を中心にした、半辺 half の正方形に ColorRect を置く。
func _place_centered(rect: ColorRect, center: Vector2, half: float) -> void:
	rect.position = center - Vector2(half, half)
	rect.size = Vector2(half, half) * 2.0
