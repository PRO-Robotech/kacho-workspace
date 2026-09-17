#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-04 «привязка правила к агенту сходится в обе стороны».
#
# ЧТО ЗДЕСЬ ДОКАЗЫВАЕТСЯ. По КАЖДОЙ оси проверки — пара: НАСТОЯЩИЙ дефект, на
# котором гейт обязан покраснеть и назвать координату, и рядом ЗАКОННЫЙ БЛИЗНЕЦ
# той же формы, на котором обязан смолчать. Одного дефекта мало: гейт, красный на
# всём, блокирует отправку и снимается вместе с настоящими находками; одного
# близнеца мало: гейт, зелёный на всём, не доказывает ничего вовсе
# (`.claude/rules/testing.md` §«Гейт на класс»).
#
# ПОЧЕМУ БЛИЗНЕЦЫ ЗДЕСЬ НЕ УКРАШЕНИЕ. Предмет check-04 — СОВПАДЕНИЕ МНОЖЕСТВ в
# четырёх местах, а множество легко спутать с текстом. Переставленный порядок имён
# в ячейке, переставленный `skills:`, иначе написанный путь той же ссылки — всё это
# ПРАВКИ ТЕКСТА при неизменном множестве, и гейт, сверяющий текст, покраснел бы на
# каждой. Первый же такой ложный срабат стоит гейту жизни.
#
# МАСКА, РАДИ КОТОРОЙ ЗАВЕДЕНА ОСЬ G. Ссылка-переходник, подменённая ОБЫЧНЫМ
# ФАЙЛОМ С ТЕМ ЖЕ СОДЕРЖИМЫМ, не различима ничем, кроме типа записи: `diff` молчит,
# содержимое совпадает побайтово, агент грузит «то же самое». Расходиться копия
# начнёт потом — молча и навсегда. Поэтому предикат гейта — `os.path.islink`, а
# проба подменяет ссылку именно КОПИЕЙ, а не другим текстом: проба, подменившая
# содержимое, доказывала бы не то, что объявляет.
#
# ПЕСОЧНИЦА СВОЯ, И ЭТО НЕСУЩЕЕ. Предмет check-04 — четыре места сразу
# (`.claude/rules`, `MANIFEST.md`, `.claude/agents`, `.claude/skills`), поэтому
# копируются все четыре плюс `CLAUDE.md` и `.claude/settings.json`. Каталог скилов
# копируется С СОХРАНЕНИЕМ ССЫЛОК (`cp -a`): разыменуй их копирование — и КАЖДАЯ
# песочница несла бы ровно тот дефект, который ось G обязана ловить, то есть
# контроль краснел бы на фикстуре набора.
#
# ФАЙЛ ИСПОЛНЯЕТСЯ ДВУМЯ СПОСОБАМИ, и оба законны:
#   · `bash scripts/rules-gate/inject-04-rule-agent-binding.sh` — сам по себе, со
#     своей оснасткой и своим вердиктом в коде выхода;
#   · подключением (`.`) из `inject.sh` — тогда берутся ЕГО `capture`/`assert_*`,
#     и удавшиеся утверждения попадают в его перепись доказанности проверок.
# Своя оснастка появляется ТОЛЬКО в первом случае и не переопределяет чужую:
# два разных определения `assert_code` в одном прогоне разошлись бы молча.
# Рабочее дерево не портится ни в одном из режимов: правки идут только в
# `mktemp -d`, а имена жертв выводятся ИЗ дерева, а не выписываются.
#
# Коды выхода (самостоятельный режим): 0 — все утверждения сошлись; 1 — хоть одно
# разошлось; 2 — не прогнано ни одного (это НЕ успех).

set -uo pipefail

CH04=check-04-rule-agent-binding.sh

if [ "${BASH_SOURCE[0]}" = "$0" ]; then INJ04_ALONE=1; else INJ04_ALONE=0; fi

if [ "$INJ04_ALONE" = 1 ]; then
    HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GATE="$HERE"
    WS="$(cd "$HERE/../.." && pwd)"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    pass=0; fail=0; OUT=""; RC=0

    # `LAST_CHECK` здесь НЕ заводится намеренно, и это не пропуск: перепись
    # доказанности ПО ПРОВЕРКАМ (какой из проверок набора досталась находка, какой
    # близнец) живёт в inject.sh и имеет смысл только там, где проверок много.
    # Самостоятельный режим гоняет ровно одну — $CH04, — и её имя уже напечатано в
    # [CENSUS] ниже. Заведи переменную «для симметрии» — и в дереве появилось бы
    # второе, немое хранилище переписи, по которому однажды отчитались бы вместо
    # настоящего.
    capture() {   # <каталог> <имя проверки>
        OUT="$( cd "$1" && RULES_GATE_ROOT="$1" bash "$GATE/$2" 2>&1 )"
        RC=$?
    }
    assert_code() {   # <ожидаемый> <утверждение>
        if [ "$1" = "$RC" ]; then
            echo "  [OK]   $2"; pass=$((pass + 1))
        else
            echo "  [FAIL] $2 — ожидался код $1, получен $RC" >&2
            printf '%s\n' "$OUT" | sed 's/^/         | /' >&2
            fail=$((fail + 1))
        fi
    }
    assert_says() {   # <подстрока> <утверждение>
        if printf '%s\n' "$OUT" | grep -qF -- "$1"; then
            echo "  [OK]   $2"; pass=$((pass + 1))
        else
            echo "  [FAIL] $2 — в вердикте нет «$1»" >&2
            printf '%s\n' "$OUT" | sed 's/^/         | /' >&2
            fail=$((fail + 1))
        fi
    }
    # Отпечаток по СОДЕРЖИМОМУ и ТИПУ записи: часть фикстур подменяет ссылку
    # файлом, и различие типа обязано считаться правкой.
    sandbox_digest() {   # <каталог песочницы>
        (
            cd "$1" 2>/dev/null || exit 0
            find . -path ./.git -prune -o -print0 2>/dev/null \
            | LC_ALL=C sort -z \
            | while IFS= read -r -d '' e; do
                  if [ -L "$e" ]; then printf 'l %s -> %s\n' "$e" "$(readlink "$e")"
                  elif [ -f "$e" ]; then printf 'f %s %s\n' "$e" "$(md5sum < "$e" | cut -d' ' -f1)"
                  else printf 'd %s\n' "$e"; fi
              done
        ) | md5sum | cut -d' ' -f1
    }
    assert_fixture_changed() {   # <каталог> <отпечаток ДО> <утверждение>
        local now; now="$(sandbox_digest "$1")"
        if [ "$now" = "$2" ]; then
            echo "  [FAIL] ФИКСТУРА ВАКУУМНА · $3 — правка не изменила песочницу $1;" \
                 "утверждение о молчании гейта относится к НЕТРОНУТОМУ дереву" >&2
            fail=$((fail + 1))
        else
            echo "  [OK]   фикстура изменила песочницу · $3"; pass=$((pass + 1))
        fi
    }
else
    # Подключение из inject.sh: оснастка ЕГО, и она спрашивается поимённо. Без
    # неё часть не просто ничего не доказывает — она пишет мимо песочницы.
    for _inj04_fn in capture assert_code assert_says assert_fixture_changed sandbox_digest; do
        command -v "$_inj04_fn" >/dev/null 2>&1 && continue
        echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
             "«$_inj04_fn» не определена; часть подключена не оттуда, доказывать нечем" >&2
        exit 2
    done
    unset -v _inj04_fn
    if [ -z "${WS:-}" ] || [ ! -d "$WS" ] || [ -z "${TMP:-}" ] || [ ! -d "$TMP" ]; then
        echo "[VOID] $(basename "${BASH_SOURCE[0]}") — \$WS или \$TMP inject.sh не определены;" \
             "жертву выводить не из чего, писать некуда" >&2
        exit 2
    fi
    GATE="${GATE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
fi

# ── ПЕСОЧНИЦА: все четыре места привязки сразу ──────────────────────────────
# `cp -a` — не вкусовщина: `-r` над каталогом скилов вправе РАЗЫМЕНОВАТЬ ссылки, и
# тогда фикстура несла бы дефект оси G сама.
inj04_sandbox() {   # <имя>
    local dir="$TMP/s04.$1"
    rm -rf "$dir"; mkdir -p "$dir/.claude"
    cp "$WS/CLAUDE.md" "$dir/" 2>/dev/null || true
    cp -a "$WS/.claude/rules" "$dir/.claude/"
    cp -a "$WS/.claude/agents" "$dir/.claude/"
    cp -a "$WS/.claude/skills" "$dir/.claude/" 2>/dev/null || true
    cp -a "$WS/.claude/settings.json" "$dir/.claude/" 2>/dev/null || true
    cp "$WS/.gitignore" "$dir/" 2>/dev/null || true
    git -C "$dir" init -q >/dev/null 2>&1
    git -C "$dir" add -A >/dev/null 2>&1
    echo "$dir"
}

# ── ЖЕРТВЫ ВЫВОДЯТСЯ ИЗ ДЕРЕВА ──────────────────────────────────────────────
# Выписанные имена отстают от дерева молча: правило переехало — проба стала
# вакуумной и печатает `[OK]` о нетронутой копии. Нужны четыре: правило,
# закреплённое РОВНО ЗА ОДНИМ агентом (на нём чисто видны обе стороны расхождения),
# этот агент, любой агент с ДВУМЯ и более правилами и любое правило с ДВУМЯ и более
# агентами (на последних двух доказывается, что сверяется множество, а не порядок).
inj04_facts="$(python3 - "$WS" <<'PY'
import io, os, re, sys
ws = sys.argv[1]
man = os.path.join(ws, '.claude', 'rules', 'MANIFEST.md')
agents = {f[:-3] for f in os.listdir(os.path.join(ws, '.claude', 'agents'))
          if f.endswith('.md')}
single = None
many_rule = None
counts = {}
for line in io.open(man, encoding='utf-8'):
    if not line.startswith('|'):
        continue
    c = line.replace('\\|', '\001').split('|')
    if len(c) < 6:
        continue
    name = c[1].strip().strip('`')
    if not name.endswith('.md'):
        continue
    names = [x.strip() for x in re.findall(r'`([^`]*)`', c[4]) if x.strip()]
    names = [n for n in names if n in agents]
    for a in names:
        counts[a] = counts.get(a, 0) + 1
    if len(names) == 1 and single is None:
        single = (name, names[0])
    if len(names) >= 2 and many_rule is None:
        many_rule = name
many_agent = next((a for a, n in sorted(counts.items()) if n >= 2), None)
if not single or not many_agent or not many_rule:
    raise SystemExit('')
print('%s\t%s\t%s\t%s' % (single[0], single[1], many_agent, many_rule))
PY
)"
if [ -z "$inj04_facts" ]; then
    echo "[VOID] inject-04 — в таблице MANIFEST.md не нашлось всех четырёх жертв (правила" \
         "с одним агентом, агента с двумя правилами, правила с двумя агентами);" \
         "доказывать не на чем" >&2
    exit 2
fi
IFS=$'\t' read -r INJ04_RULE INJ04_AGENT INJ04_MULTI INJ04_MULTIRULE <<<"$inj04_facts"
INJ04_SKILL="rule-${INJ04_RULE%.md}"
echo "-- жертвы выведены из дерева: правило «$INJ04_RULE» закреплено за «$INJ04_AGENT»;" \
     "агент с несколькими правилами — «$INJ04_MULTI»; правило с несколькими агентами —" \
     "«$INJ04_MULTIRULE» --"

# ── ПРАВКИ ПЕСОЧНИЦЫ ────────────────────────────────────────────────────────
# Каждая операция ОБЯЗАНА изменить файл: правка-пустышка делает утверждение
# вакуумным, а `[OK]` близнеца — дословно тем же, что на нетронутой копии.
inj04_edit() {   # <каталог> <операция> [аргументы…]
    python3 - "$@" <<'PY'
import io, os, re, sys
d, op = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
man = os.path.join(d, '.claude', 'rules', 'MANIFEST.md')


def rows(text):
    return text.split('\n')


def row_index(lines, rule):
    for i, l in enumerate(lines):
        if re.match(r'^\|\s*`?' + re.escape(rule) + r'`?\s*\|', l):
            return i
    raise SystemExit('ФИКСТУРА ВАКУУМНА: строки про «%s» в манифесте нет' % rule)


def edit_file(path, fn):
    before = io.open(path, encoding='utf-8').read()
    after = fn(before)
    if after == before:
        raise SystemExit('ФИКСТУРА ВАКУУМНА: операция «%s» не изменила %s; утверждение о '
                         'вердикте гейта относилось бы к нетронутому дереву' % (op, path))
    io.open(path, 'w', encoding='utf-8').write(after)


def cell(rule, fn):
    def apply(text):
        lines = rows(text)
        i = row_index(lines, rule)
        c = lines[i].split('|')
        while len(c) < 6:
            c.insert(len(c) - 1, '  ')
        c[4] = fn(c[4])
        lines[i] = '|'.join(c)
        return '\n'.join(lines)
    edit_file(man, apply)


def agent_path(name):
    return os.path.join(d, '.claude', 'agents', name + '.md')


def skills_block(text):
    # `-` и ПРОБЕЛ обязательны: `[ \t]*-[ \t]*\S+` зачитывает за элемент списка
    # закрывающую черту frontmatter (`---` = «-» + «--»), и тогда правка сносит
    # её вместе с блоком. Поймано на себе: близнец «переставленный порядок»
    # выносил семь скилов из семи и краснел там, где обязан молчать.
    m = re.search(r'^skills:[ \t]*\n((?:[ \t]*-[ \t]+\S+[ \t]*\n)+)', text, re.M)
    if not m:
        raise SystemExit('ФИКСТУРА ВАКУУМНА: у агента нет блочного ключа skills:')
    return m


if op == 'cell_empty':                       # ячейка агентов выпотрошена
    cell(args[0], lambda _: '  ')
elif op == 'cell_reverse':                   # тот же набор, обратный порядок
    def rev(s):
        names = re.findall(r'`([^`]*)`', s)
        if len(names) < 2:
            raise SystemExit('ФИКСТУРА ВАКУУМНА: в ячейке меньше двух имён, '
                             'переставлять нечего')
        return ' ' + ' · '.join('`%s`' % n for n in reversed(names)) + ' '
    cell(args[0], rev)
elif op == 'cell_add':                       # дописать имя в ячейку
    cell(args[0], lambda s: s.rstrip() + ' · `%s` ' % args[1])
elif op == 'cell_row_new':                   # НОВАЯ полная строка таблицы
    def add(text):
        lines = rows(text)
        i = max(k for k, l in enumerate(lines)
                if re.match(r'^\|\s*`?[^|`]+\.md`?\s*\|', l))
        lines.insert(i + 1, '| `%s` | проба инъекции | гейт-свидетель | `%s` |'
                     % (args[0], args[1]))
        return '\n'.join(lines)
    edit_file(man, add)
elif op == 'table_gut':                      # снять ВСЕ строки таблицы
    edit_file(man, lambda t: '\n'.join(
        l for l in rows(t) if not re.match(r'^\|\s*`?[^|`]+\.md`?\s*\|', l)))
elif op == 'skills_drop':                    # убрать rule-X из frontmatter
    def drop(text):
        return re.sub(r'^[ \t]*-[ \t]*%s[ \t]*\n' % re.escape(args[1]), '', text, count=1,
                      flags=re.M)
    edit_file(agent_path(args[0]), drop)
elif op == 'skills_add':                     # дописать скил во frontmatter
    def add(text):
        m = skills_block(text)
        return text[:m.end(1)] + '  - %s\n' % args[1] + text[m.end(1):]
    edit_file(agent_path(args[0]), add)
elif op == 'skills_reverse':                 # тот же набор, обратный порядок
    def rev(text):
        m = skills_block(text)
        items = [l for l in m.group(1).split('\n') if l.strip()]
        if len(items) < 2:
            raise SystemExit('ФИКСТУРА ВАКУУМНА: у агента меньше двух скилов')
        return text[:m.start(1)] + '\n'.join(reversed(items)) + '\n' + text[m.end(1):]
    edit_file(agent_path(args[0]), rev)
else:
    raise SystemExit('unknown op ' + op)
PY
}

echo "== контроль: нетронутая копия — check-04 молчит =="
# Без него всякое «покраснел» ниже относилось бы к фикстуре набора, а не к дефекту.
d4="$(inj04_sandbox control)"
capture "$d4" "$CH04"
assert_code 0 "нетронутая копия · $CH04"

echo "== ось A: правило не закреплено ни за кем (RULE-UNBOUND) =="
d4="$(inj04_sandbox a_unbound)"
inj04_edit "$d4" cell_empty "$INJ04_RULE"
capture "$d4" "$CH04"
assert_code 1 "пустая ячейка агентов — правило не прочтёт никто"
assert_says "RULE-UNBOUND" "  ...находка названа осью"
assert_says "$INJ04_RULE" "  ...и названо ИМЕННО это правило"

echo "== ось A′: БЛИЗНЕЦ — тот же набор агентов, обратный порядок =="
# Сверяется МНОЖЕСТВО. Гейт, сверяющий текст ячейки, покраснел бы на перестановке —
# правке, которую делает всякий, кто сортирует перечень.
d4="$(inj04_sandbox a_reorder)"; b4="$(sandbox_digest "$d4")"
inj04_edit "$d4" cell_reverse "$INJ04_MULTIRULE"
assert_fixture_changed "$d4" "$b4" "БЛИЗНЕЦ: порядок имён в ячейке перевёрнут"
capture "$d4" "$CH04"
assert_code 0 "перестановка имён множества не меняет — гейт молчит"

echo "== ось B: закрепление за несуществующим агентом (AGENT-UNKNOWN) =="
d4="$(inj04_sandbox b_unknown)"
inj04_edit "$d4" cell_add "$INJ04_RULE" "zzz-inj04-нет-такого-агента"
capture "$d4" "$CH04"
assert_code 1 "имя в ячейке, которому не соответствует файл агента"
assert_says "AGENT-UNKNOWN" "  ...находка названа осью"
assert_says "zzz-inj04-нет-такого-агента" "  ...и названо ИМЕННО это имя"

echo "== ось B′: БЛИЗНЕЦ — правило закреплено ЗА ЕЩЁ ОДНИМ существующим агентом =="
# Законная правка целиком: имя в ячейке И строка во frontmatter. Покрасней гейт
# здесь — закрепить правило за вторым агентом стало бы невозможно.
d4="$(inj04_sandbox b_second_agent)"; b4="$(sandbox_digest "$d4")"
inj04_edit "$d4" cell_add "$INJ04_RULE" "$INJ04_MULTI"
inj04_edit "$d4" skills_add "$INJ04_MULTI" "$INJ04_SKILL"
assert_fixture_changed "$d4" "$b4" "БЛИЗНЕЦ: второй агент назван в обоих местах"
capture "$d4" "$CH04"
assert_code 0 "объявление и исполнение сошлись — гейт молчит"

echo "== ось C: манифест закрепил, а frontmatter не грузит (BINDING-DRIFT ←) =="
d4="$(inj04_sandbox c_drift_left)"
inj04_edit "$d4" skills_drop "$INJ04_AGENT" "$INJ04_SKILL"
capture "$d4" "$CH04"
assert_code 1 "правило закреплено и не доезжает — его не читает никто"
assert_says "BINDING-DRIFT" "  ...находка названа осью"
assert_says "манифест закрепил, а во frontmatter нет" "  ...и названа ИМЕННО эта сторона"

echo "== ось D: frontmatter грузит, а манифест не закреплял (BINDING-DRIFT →) =="
# Вторая сторона — не симметрия ради симметрии: правило, доехавшее без строки,
# грузится БЕЗ решения, и колонка перестаёт отвечать, кому что грузится.
d4="$(inj04_sandbox d_drift_right)"
inj04_edit "$d4" skills_add "$INJ04_AGENT" "rule-${INJ04_RULE%.md}-нет-в-манифесте"
capture "$d4" "$CH04"
assert_code 1 "скил во frontmatter без строки манифеста"
assert_says "frontmatter грузит, а манифест не закреплял" "  ...и названа ВТОРАЯ сторона"

echo "== ось D′: БЛИЗНЕЦ — тот же набор skills, обратный порядок =="
d4="$(inj04_sandbox d_reorder)"; b4="$(sandbox_digest "$d4")"
inj04_edit "$d4" skills_reverse "$INJ04_MULTI"
assert_fixture_changed "$d4" "$b4" "БЛИЗНЕЦ: порядок skills перевёрнут"
capture "$d4" "$CH04"
assert_code 0 "порядок предзагрузки множества не меняет — гейт молчит"

echo "== ось E: переходника нет (RULE-SKILL-MISSING) =="
d4="$(inj04_sandbox e_no_skill)"
rm -rf "$d4/.claude/skills/$INJ04_SKILL"
capture "$d4" "$CH04"
assert_code 1 "каталога скила нет — предзагружать правило нечем"
assert_says "RULE-SKILL-MISSING" "  ...находка названа осью"

echo "== ось F: переходник — КОПИЯ, а не ссылка (та же маска, что у check-01) =="
# Содержимое побайтово то же: `diff` молчит, агент грузит «то же самое», и
# расходиться копия начнёт потом — молча и навсегда. Различается ТОЛЬКО тип записи.
d4="$(inj04_sandbox f_copy)"; b4="$(sandbox_digest "$d4")"
cp --remove-destination "$d4/.claude/rules/$INJ04_RULE" "$d4/.claude/skills/$INJ04_SKILL/SKILL.md"
assert_fixture_changed "$d4" "$b4" "ФИКСТУРА: ссылка подменена копией с тем же содержимым"
capture "$d4" "$CH04"
assert_code 1 "копия вместо ссылки — находка, хотя содержимое совпадает побайтово"
assert_says "не символьная ссылка" "  ...и названа ИМЕННО подмена типа записи"

echo "== ось G: ссылка ведёт на ЧУЖОЕ правило =="
d4="$(inj04_sandbox g_wrong_target)"
# Чужое правило берётся ГЛОБОМ ОБОЛОЧКИ, а не разбором `ls`, — тем же доводом, что
# и жертвы в inject.sh: корпус русский, а разбор вывода `ls` спотыкается на
# не-алфавитных именах (SC2010/SC2012). Отсев жертвы — СРАВНЕНИЕМ СТРОК, а не
# `grep -v "^…$"`: имя правила кончается на `.md`, и точка в регулярном выражении
# заодно вычёркивала бы `xx-md`-однофамильца, то есть проба тихо осталась бы без
# цели и подменила бы ссылку пустотой.
inj04_other=""
for _inj04_f in "$d4/.claude/rules"/*.md; do
    [ -f "$_inj04_f" ] || continue
    _inj04_b="$(basename "$_inj04_f")"
    [ "$_inj04_b" = "$INJ04_RULE" ] && continue
    inj04_other="$_inj04_b"; break
done
unset -v _inj04_f _inj04_b
ln -sfn "../../rules/$inj04_other" "$d4/.claude/skills/$INJ04_SKILL/SKILL.md"
capture "$d4" "$CH04"
assert_code 1 "ссылка на чужое правило — агент грузит не то, что объявлено"
assert_says "ведёт не на своё правило" "  ...и названа ИМЕННО подмена цели"

echo "== ось G′: БЛИЗНЕЦ — та же цель, другое написание пути =="
# Решение принимается по РАЗЫМЕНОВАННОЙ цели. Гейт, сверяющий текст ссылки,
# покраснел бы на `./` — форме, которую пишет всякий второй.
d4="$(inj04_sandbox g_same_target)"; b4="$(sandbox_digest "$d4")"
ln -sfn "../../rules/./$INJ04_RULE" "$d4/.claude/skills/$INJ04_SKILL/SKILL.md"
assert_fixture_changed "$d4" "$b4" "БЛИЗНЕЦ: путь переписан через ./, цель та же"
capture "$d4" "$CH04"
assert_code 0 "иначе написанный путь к тому же правилу — не находка"

echo "== ось H: переходник без правила (RULE-SKILL-ORPHAN) =="
d4="$(inj04_sandbox h_orphan)"
mkdir -p "$d4/.claude/skills/rule-zzz-inj04-none"
ln -s "../../rules/zzz-inj04-none.md" "$d4/.claude/skills/rule-zzz-inj04-none/SKILL.md"
capture "$d4" "$CH04"
assert_code 1 "каталог rule-* без своего правила — след переименования либо самозванец"
assert_says "RULE-SKILL-ORPHAN" "  ...находка названа осью"

echo "== ось H′: БЛИЗНЕЦ — обычный скил рядом, имя НЕ rule-* =="
# Предмет оси — зарезервированное имя, а не «лишний каталог в skills». Покрасней
# гейт здесь — завести экспертизу стало бы нельзя.
d4="$(inj04_sandbox h_plain_skill)"; b4="$(sandbox_digest "$d4")"
mkdir -p "$d4/.claude/skills/zzz-inj04-expertise"
printf -- '---\nname: zzz-inj04-expertise\n---\n\n# Экспертиза\n' \
    > "$d4/.claude/skills/zzz-inj04-expertise/SKILL.md"
assert_fixture_changed "$d4" "$b4" "БЛИЗНЕЦ: обычный скил без имени rule-*"
capture "$d4" "$CH04"
assert_code 0 "скил, не занявший зарезервированного имени, — не предмет привязки"

echo "== ось I: агент грузит несуществующее правило (AGENT-RULE-DANGLING) =="
d4="$(inj04_sandbox i_dangling)"
inj04_edit "$d4" skills_add "$INJ04_AGENT" "rule-zzz-inj04-nope"
capture "$d4" "$CH04"
assert_code 1 "ссылка на правило, которого нет в корпусе"
assert_says "AGENT-RULE-DANGLING" "  ...находка названа осью"
assert_says "rule-zzz-inj04-nope" "  ...и назван ИМЕННО этот скил"

echo "== ось I′: БЛИЗНЕЦ — во frontmatter дописан НЕ-rule скил =="
# Предикат оси — `rule-*`, а не «всякий скил». Агент вправе нести экспертизу.
d4="$(inj04_sandbox i_plain_in_fm)"; b4="$(sandbox_digest "$d4")"
mkdir -p "$d4/.claude/skills/zzz-inj04-coach"
printf -- '---\nname: zzz-inj04-coach\n---\n\n# Тренер\n' \
    > "$d4/.claude/skills/zzz-inj04-coach/SKILL.md"
inj04_edit "$d4" skills_add "$INJ04_AGENT" "zzz-inj04-coach"
assert_fixture_changed "$d4" "$b4" "БЛИЗНЕЦ: экспертиза во frontmatter агента"
capture "$d4" "$CH04"
assert_code 0 "не-rule скил предметом привязки не является"

echo "== ось J: НОВОЕ ПРАВИЛО, заведённое по всем четырём местам — молчит =="
# Самый ценный близнец набора: он утверждает, что гейт не запрещает РАСТИ. Всё,
# чего он требует, — чтобы рост был решением, видимым в диффе, а не побочным
# эффектом (файл + строка с агентом + frontmatter + переходник).
d4="$(inj04_sandbox j_new_rule)"; b4="$(sandbox_digest "$d4")"
printf '# Правило-свидетель инъекции\n' > "$d4/.claude/rules/zzz-inj04-new.md"
mkdir -p "$d4/.claude/skills/rule-zzz-inj04-new"
ln -s "../../rules/zzz-inj04-new.md" "$d4/.claude/skills/rule-zzz-inj04-new/SKILL.md"
inj04_edit "$d4" cell_row_new "zzz-inj04-new.md" "$INJ04_AGENT"
inj04_edit "$d4" skills_add "$INJ04_AGENT" "rule-zzz-inj04-new"
assert_fixture_changed "$d4" "$b4" "БЛИЗНЕЦ: правило заведено во всех четырёх местах"
capture "$d4" "$CH04"
assert_code 0 "рост корпуса, доведённый до конца, — не находка"

echo "== ось K: манифест снят при живых правилах — НАХОДКА, а не VOID =="
# Антимаска: послабление не выдаётся удалением предмета.
d4="$(inj04_sandbox k_no_manifest)"
rm -f "$d4/.claude/rules/MANIFEST.md"
capture "$d4" "$CH04"
assert_code 1 "объявления привязки нет, а правила и агенты стоят ⇒ код 1"
assert_says "единственное объявление привязки снято" "  ...и названо, что снято именно объявление"

echo "== ось K′: таблица выпотрошена — НАХОДКА, а не успех =="
d4="$(inj04_sandbox k_gut_table)"
inj04_edit "$d4" table_gut
capture "$d4" "$CH04"
assert_code 1 "строк таблицы ноль ⇒ код 1: «каждое правило закреплено» истинно на пустом множестве"
assert_says "не разобрано НИ ОДНОЙ строки таблицы" "  ...и сказано, что обход беспредметен"

echo "== ось L: предмета нет — код 2, и это НЕ успех =="
d4="$(inj04_sandbox l_no_agents)"
rm -rf "$d4/.claude/agents"
capture "$d4" "$CH04"
assert_code 2 "исполнителей в дереве нет вовсе — закреплять не за кем"

d4="$(inj04_sandbox l_no_rules)"
rm -rf "$d4/.claude/rules"
capture "$d4" "$CH04"
assert_code 2 "корпуса в дереве нет вовсе — закреплять нечего"

if [ "$INJ04_ALONE" = 1 ]; then
    echo
    # Перепись объёма — отдельным утверждением: «утверждений 0, разошлось 0» иначе
    # печаталось бы успехом.
    echo "[CENSUS] инъекция $CH04: утверждений $((pass + fail)) — сошлось $pass, разошлось $fail"
    if [ "$((pass + fail))" -eq 0 ]; then
        echo "[VOID] инъекция $CH04 — не прогнано ни одного утверждения; это НЕ успех" >&2
        exit 2
    fi
    if [ "$fail" -ne 0 ]; then
        echo "[FAIL] инъекция $CH04 — разошлось $fail утверждений из $((pass + fail))" >&2
        exit 1
    fi
    echo "[PASS] инъекция $CH04 — каждая ось доказана парой: дефект краснеет, законный близнец молчит"
    exit 0
fi
