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
файл в стороне. Замер опровержения: больше половины файлов-кандидатов ссылались
на идентификатор, объявленный сиблингом; компиляционные пробы дали `undefined:
envPrefix` и `undefined: schema`, где `schema = "kacho_registry"` — продуктовый
литерал, спрятанный соседним файлом. Здесь отсев спрашивает КАТАЛОГ ПАКЕТА
целиком: объединение импортов и объединение литералов всех его `.go`.

С КАКОЙ СТОРОНЫ БЕРЁТСЯ НЕПОДВИЖНАЯ ТОЧКА (исправлено приёмкой 2026-09-21)

Исключение 1 (направление) не отсекает импорт предмета, который САМ стоит в
очереди выноса: после выноса такое ребро становится внутренним. Очередь поэтому
определена через саму себя, и у такого определения ДВЕ неподвижные точки.
Сторона выбрана и обоснована:

  СВЕРХУ (здесь): очередь начинается ПОЛНОЙ — все каталоги предметов со второй
    пропиской — и СУЖАЕТСЯ, из неё уходит только то, что отсекается ДОКАЗАННО:
    по признаку, не зависящему от состава очереди (политика, лицензия,
    контракт, судья, одноимённость, снятие, объявление о себе), либо по импорту
    НАРУЖУ очереди. Это НАИБОЛЬШАЯ неподвижная точка.
  СНИЗУ (было): очередь начинается ПУСТОЙ и растёт. Это НАИМЕНЬШАЯ неподвижная
    точка, и она неверна для этого предмета.

Почему верна верхняя. Во-первых, печатаемый счёт объявлен ВЕРХНЕЙ ГРАНИЦЕЙ
очереди решений, а не автоматическим переносом; верхняя граница обязана браться
наибольшей точкой, иначе она границей не является. Во-вторых — и это класс
дефекта, ради которого направление и перевёрнуто, — снизу ОТСЕЧЕНИЕ ГАСИТСЯ
ДОПИСЫВАНИЕМ: попасть в очередь можно, только пережив отсев, а пережить отсев
можно, только уже стоя в очереди. Значит предмет, чей единственный блокирующий
импорт указывает на него самого или на партнёра по циклу, снизу НЕДОСТИЖИМ и
отсекается навсегда, а добавление обычного теста рядом с любым кандидатом гасит
кандидата молча. Сверху дописанный импорт отсечения добавить не может: он
отсекает, только если указывает ВНЕ очереди, — то есть на предмет, у которого
второй прописки нет, и это содержательный признак, а не артефакт порядка.

Что сломается при обратном направлении — замерено на стволе 2026-09-21:
`kacho:services/storage/internal/apps/kacho/shared/quota/states.go` ↔
`kacho:services/registry/internal/apps/kacho/quota/states.go` (пара состояний
квоты в двух службах платформы). Соседний `kinds_test.go` объявлен `package
quota_test` и импортирует СВОЙ ЖЕ пакет; снизу это отсекало предмет в первом
круге, обе копии выбывали, и объявленный счёт кандидатов был 1 вместо 2.

ДВА РЕКУРСИВНЫХ СЛУЧАЯ РАЗОБРАНЫ ЯВНО

  САМОИМПОРТ каталога. Единственная законная его форма в Go — ВНЕШНИЙ ТЕСТОВЫЙ
    пакет (`package x_test`) в том же каталоге: обычный код себя импортировать
    не может, это цикл импорта. Такое ребро направления НЕ ограничивает вовсе:
    судья едет вместе с предметом либо отсекается исключением 6, а ссылка после
    выноса указывает на новый адрес ТОГО ЖЕ пакета. Классифицируется как НЕ
    отсечение, и явно, а не тем, что каталог случайно оказался в очереди: иначе
    предмет, выбывший по другой причине, получил бы вторым вердиктом ложную
    причину «направление».
  ЦИКЛ ИЗ ДВУХ ПРЕДМЕТОВ. Оба стоят в очереди, поэтому взаимный импорт не
    отсекает ни одного: после выноса ребро становится внутренним для фундамента.
    Классифицируется как ОДИН неделимый вынос — обе стороны уезжают одним
    изменением (`poly-copy-atomic`, запрет #20); порознь вынос завёл бы
    `require` на продукт в `go.mod` фундамента. Если же партнёр второй прописки
    не имеет, цикла нет: импорт указывает ВНЕ очереди и отсекает по признаку 1.

ЧТО ЧИТАЕТСЯ

РЕВИЗИЯ каждого клона, содержимое — `git cat-file --batch`, не рабочая копия
(`poly-copy-trunk-predicate`). На грязном дереве или на ветке чтение рабочей копии
мерило бы другой предмет, и мерило бы молча. Какая ревизия — решает вызывающий:
ствол `origin/main` по умолчанию либо ЗАКРЕПЛЁННАЯ ревизия ведомости (`revs`).

ПОЧЕМУ ВЕРДИКТ НЕ ИДЁТ ЗА СОСТОЯНИЕМ `fetch` КЛОНА (возврат check-verifier, #724)

Ствол клона — не ствол продукта, а то, что в клон последний раз подтянули. Без
точки отсчёта в ведомости отставший клон читался как изменение продукта: клон
kacho с `origin/main` на `f445aaaa554` при нетронутом воркспейсе давал «РОСТ
subjects+1 files+2» — не выросло ничего, клон был старым. Поэтому ведомость
закрепляет ревизию каждого ствола (`ceiling.rev`), и `pin_state` сверяет её со
стволом клона ДО замера: ствол ПОЗАДИ закреплённой ревизии — «считать не по чему»,
а не находка о продукте. Та же форма, что у `scripts/comment-language-gate`.

ФОРМА ВЕДОМОСТИ — ФАКТ ВОРКСПЕЙСА, А НЕ ПРЕДПОСЫЛКА (#856)

Ведомость лежит в этом дереве и судится без клонов, поэтому её неполнота —
находка с именем поля (`ledger_form`), а не «считать не по чему». Прежде снятый
блок ревизий давал код 2, и хук отправки печатал «нет клона» при клонах на месте
и выходил нулём: красным это делал только ручной шаг конвейера. Код 2 остаётся
ровно за тем, чего в дереве нет по построению, — клоном и его стволом.
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

# ОБЁРТКА TestMain — НЕ ПРЕДМЕТ (ws#903). `TestMain` объявляется в КАЖДОМ
# пакете, которому он нужен: разделить его между пакетами язык не позволяет,
# поэтому файл, чья ВСЯ работа — вызов пакета фундамента, существует в N
# копиях по построению, а его предмет уже живёт в фундаменте одним экземпляром.
# Вынести такой файл некуда, и храповик, считавший его предметом, краснел на
# каждом новом тестовом пакете со стандартной обёрткой — на штатном состоянии
# (`cachedverdictmain_test.go` → `corelib/treecorpus`, `testmain_pgtest_test.go`
# → `corelib/pgtest`).
#
# Признак УЗКИЙ и проверяется целиком: файл `_test.go`; объявление верхнего
# уровня в нём ровно ОДНО, и это `func TestMain(<имя> *testing.M)`; ТЕЛО
# TestMain — РОВНО одна из форм ЗАКРЫТОГО перечня `SHIM_FORMS` ниже, а не
# «где-то в теле упомянут пакет фундамента». Вторая функция, тип, переменная
# или константа рядом — и файл снова предмет; любая иная строка тела — тоже:
# копируемая логика уже не только вызов фундамента.
#
# Почему тело судится ФОРМОЙ, а не поиском имени (возврат check-verifier,
# ws#903). Первая редакция засчитывала обёрткой тело, в котором имя пакета
# фундамента встречалось хоть раз — и хвостовой комментарий строки
# (`os.Exit(m.Run()) // pgtest.Run(…)`) этим упоминанием был, и лишний
# `os.Setenv` перед вызовом файл из обёрток не выводил. На живых стволах
# 2026-10-03 так снималась `kaname:internal/repo/kaname/pg/testmain_test.go`:
# её тело собирает модель процесса и судит окружение до вызова фундамента —
# это предмет, а не обёртка. Комментарии снимаются РАЗБОРОМ лексем (строковые
# литералы целы, `//` внутри строки комментарием не считается), пробелы вне
# литералов сжимаются, и сжатое тело сверяется с формой ЦЕЛИКОМ.
#
# ЗАКРЫТЫЙ перечень законных форм — ровно те, которыми обёртки записаны на
# стволах (выведено обходом `Tree.shims` по трём стволам 2026-10-03, ось L
# `inject.sh` держит каждую законным близнецом):
#   pgtest-exit   `os.Exit(pgtest.Run(m, pgtest.Config{…}))`;
#   pgtest-bare   `pgtest.Run(m, pgtest.Config{…})` — без `os.Exit`;
#   treecorpus    `if msg := treecorpus.CachedVerdictRefusal(); msg != "" {
#                 fmt.Fprintln(os.Stderr, "<метка>"+msg); os.Exit(1) };
#                 os.Exit(m.Run())`.
# `Config{…}` — однострочный или многострочный составной литерал; каждое его
# поле — `Имя: выражение`, и выражение не несёт функционального литерала
# (`func(`): логика, спрятанная в значение поля, — тоже иная строка тела.
# Новая форма обёртки заводится строкой этого перечня И близнецом оси L, а не
# расширением образца: без близнеца её законность ничем не доказана.
_TOPDECL = re.compile(r"^(func|type|var|const)\b")
_TESTMAIN = re.compile(r"^func\s+TestMain\s*\(\s*(\w+)\s+\*testing\.M\s*\)\s*\{")
_IMPORT_NAMED = re.compile(r'^\s*(?:([A-Za-z_][\w]*)\s+)?"([^"]+)"')

PGTEST = FOUNDATION_MODULE + "/pgtest"
TREECORPUS = FOUNDATION_MODULE + "/treecorpus"
SHIM_FORMS = ("pgtest-exit", "pgtest-bare", "treecorpus")


def strip_go_comments(text):
    """Текст без комментариев; литералы целы, переводы строк сохранены.

    Разбор лексем, а не образец по строке: `//` внутри строкового литерала —
    не комментарий, а хвостовой `// …` после кода — комментарий. Блочный
    комментарий заменяется пробелом (и своими переводами строк), чтобы строки
    файла не сливались.
    """
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(" " + "\n" * text.count("\n", i, j))
            i = j
            continue
        if c in "\"'`":
            j = i + 1
            while j < n and text[j] != c:
                if c != "`" and text[j] == "\\":
                    j += 1
                elif c != "`" and text[j] == "\n":
                    break
                j += 1
            out.append(text[i:j + 1])
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _squeeze(code):
    """Пробелы вне литералов сняты; строка — `""` пустая, `"S"` непустая; руна — `'R'`."""
    out, i, n = [], 0, len(code)
    while i < n:
        c = code[i]
        if c in "\"`'":
            j = i + 1
            while j < n and code[j] != c:
                j += 2 if (c != "`" and code[j] == "\\") else 1
            out.append("'R'" if c == "'" else ('""' if j == i + 1 else '"S"'))
            i = j + 1
            continue
        if not c.isspace():
            out.append(c)
        i += 1
    return "".join(out)


def _closing(s, i):
    """Индекс скобки, закрывающей открывающую `s[i]`, либо -1 (литералы уже сжаты)."""
    pair = {"(": ")", "{": "}", "[": "]"}
    stack = []
    for j in range(i, len(s)):
        if s[j] in pair:
            stack.append(pair[s[j]])
        elif s[j] in ")}]":
            if not stack or stack.pop() != s[j]:
                return -1
            if not stack:
                return j
    return -1


def _top_split(s, sep=","):
    parts, depth, cur = [], 0, []
    for ch in s:
        if ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        if ch == sep and depth == 0:
            parts.append("".join(cur))
            cur = []
            continue
        cur.append(ch)
    parts.append("".join(cur))
    return parts


_CFG_FIELD = re.compile(r"^[A-Z]\w*:.+$")


def _config_ok(inner):
    """Поля составного литерала `Config{…}`: каждое `Имя: выражение` без `func(`."""
    fields = [f for f in _top_split(inner) if f != ""]
    return bool(fields) and all(_CFG_FIELD.match(f) and "func(" not in f for f in fields)


def _pgtest_form(body, m, alias, std_os):
    """Имя законной формы pgtest для сжатого тела либо None."""
    for form, head, tail in (("pgtest-exit", "os.Exit(%s.Run(%s,%s.Config{" % (alias, m, alias), "}))"),
                             ("pgtest-bare", "%s.Run(%s,%s.Config{" % (alias, m, alias), "})")):
        if form == "pgtest-exit" and not std_os:
            continue
        if not body.startswith(head):
            continue
        brace = len(head) - 1
        close = _closing(body, brace)
        if close < 0 or body[close:] != tail:
            continue
        inner = body[brace + 1:close]
        if inner.endswith(","):
            inner = inner[:-1]
        if _config_ok(inner):
            return form
    return None


def _treecorpus_form(body, m, alias):
    pat = (r'^if(\w+):=%s\.CachedVerdictRefusal\(\);\1!=""\{'
           r'fmt\.Fprintln\(os\.Stderr,"S"\+\1\)os\.Exit\(1\)\}'
           r'os\.Exit\(%s\.Run\(\)\)$') % (re.escape(alias), re.escape(m))
    return "treecorpus" if re.match(pat, body) else None


def testmain_shim(rel, text):
    """Путь импорта фундамента, который зовёт обёртка `TestMain`, либо None.

    Обёртка — только файл, у которого тело TestMain целиком совпадает с одной из
    форм `SHIM_FORMS`; см. шапку выше.
    """
    if not rel.endswith("_test.go"):
        return None
    code = strip_go_comments(text)
    names, inside, decls = {}, False, []
    for raw in code.split("\n"):
        st = raw.strip()
        if st.startswith("import ("):
            inside = True
            continue
        if inside:
            if st.startswith(")"):
                inside = False
                continue
            mm = _IMPORT_NAMED.match(raw)
            if mm:
                names[mm.group(1) or mm.group(2).rsplit("/", 1)[-1]] = mm.group(2)
            continue
        if st.startswith("import "):
            mm = _IMPORT_NAMED.match(st[len("import "):])
            if mm:
                names[mm.group(1) or mm.group(2).rsplit("/", 1)[-1]] = mm.group(2)
            continue
        if _TOPDECL.match(raw):
            decls.append(raw)
    if len(decls) != 1:
        return None
    head = _TESTMAIN.match(decls[0])
    if not head:
        return None
    m = head.group(1)
    squeezed = _squeeze(code)
    start = squeezed.find("funcTestMain(")
    if start < 0:
        return None
    brace = squeezed.find("{", start)
    close = _closing(squeezed, brace)
    if close < 0:
        return None
    body = squeezed[brace + 1:close]
    by_path = dict((path, name) for name, path in names.items())
    alias = by_path.get(PGTEST)
    # `os` и `fmt` в формах — пакеты стандартной библиотеки, а не одноимённый
    # импорт продукта: иначе `os.Exit` под чужим именем прошёл бы формой.
    std_os, std_fmt = names.get("os") == "os", names.get("fmt") == "fmt"
    if alias and _pgtest_form(body, m, alias, std_os):
        return PGTEST
    alias = by_path.get(TREECORPUS)
    if alias and std_os and std_fmt and _treecorpus_form(body, m, alias):
        return TREECORPUS
    return None


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


_REV = re.compile(r"^[0-9a-f]{40}$")


def resolve(repo, rev):
    """Полная ревизия коммита либо None — её в клоне нет."""
    out = subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "--quiet",
                          rev + "^{commit}"], capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 and out.stdout.strip() else None


def is_ancestor(repo, older, newer):
    return subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor",
                           older, newer], capture_output=True).returncode == 0


def declared_revs(text):
    """({продукт: ревизия}, [неразобранное]) из блока `rev:` под `ceiling:`.

    Форма: `ceiling:`, под ним по два пробела `rev:`, под ним по четыре — имя
    продукта и полная ревизия. Строка внутри `rev:`, не подошедшая под форму, —
    ошибка разбора, а не пропуск: опечатка в имени продукта иначе делала бы
    закрепление необъявленным молча.
    """
    revs, bad, inside, in_rev = {}, [], False, False
    for n, raw in enumerate(text.split("\n"), 1):
        if raw.startswith("ceiling:"):
            inside = True
            continue
        if not inside:
            continue
        if raw[:1] not in (" ", "\t", "#", ""):
            break
        s = raw.split("#", 1)[0].rstrip()
        if not s.strip():
            continue
        if re.match(r"^  rev:\s*$", s):
            in_rev = True
            continue
        if re.match(r"^  \S", s):
            in_rev = False
            continue
        if not in_rev:
            continue
        m = re.match(r"^    (\w+):\s*(\S+)\s*$", s)
        if m and m.group(1) in PRODUCTS:
            revs[m.group(1)] = m.group(2).strip("\"'")
        else:
            bad.append("строка %d «%s»" % (n, raw.strip()))
    return revs, bad


CEILING_KEYS = ("subjects", "files", "actionable")


def declared_ceiling(text):
    """{ключ: число} из блока `ceiling:` — только те из CEILING_KEYS, что стоят числом."""
    res, inside = {}, False
    for raw in text.split("\n"):
        if raw.startswith("ceiling:"):
            inside = True
            continue
        if inside and raw[:1] not in (" ", "\t", "#", ""):
            inside = False
        if not inside:
            continue
        m = re.match(r"  (\w+):\s*(\d+)\s*$", raw)
        if m and m.group(1) in CEILING_KEYS:
            res[m.group(1)] = int(m.group(2))
    return res


def ledger_form(text):
    """(числа, ревизии, находки) — ФОРМА ведомости, каждая находка с ИМЕНЕМ ПОЛЯ.

    Единственное место, где судится полнота ведомости; оба держателя набора
    зовут его ДО сверки с клонами. Поле, которого нет, — находка о дереве
    воркспейса: оно производится правкой этого файла и ни от какого клона не
    зависит. Имя поля печатается адресом `ceiling.<ключ>` либо
    `ceiling.rev.<продукт>`, чтобы находку можно было исполнить, не читая кода.
    """
    nums = declared_ceiling(text)
    revs, bad = declared_revs(text)
    findings = []
    if not re.search(r"(?m)^ceiling:", text):
        findings.append("нет блока `ceiling:` — ни одного числа и ни одной ревизии "
                        "храповику не объявлено")
    for k in CEILING_KEYS:
        if k not in nums:
            findings.append("`ceiling.%s` не объявлено числом — храповику по этой "
                            "единице сверять не с чем" % k)
    for b in bad:
        findings.append("`ceiling.rev`: %s не разобрана — опечатка в имени продукта "
                        "делала бы закрепление необъявленным молча" % b)
    for name in PRODUCTS:
        decl = revs.get(name)
        if decl is None:
            findings.append("`ceiling.rev.%s` не объявлено — ревизия ствола %s не "
                            "закреплена, и числа ведомости ни о какой ревизии не "
                            "утверждают" % (name, name))
        elif not _REV.match(decl):
            findings.append("`ceiling.rev.%s: %s` — не полная ревизия (40 знаков): "
                            "сокращённая неоднозначна со временем, а имя ветки "
                            "движется" % (name, decl))
    return nums, revs, findings


def pin_state(root, revs):
    """Сверка закреплённых ревизий со стволами клонов — ПРЕДПОСЫЛКА вердикта.

    Зовётся ПОСЛЕ `ledger_form` без находок: полнота и форма ревизий судятся там,
    и здесь их второго представления нет. Вызов на неполной ведомости — ошибка
    вызывающего, а не исход: он падает исключением, а не выдаёт «считать не по
    чему».

    Закреплённая ревизия обязана быть предком ствола клона либо им самим. Ствол
    ПОЗАДИ неё — клон не подтянут (или ревизия есть коммит ветки поверх ствола:
    без сети их не различить) — это «считать не по чему», а не находка. Ревизия
    ни предок, ни потомок ствола — находка: точкой отсчёта стал коммит, которого
    в стволе нет.

    {"pins": {продукт: ревизия}, "trunks": {продукт: ревизия}, "findings": […],
    "voids": […]}; `pins` и `trunks` полны только при пустых `findings`/`voids`.
    """
    res = {"pins": {}, "trunks": {}, "findings": [], "voids": []}
    for name in PRODUCTS:
        decl = revs.get(name)
        if decl is None or not _REV.match(decl):
            raise ValueError("pin_state на неполной ведомости: `ceiling.rev.%s` = %r — "
                             "сначала ledger_form" % (name, decl))
        repo = clone(root, name)
        if repo is None:
            res["voids"].append("%s: клона нет — условие создаётся клоном в "
                                "project/%s либо переменной KACHO_HOME_%s"
                                % (name, name, name.upper()))
            continue
        ref = trunk_ref(repo)
        trunk = resolve(repo, ref) if ref else None
        if trunk is None:
            res["voids"].append("%s: ствол клона %s не резолвится" % (name, repo))
            continue
        pin = resolve(repo, decl)
        if pin is None:
            res["voids"].append("%s: закреплённой ревизии %s в клоне %s нет — подтянуть "
                                "ствол клона (`git fetch`), сверять не с чем"
                                % (name, decl[:11], repo))
            continue
        if pin != trunk and not is_ancestor(repo, pin, trunk):
            if is_ancestor(repo, trunk, pin):
                res["voids"].append("%s: ствол клона %s (%s) ПОЗАДИ закреплённой ревизии "
                                    "%s — ссылку не тянули либо ревизия есть коммит ветки "
                                    "поверх ствола; подтянуть ствол клона и прогнать заново"
                                    % (name, ref, trunk[:11], pin[:11]))
            else:
                res["findings"].append("%s: закреплённая ревизия %s НЕ НА СТВОЛЕ %s (%s): "
                                       "точкой отсчёта стал коммит, которого в стволе нет, "
                                       "— числа о нём о продукте не говорят"
                                       % (name, pin[:11], ref, trunk[:11]))
            continue
        res["pins"][name] = pin
        res["trunks"][name] = trunk
    return res


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
        self.shims = set()
        for p, t in self.text.items():
            d = os.path.dirname(p)
            self.pkg_files.setdefault(d, []).append(p)
            self.pkg_imports.setdefault(d, set()).update(imports_of(t))
            self.pkg_literals.setdefault(d, set()).update(literals_of(t))
            if testmain_shim(p, t):
                self.shims.add(p)
                continue
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


def measure(root, threshold=0.70, relicense_busl=False, relicense_agpl=False, revs=None):
    """Полный замер. Возвращает словарь; ключ `void` — предмета нет (третий исход).

    `revs` — {продукт: ревизия}, по которой мерить; без него — ствол клона.
    """
    trees, missing = {}, []
    for name in PRODUCTS:
        repo = clone(root, name)
        if repo is None:
            missing.append(name)
            continue
        ref = trunk_ref(repo) if revs is None else revs.get(name)
        if ref is None:
            missing.append(name + (" (ствол не резолвится)" if revs is None
                                   else " (ревизия замера не названа)"))
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
    package_files = {}
    for name, t in trees.items():
        for d, ps in t.pkg_files.items():
            package_files["%s:%s" % (name, d)] = sorted("%s:%s" % (name, p) for p in ps)

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
        # 1 — направление зависимости, КАК НАИБОЛЬШАЯ НЕПОДВИЖНАЯ ТОЧКА: импорт
        # предмета, который сам стоит в очереди выноса, не отсекает. Иначе
        # очередь строится в неверном порядке: 11 файлов в шести домах были
        # объявлены невыносимыми единственно из-за импорта `kacho/pkg/refusal` —
        # предмета, который сам обязан переехать. Сторона, с которой точка
        # берётся, обоснована в шапке модуля; здесь — два рекурсивных случая.
        self_key = "%s:%s" % (product, d)
        outside = set()
        for imp in product_imports(t.pkg_imports.get(d, set())):
            ip, idir = import_to_home(imp)
            key = "%s:%s" % (ip, idir)
            # САМОИМПОРТ: каталог назвал САМ СЕБЯ. В Go это умеет только внешний
            # тестовый пакет (`package x_test`) того же каталога — обычный код
            # себя импортировать не может. Направления такое ребро не
            # ограничивает: судья едет вместе с предметом либо отсекается
            # исключением 6, а ссылка после выноса указывает на новый адрес того
            # же пакета. Снимается ЯВНО, а не тем, что каталог оказался в
            # очереди: предмет, выбывший по другой причине, иначе получил бы
            # вторым вердиктом ложную причину «направление».
            if key == self_key:
                continue
            # ЦИКЛ: партнёр стоит в очереди — ребро после выноса внутреннее,
            # предметы уезжают одним изменением (`poly-copy-atomic`). Партнёр
            # вне очереди — второй прописки у него нет, и это отсечение по
            # существу, а не артефакт порядка обхода.
            if ip and key in queued_dirs:
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

    # ── НЕПОДВИЖНАЯ ТОЧКА — СВЕРХУ ──────────────────────────────────────────
    # Очередь начинается ПОЛНОЙ и сужается: уходит только доказанно отсечённое.
    # Обоснование стороны — в шапке модуля; коротко: печатаемый счёт объявлен
    # ВЕРХНЕЙ ГРАНИЦЕЙ, а верхняя граница берётся наибольшей точкой, и снизу
    # отсечение гасится дописыванием обычного теста.
    subject_dirs = set()
    for s in subjects:
        for k in s:
            p, rel = owner[k]
            subject_dirs.add("%s:%s" % (p, os.path.dirname(rel)))
    queued_dirs = set(subject_dirs)
    # nxt ⊆ queued_dirs ПО ПОСТРОЕНИЮ (очередь состоит из каталогов предметов, и
    # шаг её только сужает), поэтому шагов не больше, чем каталогов: предел
    # назван замером, а не «поставил побольше».
    rounds = 0
    for rounds in range(1, len(subject_dirs) + 2):
        kept = set()
        for s in subjects:
            for k in s:
                if not cuts(k, queued_dirs):
                    kept.add(k)
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
        "shims": sum(len(t.shims) for t in trees.values()),
        "subjects": len(subjects), "subject_files": subject_files,
        "second_home_dirs": second_home_dirs,
        # Файлы КАЖДОГО пакета ствола: этим `check-01` проверяет, что координата
        # довода `keep` указывает на настоящий файл названного предмета, а не на
        # дописанный текст.
        "package_files": package_files,
        "fixpoint_rounds": rounds, "queued_dirs": queued_dirs,
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
