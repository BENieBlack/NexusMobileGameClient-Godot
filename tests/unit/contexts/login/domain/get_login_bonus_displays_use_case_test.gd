## GetLoginBonusDisplaysUseCase の単体テスト（free-diamond-item client_design.md 3-3）。
extends GdUnitTestSuite


## 偽の MstItemRepository。names の ID だけ名前つきで返し、無ければ null。引いた ID を記録する。
class FakeItems:
	extends MstItemRepository
	var names: Dictionary = {}
	var asked: Array[String] = []

	func get_by_id(id: String) -> MstItem:
		asked.append(id)
		if not names.has(id):
			return null
		var item := MstItem.new()
		item.id = id
		item.name = str(names[id])
		return item


var _repository: LocalLoginBonusRepository
var _items: FakeItems


func before_test() -> void:
	_repository = LocalLoginBonusRepository.new()
	_items = FakeItems.new()


func _use_case(items: MstItemRepository) -> GetLoginBonusDisplaysUseCase:
	return GetLoginBonusDisplaysUseCase.new(GetLoginBonusesUseCase.new(_repository), items)


## 前提: item と unit の 2 件。期待: item だけ名前を引き、unit は引かない（item_name は空）。
func test_only_item_type_is_looked_up() -> void:
	_items.names = {"free_diamond": "無償ダイヤ"}
	var bonuses: Array[LoginBonus] = [
		LoginBonus.new("u1", "item", "free_diamond", 100),
		LoginBonus.new("u2", "unit", "7", 1),
	]
	_repository.replace(bonuses)
	var displays := _use_case(_items).handle()
	assert_int(displays.size()).is_equal(2)
	assert_str(displays[0].item_name).is_equal("無償ダイヤ")
	assert_str(displays[1].item_name).is_empty()
	assert_array(_items.asked).contains_exactly(["free_diamond"])


## 前提: 名前が引けない（null）・name が空。期待: item_name は空で落ちない。
func test_missing_or_empty_name_is_empty() -> void:
	_items.names = {"a": ""}
	var bonuses: Array[LoginBonus] = [
		LoginBonus.new("u1", "item", "a", 1),
		LoginBonus.new("u2", "item", "b", 1),
	]
	_repository.replace(bonuses)
	var displays := _use_case(_items).handle()
	assert_str(displays[0].item_name).is_empty()
	assert_str(displays[1].item_name).is_empty()


## 前提: Repository が null（配線の取りこぼし）。期待: 落ちずに item_name 空。
func test_null_repository_does_not_crash() -> void:
	var bonuses: Array[LoginBonus] = [LoginBonus.new("u1", "item", "a", 1)]
	_repository.replace(bonuses)
	var displays := _use_case(null).handle()
	assert_str(displays[0].item_name).is_empty()
	assert_int(displays[0].bonus.amount).is_equal(1)


## 前提: 受取が空。期待: 空の一覧。
func test_empty_bonuses() -> void:
	assert_array(_use_case(_items).handle()).is_empty()


## 絵のキー（ItemIcon が決める key）を、行の表示値から求める（reward_row と同じ引数）。
func _icon_key(display: LoginBonusDisplay) -> String:
	return ItemIconResolver.resolve_key(
		display.icon_type, display.bonus.id, display.item_type, ItemIconTable.has_key
	)


## 前提: login_bonus_list の行が wallet 系（type=gold・id=gold。サーバーの読み替え）で、mst_item に名前と type がある。
## 期待: 絵は items/gold（「?」の unknown にしない）、名前は mst_item の name、文字は「名前 x数量」で「(ID:…)」を出さない。
## 守る不具合: 行は type=gold を ItemIcon にそのまま渡して unknown になり、名前も「ゴールド (ID:gold)」になっていた。
func test_gold_row_uses_item_icon_and_master_name() -> void:
	_items.names = {"gold": "ゴールド（名前）"}
	var display := _use_case(_items).display_of(LoginBonus.new("u", "gold", "gold", 4000))
	assert_str(_icon_key(display)).is_equal("items/gold")
	assert_str(display.item_name).is_equal("ゴールド（名前）")
	assert_str(LoginBonusPresenter.build_row_text(display)).is_equal("ゴールド（名前） x4000")


## 前提: 無償ダイヤ（item・free_diamond）・通常のアイテム。期待: 絵は items/<id>、名前は mst_item の name。
func test_item_rows_use_item_icon_and_name() -> void:
	_items.names = {"free_diamond": "無償ダイヤ", "item_heal_001": "回復薬"}
	var diamond := _use_case(_items).display_of(LoginBonus.new("u", "item", "free_diamond", 5))
	var heal := _use_case(_items).display_of(LoginBonus.new("u", "item", "item_heal_001", 2))
	assert_str(_icon_key(diamond)).is_equal("items/free_diamond")
	assert_str(LoginBonusPresenter.build_row_text(diamond)).is_equal("無償ダイヤ x5")
	assert_str(_icon_key(heal)).is_equal("items/item_heal_001")
	assert_str(LoginBonusPresenter.build_row_text(heal)).is_equal("回復薬 x2")


## 前提: 名前が引けない ID（絵も無い item）と、引けない gold。
## 期待: 「(ID:…)」は名前が引けないときだけ。絵は item の未知 ID が unknown、gold は引けなくても items/gold。
func test_rows_without_master_name_show_id_and_fallback_icon() -> void:
	var other := _use_case(_items).display_of(LoginBonus.new("u", "item", "no_such_item", 3))
	assert_str(_icon_key(other)).is_equal("fallback/unknown")
	assert_str(LoginBonusPresenter.build_row_text(other)).is_equal("アイテム (ID:no_such_item) x3")
	var gold := _use_case(_items).display_of(LoginBonus.new("u", "gold", "gold", 10))
	assert_str(_icon_key(gold)).is_equal("items/gold")
	assert_str(LoginBonusPresenter.build_row_text(gold)).is_equal("ゴールド (ID:gold) x10")


## 前提: unit・paid_diamond など id で引かない type。期待: 絵は unknown のまま（items/ に同じ ID があっても引かない）。
func test_non_id_types_keep_unknown_icon() -> void:
	_items.names = {"gold": "x"}
	var unit := _use_case(_items).display_of(LoginBonus.new("u", "unit", "gold", 1))
	var paid := _use_case(_items).display_of(LoginBonus.new("u", "paid_diamond", "gold", 1))
	assert_str(_icon_key(unit)).is_equal("fallback/unknown")
	assert_str(_icon_key(paid)).is_equal("fallback/unknown")
