# 開発ドキュメント / Development Documentation

このディレクトリには、Godotモバイルゲームクライアントの開発ルールとガイドラインが含まれています。

> **📌 重要**: このプロジェクトでは**日本語**でコミュニケーションを行います。詳細は [language.md](./language.md) を参照してください。

## プロジェクト概要

このプロジェクトは、**モバイルゲームのクライアントアプリ**を提供するGodot 4アプリケーションです。
バックエンドAPIは `NexusMobileGameServer-Laravel` が提供します。

### 主な特徴

- **Godot 4**: GDScriptによる実装
- **デバイスIDベース認証**: HMAC-SHA256署名付きサインアップ、サインイン
- **自動トークンリフレッシュ**: アクセストークン期限切れ時に自動更新
- **クリーンアーキテクチャ（軽量 DDD）**: presentation / domain / data の 3 層とコンテキスト分割。依存方向は `make check-deps` で検査

## ディレクトリ構成

クリーンアーキテクチャ（presentation / domain / data の 3 層）+ 軽量 DDD。詳細は [architecture.md](./architecture.md)。旧構成（`scenes/` と `scripts/`）は削除済みで、すべてこの構成にある。

```
NexusMobileGameClient-Godot/
├── app/                       # 合成ルート
│   ├── app_context.gd         #   依存の組み立て（オートロード）
│   └── scene_router.gd        #   画面遷移（オートロード）
├── core/                      # 共有カーネル
│   ├── domain/                #   Result, AppError, EventBus, JsonReader
│   ├── data/                  #   http/（ApiClient・ApiResult）, config/（ApiConfig）, storage/
│   └── presentation/          #   Toast（オートロード）, エラー文言（ErrorMessages）, エラー表示（ErrorView）
├── master_data/               # 読み取り専用の参照データ（コンテキストに属さない共有モジュール）
│   ├── domain/                #   mst の読み取りモデル、契約、同期 UseCase（バージョン確認・更新判定）
│   └── data/                  #   SQLite、差分ダウンロード、ハッシュ管理、mst Repository、version API
├── contexts/                  # サーバーの Domain/{Context} と同じ名前（master_data は含めない）
│   ├── auth/                  #   認証、タイトル画面
│   ├── agreement/             #   規約の取得・同意・本文の閲覧（HTML → BBCode）、規約画面と閲覧画面
│   ├── login/                 #   login、ログインボーナス画面
│   ├── player/                #   プレイヤー・所持データ、ホーム画面
│   │   └── {presentation, domain(entities, use_cases, repositories), data(api, local, repositories)}
│   └── （今後: gacha / unit / equipment …）
├── tests/                     # core/・master_data/・contexts/ をミラー（GdUnit4。unit / integration）
├── debug/                     # 開発専用（エクスポート除外）: e2e_driver.gd, api_test/, verify_*.gd
├── assets/                    # アセット
├── addons/                    # Godotアドオン
├── data/                      # ローカルデータ（SQLiteなど）
└── docs/                      # ドキュメント（design/<機能>/client_design.md）
```

> 旧構成（`scenes/` と `scripts/`）は 2026-11-12 に削除済み（移行完了。architecture.md 8 節）。

## ドキュメント構成

| ファイル | 説明 |
|---------|------|
| [language.md](./language.md) | **言語設定（日本語で対応）** |
| [architecture.md](./architecture.md) | アーキテクチャ設計（3 層・コンテキスト・依存ルール・命名・移行方針） |
| [coding-standards.md](./coding-standards.md) | コーディング規約 |
| [api.md](./api.md) | サーバAPIとの通信仕様 |
| [implementation-history.md](./implementation-history.md) | **実装履歴** |
| `docs/design/<機能>/client_design.md` | 機能ごとのクライアント設計 |

## 📁 `.opencode/` について

`.opencode` は `.claude` へのシンボリックリンクです。
**ドキュメントの追加・修正は `.claude/` 側だけ行えば両方に反映されます。**

## サーバAPIとの通信フロー

### 起動フロー

```
アプリ起動
  ↓
タイトル画面（段階を直列に進める。失敗した段階から再試行できる）
  ↓ 1. GET /api/auth/version → マスターデータの差分更新（失敗しても保存済みのデータで続行し、通知する）
  ↓ 2. 新規ユーザー: POST /api/auth/sign_up (HMAC-SHA256署名付き)
  ↓    既存ユーザー: POST /api/auth/sign_in（10002 → sign_up、10004 → sign_in に 1 回だけ切り替える）
  ↓    access_token / refresh_token 取得・保存
  ↓ 3. POST /api/auth/login (Bearer認証・冪等キー付き)
  ↓    sys_player・trx 一覧 5 種（unit / item / wallet / equipment / stamina）と有償ダイヤ `trx_diamond`（単数）・login_bonus_list を取得
  ↓    login が成功するまで先へ進まない（失敗はタイトル上のエラー表示と「再試行」）
  ↓
規約画面（POST /api/agreement/pending。未同意が無ければ見えない。同意は POST /api/agreement/consent）
  ↓
ログインボーナス画面（通信しない）→ ホーム画面
```

ホーム画面は通信せず、login の値とローカルのマスターで描く。上から、プレイヤー（名前・ID・レベル）、スタミナ（「現在値 / 最大値」と次の回復までの残り時間）、通貨（コイン・ダイヤの合計）、下にメール・お知らせのボタン（枠だけで押しても何も起きない）と未読バッジの枠。スタミナの回復は login 応答の値を起点にクライアントで表示用に計算する（1 秒ごとに更新し、バックグラウンドから戻ったときはその場で計算し直す。最大値・回復間隔が分からないときは回復を計算しない）。ダイヤは `trx_diamond` の有償・無償と `trx_item_list` の `free_diamond` の合計。設計は `docs/design/home-player-info/client_design.md`。

規約画面の「確認する」は、規約の URL（`sys_agreement.url`。絶対 URL か `/legal/...` のような相対パス。相対パスは API の origin に付ける）から HTML を取得して、アプリ内の閲覧画面（`terms_viewer`）に描く。許可するタグは `h1`〜`h3` `p` `br` `ul` `ol` `li` `strong` `b` `em` `i` `a href`（http / https のみ）`hr`（変換は `html_to_bbcode.gd`）。取得に失敗したら、エラー文と「再試行」「ブラウザで開く」を出す。

規約画面でセッションが無効になった（refresh 失敗）ときは、タイトルへ戻って認証からやり直す。

### トークン管理

- **アクセストークン**: メモリ + ローカルファイル保存、有効期限1時間
- **リフレッシュトークン**: メモリ + ローカルファイル保存、有効期限30日
- **自動リフレッシュ**: `core/data/http/api_client.gd` が HTTP 401 を検知して `POST /api/auth/refresh_token` を自動呼び出し（1 本にまとめ、同じリクエストを 1 回だけ再送）。保存は `contexts/auth/data/repositories/local_auth_token_repository.gd`

### エラーハンドリング

`ApiClient` が HTTP ステータスで分類し、`AppError.kind` として上位へ渡す。表示文言は `core/presentation/error_messages.gd`（設計は client_design.md 1-3）。

| HTTPステータス | `AppError.Kind` | 対応 |
|---------------|-----------------|------|
| 通信失敗 | `NETWORK` | 「通信できませんでした」+ 再試行 |
| 200 | - | 正常処理 |
| 299 | `BUSINESS` | 「エラーが発生しました (コード: N)」+ 再試行（冪等キーは作り直す）。10002・10004・24001・24002 は画面に出さず UseCase が処理 |
| 401 | `SESSION_EXPIRED` ほか | 自動リフレッシュ → 再送。失敗でセッション破棄 → タイトルから再開。sign_up の 401 は署名不正（`SIGNATURE`） |
| 409 | `CONFLICT` | 「処理中です」+ 再試行（同じ冪等キー） |
| 422 | `VALIDATION` | 汎用エラー + 再試行 |
| 429 | `RATE_LIMITED` | `retry_after` 秒の間は再試行ボタンを無効にする |
| 503 | `MAINTENANCE` / `SERVER_BUSY` | メンテナンスはサーバーの title / message / end_at を表示。`error_code` 50300 は「しばらくしてから」 |
| その他の非 2xx / JSON 不正 | `SERVER_ERROR` / `PARSE` | 汎用エラー + 再試行 |

## クイックスタート

### 1. Godotプロジェクトを開く

Godot 4 でこのディレクトリを開いてください。

### 2. サーバを起動

`NexusMobileGameServer-Laravel` を起動してください（サーバー側で `make up`。API は `http://localhost:8090/api`、マスターデータの配信は `http://localhost:8091`）。

### 3. エンドポイント設定

接続先は `core/data/config/api_config.gd`（`ApiConfig`）が 1 か所で決めます。コードを書き換えず、次のどちらかで変えます（上が優先）。

1. 環境変数 `NEXUS_API_BASE_URL` / `NEXUS_MASTER_BASE_URL`
2. `project.godot` の `[nexus]` セクション（`api_base_url` / `master_base_url`）

Reverb（通知の WebSocket）の接続先も同じ順で決まります（環境変数 `NEXUS_REVERB_HOST` / `NEXUS_REVERB_PORT` / `NEXUS_REVERB_SCHEME` / `NEXUS_REVERB_APP_KEY`、`[nexus]` の `reverb_host` / `reverb_port` / `reverb_scheme` / `reverb_app_key`）。`X-Platform` の値も同じ順で決まります（環境変数 `NEXUS_PLATFORM`、`[nexus]` の `platform`、OS の既定。許可値は `Apple` / `Google`）。チャンネル認証の URL は API のベース URL から決まります。アプリキーの既定値（`nexus-local-key`）はローカル開発用なので、製品や他環境では `NEXUS_REVERB_APP_KEY` か `[nexus]` の `reverb_app_key` で上書きします。

### 4. 通しの動作確認（e2e ドライバー）

人の操作なしで「タイトル → 認証 → login → 規約 → ログインボーナス → ホーム」を最後まで動かせます（`debug/e2e_driver.gd`。`--e2e` 系の引数が無ければ何もしません）。

```bash
godot --path . -- --e2e-case=smoke --e2e-reset            # 新規ユーザー（トークンと device_id を消す）
godot --path . -- --e2e-case=smoke --e2e-fail-login=503 --e2e-no-retry   # login だけメンテナンスにして、エラー表示で止める
```

規約の閲覧画面まで撮るときは `--e2e-view-terms` を付ける（最初の規約の「確認する」→ 閲覧 → スクロール → 「閉じる」→ 同意）。サーバーの規約 URL が配信されていないと、閲覧画面はエラー表示になる。取得・変換・描画だけを確かめるなら `godot --path . --resolution 540x960 res://debug/verify_terms_viewer.tscn -- <画像の出力先>`（認証なし）。

ホームの確認には `--e2e-home-hold=<秒>`（ホームに留まる秒数を足す）、`--e2e-clock-skew=<秒>`（端末時計のずれを作る）、`--e2e-omit-platform`（`X-Platform` を付けない）が使える。終了時の `E2E_RESULT: OK` にホームの値（スタミナ・コイン・ダイヤ・`login_stamina`・`open_stamina`・`offset`）が出る。

ログインボーナスの確認には次の引数が使える（詳細は `debug/e2e_driver.gd` の冒頭）。`--e2e-open-login-bonus`（ホームのボタンから画面を開く）、`--e2e-receive=home|login`（指定した入口で受け取りボタンを押す。`home` は `--e2e-open-login-bonus` と併せる）、`--e2e-stale-receive`（押す直前に先に受け取って業務エラーを再現）、`--e2e-fail-bonus=<種別>`（`/login_bonus/*` の偽の失敗。`network` / `503` / `409` / `429`。回数は `--e2e-fail-count`）。

進まない画面は `--e2e-stall-sec=<秒>`（既定 30。0 以下で検出しない）と `--e2e-stall-clicks=<回>`（既定 5）の両方を満たすと、`E2E_RESULT: FAIL stalled scene=… last_api_error=…`（コード 1）で早く終わる（`debug/e2e_stall_detector.gd`）。`last_api_error` は直近の API 失敗で、無ければ `none`。失敗が続く画面を長く撮るときは `--e2e-stall-sec=0`。読み方と録画の手順は Nexus の `docs/workflow/recording.md`。

引数の一覧は `debug/e2e_driver.gd` の冒頭。sign_up は IP あたり 10 回/時間の上限があるので、`--e2e-reset` を繰り返さない。ボタンのクリックはヘッドレス（`--headless`）では効かないので、再試行ボタンの操作を含むケースは通常起動で動かす。

## 重要な設計原則

### 1. シーンとロジックの分離

- シーン（`.tscn`）はUI構造のみ
- presenter（`*_presenter.gd`）はUI制御とシグナル接続のみ。UseCase だけを呼び、API・保存を直接呼ばない
- 業務の流れは `contexts/<名前>/domain/use_cases/`、通信・保存は `data/` に実装（層の依存方向は architecture.md 2 節）

### 2. グローバルマネージャー（オートロード）

オートロードは最小に保つ（順序はこのとおり。architecture.md 2 節）。状態はオートロードに置かず、各コンテキストの Repository が持つ。

- `EventBus`: コンテキスト間のシグナル（`session_expired` / `master_update_required`）
- `AppContext`: 依存の組み立て。presenter は `AppContext.login_use_case()` のように UseCase を受け取る
- `SceneRouter`: 画面遷移（`SceneRouter.goto_home()` など）
- `Toast`: トースト表示と、リアルタイム通知（Reverb）への接続

開発専用に `E2EDriver`（`debug/`）が最後に登録されている（製品ビルドでは外す）。

### 3. サーバAPIのレスポンス形式

サーバは以下の形式でレスポンスを返します：

```json
// sign_up / sign_in
{
  "token": { "access_token": "...", "refresh_token": "...", "expires_in": 3600 },
  "sys_player": { "my_id": "...", "name": "...", "level": 1, ... },
  "sys_player_device": { ... },
  "sys_player_token": { ... }
}

// auth/login
{
  "sys_player": { ... },
  "trx_unit_list": [...],
  "trx_item_list": [...],
  "trx_wallet_list": [...],
  "trx_equipment_list": [...],
  "trx_stamina_list": [...],
  "trx_diamond": { "platform": "Apple", "paid_amount": 0, ... },  // 単数（有償のみ。無償は trx_item_list の free_diamond）。行が無ければ null
  "login_bonus_list": [
    { "unique_id": "...", "type": "gold", "id": "gold", "amount": 100, "expire_at": null, "metadata": null }
  ]
}
// 項目の詳細はサーバーの docs/design/title-to-home/api.md（正）。一覧の要素は Dictionary のまま保持する
```

## 更新履歴

| 日付 | バージョン | 変更内容 |
|------|-----------|---------|
| 2026-09-02 | 0.1.0 | 初期ドキュメント作成 |
| 2026-11-12 | 0.2.0 | タイトル〜ホームの新構成への移行完了に合わせ、概要・構成・通信フロー・エラー・クイックスタート・オートロードを更新 |
