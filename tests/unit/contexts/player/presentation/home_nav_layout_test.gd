## ホームの導線ボタン（メール・お知らせ・ログインボーナス）のバッジの重なりのテスト（V3c）。
extends GdUnitTestSuite

const HOME_SCENE := "res://contexts/player/presentation/home/home.tscn"


## 前提: 導線ボタン 3 つ（メール・お知らせ・ログインボーナス）が並ぶ 1080x1920 と、幅の狭い 720x1280。
## 期待: メール・お知らせの右上のバッジ（未読の数字が 2 桁入る幅 48 まで想定）が、ボタンの文字の矩形と重ならない
## （3 つに増えて 1 つの幅が狭くなったとき、バッジが「お知らせ」の「せ」に重なった退行の再発防止）。
func test_nav_badges_do_not_overlap_button_text() -> void:
	for size in [Vector2i(1080, 1920), Vector2i(720, 1280)]:
		var viewport := SubViewport.new()
		viewport.size = size
		add_child(auto_free(viewport))
		var screen: HomePresenter = load(HOME_SCENE).instantiate()
		screen.setup(
			GetHomeSummaryUseCase.new(
				LocalPlayerRepository.new(),
				FakeMstRepositories.Level.new(),
				FakeMstRepositories.Config.new()
			),
			GetStaminaDisplayUseCase.new(
				LocalPlayerRepository.new(), FakeMstRepositories.FixedClock.new()
			)
		)
		viewport.add_child(screen)
		for i in range(3):
			await get_tree().process_frame
		for pair in [["MailButton", "MailBadge"], ["NoticeButton", "NoticeBadge"]]:
			var button := screen.get_node("Margin/Root/NavRow/" + pair[0]) as Button
			var badge := screen.get_node("Margin/Root/NavRow/%s/%s" % pair) as Control
			var font := button.get_theme_font("font")
			var font_size := button.get_theme_font_size("font_size")
			var text_size := font.get_string_size(
				button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size
			)
			var line_height := font.get_height(font_size)
			# 文字はボタンの中央に置かれる
			var center := button.get_global_rect().get_center()
			var text_rect := Rect2(
				center - Vector2(text_size.x, line_height) / 2.0, Vector2(text_size.x, line_height)
			)
			var badge_rect := badge.get_global_rect()
			(
				assert_bool(badge_rect.intersects(text_rect))
				. override_failure_message(
					"%s のバッジ %s が文字 %s に重なる (%s)" % [pair[0], badge_rect, text_rect, size]
				)
				. is_false()
			)
			assert_float(badge_rect.size.x).is_greater_equal(48.0)
