## LocalMstLoginBonusRepository・LocalMstVipLoginBonusRepository の単体テスト（SQLite を実際に使う。
## client_design.md 2-1・2-4・9 節）。本体と報酬行は「テーブルごとに別の SQLite ファイル」で作る。
extends GdUnitTestSuite

const WORK_DIR := "user://test_login_bonus_master/"

## 実スキーマの列（サーバーのマイグレーションと同じ並び。通常の本体・報酬行は deploy_key あり）
const NORMAL_INS := "INSERT INTO mst_login_bonus_content VALUES "
const VIP_INS := "INSERT INTO mst_vip_login_bonus_content VALUES "
const NORMAL_BODY := (
	"CREATE TABLE mst_login_bonus (deploy_key INTEGER, id TEXT PRIMARY KEY, " + "loop_days INTEGER)"
)
const NORMAL_CONTENT := (
	"CREATE TABLE mst_login_bonus_content (deploy_key INTEGER, mst_login_bonus_id TEXT, day INTEGER, "
	+ "content_type TEXT, content_mst_id TEXT, content_option TEXT, content_quantity INTEGER, "
	+ "amount INTEGER, is_paid INTEGER, sort_desc INTEGER)"
)
## VIP は本体にも報酬行にも deploy_key が無い。報酬行は id（文字列）あり・is_paid なし
const VIP_BODY := (
	"CREATE TABLE mst_vip_login_bonus (id TEXT PRIMARY KEY, vip_level INTEGER, "
	+ "loop_days INTEGER)"
)
const VIP_CONTENT := (
	"CREATE TABLE mst_vip_login_bonus_content (id TEXT PRIMARY KEY, "
	+ "mst_vip_login_bonus_id TEXT, day INTEGER, content_type TEXT, content_mst_id TEXT, "
	+ "content_option TEXT, content_quantity INTEGER, amount INTEGER, sort_desc INTEGER)"
)

var _database: MasterDatabase


func before_test() -> void:
	_remove_dir(WORK_DIR)
	_database = MasterDatabase.new()


func after_test() -> void:
	_database.close_all()
	_remove_dir(WORK_DIR)


## 更新 DB を開く。extra は {テーブル名: ファイル}（必須 3 テーブルは同梱用の base に入れる）。
func _open(extra: Dictionary) -> void:
	var base := WORK_DIR + "base.db"
	assert_bool(SqliteTestHelper.create_master_db(base)).is_true()
	var files := {"mst_gacha": base, "mst_unit": base, "mst_equipment": base}
	files.merge(extra)
	assert_bool(_database.open_downloaded(files)).is_true()


func _make(file_name: String, statements: Array) -> String:
	var path := WORK_DIR + file_name
	assert_bool(SqliteTestHelper.create_db(path, statements)).is_true()
	return path


func _open_normal(
	content_rows: Array, loop_days: int = 7, content_ddl: String = NORMAL_CONTENT
) -> void:
	var body := _make(
		"normal_body.db",
		[NORMAL_BODY, "INSERT INTO mst_login_bonus VALUES (1, 'lb1', %d)" % loop_days]
	)
	var content := _make("normal_content.db", [content_ddl] + content_rows)
	_open({"mst_login_bonus": body, "mst_login_bonus_content": content})


func _open_vip(content_rows: Array) -> void:
	var body := _make(
		"vip_body.db", [VIP_BODY, "INSERT INTO mst_vip_login_bonus VALUES ('vip5', 5, 7)"]
	)
	var content := _make("vip_content.db", [VIP_CONTENT] + content_rows)
	_open({"mst_vip_login_bonus": body, "mst_vip_login_bonus_content": content})


# ---------------------------------------------------------------- 通常 ----


## 前提: 別ファイルの本体と報酬行。期待: 引ける（FOUND）。loop_days・列が読める。
func test_normal_finds_body_and_contents() -> void:
	_open_normal(
		[NORMAL_INS + "(1, 'lb1', 1, 'item', 'free_diamond', '{\"grade\":2}', 100, 3, 1, 5)"]
	)
	var lookup := LocalMstLoginBonusRepository.new(_database).find_by_id("lb1")
	assert_int(lookup.status).is_equal(MstLookupStatus.Status.FOUND)
	assert_int(lookup.bonus.loop_days).is_equal(7)
	assert_int(lookup.bonus.deploy_key).is_equal(1)
	var content := lookup.bonus.contents[0]
	assert_str(content.content_type).is_equal("item")
	assert_str(content.content_mst_id).is_equal("free_diamond")
	assert_int(int(content.content_option["grade"])).is_equal(2)
	assert_bool(content.is_paid).is_true()
	assert_int(content.sort_desc).is_equal(5)
	# 数量は content_quantity × amount（100 × 3）
	assert_int(content.total_quantity()).is_equal(300)


## 前提: 同じ日に sort_desc の異なる行・同値の行。
## 期待: day 昇順 → sort_desc 降順 → 同値は content_type → content_mst_id の昇順。
func test_normal_order_by_day_sort_desc_then_type_and_id() -> void:
	_open_normal(
		[
			NORMAL_INS + "(1, 'lb1', 2, 'item', 'b', NULL, 1, 1, 0, 1)",
			NORMAL_INS + "(1, 'lb1', 1, 'item', 'z', NULL, 1, 1, 0, 1)",
			NORMAL_INS + "(1, 'lb1', 1, 'wallet', 'a', NULL, 1, 1, 0, 1)",
			NORMAL_INS + "(1, 'lb1', 1, 'item', 'a', NULL, 1, 1, 0, 1)",
			NORMAL_INS + "(1, 'lb1', 1, 'unit', 'big', NULL, 1, 1, 0, 9)",
		]
	)
	var contents := LocalMstLoginBonusRepository.new(_database).get_by_id("lb1").contents
	var keys: Array[String] = []
	for content in contents:
		keys.append("%d:%s:%s" % [content.day, content.content_type, content.content_mst_id])
	assert_array(keys).contains_exactly(
		["1:unit:big", "1:item:a", "1:item:z", "1:wallet:a", "2:item:b"]
	)


## 前提: content_option が壊れた JSON・NULL・配列の JSON、数量が NULL。期待: 落ちずに既定値（空の辞書・0）。
func test_normal_broken_option_and_null_columns_use_defaults() -> void:
	_open_normal(
		[
			NORMAL_INS + "(1, 'lb1', 1, 'item', 'a', '{broken', NULL, NULL, NULL, NULL)",
			NORMAL_INS + "(1, 'lb1', 2, 'item', 'b', '[1,2]', 1, 1, 0, 0)",
		]
	)
	var contents := LocalMstLoginBonusRepository.new(_database).get_by_id("lb1").contents
	assert_dict(contents[0].content_option).is_empty()
	assert_int(contents[0].total_quantity()).is_equal(0)
	assert_bool(contents[0].is_paid).is_false()
	assert_dict(contents[1].content_option).is_empty()


## 前提: その ID が無い。期待: NOT_FOUND（get_by_id は null）。
func test_normal_unknown_id_is_not_found() -> void:
	_open_normal([])
	var repository := LocalMstLoginBonusRepository.new(_database)
	assert_int(repository.find_by_id("nope").status).is_equal(MstLookupStatus.Status.NOT_FOUND)
	assert_object(repository.get_by_id("nope")).is_null()


## 前提: テーブルが配信されていない・DB 未オープン。期待: UNREADABLE（null。例外にしない）。
func test_normal_without_table_or_database_is_unreadable() -> void:
	_open({})
	var repository := LocalMstLoginBonusRepository.new(_database)
	assert_int(repository.find_by_id("lb1").status).is_equal(MstLookupStatus.Status.UNREADABLE)
	assert_object(repository.get_by_id("lb1")).is_null()
	var unopened := LocalMstLoginBonusRepository.new(MasterDatabase.new())
	assert_int(unopened.find_by_id("lb1").status).is_equal(MstLookupStatus.Status.UNREADABLE)


## 前提: sort_desc の列が無い古い配信ファイルの報酬行。期待: UNREADABLE（空配列の「行なし」と区別される）。
func test_normal_content_without_sort_desc_column_is_unreadable() -> void:
	var old_ddl := (
		"CREATE TABLE mst_login_bonus_content (deploy_key INTEGER, mst_login_bonus_id TEXT, day INTEGER, "
		+ "content_type TEXT, content_mst_id TEXT, content_option TEXT, content_quantity INTEGER, "
		+ "amount INTEGER, is_paid INTEGER)"
	)
	_open_normal([NORMAL_INS + "(1, 'lb1', 1, 'item', 'a', NULL, 1, 1, 0)"], 7, old_ddl)
	var lookup := LocalMstLoginBonusRepository.new(_database).find_by_id("lb1")
	assert_int(lookup.status).is_equal(MstLookupStatus.Status.UNREADABLE)
	assert_object(lookup.bonus).is_null()


# ---------------------------------------------------------------- VIP ----


## 前提: deploy_key の無い VIP の 2 テーブル。期待: 引ける（deploy_key の列に依存しない）。数量は × 倍率。
func test_vip_reads_without_deploy_key_column() -> void:
	_open_vip(
		[
			(
				VIP_INS
				+ "('vip5:1:item:free_diamond', 'vip5', 1, 'item', 'free_diamond', NULL, 50, 4, 0)"
			)
		]
	)
	var lookup := LocalMstVipLoginBonusRepository.new(_database).find_by_id("vip5")
	assert_int(lookup.status).is_equal(MstLookupStatus.Status.FOUND)
	assert_int(lookup.bonus.vip_level).is_equal(5)
	assert_int(lookup.bonus.loop_days).is_equal(7)
	assert_int(lookup.bonus.contents[0].total_quantity()).is_equal(200)
	assert_str(lookup.bonus.contents[0].id).is_equal("vip5:1:item:free_diamond")


## 前提: 同じ日に sort_desc 同値の行を id の逆順に近い形で入れる。期待: day → sort_desc 降順 → id 昇順。
func test_vip_order_by_day_sort_desc_then_id() -> void:
	_open_vip(
		[
			VIP_INS + "('vip5:2:item:x', 'vip5', 2, 'item', 'x', NULL, 1, 1, 0)",
			# 同値の 2 行は id 昇順（first < second）の逆順に入れ、ORDER BY の id ASC が効くことを確かめる
			VIP_INS + "('vip5:1:item:second', 'vip5', 1, 'item', 'second', NULL, 1, 1, 3)",
			VIP_INS + "('vip5:1:item:first', 'vip5', 1, 'item', 'first', NULL, 1, 1, 3)",
			VIP_INS + "('vip5:1:item:top', 'vip5', 1, 'item', 'top', NULL, 1, 1, 8)",
		]
	)
	var contents := LocalMstVipLoginBonusRepository.new(_database).get_by_id("vip5").contents
	var ids: Array[String] = []
	for content in contents:
		ids.append(content.content_mst_id)
	assert_array(ids).contains_exactly(["top", "first", "second", "x"])


## 前提: ID なし・テーブルなし・sort_desc なしの報酬行。期待: NOT_FOUND・UNREADABLE の区別。
func test_vip_not_found_and_unreadable() -> void:
	_open_vip([])
	var repository := LocalMstVipLoginBonusRepository.new(_database)
	assert_int(repository.find_by_id("nope").status).is_equal(MstLookupStatus.Status.NOT_FOUND)
	assert_object(repository.get_by_id("nope")).is_null()
	var unopened := LocalMstVipLoginBonusRepository.new(MasterDatabase.new())
	assert_int(unopened.find_by_id("vip5").status).is_equal(MstLookupStatus.Status.UNREADABLE)


func test_vip_content_without_sort_desc_column_is_unreadable() -> void:
	var body := _make(
		"vip_body.db", [VIP_BODY, "INSERT INTO mst_vip_login_bonus VALUES ('vip5', 5, 7)"]
	)
	var content := _make(
		"vip_content_old.db",
		[
			(
				"CREATE TABLE mst_vip_login_bonus_content (id TEXT PRIMARY KEY, "
				+ "mst_vip_login_bonus_id TEXT, "
				+ "day INTEGER, content_type TEXT, content_mst_id TEXT, content_option TEXT, "
				+ "content_quantity INTEGER, amount INTEGER)"
			)
		]
	)
	_open({"mst_vip_login_bonus": body, "mst_vip_login_bonus_content": content})
	var lookup := LocalMstVipLoginBonusRepository.new(_database).find_by_id("vip5")
	assert_int(lookup.status).is_equal(MstLookupStatus.Status.UNREADABLE)


func _remove_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
