## 端末のタイムゾーン情報を返す契約（background-moon-phase client_design 2-1）。
##
## 目的: 半球の判定が `Time` を直接呼ばず、この契約を通してタイムゾーンを得る（Clock と同じ形）。
##       テストは偽の実装に差し替え、環境に依存せず期待値を固定できる。
## 実装: core/data/clock/system_time_zone.gd（Time.get_time_zone_from_system の値）。
class_name TimeZoneSource
extends RefCounted


## タイムゾーンの名前（略称。IANA 名ではない。取れない・数字の略称のこともある）。
func zone_name() -> String:
	push_error("未実装: TimeZoneSource.zone_name")
	return ""


## UTC からの差（分。東が正。夏時間を含む現在の値）。
func bias_minutes() -> int:
	push_error("未実装: TimeZoneSource.bias_minutes")
	return 0
