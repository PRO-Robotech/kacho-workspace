#!/usr/bin/env bash
# ЧАСТЬ инъекции набора: доказательство check-13 «сколько текста приходит в окно
# одному агенту» по семи осям, в том числе ОБА РЕЖИМА порога — без него и с ним.
#
# Файл ПОДКЛЮЧАЕТСЯ (`.`) из `inject.sh` и пользуется его оснасткой.

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — ЧАСТЬ инъекции, а не самостоятельная проба." >&2
    echo "       Запускать: bash scripts/rules-gate/inject.sh" >&2
    exit 2
fi
for _i13_fn in sandbox capture assert_code assert_says assert_lacks assert_fixture_changed sandbox_digest; do
    command -v "$_i13_fn" >/dev/null 2>&1 && continue
    echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: «$_i13_fn»" >&2
    exit 2
done
unset -v _i13_fn

C13=check-13-agent-window-load.sh

# Жертва — исполнитель с НАИБОЛЬШЕЙ загрузкой, выведенный из дерева: на нём
# порог сработает первым, и ось «порог задан» на ком угодно была бы вакуумной.
read -r AGENT13 LOAD13 <<<"$(python3 - "$WS" <<'PY'
import glob, os, sys
ws = sys.argv[1]
def ch(p):
    try: return len(open(p, encoding='utf-8').read())
    except Exception: return 0
def sk(p):
    L = open(p, encoding='utf-8').read().split('\n')
    try: i = L.index('skills:')
    except ValueError: return []
    o, j = [], i + 1
    while j < len(L) and L[j].startswith('  - '):
        o.append(L[j][4:].strip()); j += 1
    return o
best = ('', 0)
for a in sorted(glob.glob(os.path.join(ws, '.claude/agents/*.md'))):
    n = os.path.basename(a)[:-3]
    t = ch(a) + sum(ch(os.path.join(ws, '.claude/skills', s, 'SKILL.md')) for s in sk(a))
    if t > best[1]:
        best = (n, t)
print(best[0], best[1])
PY
)"
if [ -z "${AGENT13:-}" ] || [ -z "${LOAD13:-}" ]; then
    echo "[VOID] inject-13 — ни одного агента с загрузкой: жертву выводить не из чего" >&2
    exit 2
fi
echo "жертва inject-13 выведена из дерева: «$AGENT13», загрузка $LOAD13 символов"

# ── ось A: порог НЕ задан — проверка считает и МОЛЧИТ ───────────────────────
d="$(sandbox i13_nolimit)"
capture "$d" "$C13"
assert_code 0 "БЕЗ ПОРОГА: проверка считает и не блокирует"
assert_says "порог: НЕ ЗАДАН" "  ...и отсутствие порога названо словом, а не умолчано"
assert_says "осмотрено агентов:" "  ...и знаменатель обхода напечатан"

# ── ось B: порог ЗАДАН и перейдён — краснеет, называя агента и перевес ──────
d="$(sandbox i13_over)"
capture "$d" "$C13" "RULES_GATE_AGENT_WINDOW_MAX=$((LOAD13 - 1))"
assert_code 1 "С ПОРОГОМ: загрузка выше порога — краснеет"
assert_says "$AGENT13" "  ...и назван агент, чьё окно перевешено"
assert_says "перевес 1" "  ...и назван перевес числом"

# ── ось C (БЛИЗНЕЦ): тот же порог на единицу выше — молчит ─────────────────
# Пара B/C одно-фактна: различие ровно в единице порога, дерево не тронуто.
d="$(sandbox i13_under)"
capture "$d" "$C13" "RULES_GATE_AGENT_WINDOW_MAX=$LOAD13"
assert_code 0 "БЛИЗНЕЦ: та же загрузка ровно на пороге — молчит"
assert_lacks "перевес" "  ...и о перевесе не говорится"

# ── ось D: агент без правил и БЕЗ объявления — находка ─────────────────────
# «Ноль правил» штатен у диспетчера и client-simulator; у прочих он неотличим
# от непрочитанного, и проверка обязана это сказать.
d="$(sandbox i13_empty)"
python3 - "$d" <<'PY'
import glob, os, sys
ws = sys.argv[1]
for a in sorted(glob.glob(os.path.join(ws, '.claude/agents/*.md'))):
    n = os.path.basename(a)[:-3]
    if n in ('dispatcher', 'client-simulator'):
        continue
    L = open(a, encoding='utf-8').read().split('\n')
    i = L.index('skills:'); j = i + 1
    while j < len(L) and L[j].startswith('  - '):
        j += 1
    open(a, 'w', encoding='utf-8').write('\n'.join(L[:i + 1] + L[j:]))
    break
PY
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: исполнитель без правил и без объявления — краснеет"
assert_says "необъявленных 1" "  ...и он отделён от штатно пустых числом"

# ── ось E (БЛИЗНЕЦ): штатно пустые остаются штатными ───────────────────────
d="$(sandbox i13_lawful)"
capture "$d" "$C13"
assert_code 0 "БЛИЗНЕЦ: dispatcher и client-simulator без правил — молчит"
assert_says "из них ШТАТНО 2" "  ...и их ноль назван словом, а не слит с непрочитанным"

# ── ось F: закрепление не резолвится — находка ─────────────────────────────
d="$(sandbox i13_dangling)"
python3 - "$d" <<'PY'
import glob, os, sys
ws = sys.argv[1]
for a in sorted(glob.glob(os.path.join(ws, '.claude/agents/*.md'))):
    L = open(a, encoding='utf-8').read().split('\n')
    try: i = L.index('skills:')
    except ValueError: continue
    if not (i + 1 < len(L) and L[i + 1].startswith('  - ')):
        continue
    L.insert(i + 1, '  - rule-zz-inj13-net-takogo')
    open(a, 'w', encoding='utf-8').write('\n'.join(L))
    break
PY
capture "$d" "$C13"
assert_code 1 "ДЕФЕКТ: во frontmatter назван скил без переходника — краснеет"
assert_says "переходника нет" "  ...и сказано, чего именно не хватает"

# ── ось G: определений агентов нет — ОТКАЗ по предмету ─────────────────────
d="$(sandbox i13_void)"
rm -rf "$d/.claude/agents"
capture "$d" "$C13"
assert_code 2 "ОТКАЗ: определений агентов нет — вердикт беспредметен, а не зелёный"

# ── ось Z: нетронутая копия — молчит ───────────────────────────────────────
d="$(sandbox i13_clean)"
capture "$d" "$C13"
assert_code 0 "БЛИЗНЕЦ: нетронутая копия — молчит"
