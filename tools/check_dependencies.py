#!/usr/bin/env python3
"""クライアントの依存方向チェック（設計の正本は .claude/architecture.md の 2 節・6 節・9 節）。

目的:
  クリーンアーキテクチャ 3 層（presentation → domain ← data）とコンテキスト間の依存ルールを、
  GDScript のソースを静的に読んで機械的に検査する。違反は設計の誤りとして直し、
  検査を緩める抑止コメントは作らない。

使い方:
  python3 tools/check_dependencies.py [--root .]
  （make check-deps / make check から呼ばれる。CI でも同じ）

入出力と終了コード:
  入力  : --root 以下の *.gd と project.godot の [autoload]
  出力  : 違反を 1 行ずつ「パス:行: [ルールID] メッセージ」で標準出力に出し、
          最後に「違反 N 件（検査 N ファイル、検査対象外 N ファイル）」を出す
  終了  : 違反 0 件なら 0、1 件以上なら 1

全体の流れ（run_check が上から順に行う）:
  1. ファイル収集   : collect_files で *.gd を集め、FileInfo に読み込む
                      （この時点でコメント・文字列を除去し、class_name / extends を取り出す）
  2. class_name 表  : 「クラス名 → 定義ファイル」の辞書を作る（参照を解決するため）
  3. 参照の抽出     : extract_refs でファイルごとに「どこが何を参照しているか」を集める
                      （preload / load / extends のパス、class_name の識別子、オートロード名）
  4. 層の判定       : classify で参照元・参照先の置き場所（種別・コンテキスト・層）を決める
  5. ルール適用     : check_ref（参照ごとのルール）、engine_violations（D2）、
                      naming_violations（N1）、S1 / L1 を当てて違反を集める
  6. 循環検出       : preload / extends の依存グラフから find_cycles で循環（Y1）を探す
  7. 出力と終了コード: main が違反を整形して出し、違反があれば 1 を返す

検査の範囲と読み方:
  - 対象はディレクトリ（app/ core/ master_data/ contexts/ tests/ debug/）の *.gd だけ。
    それ以外のトップディレクトリの *.gd は検査せず、検査対象外の数として表示する。
    addons / tools / reports / build は走査自体をしない（SKIP_DIRS）。
    旧構成（scripts/ scenes/）は削除済み。万一戻っても、製品用の複製を作る tools/prepare_release_project.py が
    未分類のトップレベルとして失敗にする（make check-release。make check に含む）ので、ここでは検出しない。
  - 参照は 3 種類を読む: (1) preload / load / extends の res:// パス、
    (2) 全 .gd の class_name（識別子として現れたもの）、(3) project.godot の [autoload] 名。
  - コメントと文字列リテラルの中は参照として数えない（誤検出を避ける。パスの文字列だけは別に拾う）。

ルール ID（architecture.md 2 節「依存ルール」との対応）:
  D1  domain は presentation・data を参照しない            （2 節 向き / domain）
  D2  domain はエンジン依存（Node 系・HTTPRequest・FileAccess・.tscn 等）を持たない （2 節 domain）
  P1  presentation は data を参照しない                    （2 節 向き）
  P2  presentation が参照してよい他コンテキストは domain/use_cases/ だけ （2 節 他コンテキスト）
  Da1 data は presentation と他コンテキストを参照しない    （2 節 向き / 他コンテキスト）
  X1  コンテキスト間は相手の domain/use_cases/ だけ参照できる （2 節 他コンテキスト）
  M1  contexts は master_data/data を参照しない            （2-1 節 contexts → master_data/domain だけ可）
  M2  master_data は contexts を参照しない                 （2-1 節 master_data → contexts 禁止）
  C1  core は contexts・master_data・app を参照しない      （2 節 core）
  A1  app のパス参照は禁止。オートロード名は presentation だけ （2 節 contexts / オートロード）
  L1  [autoload] のスクリプトは class_name を宣言しない    （Godot の制約。下の注記）
  N1  命名（置き場所とファイル名・class_name の対応）      （6 節 命名）
  Y1  preload の循環                                       （Godot は preload の循環を解決できない）
  補助（architecture.md の記述から追加したルール）:
  S1  層ディレクトリ（presentation / domain / data）の外に置かれたファイル （1 節 階層）
  T1  本番コード（app/core/master_data/contexts）が tests/ debug/ を参照している （9 節）
  （O1 は旧構成の参照を検出するルールだった。旧構成の削除に伴い廃止。ID は欠番のまま詰めない）

  L1 の背景: オートロードのスクリプトに class_name を付けると、Godot が
  "Class hides an autoload singleton" のエラーにする（シングルトン名とクラス名が衝突する）。
"""
import argparse
import bisect
import os
import re
import sys
from collections import namedtuple

# 検査対象のトップディレクトリ。これ以外のトップディレクトリの *.gd は検査せず、検査対象外の数だけ数える
CHECK_DIRS = ("app", "core", "master_data", "contexts", "tests", "debug")
# 3 層のディレクトリ名（architecture.md 1 節）。この下に置かれていれば「層が決まった」扱いになる
LAYERS = ("presentation", "domain", "data")
# project.godot に無くても「オートロード名」として扱う名前（architecture.md 2 節のオートロード）。
# テスト用の最小プロジェクトなど、project.godot を用意しない場合でも A1 を検査できるようにする
FIXED_AUTOLOADS = ("AppContext", "SceneRouter", "Toast", "EventBus")
# 走査しないディレクトリ（アドオン・生成物・ツール自身。隠しディレクトリは collect_files で別に除く）
# build/ は make release-project が作る製品用の複製。元のコードの写しなので、走査すると class_name が二重に見える
SKIP_DIRS = {"addons", "node_modules", "reports", "tools", "build"}

# domain に置いてはならない継承元（Node 系）。D2 で extends の連鎖をたどって照合する。
# 網羅は不可能なので、実際に使われうる主要なクラスを挙げている。足りなければここに足す
NODE_FAMILY = {
    "Node", "Node2D", "Node3D", "CanvasItem", "CanvasLayer", "Control", "Window",
    "Viewport", "SubViewport", "HTTPRequest", "Timer", "Button", "BaseButton",
    "Label", "RichTextLabel", "Panel", "PanelContainer", "Container", "BoxContainer",
    "HBoxContainer", "VBoxContainer", "GridContainer", "MarginContainer",
    "CenterContainer", "ScrollContainer", "TextureRect", "ColorRect", "LineEdit",
    "TextEdit", "Sprite2D", "AnimatedSprite2D", "AnimationPlayer", "AudioStreamPlayer",
    "Area2D", "CharacterBody2D", "RigidBody2D", "StaticBody2D", "Camera2D",
    "TextureButton", "CheckBox", "OptionButton", "ProgressBar", "Range", "Tree",
    "ItemList", "TabContainer", "Popup", "PopupPanel", "Sprite3D", "MeshInstance3D",
}
# domain の識別子として現れてはならないエンジン型（継承しなくても new() や型注釈で依存になるため）
ENGINE_IDENTIFIERS = ("HTTPRequest", "FileAccess", "DirAccess", "PackedScene", "SceneTree")

# ファイルの置き場所。classify の戻り値。
#   kind     : "app" / "core" / "master"（master_data）/ "contexts" / "tests" / "debug"
#   ctx      : contexts のときのコンテキスト名（contexts/<ctx>/...）。それ以外は None
#   layer    : "presentation" / "domain" / "data"。層ディレクトリの外なら None
#   use_cases: contexts の domain/use_cases/ 配下なら True（他コンテキストから参照してよい唯一の場所）
Loc = namedtuple("Loc", "kind ctx layer use_cases")
# 1 件の参照（extract_refs の戻り値の要素）。
#   line     : 参照が書かれた行（1 始まり）
#   how      : 参照の種類。"preload" / "load" / "extends" / "class_name" / "autoload"
#   label    : メッセージに出す名前（パス、class_name、オートロード名）
#   tgt      : 参照先の置き場所（Loc）
#   tgt_path : 参照先の相対パス（res:// を除いたもの）。オートロードでスクリプト不明なら None
#   autoload : オートロード名による参照なら True
Ref = namedtuple("Ref", "line how label tgt tgt_path autoload")
# 検出した違反 1 件。path は相対パス、line は 1 始まり、rule はルール ID（D1 など）
Violation = namedtuple("Violation", "path line rule message")
# run_check の戻り値。violations は Violation のリスト（path・行・ルール順）、
# checked は検査したファイル数、skipped は検査対象外のディレクトリにあるファイル数
Report = namedtuple("Report", "violations checked skipped")


def classify(rel):
    """res:// 以下の相対パスから、置き場所（Loc）を返す。

    引数: rel は "contexts/auth/domain/use_cases/x.gd" のような / 区切りの相対パス。
    戻り値: Loc。トップディレクトリが未知（addons や project 直下のファイルなど）なら None。
    呼び出し側は None を「検査の対象外の参照先」として読み飛ばす。
    """
    parts = rel.split("/")
    top = parts[0]
    if top == "app":
        return Loc("app", None, None, False)
    if top in ("tests", "debug"):
        return Loc(top, None, None, False)
    if top in ("core", "master_data"):
        # core/<層>/... と master_data/<層>/...。層名の後ろにファイルが続く形（3 要素以上）だけ層とみなす
        kind = "core" if top == "core" else "master"
        layer = parts[1] if len(parts) >= 3 and parts[1] in LAYERS else None
        return Loc(kind, None, layer, False)
    if top == "contexts":
        # contexts/<ctx>/<層>/...。<ctx> が無い（contexts 直下のファイル）ときはコンテキスト不明
        if len(parts) < 3:
            return Loc("contexts", None, None, False)
        layer = parts[2] if len(parts) >= 4 and parts[2] in LAYERS else None
        # 他コンテキストから参照してよいのは contexts/<ctx>/domain/use_cases/<file> だけ（X1）
        use_cases = layer == "domain" and len(parts) >= 5 and parts[3] == "use_cases"
        return Loc("contexts", parts[1], layer, use_cases)
    return None


def sanitize(src):
    """コメントと文字列の中身を空白にする（長さと改行は保つ）。文字列は開き引用符の位置で記録する。

    なぜ要るか: 「# HTTPRequest は使わない」というコメントや、"AuthApiRepository" という
    文字列を参照と誤検出しないため。ただし preload("res://...") のパスは文字列の中にあるので、
    中身を捨てずに strings へ残し、あとで extract_refs が拾えるようにする。
    長さと改行を保つのは、除去後の文字位置がそのまま元の行番号に対応するようにするため。

    引数: src はファイル全文。
    戻り値: (clean, strings)
      clean   : コメントを空白に、文字列の中身を空白に置き換えた全文（引用符自体は残す）
      strings : {開き引用符の位置: 文字列の中身} の辞書
    文字列が閉じていない（改行や EOF まで来た）場合は、閉じ引用符を出さずにそこで打ち切る。
    """
    out = []
    strings = {}
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # --- 1. コメント: # から行末までを同じ長さの空白にする ---
        if c == "#":
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
            continue
        # --- 2. 文字列: 二重・単一引用符の 1 行文字列と、三連引用符の複数行文字列 ---
        if c in "\"'":
            # 同じ引用符が 3 つ続けば複数行文字列（docstring など）、そうでなければ 1 行文字列
            delim = c * 3 if src.startswith(c * 3, i) else c
            # 直前が r の raw 文字列（r"..."）はバックスラッシュをエスケープとして扱わない。
            # ただし識別子の末尾の r（bar"..." のようなもの）は raw ではないので、2 文字前を見て除く
            raw = i > 0 and src[i - 1] == "r" and (i < 2 or not (src[i - 2].isalnum() or src[i - 2] == "_"))
            j = i + len(delim)
            while j < n:
                if src[j] == "\\" and not raw:
                    j += 2  # エスケープされた 1 文字（\" など）を飛ばす
                    continue
                if src.startswith(delim, j):
                    break
                if len(delim) == 1 and src[j] == "\n":
                    break  # 1 行文字列は改行で打ち切る（閉じ忘れで以降を巻き込まないため）
                j += 1
            body = src[i + len(delim):min(j, n)]
            closed = j < n and src.startswith(delim, j)
            strings[i] = body
            # 中身は空白に（改行だけ残す）。引用符は残して、後ろの正規表現が「文字列の開始」を見分けられるようにする
            out.append(delim + re.sub(r"[^\n]", " ", body) + (delim if closed else ""))
            i = j + (len(delim) if closed else 0)
            continue
        # --- 3. それ以外のコード: そのまま残す ---
        out.append(c)
        i += 1
    return "".join(out), strings


class FileInfo(object):
    """1 つの .gd ファイルの解析結果。ルール判定はこのオブジェクトだけを見て行う。

    属性:
      rel         : プロジェクトルートからの相対パス（/ 区切り）
      loc         : classify(rel) の結果（置き場所）。対象外なら None
      clean       : コメント・文字列を除去したソース（sanitize の第 1 戻り値）
      strings     : {開き引用符の位置: 文字列の中身}（clean 上の位置と対応）
      class_name  : 宣言された class_name。無ければ None
      class_line  : class_name を宣言した行。無ければ 0
      extends     : ("name", "Node") のようなクラス名継承、("path", "res://...") のパス継承、
                    宣言が無ければ None
      extends_line: extends の行。無ければ 0
    """

    def __init__(self, rel, text):
        self.rel = rel
        self.loc = classify(rel)
        self.clean, self.strings = sanitize(text)
        # 各行の先頭オフセット。line_of が「文字位置 → 行番号」を二分探索で引くために使う
        self.starts = [0]
        for m in re.finditer("\n", self.clean):
            self.starts.append(m.end())
        # 行頭の class_name を拾う。例: "class_name AuthRepository"。
        # 行頭に限るのは、コード中の識別子としての出現（var class_name_x など）を宣言と取り違えないため
        m = re.search(r"(?m)^[ \t]*class_name[ \t]+([A-Za-z_]\w*)", self.clean)
        self.class_name = m.group(1) if m else None
        self.class_line = self.line_of(m.start(1)) if m else 0
        self.extends = None  # ("name", X) または ("path", "res://...")
        self.extends_line = 0
        # 行頭の extends を拾う。例: "extends RefCounted"（識別子）/ 'extends "res://a/b.gd"'（引用符で始まるパス）。
        # パスのときは引用符の位置で strings を引いて中身を取り出す
        m = re.search(r"(?m)^[ \t]*extends[ \t]+(?:([A-Za-z_]\w*)|([\"']))", self.clean)
        if m:
            self.extends_line = self.line_of(m.start())
            if m.group(1):
                self.extends = ("name", m.group(1))
            else:
                self.extends = ("path", self.strings.get(m.start(2), ""))

    def line_of(self, offset):
        """clean 上の文字位置（0 始まり）を、行番号（1 始まり）に変える。"""
        return bisect.bisect_right(self.starts, offset)


def read_autoloads(root):
    """project.godot の [autoload] を {名前: 相対パス} で返す。

    例: 行 `AppContext="*res://app/app_context.gd"` → {"AppContext": "app/app_context.gd"}
    先頭の * は「シングルトンとして有効」を表す Godot の記法なので外す。
    project.godot が無い（テストの最小ツリーなど）ときは空の辞書を返し、例外にしない。
    res:// で始まらない値（uid:// など）は相対パスに直せないので無視する。
    """
    result = {}
    path = os.path.join(root, "project.godot")
    if not os.path.isfile(path):
        return result
    in_section = False
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if line.startswith("["):
                # セクション見出し。[autoload] の間だけ読む
                in_section = line == "[autoload]"
                continue
            if in_section and "=" in line and not line.startswith(";"):
                name, value = line.split("=", 1)
                value = value.strip().strip('"').lstrip("*")
                if value.startswith("res://"):
                    result[name.strip()] = value[len("res://"):]
    return result


def collect_files(root):
    """root 以下の *.gd を、相対パス（/ 区切り）のソート済みリストで返す。

    アドオン・生成物（SKIP_DIRS）と隠しディレクトリ（.git / .godot など）は走査しない。
    ソートするのは、出力の順序を実行環境（OS のファイル列挙順）に依存させないため。
    """
    found = []
    for dirpath, dirnames, filenames in os.walk(root):
        # dirnames をその場で書き換えると os.walk がその下へ降りなくなる
        dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(".gd"):
                rel = os.path.relpath(os.path.join(dirpath, name), root)
                found.append(rel.replace(os.sep, "/"))
    return sorted(found)


def is_checked(rel):
    """検査対象（新構成のトップディレクトリ配下）か。"""
    return rel.split("/")[0] in CHECK_DIRS


def describe(loc):
    """Loc を "contexts/auth/domain" のような人が読める置き場所の文字列にする。"""
    if loc.kind in ("core", "master"):
        base = "core" if loc.kind == "core" else "master_data"
        return base + ("/" + loc.layer if loc.layer else "")
    if loc.kind == "contexts":
        return "contexts/%s/%s" % (loc.ctx, loc.layer) if loc.ctx else "contexts"
    return loc.kind


def pascal(stem):
    """snake_case のファイル名（拡張子なし）をパスカルケースにする。

    例: "auth_api_repository" → "AuthApiRepository"。N1 で class_name との一致を見るのに使う。
    """
    return "".join(p[:1].upper() + p[1:] for p in stem.split("_"))


def extract_refs(info, classes, autoloads):
    """1 ファイルの参照（パス・class_name・オートロード名）を Ref のリストで集める。

    引数:
      info     : 解析済みの FileInfo
      classes  : {class_name: 定義ファイルの相対パス}（run_check が作る）
      autoloads: {オートロード名: スクリプトの相対パス}（read_autoloads の結果）
    戻り値: Ref のリスト。同じ参照先は 1 件にまとめる（class_name・オートロード名のみ）。
    """
    # --- 1. パスによる参照: preload("res://...") / load("res://...") / extends "res://..." ---
    # (種類, キーワード, パス, 行) の一時リスト。種類は今は "path" 固定で、後段では使わない
    refs = []
    # 例: preload("res://core/domain/x.gd") の preload と、直後の引用符の位置を捉える。
    # 引用符の位置で strings を引けば、sanitize が空白にした中身（パス）を取り戻せる
    for m in re.finditer(r"\b(preload|load)\s*\(\s*([\"'])", info.clean):
        content = info.strings.get(m.end() - 1, "")
        # res:// 以外（user:// や変数に入れたパス）は静的に追えないので対象外
        if content.startswith("res://"):
            refs.append(("path", m.group(1), content, info.line_of(m.start())))
    if info.extends and info.extends[0] == "path" and info.extends[1].startswith("res://"):
        refs.append(("path", "extends", info.extends[1], info.extends_line))
    result = []
    for how, kw, path, line in refs:
        rel = path[len("res://"):]
        tgt = classify(rel)
        if tgt is None:
            continue  # addons 配下など、検査対象外の置き場所
        result.append(Ref(line, kw, path, tgt, rel, False))

    # --- 2. 識別子による参照: class_name とオートロード名 ---
    # 自分自身がオートロードのスクリプトなら、そのオートロード名（例: "AppContext"）を覚えておく。
    # ファイル内で自分の名前を書いても自己参照として数えないため
    own_autoload_name = None
    for name, p in autoloads.items():
        if p == info.rel:
            own_autoload_name = name
    # 同じ参照先を何度も報告しない（最初の出現だけ）。キーは ("c", 参照先パス) か ("a", オートロード名)
    seen = set()
    # clean は文字列とコメントが空白になっているので、識別子らしい語だけがここに残る
    for m in re.finditer(r"[A-Za-z_]\w*", info.clean):
        name = m.group(0)
        # `foo.Bar` の Bar はメンバ参照であって、グローバルなクラス名の参照ではない
        if m.start() > 0 and info.clean[m.start() - 1] == ".":
            continue
        if name in classes and classes[name] != info.rel:
            # 自分自身の class_name 宣言は除く（classes[name] != info.rel）
            tgt_path = classes[name]
            if ("c", tgt_path) in seen:
                continue
            seen.add(("c", tgt_path))
            # class_name の定義ファイルが検査対象外の置き場所なら、参照先の層が決まらないので読み飛ばす
            tgt = classify(tgt_path)
            if tgt is None:
                continue
            result.append(Ref(info.line_of(m.start()), "class_name", name, tgt, tgt_path, False))
        elif name in autoloads or name in FIXED_AUTOLOADS:
            if name == own_autoload_name or ("a", name) in seen:
                continue
            seen.add(("a", name))
            script = autoloads.get(name)  # FIXED_AUTOLOADS だけに載る名前は None
            # スクリプト不明（project.godot に無い）なら app 扱い。パスが検査対象外の場所を指すなら読み飛ばす
            tgt = classify(script) if script else Loc("app", None, None, False)
            if tgt is None:
                continue
            result.append(Ref(info.line_of(m.start()), "autoload", name, tgt, script, True))
    return result


def check_ref(src, ref):
    """1 つの参照が破るルールを [(ルールID, メッセージ)] で返す（違反が無ければ空リスト）。

    引数: src は参照元の Loc、ref は参照 1 件。
    判定は上から順に行い、あるルールに当たったら基本的にそこで返す
    （同じ参照が複数のルールで二重に報告されるのを避けるため）。例外は他コンテキスト参照で、
    Da1・X1・P2 の組み合わせを意図して同時に出す。
    app / tests / debug は組み立てやテスト用なので、参照元としては検査しない。
    """
    if src.kind in ("app", "tests", "debug"):
        return []
    tgt = ref.tgt
    res = []
    arrow = "%s → %s" % (ref.label, ref.tgt_path or ref.label)

    # --- 1. 参照先の種別で決まるルール（層に関係なく禁止されるもの） ---
    if ref.autoload:
        # オートロード名を使ってよいのは core / contexts の presentation だけ（2 節 contexts / オートロード）
        if not (src.layer == "presentation" and src.kind in ("core", "contexts")):
            res.append(("A1", "オートロード名は presentation だけが参照できる: " + ref.label))
        return res
    if tgt.kind == "app":
        # オートロード名でなく、app のパス・class_name を直接参照するのは禁止
        res.append(("A1", "res://app/ を参照してはならない: " + arrow))
        return res
    if tgt.kind in ("tests", "debug"):
        res.append(("T1", "本番コードが %s/ を参照している: %s" % (tgt.kind, arrow)))
        return res

    # --- 2. 種別（core / master_data / contexts）をまたぐルール ---
    if src.kind == "core" and tgt.kind != "core":
        res.append(("C1", "core は contexts・master_data を参照しない: " + arrow))
        return res
    if src.kind == "master" and tgt.kind == "contexts":
        res.append(("M2", "master_data は contexts を参照しない: " + arrow))
        return res
    if src.kind == "contexts":
        if tgt.kind == "contexts" and tgt.ctx != src.ctx:
            # 他コンテキストへの参照。同一コンテキスト内は下の層ルールに任せる
            if src.layer == "data":
                res.append(("Da1", "data は他コンテキストを参照しない: " + arrow))
            if not tgt.use_cases:
                res.append(("X1", "他コンテキストは domain/use_cases/ だけ参照できる: " + arrow))
                if src.layer == "presentation":
                    # presentation 側から見た同じ違反。P2 としても数える（ルールの出どころを分けて示すため）
                    res.append(("P2", "presentation が参照できる他コンテキストは domain/use_cases/ だけ: " + arrow))
            return res
        if tgt.kind == "master" and tgt.layer == "data":
            # master_data/domain は可、master_data/data は不可（2-1 節）。層ルールにも続けて通す
            res.append(("M1", "contexts は master_data/data を参照しない（master_data/domain だけ可）: " + arrow))

    # --- 3. 3 層の向き（presentation → domain ← data） ---
    if src.layer is None or tgt.layer is None:
        return res  # 層が決まらない置き場所は S1 が別に報告する
    if src.layer == "domain" and tgt.layer in ("presentation", "data"):
        res.append(("D1", "domain は %s を参照しない: %s" % (tgt.layer, arrow)))
    elif src.layer == "presentation" and tgt.layer == "data":
        res.append(("P1", "presentation は data を参照しない: " + arrow))
    elif src.layer == "data" and tgt.layer == "presentation":
        res.append(("Da1", "data は presentation を参照しない: " + arrow))
    return res


def engine_violations(info, infos, classes):
    """domain のエンジン依存（D2）を [(行, メッセージ)] で返す。

    domain は RefCounted だけで書き、エンジン起動なしで単体テストできる状態を保つ（2 節 domain）。
    見るのは (1) 継承元が Node 系か、(2) HTTPRequest など使ってはいけない型が現れるか、
    (3) get_tree() を呼んでいるか、の 3 点。.tscn の preload / load は run_check 側で見る。
    """
    out = []
    # --- 1. 継承の連鎖をたどり、Node 系に行き着くか調べる ---
    # 直接 Node を継承していなくても、自作の基底クラス（extends BaseNode）経由で Node になりうるため。
    # seen は継承の循環（A が B を、B が A を継承）で無限ループにならないための番人
    cur = info
    seen = set()
    while cur is not None and cur.extends and cur.rel not in seen:
        seen.add(cur.rel)
        kind, value = cur.extends
        if kind == "name":
            if value in NODE_FAMILY:
                # 行番号は検査対象のファイル自身の extends 行を指す（連鎖の途中のファイルではない）
                out.append((info.extends_line, "domain は Node 系を継承しない（RefCounted だけで書く）: extends %s" % value))
                break
            nxt = classes.get(value)
            cur = infos.get(nxt) if nxt else None  # 組み込みクラスや未知の名前ならここで追跡を終える
        else:
            cur = infos.get(value[len("res://"):]) if value.startswith("res://") else None
    # --- 2. エンジン依存の型 ---
    for name in ENGINE_IDENTIFIERS:
        # 例: "var h = HTTPRequest.new()" にマッチ。直前が識別子の一部や "." のもの
        # （MyHTTPRequest・x.HTTPRequest）は別物なので除く
        m = re.search(r"(?<![\w.])%s\b" % name, info.clean)
        if m:
            out.append((info.line_of(m.start()), "domain はエンジン依存の型を使わない: " + name))
    # --- 3. get_tree()（Node のメソッド。SceneTree への依存になる） ---
    m = re.search(r"\bget_tree\s*\(", info.clean)
    if m:
        out.append((info.line_of(m.start()), "domain は get_tree() を呼ばない"))
    return out


def naming_violations(info):
    """N1 のうち、ファイル名の接尾辞と置き場所の対応を調べる。

    戻り値: ([(行, メッセージ)], stem)。stem は拡張子を除いたファイル名で、
    呼び出し側が class_name との一致（pascal(stem)）を見るのに使う。
    接尾辞に意味を持たせる理由は architecture.md 6 節（名前だけで役割と置き場所が分かるようにする）。
    行番号はファイル単位の違反なので 1 固定。
    """
    out = []
    parts = info.rel.split("/")
    name = parts[-1]
    stem = name[:-3]  # ".gd" を除く

    def tail(*dirs):
        """パスの末尾（ファイル名の直前）が dirs と一致するか。例: tail("domain", "use_cases")"""
        return len(parts) > len(dirs) and tuple(parts[-1 - len(dirs):-1]) == dirs

    # 例外: 複数コンテキストが共有する表示専用の UseCase は core/domain/moon/ に置く
    # （背景の月。architecture.md の core/domain の記述。client_design A-1）
    shared_use_case = parts[0] == "core" and tail("domain", "moon")
    if name.endswith("_use_case.gd") and not tail("domain", "use_cases") and not shared_use_case:
        out.append((1, "*_use_case.gd は domain/use_cases/ にだけ置ける（共有の表示専用は core/domain/moon/ も可）"))
    if name.endswith("_presenter.gd") and "presentation" not in parts[:-1]:
        out.append((1, "*_presenter.gd は presentation/ にだけ置ける"))
    if (name.endswith("_api_repository.gd") or (name.startswith("local_") and name.endswith("_repository.gd"))) \
            and not tail("data", "repositories"):
        out.append((1, "*_api_repository.gd と local_*_repository.gd は data/repositories/ にだけ置ける"))
    if name.endswith("_response.gd") and not tail("data", "api"):
        out.append((1, "*_response.gd は data/api/ にだけ置ける"))
    return out, stem


def find_cycles(graph):
    """依存グラフから、強連結成分（=循環）を Tarjan 法で求める。

    引数: graph は {ファイル: {そのファイルが preload / extends するファイル}}。
    戻り値: 循環を成すファイル群のリスト（各要素はソート済みのパスのリスト）。
      サイズ 2 以上の成分と、自分自身を preload する 1 ファイルの成分だけを返す。
    なぜ循環を探すか: Godot は preload の循環を解決できず、読み込み時にエラーになるため（Y1）。
    再帰の深さがファイル数に比例するので、再帰の上限を引き上げている。
    """
    index = {}  # 訪問順の番号（深さ優先で最初に見つけた順）
    low = {}  # その頂点から辿れる最小の index。index と等しければ成分の根
    stack = []  # 現在の成分候補
    on = set()  # stack に載っている頂点（stack の所属判定を速くするため）
    counter = [0]  # 再帰の内側から書き換えるため、リストで包んだ訪問カウンタ
    comps = []
    sys.setrecursionlimit(10000)

    def visit(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in graph.get(v, ()):
            if w not in index:
                visit(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                # すでに訪問済みで、まだ成分が確定していない = 戻り辺。循環の一部
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            # v が成分の根。stack を v まで取り出すと 1 つの成分になる
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            # 単独の頂点は、自己 preload のときだけ循環とみなす
            if len(comp) > 1 or v in graph.get(v, ()):
                comps.append(sorted(comp))

    for v in sorted(graph):  # ソート順で回し、結果を実行ごとに安定させる
        if v not in index:
            visit(v)
    return comps


def run_check(root):
    """root 以下の GDScript を検査して Report を返す（出力はしない。出力は main の仕事）。

    テストからも直接呼ばれるので、標準出力への表示や終了コードを持たない。
    """
    root = os.path.abspath(root)
    # --- 1. ファイル収集と解析 ---
    autoloads = read_autoloads(root)
    all_files = collect_files(root)
    # 検査対象外のディレクトリも含めて全 .gd を読む（class_name の参照先を解決するため）
    infos = {}
    for rel in all_files:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as f:
            infos[rel] = FileInfo(rel, f.read())

    # --- 2. class_name 表（クラス名 → 定義ファイル） ---
    # 重複した class_name は最初のもの（ソート順）を採る。重複自体は Godot がエラーにする
    classes = {}
    for rel, info in infos.items():
        if info.class_name and info.class_name not in classes:
            classes[info.class_name] = rel

    checked = [r for r in all_files if is_checked(r)]
    skipped = len(all_files) - len(checked)
    # 違反の重複排除表。キーは (ファイル, ルール, 対象のキー)、値は Violation。
    # 同じ違反が複数行に出ても 1 件にまとめ、一番上の行を報告する
    found = {}

    def add(path, line, rule, message, key):
        k = (path, rule, key)
        if k not in found or line < found[k].line:
            found[k] = Violation(path, line, rule, message)

    # preload / extends の依存グラフ {ファイル: {参照先ファイル}} と、その辺が最初に現れた行（Y1 の行番号用）
    graph = {}
    first_edge = {}
    # --- 3. ファイルごとにルールを当てる ---
    for rel in checked:
        info = infos[rel]
        loc = info.loc
        # S1: 層ディレクトリの外。層が決まらないと以降の層ルールが効かないので、置き場所自体を指摘する
        if loc.kind in ("core", "master", "contexts") and loc.layer is None:
            add(rel, 1, "S1", "presentation / domain / data のいずれかの下に置く", "")
        # L1: オートロードのスクリプトは class_name を持たない（Godot が名前の衝突でエラーにする）
        for name, p in autoloads.items():
            if p == rel and info.class_name:
                add(rel, info.class_line, "L1",
                    "オートロード %s のスクリプトに class_name を付けない（Class hides an autoload singleton）" % name, name)
        # N1: 接尾辞と置き場所の対応、class_name とファイル名の対応
        viol, stem = naming_violations(info)
        for line, msg in viol:
            add(rel, line, "N1", msg, msg)
        is_autoload = rel in autoloads.values()
        # オートロードは class_name を持てない（L1）ので、ファイル名との一致は求めない
        if info.class_name and not is_autoload and info.class_name != pascal(stem):
            add(rel, info.class_line, "N1",
                "class_name はファイル名のパスカルケース（%s）にする: %s" % (pascal(stem), info.class_name), "cn")
        # D2: domain のエンジン依存
        # オートロードのスクリプトは Node を継承する必要があるため D2 の対象にしない
        if loc.layer == "domain" and loc.kind in ("core", "master", "contexts") and not is_autoload:
            for line, msg in engine_violations(info, infos, classes):
                add(rel, line, "D2", msg, msg)
        # 参照ごとのルール（D1・P1・P2・Da1・X1・M1・M2・C1・A1・T1）と、D2 の .tscn
        for ref in extract_refs(info, classes, autoloads):
            if loc.layer == "domain" and ref.tgt_path and ref.tgt_path.endswith(".tscn") and not ref.autoload:
                # シーンへの依存は、Node を継承しなくてもエンジン依存になる（2 節 domain）
                add(rel, ref.line, "D2", "domain は .tscn を preload / load しない: " + ref.tgt_path, ref.tgt_path)
            for rule, msg in check_ref(loc, ref):
                add(rel, ref.line, rule, msg, ref.tgt_path or ref.label)
            # 循環の検出に使うのは、読み込み時に解決される preload と extends の辺だけ。
            # class_name の識別子参照は実行時に解決されるので、循環の原因にならない
            if ref.how in ("preload", "extends") and ref.tgt_path and ref.tgt_path in infos \
                    and is_checked(ref.tgt_path):
                graph.setdefault(rel, set()).add(ref.tgt_path)
                first_edge.setdefault((rel, ref.tgt_path), ref.line)

    # --- 4. Y1: preload の循環 ---
    for comp in find_cycles(graph):
        # 成分の先頭（ソート済み）のファイルに、その次の参照先がある行を添えて 1 件だけ報告する
        head = comp[0]
        nxt = next((w for w in sorted(graph.get(head, ())) if w in comp), head)
        add(head, first_edge.get((head, nxt), 1), "Y1",
            "preload が循環している: " + " ⇄ ".join(comp), "|".join(comp))

    # --- 5. 出力順を決める（パス → 行 → ルール。実行ごとに同じ並びにするため） ---
    violations = sorted(found.values(), key=lambda v: (v.path, v.line, v.rule))
    return Report(violations, len(checked), skipped)


def main(argv=None):
    """コマンドラインの入口。違反を表示し、終了コード（0: 違反なし / 1: 違反あり）を返す。

    argv を引数にしているのは、テストから cd.main(["--root", dir]) で呼べるようにするため。
    """
    parser = argparse.ArgumentParser(description="クライアントの依存方向チェック")
    parser.add_argument("--root", default=".", help="プロジェクトのルート（既定: カレント）")
    args = parser.parse_args(argv)
    report = run_check(args.root)
    # 形式は「パス:行: [ルールID] メッセージ」。エディタや CI のログからジャンプしやすい
    for v in report.violations:
        print("%s:%d: [%s] %s" % (v.path, v.line, v.rule, v.message))
    print("違反 %d 件（検査 %d ファイル、検査対象外 %d ファイル）"
          % (len(report.violations), report.checked, report.skipped))
    return 1 if report.violations else 0


if __name__ == "__main__":
    sys.exit(main())
