# アセット

## 背景動画（自作）

`assets/video/bg_loop.ogv`（タイトル・ログインボーナス・ホームの背景）は自作の動画で、外部の素材は使っていない。夜空のグラデーション・横にたなびく霧状の薄い雲（周期的なノイズを重ねた帯を、奥は暗く遅く・手前は明るく速く動かす）・星・流れ星を numpy で描いて生成している（1080x1920・25fps・20 秒・音声なし・シームレスにループ・約 1.9MB。1,869,429 B）。月・光のにじみ・霧の月明かりは動画に含めず、実行時に `core/presentation/background_moon` が重ね描きする（満ち欠けは端末の現在時刻から決まる。設計: `docs/design/background-moon-phase/client_design.md`）。

- 生成スクリプト: `tools/bg_video/generate_bg_video.py`（Ogg Theora への変換は同じ場所の `yuv2theora.c`。libtheora を使う小さな C のエンコーダで、スクリプトが clang でビルドする）
- 作り直し: `python3 tools/bg_video/generate_bg_video.py`（numpy・clang・libtheora/libogg が要る。macOS は `brew install theora`）。乱数の種は固定なので、同じ動画になる
- ビルドした実行ファイルは `build/bgvideo/` に出る（git に入れない）

## アイコン（自作）

`assets/icons/` のアイコン（SVG）は自作で、外部の素材・フォント・画像は使っていない（クライアントは公開リポジトリなので、ライセンスの問題を避ける）。`THIRD_PARTY_NOTICES.md` は変えない。要件・設計は Nexus の `docs/requirements/login-bonus-calendar.md`（I1〜I12）と、この機能の `docs/design/login-bonus-calendar/client_design.md` の 5 節。

### 置き場と規格

| 置き場 | 内容 |
| --- | --- |
| `assets/icons/items/<mst_item.id>.svg` | `mst_item` の全行（29 点）。ID で引く（例: `coin.svg`・`free_diamond.svg`・`stamina_50.svg`） |
| `assets/icons/fallback/category_<mst_item.type>.svg` | カテゴリの汎用の絵（9 種類）。ID の絵が無いときに出す |
| `assets/icons/fallback/unknown.svg` | 最後の砦（未知の ID・`unit`・`equipment` などの報酬。枠のアイコンは対象外） |
| `assets/icons/ui/stamp_check.svg` | カレンダーのスタンプ |
| `core/presentation/item_icon/item_icon_table.gd` | 生成物。キー（例 `items/coin`）→ `preload` した絵の表 |

- 規格: ビューボックス 128×128（`width`・`height` も 128）・余白 8（図形は 8〜120 の内側）・背景は透明・線の太さは 4 以上 10 以下（輪郭線は使わない。線は「?」だけ）・文字・ラスター画像・フィルターなし・1 枚 4KB 以下。フラットな塗りに、ごく控えめな縦のグラデーション（明 → 基準）と、床の半透明の楕円の影。色は夜空（青紫）に合わせた限定パレット（`generate_icons.py` の `PALETTE`）を全アイコンで共有する。同じカテゴリは形を共通にし、色・中身の量・小さな丸の印の数で見分ける。形が違う差（強化薬の記号・ポイントのバッジの記号）も入れ、色だけで意味を伝えない
- 読み込み: 動的なパス（`"res://assets/icons/%s.svg" % id` の `load`）は使わない。`ItemIcon`（`core/presentation/item_icon/`）が `ItemIconResolver`（`core/domain/`）で絵のキーを決め、`ItemIconTable` の `preload` から引く。順は ① `items/<id>` → ② `fallback/category_<type>`（`mst_item` が引けたとき）→ ③ `fallback/unknown`。どの段でも例外・空表示にしない
- import は SVG の既定（スケール 1.0）。`.svg.import` はリポジトリに入れる

### 生成と検査（再生成の手順）

- 生成: `make icons`（= `python3 tools/icons/generate_icons.py`。標準ライブラリだけの Python 3.9 以上。乱数を使わないので、何度実行しても同じ出力）。図形のテンプレート（瓶・フラスコ・結晶・カード・袋・コイン・延べ棒・宝石・バッジなど）と、ID ごとの差分の表（`SPECS`。色・中身の量・印の数）から、全 SVG と `item_icon_table.gd` を出力する
- 検査: `make check-icons`（= `python3 tools/icons/check_icons.py`。`make check` に含む）。生成の出力と同じ内容か（手編集・再生成し忘れ）、表に無い SVG・SVG の無い表の行、各 SVG の規格を検査する。検査ツール自身の単体テストは `tools/tests/test_check_icons.py`（`make check-deps` が先に回す）
- 見た目の確認: `godot --path . res://debug/icon_gallery.tscn`（全アイコンを 1 枚に並べる。端末に取得済みのマスターがあれば、絵の無い ID を赤く出す）。撮影は末尾に `-- --e2e-shot=<出力先ディレクトリ>`（ヘッドレスでは描画されないので撮れない）
- **`mst_item` に行が増えたとき**: `tools/icons/generate_icons.py` の `ITEMS`（ID と type）と `SPECS`（テンプレートと差分）に 1 行ずつ足して `make icons`。足し忘れても画面は壊れない（カテゴリの絵か `unknown` が出る）が、ギャラリーが赤く出す。`mst_item.type` が増えたときは `FALLBACK_SPECS` にも足す。`ITEMS` の正本はサーバーの `MstItemSeeder`（二重管理）
- 作り方の段取り: 先に比較用の 3 点（`free_diamond`・`gold`・`unknown`）で画風と import 後の容量を確かめてから全点を作った

### 容量の実測（R4）

基準は「アイコン全体 1MB 以内（目安）、かつ背景動画（約 1.9MB）を超えない」。(a) は SVG のバイト数の合計、(b) は import 後の `.godot/imported/` の該当 `.ctex` の合計、(c) は製品用の複製（`make release-project`）を `--export-pack` で pck にしたときの、アイコンあり・なしのサイズ差（アイコンの表 `item_icon_table.gd` を含む。書き出しテンプレートは要らない）。

| 時点 | (a) SVG | (b) import 後 | (c) pck の差 |
| --- | --- | --- | --- |
| 比較用の 3 点（`free_diamond`・`gold`・`unknown`） | 2,427 B | 9,122 B | 10,468 B |
| 全 40 点（`items` 29・`fallback` 10・`ui` 1） | 41,792 B | 155,552 B（約 152KB） | 176,660 B（約 173KB） |

背景動画 `bg_loop.ogv` は 1,869,429 B（月を外して作り直した値。旧版は 2,028,637 B）。アイコン全体は 1MB を大きく下回り、動画の約 9% で、基準を満たす。(c) は pck の差で、実機の APK / IPA の容量そのものではない（実機の書き出しは未確認。CLAUDE.md の「未確認」）。
