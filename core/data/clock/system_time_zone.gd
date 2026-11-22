## 端末のタイムゾーンを返す TimeZoneSource の実装（background-moon-phase client_design 2-1）。
##
## 実装: `Time.get_time_zone_from_system()` の `name`（略称）と `bias`（分）。
## why: `Time` を触るのはここだけにして、domain（Hemisphere・UseCase）を `Time` から切り離す。
##       値は呼ぶたびに取り直す（旅行・手動設定で変わっても次に画面を開いたときに反映するため）。
class_name SystemTimeZone
extends TimeZoneSource


func zone_name() -> String:
	return str(Time.get_time_zone_from_system().get("name", ""))


func bias_minutes() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0))
