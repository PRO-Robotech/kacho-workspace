#!/usr/bin/env python3
"""check-06 — ведомость обесценивания записей пересверки ПОЛНА в обе стороны.

ЧТО УТВЕРЖДАЕТСЯ

Для КАЖДОГО файла пересверки в каталоге `…/revalidation/` верно ровно одно из
двух: либо его отпечаток равен отпечатку действующей редакции замысла (запись
действующая), либо у него есть строка в ведомости `SUPERSEDED.yaml`. Третьего
состояния нет. И обратно: строка ведомости, у которой нет файла, — такая же
находка, как молчание о существующем файле.

ЗАЧЕМ ЭТА ПРОВЕРКА СУЩЕСТВУЕТ

Ведомость перечисляет обесцененные записи и сама же называет предел своего
перечня: запись, добавленная в каталог БЕЗ своей строки, молча прочитается как
действующая. Это известный класс — арифметика по строкам слепа к строке, которой
нет: сумма по перечню не видит отсутствующего элемента, потому что складывает
ровно то, что перечислено. До этой проверки полнота держалась вниманием, и
дерево это подтвердило: пятая запись (`1e287a16…`) легла в каталог, а объявленные
ведомостью числа остались от четырёх.

ПОЧЕМУ ПЕРЕЧЕНЬ БЕРЁТСЯ ОБХОДОМ ДЕРЕВА, А НЕ ИЗ ВЕДОМОСТИ

Проверка, читающая состав каталога из самой ведомости, сверяет ведомость с
ведомостью и на отсутствующей строке зеленеет по построению. Здесь состав —
результат обхода индекса (`git ls-files --cached --others --exclude-standard`
по `docs/specs/reviews`), а ведомость входит только ВТОРОЙ стороной сверки.

ЧЕМ ОБХОД ОГРАНИЧЕН — НАЗВАНО ПРЯМО

1. Рассматриваются пути вида `docs/specs/reviews/<каталог>/revalidation/<файл>`
   — ровно один уровень каталога между корнем ревью и `revalidation`.
2. Записью пересверки считается файл, чьё имя лежит в пространстве имён
   отпечатков: `^[0-9a-f]{64}\\.md$`. Это не догадка о правиле именования, а
   само правило каталога: имя файла ЕСТЬ отпечаток прочитанного предмета, и
   ведомость названа ASCII-словом именно затем, чтобы под этот предикат не
   попасть.
3. Файл `.md`, который под предикат имени не попал, но объявляет в шапке
   отпечаток (значение из 64 hex-цифр в обратных кавычках, метка ЛЮБАЯ), —
   находка, а не тишина: он объявляет отпечаток и при этом невидим предикату
   действующей редакции. Слепая зона тем и опасна, что молчит. Прозаический
   сосед без такого значения — молчание: ось `E'` инъекции на нём и стоит.
4. Каталог `initial/` под предикат не попадает НАМЕРЕННО: первичный разбор
   привязан к приёмке, а не к замыслу, и правка замысла его не обесценивает.
5. Ведомости у каталога может не быть вовсе — тогда строк ноль, и предикат от
   этого не ослабевает: каталог, где все записи обесценены, а ведомости нет,
   лжёт ровно так же.

ДЕЙСТВУЮЩАЯ ЗАПИСЬ ОПРЕДЕЛЯЕТСЯ ЗАМЕРОМ, А НЕ ИМЕНЕМ

Отпечаток замысла считается ЗДЕСЬ, на месте, по содержимому файла — тот же
SHA-256, что даёт `sha256sum <путь>`; перепись печатает и путь, и полученное
число, чтобы человек повторил. Ни один известный отпечаток в этом файле не
выписан: выписанный пережил бы следующую редакцию замысла и превратил бы
проверку в память о прошлом.

Исходы: 0 — каталоги осмотрены, находок 0; 1 — находка, каждая названа
координатой; 2 — проверять нечего (каталогов пересверки нет, замысел не
читается, разборщик YAML недоступен).
"""
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-06-revalidation-superseded-complete"

REVIEWS = "docs/specs/reviews"
LEDGER_NAME = "SUPERSEDED.yaml"

# Пространство имён записи: имя файла ЕСТЬ отпечаток прочитанного предмета.
RECORD_RE = re.compile(r"^[0-9a-f]{64}\.md$")

# Путь вида `docs/specs/reviews/<что-то>/revalidation/<файл>` — ровно один
# уровень между корнем ревью и подкаталогом пересверок.
LANE_RE = re.compile(r"^" + re.escape(REVIEWS) + r"/[^/]+/revalidation/([^/]+)$")

# ── Шапка записи читается ПО СТРОЕНИЮ, а не по метке ─────────────────────────
#
# Метки шапок в каталоге ДВУЯЗЫЧНЫ и уже разошлись: обход дерева даёт
# `**Subject**` у трёх записей и `**Предмет**` у четвёртой, `**SHA-256**` у трёх
# и `**SHA-256 предмета**` у четвёртой (предикат:
# `grep -ohE '^\| \*\*[^*]+\*\*' <записи> | sort -u`). Предикат по одной метке
# недобирает МОЛЧА — ни красного, ни зелёного, — и ровно так он и промахнулся на
# первом прогоне инъекции. Поэтому здесь нет перечня меток вовсе: читается
# СТРОЕНИЕ шапки — обратные кавычки в её ячейках, — и от языка метки вердикт не
# зависит.
BACKTICK_RE = re.compile(r"`([^`]+)`")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")


def header_rows(text):
    """Строки первой таблицы документа — его шапки."""
    rows, started = [], False
    for line in text.split("\n"):
        if line.startswith("|"):
            rows.append(line)
            started = True
        elif started:
            break
    return rows


def header_values(text):
    """Все значения в обратных кавычках из шапки записи."""
    out = []
    for row in header_rows(text):
        out.extend(BACKTICK_RE.findall(row))
    return out


def declares_fingerprint(text):
    """Шапка объявляет отпечаток — значение из 64 hex-цифр, метка любая."""
    return any(HEX64_RE.match(v.strip()) for v in header_values(text))


def sha256_of(path):
    """Отпечаток содержимого файла — то же число, что даёт `sha256sum <path>`."""
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def lanes(root):
    """{каталог: [имена файлов]} — состав, выведенный ОБХОДОМ, не ведомостью."""
    found = {}
    for rel in _lib.tracked(root, REVIEWS):
        m = LANE_RE.match(rel)
        if not m:
            continue
        found.setdefault(os.path.dirname(rel), []).append(m.group(1))
    return {d: sorted(names) for d, names in found.items()}


def ledger_rows(doc):
    """[путь записи] — значения `record` строк `superseded` ведомости."""
    if not isinstance(doc, dict):
        return []
    rows = doc.get("superseded") or []
    if not isinstance(rows, list):
        return []
    out = []
    for row in rows:
        if isinstance(row, dict) and isinstance(row.get("record"), str):
            out.append(row["record"].strip())
    return out


def declared_numbers(doc):
    """{имя поля: объявленное число/строка} — только то, что объявлено явно.

    Отсутствующее поле НЕ находка: нечему противоречить. Находка — объявленное
    и разошедшееся с замером.
    """
    out = {}
    if not isinstance(doc, dict):
        return out
    binding = doc.get("binding_as_of")
    if isinstance(binding, dict):
        if isinstance(binding.get("design_sha256"), str):
            out["binding_as_of.design_sha256"] = binding["design_sha256"].strip()
        if isinstance(binding.get("records_bound_to_it"), int):
            out["binding_as_of.records_bound_to_it"] = binding["records_bound_to_it"]
    completeness = doc.get("completeness")
    if isinstance(completeness, dict):
        census = completeness.get("census")
        if isinstance(census, dict):
            for key in ("records_total", "superseded_rows", "bound_to_design"):
                if isinstance(census.get(key), int):
                    out["completeness.census." + key] = census[key]
    return out


def design_path(root, lane, doc, records):
    """(путь замысла, объяснение) — координата, чей отпечаток и есть предикат.

    Порядок: ведомость называет предмет сама; ведомости нет — координату берём
    из шапок самих записей. Расхождение шапок между собой — не наш вердикт, а
    отсутствие предмета: сверять не с чем.
    """
    if isinstance(doc, dict):
        subj = doc.get("subject")
        if isinstance(subj, dict) and isinstance(subj.get("design"), str):
            return subj["design"].strip(), "ведомость, subject.design"
    named = set()
    for name in records:
        try:
            text = _lib.read(root, os.path.join(lane, name))
        except OSError:
            continue
        for value in header_values(text):
            value = value.strip()
            # Замысел — документ ВНЕ каталога ревью, и он существует. Оба условия
            # структурные: ни имени поля, ни имени файла здесь не выписано.
            if (value.endswith(".md") and not value.startswith(REVIEWS + "/")
                    and os.path.isfile(os.path.join(root, value))):
                named.add(value)
    if len(named) == 1:
        return named.pop(), "шапки записей: единственная резолвящаяся координата вне каталога ревью"
    if not named:
        return None, "ни ведомость, ни шапки записей координаты замысла не называют"
    return None, ("шапки записей называют РАЗНЫЕ замыслы (%s) — предикат "
                  "действующей редакции не определён" % ", ".join(sorted(named)))


def judge(root, lane, names, findings, voids):
    """Вердикт по одному каталогу пересверок. Печатает свою перепись."""
    records = [n for n in names if RECORD_RE.match(n)]
    stray = [n for n in names if n.endswith(".md") and not RECORD_RE.match(n)]
    has_ledger = LEDGER_NAME in names

    doc = None
    if has_ledger:
        import yaml
        try:
            doc = yaml.safe_load(_lib.read(root, os.path.join(lane, LEDGER_NAME)))
        except (yaml.YAMLError, OSError) as exc:
            voids.append("%s: ведомость %s не разобрана (%s) — сверять нечем"
                         % (lane, LEDGER_NAME, exc))
            return

    rows = ledger_rows(doc)
    design, how = design_path(root, lane, doc, records)
    if design is None or not os.path.isfile(os.path.join(root, design)):
        voids.append("%s: замысел не читается (%s) — отпечаток действующей редакции "
                     "мерить не на чем; записей в каталоге %d, строк ведомости %d"
                     % (lane, design or how, len(records), len(rows)))
        return

    active = sha256_of(os.path.join(root, design))

    row_set = set(rows)
    bound, superseded = [], []
    for name in records:
        rel = os.path.join(lane, name)
        fingerprint = name[: -len(".md")]
        in_ledger = rel in row_set
        if fingerprint == active:
            bound.append(name)
            if in_ledger:
                findings.append(
                    "%s: запись ДЕЙСТВУЮЩАЯ (её отпечаток равен замеренному отпечатку "
                    "замысла %s), но внесена в ведомость как обесцененная — ведомость "
                    "объявляет снятым то, что снято не было" % (rel, active))
        else:
            superseded.append(name)
            if not in_ledger:
                findings.append(
                    "%s: отпечаток записи не равен замеренному отпечатку замысла %s "
                    "(%s), и строки в %s у неё нет — запись молча прочитается как "
                    "действующая" % (rel, active, design, LEDGER_NAME))

    seen = set()
    for row in rows:
        if row in seen:
            findings.append("%s: строка ведомости %s повторяется — счёт по строкам "
                            "перестаёт отвечать о составе каталога" % (lane, row))
            continue
        seen.add(row)
        base = os.path.basename(row)
        if os.path.dirname(row) != lane:
            findings.append("%s: строка ведомости адресует %s — путь вне своего "
                            "каталога, и о составе этого каталога строка не говорит "
                            "ничего" % (lane, row))
        elif base not in records:
            findings.append("%s: строка ведомости называет %s — такого файла в "
                            "каталоге НЕТ; запись о несуществующем так же лжива, как "
                            "молчание о существующем" % (lane, row))

    for name in stray:
        text = _lib.read(root, os.path.join(lane, name))
        if declares_fingerprint(text):
            findings.append(
                "%s/%s: файл объявляет отпечаток в шапке, но его имя вне пространства "
                "имён отпечатков (^[0-9a-f]{64}\\.md$) — предикат действующей редакции "
                "о нём ответить не может, и ни ведомость, ни обход его не видят"
                % (lane, name))

    declared = declared_numbers(doc)
    measured = {
        "binding_as_of.design_sha256": active,
        "binding_as_of.records_bound_to_it": len(bound),
        "completeness.census.records_total": len(records),
        "completeness.census.superseded_rows": len(rows),
        "completeness.census.bound_to_design": len(bound),
    }
    for key, value in sorted(declared.items()):
        if measured[key] != value:
            findings.append(
                "%s/%s: объявлено %s = %r, замер на этой ревизии даёт %r — числа "
                "ведомости остались от прежней ревизии и читаются как сегодняшние"
                % (lane, LEDGER_NAME, key, value, measured[key]))

    _lib.census("%s: %s — файлов %d, из них записей (имя = отпечаток) %d, вне "
                "пространства имён %d%s; ведомость %s, строк в ней %d; замысел %s, "
                "sha256 %s (повторить: sha256sum %s; координата — %s); действующих "
                "записей %d, обесцененных %d"
                % (NAME, lane, len(names), len(records), len(stray),
                   (" (" + ", ".join(stray) + ")") if stray else "",
                   "есть" if has_ledger else "ОТСУТСТВУЕТ", len(rows),
                   design, active, design, how, len(bound), len(superseded)))


def main():
    root = _lib.workspace_root()

    try:
        import yaml  # noqa: F401
    except ImportError:
        _lib.void(NAME, "разборщик YAML недоступен, а ведомость — YAML; условие "
                        "создаётся так: python3 -m pip install PyYAML")
        return 2

    found = lanes(root)
    if not found:
        _lib.census("%s: обход %s по индексу (--cached --others --exclude-standard) "
                    "дал 0 каталогов вида <ревью>/revalidation/" % (NAME, REVIEWS))
        _lib.void(NAME, "каталогов пересверки в дереве нет — предмета проверки нет. "
                        "Это НЕ «находок ноль»: обход прочитал и не нашёл ни одного "
                        "каталога, сверять было нечего")
        return 2

    findings, voids = [], []
    for lane in sorted(found):
        judge(root, lane, found[lane], findings, voids)

    total_records = sum(1 for lane in found for n in found[lane] if RECORD_RE.match(n))
    _lib.census("%s: каталогов пересверки %d, файлов-записей в них %d, каталогов без "
                "вердикта %d" % (NAME, len(found), total_records, len(voids)))
    for v in voids:
        _lib.census("%s: НЕ ВЫПОЛНИЛОСЬ — %s" % (NAME, v))

    if findings:
        # Перепись уходит в stdout, находки — в stderr. Без сброса буфера
        # порядок в общем выводе зависит от буферизации, а не от кода, и
        # читатель получает находку раньше знаменателя, к которому она
        # относится.
        sys.stdout.flush()
        for f in findings:
            _lib.fail(NAME, f)
        return 1

    judged = len(found) - len(voids)
    if judged == 0:
        _lib.void(NAME, "ни один из %d каталогов не проверен — вердикт выносить не по "
                        "чему" % len(found))
        return 2

    _lib.passed(NAME, "каталогов проверено %d из %d; каждая запись либо равна "
                      "замеренному отпечатку своего замысла, либо названа строкой "
                      "ведомости, и каждая строка разрешается в файл"
                      % (judged, len(found)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
