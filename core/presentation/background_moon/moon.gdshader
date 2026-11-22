// 月の本体（client_design 1-3）。円の内側を、明るい側（月の色）と暗い側（地球照）で塗り分け、
// 月面の模様・やわらかい陰影・周縁減光で立体的に見せる。外部の画像は使わず、すべて手続きで描く。
//
// 描く矩形: 月の中心を中心にした正方形の ColorRect（BackgroundMoon が置く）。UV は 0〜1。
// 明暗の境目の式（位相に対して連続）:
//   p = 半径で正規化した座標（円の中は |p| <= 1、x は右が正）
//   edge = a - cos_phase * sqrt(1 - b^2)   （> 0 が明るい側。境目は楕円。a は明るい縁の向き L の成分、
//   b は L に垂直な成分。傾きなしなら a = lit_sign * p.x、b = p.y）
//   cos_phase = cos(2π * 位相)。新月 1・上弦と下弦 0・満月 -1。
// 境目は硬い線にせず、edge を terminator_soft の幅でなだらかに落として、光る面から暗い面へ
// 徐々に暗くなる陰影にする。月面の模様は p に固定した（満ち欠けで動かない）ノイズ。
shader_type canvas_item;

// ---- 満ち欠け（BackgroundMoon が画面を開いたときに設定する値）----
// cos(2π * 位相)
uniform float cos_phase = 1.0;
// 光る側。右が光るなら +1、左なら -1（南半球は BackgroundMoon が反転して渡す）
uniform float lit_sign = 1.0;
// 明るい縁の向きの傾き（ラジアン。基準の向き［lit_sign の向き］から、画面で反時計回りが正。MoonTilt が近似する）。
// 回すのは明暗の境目（と、それに従う地球照の側）だけ。月面の模様・周縁減光は向き固定のまま
uniform float tilt = 0.0;
// 月の半径（画面のピクセル。縁のぼかしの幅を正規化座標へ直すために使う）
uniform float radius_px = 125.0;
// 矩形の半辺 / 月の半径（縁のぼかしがはみ出さないよう、矩形は半径より少し大きい）
uniform float rect_scale = 1.1;

// ---- 見た目の調整値（人が最終判断する。client_design「実装で決まった値」）----
// 月の色（旧動画の月 (250,250,255)。明るい側の地の色）
uniform vec3 moon_color = vec3(0.98039, 0.98039, 1.0);
// 【控えめ版（人の決定 2026-11-22: 「ちょっとリッチすぎる」）。次の 6 つが見た目の強さの調整値で、
//  1 行ずつ直せる。旧三日月の白くすっきりした印象を保ちつつ、半月が硬い線だけにならない程度】
// 暗い側の地球照の色（青みがかった弱い光）と濃さ（アルファ）。新月でも位置が分かる程度（要件 F7）のごく薄さ
uniform vec3 earthshine_color = vec3(0.60, 0.68, 0.92);
uniform float earthshine_alpha = 0.10;
// 明暗の境目のやわらかさ（正規化座標での幅。大きいほど陰影が長く伸びる。0 に近いと硬い線）。
// 半月まわりはこの幅のまま。細い三日月・満月・新月の近く（|cos_phase| が 0.5 を超えるとき）だけ自動で狭まり、
// 細い三日月が陰影に食われて消えない（強い版の陰影の見た目を、半月・半月に近い形では保つ）
uniform float terminator_soft = 0.30;
// 月面の模様の濃さ。海（大きな暗い斑）・細かい濃淡・クレーター。0 で模様なし。かすかに分かる程度
uniform float maria_strength = 0.05;
uniform float mottle_strength = 0.015;
uniform float crater_strength = 0.04;
// 周縁減光: 縁に向かって暗くなる量（0 で一様、1 で縁が真っ暗）
uniform float limb_darkening = 0.07;
// 縁のぼかしの幅（ピクセル。旧動画の月の縁と同じ約 1.5px）
uniform float aa_px = 1.5;

// 2 次元の値ノイズ用のハッシュ（0〜1）
float hash21(vec2 q) {
	q = fract(q * vec2(123.34, 456.21));
	q += dot(q, q + 45.32);
	return fract(q.x * q.y);
}

float value_noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 4 オクターブを重ねた濃淡（おおよそ 0〜0.94）
float fbm(vec2 q) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * value_noise(q);
		q = q * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return v;
}

// 小さなクレーター 1 つ（中心 c・半径 r の、縁が少し明るく中が少し暗い円）。戻り値は明るさの増減
float crater(vec2 p, vec2 c, float r) {
	float d = length(p - c) / r;
	float bowl = -0.5 * (1.0 - smoothstep(0.55, 0.95, d));
	float rim = 0.45 * exp(-pow((d - 1.0) * 4.0, 2.0));
	return (bowl + rim) * (1.0 - smoothstep(1.2, 1.6, d));
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 * rect_scale;
	float aa = aa_px / radius_px;
	float r = length(p);

	// 円の被覆率（外周をぼかす）
	float disc = clamp(0.5 - (r - 1.0) / aa, 0.0, 1.0);

	// ---- 明るい側の割合 lit（0 = 暗い側、1 = 明るい側）。境目をなだらかに落とす ----
	// 明るい縁の向き L（画面の座標。y は下向きが正なので、反時計回りの tilt では y を反転する）。
	// tilt = 0 なら (lit_sign, 0)。a = p の L 方向の成分、b = L に垂直な成分（旧式の p.x・p.y に相当）
	vec2 lit_dir = vec2(cos(tilt), -sin(tilt)) * lit_sign;
	float a = dot(p, lit_dir);
	float b = p.x * lit_dir.y - p.y * lit_dir.x;
	float edge = a - cos_phase * sqrt(1.0 - min(b * b, 1.0));
	// 満月・新月では終端線が円の外周と重なる。そのままだと外周が半分だけ明るく（暗く）なるので、
	// 位相がそこへ近づくにつれ、境目の位置をなだらかに明るい側（満月）・暗い側（新月）へずらす。
	// 中間の位相（|cos| < 0.6）ではずらさず、満ち欠けの形は式のとおり
	float bias = (1.0 - smoothstep(-1.0, -0.6, cos_phase)) - smoothstep(0.6, 1.0, cos_phase);
	// 境目の幅: 半月まわりは terminator_soft、細い三日月・満月・新月に近いほど狭める（細い三日月を陰影で食わない）
	float soft = max(terminator_soft * (1.0 - smoothstep(0.5, 0.95, abs(cos_phase))), 0.02);
	float lit = smoothstep(-soft, soft, edge + soft * bias);

	// ---- 月面の模様（向き固定。p だけで決まり、満ち欠けで動かない）----
	float maria = smoothstep(0.47, 0.60, fbm(p * 1.7 + vec2(3.1, 1.7)));
	float mottle = fbm(p * 5.0 + vec2(11.3, 5.9)) - 0.5;
	float craters = crater(p, vec2(-0.18, 0.62), 0.10) * 0.9 + crater(p, vec2(0.38, -0.30), 0.12) * 0.5;
	float albedo = 1.0 - maria_strength * maria - mottle_strength * mottle * 2.0 + crater_strength * craters;

	// ---- 周縁減光: 縁に向かってわずかに暗く ----
	float limb = 1.0 - limb_darkening * smoothstep(0.35, 1.0, r);

	// 明るい側: 月の色 × 模様 × 周縁減光。境目に近いほど（lit が小さいほど）暗い
	vec3 sunlit = moon_color * clamp(albedo * limb, 0.0, 1.0);
	// 暗い側: 地球照。模様はうっすらだけ見せる
	vec3 dark = earthshine_color * mix(1.0, albedo, 0.5);

	vec3 color = mix(dark, sunlit, lit);
	float alpha = disc * mix(earthshine_alpha, 1.0, lit);
	COLOR = vec4(color, alpha);
}
