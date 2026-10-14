#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-13 «стартовое окно агента не выше
# потолка» (ws#1084). Оси: W — старт выше потолка на ОДИН символ краснеет, ровно на
# потолке молчит; T — правило по триггеру в старт не входит (то же правило в
# `skills:` краснеет); K — скилл из `skills:`, которого нет в дереве; L — ведомость:
# агент без строки, строка без агента, строка без основания краснеют, нет ведомости
# или она пуста — отказ; Z — нетронутая копия молчит.
#
# ЕДИНИЦА СЧЁТА ОСЕЙ — буква в разметке `# ── ось X`; предикат —
# `grep -cE '^# ── ось ' scripts/rules-gate/inject-13-agent-window-budget.sh`.
#
# Агент-жертва и правило выводятся ИЗ ДЕРЕВА, числа — из вывода самой проверки:
# выписанный потолок разошёлся бы с ведомостью молча.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции; запускать: bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i13_fn in sandbox capture assert_code assert_says assert_number assert_lacks assert_fixture_changed sandbox_digest; do
    command -v "$_i13_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: «$_i13_fn» не определена" >&2
    exit 2
done
unset -v _i13_fn

C13=check-13-agent-window-budget.sh
LEDGER13="$GATE/agent-window-budget.tsv"

# start13 <вывод> <агент> → «старт потолок» из строки переписи проверки.
start13() {
    python3 -c '
import re, sys
for l in sys.stdin:
    m = re.match(r"^  (\S+)\s+старт\s+(\d+) / потолок\s+(\d+)", l)
    if m and m.group(1) == sys.argv[1]:
        print(m.group(2), m.group(3)); break' "$2" <<<"$1"
}

# Жертва — агент с `skills:` (в порядке C первый), правило — самое крупное
# `rule-*`, которого у неё в `skills:` нет: его размер обязан превышать запас.
read -r V13 R13 < <(python3 - "$WS" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
rules = {os.path.basename(os.path.dirname(p)): len(open(p, encoding='utf-8').read())
         for p in glob.glob(os.path.join(root, '.claude/skills/rule-*/SKILL.md'))}
for path in sorted(glob.glob(os.path.join(root, '.claude/agents/*.md'))):
    text = open(path, encoding='utf-8').read()
    fm = text.split('\n---', 1)[0]
    have = set(re.findall(r'^\s+-\s*(rule-\S+)', fm, re.M))
    if not have:
        continue
    rest = sorted(((n, r) for r, n in rules.items() if r not in have), reverse=True)
    if rest:
        print(os.path.splitext(os.path.basename(path))[0], rest[0][1]); break
PY
)
if [ -z "${V13:-}" ] || [ -z "${R13:-}" ]; then
    echo "  [FAIL] inject-13 НЕИСПОЛНИМА: нет агента с skills: и правила вне его skills:" >&2
    fail=$((fail + 1))
    return 0 2>/dev/null || exit 1
fi

# ── ось Z: нетронутая копия — молчит, и называет жертву ─────────────────────
d="$(sandbox i13_clean)"
capture "$d" "$C13"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"
read -r S13 CAP13 < <(start13 "$OUT" "$V13")
if ! grep -qE '^[0-9]+ [0-9]+$' <<<"${S13:-} ${CAP13:-}"; then
    echo "  [FAIL] inject-13: старт и потолок $V13 из переписи не прочитаны" >&2
    fail=$((fail + 1))
    S13=0; CAP13=0
fi
ROOM13=$(( CAP13 - S13 ))

# ── ось W: старт РОВНО на потолке молчит, на символ выше — краснеет ────────
grow13() {   # <каталог> <символов> — дописать в файл жертвы ровно N символов
    python3 - "$1/.claude/agents/$V13.md" "$2" <<'PY'
import sys
p, n = sys.argv[1], int(sys.argv[2])
open(p, 'a', encoding='utf-8').write('\n' + 'д' * (n - 1) if n > 0 else '')
PY
}
d="$(sandbox i13_at_cap)"; b="$(sandbox_digest "$d")"
grow13 "$d" "$ROOM13"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: в $V13 добран весь запас — $ROOM13 символов"
capture "$d" "$C13"
assert_code 0 "БЛИЗНЕЦ: старт $V13 равен потолку $CAP13 РОВНО — молчит"
assert_lacks "КРАСНОЕ окно" "  ...и окно не названо красным"

d="$(sandbox i13_over)"
grow13 "$d" "$(( ROOM13 + 1 ))"
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: старт $V13 выше потолка на один символ — краснеет"
assert_says "КРАСНОЕ окно — $V13" "ДИАГНОЗ оси W: названо окно и агент"
assert_number "перевес" 1 "ДИАГНОЗ оси W: перевес назван числом"

# ── ось T: правило по триггеру в старт НЕ входит; то же в skills: — входит ─
d="$(sandbox i13_trigger)"; b="$(sandbox_digest "$d")"
printf '\n| условие пробы | `Skill %s` | зачем |\n' "$R13" >> "$d/.claude/agents/$V13.md"
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: в тело $V13 добавлен триггер «Skill $R13»"
capture "$d" "$C13"
assert_code 0 "БЛИЗНЕЦ: правило $R13 по триггеру — в старт не входит, молчит"
read -r S13t _ < <(start13 "$OUT" "$V13")
if [ "${S13t:-0}" -lt $(( S13 + 200 )) ] && [ "${S13t:-0}" -gt "$S13" ]; then
    echo "  [OK]   БЛИЗНЕЦ: старт вырос лишь на строку триггера ($S13 → $S13t)"; pass=$((pass + 1))
else
    echo "  [FAIL] БЛИЗНЕЦ оси T: старт $S13 → ${S13t:-?} — триггер посчитан в старт" >&2
    fail=$((fail + 1))
fi

d="$(sandbox i13_preload)"
python3 - "$d/.claude/agents/$V13.md" "$R13" <<'PY'
import re, sys
p, r = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
s = re.sub(r'^(skills:\s*\n)', r'\1  - %s\n' % r, s, count=1, flags=re.M)
open(p, 'w', encoding='utf-8').write(s)
PY
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: то же правило $R13 в skills: $V13 — старт выше потолка, краснеет"
assert_says "КРАСНОЕ окно — $V13" "ДИАГНОЗ оси T: краснеет окно, а не форма"

# ── ось K: скилл из skills:, которого нет в дереве ──────────────────────────
d="$(sandbox i13_ghost)"
sed -i '0,/^skills:/s//skills:\n  - rule-net-takogo-pravila/' "$d/.claude/agents/$V13.md"
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: в skills: несуществующий скилл — краснеет"
assert_says "КРАСНОЕ скилл — $V13" "ДИАГНОЗ оси K: назван агент и скилл"

# ── ось L: ведомость сходится с агентами в обе стороны ──────────────────────
d="$(sandbox i13_ledger)"
cp "$LEDGER13" "$TMP/l13.tsv"
grep -v "^$V13	" "$LEDGER13" > "$TMP/l13_drop.tsv"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_drop.tsv"
assert_code 1 "ДЕФЕКТ: у агента $V13 нет строки ведомости — краснеет"
assert_says "у агента $V13 нет потолка" "ДИАГНОЗ оси L: назван агент без потолка"

{ cat "$LEDGER13"; printf 'agent-snyat\t1000\tws#1084 проба\n'; } > "$TMP/l13_extra.tsv"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_extra.tsv"
assert_code 1 "ДЕФЕКТ: строка ведомости без агента — краснеет"
assert_says "о «agent-snyat»: такого агента нет" "ДИАГНОЗ оси L: запись пережила предмет"

sed "s/^\($V13	[0-9]*\)	.*/\1	/" "$LEDGER13" > "$TMP/l13_nowhy.tsv"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_nowhy.tsv"
assert_code 1 "ДЕФЕКТ: потолок без основания — краснеет"
assert_says "КРАСНОЕ форма ведомости" "ДИАГНОЗ оси L: названа форма строки"

capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13.tsv"
assert_code 0 "БЛИЗНЕЦ: копия ведомости через шов — молчит"

capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_net.tsv"
assert_code 2 "ПРЕДПОСЫЛКА: ведомости нет — ОТКАЗ"
grep '^#' "$LEDGER13" > "$TMP/l13_empty.tsv"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_empty.tsv"
assert_code 2 "ПРЕДПОСЫЛКА: в ведомости ни одной строки — ОТКАЗ"
echo "  [CENSUS] inject-13: жертва $V13 (старт $S13, потолок $CAP13, запас $ROOM13)," \
     "правило по триггеру $R13; агентов в ведомости $(grep -vc '^#' "$LEDGER13")"
unset -v V13 R13 S13 CAP13 ROOM13 S13t
