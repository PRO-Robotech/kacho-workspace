"""Измеритель ВТОРОЙ ПРОПИСКИ: один предмет, лежащий больше чем в одном доме.

ЗАЧЕМ ЭТО СУЩЕСТВУЕТ

Требование владельца 2026-09-20, дословно: «все общие библиотеки, которые могут
быть вынесены должны быть вынесены в corelib а не хорониться в проекте».

«Может быть вынесено» — не намерение автора, а ФАКТ второй прописки. Похороненный
общий код виден не тем, что он «общий по смыслу», а тем, что его УЖЕ СКОПИРОВАЛИ.
Три действующие нормы этот факт не ловят: `arch-corelib-horizontal` судит
размещение НОВОГО предмета, ограничение приёмки K3-1 судит НАПРАВЛЕНИЕ
зависимости, запрет #20 ловит пару по ПУТИ. Ни одна не видит предмет,
скопированный под ДРУГИМ ИМЕНЕМ: `kacho:tools/tools.go` ↔ `kaname:tools/
generators.go`, J = 1.000, ведомостью пар не ловится, потому что пути разные.

ПОЧЕМУ ДОМ ИЗМЕРИТЕЛЯ — ВОРКСПЕЙС

Вторая прописка есть свойство ДВУХ деревьев; каждое по себе исправно, и
расхождение наступает молча. Воркспейс — единственное место, где под рукой все
три клона. Так же и по той же причине устроен `scripts/crossrepo-gate`.

ЕДИНИЦА — ПАКЕТ, А НЕ ФАЙЛ (исправлено опровержением 2026-09-20)

Первая редакция мерила файл, и обе её отсекающие проверки были дырявы ПО
ПОСТРОЕНИЮ: единица компиляции в Go — пакет, ссылка на сиблинга импорта не
требует, поэтому проверка направления (читает блок import) её не видела вовсе, а
проверка политики (читает литералы файла) была слепа к литералу, лежащему на один
файл в стороне. Замер опровержения: 12 из 19 файлов-кандидатов ссылались на
идентификатор, объявленный сиблингом; две компиляционные пробы дали `undefined:
envPrefix` и `undefined: schema`, где `schema = "kacho_registry"` — продуктовый
литерал, спрятанный соседним файлом. Здесь отсев спрашивает КАТАЛОГ ПАКЕТА
целиком: объединение импортов и объединение литералов всех его `.go`.

ЧТО ЧИТАЕТСЯ

СТВОЛ `origin/main` каждого клона, содержимое — `git cat-file --batch`, не
рабочая копия (`poly-copy-trunk-predicate`). На грязном дереве или на ветке чтение
рабочей копии мерило бы другой предмет, и мерило бы молча.
"""
import os
import re
import subprocess

PRODUCTS = ("kacho", "kaname", "corelib")

MODULE_PREFIXES = ("github.com/PRO-Robotech/kacho", "github.com/PRO-Robotech/kaname")
FOUNDATION_MODULE = "github.com/PRO-Robotech/corelib"

# Минимальная длина нормализованного файла. Короче — шум: два файла по три
# строки дают J=1.0 на совпадении `package x` и закрывающей скобке.
MIN_LINES = 5

_COMMENT = re.compile(r"^\s*(//|/\*|\*/|\*)")
_LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
_IMPORT_LINE = re.compile(r'^\s*(?:[A-Za-z_.][\w]*\s+)?"([^"]+)"')


def clone(root, name):
    """Путь клона продукта либо None. Тот же порядок, что у crossrepo-gate."""
    env = os.environ.get("KACHO_HOME_" + name.upper().replace("-", "_"))
    if env and os.path.exists(os.path.join(env, ".git")):
        return env
    guess = os.path.join(root, "project", name)
    if os.path.exists(os.path.join(guess, ".git")):
        return guess
    return None


def trunk_ref(repo):
    for ref in ("origin/main", "origin/master", "main"):
        out = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", ref],
                             capture_output=True, text=True)
        if out.returncode == 0:
            return ref
    return None


def go_paths(repo, ref):
    out = subprocess.run(["git", "-C", repo, "ls-tree", "-r", ref, "--name-only"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return [p for p in out.stdout.split("\n") if p.endswith(".go")]


def read_blobs(repo, ref, paths):
    """{путь: текст} одним `cat-file --batch` — 6400 запусков git были бы минутами."""
    if not paths:
        return {}
    req = "".join("%s:%s\n" % (ref, p) for p in paths)
    proc = subprocess.run(["git", "-C", repo, "cat-file", "--batch"],
                          input=req.encode(), capture_output=True)
    out, res, i = proc.stdout, {}, 0
    for p in paths:
        nl = out.find(b"\n", i)
        if nl < 0:
            break
        header = out[i:nl].decode("utf-8", "replace").split()
        if len(header) < 3:
            i = nl + 1
            continue
        size = int(header[2])
        res[p] = out[nl + 1:nl + 1 + size].decode("utf-8", "replace")
        i = nl + 1 + size + 1
    return res


def normalize(text):
    """Множество непустых не-комментарных строк."""
    lines = set()
    for raw in text.split("\n"):
        s = raw.strip()
        if not s or _COMMENT.match(raw):
            continue
        lines.add(s)
    return lines


def imports_of(text):
    """Пути импорта файла: блок `import ( … )` и однострочный `import "…"`."""
    res, inside = set(), False
    for raw in text.split("\n"):
        s = raw.strip()
        if s.startswith("import ("):
            inside = True
            continue
        if inside:
            if s.startswith(")"):
                inside = False
                continue
            m = _IMPORT_LINE.match(raw)
            if m:
                res.add(m.group(1))
            continue
        if s.startswith("import "):
            m = _LITERAL.search(s)
            if m:
                res.add(m.group(1))
    return res


def literals_of(text):
    """Строковые литералы вне комментариев и вне строк импорта."""
    res, inside = set(), False
    for raw in text.split("\n"):
        s = raw.strip()
        if not s or _COMMENT.match(raw):
            continue
        if s.startswith("import ("):
            inside = True
            continue
        if inside:
            if s.startswith(")"):
                inside = False
            continue
        if s.startswith("import "):
            continue
        for m in _LITERAL.finditer(raw):
            res.add(m.group(1))
    return res


def home_of(product, rel):
    """Дом = продукт + служба. Служба — для группировки; ПРОДУКТ — для адреса выноса."""
    if product == "kacho":
        parts = rel.split("/")
        if parts[0] == "services" and len(parts) > 1:
            return "kacho:services/%s" % parts[1]
        return "kacho:%s" % parts[0]
    return "%s:%s" % (product, rel.split("/")[0])


class Tree(object):
    """Один ствол: нормализованные файлы, свойства КАТАЛОГА ПАКЕТА."""

    def __init__(self, product, repo, ref):
        self.product, self.repo, self.ref = product, repo, ref
        self.paths = go_paths(repo, ref) or []
        self.text = read_blobs(repo, ref, self.paths)
        self.norm, self.pkg_imports, self.pkg_literals, self.pkg_files = {}, {}, {}, {}
        for p, t in self.text.items():
            d = os.path.dirname(p)
            self.pkg_files.setdefault(d, []).append(p)
            self.pkg_imports.setdefault(d, set()).update(imports_of(t))
            self.pkg_literals.setdefault(d, set()).update(literals_of(t))
            lines = normalize(t)
            if len(lines) >= MIN_LINES:
                self.norm[p] = lines


# ─────────────────────────────────────────────────────────────────────────────
# ИСКЛЮЧЕНИЯ — ЗАКРЫТЫЙ перечень из ВОСЬМИ. У каждого механический ПРИЗНАК и
# сказано, чем оно снимается. «И тому подобное», «по усмотрению», «если
# оправдано» сюда не подставляются: под них подводят что угодно, и норма
# становится пожеланием.
#
# Девятым пунктом ниже названа ЛАЗЕЙКА, которая исключением НЕ является и
# признака не имеет. Она закрывается не словом в норме, а устройством работы:
# счёт объявлен ВЕРХНЕЙ ГРАНИЦЕЙ, критерий производит ОЧЕРЕДЬ РЕШЕНИЙ, а не
# автоматический перенос.
EXCLUSIONS = (
    "1-направление",
    "2-политика",
    "3-контракт",
    "4а-лицензия-busl",
    "4б-лицензия-agpl",
    "5-одноимённость",
    "6-судья-не-едет",
    "7-объявление-о-себе",
    "8-под-снятие",
)
LICENSE_EXCLUSIONS = ("4а-лицензия-busl", "4б-лицензия-agpl")

_KNOB = re.compile(r"^(KACHO|KANAME)_[A-Z0-9_]+$")
_MIGRATION = re.compile(r"^\d{3,}_.*\.sql$")
_PG_OBJECT = re.compile(r"(kacho|kaname)_[a-z0-9_]+")
_SPDX = re.compile(r"SPDX-License-Identifier:\s*(\S+)")
_DATA_ACCESS = ("github.com/jackc/pgx", "database/sql", "sqlc")
_GENERATED = (".pb.go", ".pb.gw.go", "_grpc.pb.go")


def spdx_of(text):
    for raw in text.split("\n")[:4]:
        m = _SPDX.search(raw)
        if m:
            return m.group(1)
    return ""


def import_path_of(product, rel_dir, module_root):
    return module_root + "/" + rel_dir if rel_dir else module_root


def product_imports(imports):
    """Импорты, называющие модуль ПРОДУКТА (свой или чужой). Фундамент — не продукт."""
    return {i for i in imports if any(i == p or i.startswith(p + "/") for p in MODULE_PREFIXES)}


def import_to_home(imp):
    """`github.com/PRO-Robotech/kacho/pkg/refusal` → ('kacho', 'pkg/refusal')."""
    for p in MODULE_PREFIXES:
        if imp == p or imp.startswith(p + "/"):
            return p.rsplit("/", 1)[1], imp[len(p) + 1:]
    return None, None


def policy_literals(literals, imports):
    """Литералы, несущие ПОЛИТИКУ продукта. Сужено опровержением 2026-09-20.

    Прежняя редакция ловила ЛЮБОЙ литерал со словом продукта и этим принимала
    ПАРАМЕТР за политику: `observability/metrics/metrics.go` ×3 (984 строки,
    импортов продукта ноль) отсекался шестнадцатью литералами вида
    `kacho_<svc>_<предмет>` — именами метрик, то есть одним подставляемым словом
    имени службы. Признак был при этом НЕОТМЕНЯЕМ: пакет метрик не может не
    называть свои метрики. Здесь перечислены ровно те формы, ради которых
    исключение и заводилось: имя схемы PG, имя файла миграции, приставка ручки,
    идентичность spiffe, имя релизной ветки.
    """
    data_access = any(any(d in i for d in _DATA_ACCESS) for i in imports)
    hits = set()
    for lit in literals:
        if _KNOB.match(lit):
            hits.add("ручка %s" % lit)
        elif lit.startswith("spiffe://"):
            hits.add("идентичность %s" % lit)
        elif _MIGRATION.match(lit):
            hits.add("миграция %s" % lit)
        elif lit.startswith("release/"):
            hits.add("релизная ветка %s" % lit)
        elif data_access and _PG_OBJECT.search(lit):
            hits.add("объект PG %s" % lit)
    return hits


def declared_own(ledger_text):
    """Пути, объявленные парой с решением `own` в ведомости crossrepo."""
    res, cur = set(), None
    for raw in (ledger_text or "").split("\n"):
        s = raw.strip()
        if s.startswith("- path:"):
            cur = s.split(":", 1)[1].strip()
        elif cur and s.startswith("decision:") and s.split(":", 1)[1].strip() == "own":
            res.add(cur)
    return res


def jaccard_pairs(files, threshold):
    """Пары (a,b) с J ≥ threshold, только между РАЗНЫМИ домами.

    Пары порождаются ТОЧНЫМ ОКНОМ РАЗМЕРОВ [J·n … n/J]: при |A|=n и J(A,B)≥T
    неизбежно T·n ≤ |B| ≤ n/T, поэтому пропусков нет ПО ПОСТРОЕНИЮ, а не по
    везению. Это единственное место, где полнота обхода вообще обсуждается.
    """
    order = sorted(files, key=lambda k: len(files[k][0]))
    sizes = [len(files[k][0]) for k in order]
    edges = []
    import bisect
    for i, a in enumerate(order):
        sa, ha = files[a]
        lo = bisect.bisect_left(sizes, int(len(sa) * threshold))
        hi = bisect.bisect_right(sizes, int(len(sa) / threshold) + 1)
        for j in range(max(lo, i + 1), hi):
            b = order[j]
            sb, hb = files[b]
            if ha == hb:
                continue
            inter = len(sa & sb)
            if not inter:
                continue
            if inter / float(len(sa) + len(sb) - inter) >= threshold:
                edges.append((a, b))
    return edges


def groups_of(edges):
    """Связные группы рёбер = ПРЕДМЕТЫ."""
    parent = {}

    def find(x):
        parent.setdefault(x, x)
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for a, b in edges:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
    out = {}
    for k in parent:
        out.setdefault(find(k), []).append(k)
    return [sorted(v) for v in out.values()]


def measure(root, threshold=0.70, relicense_busl=False, relicense_agpl=False):
    """Полный замер. Возвращает словарь; None — предмета нет (третий исход)."""
    trees, missing = {}, []
    for name in PRODUCTS:
        repo = clone(root, name)
        if repo is None:
            missing.append(name)
            continue
        ref = trunk_ref(repo)
        if ref is None:
            missing.append(name + " (ствол не резолвится)")
            continue
        trees[name] = Tree(name, repo, ref)
        trees[name].sha = subprocess.run(
            ["git", "-C", repo, "rev-parse", "--short", ref],
            capture_output=True, text=True).stdout.strip()
    if missing:
        return {"void": "клонов нет либо ствол не резолвится: %s" % ", ".join(missing)}

    # ── обход ────────────────────────────────────────────────────────────────
    walked = sum(len(t.paths) for t in trees.values())
    files = {}          # "продукт:путь" → (множество строк, дом)
    owner = {}          # "продукт:путь" → (продукт, путь)
    for name, t in trees.items():
        for p, lines in t.norm.items():
            k = "%s:%s" % (name, p)
            files[k] = (lines, home_of(name, p))
            owner[k] = (name, p)
    comparable = len(files)

    edges = jaccard_pairs(files, threshold)
    subjects = groups_of(edges)

    # ── отсев ПОФАЙЛОВЫЙ по свойствам ПАКЕТА ─────────────────────────────────
    # Пофайловый, а не по группе целиком: одна испачканная копия иначе хоронит
    # предмет. Замер: `existence_probe.go` — 4 копии, две несут имя схемы PG,
    # две чисты; предмет остаётся кандидатом своей чистой частью.
    crossrepo = None
    try:
        with open(os.path.join(root, "docs/crossrepo-pairs.yaml"), encoding="utf-8") as fh:
            crossrepo = declared_own(fh.read())
    except IOError:
        crossrepo = set()
    sunset = sunset_dirs(root)
    gate_declared = declared_by_tree_gate(trees)

    def cuts(k, queued_dirs):
        product, rel = owner[k]
        t = trees[product]
        d = os.path.dirname(rel)
        why = []
        if os.path.basename(rel).endswith(_GENERATED):
            why.append("3-контракт")
        if rel.endswith("_test.go"):
            why.append("6-судья-не-едет")
        if rel in crossrepo:
            why.append("5-одноимённость")
        if "%s:%s" % (product, d) in sunset:
            why.append("8-под-снятие")
        if "%s:%s" % (product, d) in gate_declared:
            why.append("7-объявление-о-себе")
        # 1 — направление зависимости, КАК НЕПОДВИЖНАЯ ТОЧКА: импорт предмета,
        # который сам стоит в очереди выноса, не отсекает. Иначе очередь
        # строится в неверном порядке: 11 файлов в шести домах были объявлены
        # невыносимыми единственно из-за импорта `kacho/pkg/refusal` — предмета,
        # который сам обязан переехать.
        outside = set()
        for imp in product_imports(t.pkg_imports.get(d, set())):
            ip, idir = import_to_home(imp)
            if ip and "%s:%s" % (ip, idir) in queued_dirs:
                continue
            outside.add(imp)
        if outside:
            why.append("1-направление")
        pol = policy_literals(t.pkg_literals.get(d, set()), t.pkg_imports.get(d, set()))
        if pol:
            why.append("2-политика")
        lic = spdx_of(t.text.get(rel, ""))
        if lic.startswith("AGPL"):
            if not relicense_agpl:
                why.append("4б-лицензия-agpl")
        elif lic and lic != "Apache-2.0":
            if not relicense_busl:
                why.append("4а-лицензия-busl")
        return why

    # Неподвижная точка: сначала считаем очередь без поблажки направления,
    # затем повторяем, пока состав очереди не перестанет меняться.
    queued_dirs = set()
    for _ in range(8):
        kept, cut = {}, {}
        for s in subjects:
            for k in s:
                w = cuts(k, queued_dirs)
                (cut if w else kept)[k] = w
        nxt = set()
        for s in subjects:
            live = [k for k in s if k in kept]
            if len(live) >= 2 and len({files[k][1] for k in live}) >= 2:
                for k in live:
                    p, rel = owner[k]
                    nxt.add("%s:%s" % (p, os.path.dirname(rel)))
        if nxt == queued_dirs:
            break
        queued_dirs = nxt

    # ── сборка перечня ───────────────────────────────────────────────────────
    cand, cut_reasons = [], {}
    for s in subjects:
        live, why = [], {}
        for k in s:
            w = cuts(k, queued_dirs)
            if w:
                why[k] = w
            else:
                live.append(k)
        if len(live) >= 2 and len({files[k][1] for k in live}) >= 2:
            products = sorted({owner[k][0] for k in live})
            cand.append({
                "files": sorted(live),
                "homes": sorted({files[k][1] for k in live}),
                "products": products,
                # Адрес выноса выводится из ЧИСЛА ПРОДУКТОВ, а не из числа домов.
                # Вторая прописка внутри одного продукта адресуется в `pkg/`
                # платформы (`arch-new-util-ownership`), а не в фундамент: иначе
                # норма противоречила бы `arch-corelib-horizontal` на шести
                # своих же кандидатах из девяти.
                "address": "corelib" if len(products) > 1 else "pkg/ продукта %s" % products[0],
            })
        else:
            key = "+".join(sorted({w for ws in why.values() for w in ws})) or "0-одна-прописка"
            cut_reasons[key] = cut_reasons.get(key, 0) + 1
    cand.sort(key=lambda c: (-len(c["files"]), c["files"][0]))
    # ДВЕ величины храповика, помимо перечня. Предмет, получивший ТРЕТЬЮ
    # прописку, счёт ПРЕДМЕТОВ не меняет — он меняет счёт ФАЙЛОВ в них; поэтому
    # ведомость держит обе, и обе судятся точным числом, не потолком.
    second_home_dirs = set()
    subject_files = 0
    for s in subjects:
        subject_files += len(s)
        for k in s:
            p, rel = owner[k]
            second_home_dirs.add("%s:%s" % (p, os.path.dirname(rel)))
    return {
        "trees": {n: (t.repo, t.ref, getattr(t, "sha", t.ref), len(t.paths))
                  for n, t in trees.items()},
        "walked": walked, "comparable": comparable, "threshold": threshold,
        "subjects": len(subjects), "subject_files": subject_files,
        "second_home_dirs": second_home_dirs,
        "candidates": cand, "cut": cut_reasons,
        "relicense": (relicense_busl, relicense_agpl),
    }


def sunset_dirs(root):
    """Каталоги, объявленные ПОД СНЯТИЕ записью ведомости выноса.

    Признак исключения 8 — запись, а не догадка. Живость класса критерий сам
    спросить не умеет: сегодня он предписал бы добавить API в `corelib/quota`,
    пакет, который по записанному порядку снятия («corelib → kaname → kacho»,
    решение владельца 2026-09-16) снимается ПЕРВЫМ, — то есть вынос ушёл бы под
    снос вместе с пакетом.
    """
    res, cur = set(), None
    try:
        with open(os.path.join(root, "docs/foundation-candidates.yaml"), encoding="utf-8") as fh:
            text = fh.read()
    except IOError:
        return res
    for raw in text.split("\n"):
        s = raw.strip()
        if s.startswith("- package:"):
            cur = s.split(":", 1)[1].strip().strip('"')
        elif cur and s.startswith("decision:") and s.split(":", 1)[1].strip() == "sunset":
            res.add(cur)
    return res


def declared_by_tree_gate(trees):
    """Каталоги, чей путь импорта объявлен СЛОВАРЁМ ГЕЙТА ДЕРЕВА продукта.

    Опровержением показано, что вынос такого предмета СНИМАЕТ защиту:
    `checks.go` у края и у службы реестра объявляют СОСТАВ обязательных проверок
    токена, и объявление сверяет `internal/repohygiene`. Слитые в один файл
    фундамента, оба объявления становятся одним значением, `MissingChecks`
    тождественно пусто, и гейт зеленеет by construction — край снимет
    `CheckAudience`, объявление продолжит утверждать, что аудитория проверяется,
    и ни одна проба не покраснеет.
    """
    res = set()
    for name, t in trees.items():
        if name == "corelib":
            continue
        module = "github.com/PRO-Robotech/" + name
        for p, text in t.text.items():
            if "internal/repohygiene/" not in p:
                continue
            for lit in literals_of(text):
                if lit.startswith(module + "/"):
                    rel = lit[len(module) + 1:].split(".")[0]
                    res.add("%s:%s" % (name, rel))
    return res
