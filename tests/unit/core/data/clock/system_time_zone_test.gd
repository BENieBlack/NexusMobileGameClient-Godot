## SystemTimeZone の単体テスト。値は環境依存なので、型と Time の値との一致だけを見る。
extends GdUnitTestSuite


## 前提: 端末のタイムゾーン。期待: 名前は String、bias は int で、Time.get_time_zone_from_system と一致する。
func test_matches_time_api() -> void:
	var zone := SystemTimeZone.new()
	var info := Time.get_time_zone_from_system()
	assert_str(zone.zone_name()).is_equal(str(info.get("name", "")))
	assert_int(zone.bias_minutes()).is_equal(int(info.get("bias", 0)))
