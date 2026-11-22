## ログインボーナス画面の縦の高さの収まり・文字の潰れのテスト（client_design.md 1-4・9）。
##
## 目的: 基準機 iPhone X（1080x1920・安全領域 上 127・下 98）で、最大構成（通常 7＋VIP 7＋報酬 5 行）が
##       縦に収まること、表示されている文字のラベルが幅・高さ 0 に潰れていないことを、実際にレイアウトして確かめる。
## なぜ要るか: V2 で ValueRow のラベルが幅 1 に潰れて数値が描かれない不具合があった（コンテナの中のラベルは、
##       expand を付け忘れると最小幅になる）。見た目の崩れはテキスト比較では気づけないので、幅と高さを検査する。
## 方法: 1080x1920 の SubViewport にシーンを入れ、2 フレーム回してから Control の矩形を調べる（ヘッドレスでも
##       レイアウトは計算される）。
extends GdUnitTestSuite

const FX := preload("res://tests/unit/contexts/login/presentation/login_bonus_screen_fixtures.gd")
const VIEWPORT_SIZE := Vector2i(1080, 1920)
## iPhone X の安全領域（設計 1-4 の見積り。ビューポート単位）
const IPHONE_X_SAFE := {"left": 0.0, "top": 127.0, "right": 0.0, "bottom": 98.0}

var _repository: LocalLoginBonusRepository


func before_test() -> void:
	_repository = LocalLoginBonusRepository.new()


## 1080x1920 の SubViewport に画面を入れて 2 フレーム回す。safe が真なら iPhone X の安全領域を足す。
## prepare_masters: 段のマスターの束（null なら通常 7＋VIP 7）。release: 渡すと Prepare をその signal まで待たせる
## （「読み込み中…」の構成）。
func _layout(
	safe: bool = true,
	prepare_masters: LoginBonusStageMasters = null,
	release: LoginBonusScreenFixtures.GateSource = null
) -> Array:
	var viewport := SubViewport.new()
	viewport.size = VIEWPORT_SIZE
	add_child(auto_free(viewport))
	var masters := prepare_masters if prepare_masters != null else FX.masters()
	var gate := release.opened if release != null else Signal()
	var made := FX.make(viewport, ScreenTestDoubles.FakeRouter.new(), masters, _repository, gate)
	var presenter: LoginBonusPresenter = made[0]
	if safe:
		presenter.apply_safe_margins(IPHONE_X_SAFE)
	# 描画（_ready の描画）→ レイアウト確定のため 2 フレーム
	await get_tree().process_frame
	await get_tree().process_frame
	return [presenter, viewport]


## 最大構成の進捗（両段が 3 日目・今配ったばかり・報酬 5 行）を入れる。
func _put_max() -> void:
	FX.put_granted_now(_repository, 3)
	FX.put_rewards(_repository, 5)


func _visible_controls(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var control := node as Control
		if not control.visible:
			return
		out.append(control)
	for child in node.get_children():
		_visible_controls(child, out)


## 前提: 最大構成・iPhone X の安全領域つき。
## 期待: パネルが安全領域（上 175〜下 1774。余白 48＋安全領域）の中に収まる（収まらないと、縮め方③が要る）。
func test_max_layout_fits_in_safe_area() -> void:
	_put_max()
	var result := await _layout()
	var presenter: LoginBonusPresenter = result[0]
	var panel := presenter.get_node("Margin/Center/Panel") as Control
	var rect := panel.get_global_rect()
	var top := LoginBonusPresenter.BASE_MARGIN_VERTICAL + IPHONE_X_SAFE["top"]
	var bottom := (
		VIEWPORT_SIZE.y - LoginBonusPresenter.BASE_MARGIN_VERTICAL - IPHONE_X_SAFE["bottom"]
	)
	assert_float(rect.position.y).is_greater_equal(top - 0.5)
	assert_float(rect.end.y).is_less_equal(bottom + 0.5)
	# 幅は設計どおり 800
	assert_float(rect.size.x).is_equal_approx(800.0, 0.5)


## 前提: 最大構成。期待: 表示されている Control はすべて画面（1080x1920）の中に収まる。
func test_all_visible_controls_inside_screen() -> void:
	_put_max()
	var result := await _layout()
	var presenter: LoginBonusPresenter = result[0]
	var controls: Array[Control] = []
	# 背景動画・TapCatcher は全画面そのものなので対象外（それ以外を調べる）
	_visible_controls(presenter.get_node("Margin"), controls)
	var screen := Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE))
	var outside: Array[String] = []
	for control in controls:
		# 脈動・スタンプの拡大中の見た目は対象外（レイアウト上の矩形で見る）。サイズ 0 の入れ物は除く
		if control.size == Vector2.ZERO:
			continue
		if not screen.grow(0.5).encloses(control.get_global_rect()):
			outside.append("%s %s" % [control.get_path(), control.get_global_rect()])
	assert_array(outside).is_empty()


## 表示中の文字つきラベルが潰れていない（幅・高さが 8 以上）ことを検査し、数えたラベルの数を返す。
## 8 未満なら実質潰れとみなす（「x70」のような短い文字でも 8 は超える）。
func _assert_labels_not_collapsed(presenter: Node) -> int:
	var controls: Array[Control] = []
	_visible_controls(presenter.get_node("Margin"), controls)
	var labels := 0
	var collapsed: Array[String] = []
	for control in controls:
		if control is Label and (control as Label).text != "":
			labels += 1
			if control.size.x < 8.0 or control.size.y < 8.0:
				collapsed.append("%s size=%s" % [control.get_path(), control.size])
	assert_array(collapsed).is_empty()
	return labels


## 前提: 最大構成。期待: 文字のあるラベルは visible で、幅・高さが 0 でない（V2 の ValueRow の潰れ不具合の再発防止）。
## 14 マスぶんの文字（N 日目×14・数量×14）＋見出し・報酬の行などが数えられていること。
func test_labels_with_text_are_not_collapsed() -> void:
	_put_max()
	var result := await _layout()
	assert_int(_assert_labels_not_collapsed(result[0])).is_greater(40)


## 前提: 文字の画面（周期 9 日）。期待: タイトル・本文・案内のラベルが潰れず、画面に収まる。
func test_labels_not_collapsed_in_text_fallback() -> void:
	FX.put_granted_now(_repository, 3)
	FX.put_rewards(_repository, 2)
	var result := await _layout(true, FX.masters(9, 7))
	assert_int(_assert_labels_not_collapsed(result[0])).is_greater(2)


## 前提: マスターを引く窓口が待っている（読み込み中…）。期待: 「読み込み中…」のラベルが潰れない。
func test_labels_not_collapsed_while_loading() -> void:
	FX.put_granted_now(_repository, 3)
	var release := FX.GateSource.new()
	var result := await _layout(true, null, release)
	assert_int(_assert_labels_not_collapsed(result[0])).is_greater(1)


## 前提: 再表示（今日の段だが今配ったのではない）。期待: 「受け取り済みです」の旨を含めて潰れない。
func test_labels_not_collapsed_in_redisplay() -> void:
	_repository.replace_calendars(
		LoginBonusCalendars.new(
			LoginBonusCalendar.new("lb", 4, true, false),
			LoginBonusCalendar.new("vip", 4, true, false, false, 3)
		)
	)
	var result := await _layout()
	var notice := result[0].get_node("Margin/Center/Panel/VBox/NoticeLabel") as Label
	assert_bool(notice.visible).is_true()
	assert_int(_assert_labels_not_collapsed(result[0])).is_greater(20)


## 前提: 通常だけ／VIP だけの構成。期待: それぞれ潰れない。
func test_labels_not_collapsed_with_single_stage() -> void:
	_repository.replace_calendars(
		LoginBonusCalendars.new(LoginBonusCalendar.new("lb", 2, true, true))
	)
	var normal_only := await _layout(true, FX.masters(7, 7, true, false))
	assert_int(_assert_labels_not_collapsed(normal_only[0])).is_greater(10)
	_repository.replace_calendars(
		LoginBonusCalendars.new(null, LoginBonusCalendar.new("vip", 2, true, true, false, 3))
	)
	var vip_only := await _layout(true, FX.masters(7, 7, false, true))
	assert_int(_assert_labels_not_collapsed(vip_only[0])).is_greater(10)


## 前提: 最大構成。期待: アイコン（ItemIcon）も 0 に潰れず、指定の大きさ（通常 80・VIP 72・報酬 56）で出る。
func test_icons_have_expected_sizes() -> void:
	_put_max()
	var result := await _layout()
	var presenter: LoginBonusPresenter = result[0]
	var normal := presenter.get_node("Margin/Center/Panel/VBox/NormalSection") as CalendarSection
	var vip := presenter.get_node("Margin/Center/Panel/VBox/VipSection") as CalendarSection
	var normal_icon := normal.cells[0].get_node("Content/IconHolder/ItemIcon") as Control
	var vip_icon := vip.cells[0].get_node("Content/IconHolder/ItemIcon") as Control
	var reward_icon := (
		presenter.get_node("Margin/Center/Panel/VBox/RewardsList").get_child(0).get_node("ItemIcon")
		as Control
	)
	assert_vector(normal_icon.size).is_equal(Vector2(80, 80))
	assert_vector(vip_icon.size).is_equal(Vector2(72, 72))
	assert_vector(reward_icon.size).is_equal(Vector2(56, 56))


## 前提: 最終日（7 日目）のマス。期待: 行の残りの幅を使う（4 マス目より広い）。4 の倍数でない周期の最終日だけ伸びる。
func test_last_cell_is_wider_when_row_is_short() -> void:
	_put_max()
	var result := await _layout()
	var presenter: LoginBonusPresenter = result[0]
	var cells := (
		(presenter.get_node("Margin/Center/Panel/VBox/NormalSection") as CalendarSection).cells
	)
	assert_float(cells[6].size.x).is_greater(cells[5].size.x * 1.5)
	assert_float(cells[0].size.x).is_equal_approx(cells[3].size.x, 1.0)
