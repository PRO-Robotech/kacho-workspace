#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-13 «стартовое окно агента не выше
# потолка» (ws#1084). Оси: W — старт выше потолка на ОДИН символ краснеет, ровно на
# потолке молчит; T — правило по триггеру в старт не входит (то же правило в
# `skills:` краснеет); K — скилл из `skills:`, которого нет в дереве; L — ведомость:
# агент без строки, строка без агента, строка без основания краснеют, нет ведомости
# или она пуста — отказ; Z — нетронутая копия молчит; F — форма `skills:`: список
# в колонке 0 и поточный `[a, b]` дают тот же старт, ключ непуст при нуле имён —
# находка; B — основание потолка сходится с замером старта на своей ревизии;
# C — раздутый `CLAUDE.md` и тело `dispatcher.md` краснеют здесь (их потолки сняты
# с check-02, ws#1084); H — истории git для сверки оснований нет — отказ.
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
OUT_Z13="$OUT"
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
# ── ось F: форма skills: — колонка 0 и поточный список читаются как блочный ─
# Возврат check-verifier: разбор образцом `^\s+-` давал «skills: 0» при списке в
# колонке 0. Законные формы YAML дают ОДИН старт; ключ, под которым имён не
# разобрано, — находка (старт без скиллов неверен).
skills13() {   # <вывод> <агент> → число skills: из строки переписи
    sed -nE "s/^  $2 +старт.*· skills: ([0-9]+) ·.*/\1/p" <<<"$1" | head -1
}
N13="$(skills13 "$OUT_Z13" "$V13")"
reform13() {   # <файл> <col0|inline|comment>
    python3 - "$1" "$2" <<'PY2'
import re, sys
p, how = sys.argv[1], sys.argv[2]
s = open(p, encoding='utf-8').read()
m = re.search(r'^skills:[ \t]*\n((?:[ \t]+-[^\n]*\n)+)', s, re.M)
if not m:
    raise SystemExit('ФИКСТУРА БЕСПРЕДМЕТНА: блочного skills: с отступом нет')
items = re.findall(r'-\s*(\S+)', m.group(1))
if how == 'col0':
    new = 'skills:\n' + ''.join('- %s\n' % i for i in items)
elif how == 'inline':
    new = 'skills: [%s]\n' % ', '.join(items)
else:
    new = 'skills:\n' + ''.join('  # - %s\n' % i for i in items)
open(p, 'w', encoding='utf-8').write(s[:m.start()] + new + s[m.end():])
PY2
}
for form13 in col0 inline; do
    d="$(sandbox "i13_$form13")"; b="$(sandbox_digest "$d")"
    reform13 "$d/.claude/agents/$V13.md" "$form13"
    assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: skills: $V13 записан формой $form13"
    capture "$d" "$C13"
    assert_code 0 "БЛИЗНЕЦ: форма $form13 — законный YAML, молчит"
    read -r S13f _ < <(start13 "$OUT" "$V13")
    if [ "$(skills13 "$OUT" "$V13")" = "$N13" ] && [ -n "$N13" ] && [ "$N13" -gt 0 ] \
       && [ "${S13f:-0}" -gt $(( S13 - 200 )) ] && [ "${S13f:-0}" -le "$S13" ]; then
        echo "  [OK]   БЛИЗНЕЦ: форма $form13 — skills: $N13, старт $S13f при контроле $S13"; pass=$((pass + 1))
    else
        echo "  [FAIL] ось F ($form13): skills: $(skills13 "$OUT" "$V13") при контроле $N13, старт ${S13f:-?} при $S13" >&2
        fail=$((fail + 1))
    fi
done
d="$(sandbox i13_comment)"
reform13 "$d/.claude/agents/$V13.md" comment
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: ключ skills: непуст, имён разобрано 0 — краснеет"
assert_says "КРАСНОЕ разбор — $V13: ключ skills: непуст" "ДИАГНОЗ оси F: назван агент и ключ"
d="$(sandbox i13_badyaml)"
sed -i '0,/^skills:/s//skills: {a: [}/' "$d/.claude/agents/$V13.md"
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: frontmatter не YAML и после закавычивания — краснеет"
assert_says "КРАСНОЕ разбор — $V13: frontmatter не YAML" "ДИАГНОЗ оси F: разбор, а не окно"

# ── ось B: основание потолка сходится с замером старта на своей ревизии ────
# Возврат check-verifier: потолок 109739 при основании «старт 71264 + 10 %»
# проходил. Контроль — живая ведомость (потолок = замер × 1,10 вниз) молчит.
B13="$(grep "^$V13	" "$LEDGER13" | cut -f3)"
BN13="$(sed -nE 's/.*старт ([0-9]+) @.*/\1/p' <<<"$B13")"
BR13="$(sed -nE 's/.*старт [0-9]+ @([0-9a-f]+).*/\1/p' <<<"$B13")"
d="$(sandbox i13_basis)"
bled13() {   # <файл> <потолок> <основание> — строка жертвы заменена
    awk -F'\t' -v OFS='\t' -v v="$V13" -v c="$2" -v w="$3" '$1==v{$2=c;$3=w}1' "$LEDGER13" > "$1"
}
bled13 "$TMP/l13_b_ok.tsv" "$(( BN13 * 11 / 10 ))" "$B13"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_b_ok.tsv"
assert_code 0 "БЛИЗНЕЦ: потолок РОВНО замер $BN13 @$BR13 × 1,10 — молчит"
bled13 "$TMP/l13_b_up.tsv" "$(( BN13 * 11 / 10 + 1 ))" "$B13"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_b_up.tsv"
assert_code 1 "ДЕФЕКТ: потолок на символ выше замер × 1,10 при прежнем основании — краснеет"
assert_says "КРАСНОЕ основание устарело — $V13" "ДИАГНОЗ оси B: основание устарело"
bled13 "$TMP/l13_b_lie.tsv" "$(( (BN13 + 1000) * 11 / 10 ))" "ws#1084: старт $(( BN13 + 1000 )) @$BR13 + 10 %"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_b_lie.tsv"
assert_code 1 "ДЕФЕКТ: основание называет старт, которого на ревизии не было — краснеет"
assert_says "КРАСНОЕ основание ложно — $V13" "ДИАГНОЗ оси B: замер на ревизии разошёлся с основанием"
bled13 "$TMP/l13_b_rev.tsv" "$CAP13" "ws#1084: старт $BN13 @0000000deadbeef + 10 %"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_b_rev.tsv"
assert_code 1 "ДЕФЕКТ: ревизии основания нет в истории — краснеет"
assert_says "КРАСНОЕ основание — $V13: ревизии 0000000deadbeef нет" "ДИАГНОЗ оси B: названа ревизия"
bled13 "$TMP/l13_b_none.tsv" "$CAP13" "ws#1084: на глаз"
capture "$d" "$C13" RULES_GATE_WINDOW_BUDGET="$TMP/l13_b_none.tsv"
assert_code 1 "ДЕФЕКТ: основание без замера — краснеет"
assert_says "КРАСНОЕ основание — $V13: в основании нет замера" "ДИАГНОЗ оси B: нет замера"

# ── ось C: CLAUDE.md и тело диспетчера — в окне, их рост краснеет здесь ────
# Порог C — наименьший запас среди агентов, получающих CLAUDE.md, из переписи
# контроля; omitClaudeMd выводится из дерева.
printf '%s\n' "$OUT_Z13" > "$TMP/i13_z.out"
ROOMC13="$(python3 - "$WS" "$TMP/i13_z.out" <<'PY2'
import glob, os, re, sys
omit = set()
for p in glob.glob(os.path.join(sys.argv[1], '.claude/agents/*.md')):
    fm = open(p, encoding='utf-8').read().split('\n---', 1)[0]
    if re.search(r'^omitClaudeMd\s*:\s*true\s*$', fm, re.M):
        omit.add(os.path.splitext(os.path.basename(p))[0])
rooms = [int(m.group(3)) - int(m.group(2)) for m in
         (re.match(r'^  (\S+)\s+старт\s+(\d+) / потолок\s+(\d+)', l)
          for l in open(sys.argv[2], encoding='utf-8'))
         if m and m.group(1) not in omit]
print(min(rooms) if rooms else '')
PY2
)"
growc13() {   # <файл> <символов>
    python3 - "$1" "$2" <<'PY2'
import sys
p, n = sys.argv[1], int(sys.argv[2])
open(p, 'a', encoding='utf-8').write('\n' + 'д' * (n - 1) if n > 0 else '')
PY2
}
if [ -n "$ROOMC13" ]; then
    d="$(sandbox i13_claude_at)"
    growc13 "$d/CLAUDE.md" "$ROOMC13"
    capture "$d" "$C13"
    assert_code 0 "БЛИЗНЕЦ: CLAUDE.md вырос на наименьший запас $ROOMC13 — молчит"
    d="$(sandbox i13_claude_over)"
    growc13 "$d/CLAUDE.md" "$(( ROOMC13 + 1 ))"
    capture "$d" "$C13"
    assert_code 1 "ДЕФЕКТ: раздутый CLAUDE.md (+$(( ROOMC13 + 1 ))) — краснеет в check-13"
    assert_says "КРАСНОЕ окно — " "ДИАГНОЗ оси C: краснеет окно агента"
    d="$(sandbox i13_claude_big)"
    growc13 "$d/CLAUDE.md" 20000
    capture "$d" "$C13"
    assert_code 1 "ДЕФЕКТ: CLAUDE.md +20000 — краснеет и у диспетчера"
    assert_says "КРАСНОЕ окно — dispatcher" "ДИАГНОЗ оси C: CLAUDE.md в окне диспетчера"
else
    echo "  [FAIL] inject-13 ось C НЕИСПОЛНИМА: запас агентов из переписи не прочитан" >&2
    fail=$((fail + 1))
fi
read -r SD13 CD13 < <(start13 "$OUT_Z13" dispatcher)
d="$(sandbox i13_disp)"
growc13 "$d/.claude/agents/dispatcher.md" "$(( ${CD13:-0} - ${SD13:-0} + 1 ))"
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: тело dispatcher.md на символ выше потолка окна — краснеет"
assert_number "перевес" 1 "ДИАГНОЗ оси C: перевес диспетчера назван числом"
assert_says "КРАСНОЕ окно — dispatcher" "ДИАГНОЗ оси C: назван диспетчер"

# ── ось H: истории для сверки оснований нет — отказ, а не молчание ──────────
mkdir -p "$TMP/i13_nogit"
d="$(sandbox i13_nohist)"
capture "$d" "$C13" RULES_GATE_WINDOW_HISTORY="$TMP/i13_nogit" GIT_CEILING_DIRECTORIES="$TMP"
assert_code 2 "ПРЕДПОСЫЛКА: истории git для сверки оснований нет — ОТКАЗ"

echo "  [CENSUS] inject-13: жертва $V13 (старт $S13, потолок $CAP13, запас $ROOM13)," \
     "правило по триггеру $R13; агентов в ведомости $(grep -vc '^#' "$LEDGER13")"
unset -v V13 R13 S13 CAP13 ROOM13 S13t S13f N13 B13 BN13 BR13 ROOMC13 SD13 CD13 OUT_Z13 form13
