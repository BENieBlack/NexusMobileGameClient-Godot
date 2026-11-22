## ログインボーナス画面（presenter・部品）のテスト用の偽物と、表示モデルの組み立て（共用）。
##
## 目的: 画面のテストごとに「マスターの束・進捗・偽の mst_item・偽の Prepare」を書かないための共用部品。
##       本物の LoginBonusPresenter・GetLoginBonusScreenUseCase を使い、差し替えるのはマスターを引く窓口と
##       mst_item の引き（偽）だけ。
class_name LoginBonusScreenFixtures
extends RefCounted

## 絵が在る ID（assets/icons/items/）
const ITEM_IDS: Array[String] = ["coin", "free_diamond", "item_heal_001", "item_exp_001"]
const PRESENTER_SCENE := "res://contexts/login/presentation/login_bonus/login_bonus.tscn"
const PRESENTER_FROM_HOME_SCENE := (
	"res://contexts/login/presentation/login_bonus/" + "login_bonus_from_home.tscn"
)


## 偽の mst_item。ITEM_IDS だけ名前つきで返し、他は null（引けない）。
class FakeItems:
	extends MstItemRepository

	func get_by_id(id: String) -> MstItem:
		if not LoginBonusScreenFixtures.ITEM_IDS.has(id):
			return null
		var item := MstItem.new()
		item.id = id
		item.name = "名前_" + id
		item.type = "recovery"
		return item


## 「窓口を待たせる」ための signal の持ち主（Signal 単体は作れないので、ユーザー signal を持つ入れ物）。
class GateSource:
	extends RefCounted
	signal opened


## 偽の「マスターを引く窓口」。固定の束を返し、渡された進捗を記録する。
## gate を渡すと、その signal が発火するまで待つ（「読み込み中…」の表示の確認用）。
class FakePrepare:
	extends PrepareLoginBonusMasterUseCase
	var fixed: LoginBonusStageMasters
	var received: Array[LoginBonusCalendars] = []
	var gate: Signal

	func _init(masters: LoginBonusStageMasters) -> void:
		fixed = masters

	func handle(calendars: LoginBonusCalendars) -> PrepareLoginBonusMasterResult:
		received.append(calendars)
		if not gate.is_null():
			await gate
		return PrepareLoginBonusMasterResult.new(fixed, true)


## cycle 日の段のマスター。day ごとに 1 件、最終日だけ 2 件にして「＋1」も作れる。
static func stage(cycle: int, last_day_multi: bool = true) -> LoginBonusStageMaster:
	var entries: Array[Dictionary] = []
	for day in range(1, cycle + 1):
		var count := 2 if (day == cycle and last_day_multi) else 1
		for k in range(count):
			entries.append(
				{
					"day": day,
					"type": "item",
					"id": ITEM_IDS[(day + k) % ITEM_IDS.size()],
					"quantity": day * 100,
					"metadata": {}
				}
			)
	return LoginBonusStageMasterReader.build_stage(cycle, entries)


static func masters(
	normal_cycle: int = 7, vip_cycle: int = 7, with_normal: bool = true, with_vip: bool = true
) -> LoginBonusStageMasters:
	var result := LoginBonusStageMasters.new()
	if with_normal:
		result.normal = stage(normal_cycle)
	if with_vip:
		result.vip = stage(vip_cycle)
	return result


## 画面を作って木に入れる（まだ _ready は走るが、描画は await が要る。呼び出し側で await する）。
## 戻り値: [presenter, repository, prepare]。
static func make(
	parent: Node,
	router: Object,
	prepare_masters: LoginBonusStageMasters,
	repository: LocalLoginBonusRepository,
	gate: Signal = Signal()
) -> Array:
	var items := FakeItems.new()
	var displays := GetLoginBonusDisplaysUseCase.new(GetLoginBonusesUseCase.new(repository), items)
	var prepare := FakePrepare.new(prepare_masters)
	prepare.gate = gate
	var presenter: LoginBonusPresenter = load(PRESENTER_SCENE).instantiate()
	presenter.setup(
		repository, prepare, GetLoginBonusScreenUseCase.new(repository, displays), router
	)
	parent.add_child(presenter)
	return [presenter, repository, prepare]


## 通常・VIP の両方が今日の段で、今日配ったばかり（スタンプが押される）進捗。last_day は 1 始まり。
static func put_granted_now(
	repository: LocalLoginBonusRepository, last_day: int, with_vip: bool = true
) -> void:
	var vip: LoginBonusCalendar = null
	if with_vip:
		vip = LoginBonusCalendar.new("vip", last_day, true, true, false, 3)
	repository.replace_calendars(
		LoginBonusCalendars.new(LoginBonusCalendar.new("lb", last_day, true, true), vip)
	)


## 報酬の行（login_bonus_list）を count 件入れる。
static func put_rewards(repository: LocalLoginBonusRepository, count: int) -> void:
	var list: Array[LoginBonus] = []
	for i in range(count):
		list.append(LoginBonus.new("u%d" % i, "item", ITEM_IDS[i % ITEM_IDS.size()], 100 * (i + 1)))
	repository.replace(list)


## 偽のカレンダー API（list・receive）。結果を順に返し（足りなくなったら最後を繰り返す）、呼び出しを記録する。
## fetch_gate / receive_gate があれば、その signal が発火するまで応答を待たせる（「読み込み中」「受け取り中」の確認用）。
class ScriptedCalendar:
	extends LoginBonusCalendarRepository
	var fetch_results: Array[FetchLoginBonusCalendarsResult] = []
	var receive_results: Array[ReceiveVipLoginBonusResult] = []
	var fetch_gate: Signal
	var receive_gate: Signal
	var fetch_count: int = 0
	## receive_vip に渡された {id, key}
	var receive_calls: Array[Dictionary] = []

	func fetch_calendars() -> FetchLoginBonusCalendarsResult:
		fetch_count += 1
		if not fetch_gate.is_null():
			await fetch_gate
		return fetch_results[mini(fetch_count, fetch_results.size()) - 1]

	func receive_vip(id: String, key: String) -> ReceiveVipLoginBonusResult:
		receive_calls.append({"id": id, "key": key})
		if not receive_gate.is_null():
			await receive_gate
		return receive_results[mini(receive_calls.size(), receive_results.size()) - 1]


## 再受け取りが可能な進捗（通常・VIP とも 4 日目・今日の段・今配ったのではない。VIP は can_re_receive 真）。
static func offer_calendars(can_re_receive: bool = true) -> LoginBonusCalendars:
	return LoginBonusCalendars.new(
		LoginBonusCalendar.new("lb", 4, true, false),
		LoginBonusCalendar.new("vip", 4, true, false, can_re_receive, 3)
	)


## list の成功結果。
static func fetched(calendars: LoginBonusCalendars) -> FetchLoginBonusCalendarsResult:
	return FetchLoginBonusCalendarsResult.new(null, calendars)


## receive の成功結果。VIP の段は今日受け取り済み（is_granted_now 真・can_re_receive 偽）、報酬は count 件。
static func received(count: int = 1) -> ReceiveVipLoginBonusResult:
	var rewards: Array[LoginBonus] = []
	for i in range(count):
		rewards.append(LoginBonus.new("r%d" % i, "item", ITEM_IDS[(i + 1) % ITEM_IDS.size()], 500))
	return ReceiveVipLoginBonusResult.new(
		null, rewards, LoginBonusCalendar.new("vip", 4, true, true, false, 4)
	)


## 失敗結果（kind 指定）。
static func failed_receive(kind: AppError.Kind, code: int = -1) -> ReceiveVipLoginBonusResult:
	var error := AppError.new(kind)
	error.error_code = code
	return ReceiveVipLoginBonusResult.new(error)


static func failed_fetch(kind: AppError.Kind) -> FetchLoginBonusCalendarsResult:
	return FetchLoginBonusCalendarsResult.new(AppError.new(kind))


## 受け取りまで本物の UseCase でつないだ画面を作る（Prepare だけ偽。API は ScriptedCalendar）。
## 戻り値: [presenter, player_repository]。ApplyUpdatedResourcesUseCase は本物で、PlayerRepository に反映される。
static func make_full(
	parent: Node,
	router: Object,
	toast: Object,
	repository: LocalLoginBonusRepository,
	calendar: ScriptedCalendar,
	from_home: bool = false,
	prepare_masters: LoginBonusStageMasters = null
) -> Array:
	var items := FakeItems.new()
	var displays := GetLoginBonusDisplaysUseCase.new(GetLoginBonusesUseCase.new(repository), items)
	var player := LocalPlayerRepository.new()
	var prepare := FakePrepare.new(prepare_masters if prepare_masters != null else masters())
	var scene := PRESENTER_FROM_HOME_SCENE if from_home else PRESENTER_SCENE
	var presenter: LoginBonusPresenter = load(scene).instantiate()
	presenter.setup(
		repository,
		prepare,
		GetLoginBonusScreenUseCase.new(repository, displays),
		router,
		FetchLoginBonusCalendarsUseCase.new(calendar, repository),
		ReceiveVipLoginBonusUseCase.new(
			calendar, repository, ApplyUpdatedResourcesUseCase.new(player)
		),
		toast
	)
	parent.add_child(presenter)
	return [presenter, player]
