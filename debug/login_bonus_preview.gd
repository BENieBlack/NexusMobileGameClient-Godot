## ログインボーナス画面の単体プレビュー（debug 専用。製品の複製には入らない。client_design.md 11-3・V3b の目視確認）。
##
## 目的: マスターの配信ファイルやサーバーが無い環境でも、カレンダー画面を実際に描いて画像に撮る。
##       本物の LoginBonusPresenter・GetLoginBonusScreenUseCase を使い、差し替えるのは「マスターを引く窓口」
##       （偽の PrepareLoginBonusMasterUseCase）と mst_item の名前の引き（偽の MstItemRepository）だけ。
## 使い方:
##   godot --path . res://debug/login_bonus_preview.tscn -- --preview=<名前> [--shot=<PNG>]
##   名前: normal（通常だけ・3 日目）/ both（通常＋VIP・報酬 2 行）/ text（周期 9 日 = 文字の画面）/
##         max（通常 7＋VIP 7＋報酬 5 行 = 最大構成）/ received（再表示。押印済み・受け取り済みの旨）
##   --shot=<パス>  アニメーションが終わった頃に画面を PNG に保存して終了（ヘッドレスでは描画されず撮れない）
##   --probe=<秒>   画面が出てから指定秒、描画の指標（FrameProbe。7 節）を集めて `E2E_PROBE:` の行を出し終了する
##                  （ウィンドウありで測る。スタンプのアニメーション中を含む。V2 の測り方に揃える）
##   --no-safe      iPhone X 相当の安全領域（上 127・下 98。ビューポート単位）を足さない
## 注意: 本番のコードから参照されない（T1）。ホームへの遷移は偽のルーター（何もしない）。

extends Control

## 撮影までの待ち（秒）。VIP のスタンプが終わる 1.0 秒より後
const SHOT_DELAY := 1.4
## iPhone X の安全領域（設計 1-4 の見積り。ビューポート単位）
const FrameProbe := preload("res://debug/frame_probe.gd")
const IPHONE_X_SAFE := {"left": 0.0, "top": 127.0, "right": 0.0, "bottom": 98.0}
const PRESENTER_SCENE := "res://contexts/login/presentation/login_bonus/login_bonus.tscn"
## 絵の ID（assets/icons/items/ に在るもの）を日ごとに回す
const ITEM_IDS: Array[String] = [
	"coin", "free_diamond", "item_heal_001", "item_exp_001", "item_boost_001", "item_material_001"
]


## 偽の router。ホームへの遷移を数えるだけ。
class PreviewRouter:
	extends RefCounted
	var home_count: int = 0

	func goto_home() -> void:
		home_count += 1


## 偽の「マスターを引く窓口」。決めておいた束をそのまま返す（再取得の通信をしない）。
class FakePrepare:
	extends PrepareLoginBonusMasterUseCase
	var fixed: LoginBonusStageMasters

	func _init(masters: LoginBonusStageMasters) -> void:
		fixed = masters

	func handle(_calendars: LoginBonusCalendars) -> PrepareLoginBonusMasterResult:
		return PrepareLoginBonusMasterResult.new(fixed, true)


## 偽の mst_item。ITEM_IDS の ID に名前とカテゴリを返す。
class FakeItems:
	extends MstItemRepository

	func get_by_id(id: String) -> MstItem:
		if not ITEM_IDS.has(id) and id != "gold":
			return null
		var item := MstItem.new()
		item.id = id
		item.name = "ゴールド" if id == "gold" else "アイテム " + id
		item.type = "recovery"
		return item


var _shot_path: String = ""
var _elapsed: float = 0.0
var _shot_done: bool = false
## 描画の指標の記録（--probe）。無ければ null
var _probe: RefCounted = null
var _probe_label: String = ""


func _ready() -> void:
	var args := _parse_args()
	_shot_path = str(args.get("shot", ""))
	if args.has("probe"):
		_probe = FrameProbe.new(float(args["probe"]))
		_probe_label = "login_bonus_" + str(args.get("preview", "both"))
	var repository := LocalLoginBonusRepository.new()
	var masters := _build(str(args.get("preview", "both")), repository)
	var displays := GetLoginBonusDisplaysUseCase.new(
		GetLoginBonusesUseCase.new(repository), FakeItems.new()
	)
	var presenter: LoginBonusPresenter = load(PRESENTER_SCENE).instantiate()
	presenter.setup(
		repository,
		FakePrepare.new(masters),
		GetLoginBonusScreenUseCase.new(repository, displays),
		PreviewRouter.new()
	)
	add_child(presenter)
	if not args.has("no-safe"):
		presenter.apply_safe_margins(IPHONE_X_SAFE)


func _process(delta: float) -> void:
	_elapsed += delta
	if _probe != null:
		if _probe.advance(delta):
			print(
				FrameProbe.format_line(
					_probe_label, _probe.frames(), _probe.result(), FrameProbe.is_headless()
				)
			)
			get_tree().quit(0)
		return
	if _shot_path == "" or _shot_done or _elapsed < SHOT_DELAY:
		return
	_shot_done = true
	DirAccess.make_dir_recursive_absolute(_shot_path.get_base_dir())
	var error := get_viewport().get_texture().get_image().save_png(_shot_path)
	print("PREVIEW: 保存 ", _shot_path, " (", error, ")")
	get_tree().quit(0 if error == OK else 1)


## 名前に応じて、メモリの進捗と login_bonus_list を repository に入れ、段のマスターの束を返す。
func _build(name: String, repository: LocalLoginBonusRepository) -> LoginBonusStageMasters:
	var masters := LoginBonusStageMasters.new()
	masters.normal = _stage(7, 2)
	masters.vip = _stage(7, 1)
	var rewards_count := 2
	match name:
		"normal":
			# 通常だけ。VIP の段は無い（null）
			repository.replace_calendars(
				LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 3, true, true))
			)
			rewards_count = 1
		"text":
			# 周期 9 日（8 超）→ 文字の画面
			masters.normal = _stage(9, 1)
			repository.replace_calendars(
				LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 3, true, true))
			)
		"received":
			repository.replace_calendars(
				LoginBonusCalendars.new(
					LoginBonusCalendar.new("lb", 4, true, false),
					LoginBonusCalendar.new("vip", 4, true, false, false, 3)
				)
			)
			rewards_count = 0
		_:
			# both / max: 両方の段が今日の段で、今日配ったばかり（スタンプが押される）
			repository.replace_calendars(
				LoginBonusCalendars.new(
					LoginBonusCalendar.new("lb", 3, true, true),
					LoginBonusCalendar.new("vip", 3, true, true, false, 3)
				)
			)
			rewards_count = 5 if name == "max" else 2
	var list: Array[LoginBonus] = []
	for i in range(rewards_count):
		# 1 行目はサーバーの実際の形（wallet は type=gold・id=gold で来る）にして、行の絵・名前の引きを確かめる
		if i == 0:
			list.append(LoginBonus.new("u0", "gold", "gold", 4000))
			continue
		list.append(LoginBonus.new("u%d" % i, "item", ITEM_IDS[i % ITEM_IDS.size()], 100 * (i + 1)))
	repository.replace(list)
	return masters


## cycle 日の段のマスター。日ごとに 1 件、last_multi 日目（最終日）だけ 2 件にして「＋1」も出す。
func _stage(cycle: int, last_multi: int) -> LoginBonusStageMaster:
	var entries: Array[Dictionary] = []
	for day in range(1, cycle + 1):
		var count := 2 if (day == cycle and last_multi == 2) else 1
		for k in range(count):
			entries.append(
				{
					"day": day,
					"type": "item",
					"id": ITEM_IDS[(day + k) % ITEM_IDS.size()],
					"quantity": day * 100 if day % 2 == 0 else day * 10,
					"metadata": {}
				}
			)
	return LoginBonusStageMasterReader.build_stage(cycle, entries)


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if not arg.begins_with("--"):
			continue
		var body: String = arg.substr(2)
		var separator := body.find("=")
		if separator < 0:
			result[body] = true
		else:
			result[body.substr(0, separator)] = body.substr(separator + 1)
	return result
