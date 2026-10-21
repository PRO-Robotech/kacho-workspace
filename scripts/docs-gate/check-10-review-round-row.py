#!/usr/bin/env python3
"""check-10 — строка круга ревью стоит в «Истории review» приёмки ДО нового отпечатка.

Что запрещает. История ревью приёмки (`docs/specs/<имя>-acceptance.md`, строка шапки
«История review: дата · круг · вердикт · SHA-256 редакции · путь записи») только
дописывается — норма `acceptance-author` §3 и `acceptance-reviewer` §7. Строку круга N
вносит автор в редакцию N+1, и вносить её можно лишь до того, как рецензент вычислит
отпечаток этой редакции: правка после вердикта меняет отпечаток, и вердикт о прежней
редакции на новую не переносится (`approval-event.sh` требует равенства). История дважды
теряла строку круга (bcs круг 4, sua круг 3), и правка после вердикта стоила отдельного
круга ревью (ws#1273). Проверка стоит в наборе, который гонит хук отправки: редакция без
строки прошлого круга не уезжает к рецензенту.

Предмет. Записи ревью `docs/specs/reviews/<имя>/*.yaml` (каталог — имя приёмки) с полем
`subject.sha256`. Запись о ДРУГОЙ редакции, чем нынешний файл (`subject.sha256` ≠ sha256
файла на диске), — прошлый круг; её отпечаток целиком обязан стоять в тексте приёмки
(строкой истории; путь записи несёт тот же отпечаток). Запись о нынешней редакции —
текущий круг: строку о нём впишет следующая редакция.

Прежние пропуски — ведомость `review-round-row-baseline.txt` рядом: строка `<имя>
<sha256>`, точный состав, а не потолок. Правка одобренной приёмки ради строки сменила
бы её отпечаток, поэтому прежнее не чинится, а перечисляется; запись ведомости, которой
нечего исключать (записи нет, строка уже стоит, запись стала текущей), — находка:
ведомость только убывает.

Граница (печатается переписью): приёмки дерева продукта (`check-04`) и записи ревью
кода `docs/changes/*/reviews/` — вне предмета; каталог записей без своей приёмки и YAML
без `subject.sha256` (состояние публикации и т.п.) — счётом, не находкой.

Исходы: 0 — у каждого прошлого круга строка стоит либо он в ведомости; 1 — находка
(названы приёмка и запись); 2 — записей ревью нет либо разборщика YAML нет.
"""
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-10-review-round-row"
SHA = re.compile(r"^[0-9a-f]{64}$")
BASELINE = "scripts/docs-gate/review-round-row-baseline.txt"


def baseline(root):
    """Ведомость СУДИМОГО дерева; файла нет — пусто (находок больше, не меньше)."""
    rows = set()
    path = os.path.join(root, BASELINE)
    if not os.path.isfile(path):
        return rows
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if line:
                stem, sha = line.split()
                rows.add((stem, sha))
    return rows


def main():
    try:
        import yaml
    except ImportError:
        _lib.void(NAME, "разборщика YAML нет (PyYAML) — записи ревью не прочитаны")
        return 2
    root = _lib.workspace_root()
    recs = [p for p in _lib.tracked(root, "docs/specs/reviews/*.yaml")
            if len(p.split("/")) == 5 and p.endswith(".yaml")]
    if not recs:
        _lib.void(NAME, "записей ревью docs/specs/reviews/<приёмка>/*.yaml нет — судить нечего")
        return 2
    allowed = baseline(root)
    by = {}
    for p in recs:
        by.setdefault(p.split("/")[3], []).append(p)
    findings, used, nodoc, nonrec = [], set(), [], []
    past = named = current = 0
    for stem in sorted(by):
        doc = "docs/specs/%s.md" % stem
        path = os.path.join(root, doc)
        if not os.path.isfile(path):
            nodoc.append(stem)
            continue
        with open(path, "rb") as fh:
            raw = fh.read()
        cur = hashlib.sha256(raw).hexdigest()
        text = raw.decode("utf-8", errors="replace")
        for rec in by[stem]:
            try:
                with open(os.path.join(root, rec), encoding="utf-8") as fh:
                    y = yaml.safe_load(fh)
            except Exception as e:  # noqa: BLE001 — неразобранная запись есть находка, а не пропуск
                findings.append("%s: запись не разбирается как YAML (%s)" % (rec, str(e).splitlines()[0]))
                continue
            subj = y.get("subject") if isinstance(y, dict) and isinstance(y.get("subject"), dict) else {}
            s = subj.get("sha256")
            if not isinstance(s, str) or not SHA.match(s):
                nonrec.append(rec)
                continue
            if s == cur:
                current += 1
                continue
            past += 1
            if s in text:
                named += 1
                continue
            if (stem, s) in allowed:
                used.add((stem, s))
                continue
            findings.append("%s: строки круга нет — запись %s (раунд %s) о редакции %s… не названа в «Истории "
                            "review»; допиши строку «дата · круг · вердикт · %s · %s» ДО отправки редакции на ревью"
                            % (doc, rec, y.get("round", "?"), s[:12], s, rec))
    for stem, s in sorted(allowed - used):
        findings.append("ведомость %s: строка «%s %s» ничего не исключает (записи нет, строка круга уже стоит либо "
                        "запись — о нынешней редакции) — сними её" % (os.path.basename(BASELINE), stem, s))
    _lib.census("%s: каталогов записей %d (без своей приёмки %d%s); записей %d, не записей ревью %d; текущих "
                "кругов %d, прошлых %d — строка стоит %d, в ведомости %d; ведомость %d строк; находок %d; "
                "вне предмета — приёмки продукта (check-04) и docs/changes/*/reviews"
                % (NAME, len(by), len(nodoc), (": " + ", ".join(nodoc)) if nodoc else "", len(recs), len(nonrec),
                   current, past, named, len(used), len(allowed), len(findings)))
    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        return 1
    _lib.passed(NAME, "прошлых кругов %d, у каждого строка либо запись ведомости" % past)
    return 0


if __name__ == "__main__":
    sys.exit(main())
