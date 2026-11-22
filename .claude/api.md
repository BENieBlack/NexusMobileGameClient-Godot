# サーバAPI通信仕様

## 基本情報

- **ベースURL**: `http://localhost:8090/api`（開発環境）。マスターデータの配信ホストは `http://localhost:8091`
  - どちらも `core/data/config/api_config.gd`（`ApiConfig`）の 1 か所。環境変数 `NEXUS_API_BASE_URL` / `NEXUS_MASTER_BASE_URL`、または `project.godot` の `[nexus]` で変える
  - ポート 8080 は API ではなく Reverb（WebSocket。`core/presentation/toast.gd`。この機能の対象外）。接続先は `ApiConfig` が決める: 環境変数 `NEXUS_REVERB_HOST` / `NEXUS_REVERB_PORT` / `NEXUS_REVERB_SCHEME`（`ws` / `wss`。`http` / `https` も可）/ `NEXUS_REVERB_APP_KEY`、または `[nexus]` の `reverb_host` / `reverb_port` / `reverb_scheme` / `reverb_app_key`（既定 `localhost` / `8080` / `ws` / `nexus-local-key`）
  - private / presence チャンネルの認証（`POST /broadcasting/auth`）は Reverb ではなく **API サーバー**（:8090。`/api` の下ではない）にある。URL は API のベース URL の origin + `/broadcasting/auth`（`ApiConfig.broadcasting_auth_url()`）
- **コンテンツタイプ**: `application/json`
- **項目・エラーコードの正**: サーバーの `docs/design/title-to-home/api.md`。このファイルはクライアントの使い方の要点だけを書き、項目は複製しない

### クライアントが使うヘッダー

| ヘッダー | 向き | 内容 |
|---------|------|------|
| `Authorization: Bearer {access_token}` | 送信 | 認証付き API。`ApiClient` が付ける（sign_up / sign_in / version / refresh には付けない） |
| `X-Unique-Request-Identifier` | 送信 | 冪等キー（UUID v4）。**login・consent・`POST /login_bonus/receive` に付ける**（`POST /login_bonus/list` は付けない）。寿命は「ひとつの操作」で、presenter が持つ。通信断・409・503 の再送では同じキー、業務エラー（299）の後は作り直す（client_design.md 3-4） |
| `X-Master-Hash` | 送信 | 端末が持つマスターのハッシュ。空でなければ全リクエストに付ける |
| `X-Platform: Apple` / `Google` | 送信 | 端末の platform。**`ApiClient.request()` を通る全リクエストに `_build_headers()` の 1 か所で付ける**（refresh・`GET /auth/version` を含む）。`download()`（配信ホスト・規約本文）と Toast の `/broadcasting/auth` には付けない。署名には含めない。値は `ApiConfig.platform()`: 環境変数 `NEXUS_PLATFORM` → `[nexus]` の `platform` → OS の既定（iOS → Apple、Android → Google、それ以外 → Apple）。許可値は `Apple` / `Google`（大文字小文字は区別せず正規形に直す）で、不正値は警告して OS の既定に戻す。欠落・不正はサーバーが HTTP 299 / `error_code` 99003 で拒否する（画面は汎用の BUSINESS 表示のまま、`push_error` を 1 回出す）。`set_platform("")` で付けない状態を作れる（e2e 専用） |
| `Accept-Language: ja` | 送信 | 言語。**`request()` を通る全リクエストに `_build_headers()` の 1 か所で付ける**（`X-Platform` と同じ位置。refresh・version を含む）。`download()` と Toast の `/broadcasting/auth` には付けない。署名には含めない。値は `ApiConfig.language()` の固定 `ja`（環境変数・`[nexus]` で上書きしない）。サーバーの `ResolveLanguage` が解釈する（無い・非対応は `ja`）。今の応答は変わらない（言語を使うのはメール一覧など）。マスターの名前の引き（`mst_item__l10n`）も同じ値 |
| `Date` | 受信 | login 応答の `Date` からサーバー時刻とのオフセット（サーバー時刻 − 端末時刻）を作り、`PlayerState` に持つ（スタミナの回復表示の基準。login のたびに更新）。無い・読めないときは端末時計のみ |
| `X-Master-Update-Required: true` | 受信 | HTTP 200 の応答に付く。マスターを裏で更新する（`master_data`）。version API の応答では無視する |
| `X-Client-Timestamp` / `X-Client-Nonce` / `X-Client-Signature` | 送信 | sign_up の署名（下記） |

### 0. バージョン確認（マスターデータの更新要否）

**エンドポイント**: `GET /auth/version?deploy_version={保存済みの deploy_id}`（認証不要。メンテナンス中も通る）

タイトルの最初（認証の前）に `master_data` の `CheckMasterDataUseCase` が呼ぶ。`needs_update` が真なら、差分のテーブルだけ配信ホストからダウンロードして DB を切り替える。ファイルの `url` は `/` 始まりなら配信ホストを前置し、`http` 始まりならそのまま使う。失敗しても止めずに、保存済み（または同梱）のデータで続行する。詳細は [docs/MASTER_DATA.md](../docs/MASTER_DATA.md)。

## 認証フロー

### 1. サインアップ（新規ユーザー）

**エンドポイント**: `POST /auth/sign_up`

**必須ヘッダー（HMAC-SHA256署名）**:
```
Content-Type: application/json
X-Client-Timestamp: {Unixタイムスタンプ（秒）}
X-Client-Nonce: {32文字以上のランダム文字列}
X-Client-Signature: HMAC-SHA256("{timestamp}:{nonce}:{request_body}")
```

**リクエストボディ**:
```json
{
  "device_id": "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx",
  "device_info": {
    "os": "Android",
    "os_version": "14",
    "model": "Pixel 8",
    "app_version": "1.0.0"
  }
}
```

**レスポンス**:
```json
{
  "token": {
    "access_token": "...",
    "refresh_token": "...",
    "expires_in": 3600
  },
  "sys_player": {
    "my_id": "...",
    "name": "...",
    "level": 1,
    "level_exp": 0,
    "vip_point": 0,
    "total_paid_amount": "0.00",
    "last_login_at": null
  },
  "sys_player_device": { ... },
  "sys_player_token": { ... }
}
```

### 2. サインイン（既存ユーザー）

**エンドポイント**: `POST /auth/sign_in`

署名ヘッダー不要。

**リクエストボディ**: サインアップと同じ形式

**レスポンス**: サインアップと同じ形式

### 3. ログイン（ゲームデータ取得）

**エンドポイント**: `POST /auth/login`

**必須ヘッダー**: `Authorization: Bearer {access_token}`、`X-Unique-Request-Identifier`（冪等キー）

認証成功の直後にタイトルが 1 回だけ呼ぶ（`login` の `LoginUseCase`）。成功するまで規約・ログインボーナス・ホームへ進まない。

**レスポンスの項目**（正はサーバーの api.md。例は載せない）:

| 項目 | 保持先 |
|------|--------|
| `sys_player` | `player` の Repository（`my_id` がプレイヤー ID）。`total_paid_amount` は文字列（`"0.00"`）、`vip_point` は整数 |
| `trx_unit_list` / `trx_item_list` / `trx_wallet_list` / `trx_equipment_list` / `trx_stamina_list` | `player` の Repository（要素は Dictionary のまま。キーが無い・null は空配列として扱う。新規ユーザーにも stamina・wallet・item の行が入る） |
| `trx_diamond` | `player` の Repository（`PlayerState.trx_diamond`）。**単数のオブジェクト**（`X-Platform` の platform の 1 行。有償は `paid_amount`。`free_amount` は無い。無償は `trx_item_list` の `free_diamond`）。行が無い・null・型違いは空の辞書。旧キー `trx_diamond_list` は読まない |
| `is_delete`（各行） | 真偽値。移行の間は 0/1 も来うるので `PlayerState.is_row_deleted()` で読む |
| `login_bonus_list` | `login` の Repository。要素は `unique_id` / `type` / `id` / `amount` / `expire_at`（常に null）/ `metadata`（null 可。`grade` があるときだけグレードを表示する） |
| `login_bonus_calendar` / `vip_login_bonus_calendar` | `login` の Repository（`LoginBonusCalendars`。通常の段・VIP の段の**進捗**だけ。日ごとの報酬・周期の日数は応答に無く、マスターから引く）。キーの欠落・null は「その段なし」（旧サーバーの応答は両方 null）。`LoginBonusCalendarsResponse` が変換する |

保持はメモリのみ（永続化しない）。

### 3-2. ログインボーナスの状態取得・再受け取り

項目・エラーコードの正はサーバーの `docs/design/login-bonus-calendar/api.md`（複製しない）。クライアントの設計は [client_design.md](../docs/design/login-bonus-calendar/client_design.md)。呼び出しは `login` の `LoginBonusCalendarApiRepository`（契約 `LoginBonusCalendarRepository`）。

| API | 呼び元 | 冪等キー | 応答の扱い |
|------|------|------|------|
| `POST /login_bonus/list` | ホームのボタンから開いたログインボーナス画面（開くたびに 1 回）。`FetchLoginBonusCalendarsUseCase` | **付けない**（同じキーの応答が再生され、古い状態が返るのを避ける。本文なし） | 通常・VIP の段の進捗で `login` の Repository を置き換える（login 応答と同じ変換） |
| `POST /login_bonus/receive` | VIP の再受け取りボタン。`ReceiveVipLoginBonusUseCase` | **付ける**（本文は `mst_vip_login_bonus_id`。キーは presenter が持つ） | `login_bonus_list`（今回の報酬）・`vip_login_bonus_calendar`・`updated_resources` を読む。所持数は `ApplyUpdatedResourcesUseCase` で反映し、VIP の段を置き換える |

- 再送のキー: 通信断・409・503 は同じキー、業務エラー（299。26001〜26003 など）の後・成功の後は新しいキー（`IdempotencyKey.can_reuse`）。26001〜26003 はコードで分岐せず、画面が `list` で状態を取り直す
- 失敗は `ApiResult.to_app_error()` で `AppError` にする（401 の refresh は `ApiClient`）

### 4. トークンリフレッシュ

**エンドポイント**: `POST /auth/refresh_token`（`ApiClient` が 401 のときに自動で呼ぶ。画面からは呼ばない）

**リクエストボディ**:
```json
{ "refresh_token": "..." }
```

**レスポンス**:
```json
{
  "token": { "access_token": "...", "refresh_token": "...", "expires_in": 3600 }
}
```

### 5. 未同意の規約の取得

**エンドポイント**: `POST /agreement/pending`（認証付き。ボディは空の `{}`、冪等キーは付けない）

規約画面の表示時に呼ぶ（`agreement` の `FetchPendingAgreementsUseCase`）。`agreement_list` が空なら画面を見せずにログインボーナスへ進む。

### 6. 規約への同意

**エンドポイント**: `POST /agreement/consent`（認証付き・冪等キー付き）

ボディは `{"sys_agreement_id": N}`。規約ごとに 1 件ずつ、規約ごとの冪等キーで送る。成功の本文は項目の無い空の配列 `[]` で返ることがあるので、`ApiClient` に `allow_empty_body` を指定して成功扱いにする。24002（同意済み）は成功扱い、24001（規約が存在しない・公開前）は未同意の一覧を取り直す。

## エラーレスポンス

クライアントは **HTTP ステータスで分類**する（`ApiClient` → `AppError.kind`。表示は README の「エラーハンドリング」の表と client_design.md 1-3）。401・429・503（メンテナンス）の本文には `error_code` が無い。`error_code` を見るのは 299 だけ。

### HTTP 299（ビジネスエラー）
```json
{ "error_code": 1001, "message": "エラーメッセージ" }
```
本番では `message` がマスクされることがあるので、画面にはコードを出し、`message` は補助にとどめる。

### HTTP 401 / 409 / 422 / 429

| ステータス | 本文・意味 |
|-----------|-----------|
| 401 | 認証付きはトークン期限切れ → 自動 refresh。認証なし（sign_up）は署名不正（本文の `error` が `INVALID_SIGNATURE` / `REQUEST_EXPIRED` など） |
| 409 | 同じ操作が処理中（`error_code` 40900）。同じ冪等キーで再試行する |
| 422 | 入力の検証エラー |
| 429 | レート制限。本文の `retry_after`（秒）の間は再試行を待たせる |

### HTTP 503（メンテナンス / ロック基盤の不達）
`error_code` が無ければメンテナンス（`title` / `message` / `end_at` を表示する）、`error_code` が 50300 なら `SERVER_BUSY`（「しばらくしてから」）。
```json
{
  "error": "Service Unavailable",
  "title": "メンテナンス中",
  "message": "メンテナンス中です",
  "start_at": "2026-01-01 00:00:00",
  "end_at": "2026-01-01 02:00:00"
}
```

## Resourceタイプ一覧（login_bonus_listのtypeフィールド）

| type | 説明 |
|------|------|
| `gold` | ゴールド（無課金通貨） |
| `stamina` | スタミナ |
| `unit` | ユニット |
| `equipment` | 装備 |
| `item` | アイテム。**無償ダイヤは `type = item`・`id = free_diamond`**（種別 `diamond` は廃止。`id` で見分ける）。表示名は `mst_item`（l10n）から引く（`GetLoginBonusDisplaysUseCase`）。引けなければ `free_diamond` は「無償ダイヤ」、他は「アイテム (ID:…)」 |

## updated_resources と購入・消費の応答（読むのはログインボーナスの再受け取りだけ。ほかは将来の機能の前提）

クライアントが `updated_resources` を読むのは、ログインボーナスの再受け取り（`POST /login_bonus/receive`）だけ。`ApplyUpdatedResourcesUseCase`（player の公開 UseCase）が、ホームが読む 4 種（`trx_item_list`・`trx_wallet_list`・`trx_diamond`・`trx_stamina_list`）だけを取り込み、他のキーは無視する（`trx_item_list`・`trx_wallet_list` は `mst_item_id`、`trx_stamina_list` は `type` を主キーに差し替え）。購入・消費の応答は読まない（呼ぶ API が無い）。読む機能（ガチャ・交換・購入・メール）を作るときの前提:

- `updated_resources` は「キーがあれば上書き、無ければ現状維持」。変更があった方だけ載る（無償だけ使えば `trx_item_list` だけ、有償だけなら `trx_diamond` だけ）
- `trx_diamond` は単数のオブジェクト、`trx_item_list` は配列（型が違う）。`trx_item_list` は変更のあった行だけ載りうる（login の全量とは違う）ので、`mst_item_id` を主キーに差し替える（全置き換えにしない。方式は読む機能の設計で決める）
- 購入応答に `paid_diamond_amount`・`total_*` は無い。残高は `updated_resources` から読む
- 購入は body の `platform` と `X-Platform` に同じ値（`ApiConfig.platform()`）を送る
