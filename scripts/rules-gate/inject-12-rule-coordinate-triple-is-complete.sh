#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-12 «координата правила, написанная в
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
for _i12_fn in sandbox capture assert_code assert_says assert_fixture_changed sandbox_digest; do
    command -v "$_i12_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
         "«$_i12_fn» не определена; часть подключена не оттуда" >&2
    exit 2
done
unset -v _i12_fn

C12=check-12-rule-coordinate-triple-is-complete.sh
GHOST12=zz-inj12-ghost           # имя, которого в корпусе нет by construction
if [ -e "$WS/.claude/rules/$GHOST12.md" ]; then
    echo "[VOID] inject-12 — «$GHOST12.md» существует в корпусе: синтетическое имя" \
         "перестало быть синтетическим" >&2
    exit 2
fi

# ЖЕРТВЫ ВЫВОДЯТСЯ ИЗ ДЕРЕВА, А НЕ ВЫПИСЫВАЮТСЯ. Нужны два имени: брифинг, который
# УЖЕ называет координату правила (в него дописывается и дефект, и близнец), и само
# это правило — у него рвётся тройка.
read -r AGENT12 VICTIM12 <<<"$(python3 - "$WS" <<'PY'
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
if [ -z "${AGENT12:-}" ] || [ -z "${VICTIM12:-}" ]; then
    echo "[VOID] inject-12 — ни один брифинг не называет координату существующего правила:" \
         "жертву выводить не из чего" >&2
    exit 2
fi
echo "жертвы inject-12 выведены из дерева: брифинг «$AGENT12», правило «$VICTIM12.md»"

# ── ось A: координата НЕСУЩЕСТВУЮЩЕГО правила в брифинге агента ─────────────
d="$(sandbox i12_ghost)"
printf '\n| пробный триггер | `Skill rule-%s` | `.claude/rules/%s.md` §«Раздел» |\n' \
    "$GHOST12" "$GHOST12" >> "$d/.claude/agents/$AGENT12"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C12"
assert_code 1 "ДЕФЕКТ: брифинг зовёт правило, которого нет — краснеет"
assert_says ".claude/rules/$GHOST12.md" "  ...и координата названа"
assert_says ".claude/agents/$AGENT12" "  ...и назван файл, который её пишет"

# ── ось B (БЛИЗНЕЦ): та же строка, но координата СУЩЕСТВУЮЩЕГО правила ──────
d="$(sandbox i12_live)"; b="$(sandbox_digest "$d")"
printf '\n| пробный триггер | `Skill rule-%s` | `.claude/rules/%s.md` §«Раздел» |\n' \
    "$VICTIM12" "$VICTIM12" >> "$d/.claude/agents/$AGENT12"
git -C "$d" add -A >/dev/null 2>&1
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: строка с координатой живого правила дописана"
capture "$d" "$C12"
assert_code 0 "БЛИЗНЕЦ: брифинг зовёт существующее правило — молчит"

# ── ось C (БЛИЗНЕЦ): ТА ЖЕ несуществующая координата, но в АППАРАТУРЕ ───────
# Аппаратура заводится здесь новая: shebang плюс корпус под корнем-переменной.
# Ни одного имени из перечня — признак берёт её по устройству.
d="$(sandbox i12_fixture)"; b="$(sandbox_digest "$d")"
mkdir -p "$d/scripts/proba-gate"
cat > "$d/scripts/proba-gate/inject-proba.sh" <<'SH'
#!/usr/bin/env bash
# Синтетическая аппаратура: работает на КОПИИ корпуса под корнем-переменной.
w="$(mktemp -d)"
mkdir -p "$w/.claude/rules"
printf '# правило песочницы\n' > "$w/.claude/rules/zz-inj12-ghost.md"
ln -sfn ../../rules/zz-inj12-ghost.md "$w/.claude/skills/rule-zz-inj12-ghost/SKILL.md"
SH
git -C "$d" add -A >/dev/null 2>&1
assert_fixture_changed "$d" "$b" "БЛИЗНЕЦ: заведена новая аппаратура с той же координатой"
capture "$d" "$C12"
assert_code 0 "БЛИЗНЕЦ: та же несуществующая координата в аппаратуре — молчит"

# ── БАРЬЕРЫ ПРИЗНАКА НАГРУЖАЮТСЯ ПОРОЗНЬ, А НЕ ВМЕСТЕ ──────────────────────
# Возврат приёмки W1: прежняя пара меняла ДВА факта сразу (маркер комментария И
# упоминание→акт) и потому ничего не доказывала — красное могло прийти от любого.
# Сетка ниже держит два барьера по отдельности, и каждая пара различает ОДИН факт:
#   S1 комментарий + упоминание    S2 код + упоминание
#   S3 комментарий + АКТ           S4 код + акт
# одно-фактные пары: S3→S4 (только маркер) и S2→S4 (только акт). S1 — контроль
# «оба барьера не пройдены», и он же показывает, что зелёное у S4 не вакуумно.
i12_cell() {   # <каталог> <третья строка файла-пробы>
    mkdir -p "$1/scripts/proba-gate"
    { printf '#!/usr/bin/env bash\n'
      printf '# Норма: .claude/rules/%s.md\n' "$GHOST12"
      printf '%s\n' "$2"; } > "$1/scripts/proba-gate/pribor.sh"
    git -C "$1" add -A >/dev/null 2>&1
}

# ── ось S1: комментарий + упоминание — оба барьера не пройдены ─────────────
d="$(sandbox i12_s1)"
i12_cell "$d" '# пример пути: "$SOME_ROOT/.claude/rules/"'
capture "$d" "$C12"
assert_code 1 "S1 комментарий + упоминание — краснеет"
assert_says "файлов-аппаратуры 0" "  ...и роль не выдана: счёт аппаратуры песочницы остался нулём"

# ── ось S2: КОД + упоминание — не пройден барьер создающего акта ───────────
d="$(sandbox i12_s2)"
i12_cell "$d" 'RULES_DIR="$SOME_ROOT/.claude/rules"'
capture "$d" "$C12"
assert_code 1 "S2 код + упоминание — краснеет: чтение актом не является"

# ── ось S3: комментарий + АКТ — не пройден барьер исполняемой части ────────
# ПАРА S3→S4 ОДНО-ФАКТНА: строка та же посимвольно, различие — ведущий `# `.
d="$(sandbox i12_s3)"
i12_cell "$d" '# mkdir -p "$SOME_ROOT/.claude/rules"'
capture "$d" "$C12"
assert_code 1 "S3 комментарий + АКТ — краснеет: маркер комментария роли не даёт"
assert_says ".claude/rules/$GHOST12.md" "  ...и координата названа"

# ── ось S4 (БЛИЗНЕЦ): код + акт — оба барьера пройдены, роль выдана ────────
d="$(sandbox i12_s4)"; b="$(sandbox_digest "$d")"
i12_cell "$d" 'mkdir -p "$SOME_ROOT/.claude/rules"'
assert_fixture_changed "$d" "$b" "S4 фикстура: та же строка БЕЗ маркера комментария"
capture "$d" "$C12"
assert_code 0 "S4 код + акт — молчит (пара S3→S4: различие ровно в `# `)"
assert_says "файлов-аппаратуры 1" "  ...и роль выдана: счёт аппаратуры песочницы вырос с нуля до одного"

# ── ось C3 (ДЕФЕКТ): РАЗМЕТКЕ роль не выдаётся никогда ─────────────────────
# Барьер формата нагружен отдельно: тело то же, что у S4, меняется ФОРМАТ файла.
d="$(sandbox i12_md)"
{ printf '#!/usr/bin/env bash\n'
  printf 'mkdir -p "$SOME_ROOT/.claude/rules"\n'
  printf 'Координата: .claude/rules/%s.md\n' "$GHOST12"; } > "$d/zz-inj12-proza.md"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C12"
assert_code 1 "C3 разметка с shebang и создающим актом роли не получает — краснеет"

# ── ось D: тройка разорвана — снят ПЕРЕХОДНИК при живых файле и строке ──────
d="$(sandbox i12_link)"
rm -rf "$d/.claude/skills/rule-$VICTIM12"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C12"
assert_code 1 "ДЕФЕКТ: переходник снят при живых файле и строке — краснеет"
assert_says "переходника" "  ...и названа именно снятая половина"

# ── ось E: снята СТРОКА МАНИФЕСТА при живых файле и переходнике ─────────────
d="$(sandbox i12_row)"
grep -v "^| \`$VICTIM12\.md\` |" "$d/.claude/rules/MANIFEST.md" > "$d/.claude/rules/MANIFEST.md.tmp"
mv "$d/.claude/rules/MANIFEST.md.tmp" "$d/.claude/rules/MANIFEST.md"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C12"
assert_code 1 "ДЕФЕКТ: строка манифеста снята при живых файле и переходнике — краснеет"
assert_says "строки в .claude/rules/MANIFEST.md нет" "  ...и названа именно снятая половина"

# ── ось F: снят САМ ФАЙЛ при живых переходнике и строке ─────────────────────
d="$(sandbox i12_file)"
rm -f "$d/.claude/rules/$VICTIM12.md"
git -C "$d" add -A >/dev/null 2>&1
capture "$d" "$C12"
assert_code 1 "ДЕФЕКТ: файл правила снят при живых переходнике и строке — краснеет"
assert_says "файла .claude/rules/$VICTIM12.md нет" "  ...и названа именно снятая половина"

# ── ось G: обход усечён — ОТКАЗ по беспредметности, а не «находок ноль» ─────
d="$(sandbox i12_void)"
git -C "$d" rm -r --cached . -q >/dev/null 2>&1
capture "$d" "$C12"
assert_code 2 "ОТКАЗ: отслеживаемых файлов ноль — вердикт беспредметен, а не зелёный"

# ── ось Z: нетронутая копия — молчит ───────────────────────────────────────
d="$(sandbox i12_clean)"
capture "$d" "$C12"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"
