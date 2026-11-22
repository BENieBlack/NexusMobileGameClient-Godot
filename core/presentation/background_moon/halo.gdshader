// 月のまわりの光（client_design 1-3。光のにじみ Glow と霧の月明かり FogLight が共有する）。
//
// 月の中心からのガウス型 exp(-(d / sigma_px)^2) に、色と強さを掛けて加算合成で足す。
// 旧動画の光のにじみ（img += ガウス * 0.28 * 色）と同じ式なので、加算合成で同じ見た目になる。
// 矩形は BackgroundMoon が「sigma の 3 倍以上」で置く（ガウスは 3 倍で約 0.01%）。それでも矩形の縁で
// 値が飛ばないよう、縁の手前で 0 へなめらかに落とす係数 edge_fade を掛ける（2.2 倍で切ると
// ガウスが約 0.8% 残って縞が出るため）。
shader_type canvas_item;
render_mode blend_add;

// ガウスの広がり（ピクセル）
uniform float sigma_px = 212.5;
// 矩形の半辺（ピクセル。UV を中心からの距離へ直すために使う）
uniform float half_size_px = 640.0;
// 光の色（0〜1）
uniform vec3 light_color = vec3(0.58824, 0.58824, 0.74510);
// 強さ。照らされる割合（illumination）に比例した値が BackgroundMoon から入る
uniform float strength = 0.28;

void fragment() {
	float d = length((UV - vec2(0.5)) * 2.0 * half_size_px) / sigma_px;
	float gauss = exp(-d * d);
	// 矩形の縁（中心から半辺の位置）で 0、その 80% の位置までは 1
	float edge_fade = 1.0 - smoothstep(0.8, 1.0, length(UV - vec2(0.5)) * 2.0);
	COLOR = vec4(light_color * strength * gauss * edge_fade, 1.0);
}
