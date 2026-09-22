#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-10 «координата правила, написанная в
# дереве, резолвится, и её тройка полна» по семи осям.
#
# ПАРА, РАДИ КОТОРОЙ ПРОВЕРКА ЗАВЕДЕНА, — оси A и C: ОДНА И ТА ЖЕ несуществующая
# координата краснеет в брифинге агента и МОЛЧИТ в аппаратуре, работающей на копии
# корпуса. Различает их не имя из перечня, а УСТРОЙСТВО файла-референта, и ось C
# доказывает именно это: аппаратура заводится здесь НОВАЯ, её в дереве нет, и
# никакой список имён её бы не знал.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

# ── СТРАЖ ПОДКЛЮЧЕНИЯ ────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Запускать: bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i10_fn in sandbox capture assert_code assert_says assert_fixture_changed sandbox_digest; do
    command -v "$_i10_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i10_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i10_fn

C10=check-10-rule-coordinate-resolves.sh
GHOST10=zz-inj10-ghost           # имя, которого в корпусе нет by construction
if [ -e "$WS/.claude/rules/$GHOST10.md" ]; then
    echo "[VOID] inject-10 — «$GHOST10.md» существует в корпусе: синтетическое имя" \
         "перестало быть синтетическим" >&2
    exit 2
fi

# ЖЕРТВЫ ВЫВОДЯТСЯ ИЗ ДЕРЕВА, А НЕ ВЫПИСЫВАЮТСЯ. Нужны два имени: брифинг, который
# УЖЕ называет координату правила (в него дописывается и дефект, и близнец), и само
# это правило — у него рвётся тройка.
read -r AGENT10 VICTIM10 <<<"$(python3 - "$WS" <<'PY'
import os, re, sys
ws = sys.argv[1]
coord = re.compile(r'\.claude/rules/([A-Za-z0-9_][A-Za-z0-9_.-]*)\.md')
adir = os.path.join(ws, '.claude', 'agents')
for a in sorted(os.listdir(adir)):
    if not a.endswith('.md') or a == 'dispatcher.md':
        continue
    text = open(os.path.join(adir, a), encoding='utf-8').read()
    for m in coord.finditer(text):
        n = m.group(1)
        if os.path.isfile(os.path.join(ws, '.claude', 'rules', n + '.md')):
            print(a, n)
            sys.exit(0)
print('', '')
PY
)"
if [ -z "${AGENT10:-}" ] || [ -z "${VICTIM10:-}" ]; then
    echo "[VOID] inject-10 — ни один брифинг не называет координату существующего правила:" \
         "жертву выводить не из чего" >&2
    exit 2
fi
echo "жертвы inject-10 выведены из дерева: брифинг «$AGENT10», правило «$VICTIM10.md»"

# ── ось A: координата НЕСУЩЕСТВУЮЩЕГО правила в брифинге агента ─────────────
d="$(sandbox i10_ghost)"
printf '\n| пробный триггер | `Skill rule-%s` | `.claude/rules/%s.md` §«Раздел» |\n' \
    "$GHOST10" "$GHOST10" >> "$d/.claude/agents/$AGENT10"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: брифинг зовёт правило, которого нет — краснеет"
assert_says ".claude/rules/$GHOST10.md" "  ...и координата названа"
assert_says ".claude/agents/$AGENT10" "  ...и назван файл, который её пишет"

# ── ось B (БЛИЗНЕЦ): та же строка, но координата СУЩЕСТВУЮЩЕГО правила ──────
d="$(sandbox i10_live)"; b="$(sandbox_digest "$d")"
printf '\n| пробный триггер | `Skill rule-%s` | `.claude/rules/%s.md` §«Раздел» |\n' \
    "$VICTIM10" "$VICTIM10" >> "$d/.claude/agents/$AGENT10"
git -C "$d" add -A >/dev/null 2>&1
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: строка с координатой живого правила дописана"
capture "$d" "$C10"
assert_code 0 "БЛИЗНЕЦ: брифинг зовёт существующее правило — молчит"

# ── ось C (БЛИЗНЕЦ): ТА ЖЕ несуществующая координата, но в АППАРАТУРЕ ───────
# Аппаратура заводится здесь новая: shebang плюс корпус под корнем-переменной.
# Ни одного имени из перечня — признак берёт её по устройству.
d="$(sandbox i10_fixture)"; b="$(sandbox_digest "$d")"
mkdir -p "$d/scripts/proba-gate"
cat > "$d/scripts/proba-gate/inject-proba.sh" <<'SH'
#!/usr/bin/env bash
# Синтетическая аппаратура: работает на КОПИИ корпуса под корнем-переменной.
w="$(mktemp -d)"
mkdir -p "$w/.claude/rules"
printf '# правило песочницы\n' > "$w/.claude/rules/zz-inj10-ghost.md"
ln -sfn ../../rules/zz-inj10-ghost.md "$w/.claude/skills/rule-zz-inj10-ghost/SKILL.md"
SH
git -C "$d" add -A >/dev/null 2>&1
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: заведена новая аппаратура с той же координатой"
capture "$d" "$C10"
assert_code 0 "БЛИЗНЕЦ: та же несуществующая координата в аппаратуре — молчит"

# ── ось D: тройка разорвана — снят ПЕРЕХОДНИК при живых файле и строке ──────
d="$(sandbox i10_link)"
rm -rf "$d/.claude/skills/rule-$VICTIM10"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: переходник снят при живых файле и строке — краснеет"
assert_says "переходника" "  ...и названа именно снятая половина"

# ── ось E: снята СТРОКА МАНИФЕСТА при живых файле и переходнике ─────────────
d="$(sandbox i10_row)"
grep -v "^| \`$VICTIM10\.md\` |" "$d/.claude/rules/MANIFEST.md" > "$d/.claude/rules/MANIFEST.md.tmp"
mv "$d/.claude/rules/MANIFEST.md.tmp" "$d/.claude/rules/MANIFEST.md"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: строка манифеста снята при живых файле и переходнике — краснеет"
assert_says "строки в .claude/rules/MANIFEST.md нет" "  ...и названа именно снятая половина"

# ── ось F: снят САМ ФАЙЛ при живых переходнике и строке ─────────────────────
d="$(sandbox i10_file)"
rm -f "$d/.claude/rules/$VICTIM10.md"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C10"
assert_code 1 "ДЕФЕКТ: файл правила снят при живых переходнике и строке — краснеет"
assert_says "файла .claude/rules/$VICTIM10.md нет" "  ...и названа именно снятая половина"

# ── ось G: обход усечён — ОТКАЗ по беспредметности, а не «находок ноль» ─────
d="$(sandbox i10_void)"
git -C "$d" rm -r --cached . -q >/dev/null 2>&1
capture "$d" "$C10"
assert_code 2 "ОТКАЗ: отслеживаемых файлов ноль — вердикт беспредметен, а не зелёный"

# ── ось Z: нетронутая копия — молчит ───────────────────────────────────────
d="$(sandbox i10_clean)"
capture "$d" "$C10"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"
