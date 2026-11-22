"""check_dependencies.py のテスト。一時ディレクトリに最小の新構成ツリーを作って検査する。

流れ（各テスト共通）:
  1. 一時ディレクトリに project.godot と .gd ファイルを書いて、小さなプロジェクトを作る
  2. check_dependencies.run_check（または main）を実行する
  3. 出た違反のルール ID（D1 など）が期待と一致するか確かめる

構成:
  CleanTree : 正しい構成・対象外・除去処理で「違反が出ないこと」を守る（誤検出の防止）
  Rules     : ルール ID ごとに「違反が出ること」を守る（検出漏れの防止）。
              同じ Rules の中に、各ルールの「許可される側」のテストも置いて境界を固定する

実行: python3 -m unittest discover -s tools/tests（make check-deps が先に実行する）
"""
import os
import sys
import tempfile
import unittest

# tools/ は Python パッケージではないので、1 つ上のディレクトリを探索パスに足して直接 import する
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import check_dependencies as cd  # noqa: E402


class Case(unittest.TestCase):
    """テスト共通の道具。テストごとに空の一時ディレクトリを root として用意し、終了時に消す。"""

    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = self._tmp.name
        self.addCleanup(self._tmp.cleanup)

    def write(self, rel, text):
        """root からの相対パス rel に text を書く（途中のディレクトリも作る）。"""
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(text)

    def project(self, autoloads=""):
        """project.godot を作る。autoloads は [autoload] 節の中身（例: 'AppContext="*res://app/app_context.gd"\\n'）。"""
        self.write("project.godot", "[autoload]\n\n" + autoloads + "\n[display]\n")

    def rules(self):
        """検査して、出た違反のルール ID を重複なし・ソート済みで返す（assertIn 用）。"""
        return sorted(set(v.rule for v in cd.run_check(self.root).violations))

    def assert_rules(self, expected):
        """出た違反のルール ID の集合が expected と等しいことを確かめる。

        expected が [] なら「違反なし」。失敗時は違反の (パス, 行, ルール) を表示して原因を追えるようにする。
        件数でなく集合で比べるのは、同じルールが複数行で出ても 1 つのルールの検出として扱うため。
        """
        report = cd.run_check(self.root)
        self.assertEqual(sorted(expected), sorted(set(v.rule for v in report.violations)),
                         [(v.path, v.line, v.rule) for v in report.violations])


class CleanTree(Case):
    """違反が出てはいけないケース（誤検出の防止）。"""

    def test_valid_tree_passes(self):
        """前提: 3 層・コンテキスト間・master_data・core・オートロードの許可された参照だけで組んだツリー。
        期待: 違反 0 件。許可される参照を誤って違反にしない（誤検出の防止）。
        この 1 本が通ることで、各ルールが「許可側」を壊していないことを広く確かめる。"""
        self.project('AppContext="*res://app/app_context.gd"\nEventBus="*res://core/domain/event_bus.gd"\n')
        self.write("app/app_context.gd", "extends Node\nvar r = AuthApiRepository.new()\n")
        self.write("core/domain/result.gd", "class_name Result\nextends RefCounted\n")
        self.write("core/domain/event_bus.gd", "extends Node\n")
        self.write("core/data/http/api_client.gd", "class_name ApiClient\nextends RefCounted\nvar r: Result\n")
        self.write("core/presentation/toast.gd", "extends CanvasLayer\nfunc f(): EventBus.x()\n")
        self.write("master_data/domain/mst_repository.gd", "class_name MstRepository\nextends RefCounted\n")
        self.write("master_data/data/sqlite_mst_repository.gd",
                   "class_name SqliteMstRepository\nextends MstRepository\nvar c: ApiClient\n")
        self.write("contexts/auth/domain/repositories/auth_repository.gd",
                   "class_name AuthRepository\nextends RefCounted\nvar m: MstRepository\nvar r: Result\n")
        self.write("contexts/auth/domain/use_cases/authenticate_use_case.gd",
                   "class_name AuthenticateUseCase\nextends RefCounted\nvar r: AuthRepository\n")
        self.write("contexts/auth/data/repositories/auth_api_repository.gd",
                   "class_name AuthApiRepository\nextends AuthRepository\nvar c: ApiClient\n")
        self.write("contexts/login/domain/use_cases/login_use_case.gd",
                   "class_name LoginUseCase\nextends RefCounted\nvar a: AuthenticateUseCase\n")
        self.write("contexts/auth/presentation/title/title_presenter.gd",
                   'class_name TitlePresenter\nextends Control\n'
                   'const S = preload("res://contexts/auth/presentation/title/title.tscn")\n'
                   "func f():\n\tAppContext.x()\n\tSceneRouter.go()\n\tvar u: LoginUseCase\n\tvar a: AuthenticateUseCase\n\tvar r: Result\n")
        self.write("tests/unit/foo_test.gd", "extends GdUnitTestSuite\nvar a = AppContext\nvar b = AuthApiRepository\n")
        self.write("debug/x.gd", "extends Node\nvar a = AppContext\n")
        self.assert_rules([])

    def test_files_outside_check_dirs_are_skipped_and_counted(self):
        """前提: 検査対象外のトップディレクトリ（other/ extra/）に、本来なら違反になる内容（HTTPRequest）を持つファイルが 2 つある。
        期待: 違反は出ず、skipped が 2。対象外のディレクトリは検査せず、数だけ表示する。"""
        self.project()
        self.write("other/a.gd", "class_name Other\nextends Node\nvar x = HTTPRequest\n")
        self.write("extra/b/b.gd", "extends Node\n")
        report = cd.run_check(self.root)
        self.assertEqual([], report.violations)
        self.assertEqual(2, report.skipped)

    def test_comments_and_strings_are_ignored(self):
        """前提: domain のファイルで、禁止された語（HTTPRequest・get_tree・参照先の class_name）が
        コメント・文字列・三連引用符の中にだけある。
        期待: 違反 0 件。sanitize が除去できていないと、コメントを書いただけで誤検出になる。"""
        self.project()
        self.write("contexts/a/domain/x.gd",
                   '# HTTPRequest get_tree() FileAccess\nvar s = "HTTPRequest AuthApiRepository"\n'
                   'var t = """\nSceneTree\n"""\n')
        self.assert_rules([])

    def test_main_exit_codes(self):
        """前提: 空のプロジェクト、のちに domain が Node を継承するファイルを足したプロジェクト。
        期待: main の終了コードが 違反なし=0、違反あり=1。CI が失敗を検知できる前提を守る。"""
        self.project()
        self.assertEqual(0, cd.main(["--root", self.root]))
        self.write("contexts/a/domain/x.gd", "extends Node\n")
        self.assertEqual(1, cd.main(["--root", self.root]))


class Rules(Case):
    """ルール ID ごとの検出と、その許可側の境界を確かめる。

    setUp の部品（下の write）は、コンテキスト a・b と master_data・core の最小の登場人物。
    各テストはここに「違反するファイル」を 1 つ足し、期待するルールだけが出るかを見る。
    """

    def setUp(self):
        # 登場人物（名前はテスト本文で参照される）:
        #   AApiRepository / PPresenter : コンテキスト a の data / presentation
        #   BUseCase / BEntity          : コンテキスト b の domain/use_cases（公開）/ domain/entities（非公開）
        #   MData / MDom                : master_data の data / domain
        #   CData / CDom                : core の data / domain
        # オートロードは AppContext だけ（app/app_context.gd）
        super().setUp()
        self.project('AppContext="*res://app/app_context.gd"\n')
        self.write("app/app_context.gd", "extends Node\n")
        self.write("contexts/a/data/repositories/a_api_repository.gd",
                   "class_name AApiRepository\nextends RefCounted\n")
        self.write("contexts/a/presentation/p/p_presenter.gd", "class_name PPresenter\nextends Control\n")
        self.write("contexts/b/domain/use_cases/b_use_case.gd", "class_name BUseCase\nextends RefCounted\n")
        self.write("contexts/b/domain/entities/b_entity.gd", "class_name BEntity\nextends RefCounted\n")
        self.write("master_data/data/m_data.gd", "class_name MData\nextends RefCounted\n")
        self.write("master_data/domain/m_dom.gd", "class_name MDom\nextends RefCounted\n")
        self.write("core/data/c_data.gd", "class_name CData\nextends RefCounted\n")
        self.write("core/domain/c_dom.gd", "class_name CDom\nextends RefCounted\n")

    def test_d1_domain_refs_data(self):
        """前提: domain が data の class_name（AApiRepository）を型に使う。
        期待: D1。識別子による参照も検出できること。"""
        self.write("contexts/a/domain/x.gd", "extends RefCounted\nvar r: AApiRepository\n")
        self.assert_rules(["D1"])

    def test_d1_domain_refs_presentation_by_path(self):
        """前提: domain が presentation のスクリプトを preload する。
        期待: D1。パス（preload）による参照も検出できること。"""
        self.write("contexts/a/domain/x.gd",
                   'extends RefCounted\nconst P = preload("res://contexts/a/presentation/p/p_presenter.gd")\n')
        self.assert_rules(["D1"])

    def test_d2_extends_node(self):
        """前提: domain が Node を直接継承する。 期待: D2。"""
        self.write("contexts/a/domain/x.gd", "extends Node\n")
        self.assert_rules(["D2"])

    def test_d2_extends_chain_via_class(self):
        """前提: domain が、Node2D を継承する自作クラス（BaseNode）を継承する。
        期待: D2。直接でなく継承の連鎖の先で Node 系になるものを見逃さない。"""
        self.write("core/domain/base_node.gd", "class_name BaseNode\nextends Node2D\n")
        self.write("contexts/a/domain/x.gd", "extends BaseNode\n")
        self.assert_rules(["D2"])

    def test_d2_engine_identifiers_and_get_tree(self):
        """前提: master_data/domain が HTTPRequest を使い、get_tree() も呼ぶ。
        期待: D2 が 2 件（型の使用と get_tree() を別々に報告する）。"""
        self.write("master_data/domain/x.gd", "extends RefCounted\nvar h = HTTPRequest.new()\nfunc f():\n\tget_tree()\n")
        report = cd.run_check(self.root)
        self.assertEqual(["D2", "D2"], [v.rule for v in report.violations])

    def test_d2_tscn(self):
        """前提: domain が .tscn を preload する。
        期待: D2。Node を継承しなくても、シーンへの依存はエンジン依存になる。"""
        self.write("core/domain/x.gd", 'extends RefCounted\nconst S = preload("res://core/presentation/t.tscn")\n')
        self.assertIn("D2", self.rules())

    def test_p1_presentation_refs_data(self):
        """前提: 同じコンテキストの presentation が data の Repository 実装を参照する。 期待: P1。"""
        self.write("contexts/a/presentation/p/q_presenter.gd",
                   "class_name QPresenter\nextends Control\nvar r: AApiRepository\n")
        self.assert_rules(["P1"])

    def test_p1_presentation_refs_core_data(self):
        """前提: presentation が core/data を参照する。
        期待: P1。同じコンテキスト内に限らず、data 層全般が対象であること。"""
        self.write("contexts/a/presentation/p/q_presenter.gd", "class_name QPresenter\nextends Control\nvar r: CData\n")
        self.assert_rules(["P1"])

    def test_p2_and_x1_presentation_other_context_entity(self):
        """前提: presentation が他コンテキストの entity（use_cases 以外）を参照する。
        期待: P2 と X1 の両方（presentation 側の規則とコンテキスト間の規則を両方破っている）。"""
        self.write("contexts/a/presentation/p/q_presenter.gd",
                   "class_name QPresenter\nextends Control\nvar r: BEntity\n")
        self.assert_rules(["P2", "X1"])

    def test_presentation_other_context_use_case_ok(self):
        """前提: presentation が他コンテキストの UseCase、master_data/domain、core/domain を参照する。
        期待: 違反なし。許可される参照の境界（use_cases は可）を固定する。"""
        self.write("contexts/a/presentation/p/q_presenter.gd",
                   "class_name QPresenter\nextends Control\nvar r: BUseCase\nvar m: MDom\nvar c: CDom\n")
        self.assert_rules([])

    def test_da1_data_refs_presentation(self):
        """前提: data が presentation の class_name を参照する。 期待: Da1。"""
        self.write("contexts/a/data/x.gd", "extends RefCounted\nvar r: PPresenter\n")
        self.assert_rules(["Da1"])

    def test_da1_data_refs_other_context_use_case(self):
        """前提: data が他コンテキストの UseCase を参照する。
        期待: Da1 だけ。UseCase は X1 では許可だが、data からは参照してはならない。"""
        self.write("contexts/a/data/x.gd", "extends RefCounted\nvar r: BUseCase\n")
        self.assert_rules(["Da1"])

    def test_data_allowed_refs(self):
        """前提: data が core/data・core/domain・master_data/domain を参照する。 期待: 違反なし。"""
        self.write("contexts/a/data/x.gd", "extends RefCounted\nvar a: CData\nvar b: CDom\nvar c: MDom\n")
        self.assert_rules([])

    def test_x1_domain_refs_other_context_entity(self):
        """前提: domain が他コンテキストの entity を参照する。 期待: X1（presentation でないので P2 は出ない）。"""
        self.write("contexts/a/domain/x.gd", "extends RefCounted\nvar r: BEntity\n")
        self.assert_rules(["X1"])

    def test_domain_refs_other_context_use_case_ok(self):
        """前提: domain が他コンテキストの UseCase を参照する。 期待: 違反なし。"""
        self.write("contexts/a/domain/x.gd", "extends RefCounted\nvar r: BUseCase\n")
        self.assert_rules([])

    def test_m1_context_refs_master_data(self):
        """前提: contexts の data が master_data/data を参照する。
        期待: M1（master_data は domain だけ参照できる）。"""
        self.write("contexts/a/data/x.gd", "extends RefCounted\nvar r: MData\n")
        self.assert_rules(["M1"])

    def test_m2_master_refs_context(self):
        """前提: master_data が他コンテキストの UseCase を参照する。 期待: M2。"""
        self.write("master_data/domain/x.gd", "extends RefCounted\nvar r: BUseCase\n")
        self.assert_rules(["M2"])

    def test_m2_master_refs_app(self):
        """前提: master_data が app のスクリプトを preload する。
        期待: A1（app 参照は種別を問わず禁止なので、M2 でなく A1 で報告される）。"""
        self.write("master_data/data/x.gd", 'extends RefCounted\nconst A = preload("res://app/app_context.gd")\n')
        self.assert_rules(["A1"])

    def test_master_data_allowed_refs(self):
        """前提: master_data が自分の domain と core を参照する。 期待: 違反なし。"""
        self.write("master_data/data/x.gd", "extends RefCounted\nvar a: MDom\nvar b: CData\nvar c: CDom\n")
        self.assert_rules([])

    def test_c1_core_refs_context_and_master(self):
        """前提: core が contexts と master_data を参照する。 期待: C1 が 2 件。"""
        self.write("core/data/x.gd", "extends RefCounted\nvar a: BUseCase\nvar b: MDom\n")
        report = cd.run_check(self.root)
        self.assertEqual(["C1", "C1"], [v.rule for v in report.violations])

    def test_a1_app_path_from_context(self):
        """前提: contexts の domain が app のスクリプトを preload する。 期待: A1。"""
        self.write("contexts/a/domain/x.gd",
                   'extends RefCounted\nconst A = preload("res://app/app_context.gd")\n')
        self.assert_rules(["A1"])

    def test_a1_autoload_name_from_domain_and_data(self):
        """前提: contexts の domain・data、core の data がオートロード名を使う。
        期待: A1 が 3 件。オートロード名は presentation だけの特権であること。"""
        self.write("contexts/a/domain/x.gd", "extends RefCounted\nvar a = AppContext\n")
        self.write("contexts/a/data/y.gd", "extends RefCounted\nvar a = Toast\n")
        self.write("core/data/z.gd", "extends RefCounted\nvar a = EventBus\n")
        report = cd.run_check(self.root)
        self.assertEqual(["A1", "A1", "A1"], [v.rule for v in report.violations])

    def test_autoload_name_from_presentation_ok(self):
        """前提: contexts と core の presentation がオートロード名を使う。 期待: 違反なし。"""
        self.write("contexts/a/presentation/p/q_presenter.gd",
                   "class_name QPresenter\nextends Control\nvar a = AppContext\nvar b = SceneRouter\n")
        self.write("core/presentation/t.gd", "extends Node\nvar a = EventBus\n")
        self.assert_rules([])

    def test_l1_autoload_with_class_name(self):
        """前提: オートロードに登録したスクリプトが class_name を宣言する。
        期待: L1（Godot の "Class hides an autoload singleton" を事前に防ぐ）。"""
        self.project('SceneRouter="*res://app/scene_router.gd"\n')
        self.write("app/scene_router.gd", "class_name SceneRouter\nextends Node\n")
        self.assert_rules(["L1"])

    def test_n1_placement(self):
        """前提: 接尾辞（_use_case / _presenter / _api_repository / local_*_repository / _response）の
        ファイルを、置いてはならない場所に 5 つ置く。
        期待: N1 が 5 件（接尾辞ごとに検出できる。1 つ漏れても件数でわかる）。"""
        self.write("contexts/a/data/x_use_case.gd", "extends RefCounted\n")
        self.write("contexts/a/domain/y_presenter.gd", "extends RefCounted\n")
        self.write("contexts/a/domain/z_api_repository.gd", "extends RefCounted\n")
        self.write("contexts/a/domain/local_w_repository.gd", "extends RefCounted\n")
        self.write("contexts/a/domain/v_response.gd", "extends RefCounted\n")
        report = cd.run_check(self.root)
        self.assertEqual(["N1"] * 5, [v.rule for v in report.violations])

    def test_n1_shared_use_case_in_core_moon_ok(self):
        """前提: *_use_case.gd を core/domain/moon/ に置く（共有の表示専用 UseCase の例外）。
        期待: 違反なし。"""
        self.write("core/domain/moon/g_use_case.gd", "class_name GUseCase\nextends RefCounted\n")
        self.assert_rules([])

    def test_n1_use_case_in_other_core_dir_ng(self):
        """前提: *_use_case.gd を core/domain/ 直下に置く。 期待: N1（例外は moon/ だけ）。"""
        self.write("core/domain/g_use_case.gd", "class_name GUseCase\nextends RefCounted\n")
        self.assert_rules(["N1"])

    def test_n1_placement_ok(self):
        """前提: local_*_repository と _response を正しい場所（data/repositories・data/api）に置く。
        期待: 違反なし。"""
        self.write("contexts/a/data/repositories/local_t_repository.gd", "class_name LocalTRepository\nextends RefCounted\n")
        self.write("contexts/a/data/api/v_response.gd", "class_name VResponse\nextends RefCounted\n")
        self.assert_rules([])

    def test_n1_class_name_mismatch(self):
        """前提: ファイル名 foo_bar.gd に class_name FooBaz。 期待: N1（パスカルケースと不一致）。"""
        self.write("contexts/a/domain/entities/foo_bar.gd", "class_name FooBaz\nextends RefCounted\n")
        self.assert_rules(["N1"])

    def test_y1_preload_cycle(self):
        """前提: m1.gd と m2.gd が互いを preload する。
        期待: Y1。Godot が解決できない循環を事前に見つける。"""
        self.write("core/domain/m1.gd", 'extends RefCounted\nconst O = preload("res://core/domain/m2.gd")\n')
        self.write("core/domain/m2.gd", 'extends RefCounted\nconst O = preload("res://core/domain/m1.gd")\n')
        self.assert_rules(["Y1"])

    def test_s1_outside_layer(self):
        """前提: core 直下（層ディレクトリの外）にファイルを置く。 期待: S1。"""
        self.write("core/loose.gd", "extends RefCounted\n")
        self.assert_rules(["S1"])

    def test_ref_to_class_outside_check_dirs_is_ignored(self):
        """前提: 新構成の core が、検査対象外のディレクトリ（other/）の class_name を参照する。
        期待: 違反なし。参照先の層が決まらないので読み飛ばす（旧構成のルール O1 は廃止した）。"""
        self.write("other/old.gd", "class_name OtherThing\nextends RefCounted\n")
        self.write("core/domain/x.gd", "extends RefCounted\nvar a: OtherThing\n")
        self.assert_rules([])

    def test_t1_production_refs_tests(self):
        """前提: 本番コード（core）が tests/ のクラスを参照する。 期待: T1。"""
        self.write("tests/helper.gd", "class_name Helper\nextends RefCounted\n")
        self.write("core/domain/x.gd", "extends RefCounted\nvar a: Helper\n")
        self.assert_rules(["T1"])


if __name__ == "__main__":
    unittest.main()
