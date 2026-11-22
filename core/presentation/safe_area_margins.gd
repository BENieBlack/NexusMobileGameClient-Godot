## 端末のセーフエリア（物理ピクセル）を、ビューポート座標の余白に直す純粋関数（client_design.md 1-2）。
##
## なぜ変換が要るか: DisplayServer.get_display_safe_area() は物理ピクセルの Rect2i を返す。一方レイアウトの値は
## ビューポート座標（project.godot は 1080x1920・stretch/mode=canvas_items）で、ウィンドウの大きさと
## 一致しない。そのまま余白に足すと実際の何倍もずれるので、ウィンドウサイズに対するビューポートサイズの
## 比（軸ごと）を掛けてから使う。
## エディタ・デスクトップではセーフエリアが全面と同じで、余白は 0。
class_name SafeAreaMargins
extends RefCounted

## 1 辺の余白がビューポートに占める割合の上限。座標系の取り違えなど異常な値で内容が画面外へ
## 押し出されないための安全弁（実際のノッチ・ホームバーはこの割合よりずっと小さい）
const MAX_RATIO := 0.2


## セーフエリアを使う OS か（OS.get_name() の値を受ける純粋関数）。ノッチ・ホームバーがあるモバイルだけ。
## デスクトップの get_display_safe_area() は「画面（モニター）座標の作業領域」でウィンドウと一致しないため使わない
## （ホームとログインボーナス画面が同じ判定を使う）。
static func is_safe_area_platform(os_name: String) -> bool:
	return os_name == "iOS" or os_name == "Android"


## 戻り値: {"left": float, "top": float, "right": float, "bottom": float}（ビューポート座標。0 以上）。
## safe: 物理ピクセルのセーフエリア。window_size: ウィンドウの物理ピクセル。viewport_size: ビューポートの大きさ。
## ウィンドウかセーフエリアの大きさが 0 以下（ヘッドレスなど値が取れない）なら、すべて 0。
static func to_viewport(safe: Rect2i, window_size: Vector2i, viewport_size: Vector2) -> Dictionary:
	var zero := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if window_size.x <= 0 or window_size.y <= 0:
		return zero
	if safe.size.x <= 0 or safe.size.y <= 0:
		return zero
	# 物理ピクセル → ビューポート座標の倍率（軸ごと）
	var scale_x := viewport_size.x / float(window_size.x)
	var scale_y := viewport_size.y / float(window_size.y)
	# 各辺の余白 = 画面端からセーフエリアの端までの物理ピクセル × 倍率。負（はみ出し）は 0 に丸める
	var max_x := viewport_size.x * MAX_RATIO
	var max_y := viewport_size.y * MAX_RATIO
	return {
		"left": clampf(safe.position.x * scale_x, 0.0, max_x),
		"top": clampf(safe.position.y * scale_y, 0.0, max_y),
		"right": clampf((window_size.x - safe.end.x) * scale_x, 0.0, max_x),
		"bottom": clampf((window_size.y - safe.end.y) * scale_y, 0.0, max_y),
	}
