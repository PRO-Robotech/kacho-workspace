#!/usr/bin/env bash
# check-14 — у каждого действующего потолка есть основание, и запас остался.
# Заведена номером 10; перенумерована 2026-09-22: номер 10 в этом наборе носят
# проверки двух других веток origin.
#
# ПРЕДМЕТ. `BUDGET` в check-02 — числа; `ceiling-basis.txt` — основания. Число
# производится одним местом, основание обязано меняться ВМЕСТЕ с ним. Проверка
# судит три вещи, и каждая — отдельная ось:
#
#   1. СОВПАДЕНИЕ. Потолок в ведомости равен потолку в `BUDGET`. Разошлись —
#      число подняли, основание осталось от прежнего подъёма. Основание,
#      пережившее свой подъём, — находка, а не мелочь: именно так подъём и
#      становится привычкой, ведь оформлять его больше нечем.
#   2. ЗАПАС. `потолок - тело` не меньше МЕДИАННОГО АБЗАЦА этого файла. Медиана
#      берётся обходом абзацев (блоки между пустыми строками, заголовки и
#      frontmatter исключены), а не назначается: назначенное число — та же
#      подгонка под написанное, только на шаг раньше. Правило запаса не
#      изобретено здесь — «запас на абзац, но не на раздел» стоит в check-02 с
#      самой установки потолка.
#   3. ПОЛНОТА СТРОКИ. Шесть полей, и поля «предмет» и «что невозможно без него»
#      непустые. Подъём «про запас» предмета назвать не может — этим он и
#      отсекается.
#
# ПРЕДПОСЫЛКА ПРОВЕРЯЕТСЯ. Нет `BUDGET`, нет ведомости, ведомость пуста, файла
# потолка нет на диске — код 2, а не зелёное: «ноль находок» без прочитанного
# числа ничего не утверждает.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${KACHO_WS:-$(cd "$SELF_DIR/../.." && pwd)}"
exec python3 - "$WS" "$SELF_DIR/ceiling-basis.txt" "$SELF_DIR/check-02-nothing-lost.sh" <<'PY'
import os, re, sys

ws, ledger_path, check02_path = sys.argv[1], sys.argv[2], sys.argv[3]
NAME = "check-14-ceiling-raise-carries-its-basis"


def void(msg):
    print(f"[VOID] {NAME} — {msg}", file=sys.stderr)
    sys.exit(2)


if not os.path.isfile(check02_path):
    void("check-02 не найден — потолки брать неоткуда")
src = open(check02_path, encoding="utf-8").read()
m = re.search(r"^BUDGET = \{(.+?)\}", src, re.M)
if not m:
    void("в check-02 нет строки `BUDGET = {…}` — числа не прочитаны")

# CLAUDE_REL / DISPATCHER_REL -> их значения, чтобы не дублировать координаты.
consts = dict(re.findall(r"^(\w+) = (.+)$", src, re.M))


def resolve(token):
    token = token.strip()
    if token in consts:
        val = consts[token]
        if val.startswith('"'):
            return val.strip('"')
        j = re.match(r'(\w+) \+ "(.+?)" \+ (\w+) \+ "(.+?)"', val)
        if j:
            base = consts.get(j.group(1), "").strip('"')
            mid = consts.get(j.group(3), "").strip('"')
            return base + j.group(2) + mid + j.group(4)
        return None
    return None


budget = {}
for key, num in re.findall(r"(\w+_REL): (\d+)", m.group(1)):
    rel = resolve(key)
    if rel:
        budget[rel] = int(num)
if not budget:
    void("`BUDGET` разобран в пусто — координаты потолков не восстановлены")

if not os.path.isfile(ledger_path):
    void("ведомости оснований нет — подъём нечем обосновать")
rows = {}
malformed = []
for line in open(ledger_path, encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    parts = [p.strip() for p in line.split("|")]
    if len(parts) != 6:
        malformed.append(line[:70])
        continue
    rows[parts[0]] = parts
if not rows and not malformed:
    void("ведомость пуста — оснований ноль, сверять нечего")

FM = re.compile(rb"^---[ \t]*\r?\n.*?\r?\n---[ \t]*\r?\n", re.S)


def body_and_median(rel):
    data = open(os.path.join(ws, rel), "rb").read()
    fm = FM.match(data)
    text = data[fm.end():] if fm else data
    paras = sorted(
        len(p) for p in text.split(b"\n\n")
        if p.strip() and not p.lstrip().startswith(b"#")
    )
    return len(text), (paras[len(paras) // 2] if paras else 0)


findings = []
census = []
for rel, cap in sorted(budget.items()):
    abs_path = os.path.join(ws, rel)
    if not os.path.isfile(abs_path):
        void(f"{rel} нет на диске — потолок {cap} не с чем сверить")
    size, median = body_and_median(rel)
    slack = cap - size
    row = rows.get(rel)
    census.append(f"{rel} — тело {size} Б, потолок {cap} Б, запас {slack} Б, медианный абзац {median} Б")
    if row is None:
        findings.append(
            f"ОСНОВАНИЯ НЕТ: {rel} — потолок {cap} Б объявлен в BUDGET, "
            f"а в ведомости строки нет. Число без основания поднимается одной "
            f"строкой, и подъём неотличим от опечатки"
        )
        continue
    declared = int(row[1]) if row[1].isdigit() else None
    if declared != cap:
        findings.append(
            f"ОСНОВАНИЕ ПЕРЕЖИЛО СВОЙ ПОДЪЁМ: {rel} — в BUDGET {cap} Б, в "
            f"ведомости {row[1]} Б. Число подняли, основание осталось от "
            f"прежнего подъёма: правится ТЕМ ЖЕ изменением, что и число"
        )
    if not row[4] or not row[5]:
        findings.append(
            f"ПОДЪЁМ БЕЗ ПРЕДМЕТА: {rel} — поле «предмет» либо «что невозможно "
            f"без него» пусто. Подъём «про запас» предмета назвать не может"
        )
    if slack < median:
        findings.append(
            f"ЗАПАСА НЕ ОСТАЛОСЬ: {rel} — запас {slack} Б при медианном абзаце "
            f"{median} Б. Потолок, отмеренный по размеру написанного, — не "
            f"решение, а оформление факта: следующая норма потребует следующего "
            f"подъёма в тот же день"
        )

for bad in malformed:
    findings.append(f"СТРОКА ВЕДОМОСТИ НЕ ШЕСТИПОЛЬНАЯ: {bad}")

orphan = [r for r in rows if r not in budget]
for rel in orphan:
    findings.append(
        f"ОСНОВАНИЕ БЕЗ ПОТОЛКА: {rel} — в ведомости есть, в BUDGET нет. "
        f"Запись, которой нечего обосновывать, — находка: ведомость не может "
        f"пережить свой предмет"
    )

print(
    f"[CENSUS] {NAME}: потолков в BUDGET {len(budget)}; строк ведомости "
    f"{len(rows)}, негодных {len(malformed)}, без потолка {len(orphan)}; "
    f"находок {len(findings)}. " + "; ".join(census)
)

if findings:
    print(f"[FAIL] {NAME} — потолок без действующего основания либо без запаса:")
    for f in findings:
        print(f"    {f}")
    sys.exit(1)

print(
    f"[PASS] {NAME} — потолков {len(budget)}, у каждого основание совпадает с "
    f"числом, предмет назван, запас не меньше медианного абзаца"
)
PY
