## スタンプのアニメーションの再生・即時完了（client_design.md 6 節）。
##
## 目的: 「今日のマス」にスタンプが押される動き（K1〜K6）を、Tween で再生する。Tween は寿命をホストの Node
##       （presenter）に結びつけて作る（RefCounted の自分からは作れない）。ホストが画面ごと解放されると Tween も止まる。
## 動き（1 マス。開始の遅れ delay の後）:
##   1. スケール 2.0 → 1.0（TRANS_BACK・EASE_OUT。Godot の既定の行き過ぎで着地に弾みが出る）
##   2. 透明度 0 → 1 を最初の 0.1 秒（1. と同時）
##   3. 着地（STAMP_DURATION 秒後）にマス全体が明るくなる（modulate 1.0 → 1.3 → 1.0、全体で 0.1 秒）
##   使う動きは位置・スケール・透明度だけ（K5。シェーダ・パーティクルなし）。
## 時間: 通常の段は開始 0.3 秒・VIP の段は開始 0.5 秒（いずれもスタンプ 0.4 秒）。最終状態は通常 0.8 秒・VIP 1.0 秒で、
##       全体 1.0 秒以内（K3）。
## スキップ（K4）: finish_all() が実行中の Tween を止め、各マスを apply_state(state, false) の最終状態へ飛ばす。
##       「閉じる」ではない。完了後のタップでホームへ。
class_name StampPlayer
extends RefCounted

## 開始の遅れ（秒）。画面が出てから。通常の段が先、VIP の段が後
const NORMAL_DELAY := 0.3
const VIP_DELAY := 0.5
## スタンプが押される動きの長さ（秒）
const STAMP_DURATION := 0.4
## 透明度が 0 → 1 になる長さ（秒）
const FADE_DURATION := 0.1
## 着地の明るさの山（1.0 → これ → 1.0）。片道 0.05 秒で全体 0.1 秒
const FLASH_BRIGHTNESS := 1.3
const FLASH_HALF := 0.05

var _host: Node
## 再生中のマスと Tween の対応（キー: マス、値: Tween）。完了したものは取り除く
var _running: Dictionary = {}


func _init(host: Node) -> void:
	_host = host


## 1 マスのスタンプを、delay 秒後に押す。再生対象でない（is_waiting_stamp が偽）マスは何もしない。
func play(cell: CalendarCell, delay: float) -> void:
	if not cell.is_waiting_stamp:
		return
	# --- 1. 初期状態（縮尺 2.0・透明度 0）にして、遅れの後に動かす ---
	cell.prepare_stamp_animation()
	var stamp := cell.stamp_node()
	var tween := _host.create_tween()
	_running[cell] = tween
	# --- 2. 全ステップを同時に登録し、それぞれ set_delay で開始をずらす ---
	# （tween_interval で待ってから set_delay も付けると、遅れが二重に掛かる）
	tween.set_parallel(true)
	(
		tween
		. tween_property(stamp, "scale", Vector2.ONE, STAMP_DURATION)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
		. set_delay(delay)
	)
	tween.tween_property(stamp, "modulate:a", 1.0, FADE_DURATION).set_delay(delay)
	# --- 3. 着地の明るさ（スタンプの動きが終わってから 0.1 秒）---
	var land_delay := delay + STAMP_DURATION
	(
		tween
		. tween_property(
			cell,
			"modulate",
			Color(FLASH_BRIGHTNESS, FLASH_BRIGHTNESS, FLASH_BRIGHTNESS, 1.0),
			FLASH_HALF
		)
		. set_delay(land_delay)
	)
	tween.tween_property(cell, "modulate", Color.WHITE, FLASH_HALF).set_delay(
		land_delay + FLASH_HALF
	)
	tween.finished.connect(_on_finished.bind(cell), CONNECT_ONE_SHOT)


## 再生中のマスがあるか（アニメーション中のタップが「飛ばすだけ」か「閉じる」かの判断に使う）。
func is_running() -> bool:
	return not _running.is_empty()


## 実行中の Tween を全部止め、そのマスを最終状態（押印済み・縁取り）へ即時に飛ばす（K4）。
func finish_all() -> void:
	# 反復中に辞書が変わらないよう、キーを写してから処理する
	for cell in _running.keys():
		var tween: Tween = _running[cell]
		if tween != null and tween.is_valid():
			tween.kill()
		if is_instance_valid(cell):
			cell.apply_state(cell.state, false)
			cell.mark_stamped()
	_running.clear()


## 画面を離れるとき（presenter の _exit_tree）。Tween を止めるだけで、見た目は触らない。
func kill_all() -> void:
	for cell in _running.keys():
		var tween: Tween = _running[cell]
		if tween != null and tween.is_valid():
			tween.kill()
	_running.clear()


func _on_finished(cell: CalendarCell) -> void:
	_running.erase(cell)
	if is_instance_valid(cell):
		cell.mark_stamped()
