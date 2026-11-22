## BackgroundMoon（背景の月の共通部品）の単体テスト（client_design 8 節）。
##
## 描画の見た目はヘッドレスでは検査できないので、シェーダーに渡す値（満ち欠けの式の値・向き・強さ・
## 位置・半径）と、3 画面への組み込み（ノードの並び・矩形が BgVideo と揃う）を確かめる。
## 見た目そのものは録画と静止画で人が見る（11 節）。
extends GdUnitTestSuite

const MOON_SCENE := "res://core/presentation/background_moon/background_moon.tscn"
## 3 画面の .tscn（ログインボーナスのホームから開く入口は基底を継承しているので別に確かめる）
const SCREENS := [
	"res://contexts/auth/presentation/title/title.tscn",
	"res://contexts/login/presentation/login_bonus/login_bonus.tscn",
	"res://contexts/login/presentation/login_bonus/login_bonus_from_home.tscn",
	"res://contexts/player/presentation/home/home.tscn",
]


## 値を直接渡せるよう load_on_ready を偽にして、ツリーに入れたシーンを返す（幅 1080・高さ 1920）。
func _make_moon() -> BackgroundMoon:
	var moon: BackgroundMoon = load(MOON_SCENE).instantiate()
	moon.load_on_ready = false
	add_child(moon)
	auto_free(moon)
	moon.size = Vector2(1080, 1920)
	return moon


func _view(phase: float, lit_on_right: bool) -> BackgroundMoonView:
	var illumination := (1.0 - cos(TAU * phase)) / 2.0
	return BackgroundMoonView.new(
		phase * MoonPhase.SYNODIC_DAYS,
		phase,
		illumination,
		phase < 0.5,
		lit_on_right,
		Hemisphere.Kind.NORTH
	)


func _param(node: Node, name: String) -> Variant:
	return (node as CanvasItem).material.get_shader_parameter(name)


## 前提: 新月・上弦・満月。期待: cos(2π 位相) が 1・0・-1（暗い側と明るい側の境目の式の値）。
func test_cos_phase_for_new_quarter_full() -> void:
	var moon := _make_moon()
	moon.apply(_view(0.0, true))
	assert_float(_param(moon.get_node("Moon"), "cos_phase")).is_equal_approx(1.0, 0.0001)
	moon.apply(_view(0.25, true))
	assert_float(_param(moon.get_node("Moon"), "cos_phase")).is_equal_approx(0.0, 0.0001)
	moon.apply(_view(0.5, true))
	assert_float(_param(moon.get_node("Moon"), "cos_phase")).is_equal_approx(-1.0, 0.0001)


## 前提: 右が光る・左が光る（南半球の反転後の値）。期待: 向きが +1 / -1。
func test_lit_sign_follows_lit_on_right() -> void:
	var moon := _make_moon()
	moon.apply(_view(0.25, true))
	assert_float(_param(moon.get_node("Moon"), "lit_sign")).is_equal(1.0)
	moon.apply(_view(0.75, false))
	assert_float(_param(moon.get_node("Moon"), "lit_sign")).is_equal(-1.0)


## 前提: 新月・上弦・満月。期待: にじみと霧の強さが illumination に比例（新月 0・上弦で半分・満月で最大）。
func test_halo_strength_is_proportional_to_illumination() -> void:
	var moon := _make_moon()
	moon.apply(_view(0.0, true))
	assert_float(_param(moon.get_node("Glow"), "strength")).is_equal_approx(0.0, 0.0001)
	assert_float(_param(moon.get_node("FogLight"), "strength")).is_equal_approx(0.0, 0.0001)
	moon.apply(_view(0.5, true))
	assert_float(_param(moon.get_node("Glow"), "strength")).is_equal_approx(
		BackgroundMoon.GLOW_STRENGTH, 0.0001
	)
	assert_float(_param(moon.get_node("FogLight"), "strength")).is_equal_approx(
		BackgroundMoon.FOG_STRENGTH, 0.0001
	)
	moon.apply(_view(0.25, true))
	assert_float(_param(moon.get_node("Glow"), "strength")).is_equal_approx(
		BackgroundMoon.GLOW_STRENGTH * 0.5, 0.0001
	)


## 前提: 傾きのある値（-45 度）。期待: 明暗の傾き tilt がシェーダーにそのまま渡る（模様は回さないので他の値は変わらない）。
func test_tilt_is_passed_to_shader() -> void:
	var moon := _make_moon()
	var view := BackgroundMoonView.new(
		7.38, 0.25, 0.5, true, true, Hemisphere.Kind.NORTH, deg_to_rad(-45.0)
	)
	moon.apply(view)
	assert_float(_param(moon.get_node("Moon"), "tilt")).is_equal_approx(deg_to_rad(-45.0), 0.0001)
	moon.apply(_view(0.25, true))
	assert_float(_param(moon.get_node("Moon"), "tilt")).is_equal(0.0)


## 前提: 幅 1080・高さ 1920。期待: 月の中心が (0.78W, 0.115H) = (842.4, 220.8)、半径 125px（旧動画と同じ）。
func test_moon_position_and_radius_match_old_video() -> void:
	var moon := _make_moon()
	moon.apply(_view(0.5, true))
	var rect: ColorRect = moon.get_node("Moon")
	var center := rect.position + rect.size / 2.0
	assert_vector(center).is_equal_approx(Vector2(842.4, 220.8), Vector2(0.01, 0.01))
	assert_float(_param(rect, "radius_px")).is_equal_approx(125.0, 0.001)
	# 光のにじみ（半径 1.7r）と霧の月明かり（380px）も同じ中心
	for name in ["Glow", "FogLight"]:
		var halo: ColorRect = moon.get_node(name)
		assert_vector(halo.position + halo.size / 2.0).is_equal_approx(
			Vector2(842.4, 220.8), Vector2(0.01, 0.01)
		)
	assert_float(_param(moon.get_node("Glow"), "sigma_px")).is_equal_approx(212.5, 0.001)
	assert_float(_param(moon.get_node("FogLight"), "sigma_px")).is_equal_approx(380.0, 0.001)


## 前提: 矩形の大きさを変える（resized）。期待: 割合で持っているので、中心と半径が追従する。
func test_layout_follows_resize() -> void:
	var moon := _make_moon()
	moon.apply(_view(0.5, true))
	moon.size = Vector2(540, 960)
	var rect: ColorRect = moon.get_node("Moon")
	assert_vector(rect.position + rect.size / 2.0).is_equal_approx(
		Vector2(421.2, 110.4), Vector2(0.01, 0.01)
	)
	assert_float(_param(rect, "radius_px")).is_equal_approx(62.5, 0.001)


## 前提: 光の 2 枚の矩形。期待: 半辺がガウスの広がりの 3 倍以上（縁でガウスがほぼ 0）。
func test_halo_rect_is_at_least_three_sigma() -> void:
	var moon := _make_moon()
	moon.apply(_view(0.5, true))
	for name in ["Glow", "FogLight"]:
		var halo: ColorRect = moon.get_node(name)
		assert_float(halo.size.x / 2.0 / _param(halo, "sigma_px")).is_greater_equal(3.0)
		assert_float(_param(halo, "half_size_px")).is_equal_approx(halo.size.x / 2.0, 0.001)


## 前提: 子 3 つ。期待: タップを奪わない（mouse_filter が無視）。部品自身も同じ。
func test_does_not_steal_input() -> void:
	var moon := _make_moon()
	assert_int(moon.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	for child in moon.get_children():
		assert_int((child as Control).mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


## 前提: 3 画面の .tscn（ログインボーナスは入口 2 つ）。期待: BackgroundMoon がちょうど 1 つあり、
## BgVideo の直後（UI より下）に並ぶ。新しい画面で足し忘れる・位置を間違えるのを防ぐ。
func test_screens_have_one_background_moon_right_after_bg_video() -> void:
	for path in SCREENS:
		var screen: Control = load(path).instantiate()
		auto_free(screen)
		var moons := screen.get_children().filter(func(n: Node) -> bool: return n is BackgroundMoon)
		assert_int(moons.size()).override_failure_message(path).is_equal(1)
		var video := screen.get_node("BgVideo")
		(
			assert_object(screen.get_child(video.get_index() + 1))
			. override_failure_message(path)
			. is_same(moons[0])
		)


## 前提: 3 画面。期待: 月の部品の矩形（アンカー・オフセット）が BgVideo と同じ全面で、動画と同じ座標系になる。
func test_background_moon_rect_matches_bg_video() -> void:
	for path in SCREENS:
		var screen: Control = load(path).instantiate()
		auto_free(screen)
		var video: Control = screen.get_node("BgVideo")
		var moons := screen.get_children().filter(func(n: Node) -> bool: return n is BackgroundMoon)
		var moon: Control = moons[0]
		for property in [
			"anchor_left",
			"anchor_top",
			"anchor_right",
			"anchor_bottom",
			"offset_left",
			"offset_top",
			"offset_right",
			"offset_bottom"
		]:
			(
				assert_float(moon.get(property))
				. override_failure_message("%s %s" % [path, property])
				. is_equal(video.get(property))
			)
