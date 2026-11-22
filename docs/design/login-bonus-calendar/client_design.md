# ログインボーナスのカレンダー表示とアイテムアイコン クライアント設計

- 要件（正。ここには複製せず記号で指す）: `Nexus/docs/requirements/login-bonus-calendar.md`（T = 今日の段、C = カレンダー、K = スタンプ、D = データ、I = アイコン、H = ホームの導線、R = 再受け取り、Q = 確認事項。Q1〜Q31 は確定済み）
- **全体設計・要件・サーバー設計の同時改訂（未マージ）**: 人の決定で、全日の報酬と周期の日数は応答から外れ、クライアントが配信の SQLite のマスターを ID で引いて描く（応答に残るのは段のマスター ID・進捗・VIP の `vip_level`・`can_re_receive`）。Nexus の要件・全体設計とサーバーの設計 md は**別の書き手が同時に直している（未マージ）**。この文書はその決定に先に合わせた。**マージ後に差分を確認する**（12 節）
- 全体設計（正。マージ済み）: `Nexus/docs/design/login-bonus-calendar/overview.md`（責務の分担 2 節、API の変更 3 節、判定 4 節、非機能 5 節、S4 への宿題 8 節、決定 D-1〜D-5・未解決 U-1〜U-10）
- サーバー設計（S2。**マージ済み**）: `NexusMobileGameServer-Laravel/docs/design/login-bonus-calendar/{db,api,sequence}.md`。**この文書の API の項目名・型・エラーコードはサーバーの api.md の確定名**（4 節に対応表。12 節の差分表 S-1〜S-10 で突き合わせ済み）。項目の正はサーバーの api.md で、ここには型と null の扱い（クライアントの責務）だけを書く
- 前提: [title-to-home](../title-to-home/client_design.md)（login・冪等キー 3-4・エラー 1-3）、[home-player-info](../home-player-info/client_design.md)、[free-diamond-item](../free-diamond-item/client_design.md)（名前の引き 3-2・3-3）
- 規約: `.claude/architecture.md`（3 層・master_data・依存ルール）、`.claude/coding-standards.md`（コメント）、`.claude/api.md`

旧クライアントは未配布で互換は持たない。ただし**新クライアント × 旧サーバー**（新キー・新 API が無い）では、カレンダーを出さず今の文字の画面に落とす（D4）。サーバーが先、クライアントは同じ時期に追従する。

## 0. 現状の確認結果（設計の前提。コードを読んで確かめた）

| # | 確認したこと | 場所 |
| --- | --- | --- |
| a | ログインボーナス画面は通信しない（今の画面）。`LoginBonusPresenter` が `GetLoginBonusDisplaysUseCase` の結果を 1 つの Label に複数行で出し、画面のどこでもタップ（`_input` でマウス左・タッチ）でホームへ。`_is_leaving` で二重遷移を防ぐ。アニメーションは無い | `contexts/login/presentation/login_bonus/` |
| b | 読み取りモデルは `LoginBonus`（6 項目）と `LoginBonusDisplay`（`bonus`・`item_name`）だけ。日数・全日・受け取り済みを持つモデルは無い。保持先 `LocalLoginBonusRepository` は `login_bonus_list` の配列だけをメモリに持つ | `contexts/login/domain/entities/`、`data/repositories/` |
| c | `LoginResponse.from_dict` は `sys_player`・`trx_diamond`・trx 5 種・`login_bonus_list` だけを読む（未知のキーは無視）。null・欠落は `JsonReader.get_array/get_dict` で `[]`/`{}` | `contexts/login/data/api/login_response.gd` |
| d | `LoginUseCase.handle` は取得 → `ApplyLoginDataUseCase`（player の公開 UseCase）→ `LoginBonusRepository.replace`。冪等キーは呼び出し元が持ち、`IdempotencyKey.can_reuse(kind)` で再利用を決める | `login_use_case.gd`、`core/domain/idempotency_key.gd` |
| e | `SceneRouter.goto_login_bonus()` は既にある。呼ぶのは agreement だけ。ホームからの導線は無い。遷移は `change_scene_to_file` で、**引数を渡す口は無い** | `app/scene_router.gd` |
| f | ホームは `_ready` で `reload()` し、PlayerRepository の現在値から全ラベルを作る。ホームを離れて戻ると `_ready` が走るので、再読み込みで最新になる。ナビ列 `NavRow` にメール・お知らせのボタン（`pressed` は未接続）とバッジの枠がある。`HomePresenter` はルーターを持たない（`setup` は UseCase 2 つと Signal） | `contexts/player/presentation/home/` |
| g | ホームの値は `Margin/Root/{StaminaPanel,CurrencyRow/CoinPanel,CurrencyRow/DiamondPanel}/VBox/*ValueLabel` の Label。コインは **`trx_wallet_list` の `mst_item_id = coin` の `free_amount`**（`CoinAmount`。`get_home_summary_use_case.gd` が `trx_wallet_list` を渡す）、無償ダイヤは `trx_item_list` の `free_diamond`（`DiamondTotal`。`PlayerResourceIds`）、スタミナは `trx_stamina_list` の `type = normal`。**`updated_resources` を取り込む UseCase は無い**（login 以外の応答を読む機能が無かった。`.claude/api.md` の末節） | `home_presenter.gd`、`coin_amount.gd`、`diamond_total.gd` |
| h | `MstItemRepository` は `get_by_id` だけ（全件を返す口は無い）。`MstItem` は `deploy_key`・`id`・`type`・`name`。`mst_item` は同梱 DB に無く、配信があるときだけ引ける | `master_data/` |
| i | `ApiClient.request(method, endpoint, body, options)`。`options` の `idempotency_key` で `X-Unique-Request-Identifier` を付ける。401 は自動 refresh。失敗は `ApiResult.to_app_error()` → `AppError.Kind` | `core/data/http/api_client.gd` |
| j | `ErrorView.show_error(label, retry_button, error)` と `ErrorMessages.text(error)` が、エラーの文言と再試行ボタン（429 は待ち）の共通部品。`SESSION_EXPIRED` は agreement がメッセージを見せてからタイトルへ戻す | `core/presentation/`、`agreement_presenter.gd` |
| k | `SafeAreaMargins`（純粋関数）は `player/presentation/home/` にあり、ホームだけが使う。ログインボーナス画面は使っていない。**他コンテキストの presentation から参照できるのは domain/use_cases だけ**（依存チェック P2）なので、そのままでは使えない | `safe_area_margins.gd`、`tools/check_dependencies.py` |
| l | `debug/e2e_driver.gd` は、ログインボーナス画面で「出てから `ACTION_DELAY`（1.5 秒）＋ `--e2e-dwell` 秒後に画面中央をクリック」、写真は 1.0 秒後（`SHOT_DELAY`）。クリックは**マウスボタン**（タッチではない）。シーンは `scene_file_path` で分岐する | `debug/e2e_driver.gd` |
| m | アイコン資産は無い。`assets/` は `fonts`・`ui`（Kenney）・`video`。SVG は `icon.svg` だけ。自作資産の生成スクリプトは `tools/bg_video/` と `docs/ASSETS.md` の前例がある。`tools/` と `debug/` は製品の複製から除外、`assets/` は含める。`make check-release` は `preload` の実在を検査する（`%` を含む動的パスは対象外） | `docs/ASSETS.md`、`tools/prepare_release_project.py` |
| n | `HomeText.format_number`（桁区切り）が home の presentation にある。他コンテキストからは参照できない | `home_text.gd` |

## 1. 画面・シーン構成と遷移

### 1-1. 入口と遷移

ログインボーナス画面は**2 つの入口**で開く。同じ presenter・同じ部品で、入口だけが違う。

| 入口 | 開き方 | データの出どころ | 通信 | アニメーション | 戻り先 |
| --- | --- | --- | --- | --- | --- |
| login 直後（`FROM_LOGIN`） | 規約画面（または規約なし）の次。今と同じ位置（`goto_login_bonus()`） | login 応答（メモリの `LoginBonusRepository`） | **しない** | 「今回配った」段（`is_granted_now`）のマスだけ（K1） | ホーム |
| ホームから（`FROM_HOME`） | ホームの「ログインボーナス」ボタン（`goto_login_bonus_from_home()`） | `POST /login_bonus/list` を**開くたびに**呼んで取得（login 応答は古くなりうるので使わない。H2） | **する**（開いた直後に 1 回） | **しない**（確認のみ。H3）。再受け取りの応答を受けたときだけ VIP のマス | ホーム |

```
タイトル → 規約 → [ログインボーナス FROM_LOGIN] → ホーム ⇄ [ログインボーナス FROM_HOME] → ホーム
                          │ 受け取りボタン（再受け取り可のときだけ）     │ 同左
                          └ POST /login_bonus/receive → 同じ画面でスタンプ → タップでホーム
```

- **入口の渡し方**: `SceneRouter` は遷移の引数を持たず、オートロードに状態を置かない方針（architecture.md 2 節）なので、**入口ごとにシーンを分ける**。`login_bonus.tscn`（`FROM_LOGIN`。既定）と、それを継承した `login_bonus_from_home.tscn`（ルートの `@export var entry` だけ `FROM_HOME` に変える継承シーン）。`SceneRouter` に `LOGIN_BONUS_FROM_HOME_SCENE` と `goto_login_bonus_from_home()` を足す。`debug/e2e_driver.gd` は `scene_file_path` で分岐するので、2 つのパスを別々に扱える（11 節）
- **閉じる操作（H5）**: 画面の**ボタン以外**のどこをタップ（マウス左・タッチ）してもホームへ。受け取りボタンのタップは閉じない。**アニメーション中のタップは、最終状態へ飛ぶだけで閉じない**（K4）。完了後のタップで閉じる。連打しても二重に遷移しない（`_is_leaving`）。「閉じるボタン」は足さない
- **タップの受け方**: 今は `_input` で全イベントを拾うので、ボタンのタップも拾ってしまう。**`TapCatcher`（全画面の Control。`mouse_filter = STOP`）を背面に置き、その `gui_input` で受ける**。**規則: `TapCatcher` より前面にある、画面を覆うコンテナ・表示専用の Control（`Margin`・`Panel`・`VBox`・`calendar_section`・マス・ラベル・`ItemIcon`・`TextureRect` すべて）は `mouse_filter = IGNORE`**（`MarginContainer`・`PanelContainer` の既定は `STOP` なので、シーンを作るときに全部変える。1 つでも漏れるとその範囲のタップが閉じなくなる）。`STOP` にするのは受け取りボタン・再試行ボタンだけ。**例外**: 報酬の行を `ScrollContainer` にしたとき（縮め方③）は `STOP`（スクロールを受けるため。この範囲のタップは閉じない）。**受け取りボタンは受け取り中（無効化中）も `STOP` のまま**にする（二重タップがボタンを貫通して画面を閉じないため）。**受け取り中はタップで閉じない**（3-2 の 5 に合わせる）。テストで、シーン内の「`TapCatcher` より後ろの子孫」の `Control` を走査して、`Button`・`ScrollContainer` 以外は `IGNORE` を検査する（ルート・`BgVideo`・`TapCatcher` 自身は対象外。ルートは `STOP` でも `IGNORE` でもよい）。こうするとボタン上のタップは `TapCatcher` に届かない。マウス左とタッチ（`InputEventScreenTouch`）の両方を受け、二重に来ても `_is_leaving` で 1 回にする
- **ホームで再受け取りした後に戻ったとき**: ホームは `_ready` の `reload()` で PlayerRepository から作り直すので、所持数は 3-3 の取り込みだけで最新になる（ホーム側にイベント購読は足さない）
- 規約画面の前後の遷移・タイトルへの戻り（`SESSION_EXPIRED`）は変えない

### 1-2. シーン構成（`contexts/login/presentation/login_bonus/`）

```
LoginBonus (Control, login_bonus_presenter.gd)         … 入口 entry を @export
├─ BgVideo (VideoStreamPlayer)                          … 既存の背景動画
├─ TapCatcher (Control, 全画面, mouse_filter=STOP)       … 閉じるタップを受ける
└─ Margin (MarginContainer)                              … 安全領域の余白（1-4）
   └─ Panel (PanelContainer, 幅 800)                     … 既存の黄色いパネル（mouse_filter=IGNORE）
      └─ VBox
         ├─ TitleLabel                                   … 「ログインボーナス！」（星の行は 1-4 で外す）
         ├─ NoticeLabel                                  … 「本日のログインボーナスは受け取り済みです」（出す条件は 1-3）
         ├─ StatusLabel / RetryButton                    … FROM_HOME の読み込み中・失敗（1-5）
         ├─ NormalSection (calendar_section.tscn)        … 通常の段（null なら非表示）
         ├─ VipSection (calendar_section.tscn)           … VIP の段（null なら非表示）
         ├─ ReceiveButton                                … 再受け取りが可能なときだけ表示（VIP の段の下）
         ├─ RewardsHeader + RewardsList (VBox)           … 「今日配られた報酬」の行（reward_row.tscn の並び）
         ├─ TextFallbackLabel                            … 文字の画面（1-3 の「カレンダーを出さない」場合。今の BonusLabel）
         └─ TapLabel                                     … 「タップして続ける」
```

| 部品（シーン + スクリプト） | 責務 | 引数 |
| --- | --- | --- |
| `calendar_section.tscn`（`CalendarSection`） | 段 1 つ。見出し（「ログインボーナス」/「VIP ボーナス　VIP n」）と、行ごとの `HBoxContainer`（1 行 4 マス。最終日のマスは残りの幅を使う）にマスを並べる。行数はマスターの周期の日数（`cycle_days`）から決まる | `CalendarStageView`、マスの絵のサイズ（通常 80・VIP 72） |
| `calendar_cell.tscn`（`CalendarCell`） | マス 1 つ。「N 日目」・`ItemIcon`・数量・「＋n」・「今日」の印・縁取り・スタンプ（`TextureRect`）。状態は `apply_state(state, play)` で切り替える（`play = false` が最終状態へ飛ぶ入口。6 節。引数は常にこの 2 つに統一） | `CalendarCellView` |
| `reward_row.tscn`（`RewardRow`） | 「今日配られた報酬」の 1 行: `ItemIcon`（56）＋「名前 x数量」（名前の規則は今の `build_text` のまま） | `LoginBonusDisplay` |
| `stamp_player.gd`（`StampPlayer`、RefCounted） | スタンプのアニメーションの再生・即時完了。`Tween` はホストの Node から作る（6 節） | セル、開始の遅れ |
| `item_icon.tscn`（`ItemIcon`、`core/presentation/item_icon/`） | アイコンの共通部品（5 節）。ログインボーナス・ホームで共用 | `type`・`id`・`mst_item_type`・サイズ |

1 マスのノード数は、ルート 1＋「N 日目」ラベル・アイコン・数量ラベル・「＋n」ラベル・「今日」印・スタンプで 6〜7。14 マスで約 100 ノード（非機能「マスごとに数個」の範囲）。

### 1-3. 各状態の表示

**段（通常・VIP それぞれ）の状態**は、サーバーの 2 つの真偽（`is_granted_today`・`is_granted_now`）と最後に配った日数 `last_day` だけから決める。クライアントはゲーム内日付も `login_bonus_list` の空・非空も使わない（C8・T3）。

| 段の状態 | 条件（サーバーの値だけ） | マスの出し方 |
| --- | --- | --- |
| 今日の段 | `is_granted_today` が真、かつ `1 ≤ last_day ≤ cycle_days` | `last_day` のマスが**今日**、それ以前が**受け取り済み**、それより後が**未来** |
| 今日の段でない | `is_granted_today` が偽（T2） | **全マスを同じ見た目**（強調なし・スタンプなし・未来の暗さも付けない）。段は隠さない |
| 日数が範囲外 | `is_granted_today` が真でも `last_day` が `cycle_days` の範囲外（マスターで周期を縮めた直後。体験 9） | 「今日の段でない」と同じ（強調なし） |
| 段が無い | 応答の項目が null・欠落・型違い（T4・D3・D4） | その段を出さない |

**マス（1 日分）の状態**（`CalendarCellView.state`）:

| 状態 | 絵 | 数量・N 日目 | 縁取り・印 | スタンプ |
| --- | --- | --- | --- | --- |
| `TODAY`（今日。受け取り前のアニメーション直前を含む） | 通常の明るさ | 表示 | 色付きの太い縁取り＋「今日」の印。**アニメーションを再生しない再表示では最初から押印済み**（C7・C10） | `play_stamp` が偽なら押印済み、真ならアニメーション（6 節） |
| `RECEIVED`（今日より前） | 少し暗く（明るさ 0.8。C5） | 表示 | なし | 押印済み（アニメーションなし） |
| `FUTURE`（未来） | 彩度 0.5・明るさ 0.7（C6。目安） | 表示 | なし。鍵・ロックは付けない | なし |
| `NEUTRAL`（今日の段でない段・範囲外） | 通常 | 表示 | なし | なし |

- 「今日」の脈動（C4）は、**アニメーションを再生するマスの、スタンプが押される前**だけに限り、周期 1.2 秒・拡大 1.04 倍まで。押印後・再表示では止める（60fps の軽量化の第 1 段。7 節）。点滅はしない
- **VIP の段**: 通常と同じ部品。見出しは「VIP ボーナス　VIP n」（n はサーバーが返す対象レベル。受取済みの `vip_level` ではない。Q6・C8b）。マスの絵は 72
- **1 日に複数の報酬**: マスターの報酬行を **`sort_desc` の降順**（大きい値が先。同値は `content_type`・`content_mst_id` の昇順。12 節 Q-12）に並べた先頭の絵に「＋n」（n = 件数 − 1。Q14）。クライアントはこの並びをマスターの列から作り、それ以外の並べ替えはしない（D2）
- **報酬の種別**（要件「報酬の種別ごとの表示」の表のとおり。絵の決め方は 5 節）: `unit`・`equipment`・`stamina`・`paid_diamond`・**未知の `content_type`** は `unknown` の絵＋数量で出す。**`item` と `wallet` はどちらも `mst_item` を `content_mst_id` で引く**（`wallet` は `mst_item.is_wallet = true` のアイテム。`gold` などへの読み替えを固定で書かない）。**例外・空表示にしない**。マスターに報酬行が 1 件も無い日（`day = 0` のカムバック行は周期の日に含めない）は、`unknown` の絵のみ・数量なしで出す
- **再表示の旨**（`NoticeLabel`）: **いずれかの段が今日の段で、どの段も `is_granted_now` が偽**のときだけ「本日のログインボーナスは受け取り済みです」をカレンダーの上に出す（T3・C10・H3・U-3 の既定案）。どの段も今日の段でない日には出さない。`FROM_HOME` の通常（確認のみ）は常にこの条件になる
- **「今日配られた報酬」の行**（C9）: `FROM_LOGIN` で `login_bonus_list` が非空のときだけ、その全行を（VIP・カムバックを含み、**受け取った順のまま**。D-4）。`FROM_HOME` では出さない。再受け取りの応答を受けたら、その報酬（VIP の段の今日の日の報酬）を行に足す（3-2）
- **受け取りボタン**（H4）: `ReceiveOffer.visible`（VIP の段の `can_re_receive` が真）のときだけ。押せない状態の印（灰色のボタンなど）は出さない。ラベルは「受け取る」（固定文字）
- **カレンダーを出さず今の文字の画面に落とす場合**: ① 両方の段が無い（T4・体験 7。VIP も通常も無い）② 旧サーバー（新キー無し。D4）③ いずれかの段の周期の日数（`cycle_days`）が 8 を超える、または 1 未満（C1。**画面全体**を文字にする。段ごとには落とさない）④ **出せる段が 1 つも無い**（進捗のある段のマスターの ID を、再取得しても全て引けない古いマスター。2-4）。**片方の段だけ引けるときは、引けない段だけ出さず、引けた段だけ表示する**（人の回答 U-11。VIP を引けなければ受け取りボタンも出さない。③ の周期の範囲外とは別の規則）。文字の画面は今の `build_text` をそのまま使う（`login_bonus_list` が空なら「受け取り済み」の文）。②③ のときもカムバックの行は「今日配られた報酬」として文字に出る
- **「N 日目」「今日」「ログインボーナス」「VIP ボーナス」「＋n」「受け取る」の文字**: クライアントの固定文字（言語は `ja` 固定。overview 7 節 h）。名前はマスに出さない（C3）

### 1-4. レイアウトと安全領域

- パネル幅 800（今と同じ）。4 列: 1 マスの幅 = (800 − 左右の内側余白 2×24 − 列の間 3×12) ÷ 4 ≒ 179。通常 80・VIP 72 の絵が収まる。最終日のマスは行の残りの幅（`size_flags_stretch_ratio` = 空き列数＋1）。`cycle_days` が 4 の倍数なら伸ばさない
- **縦の高さの見積り**（1920 基準。S5 で最大構成の写真で実測し、この表を直す）: 絵のサイズは次の項の確定値（通常 80・VIP 72・報酬の行 56）。内容の合計は、タイトル 72・再表示の旨 48・通常の段（見出し 40＋2 行×約 174）388・VIP の段（見出し 40＋2 行×約 150）340・受け取りボタン 112・今日配られた報酬（見出し 40＋最大 5 行×64）360・タップの案内 64・各部の間隔 8×16＝128 ＝ **約 1512**（絵を要件の目安 96/72 のままにすると 72＋48＋420＋340＋112＋440＋64＋128 ＝ 1624）。**ホームの既定の余白 `BASE_MARGIN_VERTICAL = 96`（上下で 192）は安全領域を含まない**（`home_presenter.gd` は安全領域の値を足している）。iPhone X の安全領域は上 44pt・下 34pt で、ビューポート単位（1080 単位 ÷ 375pt ≒ 2.88 倍/pt）では上 約 127・下 約 98（計 約 225。実機の値は `get_display_safe_area` で S5 に確かめる）。**余白 96 のままだと使える高さは 1920 − 192 − 225 ＝ 約 1503 で、1512 は収まらない**。この画面の基本の余白を**上下 48**（ホームの 96 でなく）にすると使える高さは 1920 − 96 − 225 ＝ **約 1599 で、1512 が収まる（余裕 約 87）**。つまり「**余白 48＋縮め方①②**」で収まる（どちらか片方では収まらない）。星の行（72）は外す。デスクトップ・シミュレーターは安全領域 0 でもっと余る
- **縮め方（余白 48 と①② は最初から適用済み。③ だけ実測で足りないときに足す）**: ① 「今日配られた報酬」の行の絵を要件の目安 72 → 56（1 行 −16、5 行で −80）② 通常のマスの絵を要件の目安 96 → 80（1 行 −16、2 行で −32）。**絵のサイズの確定値は通常 80・VIP 72・報酬の行 56**（要件の目安から縮めた旨はここだけに書く。他の箇所は確定値だけ） ③ 行が 6 件を超えるときだけ、報酬の行の領域を `ScrollContainer`（最大高さ固定）にする（Q2 の扱い）。①②③ はどれも要件の決定の範囲内
- **安全領域**: ログインボーナス画面も `SafeAreaMargins` を使う（モバイルのみ。デスクトップは 0）。使うために `SafeAreaMargins` を `contexts/player/presentation/home/` から **`core/presentation/safe_area_margins.gd`** へ移す（純粋関数でホームにしか依存しない。`HomePresenter` と `tests/unit/` の参照を直す。他コンテキストの presentation が `core/presentation` を使うのは規約の範囲）。基本の余白は `Margin` に足す（ホームと同じ方式）

### 1-5. FROM_HOME の読み込み・失敗の表示

（`FROM_LOGIN` も、マスターを引けないときだけ同じ「読み込み中…」を挟む。2-4）

1. 画面を開いた直後（`_ready`）は、`StatusLabel` に「読み込み中…」を出し、カレンダー・ボタン・行は隠す（背景動画とタイトルとタップの案内は出す）
2. 成功 → `StatusLabel` を隠して 1-3 の表示（アニメーションなし）
3. 失敗 → `ErrorView.show_error(StatusLabel, RetryButton, error)`（既存の共通部品）。再試行は同じ取得をやり直す。**失敗していてもタップでホームへ戻れる**（`TapCatcher` は常に有効）。`SESSION_EXPIRED` は agreement と同じく、メッセージを見せてタイトルへ戻す
4. 読み込み中・失敗中にホームへ戻っても、応答が来たときに画面（解放済み）を触らない（`_is_leaving` と `is_inside_tree()` を応答後に確認する）

## 2. スクリプトの分担と層

コンテキストは `login`（サーバーの `Domain/LoginBonus` と対応させる案は 12 節 Q-2。既定は**既存の `login` に置く**）。player と core・master_data への変更は最小。

### 2-1. 追加・変更するファイル

**`contexts/login/`**

| 層 | ファイル | 種別 | 責務 |
| --- | --- | --- | --- |
| domain/entities | `login_bonus_calendar.gd`（`LoginBonusCalendar`） | 追加 | 段 1 つの**進捗**（応答の値だけ）: `mst_id`（応答では `mst_login_bonus_id` / `mst_vip_login_bonus_id`）・`last_day`（応答の `last_received_day`。null は 0）・`is_granted_today`・`is_granted_now`・`can_re_receive`・`vip_level`（VIP のみ。無ければ 0）。**日ごとの報酬・周期の日数は応答に無く、マスターから引く**（`LoginBonusStageMaster`。下）。**クライアントの名前は短く保ち、応答の名前との対応は 4 節の表の 1 か所だけ**（変換は `data/api` に閉じる）。判定は足さない。受け取り後の更新用に `duplicate_as_re_received()`（`is_granted_now = true`・`can_re_receive = false` の複製を返すだけ）を持つ |
| domain/entities | `login_bonus_stage_master.gd`（`LoginBonusStageMaster`）・`login_bonus_calendar_day.gd` | 追加 | マスターから作る段の定義: `cycle_days`・`days: Array[LoginBonusCalendarDay]`。`LoginBonusCalendarDay` は `day: int`・`rewards: Array[LoginBonus]`（`login_bonus_list` の要素と同じ型を使い回す。`type` = `content_type`・`id` = `content_mst_id`・`amount` = **`content_quantity` × `amount`**（サーバーと同じ式。`amount` は通常の行では配布回数、VIP の行では報酬の倍率。要件 B 節）・`metadata` = `content_option` の JSON ＋通常の行の `is_paid` が真なら `is_paid: true`。`unique_id` は空）。報酬行は `sort_desc` 降順 |
| domain/entities | `login_bonus_calendars.gd` | 追加 | 通常・VIP の 2 段の**進捗**の束（`normal`・`vip`。null 可）。`has_any()` |
| domain/entities | `login_bonus_screen.gd` ほか表示用の値（`CalendarStageView`・`CalendarCellView`・`ReceiveOffer`） | 追加 | presenter が描くだけの値の束（1-3 の状態・`play_stamp`・絵の引数）。文字列は持たない |
| domain/entities | `login_bonus_display.gd` | 変更 | `item_type: String`（引けた `mst_item.type`。引けなければ空）を足す（アイコンのフォールバック ② に使う） |
| domain/entities | `login_data_result.gd` | 変更 | `login_bonus_calendars: LoginBonusCalendars` を末尾に足す（既定は空の束。既存の呼び出しを壊さない） |
| domain/repositories | `login_bonus_repository.gd` | 変更 | `replace_calendars(c)` / `calendars()` を足す（メモリの保持。`clear()` は両方を空にする）。**実装** `local_login_bonus_repository.gd` も同様 |
| domain/repositories | `login_bonus_calendar_repository.gd`（`LoginBonusCalendarRepository`） | 追加 | 契約（命名は既存の `login_repository` / `login_api_repository` の対に倣い、契約は `<名前>_repository`、実装は `<名前>_api_repository`。`remote` は master_data だけの呼び名で login には持ち込まない）（テストで偽物に差し替える）: `fetch_calendars()`・`receive_vip(mst_vip_login_bonus_id, idempotency_key)` |
| domain/use_cases | `fetch_login_bonus_calendars_use_case.gd` | 追加 | `FROM_HOME` の取得。`POST /login_bonus/list`（**冪等キーを付けない**。3-4）。成功したらメモリの保持を置き換え、結果（`FetchLoginBonusCalendarsResult`）を返す。失敗は `Result.failure` 相当 |
| domain/use_cases | `receive_vip_login_bonus_use_case.gd` ＋ `receive_vip_login_bonus_result.gd` | 追加 | 再受け取り。`POST /login_bonus/receive`。成功なら player の公開 UseCase で所持数を反映（3-3）→ メモリの VIP の段を応答の `vip_login_bonus_calendar` で置き換える（サーバーの値を正とする。`duplicate_as_re_received()` は応答の段が読めないときの代替）→ 受け取った報酬は応答の `login_bonus_list` を結果に載せる |
| domain/use_cases | `prepare_login_bonus_master_use_case.gd` | 追加 | **非同期**。メモリの進捗の段の ID をマスターで引き（`LoginBonusStageMasterReader`＝`master_data` の 2 つの Repository の窓口）、引けない段があれば `CheckMasterDataUseCase.handle()` を **1 回だけ**実行してから引き直す。結果は「段のマスターの束」か「引けない」（2-4） |
| domain/use_cases | `get_login_bonus_screen_use_case.gd` | 追加 | 同期。メモリの進捗・段のマスターの束・`login_bonus_list` から `LoginBonusScreen` を作る（1-3 の規則。名前・`mst_item.type` の引きは既存 `GetLoginBonusDisplaysUseCase` を使う）。`FROM_LOGIN` / `FROM_HOME` の違いは引数 `include_login_bonus_list` と `play_stamp_allowed` で受ける。第 4 引数 `play_stamp_normal`（既定 真）は、再受け取りの成功後に画面を作り直すとき、login で再生済みの通常の段をもう一度鳴らさないために偽にする（T5: 再受け取りで真なのは VIP の段だけ） |
| domain/use_cases | `get_login_bonus_displays_use_case.gd` | 変更 | `item_type` を載せる。`unit`・`equipment`・`stamina` 以外の行で `mst_item` を引く（`item_type` のため。`item_name` は今のまま `item` の行だけ） |
| domain/use_cases | `login_use_case.gd` | 変更 | 成功時に `login_bonus_calendars` もメモリへ置く（`replace_calendars`）。再受け取りの応答は login ではないので扱わない |
| data/api | `login_bonus_calendar_response.gd` | 追加 | **段 1 つ**の辞書（進捗だけ）→ `LoginBonusCalendar`（login 応答と list 応答で共用。4 節） |
| data/api | `login_bonus_calendars_response.gd` | 追加 | list 応答（通常・VIP の 2 キー）→ `LoginBonusCalendars` |
| data/api | `receive_vip_login_bonus_response.gd` | 追加 | 再受け取りの応答（`trx_vip_login_bonus`・`login_bonus_list`・`vip_login_bonus_calendar`・`updated_resources`）の取り出し |
| data/api | `login_response.gd` | 変更 | 新しい 2 キーを `LoginBonusCalendarResponse` で読み、`to_domain()` に載せる。既存の項目・`login_bonus_list` は変えない |
| data/repositories | `login_bonus_calendar_api_repository.gd` | 追加 | 契約の実装。`ApiClient.request("POST", "/login_bonus/list", {})`（冪等キーなし）と `"POST", "/login_bonus/receive", {mst_vip_login_bonus_id}`（冪等キーつき）。`ApiResult` を `AppError` に直して返す |
| presentation | `login_bonus/login_bonus_presenter.gd`・`login_bonus.tscn` | 変更 | 入口の分岐・描画・受け取りボタン・タップ。業務の判断はしない（UseCase の結果を描く） |
| presentation | `login_bonus/login_bonus_from_home.tscn` | 追加 | 継承シーン（`entry = FROM_HOME`） |
| presentation | `login_bonus/calendar_section.{tscn,gd}`・`calendar_cell.{tscn,gd}`・`reward_row.{tscn,gd}`・`stamp_player.gd`・`calendar_text.gd` | 追加 | 1-2 の表。`calendar_text.gd` は「N 日目」「＋n」などの文字を作る静的関数（`NumberText` を使う） |

**`contexts/player/`**（所持数の反映。他コンテキストは公開 UseCase だけ使う）

| 層 | ファイル | 種別 | 責務 |
| --- | --- | --- | --- |
| domain/use_cases | `apply_updated_resources_use_case.gd` | 追加 | `updated_resources` の 4 種（`trx_item_list`・`trx_wallet_list`・`trx_diamond`・`trx_stamina_list`）を PlayerRepository の現在値へ取り込む（3-3）。失敗しない（メモリのみ）。`ApplyLoginDataUseCase` と同じ形（`Result` を返す） |
| presentation | `home/home_presenter.gd`・`home.tscn` | 変更 | 「ログインボーナス」ボタン（`NavRow`）の接続（`setup` にルーターを足す）。値の横の `ItemIcon` 3 つ（5-5）。ラベルのパスが変わる（3 つの値ラベルが `ValueRow` の子になる） |
| presentation | `home/safe_area_margins.gd` | 移動 | `core/presentation/safe_area_margins.gd` へ（1-4） |

**`core/`**

| 層 | ファイル | 種別 | 責務 |
| --- | --- | --- | --- |
| domain | `item_icon_resolver.gd`（`ItemIconResolver`） | 追加 | 純粋関数。`type`・`id`・`mst_item_type`・「その絵が存在するか」の述語（Callable）から、絵のキー（`items/<id>`・`fallback/category_<type>`・`fallback/unknown`）を返す（5-2） |
| presentation | `item_icon/item_icon.{tscn,gd}`（`ItemIcon`） | 追加 | `TextureRect`。`setup(type, id, mst_item_type, size)` で絵を出す。読み込みは `ItemIconTable` から（動的な `load` をしない） |
| presentation | `item_icon/item_icon_table.gd`（`ItemIconTable`） | 追加（**生成物**） | キー → `preload` した `Texture2D` の定数表と `has_key`・`texture_of`。生成スクリプトが作る（5-3） |
| presentation | `number_text.gd`（`NumberText`） | 追加 | 桁区切り（`HomeText.format_number` と同じ規則）。`HomeText` を寄せる整理は任意（S5 で小さく） |
| presentation | `safe_area_margins.gd` | 移動 | 上のとおり |

**`app/`**: `app_context.gd` に UseCase の取得メソッド（`prepare_login_bonus_master_use_case()`・`fetch_login_bonus_calendars_use_case()`・`receive_vip_login_bonus_use_case()`・`get_login_bonus_screen_use_case()`・`apply_updated_resources_use_case()`）と、`LoginBonusCalendarApiRepository` の組み立てを足す。`scene_router.gd` に `LOGIN_BONUS_FROM_HOME_SCENE`・`goto_login_bonus_from_home()` を足す。**EventBus への影響なし**（`session_expired` の購読は既存の `_login_bonus_repository.clear()` が新しい保持も空にする）。

**`master_data/`**（ログボのマスターを引く。既存の `MstItemRepository`／`LocalMstItemRepository` の作りに倣う）

| 層 | ファイル | 種別 | 責務 |
| --- | --- | --- | --- |
| domain/entities | `mst_login_bonus.gd`（`MstLoginBonus`）・`mst_login_bonus_content.gd`（`MstLoginBonusContent`）・`mst_vip_login_bonus.gd`・`mst_vip_login_bonus_content.gd` | 追加 | 本体 1 行・報酬 1 行。**通常の報酬行**: `mst_login_bonus_id`・`day`・`content_type`・`content_mst_id`・`content_option`（JSON）・`content_quantity`・`amount`（配布回数）・`is_paid`・`sort_desc`（主キーは複合で `id` 無し）。**VIP の報酬行**: `id`（連番）・`mst_vip_login_bonus_id`・`day`・`content_type`・`content_mst_id`・`content_option`・`content_quantity`・`amount`（倍率）・`sort_desc`（`deploy_key`・`is_paid` は無い）。**VIP の本体にも `deploy_key` は無い**。判断は持たない |
| domain/repositories | `mst_login_bonus_repository.gd`・`mst_vip_login_bonus_repository.gd`（契約） | 追加 | `get_by_id(id)`（本体＋報酬行を `day`・`sort_desc` 降順で返す。引けない・テーブルが無い・DB が開けないときは null。例外にしない） |
| data/repositories | `local_mst_login_bonus_repository.gd`・`local_mst_vip_login_bonus_repository.gd` | 追加 | `MasterDatabase` の失敗を区別して読む（2-4 の「失敗の区別」）。本体と報酬行は**テーブルごとに別の SQLite ファイル**で、1 つの SQL で JOIN できないので、**本体を引く → 報酬行を別に引く**の 2 回に分ける（`mst_item` と `mst_item__l10n` のように同じファイルの親子ではない）。**列は `SELECT` に明示する。VIP の 2 テーブルでは `deploy_key` を読まない**（`LocalMstItemRepository` の `COLUMNS` の並びを流用すると `no such column` になる）。SQL（報酬行）: 通常 `ORDER BY day, sort_desc DESC, content_type, content_mst_id`、VIP `ORDER BY day, sort_desc DESC, id ASC`。キャッシュは持たない |
| data/local | `master_database.gd` | 変更 | `try_select_rows(table, sql, bindings)` を足す: テーブルの DB が開けていない・クエリが失敗（古い配信ファイルの列なしなど）なら `ok = false`、成功なら `ok = true` と行（0 件も成功）。**既存の `select_rows` は変えない**（失敗を空配列にする今の契約に他が依存する） |
| domain/entities | `mst_item.gd`・`local_mst_item_repository.gd` | 変更 | `is_wallet: bool` を足す。`COLUMNS` を列挙しているので、**列が無い版のマスターで全件が引けなくなる**のを避けるため `SELECT *` にして `is_wallet` の列があるときだけ読む（無ければ偽。12 節 Q-11） |

`REQUIRED_TABLES` は変えない（ログボのテーブルは必須にしない。`mst_item` と同じ。無ければ「引けない」の扱い。2-4）。

**`debug/`・`tools/`・`assets/`**: 5・11 節。

### 2-2. 層の確認（依存チェックに通ること）

- presenter（presentation）は UseCase と `core/presentation` の部品（`ItemIcon`・`ErrorView`・`SafeAreaMargins`・`NumberText`）だけを使う。data（`*_response.gd`・Repository 実装）は参照しない（P1）。ホームは `login` の UseCase を使わない（遷移だけ）
- `login` → `player` は `ApplyUpdatedResourcesUseCase`（公開 UseCase）だけ（X1・P2）。`login` → `master_data` は `domain` の Repository の契約・`CheckMasterDataUseCase`・エンティティだけ（`data` は参照しない。architecture.md）
- `core/domain/item_icon_resolver.gd` は `Node`/`Texture2D` に依存しない（D2）。`core/presentation/item_icon/item_icon_table.gd` がアセットを `preload` する（C1: core は contexts・master_data を参照しない。引けた `mst_item.type` は呼び出し側が渡す）
- `debug/` の確認用画面は本番コードから参照されない（T1）。製品の複製から除外される

### 2-4. マスターが古くて ID を引けないとき（人の決定の宿題。既定案）

- 通常は起きない（タイトルから入るときにマスターのダウンロードが走る。`master_data_loaded`）。起きるのは、サーバーがマスターを更新した直後（応答の段の ID が新しい）・ダウンロードが失敗していた・同梱 DB しか無いときなど
- **失敗の区別（古い配信ファイルの合図）**: 古い配信ファイルに `sort_desc` の列が無いと、並べ替えの SQL が「列なし」のエラーになる。`select_rows` は失敗を空配列にするので、**`try_select_rows` の `ok = false`（クエリ失敗・テーブルが開けない）を「古いマスター」の合図として扱い、再取得の対象に含める**。`ok = true` で本体が 0 件（その ID の行が無い）も同じく再取得の対象。Repository は結果の種別（見つかった／行が無い／読めない）を返し、UseCase は後 2 つを同じ再取得にする（種別はログ・テストで区別する）
- **既定案**: 画面を出す前（`FROM_LOGIN` は `_ready`、`FROM_HOME` は list の応答の後）に `PrepareLoginBonusMasterUseCase` が、引けない段があれば **`CheckMasterDataUseCase.handle()` を 1 回**呼んで引き直す（同じ「読み込み中…」を出す。再取得は version の確認＋差分テーブルのダウンロード）。**IN_PROGRESS（ほかで同期中）・FAILED・再取得後も引けないときは、引けない段だけ出さず、両方の段が出せないときだけ今の文字の画面にフォールバックする**（1-3 の④。人の回答 U-11。通常だけ引ければ通常だけ、VIP だけ引ければ VIP だけ表示）。ループはしない（1 回だけ）。`FROM_LOGIN` は通常通信しないが、このときだけ通信が入る（失敗してもタップでホームへ進める）
- `X-Master-Update-Required` の裏の同期とは独立（同時実行は `CheckMasterDataUseCase` が防ぐ。IN_PROGRESS はフォールバック）

### 2-3. オートロードへの影響

追加なし。`AppContext`（取得メソッド・組み立て）と `SceneRouter`（遷移 2 つ）の追記だけ。`_ready` で他のオートロードを呼ばない規則は守る。

## 3. API 呼び出し

項目名はサーバーの api.md（2・7・8 節）の確定名。パスはどちらも POST。

### 3-1. 一覧

| API | 呼ぶタイミング・呼び元 | 送る値 | 冪等キー | 応答の使い方 |
| --- | --- | --- | --- | --- |
| POST `/auth/login`（既存） | タイトルの LOGIN 段階（変更なし） | なし | 付ける（既存） | 末尾に追加された 2 キー `login_bonus_calendar`・`vip_login_bonus_calendar`（常にキーはあり、マスターが無いと `null`）を読む（4 節）。`login_bonus_list` は今のまま |
| POST `/login_bonus/list`（新） | `FROM_HOME` で画面を開いた直後に 1 回（`FetchLoginBonusCalendarsUseCase`）。再受け取りのエラーの後の取り直しにも使う | `{}` | **付けない**（サーバーは任意。同じキーは 24 時間 2xx を再生して古い状態が返るため、使い回さない。毎回新規にする案は採らず、キー自体を持たない。サーバー api.md 7.1。エラーも 299 で保存される） | `login_bonus_calendar`・`vip_login_bonus_calendar`（login の新キーと同じ形。`is_granted_now` は常に偽。`updated_resources`・`login_bonus_list` は無い）を `LoginBonusCalendars` に |
| POST `/login_bonus/receive`（新） | 受け取りボタンのタップ（`ReceiveVipLoginBonusUseCase`） | `mst_vip_login_bonus_id`（`vip_login_bonus_calendar.mst_vip_login_bonus_id` をそのまま送る） | **付ける**（presenter が `_receive_key` に保持。3-4） | `updated_resources` を所持数へ（3-3）、`vip_login_bonus_calendar`（`is_granted_now` 真・`can_re_receive` 偽）で VIP の段を置き換え、`login_bonus_list` を「今日配られた報酬」の行へ、`trx_vip_login_bonus` は照合用（4 節） |

### 3-2. タイミングと失敗時

**FROM_LOGIN**: 通常は通信しない。`_ready` で `PrepareLoginBonusMasterUseCase`（マスターで段の ID を引く。引けなければ 2-4 の再取得）→ `GetLoginBonusScreenUseCase.handle()`（メモリ・SQLite）→ 描画 → アニメーション開始（6 節）。

**FROM_HOME**: `_ready` で取得（1-5 の読み込み中表示）→ マスターを引く（2-4）→ 描画（アニメーションなし）。

**受け取りボタン**（`FROM_LOGIN`・`FROM_HOME` 共通）:

1. タップ → ボタンを無効化して「受け取り中…」にする（**二重タップの防止**。応答が戻るまで再度押せない）。`_receive_key` が空なら作る
2. `await receive_vip_login_bonus.handle(mst_id, _receive_key)`
3. **成功**: メモリが更新済み。`GetLoginBonusScreenUseCase` で画面の値を作り直して描画し、VIP の今日のマスに**スタンプのアニメーション**（T5・K1。6 節）。ボタンは消す。「今日配られた報酬」の行には、応答の `login_bonus_list` の報酬を足す（`FROM_LOGIN` は既存の行の後ろ、`FROM_HOME` は行が無いので新しく出す。12 節 Q-3）。再受け取りの旨の `NoticeLabel` は、VIP の段が `is_granted_now` なので出ない。`_receive_key` を空に戻す
4. **失敗**: `AppError.kind` で分ける。
   - `BUSINESS`（HTTP 299 の `error_code` 26001〜26003。26001 = 今日の段でない・既に受け取り済み、26002 = 今のレベルのボーナスが無い・ID 不一致、26003 = マスターに報酬行が無い。**クライアントはコードで分岐しない**。サーバー api.md 6 節）: **状態を取り直す**（`FetchLoginBonusCalendarsUseCase`）→ 画面を更新（アニメーションなし。ボタンは取得結果で出し直し）→ 短いメッセージ（Toast「状態を更新しました」）。`_receive_key` は**新しく作り直す**（業務エラー 299 も 24 時間保存され、同じキーで再送すると状態が変わっても古いエラーが返り続ける。3-4）。再取得の結果でボタンが出たときだけ、新しいキーで送れる。26003 はマスターの設定ミスで、再取得すると `can_re_receive` が偽になりボタンが消える
   - `NETWORK`・`SERVER_BUSY`・`CONFLICT`・`SERVER_ERROR` など再試行できるもの: ボタンの下に `ErrorMessages.text(error)` を出し、ボタンを有効に戻す。再タップは**同じ `_receive_key`** で送る（`IdempotencyKey.can_reuse`。サーバーが先に処理していても同じ応答が返る）
   - `RATE_LIMITED`: `ErrorView` の待ち（`retry_after` の間ボタンを無効）
   - `SESSION_EXPIRED`: メッセージを見せてタイトルへ（agreement と同じ）
   - `MAINTENANCE`: メンテナンスの文言（`ErrorMessages`）
5. 受け取り中に画面を離れた（ホームへ戻った）場合も、応答後に画面を触らない（1-5 の 4）。**受け取り中は、タップで閉じない**（`_is_receiving` の間は `TapCatcher` の閉じる処理を無効にする。ボタンの二重タップが画面を閉じて所持数の反映前にホームへ戻るのを防ぐ）。通信は `ApiClient` のタイムアウトで終わり、失敗の表示のあとは閉じられる

**取り直しに失敗**したとき（BUSINESS の後の list も失敗）: 今の画面の表示は維持し、ボタンを消してエラー文を出す（古い状態でボタンを押させない）。

### 3-3. `updated_resources` をホームの所持数へ反映する（Q31）

- **現状**: 取り込む UseCase が無い（0 節 g）。**`ApplyUpdatedResourcesUseCase`（player の公開 UseCase）を足す**。`ReceiveVipLoginBonusUseCase` が呼ぶ
- **取り込む範囲**: ホームが読む **4 種**（`trx_item_list`・`trx_wallet_list`・`trx_diamond`・`trx_stamina_list`）だけ。**他のキーは無視する**（読む画面が無い。足すときは各機能が拡張）
  - `trx_item_list`: 行の `mst_item_id` を主キーに**差し替え**（無ければ追加）。変更のあった行だけが載りうるので全置き換えにしない（`.claude/api.md` の前提）。コイン・無償ダイヤ・経験値アイテムなどが入る
  - `trx_diamond`: 単数のオブジェクト。キーがあれば置き換える（再受け取りの報酬には有償ダイヤは無いはずだが、来たら取り込む）
  - `trx_stamina_list`: キーがあれば、行の `type`（`trx_stamina` の主キーは `(sys_player_id, type)`。ホームの `PlayerResourceIds` も `type` で読む）を主キーに差し替える
  - `trx_wallet_list`: 行の `mst_item_id`（`CoinAmount` が読む実キー。値は `free_amount`・`paid_amount`）を主キーに**差し替え**（無ければ追加）。`content_type = wallet` の報酬（`gold` などの `type`。サーバー api.md 2.3・8 節の例）が入る。**コインはここから読むので必須**
  - `trx_unit_list`・`trx_equipment_list`: 今のホームが読まないので取り込まない
- **削除行**: `is_delete` は `PlayerState.is_row_deleted()` で読む（既存の規則）。差し替えの行をそのまま入れ、表示側（`CoinAmount` など）の既存の除外に任せる
- **サーバーの時刻差**: 再受け取りの応答の `Date` でオフセットは更新しない（login のときだけ）
- **PlayerRepository**: `current()` が返す `PlayerState` の `trx_lists` を直接書き換えず、新しい `PlayerState` を作って `replace()`（全量の置き換えの契約を保つ）
- 反映のタイミングは UseCase 内（応答の直後）。ホームは戻ったときの `_ready` で読む。ホームが開いたままのときは無い（ログインボーナス画面はシーンの切り替えで開くので、ホームは常に作り直される）
- `.claude/api.md` の末節（「今は読まない」）をこの機能の実装に合わせて書き換える（10 節）

### 3-4. 冪等キー

- receive だけ付ける。**キーの寿命は「ひとつの操作」**（title-to-home 3-4 と同じ）。presenter が `_receive_key` に持ち、`IdempotencyKey.generate()` で作る
- **同じキーで再送してよいのは、応答が届かなかったとき（通信断・409・503）だけ**（成功済みなら保存済みの同じ応答が返り、配らない）。**業務エラー（299。26001〜26003）の後・成功の後・list で取り直した後の送信は、必ず新しいキー**（`IdempotencyKey.can_reuse(error.kind)` が偽）。サーバー api.md 6.1 の約束
- 状態の取得（list）には**付けない**（上の表。サーバー api.md 7.1）。list を再試行するときも付けない
- テストで固定する: BUSINESS の後の `_receive_key` が変わる・list のリクエストに `X-Unique-Request-Identifier` が無い（9 節）
- ヘッダーの `X-Master-Hash`・`X-Platform`・`Accept-Language` は `ApiClient` が付ける（変更なし）

## 4. Response からモデルへの対応と null の扱い

項目名はサーバー api.md の確定名（2・8 節）。クライアントのモデル名との対応は次の表が唯一の場所。`unique_id` は報酬に入れない（サーバーが載せない。api.md 2.3）。形:

```
<段> = { mst_login_bonus_id | mst_vip_login_bonus_id, last_received_day|null,
         is_granted_today, is_granted_now, [VIP のみ: vip_level, can_re_receive] }
         （全日の報酬・周期の日数は応答に無い。段の ID でマスターを引く）
login 応答:   末尾に login_bonus_calendar（通常）・vip_login_bonus_calendar（VIP）。各 <段> か null。キーは常にある
list 応答:    同じ 2 キーだけ（updated_resources・login_bonus_list は無い）
receive 応答: { trx_vip_login_bonus: { mst_vip_login_bonus_id, day, vip_level, received_at },
               login_bonus_list: [...今回配った報酬。login と同形],
               vip_login_bonus_calendar: <段>（is_granted_now 真・can_re_receive 偽）,
               updated_resources: {...} }
```

| 応答の名前 | クライアントのモデルの名前 |
| --- | --- |
| `mst_login_bonus_id` / `mst_vip_login_bonus_id` | `LoginBonusCalendar.mst_id` |
| `last_received_day` | `.last_day` |
| （応答に無い。`LoginBonusStageMaster` がマスターから作る） | `cycle_days`・`days`・`LoginBonusCalendarDay.rewards` |

| 応答の項目 | モデル（domain） | null・欠落・型違いの扱い（D3 の規則を `data/api` に閉じ込める） |
| --- | --- | --- |
| 段のキー（通常用・VIP 用） | `LoginBonusCalendars.normal` / `.vip` | キーが無い・null・Dictionary でない → **null**（その段を出さない。旧応答でもここに落ちる）。両方 null かつ `login_bonus_list` が空 → 今の「受け取り済み」の文字画面 |
| `mst_login_bonus_id` / `mst_vip_login_bonus_id` | `LoginBonusCalendar.mst_id` | 文字列。無い・null → 空文字（サーバーは不可としている）。VIP で空のときは `can_re_receive` を偽に落とす（ボタンを出さない。送る ID が無いため） |
| （マスターの周期の列） | `LoginBonusStageMaster.cycle_days` | `int()`。無い・NULL・数値でない → 0。**0 以下・8 超は 1-3 のとおり文字の画面へ落とす条件** |
| `last_received_day` | `.last_day` | null（まだ配っていない）・無い → 0。`int()`。`is_granted_today` が真のときだけ今日の日数として使う（T2。サーバー api.md 2.1）。周期の日数を超える値もそのまま返るのでクライアントが範囲外を扱う（1-3） |
| `is_granted_today` / `is_granted_now` / `can_re_receive` | 同名 | **真偽値型のときだけその値。それ以外（null・無い・0/1・文字列）は偽**（安全側。ボタンもアニメーションも出さない）。`can_re_receive` は VIP のみ。通常に付いていても無視 |
| `vip_level` | `.vip_level` | `int()`。無い・null → 0（見出しは「VIP ボーナス」のみ） |
| マスターの報酬行（`mst_login_bonus_content`・`mst_vip_login_bonus_content`。`day` ごと） | `LoginBonusCalendarDay`（`day` 昇順）・`rewards: Array[LoginBonus]` | `day` が 1〜`cycle_days` の範囲外（`day = 0` のカムバック用を含む）の行は捨てる。`1..cycle_days` のうち行が無い日は**空の日**（`unknown` の絵のみ・数量なし）として補う。日の中の並びは `sort_desc` の降順（同値は `content_type`・`content_mst_id` の昇順）|
| マスターの報酬行の列 | `LoginBonus`（`type` = `content_type`・`id` = `content_mst_id`・`amount` = `content_quantity`・`metadata` = `content_option`。`unique_id` は空） | NULL は既定値（空文字・0・`{}`）。`content_option` は JSON 文字列なら辞書に直し、直せなければ `{}`。`content_type` が空の行は捨てる。**未知の `content_type` は捨てない**（`unknown` の絵で出す）。**`wallet` は `mst_item` を引いて名前・絵を決める**（`is_wallet` が偽・引けなければ `unknown`）。`amount`（出す数量）は **`content_quantity` × `amount`** で計算する（通常は配布回数・VIP は倍率。要件 B 節・サーバー）。`is_paid`（通常の行のみ）が真なら `metadata` に `is_paid: true` を足す。SQLite の真偽値・整数は 0/1 の整数で来るので、`is_paid`・`is_wallet` は真偽値に直して読む（0 以外を真） |
| `login_bonus_list`（既存） | `LoginBonus` | 変更なし（`LoginResponse._to_login_bonus`） |
| receive の `updated_resources` | `ApplyUpdatedResourcesUseCase` の入力（辞書のまま） | 無い・null・Dictionary でない → `{}`（取り込みなし）。4 種のキーは配列/辞書の型を確かめ、違えば無視 |
| receive の `vip_login_bonus_calendar` | 置き換える VIP の段（`LoginBonusCalendarResponse`） | 段として読めなければ、メモリの VIP の段を `duplicate_as_re_received()` で更新して代える（`is_granted_now` 真・`can_re_receive` 偽）。list と同じ変換を使う。**代替のときは `login_bonus_list` の報酬行も読めないので、「今日配られた報酬」に足せない**（所持数は `updated_resources` で反映される） |
| receive の `login_bonus_list` | `ReceiveVipLoginBonusResult.rewards`（`LoginBonus` の配列） | 既存の `LoginResponse._to_login_bonus` と同じ変換。無い・null → 空（行を足さない） |
| receive の `trx_vip_login_bonus` | 使わない（照合のみ） | 日数・`vip_level` は応答の `vip_login_bonus_calendar` から取る。`received_at` の書式はサーバーも未確認（S3 で実測）なので**クライアントは読まない**。キーが無くても失敗にしない |

- 変換のクラスは `LoginResponse`（login 応答）と `LoginBonusCalendarsResponse`（list 応答）が、段 1 つを `LoginBonusCalendarResponse.from_dict()` に任せる。**2 通りの変換を作らない**（形は同じ）。報酬・周期は応答のクラスではなく `master_data` の Repository が作る
- 画面（presenter）は `LoginBonusScreen` だけを見る。生の Dictionary を domain・presentation に渡さない（architecture.md の腐敗防止層）

## 5. アイコン・アセット

### 5-1. 置き場と規格（I1〜I8）

| 項目 | 決定 |
| --- | --- |
| 置き場 | `assets/icons/items/<mst_item.id>.svg`（`mst_item` 全行。IDs はサーバーの `MstItemSeeder` の 29 行から転記）、`assets/icons/fallback/category_<mst_item.type>.svg`（9 種）・`fallback/unknown.svg`、`assets/icons/ui/stamp_check.svg`（スタンプ） |
| 規格 | ビューボックス 128×128、余白 8、背景透明、最小の線の太さ 4（128 基準）以上、太い輪郭線なし、角丸・柔らかい影・ごく控えめなグラデーション。色は夜空（青紫系）に合わせた限定パレット 1 つを全アイコンで共通。色だけで意味を伝えない（形も変える。I7・I8） |
| import | SVG の既定（スケール 1.0）。表示は 80（通常のマス）・72（VIP のマス）・56（報酬の行）・48（ホーム）なので 128 のラスターで足りる。S5 で import の設定（`.import`）はリポジトリに入れる |
| 数 | 29＋10＋1 = 約 40 |

### 5-2. 引き方（I5・I9）

- `ItemIconResolver.resolve_key(type, id, mst_item_type, exists)`（core/domain の純粋関数）:
  1. `exists("items/" + id)` → `items/<id>`（`id` が空のときは飛ばす）
  2. `mst_item_type` が空でなく `exists("fallback/category_" + mst_item_type)` → `fallback/category_<type>`
  3. それ以外 → `fallback/unknown`
  - **`type` が `unit`・`equipment`・`stamina`・`paid_diamond`・未知の値のときは 1・2 を飛ばして 3**（枠のアイコンは対象外・I11。`stamina` は `mst_item` の行ではない。Q4）。`item`・`wallet` は `id` で引く（`wallet` は `mst_item.is_wallet = true` のアイテム。マスター由来の行の `content_type = wallet` は、`ItemIcon` には `type = item` として渡し、`gold` などへの読み替えを固定で持たない）
  - どの段でも例外・空表示にしない。マスターが無くても 1・3 は動く（`mst_item_type` は空で渡るだけ）
- **`mst_item_type` の出どころ**: ログインボーナスでは `GetLoginBonusDisplaysUseCase` とカレンダーの表示値の作成（`GetLoginBonusScreenUseCase`）が `MstItemRepository.get_by_id(id).type` を引いて渡す（`unit`・`equipment`・`stamina` は引かない）。**マスターが引けなければ空**。ホームは固定の 3 つ（5-5）で `items/` が必ず在るので渡さない。**引きは画面を開くとき 1 回だけ**（`master_data_loaded` は購読しない。非機能）
- `ItemIcon.setup(...)` が `ItemIconResolver` に `ItemIconTable.has_key` を渡し、`ItemIconTable.texture_of(key)` を `texture` に入れる。`mst_item` を引かない・`master_data` を参照しない（C1）

### 5-3. 動的パスを使わない（U-5 の既定案）

`"res://assets/icons/%s.svg" % id` の動的な `load` は、書き出し（実機ビルド）に入るかが未確認（要件 F）で、`make check-release` も `%` を含む参照は検査しない。**生成スクリプトが `item_icon_table.gd`（キー → `preload("res://assets/icons/…")` の定数辞書）を作り、`ItemIcon` はそこだけから読む**。利点: ① `preload` の実在が `make check-release` で検査される ② 書き出しの設定に依存しない ③ ID に無いキーは `has_key` が偽で、フォールバックへ落ちる。実機の書き出しは別の確認（本機能の確認は複製の起動検査まで）。

### 5-4. 生成スクリプトと ASSETS.md（I1・I7）

- `tools/icons/generate_icons.py`（**標準ライブラリだけ**。乱数を使わない・使うなら種を固定。実行は何度でも同じ出力）: 図形のテンプレート（回復の瓶・ブースト・経験値の結晶・素材・通貨のコイン・ダイヤ・スタミナ・資源・ポイントのバッジなど。カテゴリごとに共通の形）と、ID ごとの差分の表（色・中身の量・小さな印の数）から、全 SVG と `item_icon_table.gd` を出力する
- 実行: `python3 tools/icons/generate_icons.py`（`make icons` として登録）。**検査**: `make check-icons`（生成して git の差分が出ないこと、各 SVG が規格を満たすこと〔viewBox・サイズ上限・禁止要素〕、表のキーと実在の一致）。`make check` に足す（実行が軽い。12 節 Q-4 の仮置き）
- `docs/ASSETS.md` に「アイコン（自作）」の節を足す: 規格（5-1）・引き方（5-2）・生成と検査の手順・**`mst_item` に行が増えたとき**（`tools/icons/` の差分の表に 1 行足して再生成。足し忘れてもフォールバックで出るので画面は壊れない）・容量の実測値（5-6）。`THIRD_PARTY_NOTICES.md` は変えない（自作）
- 先に**比較用の 3 点**（例: `free_diamond`・`gold`・`unknown`）だけ作り、画風と import 後の見た目・容量を確かめてから全点へ（要件の段取り）

### 5-5. ホームの値の横の絵（I10・D-1・Q11）

- 3 つの値ラベルを `HBoxContainer`（`ValueRow`）で包み、左に `ItemIcon`（48）を置く: コイン → `coin`、ダイヤ → `free_diamond`（**合計用の絵は作らない**。D-1）、スタミナ → `stamina_50`。値ラベルの位置は右にずれるだけで、パネルの大きさ・他の見た目は変えない
- ホームは `master_data` を使わず固定 ID で出す（`PlayerResourceIds` の `COIN`・`FREE_DIAMOND` と、スタミナ用の定数を足す）。ラベルの `@onready` パスと `home_presenter_test.gd` の参照を直す

### 5-6. 確認用の一覧画面（I12）と容量（R4）

- `debug/icon_gallery.tscn`（製品に入らない）: `ItemIconTable` の全キーを並べ、`MstItemRepository` を持てるときは**マスターに在って絵が無い ID**を赤く出す（全件を返す口が無いので、ギャラリーは `master.db` を読む debug 専用の読み取りを持つ。`master_data/` は変えない）。`--e2e-shot` で 1 枚に撮る
- **APK 容量の実測（R4）**: ① 比較用 3 点を作った時点 ② 全 40 点を作った時点の 2 回、(a) SVG ファイルの合計（`du`）、(b) import 後の `.godot/imported/` の該当 `.ctex` の合計、(c) `make release-project` した複製を `--export-pack` で pck にしたときのサイズ差（アイコンあり・なし。pck は書き出しテンプレート無しで作れる想定。作れなければ (b) を代用）を測る。基準は**アイコン全体 1MB 以内（目安）かつ背景動画（約 2MB）を超えない**。超えるときは SVG の import スケール・図形の数を見直す。結果は PR 本文と `docs/ASSETS.md` に書く

## 6. スタンプのアニメーション（K1〜K6）

**入口は 1 つ**: `CalendarCell.apply_state(state, play)`。`play = false` なら最終状態（押印済み・縁取りの強調）へ**即時**に飛ぶ。再表示・過去のマス・`FROM_HOME` はこの入口を最初から `play = false` で使う（K6。将来の「アニメーションを減らす設定」はここで`play` を偽にするだけで足りる）。

**再生するマス**（K1）: `CalendarCellView.play_stamp = true` のマスだけ。値は `GetLoginBonusScreenUseCase` が「その段が今日の段、かつ `is_granted_now` が真、かつ今日のマス」から作る。`FROM_HOME` の最初の描画では常に偽。

| 項目 | 値（要件の目安を確定） |
| --- | --- |
| スタンプの絵 | `assets/icons/ui/stamp_check.svg`: 赤橙（#E0483A 付近）の二重の円の印（外周の輪＋内側の輪）に白いチェック。**形（円＋チェック）で受け取り済みと分かる**（色だけに頼らない）。 マスの 7〜8 割を覆う（**実装は一辺 88＝マスの 5〜6 割**。押印後も「N 日目」「今日」と数量を読めるよう、絵の位置に収めた。V3b レビューの指摘） |
| 動き | 初期: スケール 2.0・透明度 0・位置はマスの中心。`Tween` で、スケール 2.0 → 1.0（`TRANS_BACK`・`EASE_OUT`。Godot の既定の overshoot で、着地で少し行き過ぎて戻る＝弾み）、透明度 0 → 1 は最初の 0.1 秒。使う動きは**位置・スケール・透明度だけ**（K5。シェーダ・パーティクルなし） |
| 時間 | **通常の段: 開始 0.3 秒（画面が出てから）・スタンプ 0.4 秒（着地 0.7 秒）**。**VIP の段: 開始 0.5 秒・0.4 秒（着地 0.9 秒）**。着地で**マスが明るくなる**（`modulate` の明るさを 1.0 → 1.3 → 1.0。**全体で 0.1 秒**）。どちらも 1.0 秒以内に最終状態（通常 0.8 秒・VIP 1.0 秒。K3）。両段を再生しない場合（片方だけ）は、その段の開始のまま |
| 再受け取り（`FROM_*` 共通） | 画面は既に出ているので、**応答を受けた瞬間に VIP の今日のマスのスタンプを一度外して（透明度 0）、0.3 秒後に同じ動きで押す**（着地 0.7 秒、全体 0.8 秒）。「受け取った感」を出すため（既に押印済みの絵の上に重ねるだけだと変化が分からない。12 節 Q-5 の仮置き） |
| 点滅 | 3 回/秒を超えない。「今日」の脈動は押印前だけ（周期 1.2 秒・1.04 倍）で、スタンプが始まったら止める |
| タイミングの基準 | 「画面が出て」= `_ready` の描画完了の次のフレーム。`Tween` はホスト（presenter）から作り、画面を離れたら kill する |
| スキップ（K4） | アニメーション中のタップは、実行中の Tween をすべて完了状態へ（`Tween.custom_step` か、`kill()` ののち各マスの `apply_state(state, false)`）で**最終状態へ飛ぶだけ**で、閉じない。完了後のタップでホームへ |
| e2e との関係 | 中央クリック（出てから 1.5 秒＋dwell）は完了後。写真（1.0 秒後）は VIP の演出の終了と同時刻になるので、**ログインボーナス画面の写真は 1.2 秒後に撮る**（`SHOT_DELAY` をこの画面だけ変える。11 節）。録画は 30fps 固定で、押印の動きが約 20 コマに写る |

## 7. 60fps（R2）の実測と方針

**基準**: iPhone X（A11）、背景動画（1080×1920）の再生中に、最大 14 マス（通常 7＋VIP 7）とスタンプで 60fps（フレーム 16.6ms）。動画では測れない（Movie Maker は固定フレーム）。

**実行形態**: `Performance` の描画統計（ドロー呼び出し・オブジェクト数）はヘッドレスでは取れない（描画しない）ので、`frame_probe.gd` は**ヘッドレスでない通常の起動**（ウィンドウあり。`--write-movie` は固定フレームで時間が歪むので併用しない）で動かす。

**制約**: 製品ビルドの書き出しテンプレートは手元に無い（CLAUDE.md の「未確認」）ので、**実機（iPhone X）での計測はこの環境ではできない**。実機計測は未解決（12 節 Q-6）。代わりに次の 2 段で見る。

1. **現行の画面の基準値（V2 の最初の作業）**: 現行のログインボーナス画面とホームを、**デバイス非依存の指標**で測る。`debug/frame_probe.gd`（debug 専用。`--e2e-frame-probe=<秒>` で、画面が出てから指定秒の `Performance` の値を記録して出力）で、`TIME_PROCESS`（ms）・`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`・`RENDER_TOTAL_OBJECTS_IN_FRAME`・ノード数（`OBJECT_NODE_COUNT`）を、画面が出てから 2 秒間の平均・最大で出す。開発機の値は絶対値としては使わず、**変更前後の比**とドロー呼び出し数・オブジェクト数（端末に依らない）で比べる
2. **変更後**: 同じ手順で、最大構成（通常 7＋VIP 7＋報酬 5 行）を測る。**ドロー呼び出し数・オブジェクト数が基準の何倍か**と、`TIME_PROCESS` の比を PR に書く。実機が使えるとき（誰かが書き出せたとき）は、Godot の Monitor（フレーム時間）で同じ 2 秒を測る

**軽くする順**（overview 5 節。要件の見た目の決定は変えない）: ① 「今日」の脈動を止める（最初から 1-3 のとおり押印前だけ） ② VIP のスタンプの開始のずらし幅・同時再生を減らす ③ マスの装飾（影・グラデーション）を事前に作った絵（SVG の中）に置き換える。**マスに `PanelContainer` ＋ `StyleBoxFlat` の影を使わない**（影・角丸は SVG の絵の側）を最初の設計から守る

## 8. スライス

サーバーの S2（設計）・S3（実装）は別の流れ。**V2 はサーバーに依存しない**ので先に出せる。V3 はサーバーの新キー・新 API が必要。

### V2: アイコン・共通部品（サーバー不要）

| 内容 | ファイル |
| --- | --- |
| 基準の実測（R2）の仕組みと、現行の値 | `debug/frame_probe.gd`、E2E の引数（11 節） |
| アイコン一式の生成と検査 | `tools/icons/`、`assets/icons/**`、`core/presentation/item_icon/item_icon_table.gd`（生成）、`Makefile`（`icons`・`check-icons`） |
| 共通部品 | `core/domain/item_icon_resolver.gd`、`core/presentation/item_icon/item_icon.{tscn,gd}`、`core/presentation/number_text.gd` |
| ホームの値の横の絵 | `home.tscn`・`home_presenter.gd`、`PlayerResourceIds`（スタミナ用の定数） |
| 確認用の画面 | `debug/icon_gallery.tscn` |
| 容量の実測（R4）、ASSETS.md | `docs/ASSETS.md`、PR 本文 |
| テスト | 9 節の V2 |

### V3: 導線・カレンダー・スタンプ・再受け取り（サーバーの S3 が必要）

| 内容 | ファイル |
| --- | --- |
| login 応答の新キー・list・receive の通信とモデル | 2-1 の login の domain・data（`LoginBonusCalendar*`・`*Response`・`LoginBonusCalendarApiRepository`・UseCase 3 つ）、`ApplyUpdatedResourcesUseCase`、`AppContext` |
| 画面（カレンダー・スタンプ・受け取りボタン・2 つの入口） | login の presentation 一式、`SafeAreaMargins` の移動、`SceneRouter` |
| ホームの導線（ボタン） | `home.tscn`・`home_presenter.gd` |
| e2e（ホームから開く・再受け取り・旧応答） | `debug/e2e_driver.gd` |
| 既存テストの更新 | `login_bonus_presenter_test`・`login_response_test`・`login_use_case_test` ほか（9 節） |
| ドキュメント | 10 節 |
| 60fps の変更後の実測 | 7 節 |

S2 のマージ後の差分は直し済み（12 節）。V2 と V3 は別の PR・別の会話に分ける（`docs/<機能>-client-v2` など。ブランチ名は実装時に決める）。

## 9. テスト（GdUnit4。`make check-quiet` を通す）

「前提 → 操作 → 期待」をテストごとに書く（coding-standards の規約 7）。偽物の Repository は `tests/unit/contexts/login/domain/fake_login_repositories.gd` に足す。

**V2**
- `ItemIconResolver`: `items/<id>` が在る → そのキー。無い＋`mst_item_type` あり → `category_*`。両方無い → `unknown`。`type` が `unit`・`equipment`・`stamina`・`paid_diamond`・未知 → `unknown`（`items/` に同じ ID があっても引かない）。`id` が空 → `unknown`。述語が全て偽 → 常に `unknown`（空にならない）
- `ItemIconTable`: 生成物の全キーが `has_key` で真・`texture_of` が `null` でない（`preload` の実在）。`fallback/unknown` と `ui/stamp_check` が必ず在る
- `ItemIcon`: `setup` で `texture` が入る・存在しない ID でもエラー・空表示にならない（シーンを作るテスト）
- `NumberText`: 20000 → `20,000`、0、負、3 桁の境界（`HomeText.format_number` と同じ結果）
- `tools/` の生成の検査（`make check-icons` の単体テスト: 規格違反の SVG を弾く・表と実在の不一致を弾く）
- ホームの presenter: 3 つの `ItemIcon` が在り、値ラベルの文字が従来と同じ（パスの変更に追従）。ボタン（V3）は含めない

**V3**
- `LoginBonusCalendarResponse`（サーバー api.md 2.4 の例の JSON のうち進捗の項目を固定の入力にする。`last_received_day` の名前の取り違えを防ぐ）: 正常な段・null・キー無し・Dictionary でない・`last_day` null・真偽値が null/0/1/文字列（偽に落ちる）・全日の報酬が応答に**無くても**読める
- `LocalMstLoginBonusRepository`／`LocalMstVipLoginBonusRepository`（`LocalMstItemRepository` のテストの方式。偽の `MasterDatabase`）: 引ける・引けない（null）・テーブルが無い（null）・報酬行が `sort_desc` 降順で同値は `content_type`・`content_mst_id` 昇順・`day = 0` を捨てる・範囲外の日を捨てる・欠けた日を空の日で補う・`content_option` が壊れた JSON でも落ちない・`is_wallet` が 0/1 の整数で来ても真偽値に直る・数量が `content_quantity` × `amount`・VIP の読みが `deploy_key` の列に依存しない（`deploy_key` の無いテーブルの偽の DB で引ける）・`try_select_rows` が失敗（列なし・テーブルなし）で `ok = false`、0 件では `ok = true`・`sort_desc` の列が無い古い配信ファイルで「失敗」が返る（空配列と区別される）・古い配信ファイルの `mst_item`（`is_wallet` の列が無い）でも `get_by_id` が引ける（偽）
- `PrepareLoginBonusMasterUseCase`（偽の `CheckMasterDataUseCase`）: 全部引ける → 再取得しない・引けない段がある → `handle()` を 1 回だけ呼んで引き直す・再取得後も引けない/FAILED/IN_PROGRESS → その段は引けないまま返る（出す・出さないは画面の UseCase）・再取得を繰り返さない
- `ReceiveVipLoginBonusResponse`: `trx_vip_login_bonus`・`login_bonus_list`・`vip_login_bonus_calendar`・`updated_resources` の取り出し・各キー欠落でも失敗にしない・`vip_login_bonus_calendar` が `is_granted_now` 真・`can_re_receive` 偽で VIP の段になる
- `LoginResponse`: 新キー無しの旧応答で `login_bonus_calendars` が空、`login_bonus_list` は従来どおり。新キーがあっても既存の項目は変わらない
- `GetLoginBonusScreenUseCase`（**中核。表の全行**）: 今日の段（`last_day` = 1・中間・`cycle_days`）・今日の段でない・`is_granted_today` が真で `last_day` が範囲外・`is_granted_now` が真/偽（`play_stamp` が今日のマスだけ）・通常だけ/VIP だけ/両方/どちらも無い・8 日超（文字の画面）・再表示の旨の条件（どの段も今日の段でない日は出さない。T3・U-3）・`FROM_HOME` は `login_bonus_list` の行を出さない・サイクルが 1 周した後（`last_day` = 1 で前サイクルのスタンプを引き継がない）・カムバックだけが配られた日・`content_type = wallet` の報酬が `mst_item.is_wallet` の行として名前・絵で出る・片方の段だけ引けるとき（引けた段だけ表示・VIP を引けなければボタンも出さない）・両方引けないときの文字の画面
- `FetchLoginBonusCalendarsUseCase` / `ReceiveVipLoginBonusUseCase`（偽の Repository）: 成功でメモリが更新される・VIP の段だけ `is_granted_now` が真で通常は変わらない・`ApplyUpdatedResourcesUseCase` が呼ばれる・失敗で何も反映しない・`BUSINESS`（26001〜26003 の 299）の `can_reuse` が偽（キー作り直し）。BUSINESS の後の再送は新しいキー・通信断の再送は同じキー（presenter のテストで `_receive_key` の変化を見る）
- `ApplyUpdatedResourcesUseCase`: `trx_item_list` の差し替え（`mst_item_id` で置換・無ければ追加・他の行は残す）・`trx_diamond` の置換・キー無し/null/型違いで何も壊さない・他のキーを無視・`trx_wallet_list` の差し替え（`mst_item_id` が `coin` の行）・ホームの `CoinAmount`（wallet）・`DiamondTotal`（item）に反映される
- `LoginBonusCalendarApiRepository`: list は冪等キー無し（リクエストのヘッダーに `X-Unique-Request-Identifier` が無い）・receive は冪等キーつきで本文に `mst_vip_login_bonus_id`・`ApiResult` の失敗が `AppError` になる（`login_api_repository_test` の方式）
- `login_bonus_presenter`（シーンを作る）: `FROM_LOGIN` は通信しない・段の有無でセクションの表示が切り替わる・受け取りボタンは `can_re_receive` のときだけ・押下中は無効・成功で VIP のマスがスタンプ・BUSINESS で取り直し・タップでホーム（ボタンのタップでは閉じない・連打で 1 回）・アニメーション中のタップは閉じず最終状態へ
- スタンプ: `apply_state(play=false)` が最終状態（押印・縁取り）・`play=true` の後に完了すると同じ最終状態・再受け取りでスタンプが外れて再度押される
- `HomePresenter`: ボタンで `goto_login_bonus_from_home` が 1 回呼ばれる（連打でも 1 回）。メール・お知らせは何も起きない（P3 のまま）
- `SceneRouter` の定数の実在（既存の方式）
- 依存方向: `make check-deps`（新ファイルが P1・P2・C1 に違反しないこと）

## 10. ドキュメント更新（実装 S5 で行う。ここでは一覧だけ）

| 文書 | 更新 |
| --- | --- |
| `.claude/api.md` | login の新キー・`POST /login_bonus/list`・`POST /login_bonus/receive`（項目はサーバーの api.md を指し複製しない）、冪等キーの対象に receive を追加、`updated_resources` の節を「ホームが読む 4 種を取り込む」へ |
| `.claude/architecture.md` | 階層の例に `core/presentation/item_icon/`・`safe_area_margins.gd` の移動、login の構成（`login` の保持はカレンダーも）、`ItemIconResolver` を core/domain に置く理由 |
| `.claude/implementation-history.md` | この機能の経緯 |
| `docs/ASSETS.md` | アイコン（5-4） |
| `CLAUDE.md` | 命令・コマンドの表に `make icons`・`make check-icons`（`make check` に含むなら） |
| `docs/design/title-to-home/client_design.md` | login の保持先に新キーを 1 行（Nexus の全体設計 8 節のドキュメント更新と同じ。仕様は Nexus を指す） |

## 11. 確認手順（S5 で動画に撮る操作と期待結果）

### 11-1. 前提

- 撮影の基本は Nexus の `docs/workflow/recording.md`（Movie Maker・540 幅へ変換・PR にドラッグ&ドロップ）。サーバーは動画用のシードを入れる（`make seed` → `make seed-recording`）。**カレンダー用のシナリオはサーバー設計 db.md 6 節の録画用シーダー（`Recording/Scenarios/` の `RecordingLoginBonusProgressSeeder`［仮の名前。サーバー側も仮置き］。シナリオ ①〜⑧）**。**既定の一覧に入らず、`RECORDING_PLAYER_MY_ID`（`sys_player.my_id`）で 1 人を指して書き換える**（無いと何もしない）。11-2 のシードの列はこのシナリオの番号で書く。**分類: ①〜⑤・⑦・⑧ はプレイヤー単位のシード（上の指し方）。⑥ は `mst_vip_login_bonus.is_active` を切り替える**マスターの変更**で、プレイヤーを指さず全員に効く（戻し方は F の前提）。** シナリオ ①〜⑧ は login で配る前の状態（①②④⑤）または配った後の状態（③⑦⑧）を作るので、1 回 login すると状態が進む。ケースごとに撮り直す前に同じシナリオで上書きし直す**（`make seed-recording-one SEEDER=<クラス名>`。シナリオの選び方はサーバー側が未決。12 節 Q-9）
- **再試行・取り直しの冪等キー（確認項目）**: ケース K・L の e2e の通信の記録（`ApiClient` のログまたは偽の通信層）で、(a) receive が 26001 の後の次の送信は**前と違う** `X-Unique-Request-Identifier`、(b) list の呼び出しに `X-Unique-Request-Identifier` が**無い**、(c) 通信断（`--e2e-fail-bonus=network`）後の receive の再送は**同じキー**、を単体テストと合わせて確かめる。**同じキーで 26001 を再送すると古い 299 が返り続ける**（`X-Idempotency-Cache: HIT`）ので、(a) が守られないと取り直しても受け取れない
- 1 コマずつ見る: `--e2e-dwell=<秒>` で止める。アニメーションは `ffmpeg -ss <秒> -frames:v 1` で、押印前（0.2 秒）・押印中（0.5）・着地後（1.1）の 3 枚を、**`E2E: 画面 <path>` の行の `t` に足した秒**で抜いて見る（動画の先頭からの秒ではない。次のドライバーの拡張）。**動画では 60fps を測れない**（7 節。測定は別の手順）
- ドライバー（`debug/e2e_driver.gd`）の拡張（V3）:
  - `--e2e-open-login-bonus`: 通常の流れ（ログインボーナス → ホーム）の後、ホームで `ACTION_DELAY`＋dwell 待って**「ログインボーナス」ボタンをクリック**し、`FROM_HOME` の画面を開く。その画面で dwell 待ち、中央（ボタンの無い位置）をクリックしてホームへ戻り、終了する
  - `--e2e-receive=home|login`（**押す入口を指定する。値なしは不可**）: 指定した入口の画面で、受け取りボタンが出ていれば dwell の後に**ボタンの中心をクリック**する。ボタンが無ければ押さず「ボタン無し」を出力する。**指定と違う入口の画面では押さず、dwell の後に中央（ボタンの無い位置）をクリックしてホームへ進む**。押した後は dwell 待ってから中央をクリック
  - `--e2e-stale-receive`（**値なしのフラグ**。入口は `--e2e-receive=home|login` が決める）: `--e2e-receive` が押す画面で、押す直前にドライバーが `ReceiveVipLoginBonusUseCase` を直接呼んで先にサーバー側を受け取り済みにしてから、古い画面のボタンを押す（BUSINESS → 取り直しの再現）
  - `--e2e-fail-bonus=<種別>`: `/login_bonus/*` の応答を偽の失敗にする（`--e2e-fail-login` と同じ種別: 503 / 409 / 429 / network。回数は `--e2e-fail-count`）
  - `--e2e-frame-probe=<秒>`: 7 節の計測を出力
  - **基準時刻の出力**: 既存の `E2E: 画面 <path>`（画面が変わった最初のフレームで出る行）に **`frame=<Engine.get_frames_drawn()> t=<秒>`** を足す。**`t` は 30fps 固定の録画の時間（`frame ÷ 30`。Movie Maker の固定 delta の積算 `_elapsed` と同じ値）**で、動画の先頭からの秒に等しい。押印の撮るコマは、ログインボーナス画面の行の `t` に **0.2・0.5・1.1 秒**（押印前・押印中・着地後。**通常は 0.7 秒・VIP は 0.9 秒で着地し、VIP の演出の終了は 1.0 秒ちょうどなので、着地後は 1.1 秒に撮る**）を足して `ffmpeg -ss` を決める。`--e2e-shot` の写真は画面ごとの相対時刻で撮るので影響なし。**再受け取りの押印は、応答を受けた時点で `E2E: 受け取り応答 frame=… t=…` を出し**、それに 0.2（外れた状態）・0.5・1.1 秒を足す（押印の開始は応答 +0.3 秒、着地 +0.7 秒、終了 +0.8 秒）
  - 写真: ログインボーナス画面は 1.2 秒後。`FROM_HOME` の画面は `bonus_home` の名前で撮る（読み込み完了後）。終了時に `E2E_RESULT:` の行で、画面の段の状態（今日の日数・マスの状態の並び・ボタンの有無）を出す（文字ではなく UseCase の結果を出して目視と照合する。ホームの前例と同じ）

### 11-2. ケース（動画 1 本 1 ケース。期待結果は要件の体験の番号と対応）

| # | シード（サーバーの前提状態） | 操作（引数） | 期待結果 |
| --- | --- | --- | --- |
| A | シナリオ ①（初回。行なし・`last_login_at` null。VIP は全レベルに 7 日の行がある） | `--e2e-reset --e2e-dwell=2`（新規プレイヤーが ① の状態そのもの。シード不要） | 通常・VIP の 2 段が 1〜7 日目で並ぶ。両方の「1 日目」が今日（縁取り＋「今日」）。**通常 0.3 秒後・VIP 0.5 秒後に 1 日目へスタンプ**。2〜7 日目は暗い（未来）。下に「今日配られた報酬」（絵＋名前＋数量）。7 日目のマスは幅が広い。体験 1 |
| B | シナリオ ②（3 日目まで・前日 login。今日 4 日目を配る） | **Q-9 の手順**（`--e2e-reset` なし）で `--e2e-dwell=2` | 1〜3 日目は押印済み（アニメーションなし）で少し暗い、4 日目だけアニメーション、5〜7 日目は未来。体験 2・3 |
| C | シナリオ ③（B のあとの同じ日の 2 回目） | Q-9 の手順（リセットなし）で `--e2e-dwell=2` | 「本日のログインボーナスは受け取り済みです」が上に出る。4 日目は**最初から押印済み**でアニメーションなし。「今日配られた報酬」の行は無い。体験 4 |
| D | シナリオ ④（6 日目まで・前日 login。7 日目を配る） | Q-9 の手順（リセットなし）で `--e2e-dwell=2` | 7 日目（広いマス）にスタンプ。全マス押印後の最終状態。特別な演出なし。体験 5 |
| E | シナリオ ⑤（7 日目まで・前日 login。1 周して 1 日目） | Q-9 の手順（リセットなし）で `--e2e-dwell=2` | 前のサイクルのスタンプは引き継がれず、1 日目が今日・スタンプ。2〜7 日目は未来。体験 6 |
| F | シナリオ ⑥（**マスターの変更**。対象レベルの `mst_vip_login_bonus.is_active = false` で VIP の項目が `null`。プレイヤー単位のシードではなく全員に効く。撮影後は `is_active` を戻す＝`make seed-recording-reset`［または再 seed］。11-1） | 新規プレイヤーで `--e2e-reset --e2e-dwell=2`（マスターの切り替えだけで足りる） | 通常の段だけ。VIP の見出し・マスは出ない。体験 7。通常も無効なら「受け取り済み」の文字画面（文字の画面の確認） |
| F2 | **サーバーのシナリオに無い**（通常が無効＝`mst_login_bonus` の `daily_login` を無効にする状態。12 節 Q-10） | （足されたら）`--e2e-reset --e2e-dwell=2` | **VIP の段だけ**が出る（通常の見出し・マスは無い）。VIP の今日のマスにスタンプ。体験 7 |
| G | シナリオ ⑦（通常は受取日が今日、VIP は受取日が前日か行なし、`last_login_at` は今日。VIP は `is_granted_today` 偽。両方が今日の段でない状態はサーバーのシナリオに無い。Q-10） | Q-9 の手順（リセットなし）で `--e2e-dwell=2` | **VIP の段だけ**が全日未強調（スタンプも強調も無い）。**通常の段は今日の段なので、1-3 の規則どおり「本日のログインボーナスは受け取り済みです」が出る**。体験 8（両段とも今日の段でない場合は出ないことは `GetLoginBonusScreenUseCase` の単体テストで確かめる。Q-10） |
| H | シナリオ ③（再受け取り不可。login 済みの状態） | Q-9 の手順（リセットなし）で `--e2e-open-login-bonus --e2e-dwell=2` | ホームに「ログインボーナス」ボタン（メール・お知らせの隣。バッジなし）。タップで読み込み中 → カレンダー。**アニメーションなし**・今日のマスは押印済み・受け取りボタン無し。ボタン以外のタップでホームへ戻る。H1〜H5 |
| I | シナリオ ⑧（VIP を今日受け取り済み・`vip_point` を加算してレベルが上がった状態。`can_re_receive` 真） | Q-9 の手順（リセットなし）で `--e2e-open-login-bonus --e2e-receive=home --e2e-dwell=2` | **押す画面は `FROM_HOME`**（login 直後の画面にもボタンが出ているが押さず、中央クリックでホームへ進む）。`FROM_HOME` の VIP の段の下に**受け取りボタン**。押すと「受け取り中…」→ **VIP の今日のマスのスタンプが外れて再度押される**・ボタンが消える・報酬の行に新レベルの報酬。通常の段は変わらない。ホームに戻ると、**報酬に含まれる種類の所持数が増えている**（コインは `trx_wallet_list`、無償ダイヤは `trx_item_list`、スタミナは `trx_stamina_list` から。マスターの報酬に無い種類は変わらない）（`E2E_RESULT` の所持数と照合）。R1〜R7・Q31 |
| J | シナリオ ⑧（`last_login_at` が今日であること。そうでないと login が通常の配布をして `is_granted_now` が立つ。Q-9） | Q-9 の手順（リセットなし）で `--e2e-receive=login --e2e-dwell=2`（`--e2e-open-login-bonus` なし） | **押す画面は `FROM_LOGIN`**。login 直後の画面にボタンが出て、押すと I と同じ（スタンプ・報酬の行・ホームの所持数）。H4 |
| K | シナリオ ⑧（押す前に別の経路で受け取り済みにする） | Q-9 の手順（リセットなし）で `--e2e-open-login-bonus --e2e-receive=home --e2e-stale-receive --e2e-dwell=2`（`login` 入口で試すときは `--e2e-open-login-bonus` を外し `--e2e-receive=login`） | **押す画面は `FROM_HOME`**（先行受け取りは `--e2e-receive` と同じ画面で、押す直前）。ボタンを押す → サーバーが業務エラー → 状態を取り直してボタンが消え「状態を更新しました」。画面は壊れない。二重受け取りは起きない（ホームの所持数が 1 回分） |
| L | シナリオ ③ | Q-9 の手順（リセットなし）で `--e2e-open-login-bonus --e2e-fail-bonus=network --e2e-dwell=2` | `FROM_HOME` の読み込みが失敗し、エラー文＋「再試行」。タップでホームへ戻れる |
| M | **この機能を入れる前のサーバーの版**（新キー・新 API が無い。用意: サーバーのリポジトリで、この機能の最初の変更の親のコミットを別の作業ツリーに取り出して起動し、`NEXUS_API_BASE_URL` をそちらに向ける。コミットの特定と起動手順はサーバー設計にも README にも無いので S-10 のまま未解決） | `--e2e-dwell=2` | カレンダーを出さず、今の文字の画面（「ログインボーナス!」＋行、または「受け取り済み」）。落ちない。旧サーバーのときホームのボタンを押すと、list が 404/エラーになり、L と同じ表示（要確認の挙動。12 節 Q-7） |
| N2 | 古いマスター（同梱 DB に段の ID が無い。ダウンロードを止める） | Q-9 の手順（リセットなし）で `--e2e-dwell=2`（マスターのダウンロードを失敗させる引数は実装で決める） | 画面を出す前に「読み込み中…」→ 再取得が失敗 → 今の文字の画面にフォールバックし、タップでホームへ進める。落ちない（2-4）。両方の段を引けない場合の動き（片方だけ引けるなら引けた段だけ表示する） |
| N | アイコンの確認 | `godot --path . debug/icon_gallery.tscn --e2e-shot=<dir>`（形は実装で決める） | 全アイコンが 1 枚に並ぶ。マスターに在って絵が無い ID は赤。`unknown`・`category_*` も見える |

- 未知の `content_type`・`unit`・`equipment` の絵（`unknown`）は、録画用シードで作りにくいので単体テストと、ギャラリー（N）の `unknown` で確かめる。報酬が `unit`・`equipment` のマスターを録画用シードで足せるなら、ケース A に足す（サーバーに依頼。db.md 6 節のシナリオには無い）
- 各ケースで、**押印の 3 コマ**（`E2E: 画面` の `t`＋0.2・0.5・1.1 秒。再受け取りは `E2E: 受け取り応答` の `t` から）、ホームの値、`E2E_RESULT` の行（マスの状態の並び・ボタンの有無）を PR に載せる

### 11-3. その他の確認（動画以外）

- `make check-quiet`（依存方向 → lint → format → テスト → 複製の起動。`make check-icons` を含める場合はそこも）
- 製品用の複製: `make check-release-quiet`（`preload` したアイコンの実在・`tools/icons`・`debug/` の分類）。**実機の書き出しは未確認のまま**（CLAUDE.md の「未確認」）
- 実測: R2（7 節）・R4（5-6）の結果を PR に書く。**実機（iPhone X）での 60fps は未確認**と明記する

## 12. 未解決点

### S2 マージ後の差分の洗い出し（処理済み。サーバー設計 api.md・db.md・sequence.md と突き合わせた）

**注（未マージの同時改訂）**: 下の S-1・S-2・S-7・S-8 と 2・4 節は、人の決定（全日の報酬・周期をマスターから引く）に先に合わせた。Nexus の要件・全体設計とサーバーの設計 md は別の書き手が同時に直している（未マージ）。**それらのマージ後に、この文書との差分を確認して直す**（応答の項目・録画環境の配信。マスターの列名・量の式・並びはサーバーの実スキーマで確認済み。Q-11・Q-12）。

| # | 見る点 | 結果 |
| --- | --- | --- |
| S-1 | 新キーの名前・各項目の名前・型・null 可否 | **解決（人の決定で改訂）**。`login_bonus_calendar`・`vip_login_bonus_calendar`（常にキーあり。マスターが無いと `null`）。段は `mst_login_bonus_id`／`mst_vip_login_bonus_id`・`last_received_day`（null 可）・`is_granted_today`・`is_granted_now`、VIP は `vip_level`・`can_re_receive`。**全日の報酬・周期の日数は応答から外れた**。真偽値は真偽値型。4 節に反映（サーバー設計の改訂は未マージ。12 節の上の注） |
| S-2 | 日ごとの報酬の出どころ・並び・`unique_id` | **改訂**。応答に無く、クライアントが配信の SQLite のマスターを段の ID で引く（`master_data` に Repository・エンティティを追加。2-1）。並びは `sort_desc` 降順（Q-12）。`unique_id`・`expire_at` は無い |
| S-3 | receive の応答・パラメータ名 | **解決**。Post は `mst_vip_login_bonus_id`。応答は `trx_vip_login_bonus`（`received_at` の書式はサーバーも未確認。読まない）・`login_bonus_list`・`vip_login_bonus_calendar`・`updated_resources`。サーバーの**足した応答**（`login_bonus_list`・`vip_login_bonus_calendar`）はサーバー側でも仮置き（U-S2-6）。外れたら 3-2・4 節の「`duplicate_as_re_received()` で代える」に落ちる（報酬の行は出せなくなるので、外れる場合は設計を直す） |
| S-4 | 条件を満たさないときのエラー | **解決**。299 の 26001〜26003。**クライアントはコードで分岐せず BUSINESS として取り直し**。新しい冪等キー（3-4） |
| S-5 | `updated_resources` に VIP の状態・`trx_stamina_list` の主キー | **解決**。VIP の状態は含まれない（`trx_vip_login_bonus` を別キーで返す）。スタミナの主キーは `mst_stamina_type` ではなく **`type`**（3-3 を直した） |
| S-6 | list の冪等キー・ロック・失敗時 | **解決**。キーを付けない（サーバー api.md 7.1）。プレイヤーロックのため 409・503 は既存どおり（`ErrorView` の再試行） |
| S-7 | 不正な行（U-1）のときの日のマス | **改訂**。サーバーは行を除かなくなり、クライアントがマスターを読む。未知の `content_type`・引けない `wallet` は `unknown` の絵、行の無い日は空の日（`unknown` の絵のみ・数量なし）。1-3 |
| S-8 | wallet 系報酬の `type`・`id` | **改訂**。`content_type = wallet` は `mst_item.is_wallet = true` のアイテムとして `mst_item` を `content_mst_id` で引く（`gold` への読み替えを固定で持たない）。`login_bonus_list`（応答の報酬）の `type` は従来どおり |
| S-9 | 録画用シードのシナリオ名・再受け取りの作り方 | **一部解決**。シナリオ ①〜⑧ と `RECORDING_PLAYER_MY_ID`（11-1・11-2 に反映）。クラス名・シナリオの選び方・プレイヤーの指し方はサーバー側も仮置きで、Q-9・Q-10 に残す |
| S-10 | 旧サーバーの版の取り出し方・起動手順、list・receive が返す応答 | **未解決のまま**。サーバー設計には無い（旧サーバーが新 API に返す応答の記述も無い）。Q-7 の既定案（エラー表示）で進め、取り出し手順はサーバーに依頼 |

### 確認事項（人が決める。既定案つき）

| # | 確認事項 | 既定案 |
| --- | --- | --- |
| Q-1 | 星の行（72）をこの画面から外してよいか（縦の高さを収めるため。1-4） | **外す**（余白 48＋①② で見積り 1512 が使える高さ 約 1599 に収まる。星の行 72 を残すと 1584 で余裕が約 15 になるので、残すなら実測で確かめる） |
| Q-2 | 新しい UseCase・保持を、既存の `contexts/login` に置くか、サーバーの `Domain/LoginBonus` に合わせて `contexts/login_bonus` を新設するか（overview は「サーバーは分離した LoginBonus ドメイン」と決めたが、クライアントのコンテキスト名は言っていない） | **既存の `login` に置く**（画面・保持・`LoginUseCase` が既にあり、分けると `login` ↔ `login_bonus` で保持の受け渡しが増える）。名前を揃えたいなら、`login_bonus` を新設して画面ごと移す（移動の PR を別に出す） |
| Q-3 | 再受け取りの後の「今日配られた報酬」の行: `FROM_LOGIN` は既存の行の後ろに足す、`FROM_HOME` は再受け取りの報酬だけ出す（3-2。R6 は「再受け取りの応答で返し、行に出す」までしか決めていない） | 3-2 のとおり。見出しは同じ「今日配られた報酬」 |
| Q-4 | `make check` に `check-icons`（生成物が最新か・規格）を足すか | **足す**（軽い。足し忘れの SVG・生成物の食い違いを CI で止める） |
| Q-5 | 再受け取りの押印を「一度外して押し直す」か、「押印済みのまま弾むだけ」か | **外して押し直す**（6 節。変化が分かるため） |
| Q-6 | 60fps を保てるかの実機（iPhone X）での確認の手段（書き出しテンプレートが無い）。人が実機で測るか、相当の端末か | **この設計では実機を測らない**。7 節の指標（ドロー呼び出し・オブジェクト数の比）で判断し、実機は別の確認として残す。実機で測れる人がいれば同じ 2 秒の手順を使う |
| Q-7（**S-10 待ち**。サーバー設計に旧サーバーの応答の記述が無い） | 新クライアント × 旧サーバーで、ホームの「ログインボーナス」ボタンを押したときの扱い（list が無い）。エラー表示で足りるか、ボタンを出さないか（login の新キーが無いことで旧サーバーと分かる） | **エラー表示（L と同じ）で足りる**（旧クライアントは未配布で、旧サーバーとの組み合わせは移行の短い間だけ） |
| Q-9（新規。録画） | `RECORDING_PLAYER_MY_ID` は既存プレイヤーを指すが、`--e2e-reset` は毎回新しいプレイヤーを作る。シナリオの選び方（1 クラス＋引数か小クラスか）もサーバー側が未決。⑧ は `last_login_at` を書かない記述で、J（login 直後に押す）は `last_login_at` が今日でないと再受け取りの前に通常の配布が走る | **手順（A 以外のケース。コードで確かめた）**: (1) `--e2e-reset` を付けて起動し、新規プレイヤーを作る。`E2E_RESULT: OK player_id=…` の `player_id`（`sys_player.my_id`。既存の出力）を控える。(2) `RECORDING_PLAYER_MY_ID=<player_id> make seed-recording-one SEEDER=<クラス名>` でそのプレイヤーを上書き。(3) **`--e2e-reset` を付けずに**起動する（トークンは `LocalAuthTokenRepository` が `user://` に保存し、`AuthenticateUseCase` は保存トークンが残っていれば再利用するので、同じプレイヤーで login する）。ドライバーの拡張は要らない。サーバーへの依頼は「⑧ は `last_login_at` を今日にする」だけで足りる（⑧ を**プレイヤー作成と同じ日**に使うなら、新規作成時の `last_login_at` が今日で済む）。シナリオの選び方の確定も依頼 |
| Q-10（新規。録画） | クライアントのケース F2（通常が無効で VIP だけ）・G（両方が今日の段でない）に当たるシナリオがサーバーの ①〜⑧ に無い | サーバーに足すよう依頼する。足されるまでは単体テスト（`GetLoginBonusScreenUseCase`）で確かめ、動画はケースから外す |
| Q-11（**実スキーマで確定**。サーバーのレビューで確認済み） | クライアントが引くマスターの形: テーブルごとに別の SQLite ファイルで配信される（`mst_login_bonus`・`mst_login_bonus_content`・`mst_vip_login_bonus`・`mst_vip_login_bonus_content`・`mst_item` は別ファイル。JOIN しない）。列: 通常の報酬行 `deploy_key`・`mst_login_bonus_id`・`day`・`content_type`（item/unit/equipment/wallet/stamina）・`content_mst_id`・`content_option`（JSON）・`content_quantity`・`amount`（配布回数）・`is_paid`・`sort_desc`（複合主キー・`id` 無し）。VIP の報酬行は `id`（連番）・`mst_vip_login_bonus_id`・`day`・`content_type`（string）・`content_mst_id`・`content_option`・`content_quantity`・`amount`（倍率）・`sort_desc`（`deploy_key`・`is_paid` 無し）。VIP の本体にも `deploy_key` は無い。`mst_item.is_wallet` は元からある列（boolean。SQLite では 0/1）。**(4) 確認済み（事実。`data/master.db` を `sqlite3` で確認）**: 同梱 DB（`res://data/master.db`）のテーブルは `mst_gacha`・`mst_unit`・`mst_equipment` と各 `__l10n` の 6 つだけで、3 つの本体も 0 行。ログボの 4 テーブルと `mst_item` は無い（`is_wallet` 列も無い）。さらに `MasterDatabase.open_bundled` は `REQUIRED_TABLES` の 3 つだけを接続に登録するので、同梱 DB にあっても `select_rows` は空配列を返す。配信はテーブルごとの別ファイルで、同梱 DB は初回・更新 DB が欠けたときの戻り先 | 上の実名で作る（2-1・4 節）。数量は `content_quantity` × `amount`。`is_wallet` の「列が無ければ偽」は古い配信ファイル対策として残す。同梱 DB には無いので、配信から取れるまではログボのマスターを引けず、`PrepareLoginBonusMasterUseCase` が `CheckMasterDataUseCase` を 1 回だけ実行して引き直す。取れない（オフライン・失敗）ときは文字の画面（2-4）に落ちる（コードで確認済み）。同梱 DB への追加は不要（入れると二重管理になる） |
| Q-12（人の決定済み。並び） | 並びの列は通常・VIP のどちらの報酬マスターも `sort_desc`（人の決定。昇順か降順かが列名で分かるように） | **降順（大きい値が先）**。**通常**: `ORDER BY day, sort_desc DESC, content_type, content_mst_id`。**VIP**: `ORDER BY day, sort_desc DESC, id ASC`（同値はサーバーの VIP の `id` 昇順。2-1 の SQL と同じ） |
| Q-13（新規。録画環境） | 録画環境にマスターの配信ファイル（テーブルごとの SQLite）が無い（U-12）。サーバーの録画用デプロイシードに配信ファイルを作る手順が無く、クライアントはマスターから描くので、配信が無いと文字の画面になる | **サーバーの録画用デプロイシードに配信ファイルを作る手順を足すよう、S3 の追加依頼として人に確認する**。それまでは単体テストと同梱 DB で確かめる（動画のケース A〜K はこの手順が前提） |
| Q-8 | 周期の日数が 8 を超える・1 未満のとき、画面全体を文字にするか、その段だけ落とすか（C1 は「カレンダーを出さず今の文字の画面に落とす」） | **画面全体を文字にする**（段ごとに混ぜると見た目が揃わない。8 日超は今の運用に無い） |

### 仮置き（既定案で進める）

- 画面の入口の渡し方: 入口ごとの継承シーン（1-1）。`SceneRouter` に引数の口を足す案は採らない（オートロードに状態を置かないため）
- スタンプ: 赤橙の円の印＋白いチェック。`TRANS_BACK`・`EASE_OUT` の既定の overshoot。明るさ 1.3 倍・0.1 秒（6 節）
- マスの状態の明るさ・彩度（受け取り済み 0.8・未来 0.5/0.7）、縁取りの色・太さ（4px。色は黄〜橙）は実装時に画面で調整する（要件は「目安」）
- `ApplyUpdatedResourcesUseCase` の取り込み範囲はホームが読む 4 種のみ（3-3）
- `SafeAreaMargins` を `core/presentation` へ移す（1-4。他に置き場の案: login の presentation にコピー → 二重定義になるので採らない）
- 受け取りボタンのラベル「受け取る」・Toast の文言「状態を更新しました」・「読み込み中…」・「VIP ボーナス　VIP n」は固定文字（ja）
- `HomeText.format_number` を `NumberText` に寄せる整理は、V2 で一緒にするか後回しにするかを S5 で決める（挙動は変えない）

### 実行で確かめる点（S5）

- 縦の高さの実測（最大構成で収まるか。1-4 の見積りの修正）
- `.svg` の import 後の容量・見た目（5-6・R4）、`--export-pack` が使えるか
- ギャラリーで `master.db` を debug 専用に読む方法（5-6）
- 継承シーンと `@export` の `entry`、`TapCatcher` の `gui_input` が背景動画・Panel の下でタッチ・マウスの両方を受けるか（`mouse_filter` の組み合わせ）
- `Tween` を画面離脱時に kill する漏れが無いか（連続で開閉して確認）
