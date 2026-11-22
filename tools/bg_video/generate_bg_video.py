#!/usr/bin/env python3
"""背景動画 assets/video/bg_loop.ogv を、外部素材なしで一から生成する。

夜空のグラデーション・ゆっくりたなびく霧状の雲・またたく星・時々走る流れ星を numpy で描き、
月は描かない（月の満ち欠け・光のにじみ・霧の月明かりは、実行時に core/presentation/background_moon が重ね描きする。
その位置・半径・色は、この動画に焼き込んでいた旧版の値が由来）。
同梱の小さな C エンコーダ（tools/bg_video/yuv2theora.c、libtheora を使う）で Ogg Theora にする。
Godot 4 が再生できる動画は Ogg Theora だけで、ffmpeg に libtheora が無い環境でも作れるようにするため。

シームレスなループの作り方: 動きはすべて「ループの長さ（SECONDS 秒）の周期」にする。
  - 雲: 横に周期的なノイズを、ちょうど 1 周ぶん（レイヤーの幅だけ）左へ動かす
  - 星のまたたき: 周期が SECONDS の約数になる正弦波
  - 流れ星: すべて SECONDS の内側で始まり、終わる（境目をまたがない）
  最後のコマの次が最初のコマになるので、継ぎ目で値が飛ばない。

必要なもの: python3 + numpy、clang、libtheora と libogg（macOS は brew install theora）。
使い方: python3 tools/bg_video/generate_bg_video.py [--out assets/video/bg_loop.ogv] [--bitrate 800000]
生成物のバイナリは build/bgvideo/ に置く（git に入れない）。
"""
import argparse
import math
import subprocess
import sys
from pathlib import Path

import numpy as np

WIDTH, HEIGHT, FPS, SECONDS = 1080, 1920, 25, 20
FRAMES = FPS * SECONDS
ROOT = Path(__file__).resolve().parents[2]
ENCODER_SRC = ROOT / "tools" / "bg_video" / "yuv2theora.c"
ENCODER_BIN = ROOT / "build" / "bgvideo" / "yuv2theora"


def build_encoder() -> None:
    """C エンコーダを clang でビルドする（ヘッダとライブラリの場所は brew の既定。環境変数で変えられる）。"""
    import os

    prefix = os.environ.get("THEORA_PREFIX", "/opt/homebrew")
    ENCODER_BIN.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        "clang", "-O2", "-Wall", f"-I{prefix}/include", f"-L{prefix}/lib",
        str(ENCODER_SRC), "-ltheoraenc", "-ltheoradec", "-logg", "-o", str(ENCODER_BIN),
    ]
    subprocess.run(cmd, check=True)


def lerp_gradient(stops, t):
    """縦位置 t（0..1 の配列）に対して、色の停止点（位置, RGB）を線形補間する。"""
    pos = [s[0] for s in stops]
    return np.stack([np.interp(t, pos, [s[1][c] for s in stops]) for c in range(3)], axis=-1)


def make_base(rng):
    """静止している背景（グラデーション + 細かいディザ。月は描かない）を作る。"""
    ys = np.linspace(0.0, 1.0, HEIGHT)
    grad = lerp_gradient(
        [(0.0, (36, 32, 68)), (0.35, (48, 50, 98)), (0.7, (66, 92, 128)), (1.0, (122, 146, 164))], ys
    )
    img = np.repeat(grad[:, None, :], WIDTH, axis=1).astype(np.float32)

    # 縞（バンディング）を目立たなくする静止ディザ
    img += rng.normal(0.0, 0.6, size=img.shape).astype(np.float32)
    return img


def periodic_noise(rng, width, height, cells_x, cells_y):
    """x 方向に周期 width でつながる値ノイズ（0..1）。セル数が少ないほどゆるやかな起伏になる。

    乱数の格子を滑らかに（smoothstep で）補間して作る。x は格子の端を反対側に巻き付けるので、
    width ぶん横にずらすとちょうど元に戻る（= シームレスなループの土台）。
    """
    grid = rng.random((cells_y + 1, cells_x)).astype(np.float32)

    def axis_weights(n, cells, wrap):
        pos = np.arange(n, dtype=np.float32) / n * cells
        i0 = np.floor(pos).astype(int)
        f = pos - i0
        f = f * f * (3 - 2 * f)  # smoothstep
        i1 = i0 + 1
        if wrap:
            i0, i1 = i0 % cells, i1 % cells
        return i0, i1, f

    x0, x1, fx = axis_weights(width, cells_x, True)
    y0, y1, fy = axis_weights(height, cells_y, False)
    top = grid[y0][:, x0] * (1 - fx) + grid[y0][:, x1] * fx
    bot = grid[y1][:, x0] * (1 - fx) + grid[y1][:, x1] * fx
    return top * (1 - fy[:, None]) + bot * fy[:, None]


class FogLayer:
    """横に長くたなびく霧状の薄い雲のレイヤー。1 ループでちょうど canvas_w だけ左へ動いて元に戻る。

    作り方: x 方向に周期的なノイズを数オクターブ重ね、縦はセル数を少なくして横長の筋にする。
    それを「しきい値のなだらかな段」で雲と空に分け（縁が硬くならない）、縦の帯の中心に寄せる
    ガウス型の重みを掛けて、上下がふんわり消える帯にする。
    """

    def __init__(self, seed, canvas_w, y_top, band_h, color, opacity, cells, thr=(0.4, 0.75)):
        rng = np.random.default_rng(seed)
        self.canvas_w, self.y_top, self.band_h = canvas_w, y_top, band_h
        # 数オクターブを重ねる（粗い起伏が主で、細かい起伏で霧のむらを足す）
        field = np.zeros((band_h, canvas_w), np.float32)
        total = 0.0
        for i, cx in enumerate(cells):
            amp = 0.55 ** i
            # セルの縦横比が約 1:4（横長）になるよう、縦のセル数を決める
            cy = max(2, round(4 * band_h * cx / canvas_w))
            field += amp * periodic_noise(rng, canvas_w, band_h, cx, cy)
            total += amp
        field /= total
        # しきい値のなだらかな段（thr[0] 以下は空、thr[1] 以上は濃い雲）
        t = np.clip((field - thr[0]) / (thr[1] - thr[0]), 0, 1)
        t = t * t * (3 - 2 * t)
        # 帯の上下をふんわり消す重み
        yy = (np.arange(band_h, dtype=np.float32) - band_h / 2) / (band_h / 2)
        env = np.exp(-(yy * 2.3) ** 2)[:, None]
        self.alpha = (t * env * opacity).astype(np.float32)
        self.color = np.array(color, np.float32)

    def draw(self, img, t_frac):
        """t_frac（0..1）に応じて左へ動かし、画面の幅（WIDTH）だけ切り出して合成する。"""
        shift = int(round(t_frac * self.canvas_w))
        a = np.roll(self.alpha, -shift, axis=1)[:, :WIDTH]
        region = img[self.y_top : self.y_top + self.band_h]
        region += (self.color - region) * a[..., None]


def draw_dot(img, x, y, radius, intensity, cross=0.0):
    """星 1 つ（ガウス型の点。cross > 0 なら十字のきらめきも足す）を加算で描く。"""
    pad = int(radius * 5 + cross + 2)
    x0, x1 = max(int(x) - pad, 0), min(int(x) + pad + 1, WIDTH)
    y0, y1 = max(int(y) - pad, 0), min(int(y) + pad + 1, HEIGHT)
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dy = xx - x, yy - y
    v = np.exp(-(dx * dx + dy * dy) / (2 * radius * radius))
    if cross > 0:
        v += 0.6 * (np.exp(-(dy / 1.1) ** 2) * np.exp(-np.abs(dx) / cross) + np.exp(-(dx / 1.1) ** 2) * np.exp(-np.abs(dy) / cross))
    img[y0:y1, x0:x1] += (v * intensity)[..., None] * np.array([235, 238, 255], np.float32) * 0.9


def draw_shooting_star(img, sx, sy, angle, length, travel, u):
    """流れ星 1 本。u（0..1）は進み具合。頭から尾に向かって細く薄くなる線を描く。"""
    dx, dy = math.cos(angle), math.sin(angle)
    hx, hy = sx + dx * travel * u, sy + dy * travel * u
    env = math.sin(math.pi * u)  # 出だしと終わりは淡く
    pad = 8
    xs = [hx, hx - dx * length]
    ys = [hy, hy - dy * length]
    x0, x1 = max(int(min(xs)) - pad, 0), min(int(max(xs)) + pad, WIDTH)
    y0, y1 = max(int(min(ys)) - pad, 0), min(int(max(ys)) + pad, HEIGHT)
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    rx, ry = hx - xx, hy - yy
    along = rx * dx + ry * dy  # 頭からの距離（尾の側が正）
    perp = np.abs(rx * dy - ry * dx)
    v = np.clip(1 - along / length, 0, 1) * (along >= -2) * np.exp(-(perp / 1.7) ** 2)
    img[y0:y1, x0:x1] += (v * env * 0.85)[..., None] * np.array([235, 240, 255], np.float32)


def to_yuv420(rgb):
    """RGB（float, 0..255）を BT.601 の yuv420p（Y 面・U 面・V 面を連結した bytes）にする。"""
    rgb = np.clip(rgb, 0, 255)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = 16 + (65.481 * r + 128.553 * g + 24.966 * b) / 255
    u = 128 + (-37.797 * r - 74.203 * g + 112.0 * b) / 255
    v = 128 + (112.0 * r - 93.786 * g - 18.214 * b) / 255

    def sub(p):  # 2x2 平均で色差を半分の解像度に
        return (p[0::2, 0::2] + p[1::2, 0::2] + p[0::2, 1::2] + p[1::2, 1::2]) / 4

    planes = [np.clip(np.rint(y), 16, 235), np.clip(np.rint(sub(u)), 16, 240), np.clip(np.rint(sub(v)), 16, 240)]
    return b"".join(p.astype(np.uint8).tobytes() for p in planes)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=str(ROOT / "assets" / "video" / "bg_loop.ogv"))
    ap.add_argument("--bitrate", type=int, default=800000, help="目標ビットレート(bps)")
    ap.add_argument("--frames", type=int, default=FRAMES, help="試し撮り用にコマ数を減らすとき（ループにはならない）")
    args = ap.parse_args()

    build_encoder()
    rng = np.random.default_rng(20240607)  # 固定の種: 何度作っても同じ動画になる
    base = make_base(rng)

    # 雲（霧状のたなびく帯）: 奥ほど暗く遅く、手前ほど明るく速い。1 ループで canvas の幅だけ動く
    # （幅 1080 / 1620 / 2160 → 54 / 81 / 108 px/秒。いずれも整数ピクセルでぴったり 1 周する）
    clouds = [
        FogLayer(11, 1080, 60, 760, (58, 62, 112), 0.85, (3, 6, 12)),
        FogLayer(23, 1620, 420, 800, (96, 108, 150), 0.8, (4, 8, 16)),
        FogLayer(37, 2160, 200, 620, (128, 140, 178), 0.7, (5, 10, 20), thr=(0.45, 0.8)),
    ]

    # 星: 位置・大きさ・またたきの周期（SECONDS の約数になるよう整数回）と位相を固定の乱数で決める
    stars = []
    for i in range(70):
        stars.append(dict(
            x=rng.uniform(20, WIDTH - 20), y=rng.uniform(40, HEIGHT * 0.72),
            r=rng.uniform(1.2, 2.2) if i >= 8 else rng.uniform(2.6, 3.4),
            base=rng.uniform(0.45, 0.8), k=int(rng.integers(1, 5)), ph=rng.uniform(0, 2 * math.pi),
            cross=14.0 if i < 8 else 0.0,
        ))

    # 流れ星: (開始秒, 長さ秒, 開始 x, 開始 y, 角度) すべて 0..SECONDS の内側に収める
    shooters = [
        (1.5, 1.0, 900, 300, math.radians(145)),
        (5.0, 0.9, 620, 120, math.radians(140)),
        (9.0, 1.1, 1000, 760, math.radians(150)),
        (13.0, 0.9, 760, 520, math.radians(142)),
        (16.4, 1.0, 960, 180, math.radians(146)),
    ]

    enc = subprocess.Popen([str(ENCODER_BIN), args.out, str(WIDTH), str(HEIGHT), str(FPS), str(args.bitrate)], stdin=subprocess.PIPE)
    for f in range(args.frames):
        t = f / FPS
        frac = f / FRAMES
        img = base.copy()
        for s in stars:
            tw = 0.5 + 0.5 * math.sin(2 * math.pi * s["k"] * frac + s["ph"])
            draw_dot(img, s["x"], s["y"], s["r"], s["base"] * (0.25 + 0.75 * tw), s["cross"] * tw)
        for t0, dur, sx, sy, ang in shooters:
            if t0 <= t < t0 + dur:
                draw_shooting_star(img, sx, sy, ang, 260, 760, (t - t0) / dur)
        for layer in clouds:
            layer.draw(img, frac)
        enc.stdin.write(to_yuv420(img))
        if f % 50 == 0:
            print(f"frame {f}/{args.frames}", file=sys.stderr)
    enc.stdin.close()
    return enc.wait()


if __name__ == "__main__":
    sys.exit(main())
