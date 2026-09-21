#!/usr/bin/env bash
# check-13 — каждая строка §12 базы называет ИСТОЧНИК, как требует её преамбула.
#
# ПРЕДМЕТ. §12 «Противоречия, разрешённые в базе» открывается словами «по более
# позднему решению, С ИСТОЧНИКОМ». Источник — ДАТА (`20\d\d-\d\d-\d\d`) либо
# координата правила (`файл.md`). Ссылка на соседний раздел той же базы
# источником НЕ считается, и это не придирка: §12 говорит, какое из двух чтений
# ПОЗДНЕЕ, а §7 или §11 о старшинстве не сообщают ничего — они такой же текст
# того же файла. Именно так и выглядела находка, ради которой проверка заведена:
# строка «Ролей автора замысла… НЕ заводим» заканчивалась «(§11)», и §11 сносил
# СОСЕДНЮЮ оговорку, а не само решение.
#
# ПРЕДПОСЫЛКА ПРОВЕРЯЕТСЯ: нет §12 — нет и предмета, код 2, а не зелёное.
# Пустой раздел — тоже код 2: «ноль находок» на нуле строк ничего не значит.
#
# ДВЕ ЗАКОННЫЕ ФОРМЫ КООРДИНАТЫ, И ОБЕ С ЗАГЛАВНЫМИ: голое имя (`testing.md`) и
# канонический полный путь (`.claude/rules/testing.md`), плюс `CLAUDE.md` и
# `MANIFEST.md`. Первая редакция знала ОДНУ форму в нижнем регистре и давала
# ЛОЖНОЕ КРАСНОЕ на законной записи.
#
# СВЕРКА С ВЕДОМОСТЬЮ — ТОЧНАЯ. Первая редакция сверяла ПРЕФИКСОМ, и запись в
# один знак гасила любую новую строку без источника: она префикс чего угодно.
# «Краснеет в обе стороны» держалось тогда ДЛИНОЙ записей, а не предикатом.
#
# ВЕДОМОСТЬ `decision-source-baseline.txt` — только СОКРАЩАЕТСЯ, и краснеет в
# обе стороны: новая строка без источника — находка; строка ведомости, которая
# источник уже называет, — тоже находка, её обязаны убрать.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${KACHO_WS:-$(cd "$SELF_DIR/../.." && pwd)}"
exec python3 - "$WS" "$SELF_DIR/decision-source-baseline.txt" <<'PY'
import datetime, re, sys, os

ws, baseline_path = sys.argv[1], sys.argv[2]
base_rel = ".claude/agents/dispatcher.md"
base_abs = os.path.join(ws, base_rel)
NAME = "check-13-decision-rows-name-their-source"

if not os.path.isfile(base_abs):
    print(f"[VOID] {NAME} — базы нет: {base_rel}; предмета нет", file=sys.stderr)
    sys.exit(2)

text = open(base_abs, encoding="utf-8").read()
section = re.search(r"^## 12\. (.+?)$(.*?)(?=^## |\Z)", text, re.S | re.M)
if not section:
    print(f"[VOID] {NAME} — раздела 12 в базе нет; предмета нет", file=sys.stderr)
    sys.exit(2)

rows = [l for l in section.group(2).split("\n") if l.startswith("- ")]
if not rows:
    print(f"[VOID] {NAME} — раздел 12 пуст, строк-решений 0; предмета нет", file=sys.stderr)
    sys.exit(2)

DATE = re.compile(r"\b(20\d\d)-(\d\d)-(\d\d)\b")


def has_real_date(row):
    """Дата обязана СУЩЕСТВОВАТЬ, а не только иметь форму.

    Прежняя редакция судила образец, и `2026-13-45` проходило источником.
    Источник — это когда решение принято; несуществующий день не называет
    ничего и отличим от опечатки только календарём."""
    for y, m, d in DATE.findall(row):
        try:
            datetime.date(int(y), int(m), int(d))
            return True
        except ValueError:
            continue
    return False
COORD = re.compile(r"`[A-Za-z0-9.][A-Za-z0-9._/-]*\.md`")

known = []
if os.path.isfile(baseline_path):
    for line in open(baseline_path, encoding="utf-8"):
        line = line.strip()
        if line and not line.startswith("#"):
            known.append(line)

def key_of(row):
    return row[2:].split("→")[0].strip()[:60]

sourceless, sourced_keys = [], []
for row in rows:
    key = key_of(row)
    if has_real_date(row) or COORD.search(row):
        sourced_keys.append(key)
    else:
        sourceless.append(key)

known_set = set(known)
new_findings = [k for k in sourceless if k not in known_set]
healed = [b for b in known if b not in set(sourceless)]

print(
    f"[CENSUS] {NAME}: строк-решений §12 {len(rows)}; с источником "
    f"{len(sourced_keys)}, без источника {len(sourceless)}; в ведомости "
    f"{len(known)}; новых без источника {len(new_findings)}; "
    f"зажило, но осталось в ведомости {len(healed)}"
)

if new_findings or healed:
    print(f"[FAIL] {NAME} — §12 требует источник у каждой строки:")
    for k in new_findings:
        print(f"    БЕЗ ИСТОЧНИКА и не в ведомости: {k}")
    for k in healed:
        print(f"    ЗАЖИЛА, убрать из ведомости: {k}")
    sys.exit(1)

print(
    f"[PASS] {NAME} — строк §12 {len(rows)}, источник называют "
    f"{len(sourced_keys)}; остальные {len(sourceless)} стоят в ведомости "
    f"как названный долг"
)
PY
