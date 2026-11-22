## e2e 確認用ドライバー（デバッグ専用のオートロード `E2EDriver`。最後に登録する）。
##
## 目的: 実サーバーに対して「タイトル → 認証 → login → 規約 → ログインボーナス → ホーム」の通しを、
##       人の操作なしで最後まで動かす（client_design.md 7 節）。動画撮影・通しの確認で使う。録画自体はしない。
## 通常起動への影響: 起動引数に `--e2e` 系が無ければ何もしない（_ready で処理を止める）。
## 製品ビルドへの混入防止（二重）:
##   1. `make release-project` が debug/ を除いた製品用の複製を作り、その project.godot から
##      この autoload の行も外す（元の project.godot は変えない）。
##   2. 万一この処理が製品ビルドに混ざっても、debug ビルドでなければ（OS.is_debug_build() が偽）
##      引数があっても無効にする（is_enabled）。
## 使い方: 引数は Godot の `--` の後ろに付ける（`--` の前でも読む）。
##   godot --path . -- --e2e-case=case1 --e2e-reset
##   godot --headless --path . -- --e2e-case=smoke --e2e-timeout=60
## 引数一覧（`--名前` か `--名前=値`）:
##   --e2e / --e2e=<名前> / --e2e-case=<名前>
##                          ドライバーを有効にする。名前は出力に出すだけのラベル（どれか 1 つが必要）
##   --e2e-reset            起動時にトークンと device_id を消す（新規ユーザーの再現。マスターは消さない）
##   --e2e-fail-login=<種別> login の応答を偽の失敗にする。503（メンテナンス）/ 409 / 429 / network
##   --e2e-fail-count=<回数> 上の失敗を返す回数（既定 1。超えたら本物のサーバーへ送る）
##   --e2e-corrupt-token    規約画面に入る前にアクセストークンを不正値にする（401 → refresh の確認）
##   --e2e-corrupt-refresh  上に加えてリフレッシュトークンも不正値にする（refresh 失敗 → タイトルへ戻る確認）
##   --e2e-no-retry         エラー表示（再試行ボタン）が出たら、押さずに内容を出力して終了する（コード 0）
##   --e2e-shot=<ディレクトリ> 画面ごとにビューポートを PNG に保存する（ヘッドレスでは保存できない）
##   --e2e-dwell=<秒>       画面の操作とエラー表示の再試行の前に止まる秒数（既定 0。録画で画面・エラー文を読めるようにする。
##                          エラーは表示されてから dwell 秒たつまで再試行を押さない。失敗が続いても毎回見える。
##                          429 は dwell と、再試行ボタンが有効になるまでの両方を待つ）
##   --e2e-view-terms       規約画面で、最初の規約の「確認する」を押して閲覧画面を開き、dwell 秒止まる →
##                          本文を数回スクロールして下を見せる → 「閉じる」を押す → 既存どおり同意ボタンへ（動画用）
##   --e2e-home-hold=<秒>   ホームで止まる秒数。HOME_QUIT_DELAY（2 秒）+ --e2e-dwell に加算する（置き換えない。既定 0。
##                          スタミナの回復を画面に出し続けて撮るため。--e2e-dwell は全画面に効くので別にする）
##   --e2e-clock-skew=<秒>  端末時計のずれ（AppContext.debug_clock().skew_seconds）。正なら端末が進んでいる
##                          （サーバー時刻のオフセット補正の確認）
##   --e2e-omit-platform    X-Platform を付けない状態にする（api_client().set_platform("")。99003 の表示の確認）
##   --e2e-frame-probe=<秒> ログインボーナス画面とホームが出てから指定秒のあいだ、描画の指標（処理時間・ドロー呼び出し・
##                          オブジェクト数・ノード数）を毎フレーム集めて `E2E_PROBE:` の行に平均・最大を出す（FrameProbe。
##                          client_design.md 7 節）。記録中は画面の操作（クリック・終了）を待つ。ヘッドレスでは描画統計が
##                          取れないので、行に `render=unavailable(headless)` が付く。--write-movie とは併用しない
##   --e2e-stall-sec=<秒>   同じ画面に居続けて進まないとみなす秒数（既定 30。0 以下で検出しない）。クリック回数の条件と両方
##                          満たしたら、すぐ `E2E_RESULT: FAIL stalled ...`（コード 1）で終わる（StallDetector）
##   --e2e-stall-clicks=<回> 上と合わせて見る、その画面でのクリック回数（既定 5）。dwell で止まっているだけ・再試行を
##                          数回押す確認では失敗にしない。失敗し続ける画面を長く見せる使い方（429・503 を --e2e-fail-count で
##                          約 20 回を超えて返す動画など）は FAIL になるので、--e2e-stall-sec=0 で検出を切る
##   --e2e-timeout=<秒>     この秒数で打ち切る（既定 120。コード 1）
## クリックの送り方: 実際のマウス操作に近づけ、移動 → 押下 → 数フレーム → 解放の順に送る（動画で押下の
##   見た目が出る）。座標はビューポート座標で指定し、ウィンドウ座標へ変換して送る（下の make_* と
##   to_window_position。画面より大きい解像度でウィンドウが縮むと、そのままでは別の場所を押すため）。
## 操作（画面ごと。シーンのパスで判定する）:
##   タイトル: 再試行ボタンが見えて押せるなら押す / 規約: 再試行 → 同意ボタンの順に押す
##   ログインボーナス: 画面中央をクリック / ホーム: 2 秒（+ dwell + home-hold）後にホームの値を出して終了
## 出力: `E2E: ...` の行に経過、最後に `E2E_RESULT: OK ...`（コード 0）、
##       `E2E_RESULT: FAIL stalled scene=… last_api_error=…`
##       （画面が進まない。コード 1。last_api_error は直近の API 失敗。無ければ none）か `E2E_RESULT: TIMEOUT ...`（コード 1）。
##       トークン・秘密鍵・device_id は出さない。
extends Node

## 規約の閲覧の操作の段階（--e2e-view-terms）
enum TermsPhase { OPEN, VIEWING, SCROLLING, CLOSING, DONE }

## 画面が出てから操作するまでの待ち（秒。録画で表示が見えるように）
const ACTION_DELAY := 1.5
## 画面のスクリーンショットを撮るまでの待ち（秒。レイアウトが落ち着いてから）
const SHOT_DELAY := 1.0
## ログインボーナス画面の写真だけ待つ秒数。VIP のスタンプの演出が 1.0 秒ちょうどで終わるので、終わった後に撮る
## （client_design.md 6 節「e2e との関係」・11-1）
const BONUS_SHOT_DELAY := 1.2
## ホームに入ってから終了するまでの秒数
const HOME_QUIT_DELAY := 2.0
## 押下してから解放するまでのフレーム数（Button が押下の見た目になり、動画に映る長さ）
const PRESS_HOLD_FRAMES := 4

const TITLE_RETRY_PATH := "CenterContainer/PanelContainer/VBoxContainer/RetryButton"
const TITLE_STATUS_PATH := "CenterContainer/PanelContainer/VBoxContainer/StatusLabel"
const AGREEMENT_RETRY_PATH := "VBoxContainer/RetryButton"
const AGREEMENT_AGREE_PATH := "VBoxContainer/AgreeAllButton"
const AGREEMENT_STATUS_PATH := "VBoxContainer/StatusLabel"
const AGREEMENT_LIST_PATH := "VBoxContainer/ScrollContainer/AgreementList"
## 規約画面の上に重なる閲覧画面（ノード名と中の部品。terms_viewer.tscn）
const TERMS_VIEWER_NAME := "TermsViewer"
const TERMS_BODY_PATH := "VBoxContainer/BodyLabel"
const TERMS_STATUS_PATH := "VBoxContainer/StatusLabel"
const TERMS_CLOSE_PATH := "VBoxContainer/CloseButton"
## 閲覧画面で本文を進める回数と間隔（秒）、1 回に進める量（表示領域の高さに対する割合）
const TERMS_SCROLL_STEPS := 4
const TERMS_SCROLL_INTERVAL := 0.6
const TERMS_SCROLL_RATIO := 0.6

const FrameProbe := preload("res://debug/frame_probe.gd")
const StallDetector := preload("res://debug/e2e_stall_detector.gd")

## 引数の辞書（キーは "e2e-reset" のように先頭の -- を除いた名前。値の無いものは true）
var _args: Dictionary = {}
var _fail_kind: String = ""
var _fail_remaining: int = 0
var _scene_path: String = ""
## 現在の画面に入ってからの秒数
var _scene_time: float = 0.0
var _elapsed: float = 0.0
var _timeout: float = 120.0
## 各画面で追加で止まる秒数（--e2e-dwell）
var _dwell: float = 0.0
## クリックの送信中（移動 → 押下 → 解放の途中）は次のクリックを始めない
var _is_clicking: bool = false
## このフレームの経過秒（エラー表示の経過時間の更新に使う）
var _error_delta: float = 0.0
## 再試行ボタン（エラー表示）が見えてからの秒数。見えていないときは -1（next_error_time で更新）
var _error_time: float = -1.0
var _quitting: bool = false
## 撮影済みの画面（キー: 画面のパス + 状態）。同じ状態は 1 回だけ撮る
var _shot_keys: Dictionary = {}
var _shot_count: int = 0
## トークンを不正値にしたか。1 回だけにする（毎回壊すと、タイトルへ戻って復旧しても再び壊して無限に戻る）
var _tokens_corrupted: bool = false
## 規約の閲覧の段階と、段階に入ってからの秒数・スクロールした回数
var _terms_phase: TermsPhase = TermsPhase.OPEN
var _terms_time: float = 0.0
var _terms_scrolls: int = 0
## 描画の指標の記録（--e2e-frame-probe）。画面が変わるたびに作り直す。記録済みの画面は _probed_scenes に入れて 1 回だけにする
var _probe: RefCounted = null
var _probed_scenes: Dictionary = {}
## ホームで止まる追加の秒数（--e2e-home-hold）
var _home_hold: float = 0.0
## ホームに入った最初の値（login_stamina・open_stamina の出力用）。入るまでは null
var _home_open_summary: HomeSummary = null
var _home_open_stamina: int = -1
## 「画面が進まない」の検出（_ready で引数から作る）。同じ画面で押し続けても遷移しないと FAIL にする
var _stall: RefCounted = StallDetector.new()


func _ready() -> void:
	_args = _parse_args()
	if not is_enabled(_args, OS.is_debug_build()):
		# 通常起動、または debug ビルドでない（製品ビルド）: 何もしない（_process も止める）
		set_process(false)
		return

	print("E2E: ドライバー有効 case=", _args.get("e2e-case", _args.get("e2e", "")), " args=", _args)
	_timeout = float(_args.get("e2e-timeout", 120))
	_dwell = float(_args.get("e2e-dwell", 0))
	_home_hold = home_hold_seconds(_args)
	_stall = StallDetector.from_args(_args)

	# --- 0. 端末時計のずれ・X-Platform の省略（ホームの確認用） ---
	if _args.has("e2e-clock-skew"):
		AppContext.debug_clock().skew_seconds = clock_skew_seconds(_args)
		print("E2E: 端末時計のずれ ", AppContext.debug_clock().skew_seconds, " 秒")
	if _args.has("e2e-omit-platform"):
		AppContext.api_client().set_platform("")
		print("E2E: X-Platform を付けません")

	# --- 1. 保存の消去（新規ユーザーの再現） ---
	# AppContext は 2 番目のオートロードで、もう組み立て済み。トークンと device_id は保存の窓口から消す
	if _args.has("e2e-reset"):
		var tokens := AppContext.debug_auth_token_repository()
		tokens.save_tokens("", "")
		tokens.reset_device_id()
		print("E2E: トークンと device_id を消しました")

	# --- 2. login の偽の失敗 ---
	if _args.has("e2e-fail-login"):
		_fail_kind = str(_args["e2e-fail-login"])
		_fail_remaining = int(_args.get("e2e-fail-count", 1))
		AppContext.api_client().debug_override = _override_request

	# --- 3. トークンを不正値にする（規約画面がツリーに入る瞬間に差し替える） ---
	if _args.has("e2e-corrupt-token") or _args.has("e2e-corrupt-refresh"):
		get_tree().node_added.connect(_on_node_added)


func _process(delta: float) -> void:
	if _quitting:
		return
	_elapsed += delta
	if _elapsed > _timeout:
		print("E2E_RESULT: TIMEOUT scene=", _scene_path)
		_quit(1)
		return

	var scene := get_tree().current_scene
	if scene == null:
		return
	if scene.scene_file_path != _scene_path:
		_scene_path = scene.scene_file_path
		_scene_time = 0.0
		# frame・t は押印のコマを抜く基準時刻（設計 11-1）。t は録画（Movie Maker は 30fps 固定の delta）の
		# 動画の先頭からの秒と一致する（_elapsed は delta の積算）。ログインボーナス画面の行の t に 0.2・0.5・1.1 秒を
		# 足して ffmpeg -ss を決める（押印前・押印中・着地後）
		print(
			"E2E: 画面 ", _scene_path, " frame=", Engine.get_frames_drawn(), " t=", "%.3f" % _elapsed
		)
	_scene_time += delta
	_error_delta = delta

	# --- 描画の指標の記録（--e2e-frame-probe）。記録中は画面の操作を止める（記録の窓の途中で画面が変わらないように） ---
	if not _run_probe(delta):
		return

	# --- 画面が進まない検出。同じ画面で秒数・クリック回数が閾値に達したら、原因を添えてすぐ失敗にする ---
	var api_client: ApiClient = AppContext.api_client()
	_stall.observe(_scene_path, delta, api_client.error_serial)
	if _stall.is_stalled():
		var error_screen := _screen_error(scene)
		print(_stall.fail_line(api_client.last_error, error_screen[0], error_screen[1]))
		_quit(1)
		return

	match _scene_path:
		SceneRouter.TITLE_SCENE:
			_drive_title(scene)
		SceneRouter.AGREEMENT_SCENE:
			_drive_agreement(scene)
		SceneRouter.LOGIN_BONUS_SCENE:
			_maybe_shot("bonus", BONUS_SHOT_DELAY)
			if _scene_time > ACTION_DELAY + _dwell and not _is_clicking:
				_scene_time = 0.0
				_click_at(get_viewport().get_visible_rect().size / 2.0)
		SceneRouter.HOME_SCENE:
			_record_home_open()
			_maybe_shot("home")
			if _scene_time > HOME_QUIT_DELAY + _dwell + _home_hold:
				print(_home_result_line())
				_quit(0)


# --- 描画の指標（--e2e-frame-probe） ---


## 記録の秒数（--e2e-frame-probe=<秒>）。無い・数値でない・0 以下は 0（記録しない）。
static func frame_probe_seconds(args: Dictionary) -> float:
	var value: Variant = args.get("e2e-frame-probe", null)
	if value is String and value.is_valid_float():
		return maxf(0.0, value.to_float())
	return 0.0


## ログインボーナス画面とホームで、画面が出てから指定秒のあいだ指標を集める。
## 戻り値: 記録中なら false（呼び出し側は画面の操作をしない）、記録しない・済んだなら true。
## 流れ: 画面が出た最初のフレームで FrameProbe を作る → 毎フレーム advance → 指定秒に達したら 1 行出して済みにする。
## 画面ごとに 1 回だけ（_probed_scenes）。ホームはタイマーが動き続けるので、窓の外の値は見ない。
func _run_probe(delta: float) -> bool:
	var seconds := frame_probe_seconds(_args)
	if seconds <= 0.0 or _probed_scenes.has(_scene_path):
		return true
	if _scene_path != SceneRouter.LOGIN_BONUS_SCENE and _scene_path != SceneRouter.HOME_SCENE:
		return true
	if _probe == null:
		_probe = FrameProbe.new(seconds)
	if not _probe.advance(delta):
		return false
	var summary: Dictionary = _probe.result()
	print(
		FrameProbe.format_line(
			_scene_path.get_file().get_basename(),
			_probe.frames(),
			summary,
			FrameProbe.is_headless()
		)
	)
	_probed_scenes[_scene_path] = true
	_probe = null
	# 記録の間に進んだ画面の時間は、操作の待ち（ACTION_DELAY など）に数えず 0 から数え直す
	_scene_time = 0.0
	return true


# --- ホームの値 ---


## ホームに入った最初のフレームで、login 時点の値とホームの最初の表示値を記録する（1 回だけ）。
## 二重加算の確認（open_stamina が login_stamina と一致するか）に使う。
func _record_home_open() -> void:
	if _home_open_summary != null:
		return
	_home_open_summary = AppContext.get_home_summary_use_case().handle()
	var display := AppContext.get_stamina_display_use_case().handle(
		_home_open_summary.stamina_source
	)
	_home_open_stamina = display.current


## 終了時に出す E2E_RESULT の行。画面の文字ではなく、UseCase の結果を出す（目視と照合する）。
func _home_result_line() -> String:
	var summary := AppContext.get_home_summary_use_case().handle()
	var display := AppContext.get_stamina_display_use_case().handle(summary.stamina_source)
	var login_stamina := summary.stamina_source.current
	if _home_open_summary != null:
		login_stamina = _home_open_summary.stamina_source.current
	return format_home_result(
		summary, display, login_stamina, _home_open_stamina, _server_time_offset_text()
	)


## サーバー時刻のオフセット（秒）。Date が読めていなければ "none"。
func _server_time_offset_text() -> String:
	var state := AppContext.debug_player_state()
	if not state.has_server_time:
		return "none"
	return str(state.server_time_offset_seconds)


## --e2e-home-hold の値（秒）。無い・数値でない・負は 0。
static func home_hold_seconds(args: Dictionary) -> float:
	var value: Variant = args.get("e2e-home-hold", null)
	if value is String and value.is_valid_float():
		return maxf(0.0, value.to_float())
	return 0.0


## --e2e-clock-skew の値（秒。負も可）。無い・整数でない（値なしの true を含む）は 0。
static func clock_skew_seconds(args: Dictionary) -> int:
	var value: Variant = args.get("e2e-clock-skew", null)
	if value is String and value.is_valid_int():
		return value.to_int()
	return 0


## E2E_RESULT: OK の行を作る。形（設計 8-2）:
##   player_id=… name=… level=… stamina=現在値/最大値 remain=… coin=… diamond=…
##   login_stamina=… open_stamina=… offset=…
## 最大値が不明なら stamina は「42/--」、残り時間なしなら remain は none、スタミナ行なしは stamina=none。
static func format_home_result(
	summary: HomeSummary,
	display: StaminaDisplay,
	login_stamina: int,
	open_stamina: int,
	offset_text: String
) -> String:
	var stamina := "none"
	if display.is_present:
		var max_text := "--" if display.max_stamina < 0 else str(display.max_stamina)
		stamina = "%d/%s" % [display.current, max_text]
	var remain := "none" if display.seconds_to_next < 0 else str(display.seconds_to_next)
	return (
		(
			"E2E_RESULT: OK player_id=%s name=%s level=%d stamina=%s remain=%s coin=%d diamond=%d"
			+ " login_stamina=%d open_stamina=%d offset=%s"
		)
		% [
			summary.player_id,
			summary.player_name,
			summary.level,
			stamina,
			remain,
			summary.coin,
			summary.diamond_total,
			login_stamina,
			open_stamina,
			offset_text,
		]
	)


# --- 画面ごとの操作 ---


func _drive_title(scene: Node) -> void:
	var retry := scene.get_node_or_null(TITLE_RETRY_PATH) as Button
	var status := scene.get_node_or_null(TITLE_STATUS_PATH) as Label
	if retry != null and retry.visible:
		# エラー表示中。内容を撮ってから、押す（--e2e-no-retry なら内容を出して終了）
		_maybe_shot("title_error_" + str(status.text.hash()))
		if _args.has("e2e-no-retry") and _scene_time > SHOT_DELAY + 0.5:
			print("E2E_RESULT: ERROR_SCREEN title: ", status.text.replace("\n", " / "))
			_quit(0)
			return
	elif status != null:
		_maybe_shot("title")
	_error_time = next_error_time(_error_time, retry != null and retry.visible, _error_delta)
	_click_retry_if_ready(retry)


func _drive_agreement(scene: Node) -> void:
	var retry := scene.get_node_or_null(AGREEMENT_RETRY_PATH) as Button
	var agree := scene.get_node_or_null(AGREEMENT_AGREE_PATH) as Button
	var status := scene.get_node_or_null(AGREEMENT_STATUS_PATH) as Label
	if retry != null and retry.visible:
		_maybe_shot("agreement_error_" + str(status.text.hash()))
		if _args.has("e2e-no-retry") and _scene_time > SHOT_DELAY + 0.5:
			print("E2E_RESULT: ERROR_SCREEN agreement: ", status.text.replace("\n", " / "))
			_quit(0)
			return
	elif agree != null and agree.visible:
		_maybe_shot("agreement")
	# 再試行が出ていればそれを、無ければ（規約の閲覧の操作 → ）同意ボタンを押す
	_error_time = next_error_time(_error_time, retry != null and retry.visible, _error_delta)
	if retry != null and retry.visible:
		_click_retry_if_ready(retry)
	elif not _drive_terms_viewer(scene, agree):
		_click_if_ready(agree)


## --e2e-view-terms の操作。閲覧が終わるまで true（= 同意ボタンはまだ押さない）、終われば false を返す。
## 段階: OPEN（最初の「確認する」を押す）→ VIEWING（本文が出るまで待ち、dwell 秒見せる）→
##       SCROLLING（本文を数回進める）→ CLOSING（「閉じる」を押す）→ DONE。
## 時間は _terms_time（段階ごとに 0 から数える）。クリックは通常の _click_at で、閉じる動作まで本物の操作と同じ経路。
func _drive_terms_viewer(scene: Node, agree: Button) -> bool:
	if not _args.has("e2e-view-terms") or _terms_phase == TermsPhase.DONE:
		return false
	var viewer := scene.get_node_or_null(TERMS_VIEWER_NAME)
	_terms_time += _error_delta
	match _terms_phase:
		TermsPhase.OPEN:
			_terms_open(scene, viewer, agree)
		TermsPhase.VIEWING:
			_terms_view(viewer)
		TermsPhase.SCROLLING:
			_terms_scroll(viewer)
		TermsPhase.CLOSING:
			_terms_close(viewer)
	return _terms_phase != TermsPhase.DONE


## OPEN: 一覧が出てから、最初のカードの「確認する」を押す。閲覧画面が現れたら VIEWING へ。
func _terms_open(scene: Node, viewer: Node, agree: Button) -> void:
	if agree == null or not agree.visible:
		return
	if viewer != null:
		_set_terms_phase(TermsPhase.VIEWING)
		return
	var list := scene.get_node_or_null(AGREEMENT_LIST_PATH)
	if list != null and list.get_child_count() > 0:
		_click_if_ready(list.get_child(0).get_node_or_null("OpenButton") as Button, false)


## VIEWING: 取得が終わる（「読み込み中...」でなくなる）まで数えず、終わったら dwell 秒見せる。
func _terms_view(viewer: Node) -> void:
	var status: Label = null
	if viewer != null:
		status = viewer.get_node_or_null(TERMS_STATUS_PATH) as Label
	if status == null or status.text == "読み込み中...":
		_terms_time = 0.0
		return
	_maybe_shot("terms")
	if _terms_time >= ACTION_DELAY + _dwell:
		_set_terms_phase(TermsPhase.SCROLLING)


## SCROLLING: 一定の間隔で本文を表示領域の一部ずつ進め、最後に dwell 秒見せてから CLOSING へ。
func _terms_scroll(viewer: Node) -> void:
	var body: RichTextLabel = null
	if viewer != null:
		body = viewer.get_node_or_null(TERMS_BODY_PATH) as RichTextLabel
	if body == null:
		_set_terms_phase(TermsPhase.CLOSING)
		return
	if _terms_scrolls >= TERMS_SCROLL_STEPS:
		if _terms_time >= ACTION_DELAY + _dwell:
			_maybe_shot("terms_scrolled")
			_set_terms_phase(TermsPhase.CLOSING)
		return
	if _terms_time >= TERMS_SCROLL_INTERVAL:
		_terms_time = 0.0
		_terms_scrolls += 1
		var bar := body.get_v_scroll_bar()
		bar.value += bar.page * TERMS_SCROLL_RATIO
		print("E2E: 規約を ", _terms_scrolls, " 回スクロール value=", bar.value)


## CLOSING: 「閉じる」を押す（押し直しは 0.5 秒あける）。閲覧画面が消えたら DONE（同意ボタンの操作へ戻る）。
func _terms_close(viewer: Node) -> void:
	if viewer == null:
		_scene_time = 0.0
		_set_terms_phase(TermsPhase.DONE)
		return
	var close := viewer.get_node_or_null(TERMS_CLOSE_PATH) as Button
	if close != null and not _is_clicking and _terms_time >= 0.5:
		_terms_time = 0.0
		_click_at(close.get_global_rect().get_center(), false)


func _set_terms_phase(phase: TermsPhase) -> void:
	_terms_phase = phase
	_terms_time = 0.0
	print("E2E: 規約の閲覧 段階=", TermsPhase.keys()[phase])


## 再試行ボタンを押す。通常の条件（_click_if_ready）に加えて、エラーが表示されてから dwell 秒
## たっていること（動画でエラー文が読める。dwell 0 なら従来どおり即）。押したら計り直す
## （次の失敗の表示も dwell 秒見せるため）。429 のボタン無効中は押せないので、その間も表示される。
func _click_retry_if_ready(retry: Button) -> void:
	if retry == null or _error_time < _dwell:
		return
	var before := _scene_time
	_click_if_ready(retry)
	if _scene_time < before:
		# _click_if_ready が押した（_scene_time を 0 に戻した）
		_error_time = -1.0


## ボタンが見えていて押せるとき、画面に出てから ACTION_DELAY 秒後に中心をクリックする。
## counts_as_progress は _click_at へ渡す（進まない検出に数えるか）。
func _click_if_ready(button: Button, counts_as_progress: bool = true) -> void:
	if button == null or not button.is_visible_in_tree() or button.disabled:
		return
	if _scene_time < ACTION_DELAY + _dwell or _is_clicking:
		return
	_scene_time = 0.0
	_click_at(button.get_global_rect().get_center(), counts_as_progress)


## 画面のエラー表示（タイトル・規約）を [再試行ボタンが見えているか, StatusLabel の文] で返す。
## 対象外の画面は [false, ""]。進まない失敗の行に添えて、API エラーと画面の表示を突き合わせられるようにする。
func _screen_error(scene: Node) -> Array:
	var retry_path := ""
	var status_path := ""
	match _scene_path:
		SceneRouter.TITLE_SCENE:
			retry_path = TITLE_RETRY_PATH
			status_path = TITLE_STATUS_PATH
		SceneRouter.AGREEMENT_SCENE:
			retry_path = AGREEMENT_RETRY_PATH
			status_path = AGREEMENT_STATUS_PATH
		_:
			return [false, ""]
	var retry := scene.get_node_or_null(retry_path) as Button
	var status := scene.get_node_or_null(status_path) as Label
	if retry == null or status == null:
		return [false, ""]
	return [retry.visible, status.text]


## ビューポート座標の位置を左クリックする（移動 → 押下 → PRESS_HOLD_FRAMES フレーム → 解放）。
## 移動を先に送るのは、Control がホバー（マウスの下にある状態）になってから押されるようにするため。
## 押下と解放を同じフレームに送ると、押下の見た目が出ず、環境によって Button が反応しないことがある。
## counts_as_progress は、画面を進めるためのクリックか（進まない検出の回数に数える。規約の閲覧の開閉は数えない）。
func _click_at(viewport_position: Vector2, counts_as_progress: bool = true) -> void:
	_is_clicking = true
	if counts_as_progress:
		_stall.record_click()
	var window_position := to_window_position(
		viewport_position, get_viewport().get_final_transform()
	)
	print("E2E: クリック ", viewport_position)
	Input.parse_input_event(make_motion(window_position))
	await get_tree().process_frame
	Input.parse_input_event(make_button(window_position, true))
	for i in range(PRESS_HOLD_FRAMES):
		await get_tree().process_frame
	Input.parse_input_event(make_button(window_position, false))
	_is_clicking = false


## ドライバーを有効にするか。debug ビルドで、かつ --e2e か --e2e-case の引数があるときだけ真。
## debug ビルドでないときは引数があっても偽（製品ビルドに混ざっても動かさない）。
## OS.is_debug_build() を引数で受けるのは、テストで製品ビルドの場合を再現するため。
static func is_enabled(args: Dictionary, is_debug_build: bool) -> bool:
	if not is_debug_build:
		return false
	return args.has("e2e") or args.has("e2e-case")


## エラー表示（再試行ボタンが見えている状態）の経過秒を 1 フレーム進める。
## 見えていなければ -1（エラーなし）、見え始めたフレームは 0、見え続けていれば delta だけ増やす。
static func next_error_time(current: float, is_error_visible: bool, delta: float) -> float:
	if not is_error_visible:
		return -1.0
	if current < 0.0:
		return 0.0
	return current + delta


## ビューポート座標をウィンドウ座標へ変換する。Input.parse_input_event の位置はウィンドウ座標として扱われ、
## stretch（canvas_items）の逆変換がかかる。ウィンドウが画面に収まらず縮む（例: 1080x1920 が 1832 の高さ
## になる）と、ビューポート座標のまま送ると別の場所（画面の外を含む）を押してしまう。
static func to_window_position(viewport_position: Vector2, final_transform: Transform2D) -> Vector2:
	return final_transform * viewport_position


## マウスの移動イベント（ボタンは押していない）。
static func make_motion(window_position: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = window_position
	event.global_position = window_position
	event.button_mask = 0
	return event


## 左ボタンの押下・解放イベント。押下中は button_mask に左ボタンが立ち、解放では 0 になる（実機と同じ）。
static func make_button(window_position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = window_position
	event.global_position = window_position
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	return event


# --- 偽の失敗・トークンの差し替え ---


## ApiClient.debug_override から呼ばれる。login だけ、指定の回数まで偽の失敗を返す（他は null = 本物を送る）。
func _override_request(_method: String, endpoint: String) -> Variant:
	if endpoint != "/auth/login" or _fail_remaining <= 0:
		return null
	_fail_remaining -= 1
	print("E2E: login を偽の失敗にします kind=", _fail_kind, " 残り=", _fail_remaining)
	match _fail_kind:
		"503":
			var maintenance := ApiResult.make_error(AppError.Kind.MAINTENANCE, 503)
			maintenance.maintenance = {
				"title": "メンテナンス中",
				"message": "ただいまメンテナンス中です",
				"end_at": "2099-01-01 00:00:00",
			}
			return maintenance
		"409":
			return ApiResult.make_error(AppError.Kind.CONFLICT, 409)
		"429":
			var limited := ApiResult.make_error(AppError.Kind.RATE_LIMITED, 429)
			limited.retry_after = 5
			return limited
		_:
			return ApiResult.make_error(AppError.Kind.NETWORK)


## 規約画面がツリーに入った直後（_ready の前）に、トークンを不正値へ差し替える。
func _on_node_added(node: Node) -> void:
	if _tokens_corrupted or node.scene_file_path != SceneRouter.AGREEMENT_SCENE:
		return
	_tokens_corrupted = true
	var tokens := AppContext.debug_auth_token_repository()
	var refresh := tokens.refresh_token()
	if _args.has("e2e-corrupt-refresh"):
		# サーバーが受け付けない 64 桁（refresh の形式）の不正値
		refresh = "x".repeat(64)
	print("E2E: トークンを不正値にします（refresh も: ", _args.has("e2e-corrupt-refresh"), "）")
	tokens.save_tokens("invalid.access.token", refresh)


# --- スクリーンショット ---


## --e2e-shot が指定されていて、画面が落ち着いたら 1 回だけ保存する。
## 同じ状態（key）は 1 回だけ。ヘッドレス（描画なし）では画像が取れないので何もしない。
func _maybe_shot(key: String, delay: float = SHOT_DELAY) -> void:
	if not _args.has("e2e-shot") or _scene_time < delay:
		return
	var shot_key := _scene_path + "#" + key
	if _shot_keys.has(shot_key):
		return
	_shot_keys[shot_key] = true
	var texture := get_viewport().get_texture()
	if texture == null:
		return
	var directory := str(_args["e2e-shot"])
	DirAccess.make_dir_recursive_absolute(directory)
	_shot_count += 1
	var path := "%s/%02d_%s.png" % [directory, _shot_count, key.get_slice("_", 0)]
	var error := texture.get_image().save_png(path)
	print("E2E: スクリーンショット ", path, " (", error, ")")


# --- 引数・終了 ---


## `--` の後ろ（ユーザー引数）と通常の引数から、--e2e で始まる --key[=value] を集める。
func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not arg.begins_with("--e2e"):
			continue
		var body: String = arg.substr(2)
		var separator := body.find("=")
		if separator < 0:
			result[body] = true
		else:
			result[body.substr(0, separator)] = body.substr(separator + 1)
	return result


func _quit(code: int) -> void:
	_quitting = true
	get_tree().quit(code)
