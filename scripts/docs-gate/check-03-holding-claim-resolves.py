#!/usr/bin/env python3
"""check-03 — «этот кейс уже держится» обязано называть координату, которая есть.

Что запрещает эта проверка. Приёмка, часть кейсов которой уже исполнена, несёт
таблицу состояния: кейс — состояние — чем держится. Такая строка читается как
СВИДЕТЕЛЬСТВО: следующий заход не строит названное второй раз и на него
опирается. Свидетельство проверяемо ровно тогда, когда названы ОБА элемента —
файл и имя проверки внутри него — и оба резолвятся в дереве продукта.

Класс, ради которого проверка заведена, наблюдался целиком: строка объявляла
кейс держащимся и называла файл, в котором требуемого утверждения не было;
вторая строка засчитывала исполненным кейс, чью половину дерево не несёт вовсе.
Обе выглядели одинаково с теми, что верны, — координата стояла, файл
существовал. Отличить их можно только спросив дерево ИМЕНЕМ проверки, а не
именем файла: файл переживает снятие теста, который в нём лежал.

Предмет — таблица, которую документ объявляет САМ: первая колонка озаглавлена
`кейс` (или `сценарий`) И есть колонка `чем держится`. Оба условия обязательны,
и второе без первого предметом не делает: колонка «чем держится» законно стоит и
в таблице слоёв, и в таблице цены плана — там она говорит о механизме, а не о
кейсе, и требовать от неё имени проверки значило бы ловить форму вместо
существа. Обе такие таблицы в корпусе есть, и на них проверка обязана молчать.
Документ без таблицы предметом не является; сколько документов её несут —
печатается переписью, чтобы «находок ноль» было отличимо от «предмет не найден».

Что требуется от таблицы состояния:

  P1. колонка СОСТОЯНИЯ обязана быть. Без неё «держится» и «держится
      наполовину» неотличимы, и половина уезжает в зачёт целого;
  P2. первая клетка строки — идентификатор кейса;
  P3. состояние — из ЗАКРЫТОГО набора (`держится` · `наполовину` · `не начат`).
      Свободная формулировка вернула бы прозу, которую и заменяет таблица;
  P4. `держится` и `наполовину` называют ≥1 путь и ≥1 проверку; путь обязан
      быть в СТВОЛЕ дерева продукта, имя вида `Test…` — обязано находиться в
      одном из названных файлов `.go` объявлением `func <имя>(`. Путь `.sh`/`.py`
      считается проверкой сам: скрипт и есть проба;
  P5. `не начат` не называет координат — иначе строка противоречит себе;
  P6. множество кейсов таблицы совпадает с множеством кейсов, объявленных
      сценариями. Обе стороны — находка: сценарий без строки уходит из счёта
      молча, строка без сценария засчитывает то, чего документ не требует.

ГДЕ СУДИТСЯ — В СТВОЛЕ ПРОДУКТА, А НЕ В РАБОЧЕЙ КОПИИ РЯДОМ

Координата резолвится по `origin/main` продукта, а не по индексу лежащей рядом
копии. Копия ОБЩАЯ: её ревизию переключает соседняя сессия, не спрашивая
отправляющего, — и вердикт, прочитанный с неё, есть функция чужого переключения.
Класс наблюдался целиком (`PRO-Robotech/kacho-workspace#543`): копия стояла на
релизной линии, где каталог службы переименован, и проверка объявила
несуществующими шесть координат, которые в стволе ЕСТЬ и в приёмке названы верно.
Отправка любой ветки блокировалась работой, к которой отправляющий не причастен,
а «починка» состояла бы в подгонке приёмки под линию — то есть в превращении
верного документа в ложный ровно к моменту вливания линии.

Тот же выбор и по той же причине сделан у `check-04` и у хука свежести
(`multi-agent-flow.md` §8): вердикт выносится по стволу, расхождение копии
называется ЧИСЛОМ — и в ОБЕ стороны. Односторонняя перепись здесь не годится:
копия на линии отстаёт на 0 и опережает ствол на сотни коммитов, то есть печатала
бы ровно то же, что копия вровень.

Ствол не резолвится (клон без этой ссылки) — судится индекс копии, и перепись
говорит это прямо, а не подставляет молча.

Разбор идёт по таблице markdown, а не по прозе: лексиконный предикат над
естественным языком в этом корпусе уже проверялся и контроль в обе стороны
провалил (`security.md` §«Механического детектора сборки НЕТ»). Здесь предмет —
структура, объявленная самим документом, поэтому у него есть ровно одно
прочтение.

ГРАНИЦА ПРЕДМЕТА: ПРОЗА ПРИЁМОК МАШИННО НЕ СУДИТСЯ — НИ ЗДЕСЬ, НИ РЯДОМ

Сказано отдельным разделом, потому что без него «находок ноль» читается шире,
чем есть. Эта проверка судит ТОЛЬКО таблицу состояния — сегодня это 69 строк в
3 приёмках. Прозаические координаты — координата в инлайн-коде вне такой
таблицы — в её предмет НЕ входят, и масштаб невидимого печатается переписью на
каждом прогоне (верхняя оценка: всё, что похоже на путь к файлу).

Их не судит и хук свежести: `docs/specs/*-acceptance.md` выведены из его набора
`LIVE_WS` НАМЕРЕННО и с замером — приёмка есть ДАТИРОВАННАЯ ЗАПИСЬ, она
«называет по имени снятое, и обвинять её в этом нельзя»; включение дало бы 2754
«находки» шума против 213 сигнала (`.claude/hooks/docfresh/docfresh.py`, комментарий
у `LIVE_WS` и §Объём его README). Тот же выбор сделан там и для дерева продукта —
`NOT_LIVE_MONO` исключает каталог `acceptance/`.

Отсюда следствие, которое обязан знать читатель вердикта: мёртвая координата в
прозе приёмки — НЕ находка этой проверки и не дефект по построению. Законных
видов таких координат в корпусе три, и все три наблюдались: координата,
НАМЕРЕННО названная старой, чтобы сказать «предмет переехал»; координата,
связанная ревизией (`git show "$R":<путь>`, `<rev>:<путь>`); и координата
ПЛАНИРУЕМОГО файла, помеченная `[новый]`. Предикат, который стал бы судить прозу,
обязан различать эти три вида, иначе он краснеет на верных документах — а гейт,
краснеющий на верном, отключают первым.

Что из этого следует для того, кто ищет мёртвые координаты приёмок: у этого
класса машинного судьи НЕТ, он держится вниманием и обзором, и это сказано здесь
вслух, а не подразумевается (`PRO-Robotech/kacho-workspace#589`).

Исходы: 0 — у каждой претензии координата резолвится; 1 — находки, каждая
названа; 2 — проверять нечего (нет дерева продукта либо нет ни одной таблицы).
"""
import os
import re as _re
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-03-holding-claim-resolves"

# Закрытый набор состояний. Расширять — только вместе с правилом, что новое
# состояние требует от строки: состояние без требования есть та же проза.
STATES = {
    "держится": "held",
    "наполовину": "half",
    "не начат": "none",
}

HOLDS_COL = re.compile(r"чем\s+держится", re.I)
STATE_COL = re.compile(r"состояние", re.I)
# Первая колонка таблицы состояния кейсов. Дискриминатор объявляет сам документ:
# без него под предмет попали бы таблица слоёв и таблица цены плана, где колонка
# «чем держится» законна и говорит о механизме, а не о кейсе.
CASE_COL = re.compile(r"^\s*(кейс|сценари)", re.I)
# Идентификатор кейса: XC-11-04, GEO-1-20, IAM-USR-BLK-NEG-PENDING не подходит
# (кейс нумерован), — предмет именно нумерованные кейсы приёмки.
CASE_ID = re.compile(r"([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-\d+)")
# Сценарий объявляется строкой тела: **XC-11-04 — …**
SCENARIO = re.compile(r"^\s*\*\*([A-Z][A-Z0-9]*(?:-[A-Z0-9]+)*-\d+)\s*[—-]")
TICK = re.compile(r"`([^`]+)`")
PATHISH = re.compile(r"^[A-Za-z0-9_./-]+/[A-Za-z0-9_.-]+\.[a-z]+$")
CHECKISH = re.compile(r"^Test[A-Za-z0-9_]*$")
SCRIPTISH = (".sh", ".py")


def _git0(repo, args):
    """Вывод git, разделённый NUL. `-z` намеренно: без него git ЭКРАНИРУЕТ путь с
    не-ASCII, и такой путь не совпал бы с координатой документа никогда."""
    out = subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True)
    if out.returncode != 0:
        return []
    return [p for p in out.stdout.split("\0") if p]


def tree_index(repo, ref):
    """Состав дерева продукта на СТВОЛЕ; без ствола — индекс рабочей копии."""
    if ref:
        return set(_git0(repo, ["ls-tree", "-r", "-z", "--name-only", ref]))
    return set(_git0(repo, ["ls-files", "-z"]))


def strip_cell(text):
    """Клетка без разметки: жирный, курсив, обратные кавычки, значки."""
    t = re.sub(r"[*_`✅❌⚠️·]+", " ", text)
    return re.sub(r"\s+", " ", t).strip()


def split_row(line):
    body = line.strip()
    if body.startswith(">"):
        body = body.lstrip(">").strip()
    if not body.startswith("|"):
        return None
    return [c.strip() for c in body.strip().strip("|").split("|")]


def tables(text):
    """Таблицы состояния документа: (номер строки заголовка, индексы колонок, строки)."""
    lines = text.split("\n")
    out = []
    i = 0
    while i < len(lines):
        cells = split_row(lines[i])
        if (not cells
                or not any(HOLDS_COL.search(c) for c in cells)
                or not CASE_COL.match(strip_cell(cells[0]))):
            i += 1
            continue
        holds = next(n for n, c in enumerate(cells) if HOLDS_COL.search(c))
        state = next((n for n, c in enumerate(cells) if STATE_COL.search(c)), None)
        rows, j = [], i + 1
        # Разделитель заголовка markdown пропускается, дальше — тело таблицы.
        while j < len(lines):
            r = split_row(lines[j])
            if not r:
                break
            if all(re.fullmatch(r":?-{2,}:?", c) for c in r if c):
                j += 1
                continue
            rows.append((j + 1, r))
            j += 1
        out.append({"line": i + 1, "holds": holds, "state": state, "rows": rows})
        i = j
    return out


def coordinates(cells):
    """Пути и имена проверок, названные строкой."""
    paths, checks = [], []
    for c in cells:
        for tok in TICK.findall(c):
            tok = tok.strip()
            if PATHISH.match(tok):
                paths.append(tok)
            elif CHECKISH.match(tok):
                checks.append(tok)
    return paths, checks


def declares(repo, ref, rel, name):
    """Объявлена ли функция `name` в файле `rel` НА СТВОЛЕ продукта.

    Содержимое берётся из объекта ссылки, а не с диска: файл рабочей копии
    принадлежит той ветке, на которую её переключили, и читать его значило бы
    выносить вердикт о чужом переключении. Без ствола (клон без этой ссылки)
    читается диск, и перепись говорит это прямо.
    """
    if ref:
        out = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (ref, rel)],
                             capture_output=True, text=True, errors="replace")
        if out.returncode != 0:
            return False
        body = out.stdout
    else:
        try:
            with open(os.path.join(repo, rel), encoding="utf-8",
                      errors="replace") as fh:
                body = fh.read()
        except OSError:
            return False
    return re.search(r"^func\s+%s\s*\(" % re.escape(name), body, re.M) is not None


def audit(root, repo, ref, where, index, rel, findings, stats):
    text = _lib.read(root, rel)
    tabs = tables(text)
    if not tabs:
        return False
    scenarios = set()
    for line in text.split("\n"):
        m = SCENARIO.match(line)
        if m:
            scenarios.add(m.group(1))
    listed = set()

    for tab in tabs:
        stats["tables"] += 1
        if tab["state"] is None:
            findings.append(
                "%s:%d — у таблицы состояния нет колонки состояния: «держится» и "
                "«держится наполовину» в ней неотличимы, и половина уезжает в зачёт "
                "целого" % (rel, tab["line"]))
            continue
        for lineno, cells in tab["rows"]:
            stats["rows"] += 1
            if len(cells) <= max(tab["holds"], tab["state"]):
                findings.append("%s:%d — в строке меньше клеток, чем колонок заголовка"
                                % (rel, lineno))
                continue
            cid = CASE_ID.search(strip_cell(cells[0]))
            if not cid:
                findings.append("%s:%d — первая клетка не называет кейса: %s"
                                % (rel, lineno, strip_cell(cells[0])[:60]))
                continue
            listed.add(cid.group(1))
            state = strip_cell(cells[tab["state"]]).lower()
            kind = next((v for k, v in STATES.items() if state.startswith(k)), None)
            if kind is None:
                findings.append(
                    "%s:%d — состояние «%s» вне закрытого набора (%s): свободная "
                    "формулировка возвращает прозу, которую таблица и заменяет"
                    % (rel, lineno, state[:40], " · ".join(sorted(STATES))))
                continue

            paths, checks = coordinates(cells)
            if kind == "none":
                if paths:
                    findings.append(
                        "%s:%d — кейс %s объявлен не начатым и при этом называет "
                        "координату (%s): строка противоречит себе"
                        % (rel, lineno, cid.group(1), ", ".join(paths)))
                continue

            if not paths:
                findings.append("%s:%d — кейс %s объявлен держащимся и не называет ни "
                                "одного файла" % (rel, lineno, cid.group(1)))
                continue
            alive = []
            for p in paths:
                stats["paths"] += 1
                if p in index:
                    alive.append(p)
                else:
                    findings.append(
                        "%s:%d — кейс %s ссылается на %s, которого в %s нет: "
                        "свидетельство не проверяемо"
                        % (rel, lineno, cid.group(1), p, where))
            scripts = [p for p in alive if p.endswith(SCRIPTISH)]
            if not checks and not scripts:
                findings.append(
                    "%s:%d — кейс %s называет файл, но не называет ПРОВЕРКУ. Файл "
                    "переживает снятие теста, который в нём лежал, поэтому имя файла "
                    "свидетельством не является" % (rel, lineno, cid.group(1)))
            for name in checks:
                stats["checks"] += 1
                gofiles = [p for p in alive if p.endswith(".go")]
                if not any(declares(repo, ref, p, name) for p in gofiles):
                    findings.append(
                        "%s:%d — кейс %s называет проверку %s, которой в %s нет ни в "
                        "одном из названных им файлов (%s)"
                        % (rel, lineno, cid.group(1), name, where,
                           ", ".join(gofiles) if gofiles else "файлов .go не названо"))

    if scenarios:
        for cid in sorted(scenarios - listed):
            findings.append(
                "%s — кейс %s объявлен сценарием и не имеет строки в таблице состояния: "
                "из счёта он уходит молча" % (rel, cid))
        for cid in sorted(listed - scenarios):
            findings.append(
                "%s — кейс %s стоит в таблице состояния, а сценария с таким "
                "идентификатором в документе нет" % (rel, cid))
    return True



# Координата-файл в инлайн-коде. Верхняя оценка НЕВИДИМОГО: считает всё, что
# похоже на путь к файлу, — включая координаты, законно названные мёртвыми
# (см. три вида в шапке). Число нужно не как вердикт, а чтобы «находок ноль»
# было отличимо от «прочитано ноль»: предмет проверки — 69 строк таблиц, а
# рядом лежат тысячи координат, которых не судит никто.
_PROSE_COORD = _re.compile(
    r"`([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.@-]+)+"
    r"\.(?:go|py|sh|sql|proto|ts|tsx|yaml|yml|md|json))")


def prose_scale(root, docs):
    """Сколько координат приёмок лежит ВНЕ предмета: (вхождений, приёмок)."""
    total = 0
    carriers = 0
    for rel in docs:
        try:
            with open(os.path.join(root, rel), encoding="utf-8",
                      errors="replace") as fh:
                n = len(_PROSE_COORD.findall(fh.read()))
        except OSError:
            continue
        total += n
        if n:
            carriers += 1
    return total, carriers

def main():
    root = _lib.workspace_root()
    repo = _lib.monorepo(root)
    if repo is None:
        _lib.void(NAME, "дерево продукта не найдено (ни KACHO_MONOREPO, ни "
                        "project/kacho) — координату проверить не по чему")
        return 2

    docs = _lib.tracked(root, "docs/specs/*-acceptance.md")
    if not docs:
        _lib.void(NAME, "отслеживаемых docs/specs/*-acceptance.md нет — читать нечего")
        return 2

    prov = _lib.provenance(repo)
    ref = prov["ref"]
    index = tree_index(repo, ref)
    # Находка обязана называть ТО, ГДЕ искали. «Нет в индексе монорепо» посылало
    # читателя к рабочей копии — то есть ровно туда, куда смотреть не следует.
    where = ("стволе продукта %s" % ref) if ref else "индексе рабочей копии продукта"

    findings = []
    stats = {"tables": 0, "rows": 0, "paths": 0, "checks": 0}
    carriers = [rel for rel in docs
                if audit(root, repo, ref, where, index, rel, findings, stats)]

    _lib.census(
        "%s: приёмок осмотрено %d; несут таблицу состояния %d (%s); таблиц %d, строк %d"
        % (NAME, len(docs), len(carriers),
           ", ".join(carriers) if carriers else "ни одной",
           stats["tables"], stats["rows"]))
    _lib.census(
        "%s: дерево продукта %s; путей в нём %d — проверено %d, имён проверок %d"
        % (NAME, _lib.provenance_line(repo, prov), len(index),
           stats["paths"], stats["checks"]))
    prose_n, prose_docs = prose_scale(root, docs)
    _lib.census(
        "%s: ВНЕ ПРЕДМЕТА — проза приёмок: координат-файлов в инлайн-коде %d "
        "в %d приёмках из %d (верхняя оценка). Их не судит ни эта проверка, ни "
        "хук свежести (docs/specs/*-acceptance.md выведены из LIVE_WS намеренно: "
        "приёмка — датированная запись). «Находок ноль» ниже относится ТОЛЬКО к "
        "таблицам состояния"
        % (NAME, prose_n, prose_docs, len(docs)))

    if not carriers:
        _lib.void(NAME, "ни одна приёмка не несёт таблицы состояния — предмет не найден; "
                        "это НЕ «находок ноль»")
        return 2

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        _lib.fail(NAME, "претензий без проверяемой координаты: %d" % len(findings))
        return 1

    _lib.passed(NAME, "координата резолвится у всех %d строк в %d таблицах"
                      % (stats["rows"], stats["tables"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
