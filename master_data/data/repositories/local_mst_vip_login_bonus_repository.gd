## VIP ログインボーナスのマスターを SQLite から読む（MstVipLoginBonusRepository の実装）。
##
## 流れは LocalMstLoginBonusRepository と同じ（本体 → 報酬行の 2 回。失敗と 0 件を区別する）。
## 違い: VIP の 2 テーブルには deploy_key が無いので、SELECT に含めない（通常の COLUMNS を流用すると
##       「no such column」で全件が引けなくなる）。報酬行には id（文字列。値は解釈しない）があり、is_paid は無い。
## 並び: ORDER BY day, sort_desc DESC, id ASC（同値は id 昇順）。キャッシュは持たない。
class_name LocalMstVipLoginBonusRepository
extends MstVipLoginBonusRepository

const TABLE := "mst_vip_login_bonus"
const CONTENT_TABLE := "mst_vip_login_bonus_content"
const COLUMNS := "id, vip_level, loop_days"
const CONTENT_COLUMNS := (
	"id, mst_vip_login_bonus_id, day, content_type, content_mst_id, content_option, "
	+ "content_quantity, amount, sort_desc"
)

var _database: MasterDatabase


func _init(database: MasterDatabase) -> void:
	_database = database


func find_by_id(id: String) -> MstVipLoginBonusLookup:
	# --- 1. 本体 ---
	var sql := "SELECT %s FROM %s WHERE id = ? LIMIT 1" % [COLUMNS, TABLE]
	var body := _database.try_select_rows(TABLE, sql, [id])
	if not body.ok:
		return MstVipLoginBonusLookup.new(MstLookupStatus.Status.UNREADABLE)
	if body.rows.is_empty():
		return MstVipLoginBonusLookup.new(MstLookupStatus.Status.NOT_FOUND)
	var row: Dictionary = body.rows[0]
	var bonus := MstVipLoginBonus.new()
	bonus.id = MstRowReader.get_string(row, "id")
	bonus.vip_level = MstRowReader.get_int(row, "vip_level")
	bonus.loop_days = MstRowReader.get_int(row, "loop_days")

	# --- 2. 報酬行（別の SQLite ファイル）---
	var content_sql := (
		"SELECT %s FROM %s WHERE mst_vip_login_bonus_id = ? ORDER BY day, sort_desc DESC, id ASC"
		% [CONTENT_COLUMNS, CONTENT_TABLE]
	)
	var contents := _database.try_select_rows(CONTENT_TABLE, content_sql, [id])
	if not contents.ok:
		return MstVipLoginBonusLookup.new(MstLookupStatus.Status.UNREADABLE)
	for raw in contents.rows:
		bonus.contents.append(_row_to_content(raw))
	return MstVipLoginBonusLookup.new(MstLookupStatus.Status.FOUND, bonus)


func _row_to_content(row: Dictionary) -> MstVipLoginBonusContent:
	var content := MstVipLoginBonusContent.new()
	content.id = MstRowReader.get_string(row, "id")
	content.mst_vip_login_bonus_id = MstRowReader.get_string(row, "mst_vip_login_bonus_id")
	content.day = MstRowReader.get_int(row, "day")
	content.content_type = MstRowReader.get_string(row, "content_type")
	content.content_mst_id = MstRowReader.get_string(row, "content_mst_id")
	content.content_option = MstRowReader.get_json_dict(row, "content_option")
	content.content_quantity = MstRowReader.get_int(row, "content_quantity")
	content.amount = MstRowReader.get_int(row, "amount")
	content.sort_desc = MstRowReader.get_int(row, "sort_desc")
	return content
