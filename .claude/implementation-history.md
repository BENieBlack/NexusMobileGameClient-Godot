# 実装履歴

## 2026-09-02

### 認証フローの修正・改善

**問題**: クライアントとサーバのレスポンスキーが不一致
- `auth_service.gd` が `data.dtoToken`・`data.sysPlayer` を期待していたが、サーバは `token`・`sys_player` を返していた

**修正内容**:

1. **`auth_service.gd`**: レスポンスキー修正 (`dtoToken` → `token`, `sysPlayer` → `sys_player`)
   - シグナル `auth_completed` に `refresh_token` 引数を追加

2. **`api_client.gd`**: 以下を追加
   - HTTP 299 ビジネスエラー対応（`business_error` シグナル）
   - アクセストークン自動リフレッシュ（HTTP 401 時に `POST /auth/refresh_token` を呼び再送）

3. **`user_data_manager.gd`**: 以下を追加
   - `refresh_token` フィールドの保存・復元
   - `update_tokens()` メソッド（リフレッシュ後のトークン更新用）
   - `set_login_data()` メソッド（ログインAPI後のゲームデータ保存用）
   - `trx_unit_list`, `trx_item_list`, `trx_wallet_list`, `login_bonus_list` フィールド

4. **`title.gd`**: 認証完了後に `POST /auth/login` を呼び出し、ゲームデータを取得してからログインボーナス画面へ遷移

5. **`login_bonus.gd`**: `UserDataManager.login_bonus_list` のデータを実際に表示（ダイヤ・ゴールド・ユニット等のリソースタイプに対応）

6. **`.claude/` ディレクトリ**: プロジェクトドキュメントを整備
   - `README.md`, `architecture.md`, `coding-standards.md`, `api.md`, `language.md`
   - `.opencode` を `.claude` へのシンボリックリンクとして設定

## 2026-11-12

### タイトル〜ホームの新構成への移行完了（S5 第 3 段）

設計: `docs/design/title-to-home/client_design.md`。サーバー設計（正）に合わせ、旧構成（`scenes/` と `scripts/`）を新構成（クリーンアーキテクチャ + 軽量 DDD。`architecture.md`）へ置き換えた。旧構成は削除済み。

1. **画面（presentation）**: 各画面を `contexts/<名前>/presentation/<画面>/` の `*.tscn` + `*_presenter.gd` に移した。presenter は UseCase だけを呼ぶ。
   - タイトル（`TitlePresenter`）: マスター確認 → 認証 → login を段階で直列に進め、失敗した段階から「再試行」。login が成功するまで先へ進まない（旧実装の「login 失敗でもホームへ進む」を廃止）。冪等キーは presenter が保持（`IdempotencyKey.can_reuse` で再利用か作り直しかを決める）
   - 規約（`AgreementPresenter`）: 未同意が無ければ画面を見せずにスキップ。取得失敗はスキップせずエラー + 再試行。同意は規約ごとの冪等キーで 1 件ずつ送り、失敗した規約から再試行
   - ログインボーナス: 通信せず `GetLoginBonusesUseCase` の一覧を表示（`grade` は metadata にあるときだけ）。ホーム: `GetPlayerIdUseCase`
   - エラー文言は `core/presentation/error_messages.gd`、表示は `error_view.gd` に共通化（429 は `retry_after` の間、再試行ボタンを無効にする）
2. **オートロードの整理**: `EventBus` → `AppContext` → `SceneRouter` → `Toast`（+ 開発専用の `E2EDriver`）。旧 `UserDataManager` / `SceneManager` / `AuthService` / `MasterDataManager` / `ToastManager` を廃止。`Toast` は Reverb 接続の認証情報を `connect_to_reverb(user_id, access_token)` で受け取る形に変えた（挙動は旧と同じ。ギルドの自動購読は新構成へ移るまで行わない）
3. **旧構成の削除**: `scenes/`・`scripts/`（managers / services / models / repositories / tests）を削除。`api_test` は `debug/api_test/`（`AppContext` の `ApiClient` を使う形に書き換え）
4. **改名**: `master_data/` の `Master*`（`MasterUnit` など）を `Mst*` に、規約の `PendingAgreement` を `SysAgreement` に
5. **e2e ドライバー**: `debug/e2e_driver.gd`（`--e2e-case` / `--e2e-reset` / `--e2e-fail-login` / `--e2e-corrupt-token` など）。通しの確認に使う
6. **ドキュメント**: README・architecture（移行完了）・api・MASTER_DATA.md を新構成に合わせて更新

実サーバー（`http://localhost:8090`）に対し、e2e ドライバーでタイトル → 認証 → login → 規約（未同意なしでスキップ）→ ログインボーナス → ホームの通しが最後まで動くことを確認した。


## home-player-info 第 1 段: 基盤（2026-11）

設計: `docs/design/home-player-info/client_design.md`（2・3-3・5・6・7 節）。ホーム画面・スタミナ/ダイヤの計算は第 2 段。

- `X-Platform`: `ApiConfig.platform()`（環境変数 → `[nexus] platform` → OS の既定）を `ApiClient._build_headers()` の 1 か所で全 `request()` に付与。`download()` と Toast には付けない。`set_platform("")` で欠落を再現（e2e）
- 時刻: login 応答の `Date`（`HttpDate`）からサーバー時刻とのオフセットを作り `PlayerState` に保持。`Clock` / `SystemClock`（`skew_seconds`）、`ServerDatetime`（`Y-m-d H:i:s` の読み取り。失敗は -1）
- login 応答: `trx_diamond`（単数）を取り込み、旧 `trx_diamond_list` は読まない。`TRX_LIST_KEYS` は 5 種。`is_delete` は `PlayerState.is_row_deleted()`（真偽値・0/1）
- master_data: `mst_player_level` / `mst_config` の読み取りモデルと Repository（同梱せず、`REQUIRED_TABLES` も変えない）


## home-player-info 第 2 段: ホーム画面（2026-11）

設計: `docs/design/home-player-info/client_design.md`（1・2・3・4・8-2 節）。

- domain（`player/domain/`）: `StaminaRecovery`（整数計算の回復表示。起点は不変で二重加算なし）・`DiamondTotal`・`CoinAmount`（`services/` の純粋関数。architecture.md に例外を追記）、`StaminaSource` / `StaminaDisplay` / `HomeSummary` / `PlayerResourceIds`、`GetHomeSummaryUseCase`（開いたときとマスター更新時）・`GetStaminaDisplayUseCase`（tick ごと。now = 端末時計 + サーバー時刻のオフセット）
- presentation: `home.tscn` を縦並び（プレイヤー・スタミナ・通貨・導線）に作り直し。`HomePresenter` は UseCase を呼ぶだけ。1 秒の `StaminaTimer`（残り時間が無いとき止める）、復帰通知で再計算、`HomeText`（文言・桁区切り・時間）、`SafeAreaMargins`（セーフエリアの物理ピクセル → ビューポート座標）
- e2e: `--e2e-home-hold` / `--e2e-clock-skew` / `--e2e-omit-platform`、`E2E_RESULT` にホームの値


## free-diamond-item（2026-11）

設計: `docs/design/free-diamond-item/client_design.md`（1〜7 節）。

- `DiamondTotal`: 暫定項 `trx_diamond.free_amount` を削除（有償 `paid_amount` + `trx_item_list` の `free_diamond` だけ。キーが来ても足さない）
- ログインボーナス: `LoginBonus.is_free_diamond()`、`GetLoginBonusDisplaysUseCase`（`LoginBonusDisplay` = 受取 + `mst_item` の名前）、`LoginBonusPresenter` は名前を優先し、引けなければ `free_diamond` は「無償ダイヤ」・他の item は「アイテム (ID:…)」。`diamond` の分岐は削除
- master_data: `MstItem` / `MstItemRepository` / `LocalMstItemRepository`（`mst_item` と `mst_item__l10n`。同梱せず `REQUIRED_TABLES` も変えない）
- 言語: `ApiConfig.language()`（`ja` 固定）、`ApiClient._build_headers()` で全 `request()` に `Accept-Language: ja`（`download()`・Toast には付けない）
- e2e ドライバーは変更なし


## login-bonus-calendar V3a: マスターの読み取り・データ層・ドメイン層（2026-11）

設計: `docs/design/login-bonus-calendar/client_design.md`（2・3・4 節、9 節 V3）。画面は変えない（V3b・V3c）。

- master_data: `MstLoginBonus`・`MstVipLoginBonus` と報酬行、`Local*` Repository（テーブルごとに別の SQLite。`find_by_id` は FOUND / NOT_FOUND / UNREADABLE）、`MasterDatabase.try_select_rows`（失敗と 0 件を区別）、`MstItem.is_wallet`（`SELECT *`。列が無い古い配信ファイルでも引ける）
- login: 段の進捗 `LoginBonusCalendar(s)`、`LoginBonusStageMasterReader`、`PrepareLoginBonusMasterUseCase`（古いマスターは再取得 1 回。引けない段はその段だけ出さず、出せる段が無いときだけ文字の画面）、`GetLoginBonusScreenUseCase`（表示モデル `LoginBonusScreen`）、`FetchLoginBonusCalendarsUseCase`、`ReceiveVipLoginBonusUseCase`、`LoginBonusCalendarApiRepository`（list は冪等キー無し、receive は有り）
- player: `ApplyUpdatedResourcesUseCase`



## login-bonus-calendar V2: アイテムアイコン（2026-11）

設計: `docs/design/login-bonus-calendar/client_design.md`（5 節）。手順・規格は `docs/ASSETS.md`。

- アイコン: 自作 SVG（`assets/icons/items/<mst_item.id>.svg`・`fallback/`・`ui/stamp_check.svg`）を `tools/icons/generate_icons.py` で生成（`make icons`）。検査は `make check-icons`（`make check` に含む）
- core: `ItemIconResolver`（絵のキーを決める純粋関数。絵の有無は述語 `Callable` で受けるので `core/domain` に置ける）、`core/presentation/item_icon/` の `ItemIcon`（共通部品）と生成物 `ItemIconTable`（`preload` の表。動的な `load` は使わない）
- player: ホームのスタミナ・コイン・ダイヤの値の横にアイコン（`HomePresenter`）。値ラベルが幅 1 に潰れる不具合も修正
- debug: `icon_gallery`（全アイコンの一覧。マスターに在って絵が無い ID を赤く出す）


## e2e ドライバー: 進まない画面の検出（2026-11）

- `debug/e2e_stall_detector.gd`（`StallDetector`）: 同じ画面に居続け、クリック回数も条件を満たしたら `E2E_RESULT: FAIL stalled scene=… last_api_error=…`（コード 1）で早く終わる。`--e2e-stall-sec`（既定 30。0 以下で無効）・`--e2e-stall-clicks`（既定 5）。直近の API 失敗は `ApiClient`（`last_error`）が保持する


## login-bonus-calendar V3b・V3c: カレンダー画面・ホームの入口・VIP の再受け取り（2026-11）

設計: `docs/design/login-bonus-calendar/client_design.md`（1・3・6・7 節）。V3a の UseCase に画面をつないだ。

- 画面（`login/presentation/login_bonus/`）: `LoginBonusPresenter`（入口 `FROM_LOGIN` / `FROM_HOME`。継承シーン `login_bonus_from_home.tscn` が `entry` だけ変える）、`CalendarSection`・`CalendarCell`・`CalendarText`（固定文字を作る静的関数。段・マスの文字の画面は `LoginBonusPresenter.build_text`）・`RewardRow`（今日の報酬の行）・`StampPlayer`（押印のアニメーション）。`LoginBonusPresenter` は背面の `TapCatcher` でホームへ進み、前面の表示専用ノードは `mouse_filter = IGNORE`
- 入口: login 直後は通信しない。ホームの「ログインボーナス」ボタン（`SceneRouter.goto_login_bonus_from_home()`）は開くたびに `POST /login_bonus/list`（冪等キーなし。`FetchLoginBonusCalendarsUseCase`）
- 再受け取り: 受け取りボタン → `ReceiveVipLoginBonusUseCase`（`POST /login_bonus/receive`。冪等キーは presenter が持つ）。成功で `ApplyUpdatedResourcesUseCase` が所持数を反映し、VIP の段を置き換える。BUSINESS（26001〜26003）はコードで分岐せず、新しいキーで状態を取り直す
- `SafeAreaMargins` を `contexts/player/presentation/home/` から `core/presentation/` へ移動（ホームとログインボーナス画面が共有）
- e2e ドライバー: `--e2e-open-login-bonus`（ホームのボタンから開く）・`--e2e-receive=home|login`・`--e2e-stale-receive`（押す直前に先に受け取って業務エラーを再現）・`--e2e-fail-bonus=<種別>`（`/login_bonus/*` の偽の失敗）。`E2E_RESULT: OK` にログインボーナス画面の最後の状態を足す
- debug: `login_bonus_preview`（偽のマスター・API で画面を描いて撮る）
