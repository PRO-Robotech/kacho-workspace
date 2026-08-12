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
      быть в индексе монорепо, имя вида `Test…` — обязано находиться в одном из
      названных файлов `.go` объявлением `func <имя>(`. Путь `.sh`/`.py`
      считается проверкой сам: скрипт и есть проба;
  P5. `не начат` не называет координат — иначе строка противоречит себе;
  P6. множество кейсов таблицы совпадает с множеством кейсов, объявленных
      сценариями. Обе стороны — находка: сценарий без строки уходит из счёта
      молча, строка без сценария засчитывает то, чего документ не требует.

Разбор идёт по таблице markdown, а не по прозе: лексиконный предикат над
естественным языком в этом корпусе уже проверялся и контроль в обе стороны
провалил (`security.md` §«Механического детектора сборки НЕТ»). Здесь предмет —
структура, объявленная самим документом, поэтому у него есть ровно одно
прочтение.

Исходы: 0 — у каждой претензии координата резолвится; 1 — находки, каждая
названа; 2 — проверять нечего (нет монорепо либо нет ни одной таблицы).
"""
import os
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


def monorepo(ws):
    """Путь монорепо: KACHO_MONOREPO, иначе project/kacho. None — нет."""
    env = os.environ.get("KACHO_MONOREPO")
    cand = env if env else os.path.join(ws, "project", "kacho")
    return cand if os.path.isdir(os.path.join(cand, ".git")) else None


def repo_index(repo):
    out = subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True)
    return set(p for p in out.stdout.split("\n") if p)


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


def declares(repo, rel, name):
    """Объявлена ли функция `name` в файле `rel` монорепо."""
    path = os.path.join(repo, rel)
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            body = fh.read()
    except OSError:
        return False
    return re.search(r"^func\s+%s\s*\(" % re.escape(name), body, re.M) is not None


def audit(root, repo, index, rel, findings, stats):
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
                        "%s:%d — кейс %s ссылается на %s, которого в индексе монорепо "
                        "нет: свидетельство не проверяемо"
                        % (rel, lineno, cid.group(1), p))
            scripts = [p for p in alive if p.endswith(SCRIPTISH)]
            if not checks and not scripts:
                findings.append(
                    "%s:%d — кейс %s называет файл, но не называет ПРОВЕРКУ. Файл "
                    "переживает снятие теста, который в нём лежал, поэтому имя файла "
                    "свидетельством не является" % (rel, lineno, cid.group(1)))
            for name in checks:
                stats["checks"] += 1
                gofiles = [p for p in alive if p.endswith(".go")]
                if not any(declares(repo, p, name) for p in gofiles):
                    findings.append(
                        "%s:%d — кейс %s называет проверку %s, которой нет ни в одном "
                        "из названных им файлов (%s)"
                        % (rel, lineno, cid.group(1), name,
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


def main():
    root = _lib.workspace_root()
    repo = monorepo(root)
    if repo is None:
        _lib.void(NAME, "монорепо не найдено (ни KACHO_MONOREPO, ни project/kacho) — "
                        "координату проверить не по чему")
        return 2

    docs = _lib.tracked(root, "docs/specs/*-acceptance.md")
    if not docs:
        _lib.void(NAME, "отслеживаемых docs/specs/*-acceptance.md нет — читать нечего")
        return 2

    index = repo_index(repo)
    head = subprocess.run(["git", "-C", repo, "rev-parse", "--short", "HEAD"],
                          capture_output=True, text=True).stdout.strip()

    findings = []
    stats = {"tables": 0, "rows": 0, "paths": 0, "checks": 0}
    carriers = [rel for rel in docs if audit(root, repo, index, rel, findings, stats)]

    _lib.census(
        "%s: приёмок осмотрено %d; несут таблицу состояния %d (%s); таблиц %d, строк %d; "
        "дерево продукта %s — путей проверено %d, имён проверок %d"
        % (NAME, len(docs), len(carriers),
           ", ".join(carriers) if carriers else "ни одной",
           stats["tables"], stats["rows"], head or "неизвестно",
           stats["paths"], stats["checks"]))

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
