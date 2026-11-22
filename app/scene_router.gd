## 画面遷移（architecture.md 3 節 app、client_design.md 2-1）。オートロード `SceneRouter`。
##
## 目的: 画面（シーン）のパスを 1 か所に集め、presenter が `SceneRouter.goto_*()` で遷移できるようにする。
##       遷移先はコンテキストの presentation のシーン。
## 流れ: タイトル → 規約 → ログインボーナス → ホーム ⇄ ログインボーナス（ホームから）（login が成功するまで先へ進まない。遷移の判断は各 presenter）。
## 注意:
##   - オートロードなので class_name を付けない（依存チェック L1）。_ready で他のオートロードを呼ばない。
##   - 現在のシーンの管理はエンジンの SceneTree.change_scene_to_file に任せる。旧 SceneManager は
##     _ready で「ルートの最後の子」を現在のシーンと決めていたが、オートロードの _ready 時点では
##     まだメインシーンが無く、別のノードを指してしまうため廃止した。
extends Node

const TITLE_SCENE := "res://contexts/auth/presentation/title/title.tscn"
const AGREEMENT_SCENE := "res://contexts/agreement/presentation/agreement/agreement.tscn"
const LOGIN_BONUS_SCENE := "res://contexts/login/presentation/login_bonus/login_bonus.tscn"
## ホームの「ログインボーナス」ボタンから開く入口（FROM_HOME。login_bonus.tscn の継承シーンで entry だけ違う。1-1）
const LOGIN_BONUS_FROM_HOME_SCENE := (
	"res://contexts/login/presentation/login_bonus/" + "login_bonus_from_home.tscn"
)
const HOME_SCENE := "res://contexts/player/presentation/home/home.tscn"


## 指定のシーンへ切り替える。切り替えはエンジンが現在のフレームの後に行うので、
## 呼び出し元の presenter が実行中でも安全（自分自身を解放しながら動き続けない）。
func change_scene(scene_path: String) -> void:
	print("シーンを変更: ", scene_path)
	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("シーンの切り替えに失敗: %s (error=%d)" % [scene_path, error])


## タイトル画面へ（セッションが無効になったとき。最初からやり直す）
func goto_title() -> void:
	change_scene(TITLE_SCENE)


## 利用規約同意画面へ
func goto_agreement() -> void:
	change_scene(AGREEMENT_SCENE)


## ログインボーナス画面へ
func goto_login_bonus() -> void:
	change_scene(LOGIN_BONUS_SCENE)


## ログインボーナス画面へ（ホームのボタンから。開くたびに POST /login_bonus/list で状態を取る）
func goto_login_bonus_from_home() -> void:
	change_scene(LOGIN_BONUS_FROM_HOME_SCENE)


## ホーム画面へ
func goto_home() -> void:
	change_scene(HOME_SCENE)
