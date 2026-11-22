## 画面（presenter）のテスト用の偽物。遷移先（SceneRouter）と通知（Toast）の代わりをする。
##
## 目的: presenter のテストでオートロードの SceneRouter を呼ぶと、テスト中に本当にシーンが切り替わって
##       しまう。呼ばれた遷移・通知を記録するだけの偽物を setup() に渡して、画面の状態遷移だけを検証する。
## 使い方: var router := ScreenTestDoubles.FakeRouter.new() を presenter.setup(...) に渡し、
##       router.calls（"agreement" など）を検証する。
class_name ScreenTestDoubles
extends RefCounted


## SceneRouter の偽物。goto_* が呼ばれた順に、行き先の名前を calls に積む。
class FakeRouter:
	extends RefCounted
	var calls: Array[String] = []

	func goto_title() -> void:
		calls.append("title")

	func goto_agreement() -> void:
		calls.append("agreement")

	func goto_login_bonus() -> void:
		calls.append("login_bonus")

	func goto_login_bonus_from_home() -> void:
		calls.append("login_bonus_from_home")

	func goto_home() -> void:
		calls.append("home")


## Toast の偽物。show_toast の本文と、connect_to_reverb の呼び出し回数・引数を記録する。
class FakeToast:
	extends RefCounted
	var toasts: Array[String] = []
	var reverb_connects: Array[String] = []
	var reverb_endpoints: Array[ReverbEndpoint] = []

	func show_toast(title: String, _body: String, _type: String = "") -> void:
		toasts.append(title)

	func connect_to_reverb(
		user_id: String, _access_token: String, endpoint: ReverbEndpoint
	) -> void:
		reverb_connects.append(user_id)
		reverb_endpoints.append(endpoint)
