#!/usr/bin/env bash
# check-15 — все блоки контракта ВОЗВРАТ совпадают по СОСТАВУ ПОЛЕЙ.
#
# ЗАЧЕМ. Канон контракта — `CLAUDE.md`. Но `client-simulator` получает пустое
# окно ПО ПОСТРОЕНИЮ (ban #18): общий протокол ему не грузится, и копия в его
# теле ДЛЯ НЕГО И ЕСТЬ контракт. Когда 2026-09-21 в канон добавилось поле
# «несостоявшаяся загрузка», копия отстала, и дерево осталось зелёным во всех
# семи наборах: агент отвечал бы по девяти полям, считая, что по десяти.
#
# ЕДИНИЦА СЧЁТА — ИМЯ ПОЛЯ, а не строка: у копии значения свои (у неё уже одного
# вердикта и один исход), и сверять текст было бы ложным красным. Совпадать
# обязан СОСТАВ и ПОРЯДОК.
#
# ЧТО СЧИТАЕТСЯ БЛОКОМ. Огороженный блок, начинающийся строкой `### ВОЗВРАТ`.
# Копия объявляет себя копией словами «форма приведена здесь целиком и совпадает
# с контрактом»; проверка судит не эти слова, а сам состав.
#
# ОБЛАСТЬ — ВЕСЬ КОРПУС, ЧИТАЕМЫЙ АГЕНТАМИ, а не только тела. Первая редакция
# обходила `CLAUDE.md` и `.claude/agents/`, и копия, положенная в ПРАВИЛО,
# осталась невидимой: правило грузится ЦЕЛИКОМ в окно по предзагрузке и читается
# наравне с телом — для своих агентов оно тоже контракт. Теперь обход берёт
# `.claude/agents/**`, `.claude/rules/**` и `.claude/skills/**`.
#
# ПРЕДПОСЫЛКА ПРОВЕРЯЕТСЯ САМА: «копий вне области ноль» сегодня верно, но верно
# не навсегда. Гейт обходит ВЕСЬ отслеживаемый git `*.md` и краснеет на блоке,
# найденном за пределами области, — иначе утверждение об области станет ложью
# молча, ровно как в прошлый раз.
#
# ПРЕДПОСЫЛКА. Нет канона либо в каноне ноль полей — код 2. Копий ноль — тоже
# код 2: сверять не с чем, и «расхождений ноль» ничего не утверждало бы.
set -uo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WS="${KACHO_WS:-$(cd "$SELF_DIR/../.." && pwd)}"
exec python3 - "$WS" <<'PY'
import io, os, re, subprocess, sys

ws = sys.argv[1]
NAME = "check-15-contract-copies-agree"
CANON_REL = "CLAUDE.md"


def void(msg):
    print(f"[VOID] {NAME} — {msg}", file=sys.stderr)
    sys.exit(2)


BLOCK = re.compile(r"^```\w*\s*\n(### ВОЗВРАТ\n.*?)^```", re.S | re.M)
FIELD = re.compile(r"^- ([^:\n]+):", re.M)


def fields_of(text):
    out = []
    for block in BLOCK.findall(text):
        out.append([f.strip() for f in FIELD.findall(block)])
    return out


canon_abs = os.path.join(ws, CANON_REL)
if not os.path.isfile(canon_abs):
    void(f"канона нет: {CANON_REL}")
canon_blocks = fields_of(io.open(canon_abs, encoding="utf-8").read())
if not canon_blocks or not canon_blocks[0]:
    void(f"в {CANON_REL} не найден блок `### ВОЗВРАТ` с полями — сверять не с чем")
canon = canon_blocks[0]

AREA = (".claude/agents/", ".claude/rules/", ".claude/skills/")

tracked = subprocess.run(
    ["git", "-C", ws, "ls-files", "*.md"], capture_output=True, text=True
).stdout.split()
if not tracked:
    void("git не дал ни одного отслеживаемого .md — обход беспредметен")

in_area = [f for f in tracked if f.startswith(AREA)]
outside = [f for f in tracked if not f.startswith(AREA) and f != CANON_REL]

copies, findings, outside_hits = [], [], []
for rel in sorted(outside):
    abs_path = os.path.join(ws, rel)
    if not os.path.isfile(abs_path):
        continue
    if fields_of(io.open(abs_path, encoding="utf-8", errors="replace").read()):
        outside_hits.append(rel)
        findings.append(
            f"КОПИЯ ВНЕ ОБЛАСТИ: {rel} несёт блок `### ВОЗВРАТ`, а область "
            f"проверки — {', '.join(AREA)} и {CANON_REL}. Либо область узка, "
            f"либо блоку здесь не место: предпосылка «копий вне области ноль» "
            f"перестала быть верной"
        )

for rel in sorted(in_area):
    path = os.path.join(ws, rel)
    if not os.path.isfile(path):
        continue
    for got in fields_of(io.open(path, encoding="utf-8", errors="replace").read()):
        if not got:
            continue
        copies.append(rel)
        if got == canon:
            continue
        missing = [f for f in canon if f not in got]
        extra = [f for f in got if f not in canon]
        why = []
        if missing:
            why.append("НЕТ полей канона: " + ", ".join(missing))
        if extra:
            why.append("ЛИШНИЕ поля: " + ", ".join(extra))
        if not why:
            findings.append(
                f"{rel} — состав полей тот же, а ПОРЯДОК разошёлся с {CANON_REL}: "
                f"канон {canon}, копия {got}. Блок читается сверху вниз, и "
                f"переставленное поле меняет то, что отвечающий увидит первым"
            )
            continue
        findings.append(
            f"{rel} — копия контракта разошлась с {CANON_REL}: {'; '.join(why)}. "
            f"Агент отвечал бы по {len(got)} полям, считая, что по {len(canon)}"
        )

print(
    f"[CENSUS] {NAME}: канон {CANON_REL} — полей {len(canon)}; отслеживаемых "
    f"`*.md` {len(tracked)}, из них в области {len(in_area)}, вне области "
    f"{len(outside)}; копий найдено {len(copies)} "
    f"({', '.join(copies) if copies else '—'}); блоков вне области "
    f"{len(outside_hits)}; расхождений {len(findings)}"
)

if not copies and not outside_hits:
    void("копий контракта в области ноль — сверять не с чем")

if findings:
    print(f"[FAIL] {NAME} — состав полей разошёлся:")
    for f in findings:
        print(f"    {f}")
    sys.exit(1)

print(
    f"[PASS] {NAME} — копий {len(copies)}, у каждой тот же состав и порядок "
    f"{len(canon)} полей, что у {CANON_REL}"
)
PY
