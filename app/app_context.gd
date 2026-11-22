# gdlint: disable=max-public-methods
## 依存の組み立て（合成ルート。architecture.md 3 節 app、client_design.md 2-1）。
##
## 目的: ApiClient・各 Repository の実装・UseCase を生成して結ぶ唯一の場所。presenter（第 3 段）は
##       オートロード名 AppContext の取得メソッド（login_use_case() など）で UseCase だけを受け取る。
##       また、ApiClient の 2 つのシグナルを EventBus へ中継し、EventBus の受け手を登録する。
## 注意:
##   - 先頭の gdlint の指定は公開メソッド数の上限（20）を外すもの。合成ルートは UseCase の取得メソッドが増えるのが本来の姿
##   - オートロード用のスクリプトなので class_name を付けない（付けるとオートロード名と衝突する。依存チェック L1）。
##     project.godot の [autoload] に 2 番目（EventBus の次）で登録している。テストは
##     load("res://app/app_context.gd").new() で別の Node として生成し、add_child する
##     （storage_root を差し替えて実機の user:// に触れない）。
##   - _ready では他のオートロードを呼ばない。EventBus は購読の登録（connect）と、ApiClient のシグナルを
##     EventBus のシグナルへつなぐことだけ。通信・遷移・Toast は呼ばない（起動順序に依存しないため）
## 組み立ての流れ（_ready）:
##   1. 保存の窓口を作る（トークン = LocalAuthTokenRepository、マスター = LocalMasterDataRepository）
##   2. ApiClient を 1 つ作って add_child し、configure(トークンの供給元, マスターハッシュの供給元) する
##      （マスターの保存実装は MasterHashProvider を兼ねるので、同じ 1 つを渡す = 状態の持ち主は 1 つ）
##   3. API Repository・メモリの Repository・UseCase を作る
##   4. ApiClient のシグナルを EventBus へ中継し、EventBus の受け手を登録する（下記）
## 受け手（architecture.md 5 節 8）:
##   - EventBus.session_expired        → auth（トークン）・player（所持データ）・login（ログインボーナス）を空にする。
##                                        master_data は受けない（マスターは端末のもので、アカウントに依存しない）
##   - EventBus.master_update_required → master_data が CheckMasterDataUseCase を裏で呼ぶ（待たない。
##                                        実行中の重複は UseCase が 1 本にまとめる）
## テスト: storage_root を add_child の前に差し替えると、保存先（トークン・device_id・マスター）を
##   実機の user:// から外せる。
extends Node

## 保存先のルート。既定は実機の user://。add_child の前に差し替えられる（テスト・検証用）
var storage_root: String = "user://"

var _api_client: ApiClient

# --- master_data ---
var _master_database: MasterDatabase
var _master_storage: LocalMasterDataRepository
var _check_master_data_use_case: CheckMasterDataUseCase
var _mst_unit_repository: MstUnitRepository
var _mst_equipment_repository: MstEquipmentRepository
var _mst_gacha_repository: MstGachaRepository
var _mst_player_level_repository: MstPlayerLevelRepository
var _mst_config_repository: MstConfigRepository
var _mst_item_repository: MstItemRepository
var _mst_login_bonus_repository: MstLoginBonusRepository
var _mst_vip_login_bonus_repository: MstVipLoginBonusRepository

# --- core ---
var _clock: SystemClock

# --- auth ---
var _auth_token_repository: LocalAuthTokenRepository
var _authenticate_use_case: AuthenticateUseCase
var _clear_auth_session_use_case: ClearAuthSessionUseCase
var _get_access_token_use_case: GetAccessTokenUseCase

# --- player ---
var _player_repository: PlayerRepository
var _apply_login_data_use_case: ApplyLoginDataUseCase
var _get_player_id_use_case: GetPlayerIdUseCase
var _get_home_summary_use_case: GetHomeSummaryUseCase
var _get_stamina_display_use_case: GetStaminaDisplayUseCase
var _apply_updated_resources_use_case: ApplyUpdatedResourcesUseCase

# --- login ---
var _login_bonus_repository: LoginBonusRepository
var _login_use_case: LoginUseCase
var _get_login_bonuses_use_case: GetLoginBonusesUseCase
var _get_login_bonus_displays_use_case: GetLoginBonusDisplaysUseCase
var _prepare_login_bonus_master_use_case: PrepareLoginBonusMasterUseCase
var _fetch_login_bonus_calendars_use_case: FetchLoginBonusCalendarsUseCase
var _receive_vip_login_bonus_use_case: ReceiveVipLoginBonusUseCase
var _get_login_bonus_screen_use_case: GetLoginBonusScreenUseCase

# --- agreement ---
var _fetch_pending_agreements_use_case: FetchPendingAgreementsUseCase
var _consent_agreement_use_case: ConsentAgreementUseCase
var _fetch_agreement_document_use_case: FetchAgreementDocumentUseCase


func _ready() -> void:
	_build()
	_register_event_bus()


func _exit_tree() -> void:
	# EventBus はオートロードで長生きするので、受け手の登録を外す（解放済みの自分を呼ばせない）
	if EventBus.session_expired.is_connected(_on_session_expired):
		EventBus.session_expired.disconnect(_on_session_expired)
	if EventBus.master_update_required.is_connected(_on_master_update_required):
		EventBus.master_update_required.disconnect(_on_master_update_required)
	# SQLite の接続を閉じる（開いたままにしない）
	if _master_database != null:
		_master_database.close_all()


# --- 取得メソッド（presenter が UseCase を受け取る窓口） ---


func api_client() -> ApiClient:
	return _api_client


func check_master_data_use_case() -> CheckMasterDataUseCase:
	return _check_master_data_use_case


func authenticate_use_case() -> AuthenticateUseCase:
	return _authenticate_use_case


func clear_auth_session_use_case() -> ClearAuthSessionUseCase:
	return _clear_auth_session_use_case


func get_access_token_use_case() -> GetAccessTokenUseCase:
	return _get_access_token_use_case


## Reverb の接続先と認証先（Toast へ渡す。ApiConfig の設定から呼ぶたびに作る。通信はしない）。
## core/presentation の Toast は ApiConfig（core/data）を参照できないので、presenter がここから受け取って渡す。
func reverb_endpoint() -> ReverbEndpoint:
	return ApiConfig.reverb_endpoint()


func apply_login_data_use_case() -> ApplyLoginDataUseCase:
	return _apply_login_data_use_case


func get_player_id_use_case() -> GetPlayerIdUseCase:
	return _get_player_id_use_case


## ホームの表示値の束を作る（ホームを開いたときとマスター更新時）。
func get_home_summary_use_case() -> GetHomeSummaryUseCase:
	return _get_home_summary_use_case


## スタミナの表示値を now 時点で求める（tick・復帰のたび）。
func get_stamina_display_use_case() -> GetStaminaDisplayUseCase:
	return _get_stamina_display_use_case


func get_login_bonuses_use_case() -> GetLoginBonusesUseCase:
	return _get_login_bonuses_use_case


## ログインボーナス画面の表示用の値（受取 + mst_item の名前）。
func get_login_bonus_displays_use_case() -> GetLoginBonusDisplaysUseCase:
	return _get_login_bonus_displays_use_case


## ログインボーナスの進捗（login 応答・list 応答）のメモリ保持。ログインボーナス画面が、段のマスターを
## 引くための進捗を読むのに使う（calendars()）。
func login_bonus_repository() -> LoginBonusRepository:
	return _login_bonus_repository


func login_use_case() -> LoginUseCase:
	return _login_use_case


## 画面を出す前に、段の ID をマスターから引く（引けなければ 1 回だけマスターを取り直す。2-4）。
func prepare_login_bonus_master_use_case() -> PrepareLoginBonusMasterUseCase:
	return _prepare_login_bonus_master_use_case


## POST /login_bonus/list で段の進捗を取り直す（ホームから開くとき・再受け取りの業務エラーの後）。
func fetch_login_bonus_calendars_use_case() -> FetchLoginBonusCalendarsUseCase:
	return _fetch_login_bonus_calendars_use_case


## POST /login_bonus/receive（VIP の再受け取り）。
func receive_vip_login_bonus_use_case() -> ReceiveVipLoginBonusUseCase:
	return _receive_vip_login_bonus_use_case


## ログインボーナス画面の表示モデル（LoginBonusScreen）を作る。
func get_login_bonus_screen_use_case() -> GetLoginBonusScreenUseCase:
	return _get_login_bonus_screen_use_case


## updated_resources をホームの所持数の保持へ取り込む（player の公開 UseCase）。
func apply_updated_resources_use_case() -> ApplyUpdatedResourcesUseCase:
	return _apply_updated_resources_use_case


func fetch_pending_agreements_use_case() -> FetchPendingAgreementsUseCase:
	return _fetch_pending_agreements_use_case


func consent_agreement_use_case() -> ConsentAgreementUseCase:
	return _consent_agreement_use_case


func fetch_agreement_document_use_case() -> FetchAgreementDocumentUseCase:
	return _fetch_agreement_document_use_case


# --- デバッグ・e2e 用（製品の画面は使わない。debug/ だけが呼ぶ） ---


## トークンと device_id の保存の窓口。e2e ドライバー（--e2e-reset / --e2e-corrupt-token）と
## api_test が、保存を直接消す・書き換えるために使う。UseCase に載せないのは、製品の操作ではないため。
func debug_auth_token_repository() -> LocalAuthTokenRepository:
	return _auth_token_repository


## 端末の時計（SystemClock）。e2e の --e2e-clock-skew が skew_seconds を設定して、端末時計のずれを作る。
## 製品の画面は使わない（時刻は UseCase が Clock の契約で受け取る）。
func debug_clock() -> SystemClock:
	return _clock


## 保持中のプレイヤー状態（サーバー時刻のオフセットなどを e2e の出力に出すため。読み取り専用で使う）。
## 製品の画面は使わない（値は UseCase が返す）。
func debug_player_state() -> PlayerState:
	return _player_repository.current()


# --- mst の Repository（master_data。読み取りのみ。各コンテキストの UseCase が使う） ---


func mst_unit_repository() -> MstUnitRepository:
	return _mst_unit_repository


func mst_equipment_repository() -> MstEquipmentRepository:
	return _mst_equipment_repository


func mst_gacha_repository() -> MstGachaRepository:
	return _mst_gacha_repository


## スタミナの最大値（レベル → max_stamina）。配信に無いときは get_by_level が null を返す。
func mst_player_level_repository() -> MstPlayerLevelRepository:
	return _mst_player_level_repository


## 設定値（stamina_recovery_interval_seconds など）。配信に無いときは get_by_id が null を返す。
func mst_config_repository() -> MstConfigRepository:
	return _mst_config_repository


## アイテムの表示名（mst_item と l10n）。配信に無い・名前が無いときは get_by_id が null か name 空を返す。
func mst_item_repository() -> MstItemRepository:
	return _mst_item_repository


# --- 組み立て ---


## 依存を作って結ぶ。_ready から 1 回だけ呼ぶ。
func _build() -> void:
	var root := storage_root if storage_root.ends_with("/") else storage_root + "/"

	# --- 1. 保存の窓口 ---
	_auth_token_repository = LocalAuthTokenRepository.new(root)
	_master_database = MasterDatabase.new()
	_master_storage = LocalMasterDataRepository.new(
		_master_database, root + "master/", root + "master_state.json"
	)
	# 保存済みの更新 DB（無ければ同梱 DB）を開く。開けなくても起動は続ける（マスターを使う画面だけ空になる）
	if not _master_storage.initialize():
		push_warning("マスターデータの DB を開けませんでした")

	_clock = SystemClock.new()

	# --- 2. ApiClient ---
	_api_client = ApiClient.new()
	add_child(_api_client)
	_api_client.configure(_auth_token_repository, _master_storage)

	# --- 3. Repository と UseCase ---
	# master_data
	var master_remote := MasterDataApiRepository.new(_api_client)
	_check_master_data_use_case = CheckMasterDataUseCase.new(master_remote, _master_storage)
	_mst_unit_repository = LocalMstUnitRepository.new(_master_database)
	_mst_equipment_repository = LocalMstEquipmentRepository.new(_master_database)
	_mst_gacha_repository = LocalMstGachaRepository.new(_master_database)
	_mst_player_level_repository = LocalMstPlayerLevelRepository.new(_master_database)
	_mst_config_repository = LocalMstConfigRepository.new(_master_database)
	# 名前の言語は API の Accept-Language と同じ 1 か所の値（ApiConfig.language()）
	_mst_item_repository = LocalMstItemRepository.new(_master_database, ApiConfig.language())
	# ログインボーナスのマスターは、テーブルごとに別の SQLite（配信があるときだけ入る任意テーブル）
	_mst_login_bonus_repository = LocalMstLoginBonusRepository.new(_master_database)
	_mst_vip_login_bonus_repository = LocalMstVipLoginBonusRepository.new(_master_database)
	# auth
	var auth_repository := AuthApiRepository.new(_api_client, _auth_token_repository)
	_authenticate_use_case = AuthenticateUseCase.new(auth_repository, _auth_token_repository)
	_clear_auth_session_use_case = ClearAuthSessionUseCase.new(_auth_token_repository)
	_get_access_token_use_case = GetAccessTokenUseCase.new(_auth_token_repository)
	# player
	_player_repository = LocalPlayerRepository.new()
	_apply_login_data_use_case = ApplyLoginDataUseCase.new(_player_repository)
	_get_player_id_use_case = GetPlayerIdUseCase.new(_player_repository)
	_get_home_summary_use_case = GetHomeSummaryUseCase.new(
		_player_repository, _mst_player_level_repository, _mst_config_repository
	)
	_get_stamina_display_use_case = GetStaminaDisplayUseCase.new(_player_repository, _clock)
	_apply_updated_resources_use_case = ApplyUpdatedResourcesUseCase.new(_player_repository)
	# login
	_login_bonus_repository = LocalLoginBonusRepository.new()
	_login_use_case = LoginUseCase.new(
		LoginApiRepository.new(_api_client, _clock),
		_login_bonus_repository,
		_apply_login_data_use_case
	)
	_get_login_bonuses_use_case = GetLoginBonusesUseCase.new(_login_bonus_repository)
	_get_login_bonus_displays_use_case = GetLoginBonusDisplaysUseCase.new(
		_get_login_bonuses_use_case, _mst_item_repository
	)
	var calendar_repository := LoginBonusCalendarApiRepository.new(_api_client)
	_prepare_login_bonus_master_use_case = PrepareLoginBonusMasterUseCase.new(
		LoginBonusStageMasterReader.new(
			_mst_login_bonus_repository, _mst_vip_login_bonus_repository
		),
		_check_master_data_use_case
	)
	_fetch_login_bonus_calendars_use_case = FetchLoginBonusCalendarsUseCase.new(
		calendar_repository, _login_bonus_repository
	)
	_receive_vip_login_bonus_use_case = ReceiveVipLoginBonusUseCase.new(
		calendar_repository, _login_bonus_repository, _apply_updated_resources_use_case
	)
	_get_login_bonus_screen_use_case = GetLoginBonusScreenUseCase.new(
		_login_bonus_repository, _get_login_bonus_displays_use_case
	)
	# agreement
	var agreement_repository := AgreementApiRepository.new(_api_client)
	_fetch_pending_agreements_use_case = FetchPendingAgreementsUseCase.new(agreement_repository)
	_consent_agreement_use_case = ConsentAgreementUseCase.new(agreement_repository)
	_fetch_agreement_document_use_case = FetchAgreementDocumentUseCase.new(
		AgreementDocumentHttpRepository.new(_api_client)
	)


## ApiClient のシグナルを EventBus へ中継し、EventBus の受け手を登録する。
## 中継する理由: core/data（ApiClient）はオートロード名を参照できない（依存チェック A1）ので、
## ApiClient は自分のシグナルを出すだけにし、EventBus に載せ替えるのはここ（app）の役目。
func _register_event_bus() -> void:
	_api_client.session_expired.connect(EventBus.session_expired.emit)
	_api_client.master_update_required.connect(EventBus.master_update_required.emit)
	EventBus.session_expired.connect(_on_session_expired)
	EventBus.master_update_required.connect(_on_master_update_required)


## セッションが無効になった。トークン・所持データ・ログインボーナスを空にする。
## master_hash と deploy_id（master_data の持ち物）は消さない。
func _on_session_expired() -> void:
	_clear_auth_session_use_case.handle()
	_player_repository.clear()
	_login_bonus_repository.clear()


## サーバーのマスターが更新された。master_data の同期を裏で 1 本だけ走らせる（待たない）。
## 実行中の重複は CheckMasterDataUseCase が IN_PROGRESS で断り、終了後に 1 回だけ再実行する。
func _on_master_update_required() -> void:
	_check_master_data_use_case.handle()
