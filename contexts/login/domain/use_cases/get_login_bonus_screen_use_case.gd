## ログインボーナス画面の表示モデル（LoginBonusScreen）を作る UseCase（client_design.md 1-3・2-1・3）。
##
## 目的: メモリの段の進捗（login 応答・list 応答・再受け取り）と、マスターから引いた段（周期・全日の報酬）、
##       login_bonus_list から、画面が描くだけの値を作る。業務の判断（今日の段・状態・文字の画面への
##       落とし方）はここに集める。presenter は結果を描くだけ。通信はしない（同期。マスターは Prepare の結果を受け取る）。
## 流れ（handle）:
##   1. 文字の画面に落とす条件を確かめる（上から順）
##        ① 通常・VIP のどちらの段も無い（T4・旧サーバー。D4）
##        ② 出せる段が 1 つも無い。マスターを引けない段（古いマスター。再取得しても引けない。2-4）は
##           その段だけ出さず（null 扱い）、両方出せないときだけ文字の画面（人の回答 U-11）
##        ③ 出せる段のいずれかの周期の日数が 1 未満・8 超（C1。こちらは画面全体を文字にする）
##   2. 段ごとに、状態を決める（段の状態 = サーバーの 2 つの真偽と last_day だけ。ゲーム内日付も
##      login_bonus_list の空・非空も使わない。C8・T3）
##        今日の段 = is_granted_today が真、かつ 1 ≤ last_day ≤ cycle_days
##        今日の段 → last_day のマスが TODAY、それ以前が RECEIVED、それより後が FUTURE
##        今日の段でない・日数が範囲外 → 全マス NEUTRAL（隠さない。T2）
##   3. スタンプを再生するマス（play_stamp）= 今日の段 かつ is_granted_now が真 かつ今日のマス かつ再生が許される
##   4. 再表示の旨 = いずれかの段が今日の段で、どの段も is_granted_now が偽
##   5. 受け取りボタン = VIP の段の can_re_receive が真（段の ID があるとき）
##   6. 「今日配られた報酬」の行 = include_login_bonus_list が真のとき login_bonus_list の全行（FROM_HOME は出さない）
## 引数:
##   masters                  PrepareLoginBonusMasterUseCase の結果の masters
##   include_login_bonus_list FROM_LOGIN は真、FROM_HOME は偽
##   play_stamp_allowed       偽ならスタンプを再生しない（FROM_HOME の最初の描画。確認のみ。H3）
##   play_stamp_normal        偽なら通常の段のスタンプだけ再生しない。再受け取りの成功後に画面を作り直すとき、
##                            login で再生済みの通常の段をもう一度鳴らさないため（T5: 再受け取りで真なのは VIP の段だけ）
##   extra_rewards            再受け取りで今配られた報酬（応答の login_bonus_list）。「今日配られた報酬」の行の
##                            **最後に足す**（FROM_LOGIN は login の行の後ろ、FROM_HOME は include が偽なので
##                            この報酬だけの行になる。Q-3）。メモリの login_bonus_list には書かない（login の記録を汚さない）
## 名前・アイコンのカテゴリは GetLoginBonusDisplaysUseCase.display_of で引く（画面を開くとき 1 回だけ）。
class_name GetLoginBonusScreenUseCase
extends RefCounted

var _login_bonus_repository: LoginBonusRepository
var _get_displays: GetLoginBonusDisplaysUseCase


func _init(
	login_bonus_repository: LoginBonusRepository, get_displays: GetLoginBonusDisplaysUseCase
) -> void:
	_login_bonus_repository = login_bonus_repository
	_get_displays = get_displays


func handle(
	masters: LoginBonusStageMasters,
	include_login_bonus_list: bool,
	play_stamp_allowed: bool,
	play_stamp_normal: bool = true,
	extra_rewards: Array[LoginBonus] = []
) -> LoginBonusScreen:
	var screen := LoginBonusScreen.new()
	# 「今日配られた報酬」の行（文字の画面でも同じ行を文字にする）
	if include_login_bonus_list:
		screen.rewards = _get_displays.handle()
	# 再受け取りの報酬は、login の行の後ろに足す（受け取った順のまま）
	for bonus in extra_rewards:
		screen.rewards.append(_get_displays.display_of(bonus))

	var calendars := _login_bonus_repository.calendars()
	var stage_masters := masters if masters != null else LoginBonusStageMasters.new()
	# マスターを引けない段は出さない（進捗の段を null に落とす）。受け取りボタンも出さない
	var normal_calendar := calendars.normal if stage_masters.normal != null else null
	var vip_calendar := calendars.vip if stage_masters.vip != null else null

	# --- 1. 文字の画面に落とす条件 ---
	var reason := _fallback_reason(calendars, normal_calendar, vip_calendar, stage_masters)
	if reason != LoginBonusScreen.FallbackReason.NONE:
		screen.use_text_fallback = true
		screen.fallback_reason = reason
		return screen

	# --- 2・3. 段ごとの表示値 ---
	if normal_calendar != null:
		screen.normal = _build_stage(
			normal_calendar, stage_masters.normal, false, play_stamp_allowed and play_stamp_normal
		)
	if vip_calendar != null:
		screen.vip = _build_stage(vip_calendar, stage_masters.vip, true, play_stamp_allowed)

	# --- 4. 再表示の旨 ---
	var any_today := false
	var any_granted_now := false
	for stage in [screen.normal, screen.vip]:
		if stage != null and stage.is_today_stage:
			any_today = true
	for calendar in [normal_calendar, vip_calendar]:
		if calendar != null and calendar.is_granted_now:
			any_granted_now = true
	screen.show_received_notice = any_today and not any_granted_now

	# --- 5. 受け取りボタン ---
	if vip_calendar != null and vip_calendar.can_re_receive and vip_calendar.mst_id != "":
		screen.receive_offer = ReceiveOffer.new(true, vip_calendar.mst_id)
	return screen


## 文字の画面に落とす理由（落とさないなら NONE）。
func _fallback_reason(
	calendars: LoginBonusCalendars,
	normal_calendar: LoginBonusCalendar,
	vip_calendar: LoginBonusCalendar,
	masters: LoginBonusStageMasters
) -> LoginBonusScreen.FallbackReason:
	if not calendars.has_any():
		return LoginBonusScreen.FallbackReason.NO_STAGE
	# 出せる段（進捗があり、マスターも引けた段）が 1 つも無い
	if normal_calendar == null and vip_calendar == null:
		return LoginBonusScreen.FallbackReason.MASTER_UNAVAILABLE
	# 出せる段の周期が範囲外なら画面全体を文字にする（C1）
	if normal_calendar != null and not masters.normal.is_displayable():
		return LoginBonusScreen.FallbackReason.CYCLE_OUT_OF_RANGE
	if vip_calendar != null and not masters.vip.is_displayable():
		return LoginBonusScreen.FallbackReason.CYCLE_OUT_OF_RANGE
	return LoginBonusScreen.FallbackReason.NONE


func _build_stage(
	calendar: LoginBonusCalendar,
	master: LoginBonusStageMaster,
	is_vip: bool,
	play_stamp_allowed: bool
) -> CalendarStageView:
	var stage := CalendarStageView.new()
	stage.is_vip = is_vip
	stage.vip_level = calendar.vip_level if is_vip else 0
	stage.cycle_days = master.cycle_days
	stage.is_today_stage = (
		calendar.is_granted_today
		and calendar.last_day >= 1
		and calendar.last_day <= master.cycle_days
	)
	for day in master.days:
		stage.cells.append(_build_cell(day, calendar, stage.is_today_stage, play_stamp_allowed))
	return stage


func _build_cell(
	day: LoginBonusCalendarDay,
	calendar: LoginBonusCalendar,
	is_today_stage: bool,
	play_stamp_allowed: bool
) -> CalendarCellView:
	var cell := CalendarCellView.new()
	cell.day = day.day
	# --- 状態 ---
	if not is_today_stage:
		cell.state = CalendarCellView.State.NEUTRAL
	elif day.day == calendar.last_day:
		cell.state = CalendarCellView.State.TODAY
		cell.play_stamp = calendar.is_granted_now and play_stamp_allowed
	elif day.day < calendar.last_day:
		cell.state = CalendarCellView.State.RECEIVED
	else:
		cell.state = CalendarCellView.State.FUTURE
	# --- 報酬（マスターの並びのまま。先頭が絵と数量、残りは「＋n」）---
	for reward in day.rewards:
		cell.rewards.append(_get_displays.display_of(reward))
	cell.is_empty = cell.rewards.is_empty()
	if not cell.is_empty:
		var first := cell.rewards[0]
		cell.icon_type = first.icon_type
		cell.icon_id = first.bonus.id
		cell.icon_mst_item_type = first.item_type
		cell.quantity = first.bonus.amount
		cell.extra_count = cell.rewards.size() - 1
	return cell
