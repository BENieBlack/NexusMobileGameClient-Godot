## ApplyUpdatedResourcesUseCase の単体テスト（updated_resources の 4 種をホームの保持へ取り込む。client_design.md 3-3）。
## メモリのみの LocalPlayerRepository を使う。ホームの CoinAmount（wallet）・DiamondTotal（item）への反映も確かめる。
extends GdUnitTestSuite

var _repository: LocalPlayerRepository
var _use_case: ApplyUpdatedResourcesUseCase


func before_test() -> void:
	_repository = LocalPlayerRepository.new()
	_use_case = ApplyUpdatedResourcesUseCase.new(_repository)
	(
		_repository
		. replace(
			(
				PlayerState
				. new(
					{"my_id": "abc"},
					{
						"trx_unit_list": [{"trx_unit_id": "u1"}],
						"trx_item_list":
						[
							{"mst_item_id": "potion", "free_amount": 3},
							{"mst_item_id": "free_diamond", "free_amount": 100}
						],
						"trx_wallet_list":
						[{"mst_item_id": "coin", "free_amount": 10, "paid_amount": 0}],
						"trx_equipment_list": [],
						"trx_stamina_list": [{"type": "normal", "amount": 40}],
					},
					{"platform": "Apple", "paid_amount": 5},
					12,
					true
				)
			)
		)
	)


func _items() -> Array:
	return _repository.current().trx_list("trx_item_list")


## 前提: trx_item_list に既存の行（free_diamond）と新しい行（ether）。
## 期待: mst_item_id で差し替え、無ければ追加し、他の行（potion）は残る（全置き換えにしない）。
func test_item_rows_are_replaced_by_mst_item_id_and_others_kept() -> void:
	var result := _use_case.handle(
		{
			"trx_item_list":
			[
				{"mst_item_id": "free_diamond", "free_amount": 400},
				{"mst_item_id": "ether", "free_amount": 1}
			]
		}
	)
	assert_bool(result.ok).is_true()
	assert_int(_items().size()).is_equal(3)
	assert_int(int(_items()[0]["free_amount"])).is_equal(3)
	assert_int(int(_items()[1]["free_amount"])).is_equal(400)
	assert_str(_items()[2]["mst_item_id"]).is_equal("ether")
	# ホームの無償ダイヤの合計（DiamondTotal）に反映される
	assert_int(DiamondTotal.calculate(_repository.current().trx_diamond, _items())).is_equal(405)


## 前提: trx_wallet_list の coin の行。期待: mst_item_id で差し替わり、ホームのコイン（CoinAmount）に反映される。
func test_wallet_row_is_replaced_and_reflected_in_coin_amount() -> void:
	_use_case.handle(
		{"trx_wallet_list": [{"mst_item_id": "coin", "free_amount": 1500, "paid_amount": 0}]}
	)
	assert_int(_repository.current().trx_list("trx_wallet_list").size()).is_equal(1)
	assert_int(CoinAmount.calculate(_repository.current().trx_list("trx_wallet_list"))).is_equal(
		1500
	)


## 前提: 取り込み済みのコイン 10 に、updated_resources で gold の行（trx_wallet_list の mst_item_id = gold）が来る。
## 期待: gold の行は保持に入るが、ホームの「コイン」（CoinAmount。mst_item_id = coin だけを読む）は 10 のまま変わらない
## （人の決定 C の回帰防止: gold の報酬をコインの表示に混ぜない）。coin の行は残る。
func test_gold_wallet_row_does_not_change_coin_amount() -> void:
	var before := CoinAmount.calculate(_repository.current().trx_list("trx_wallet_list"))
	_use_case.handle(
		{"trx_wallet_list": [{"mst_item_id": "gold", "free_amount": 9999, "paid_amount": 0}]}
	)
	var rows := _repository.current().trx_list("trx_wallet_list")
	assert_int(rows.size()).is_equal(2)
	assert_int(CoinAmount.calculate(rows)).is_equal(before)
	assert_int(before).is_equal(10)


## 前提: trx_stamina_list の normal・trx_diamond。期待: stamina は type で差し替え、diamond は置き換える。
func test_stamina_by_type_and_diamond_replacement() -> void:
	(
		_use_case
		. handle(
			{
				"trx_stamina_list":
				[{"type": "normal", "amount": 10}, {"type": "raid", "amount": 2}],
				"trx_diamond": {"platform": "Apple", "paid_amount": 50},
			}
		)
	)
	var stamina := _repository.current().trx_list("trx_stamina_list")
	assert_int(stamina.size()).is_equal(2)
	assert_int(int(stamina[0]["amount"])).is_equal(10)
	assert_int(int(_repository.current().trx_diamond["paid_amount"])).is_equal(50)


## 前提: キー無し・null・型違い・空の辞書・主キーの無い行・辞書でない行。期待: 何も壊さない（元のまま）。
func test_missing_null_and_wrong_types_change_nothing() -> void:
	for body: Dictionary in [
		{},
		{
			"trx_item_list": null,
			"trx_wallet_list": null,
			"trx_stamina_list": null,
			"trx_diamond": null
		},
		{
			"trx_item_list": {"a": 1},
			"trx_wallet_list": "x",
			"trx_stamina_list": 5,
			"trx_diamond": [1]
		},
		{"trx_diamond": {}},
		{"trx_item_list": [{"amount": 9}, "str", null]},
	]:
		assert_bool(_use_case.handle(body).ok).is_true()
		assert_int(_items().size()).is_equal(2)
		assert_int(int(_items()[0]["free_amount"])).is_equal(3)
		assert_int(int(_repository.current().trx_diamond["paid_amount"])).is_equal(5)
		assert_int(_repository.current().trx_list("trx_stamina_list").size()).is_equal(1)


## 前提: unit・equipment と未知のキー。期待: 取り込まない（無視）。プレイヤー・サーバー時刻は引き継ぐ。
func test_other_keys_are_ignored_and_state_is_preserved() -> void:
	_use_case.handle(
		{"trx_unit_list": [{"trx_unit_id": "new"}], "trx_equipment_list": [{"x": 1}], "unknown": 1}
	)
	var state := _repository.current()
	assert_str(state.trx_list("trx_unit_list")[0]["trx_unit_id"]).is_equal("u1")
	assert_array(state.trx_list("trx_equipment_list")).is_empty()
	assert_str(state.user_id()).is_equal("abc")
	assert_int(state.server_time_offset_seconds).is_equal(12)
	assert_bool(state.has_server_time).is_true()


## 前提: 取り込み前に current() で得た状態。期待: 元の PlayerState の一覧は書き換わらない（新しい状態で置き換える）。
func test_does_not_mutate_previous_state() -> void:
	var before := _repository.current()
	_use_case.handle({"trx_item_list": [{"mst_item_id": "potion", "free_amount": 99}]})
	assert_int(int(before.trx_list("trx_item_list")[0]["free_amount"])).is_equal(3)
