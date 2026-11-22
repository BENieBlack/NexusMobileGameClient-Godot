## LoginBonusPresenter の文字の組み立て（build_text・build_row_text。client_design.md 1-3 の文字の画面）のテスト。
## 画面を作らない純粋な静的関数の検査（presenter の画面のテストとはファイルを分ける）。
extends GdUnitTestSuite


func _displays(bonus: LoginBonus, name: String = "") -> LoginBonusDisplay:
	return LoginBonusDisplay.new(bonus, name)


## 前提: 無償ダイヤ（名前あり・名前なし）。期待: 名前があれば「名前 x数量」、無ければ固定名「無償ダイヤ x数量」。ID は出さない。
func test_text_free_diamond_name_rules() -> void:
	var bonus := LoginBonus.new("u", "item", "free_diamond", 100)
	assert_str(LoginBonusPresenter.build_text([_displays(bonus, "確認用")])).contains("確認用 x100")
	var fixed := LoginBonusPresenter.build_text([_displays(bonus)])
	assert_str(fixed).contains("無償ダイヤ x100")
	assert_str(fixed).not_contains("ID:")


## 前提: 他の item と旧種別 diamond。期待: 名前が無ければ従来の「アイテム (ID:…) x3」、diamond は特別扱いせずそのまま。
func test_text_legacy_labels() -> void:
	var other := LoginBonus.new("u", "item", "other", 3)
	assert_str(LoginBonusPresenter.build_text([_displays(other)])).contains("アイテム (ID:other) x3")
	var legacy := LoginBonus.new("u", "diamond", "diamond", 20)
	assert_str(LoginBonusPresenter.build_text([_displays(legacy)])).contains(
		"diamond (ID:diamond) x20"
	)


## 前提: 報酬の行 1 件。期待: build_row_text は字下げなしの「名前 x数量」（行の部品が使う）。
func test_row_text_has_no_indent() -> void:
	var text := LoginBonusPresenter.build_row_text(
		_displays(LoginBonus.new("u", "item", "coin", 5), "コイン")
	)
	assert_str(text).is_equal("コイン x5")
