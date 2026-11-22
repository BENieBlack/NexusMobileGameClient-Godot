# アーキテクチャ設計

新しい画面・コンテキスト・API 呼び出しを追加するとき、コンテキストをまたぐ依存を書くとき、既存ファイルを新構成へ移すときに読む。
GDScript の書き方は [coding-standards.md](./coding-standards.md)、サーバー API の通信仕様は [api.md](./api.md)。

クライアントは、サーバー（`NexusMobileGameServer-Laravel`）と同じく**クリーンアーキテクチャと DDD（軽量版）**で作る。層は、モバイルの一般的な Clean Architecture に合わせた **presentation / domain / data の 3 層**。サーバーの規約（[サーバーの CLAUDE.md](../../NexusMobileGameServer-Laravel/CLAUDE.md)、同 `.claude/architecture.md`）と考え方を揃える。

- UseCase は 1 操作 1 つ。結果の型は UseCase ごとに持つ（共用しない）
- 他コンテキストは、相手の公開する契約（domain の公開 UseCase）か共有の EventBus だけを使う。相手の内部を直接参照しない
- 起きたことを伝えるだけなら EventBus（サーバーの Dispatcher に相当）
- 層の呼び名はサーバーに揃えない（サーバーは Laravel の Controller / UseCase / Service / Repository、クライアントは 3 層）。揃えるのは**コンテキスト名**と考え方
- `core/` と `contexts/` は `app/` を参照しない（サーバーの「packages は App を参照しない」に相当）。ただし presentation だけは、オートロード名（`AppContext` / `SceneRouter` / `Toast` / `EventBus`）の参照を許す（2 節）

## 1. 階層

```
res://
├── app/                          # 合成ルート（起動・DI・オートロード）
│   ├── app_context.gd            # 依存の組み立て（Repository 実装を UseCase に渡す）
│   └── scene_router.gd           # 画面遷移（旧 SceneManager）
├── core/                         # ゲーム非依存の基盤（HTTP・設定・Result 等。どこからも使える）
│   ├── domain/                   # result.gd, app_error.gd, event_bus.gd, json_reader.gd 等
│   ├── data/                     # http/（ApiClient・ApiResult）, config/（ApiConfig）, storage/
│   └── presentation/             # toast, loading, エラーダイアログ等の共通 UI。item_icon/（ItemIcon・生成物 ItemIconTable）、safe_area_margins.gd（ホームとログインボーナス画面が共有）
├── master_data/                  # 読み取り専用の参照データ。コンテキストに属さない共有モジュール
│   ├── domain/                   #   mst の読み取りモデル、Repository の契約、同期 UseCase（バージョン確認・更新判定）
│   └── data/                     #   SQLite 接続、差分ダウンロード、ハッシュ管理、mst Repository の実装、version API 呼び出し
├── contexts/                     # サーバーの Domain/{Context} と同じ名前（master_data は含めない）
│   ├── auth/                     # sign_up / sign_in / refresh、トークンの保存、タイトル画面
│   │   ├── presentation/         #   title/（*.tscn と *_presenter.gd）
│   │   ├── domain/               #   entities/, use_cases/, repositories/（契約の基底クラス）
│   │   └── data/                 #   api/（呼び出しと応答の型）, local/（保存）, repositories/（契約の実装）
│   ├── agreement/                # 規約の取得・同意・本文の閲覧、規約画面と閲覧画面
│   ├── login/                    # POST /auth/login、ログインボーナス（カレンダー画面・状態取得・VIP の再受け取り）
│   ├── player/                   # プレイヤーと所持データの読み取りモデル、ホーム画面（domain/services/ に表示専用の計算）
│   └── （今後: gacha / unit / equipment …）
├── tests/                        # contexts/・master_data/・core/ をミラー（unit / integration / e2e）
├── assets/  addons/  data/  docs/
```

各コンテキストの 3 層（presentation / domain / data）は、中身が無い層は作らない。

## 2. 依存ルール

```
presentation ──▶ domain ◀── data（domain の契約を実装する）
```

| ルール | 内容 |
| --- | --- |
| 向き | presentation → domain ← data（data が domain の契約を実装）。**presentation は data を直接参照しない**。domain は presentation・data を参照しない |
| domain | `Node` / `HTTPRequest` / `FileAccess` / シーンに依存しない。`RefCounted` だけで書く。単体テストをエンジン起動なしの軽さで書けること |
| presenter | シーンのスクリプトは API・保存を直接呼ばず、UseCase だけを呼ぶ。UseCase の結果を表示に変える |
| UseCase | 1 操作 1 つ。専用の結果型を返す。Repository は契約（domain）を通して使う |
| master_data | 下の 2-1 を参照。`contexts/*` → `master_data/domain` は読み取りのみ許可 |
| 他コンテキスト | 相手の domain の公開 UseCase、または core の EventBus だけを使う。相手の entities・契約・data は参照しない |
| core | contexts と app を参照しない（`core/presentation` はオートロード名の参照のみ可）。契約（core/domain）を定義し、contexts が実装して AppContext が結ぶ |
| contexts | `res://app/` のパス参照（`preload` / `load`）をしない。**presentation だけは**、オートロード名 `AppContext`（UseCase の受け取り）・`SceneRouter`（遷移）・`Toast` / `EventBus` の参照を許す。**domain / data は app を参照しない**。UseCase の組み立ては AppContext だけが行う |
| API 応答 | `data/api` で型付きオブジェクト（`*_response.gd`）に変換する（腐敗防止層）。null と欠落を同じに扱う規則（D3）はここに閉じ込める。domain に生の Dictionary を渡さない。応答の型・ローカル保存の実装は data に閉じ、domain には契約（基底クラス）だけがある |
| オートロード | 最小に保つ: `AppContext` / `SceneRouter` / `EventBus` / `Toast`。状態はオートロードに置かず、コンテキストの Repository が持つ。**`AppContext._ready` では他のオートロードを呼ばない**（`EventBus` の購読登録のみ。通信・遷移・Toast は呼ばない）。デバッグ専用のオートロードは debug 用の置き場にする（9 節） |

### 2-1. master_data の位置づけ

`master_data/` は `contexts/` と同階層の**共有モジュール**で、コンテキストではない。読み取り専用の参照データ（`mst_*`）と、その同期（バージョン確認・更新判定・差分ダウンロード）だけを持つ。バージョン確認はマスター同期の一部として置き、`contexts/version` は作らない。

| ルール | 内容 |
| --- | --- |
| 構成 | `domain/`（mst の読み取りモデル、Repository の契約、同期 UseCase）と `data/`（SQLite 接続、差分ダウンロード、ハッシュ管理、mst Repository の実装、version API 呼び出し）。`mst_unit` など個別テーブルの Repository・読み取りモデルもここに置く |
| `contexts/*` → `master_data/domain` | **許可（読み取りのみ）**。各コンテキストは `master_data/domain` の公開 UseCase / Repository 契約を使う。`master_data/data` は参照しない |
| `master_data` → `contexts/*` | **禁止** |
| `master_data` → `core` | 使える（`ApiClient`・`ApiConfig`・`Result`・`AppError`・`EventBus`）。`core` は `master_data` に依存しない |
| ビジネスルール | 置かない（参照と同期だけ）。マスターを使った計算・判定は各コンテキストの UseCase が行う |
| ApiClient との循環 | core の契約（token / `master_hash` の供給）と `ApiClient` のシグナルと `EventBus`（`AppContext` が中継。`master_update_required` の受け手は `master_data`）で解く |
| 層 | `master_data` も presentation / domain / data の 3 層の規則（2 節）に従う。UI は持たない |

依存方向は、スクリプトで検査する（9 節）。違反は設計の誤りとして直し、検査を緩めない。

## 3. 層ごとの責務

### core

| 層 | 置くもの |
| --- | --- |
| `core/domain/` | `Result`（成功/失敗の基底）、`AppError`（失敗の種別 `kind`・`error_code`・`message`・`retry_after`・メンテナンス情報）、`EventBus`、`JsonReader`（null と欠落を同一に扱う読み取り）、`Clock`（端末の現在時刻の契約。実装は `core/data/clock/SystemClock`）、`ServerDatetime`（サーバーの時刻文字列 `Y-m-d H:i:s`〔UTC〕を UNIX 秒に読む純粋関数。読めなければ -1）。API クライアントから見た契約（トークンの供給 `ApiAuthProvider`〔refresh の送信は `ApiClient` が持つ〕、`master_hash` の供給 `MasterHashProvider`）もここに置き、実装は contexts が持つ。`ItemIconResolver`（アイコンの絵のキーを決める純粋関数。絵が在るかは述語 `Callable` で受けるので `Texture2D` に依存せず、domain に置ける。D2）もここ。`EventBus` はオートロードで、`class_name` を付けない。依存チェック D2 は、`project.godot` の `[autoload]` に登録済みのオートロードだけ `core/domain` の Node 継承を許すので、登録しておく |
| `core/data/` | `http/ApiClient`（HTTP の窓口。分類・401 の自動 refresh・冪等キー・`X-Master-*`・`X-Platform` ヘッダー）、`http/ApiResult`（通信結果の値）、`http/HttpDate`（`Date` ヘッダーの解釈）、`clock/SystemClock`（端末時計。デバッグ用に `skew_seconds`）、`config/ApiConfig`（ベース URL・配信ホスト・Reverb の接続先と認証 URL。環境変数 `NEXUS_*` → `project.godot` の `[nexus]` → 既定値の順）、`storage/`（ファイル・設定の薄い入れ物） |
| `core/presentation/` | `Toast`（オートロード）、ローディング、エラーダイアログなどの共通 UI。エラー種別ごとの表示文言の共通部分もここ。`item_icon/`（`ItemIcon` = アイコンの共通部品。`ItemIconTable` = 絵の `preload` 表で、`tools/icons/generate_icons.py` が作る生成物。置き場と手順は `docs/ASSETS.md`）、`NumberText`（桁区切り） |

### contexts/{context}

| 層 | 置くもの | 備考 |
| --- | --- | --- |
| `presentation/{screen}/` | `.tscn` と `*_presenter.gd` | UI 制御とシグナル接続だけ。業務の判断はしない。UseCase だけを呼ぶ |
| `domain/entities/` | サーバー状態の読み取りモデル、クライアント固有の状態（セッション・再試行など） | サーバーの項目名に合わせる。基底は `RefCounted`（既定）。`Resource` は下の基準を満たすときだけ |
| `domain/services/` | **表示専用の計算の純粋関数だけ**（状態を持たない静的関数。例: `player/domain/services/` の `StaminaRecovery`・`DiamondTotal`・`CoinAmount`）。採用の条件は 4 節 | 結果をサーバーへ送らず、保持データも書き換えない。`Node` などに依存しない。UseCase が呼ぶ |
| `domain/use_cases/` | `*_use_case.gd` と、必要なときだけ結果の型 `*_result.gd` | 入口は `handle()`。1 操作 1 つ。成否だけなら `Result` をそのまま返す。値を返すときだけ専用の結果型（UseCase ごと。共用しない）。`await` してよい |
| `domain/repositories/` | Repository の**契約**（基底クラス）。テストで偽物に差し替える Repository にだけ作る | メソッドは `push_error("未実装")` を持つ。UseCase はこの型で受ける |
| `data/api/` | API 呼び出しの部品と、項目の多い API 応答の型（`*_response.gd`） | 応答を型付きに変換し、null と欠落（D3）を処理する。`ApiClient` を使う |
| `data/local/` | ローカル保存の部品（ファイル・SQLite・設定） | |
| `data/repositories/` | 契約の実装（`*_api_repository.gd`、`local_*_repository.gd`） | `ApiResult` を `AppError` に直して `Result` で返す |

**`Resource` か `RefCounted` か**: 既定は `RefCounted`。`Resource` は、`.tres` / `ResourceSaver` / `@export` を**実際に使う**ものだけ。
- `Resource`: 上記を使うデータ。entities は、既存 models（現状はすべて `RefCounted`）を `Resource` に変えず、必要が出たものを都度判断する
- `RefCounted`: API 応答の型、メモリのみの読み取りモデル、UseCase の結果、`AppError`、契約、クライアント固有の状態
- どちらでも domain は `Node` / `HTTPRequest` / シーンに依存しない（`Resource` は `RefCounted` の派生）

**軽量化の指針**（3 層は維持する）:
1. 契約（基底クラス）は、テストで偽物に差し替える Repository にだけ作る
2. 成否だけの UseCase は `Result` をそのまま使い、専用の `*_result.gd` を作らない
3. API 応答の型（`*_response.gd`）は、項目の多い login・version だけに作る。他は最小限にする（小さい応答は data の中で値に取り出す）

### app

| ファイル | 責務 |
| --- | --- |
| `app_context.gd`（オートロード） | 起動時に ApiClient・Repository 実装・UseCase を組み立てる唯一の場所。presenter へ UseCase を渡す（`AppContext.login_use_case()` のような取得メソッド。presenter はオートロード名で参照する）。EventBus の購読（受け手）の登録と、`ApiClient` のシグナル（`session_expired` / `master_update_required`）の `EventBus` への中継もここ。`_ready` では他のオートロードを呼ばない |
| `scene_router.gd`（オートロード） | 画面遷移。遷移先はコンテキストの presentation のシーン。presenter が `SceneRouter.goto_*()` で呼ぶ |

## 4. 3 層にした理由と、DDD を軽量にする方針

**3 層（presentation / domain / data）の理由**: モバイルアプリの一般的な Clean Architecture の呼び名に合わせ、読む人・ライブラリ・事例の知識をそのまま使えるようにした。サーバーとは**コンテキスト名を揃え、層の呼び名は揃えない**（サーバーは Laravel の Controller / UseCase / Service / Repository。クライアントには Controller も DB トランザクションも無い）。UseCase は domain に置き、API・保存の実装は data が domain の契約を実装して受け持つ。

**DDD を軽量にする方針**:


サーバーが正で、クライアントはビジネスルールを持たない。重い DDD（豊富な不変条件、値オブジェクトの網羅、集約の設計）を持ち込むと、サーバーの規則を二重に書いて食い違う。次の範囲に絞る。

| 項目 | 方針 |
| --- | --- |
| コンテキスト名 | サーバーの `Domain/{Context}` に揃える。対応が一目で分かり、設計書（サーバー側 `docs/design/`）を引きやすい。**`master_data` は対応する Domain なし**。サーバーの Version（バージョン確認 API）と `mst_*`（各機能のマスター）を、クライアントでは 1 つの共有モジュール `master_data/` にまとめる |
| エンティティ | **サーバー状態の読み取りモデル**が中心。サーバーの項目名・型に合わせ、独自の計算・判定を足さない。計算が要る表示は entities に足さず、下の「ドメインサービス」の例外に置く |
| 集約・不変条件 | **クライアント固有の状態**（画面遷移・再試行の段階・セッション・冪等キー）に限る。例: タイトルの段階（MASTER / AUTH / LOGIN）と失敗した段階の記憶 |
| 値オブジェクト | 必要になった時点で足す。最初から作らない |
| ドメインサービス | **原則採用しない。例外**: 表示専用の計算（F9 の例外。home-player-info の「スタミナの自然回復の表示」と「ダイヤの合算」）の純粋関数に限り、`contexts/{context}/domain/services/` に置いてよい。条件は、状態を持たない静的関数であること・結果をサーバーへ送らず保持データも書き換えないこと・サーバーの式と一致させる単体テストがあること。ルールの判定（サーバーが決めること）は置かない |
| ドメインイベント | 他コンテキストへの通知は `EventBus` のシグナルで足りる。独自のイベント基盤は作らない |

迷ったときは「サーバーが決めることか」で判断する。サーバーが決めることは、クライアントでは表示用の読み取りモデルにとどめる。

## 5. リクエスト（画面操作）の流れの例

タイトル画面での、マスターデータ確認 → 認証 → ログインを通してたどる（設計は `docs/design/title-to-home/client_design.md`）。

```
presenter     auth/presentation/title/title_presenter.gd          段階（MASTER → AUTH → LOGIN）を await で直列に進める
UseCase       master_data/domain/use_cases/check_master_data_use_case.gd
              auth/domain/use_cases/authenticate_use_case.gd
              login/domain/use_cases/login_use_case.gd
契約          auth/domain/repositories/auth_repository.gd          （基底クラス。メソッドは「未実装」）
実装          auth/data/repositories/auth_api_repository.gd       sign_in / sign_up と署名
変換          login/data/api/login_response.gd                    API 応答 → 型付きオブジェクト（項目の多い login のみ。null と欠落をここで処理）
HTTP          core/data/http/api_client.gd               分類・401 の refresh・冪等キー・X-Master-*
保存          auth/data/repositories/local_auth_token_repository.gd
```

1. `title_presenter` が `AppContext` から UseCase を受け取り、段階 1 で `check_master_data_use_case.handle()` を `await` する。失敗でも次へ進み、通知だけ出す
2. 段階 2 で `authenticate_use_case.handle()`。UseCase は `AuthRepository`（契約）の `sign_in()` / `sign_up()` を呼び、10002 / 10004 の切り替えという**操作の規則**を持つ。署名・HTTP は知らない
3. 実装の `auth_api_repository` が `ApiClient.request(...)` を呼ぶ。`ApiClient` は 401 なら refresh して 1 回だけ再送する。refresh に使うトークンは、core が定義した契約を auth の `local_auth_token_repository` が実装して供給する（core は auth を参照しない）
4. `auth_api_repository` が応答からトークンを取り出し（項目が少ないので専用の応答型は作らない）、失敗なら `ApiResult` を `AppError`（種別つき）に直して `Result` で返す
5. UseCase が成功時にトークンを `local_auth_token_repository` に保存し、`Result` を返す
6. 段階 3 で `login_use_case.handle(idempotency_key)`。`login_api_repository` が `POST /auth/login` を送り、`login_response` に変換する。UseCase は、プレイヤー・所持データを `player` コンテキストの公開 UseCase（`apply_login_data_use_case`）に渡し、ログインボーナスの受取結果（`login_bonus_list`）と段の進捗（`login_bonus_calendar`・`vip_login_bonus_calendar`）は自コンテキストの `LoginBonusRepository` に保持する（`replace` / `replace_calendars`。list・receive の応答でも段の進捗を置き換える。`clear` でセッション破棄時に両方消す）
7. presenter は `Result` の成否で、エラー文と「再試行」を出す（`core/presentation` の共通表示を使う）か、オートロード名 `SceneRouter` で次の画面へ進む（presenter が UseCase を受け取る `AppContext`、`SceneRouter` は、presentation にだけ許すオートロード名での参照。2 節）
8. refresh が失敗してセッションを破棄するときは、`ApiClient` が自分のシグナル `session_expired` を出し、`AppContext` がそれを `EventBus.session_expired` に中継する（`core/data` はオートロード名を参照しない。依存チェック A1）。`auth`（トークン）・`player`（所持データ）・`login`（ログインボーナス）が受け手になり、状態を空にする（受け手の登録は `AppContext`）。`master_data` は `session_expired` を受けない（マスターは端末のもので残す）。受けるのは `master_update_required` だけ。`ApiClient` はこれらを直接呼ばない

マスターデータの更新要求（`X-Master-Update-Required`）も同じ形で、`ApiClient` が自分のシグナル `master_update_required` を出し、`AppContext` が `EventBus.master_update_required` に中継して、`master_data` が受ける。

## 6. 命名

| 種類 | ファイル名 | class_name の例 |
| --- | --- | --- |
| UseCase | `*_use_case.gd` | `LoginUseCase` |
| UseCase の結果（値を返すときだけ） | `*_result.gd`（`Result` を継承） | `CheckMasterDataResult` |
| presenter | `*_presenter.gd` | `TitlePresenter` |
| Repository の契約（domain） | `*_repository.gd` | `AuthRepository` |
| Repository の実装（保存） | `local_*_repository.gd` | `LocalAuthTokenRepository` |
| Repository の実装（API） | `*_api_repository.gd` | `AuthApiRepository` |
| API 応答の型（項目の多いものだけ） | `*_response.gd` | `LoginResponse` |
| エンティティ | 名詞（サーバーのモデル名に寄せる） | `Player`, `LoginBonus` |

- 1 ファイル 1 クラス。`class_name` にはファイル名のパスカルケースを付ける
- **例外: オートロードのスクリプト（`EventBus` / `AppContext` / `SceneRouter` / `Toast`）には `class_name` を付けない**。オートロード名と同じ `class_name` は Godot 4 で「Class hides an autoload singleton」エラーになる。呼び出し側はオートロード名で参照する
- 型付き変数を使う（契約の型で受ける: `var _repo: AuthRepository`）
- 識別子は英語、コメントは日本語（[language.md](./language.md)）

## 7. GDScript での契約（interface が無い）

GDScript に interface が無いので、契約は**基底クラス**で表す。

```gdscript
# contexts/auth/domain/repositories/auth_repository.gd
class_name AuthRepository
extends RefCounted

func sign_in(_device_id: String) -> Result:
	push_error("未実装: AuthRepository.sign_in")
	return null
```

- 実装は `extends AuthRepository` でメソッドを上書きする
- UseCase は `AuthRepository` 型の変数で受け、AppContext が実装を渡す。テストでは偽の実装を渡す
- 契約・結果の型は、他の層の `class_name` を `preload` せず**型注釈**で参照する。`preload` どうしの循環を作らない（依存チェックで `preload` の循環も検出する）
- ファイルの移動・改名: Godot 4.4 以降（本プロジェクトは 4.7）は `.gd` の隣に `.gd.uid` がある。**`git mv` で `.gd` と `.gd.uid` を一緒に動かす**。エディタ外で動かしたら、`[autoload]`・`preload`・`load` のパス文字列を grep で直す（`.tscn` の `ext_resource` は uid で解決される）

## 8. 移行（完了）

旧構成（`scenes/` と `scripts/` の managers / services / models / repositories / tests）から新構成への移行は、タイトル〜ホームの機能（`docs/design/title-to-home/client_design.md`）で完了した。**旧構成は削除済み**で、`scenes/` と `scripts/` は存在しない。旧オートロード（`UserDataManager` / `SceneManager` / `AuthService` / `MasterDataManager` / `ToastManager`）も廃止した。

### 旧構成からの行き先（記録）

| 旧 | 新 |
| --- | --- |
| `scripts/services/api_client.gd` / `api_result.gd` | `core/data/http/` |
| `scripts/config/api_config.gd` | `core/data/config/` |
| `scripts/utils/json_reader.gd` | `core/domain/json_reader.gd` |
| `scripts/services/auth_service.gd` | `contexts/auth/domain/use_cases/authenticate_use_case.gd` と `data/`（`repositories/auth_api_repository.gd`、`api/` の署名） |
| `scripts/managers/user_data_manager.gd` | トークンは `contexts/auth/data/repositories/local_auth_token_repository.gd`、所持データは `contexts/player/`、ログインボーナスは `contexts/login/` |
| `scripts/managers/master_data_manager.gd` / `scripts/repositories/mst_*` / `scripts/models/mst/*` | `master_data/`（`Mst*` の読み取りモデルと Repository、同期 UseCase） |
| `scripts/models/sys/*`・`trx/*` | `agreement` の `SysAgreement`、`player` の `PlayerState`（trx 一覧は Dictionary のまま保持）。使われなくなった旧モデルは削除 |
| `scenes/title/` `agreement/` `login_bonus/` `home/` | `contexts/{auth,agreement,login,player}/presentation/<画面>/`（`*.tscn` と `*_presenter.gd`） |
| `scenes/api_test/` | `debug/api_test/`（エクスポート除外） |
| `scripts/managers/scene_manager.gd` | `app/scene_router.gd` |
| `scripts/managers/toast_manager.gd` | `core/presentation/toast.gd` |
| `scripts/tests/*` | `tests/unit/`（`core/` と `contexts/` をミラー） |

### これからのルール

- 新しい機能は最初から新構成で書く。`scenes/` や `scripts/` を作り直さない
- 旧構成のディレクトリ（`scripts/` `scenes/`）が戻ったときは、依存チェックでなく `make check-release`（`tools/prepare_release_project.py`）が、未分類のトップレベルとして失敗にして検出する（依存チェックは対象のディレクトリ以外を読まない。ルール O1 は廃止）
- ファイルを動かす・改名するときは、`.gd` と `.gd.uid` を `git mv` で一緒に動かす（7 節）。動作を変えない移動だけの PR と、機能変更の PR は分ける
- 状態をオートロードに持たせない。持ち主は各コンテキストの Repository 1 つ（2 節）

## 9. debug 用の置き場とツール

- e2e ドライバー・`api_test` など開発専用のものは `debug/`（または `tests/e2e/`）に置き、製品ビルドに入れない。現状、e2e ドライバー（`debug/e2e_driver.gd`）は `project.godot` の `[autoload]` の最後に `E2EDriver` として登録してあり、`--e2e` 系の引数が無ければ何もしない。Godot 4.7 は autoload への機能タグ（debug など）を条件として扱わないので、除外は「製品用の複製」で行う: `make release-project`（`tools/prepare_release_project.py`）が `debug/`・`tests/`・`addons/gdUnit4/`・開発用ファイルを除いた複製を `build/release-project` に作り、その `project.godot` から E2EDriver の autoload と gdUnit4 のプラグインを外す。元の `project.godot` は変えない。複製に除外先への参照や、複製に実在しない `res://` の参照が残っていれば終了コード 1。複製に含めるかは許可リスト方式で、リポジトリのトップレベルと `addons/` 直下は `tools/prepare_release_project.py` の `INCLUDE` / `EXCLUDE`（アドオンは `ADDONS_INCLUDE` / `ADDONS_EXCLUDE`）のどちらかに分類する。新しいトップレベルのディレクトリ・ファイル・アドオンを足したら、ここに分類する（忘れると未分類として `make check-release`（CI）が失敗する）。`make check-release` は複製をヘッドレスで起動し、ロードエラーが無く E2EDriver が動かないことを確かめる（`make check` に含まれる）。多重防御として、ドライバーは debug ビルドでなければ引数があっても無効
- `tests/` と `debug/` は `app/` の参照を許す（e2e は AppContext を通して動かす）。ただし `contexts/` と `core/` からは参照しない

ツール（導入済み。コマンドは [CLAUDE.md](../CLAUDE.md) のコマンド表）:

| 種類 | 内容 | 実行 |
| --- | --- | --- |
| 依存方向チェック | `tools/check_dependencies.py`（Python 標準ライブラリのみ）。`app/ core/ master_data/ contexts/ tests/ debug/` の `*.gd` を対象に、`preload` / `load` / `extends` の `res://` パス、`class_name` の使用、`[autoload]` 名の参照を読み、違反を `パス:行: [ID] 内容` で出して終了コード 1 にする。対象外のトップディレクトリの `*.gd` は検査せず、「検査対象外 N ファイル」として数だけ表示する（`addons` `tools` `reports` `build` は走査しない）。抑止コメントは用意しない。単体テストは `tools/tests/` | `make check-deps` |
| gdlint / gdformat | gdtoolkit 4.5.0（`tools/requirements.txt`、`.venv-tools/` に入れる）。設定は `.gdlintrc`（命名は 6 節と coding-standards.md のとおり snake_case / PascalCase）。対象は新構成のディレクトリだけ | `make lint` / `make format-check` / `make format` |
| テスト | **GdUnit4**（v6.2.3。`addons/gdUnit4/` は git に入れず、`tools/install_gdunit4.sh` が版とコミット SHA を固定して取得する。`make setup-tools` / `make test` が自動で呼ぶ）。Godot 4.7 に対応し、CLI でヘッドレス実行と JUnit XML 出力ができるため採用。`tests/` に `contexts/` `master_data/` `core/` をミラーして置く。domain と UseCase は Repository の偽実装で単体テストを書く。結果は `reports/`（git 管理外） | `make test` / `make test-quiet` |

依存方向チェックのルール ID（2 節・2-1・6 節の規則に対応）:

| ID | 内容 |
| --- | --- |
| D1 | domain は presentation・data を参照しない |
| D2 | domain はエンジン依存（Node 系の継承、`HTTPRequest` / `FileAccess` / `DirAccess` / `PackedScene` / `SceneTree`、`get_tree()`、`.tscn` の `preload` / `load`）を持たない。オートロードのスクリプトは Node 継承が必須なので対象外 |
| P1 | presentation は data を参照しない |
| P2 | presentation が参照できる他コンテキストは `domain/use_cases/` だけ |
| Da1 | data は presentation と他コンテキストを参照しない |
| X1 | コンテキスト間は相手の `domain/use_cases/` だけ参照できる |
| M1 | contexts は `master_data/data` を参照しない（`master_data/domain` だけ可） |
| M2 | `master_data` は contexts と app を参照しない |
| C1 | core は contexts・master_data・app を参照しない |
| A1 | `res://app/` のパス参照は contexts・master_data・core から禁止。オートロード名の参照は presentation（と `core/presentation`、app、tests、debug）だけ |
| L1 | `[autoload]` のスクリプトは `class_name` を宣言しない |
| N1 | 命名: `*_use_case.gd` は `domain/use_cases/`、`*_presenter.gd` は `presentation/`、`*_api_repository.gd` / `local_*_repository.gd` は `data/repositories/`、`*_response.gd` は `data/api/` にだけ置く。`class_name` はファイル名のパスカルケース（オートロード除く） |
| Y1 | `preload` / `extends` のパスの循環 |
| S1 | `core/` `master_data/` `contexts/<ctx>/` のファイルは presentation / domain / data のいずれかの下に置く |
| O1 | 欠番（旧構成の参照を検出するルール。旧構成の削除に伴い廃止。ID は詰めない。8 節） |
| T1 | 本番コード（app / core / master_data / contexts）は `tests/` `debug/` を参照しない |

`app/`・`tests/`・`debug/` は参照の制限を受けない（`tests/` `debug/` は D2 以外の層の規則も対象外）。

## 10. 画面の流れ

| 画面 | シーン | 説明 |
| --- | --- | --- |
| タイトル | `contexts/auth/presentation/title/title.tscn` | version 確認 → 認証 → login |
| 規約 | `contexts/agreement/presentation/agreement/agreement.tscn` | 未同意の規約があるときだけ表示。同意を送る。「確認する」で下の閲覧画面を重ねて開く |
| 規約の閲覧 | `contexts/agreement/presentation/terms_viewer/terms_viewer.tscn` | 規約画面の上に重ねる全画面。規約の URL から HTML を取得し（`FetchAgreementDocumentUseCase`）、`HtmlToBbcode` で BBCode にして `RichTextLabel` に描く。状態は読み込み中 / 表示 / エラー（再試行・ブラウザで開く）。遷移ではなく、閉じると規約画面に戻る |
| ログインボーナス | `contexts/login/presentation/login_bonus/login_bonus.tscn`（login 直後の入口）・`login_bonus_from_home.tscn`（ホームのボタンから。継承シーンで `entry` だけ変える） | カレンダー（通常の段・VIP の段）と今日の報酬を表示する。login 直後は通信しない。ホームから開くときは `POST /login_bonus/list` で状態を取り、VIP の再受け取りボタン（`POST /login_bonus/receive`）を持つ |
| ホーム | `contexts/player/presentation/home/home.tscn` | メインメニュー |
| API テスト | `debug/api_test/api_test.tscn` | デバッグ用（タイトル・ホームからは開けない。直接開く） |

遷移: タイトル → 規約 → ログインボーナス → ホーム。login が成功するまで先へ進まない（詳細は `docs/design/title-to-home/client_design.md`）。

## 11. API 通信と認証（要点）

詳細は [api.md](./api.md) とサーバーの api.md。

- 通信は `core/data/http/ApiClient` に一本化する。HTTP ステータスで失敗を分類し（NETWORK / MAINTENANCE / RATE_LIMITED / CONFLICT / BUSINESS 〔HTTP 299〕/ SESSION_EXPIRED など）、`AppError` として上位に渡す
- 認証は device_id ベース（sign_up は HMAC-SHA256 署名つき、sign_in）。保存トークンの有無で最初に呼ぶ API を決める。振り分けは `auth` の UseCase が持つ
- 401 は `ApiClient` が refresh して 1 回だけ再送する。refresh 失敗は `ApiClient` のシグナル `session_expired`（`AppContext` が `EventBus` へ中継）で知らせる
- 変更を伴う認証付き POST（login・consent・`/login_bonus/receive`）には `X-Unique-Request-Identifier`（冪等キー）を付ける。キーの寿命は「ひとつの操作」で、持つのは presenter（操作の呼び出し元）
- API のベース URL と配信ホストは `ApiConfig` の 1 か所
- Reverb（WebSocket の通知）の接続先も `ApiConfig`（環境変数 `NEXUS_REVERB_HOST` / `_PORT` / `_SCHEME` / `_APP_KEY`、`[nexus]` の `reverb_host` / `reverb_port` / `reverb_scheme` / `reverb_app_key`、既定 `localhost` / `8080` / `ws` / `nexus-local-key`）。チャンネル認証の URL は API のベース URL の origin + `/broadcasting/auth`（設定は無い。Reverb のポートではなく API サーバーにある）。`Toast`（core/presentation）は `ApiConfig`（core/data）を参照できない（P1）ので、`AppContext.reverb_endpoint()` が作る `ReverbEndpoint`（`core/domain`）を presenter が `Toast.connect_to_reverb()` へ渡す
