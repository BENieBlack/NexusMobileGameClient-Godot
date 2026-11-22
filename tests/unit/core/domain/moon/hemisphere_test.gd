## Hemisphere（半球の判定）の単体テスト（client_design 4-2・8 節）。
##
## 方針: 確定表の全行が南になること、北になる例（赤道付近・表に無い bias・判別不能）、
##       名前と bias の組み合わせの優先を固定する。
extends GdUnitTestSuite


## 前提: 南の略称（表の全行）、bias は北の値（0）。期待: 南。
func test_south_names() -> void:
	for n in Hemisphere.SOUTH_NAMES:
		assert_int(Hemisphere.detect(n, 0)).is_equal(Hemisphere.Kind.SOUTH)


## 前提: IANA 名の形で南の接頭辞。期待: 南。
func test_south_name_prefixes() -> void:
	assert_int(Hemisphere.detect("Australia/Sydney", 0)).is_equal(Hemisphere.Kind.SOUTH)
	assert_int(Hemisphere.detect("Antarctica/Troll", 0)).is_equal(Hemisphere.Kind.SOUTH)


## 前提: 名前は不明、bias が南の確定表（全行）。期待: 南。
func test_south_bias() -> void:
	for b in Hemisphere.SOUTH_BIAS_MINUTES:
		assert_int(Hemisphere.detect("", b)).is_equal(Hemisphere.Kind.SOUTH)


## 前提: 北・赤道付近・表に無い値。期待: 北（-03 は表に無い）。
func test_north_cases() -> void:
	assert_int(Hemisphere.detect("JST", 540)).is_equal(Hemisphere.Kind.NORTH)
	assert_int(Hemisphere.detect("GMT", 0)).is_equal(Hemisphere.Kind.NORTH)
	assert_int(Hemisphere.detect("EAT", 180)).is_equal(Hemisphere.Kind.NORTH)
	assert_int(Hemisphere.detect("-03", -180)).is_equal(Hemisphere.Kind.NORTH)
	assert_int(Hemisphere.detect("EST", -300)).is_equal(Hemisphere.Kind.NORTH)


## 前提: 名前が空・不明、bias が表に無い。期待: 北（判別不能は北）。
func test_undetermined_is_north() -> void:
	assert_int(Hemisphere.detect("", 0)).is_equal(Hemisphere.Kind.NORTH)
	assert_int(Hemisphere.detect("XYZ", 123)).is_equal(Hemisphere.Kind.NORTH)


## 前提: 南北が混在する bias（+10・+11・+12 時間）で、名前は表に当たらない。期待: 北。
func test_mixed_bias_is_north() -> void:
	for b in [600, 660, 720]:
		assert_int(Hemisphere.detect("", b)).is_equal(Hemisphere.Kind.NORTH)
		assert_int(Hemisphere.detect("VLAT", b)).is_equal(Hemisphere.Kind.NORTH)


## 前提: 名前が南の表に当たる。期待: bias が北寄りでも南。名前が当たらず bias が表に当たれば南。
func test_name_and_bias_combination() -> void:
	assert_int(Hemisphere.detect("AEST", 540)).is_equal(Hemisphere.Kind.SOUTH)
	assert_int(Hemisphere.detect("XYZ", 570)).is_equal(Hemisphere.Kind.SOUTH)
