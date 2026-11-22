## StampPlayer（スタンプのアニメーション。client_design.md 6 節）のテスト。
##
## 時間の規約（通常 0.3 秒開始・VIP 0.5 秒開始・各 0.4 秒・全体 1.0 秒以内）と、再生・スキップ・画面破棄の挙動を確かめる。
extends GdUnitTestSuite

const CELL_SCENE := "res://contexts/login/presentation/login_bonus/calendar_cell.tscn"


func _waiting_cell() -> CalendarCell:
	var cell: CalendarCell = load(CELL_SCENE).instantiate()
	add_child(auto_free(cell))
	var view := CalendarCellView.new()
	view.day = 1
	cell.setup(view, 80)
	cell.apply_state(CalendarCellView.State.TODAY, true)
	return cell


## 前提: 設計の時間（6 節）。期待: 通常 0.3 秒・VIP 0.5 秒開始で各 0.4 秒、着地の明るさ 0.1 秒を足した終了が
## 通常 0.8 秒・VIP 1.0 秒で、どちらも 1.0 秒以内（K3）。
func test_timing_constants_follow_design() -> void:
	assert_float(StampPlayer.NORMAL_DELAY).is_equal(0.3)
	assert_float(StampPlayer.VIP_DELAY).is_equal(0.5)
	assert_float(StampPlayer.STAMP_DURATION).is_equal(0.4)
	var flash := StampPlayer.FLASH_HALF * 2.0
	var normal_end := StampPlayer.NORMAL_DELAY + StampPlayer.STAMP_DURATION + flash
	var vip_end := StampPlayer.VIP_DELAY + StampPlayer.STAMP_DURATION + flash
	assert_float(normal_end).is_equal_approx(0.8, 0.0001)
	assert_float(vip_end).is_less_equal(1.0 + 0.0001)


## 前提: 再生待ちのマスに play。期待: 直後はスタンプが「縮尺 2.0・透明度 0」で再生中扱い。
func test_play_prepares_initial_state() -> void:
	var cell := _waiting_cell()
	var player := StampPlayer.new(self)
	player.play(cell, 0.3)
	assert_bool(player.is_running()).is_true()
	assert_vector(cell.stamp_node().scale).is_equal(Vector2(2.0, 2.0))
	assert_float(cell.stamp_node().modulate.a).is_equal(0.0)
	player.kill_all()


## 前提: 再生待ちでないマス。期待: 何もしない。
func test_play_ignores_cell_not_waiting() -> void:
	var cell := _waiting_cell()
	cell.apply_state(CalendarCellView.State.TODAY, false)
	var player := StampPlayer.new(self)
	player.play(cell, 0.3)
	assert_bool(player.is_running()).is_false()


## 前提: 再生中にスキップ（finish_all）。期待: 再生が止まり、そのマスは押印済みの最終状態（縮尺 1・不透明・明るさ 1）。
func test_finish_all_jumps_to_final_state() -> void:
	var cell := _waiting_cell()
	var player := StampPlayer.new(self)
	player.play(cell, 0.5)
	player.finish_all()
	assert_bool(player.is_running()).is_false()
	assert_bool(cell.is_waiting_stamp).is_false()
	assert_bool(cell.is_stamp_visible()).is_true()
	assert_vector(cell.stamp_node().scale).is_equal(Vector2.ONE)
	assert_float(cell.stamp_node().modulate.a).is_equal(1.0)
	assert_bool(cell.modulate.is_equal_approx(Color.WHITE)).is_true()


## 前提: 通常の開始（0.3 秒）で再生し、Tween が実際に動く時間を待つ。
## 期待: 約 0.2 秒後はまだ開始前（縮尺 2.0・透明度 0）、約 0.85 秒後には再生が終わり最終状態（縮尺 1・不透明・明るさ 1）。
## 守る不具合: 開始の遅れが二重に掛かる（tween_interval と set_delay の併用。終了が 1.1 秒になり 0.85 秒では終わらない）。
func test_play_timing_with_real_tween() -> void:
	var cell := _waiting_cell()
	var player := StampPlayer.new(self)
	player.play(cell, StampPlayer.NORMAL_DELAY)
	await get_tree().create_timer(0.2).timeout
	assert_vector(cell.stamp_node().scale).is_equal(Vector2(2.0, 2.0))
	assert_float(cell.stamp_node().modulate.a).is_equal(0.0)
	assert_bool(player.is_running()).is_true()
	await get_tree().create_timer(0.65).timeout
	assert_bool(player.is_running()).is_false()
	assert_bool(cell.is_waiting_stamp).is_false()
	assert_bool(cell.is_stamp_visible()).is_true()
	assert_vector(cell.stamp_node().scale).is_equal_approx(Vector2.ONE, Vector2(0.01, 0.01))
	assert_float(cell.stamp_node().modulate.a).is_equal(1.0)
	assert_bool(cell.modulate.is_equal_approx(Color.WHITE)).is_true()
