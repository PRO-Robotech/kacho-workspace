#!/usr/bin/env bash
# ДОКАЗАТЕЛЬСТВО check-05 «база маршрутизации знает каждого исполнителя».
#
# ЧТО ЗДЕСЬ ДОКАЗЫВАЕТСЯ. По КАЖДОЙ оси проверки — пара: НАСТОЯЩИЙ дефект, на
# котором гейт обязан покраснеть и назвать координату, и рядом ЗАКОННЫЙ БЛИЗНЕЦ той
# же формы, на котором обязан смолчать. Гейт, красный на всём, снимают вместе с
# настоящими находками; гейт, зелёный на всём, не доказывает ничего
# (`.claude/rules/testing.md` §«Гейт на класс»).
#
# ГДЕ У ЭТОЙ ПРОВЕРКИ ЛОЖНЫЕ СРАБАТЫ ЖИВУТ ГУЩЕ ВСЕГО — в ТЕКСТЕ. Право запуска,
# запреты исполнителя и ссылка на источник пишутся словами, и всякая редактура
# меняет буквы, не меняя предмета: переставленный перечень, заголовок другого
# уровня, сокращённая цитата. На каждую из этих правок здесь стоит близнец, и
# каждый из них — не украшение: гейт, сверяющий текст вместо множества, покраснел
# бы на всех трёх в первую же неделю.
#
# САМАЯ ТОНКАЯ ПАРА — ОСЬ F/F′: цитата, ЗАКОННО сокращающая заголовок, обязана
# резолвиться (иначе базу нельзя писать по-человечески), а цитата, назвавшая
# ПРЕЖНЕЕ имя раздела, — нет (иначе ось не ловит переименований, ради которых
# заведена). Обе пробы строятся из ЖИВОГО заголовка дерева, а не из выписанного
# текста: выписанный отстанет от правила молча.
#
# ПЕСОЧНИЦА СВОЯ: предмет — `dispatcher.md`, дерево `.claude/agents/` и файлы
# корпуса, на которые база ссылается, поэтому копируются `CLAUDE.md`,
# `.claude/rules`, `.claude/agents`, `.claude/skills` и `.claude/settings.json`.
# Правки идут ТОЛЬКО в `mktemp -d`; рабочее дерево не трогается ни в одном режиме.
#
# ФАЙЛ ИСПОЛНЯЕТСЯ ДВУМЯ СПОСОБАМИ, и оба законны:
#   · `bash scripts/rules-gate/inject-05-dispatcher-routes-every-agent.sh` — сам по
#     себе, со своей оснасткой и своим вердиктом в коде выхода;
#   · подключением (`.`) из `inject.sh` — тогда берутся ЕГО `capture`/`assert_*`,
#     и удавшиеся утверждения попадают в его перепись доказанности проверок.
#
# Коды выхода (самостоятельный режим): 0 — все утверждения сошлись; 1 — хоть одно
# разошлось; 2 — не прогнано ни одного (это НЕ успех).

set -uo pipefail

CH05=check-05-dispatcher-routes-every-agent.sh

if [ "${BASH_SOURCE[0]}" = "$0" ]; then INJ05_ALONE=1; else INJ05_ALONE=0; fi

if [ "$INJ05_ALONE" = 1 ]; then
    HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    GATE="$HERE"
    WS="$(cd "$HERE/../.." && pwd)"
    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    pass=0; fail=0; OUT=""; RC=0

    # `LAST_CHECK` здесь НЕ заводится намеренно, и это не пропуск: перепись
    # доказанности ПО ПРОВЕРКАМ (какой из проверок набора досталась находка, какой
    # близнец) живёт в inject.sh и имеет смысл только там, где проверок много.
    # Самостоятельный режим гоняет ровно одну — $CH05, — и её имя уже напечатано в
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
    for _inj05_fn in capture assert_code assert_says assert_fixture_changed sandbox_digest; do
        command -v "$_inj05_fn" >/dev/null 2>&1 && continue
        echo "[VOID] $(basename "${BASH_SOURCE[0]}") — оснастки inject.sh нет: функция" \
             "«$_inj05_fn» не определена; часть подключена не оттуда, доказывать нечем" >&2
        exit 2
    done
    unset -v _inj05_fn
    if [ -z "${WS:-}" ] || [ ! -d "$WS" ] || [ -z "${TMP:-}" ] || [ ! -d "$TMP" ]; then
        echo "[VOID] $(basename "${BASH_SOURCE[0]}") — \$WS или \$TMP inject.sh не определены;" \
             "жертву выводить не из чего, писать некуда" >&2
        exit 2
    fi
    GATE="${GATE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
fi

inj05_sandbox() {   # <имя>
    local dir="$TMP/s05.$1"
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
# Нужны: исполнитель, чьё имя встречается РОВНО В ОДНОМ заголовке базы (иначе
# снятие его подраздела было бы прикрыто чужим), и живая ссылка на источник, чей
# заголовок НУМЕРОВАН, — из неё строятся обе законные формы цитаты (сокращение по
# префиксу и чистый номер) и обе незаконные.
inj05_facts="$(python3 - "$WS" <<'PY'
import io, os, re, sys
ws = sys.argv[1]
disp = os.path.join(ws, '.claude', 'agents', 'dispatcher.md')
text = io.open(disp, encoding='utf-8').read()
m = re.match(r'\A---\r?\n(.*?)\r?\n---\r?\n', text, re.S)
fm, body = (m.group(1), text[m.end():]) if m else ('', text)

FENCE = re.compile(r'^\s*(?:```|~~~)')
HEAD = re.compile(r'^#{1,6}\s+(.*?)\s*$')


def headings(t):
    out, fence = [], False
    for line in t.split('\n'):
        if FENCE.match(line):
            fence = not fence
            continue
        if fence:
            continue
        h = HEAD.match(line)
        if h:
            out.append(h.group(1))
    return out


heads = headings(body)
allow = re.search(r'Agent\s*\(([^)]*)\)', re.search(r'^tools:.*$', fm, re.M).group(0))
allow = [x.strip() for x in allow.group(1).split(',') if x.strip()]
execs = sorted(f[:-3] for f in os.listdir(os.path.join(ws, '.claude', 'agents'))
               if f.endswith('.md') and f != 'dispatcher.md')

victim = None
for a in execs:
    if a not in allow:
        continue
    word = re.compile(r'(?<![A-Za-z0-9_-])%s(?![A-Za-z0-9_-])' % re.escape(a))
    if sum(1 for h in heads if word.search(h)) == 1:
        victim = a
        break

NUM = re.compile(r'^\s*([0-9]+[A-Za-zА-Яа-яЁё]?)[.)]?\s*')
REF = re.compile(r'`([^`\n]+\.md)`\s*§«([^»]*)»')
ref = None
for mm in REF.finditer(body):
    name, quote = mm.group(1), re.sub(r'\s+', ' ', mm.group(2)).strip()
    path = None
    for cand in (os.path.join(ws, '.claude', 'rules', name), os.path.join(ws, name)):
        if os.path.isfile(cand):
            path = cand
            break
    if path is None:
        continue
    src = io.open(path, encoding='utf-8').read()
    for h in headings(src):
        hf = re.sub(r'\s+', ' ', h).strip()
        hn = NUM.match(hf)
        if not hn:
            continue
        rest = NUM.sub('', hf).strip()
        qrest = NUM.sub('', quote).strip()
        if not (hf == quote or hf.startswith(quote) or rest == qrest or rest.startswith(qrest)):
            continue
        words = rest.split(' ')
        if len(words) < 3:
            continue
        ref = (name, quote, hn.group(1), ' '.join(words[:2]))
        break
    if ref:
        break

if not victim or not ref:
    raise SystemExit('')
print('\t'.join((victim,) + ref))
PY
)"
if [ -z "$inj05_facts" ]; then
    echo "[VOID] inject-05 — в базе не нашлось ни исполнителя с единственным заголовком," \
         "ни живой ссылки на нумерованный раздел; доказывать не на чем" >&2
    exit 2
fi
IFS=$'\t' read -r INJ05_AGENT INJ05_REFFILE INJ05_QUOTE INJ05_NUM INJ05_PREFIX <<<"$inj05_facts"
echo "-- жертвы выведены из дерева: исполнитель «$INJ05_AGENT»; ссылка \`$INJ05_REFFILE\`" \
     "§«$INJ05_QUOTE» (номер раздела «$INJ05_NUM», законное сокращение «$INJ05_PREFIX») --"

# ── ПРАВКИ ПЕСОЧНИЦЫ ────────────────────────────────────────────────────────
inj05_edit() {   # <каталог> <операция> [аргументы…]
    python3 - "$@" <<'PY'
import io, os, re, sys
d, op = sys.argv[1], sys.argv[2]
args = sys.argv[3:]
agents = os.path.join(d, '.claude', 'agents')
disp = os.path.join(agents, 'dispatcher.md')


def edit(path, fn):
    before = io.open(path, encoding='utf-8').read()
    after = fn(before)
    if after == before:
        raise SystemExit('ФИКСТУРА ВАКУУМНА: операция «%s» не изменила %s; утверждение о '
                         'вердикте гейта относилось бы к нетронутому дереву' % (op, path))
    io.open(path, 'w', encoding='utf-8').write(after)


def tools_line(text, fn):
    m = re.search(r'^tools:[ \t]*(.*)$', text, re.M)
    if not m:
        raise SystemExit('ФИКСТУРА ВАКУУМНА: у базы нет ключа tools:')
    return text[:m.start(1)] + fn(m.group(1)) + text[m.end(1):]


def allowlist(text, fn):
    def apply(line):
        a = re.search(r'Agent\s*\(([^)]*)\)', line)
        if not a:
            raise SystemExit('ФИКСТУРА ВАКУУМНА: в tools: базы нет Agent(...)')
        names = [x.strip() for x in a.group(1).split(',') if x.strip()]
        return line[:a.start(1)] + ', '.join(fn(names)) + line[a.end(1):]
    return tools_line(text, apply)


if op == 'allow_drop':
    edit(disp, lambda t: allowlist(t, lambda ns: [n for n in ns if n != args[0]]))
elif op == 'allow_add':
    edit(disp, lambda t: allowlist(t, lambda ns: ns + [args[0]]))
elif op == 'allow_reverse':
    edit(disp, lambda t: allowlist(t, lambda ns: list(reversed(ns))))
elif op == 'tools_add':
    edit(disp, lambda t: tools_line(t, lambda line: line.rstrip() + ', ' + args[0]))
elif op == 'head_rename':            # снять имя агента из его заголовка
    def rename(t):
        pat = re.compile(r'^(#{1,6})[ \t]+(.*(?<![A-Za-z0-9_-])%s(?![A-Za-z0-9_-]).*)$'
                         % re.escape(args[0]), re.M)
        return pat.sub(r'\1 полоса без имени', t, count=1)
    edit(disp, rename)
elif op == 'head_decorate':          # другой уровень и слова вокруг имени
    def dec(t):
        pat = re.compile(r'^(#{1,6})[ \t]+(.*(?<![A-Za-z0-9_-])%s(?![A-Za-z0-9_-]).*)$'
                         % re.escape(args[0]), re.M)
        return pat.sub(lambda m: '#' + m.group(1) + ' Когда звать `%s` — полоса %s'
                       % (args[0], args[0]), t, count=1)
    edit(disp, dec)
elif op == 'dis_drop_agent':         # исполнителю больше не запрещён Agent
    def drop(t):
        m = re.search(r'^disallowedTools:[ \t]*(.*)$', t, re.M)
        if not m:
            raise SystemExit('ФИКСТУРА ВАКУУМНА: у исполнителя нет disallowedTools')
        items = [x.strip() for x in m.group(1).split(',') if x.strip() and x.strip() != 'Agent']
        return t[:m.start(1)] + (', '.join(items) if items else 'NotebookEdit') + t[m.end(1):]
    edit(os.path.join(agents, args[0] + '.md'), drop)
elif op == 'dis_reorder':            # тот же набор запретов, обратный порядок
    def rev(t):
        m = re.search(r'^disallowedTools:[ \t]*(.*)$', t, re.M)
        if not m:
            raise SystemExit('ФИКСТУРА ВАКУУМНА: у исполнителя нет disallowedTools')
        items = [x.strip() for x in m.group(1).split(',') if x.strip()]
        if len(items) < 2:
            items = items + ['WebSearch']
        return t[:m.start(1)] + ', '.join(reversed(items)) + t[m.end(1):]
    edit(os.path.join(agents, args[0] + '.md'), rev)
elif op == 'ref_file':               # ссылка на файл, которого нет
    edit(disp, lambda t: t.replace('`%s` §«%s»' % (args[0], args[1]),
                                   '`%s` §«%s»' % (args[2], args[1]), 1))
elif op == 'ref_quote':              # та же ссылка, другая цитата
    edit(disp, lambda t: t.replace('`%s` §«%s»' % (args[0], args[1]),
                                   '`%s` §«%s»' % (args[0], args[2]), 1))
elif op == 'new_agent':              # законно заведённый исполнитель
    name = args[0]
    io.open(os.path.join(agents, name + '.md'), 'w', encoding='utf-8').write(
        '---\nname: %s\ndescription: "Проба инъекции."\ndisallowedTools: Agent\n'
        'skills:\n  - rule-00-kacho-core\n---\n\n# Проба\n' % name)
    edit(disp, lambda t: allowlist(t, lambda ns: ns + [name]))
    edit(disp, lambda t: t.rstrip('\n') + '\n\n### %s\nКогда: никогда, это проба.\n' % name)
else:
    raise SystemExit('unknown op ' + op)
PY
}

echo "== контроль: нетронутая копия — check-05 молчит =="
d5="$(inj05_sandbox control)"
capture "$d5" "$CH05"
assert_code 0 "нетронутая копия · $CH05"

echo "== ось A: агент есть, права запуска нет (ALLOWLIST-DRIFT) =="
d5="$(inj05_sandbox a_allow_drop)"
inj05_edit "$d5" allow_drop "$INJ05_AGENT"
capture "$d5" "$CH05"
assert_code 1 "имя убрано из Agent(…) — запустить исполнителя нельзя"
assert_says "ALLOWLIST-DRIFT" "  ...находка названа осью"
assert_says "$INJ05_AGENT" "  ...и назван ИМЕННО этот исполнитель"

echo "== ось A2: право на имя, которого нет (та же ось, другая сторона) =="
d5="$(inj05_sandbox a_allow_ghost)"
inj05_edit "$d5" allow_add "zzz-inj05-призрак"
capture "$d5" "$CH05"
assert_code 1 "в Agent(…) имя без файла агента"
assert_says "zzz-inj05-призрак" "  ...и названо ИМЕННО это имя"

echo "== ось A′: БЛИЗНЕЦ — тот же перечень, обратный порядок =="
# Сверяется МНОЖЕСТВО. Гейт, сверяющий текст перечня, покраснел бы на сортировке —
# правке, которую делает всякий, кто наводит порядок в frontmatter.
d5="$(inj05_sandbox a_allow_reverse)"; b5="$(sandbox_digest "$d5")"
inj05_edit "$d5" allow_reverse
assert_fixture_changed "$d5" "$b5" "БЛИЗНЕЦ: порядок имён в Agent(…) перевёрнут"
capture "$d5" "$CH05"
assert_code 0 "перестановка имён множества не меняет — гейт молчит"

# Одинарные кавычки: `″` — ДВОЙНОЙ ШТРИХ в имени оси (A, A′, A″), а не кавычка, и
# подставлять в этой строке нечего. В двойных shellcheck принимает его за кривую
# типографскую кавычку (SC1111) — заголовок оси от этого читается как опечатка.
echo '== ось A″: БЛИЗНЕЦ — новый исполнитель, заведённый по ВСЕМ местам =='
# Самый ценный близнец: гейт не запрещает заводить агентов. Он требует одного —
# чтобы файл, право запуска и повод звать появлялись ВМЕСТЕ.
d5="$(inj05_sandbox a_new_agent)"; b5="$(sandbox_digest "$d5")"
inj05_edit "$d5" new_agent "zzz-inj05-новичок"
assert_fixture_changed "$d5" "$b5" "БЛИЗНЕЦ: агент, allowlist и подраздел заведены разом"
capture "$d5" "$CH05"
assert_code 0 "исполнитель, объявленный целиком, — не находка"

echo "== ось B: право есть, повода нет (AGENT-NOT-IN-BASE) =="
d5="$(inj05_sandbox b_no_section)"
inj05_edit "$d5" head_rename "$INJ05_AGENT"
capture "$d5" "$CH05"
assert_code 1 "подраздела про исполнителя в базе нет — позван он не будет никогда"
assert_says "AGENT-NOT-IN-BASE" "  ...находка названа осью"
assert_says "$INJ05_AGENT" "  ...и назван ИМЕННО этот исполнитель"

echo "== ось B′: БЛИЗНЕЦ — другой уровень заголовка и слова вокруг имени =="
# Ищется ИМЯ в заголовке, а не его точная форма: база вправе звать подраздел
# «Когда звать `scout`», и гейт, сверяющий строку целиком, покраснел бы на редактуре.
d5="$(inj05_sandbox b_head_decorated)"; b5="$(sandbox_digest "$d5")"
inj05_edit "$d5" head_decorate "$INJ05_AGENT"
assert_fixture_changed "$d5" "$b5" "БЛИЗНЕЦ: заголовок переписан, имя на месте"
capture "$d5" "$CH05"
assert_code 0 "форма заголовка предметом не является — гейт молчит"

echo "== ось C: исполнитель, запускающий исполнителей (AGENT-CAN-SPAWN) =="
d5="$(inj05_sandbox c_can_spawn)"
inj05_edit "$d5" dis_drop_agent "$INJ05_AGENT"
capture "$d5" "$CH05"
assert_code 1 "«Agent» пропал из disallowedTools — вложенные запуски мимо диспетчера"
assert_says "AGENT-CAN-SPAWN" "  ...находка названа осью"

echo "== ось C′: БЛИЗНЕЦ — тот же набор запретов, обратный порядок =="
d5="$(inj05_sandbox c_dis_reorder)"; b5="$(sandbox_digest "$d5")"
inj05_edit "$d5" dis_reorder "$INJ05_AGENT"
assert_fixture_changed "$d5" "$b5" "БЛИЗНЕЦ: порядок disallowedTools перевёрнут"
capture "$d5" "$CH05"
assert_code 0 "порядок запретов множества не меняет — гейт молчит"

echo "== ось D: у базы появился инструмент исполнения (DISPATCHER-HAS-TOOLS) =="
d5="$(inj05_sandbox d_disp_read)"
inj05_edit "$d5" tools_add "Read"
capture "$d5" "$CH05"
assert_code 1 "диспетчер, умеющий прочитать сам, перестаёт раздавать"
assert_says "DISPATCHER-HAS-TOOLS" "  ...находка названа осью"
assert_says "Read" "  ...и назван ИМЕННО этот инструмент"

echo "== ось D′: БЛИЗНЕЦ — инструмент НЕ из перечня запрещённых =="
# Перечень назван в шапке проверки поимённо. Ось про инструменты чтения, записи и
# исполнения, а не про «всякий новый ключ»: база вправе получить средство учёта.
d5="$(inj05_sandbox d_disp_neutral)"; b5="$(sandbox_digest "$d5")"
inj05_edit "$d5" tools_add "TodoWrite"
assert_fixture_changed "$d5" "$b5" "БЛИЗНЕЦ: базе добавлен инструмент учёта"
capture "$d5" "$CH05"
assert_code 0 "инструмент вне названного перечня — не находка"

echo "== ось E: ссылка на несуществующий файл (BAD-SOURCE-REF) =="
d5="$(inj05_sandbox e_ref_nofile)"
inj05_edit "$d5" ref_file "$INJ05_REFFILE" "$INJ05_QUOTE" "zzz-inj05-нет-файла.md"
capture "$d5" "$CH05"
assert_code 1 "обоснование ведёт в файл, которого нет"
assert_says "BAD-SOURCE-REF" "  ...находка названа осью"
assert_says "такого файла нет" "  ...и названа ИМЕННО эта причина"

echo "== ось F: раздел переименован, цитата осталась прежней =="
# Тот самый класс, ради которого ось заведена: правило цело, дифф базы пуст, а
# читатель базы приходит в никуда.
d5="$(inj05_sandbox f_ref_stale)"
inj05_edit "$d5" ref_quote "$INJ05_REFFILE" "$INJ05_QUOTE" "Раздел, которого в правиле нет"
capture "$d5" "$CH05"
assert_code 1 "цитата не совпадает ни с одним заголовком файла"
assert_says "заголовка с такой цитатой в нём нет" "  ...и названа ИМЕННО эта причина"

echo "== ось F′: БЛИЗНЕЦ — цитата ЗАКОННО сокращает заголовок =="
# В дереве так пишут повсеместно: «## 2. Вердикт привязан к ОТПЕЧАТКУ» цитируется
# первой половиной. Покрасней гейт здесь — базу пришлось бы писать побайтовыми
# заголовками, и ось сняли бы целиком.
d5="$(inj05_sandbox f_ref_prefix)"; b5="$(sandbox_digest "$d5")"
inj05_edit "$d5" ref_quote "$INJ05_REFFILE" "$INJ05_QUOTE" "$INJ05_PREFIX"
assert_fixture_changed "$d5" "$b5" "БЛИЗНЕЦ: цитата сокращена до префикса заголовка"
capture "$d5" "$CH05"
assert_code 0 "сокращение по префиксу — законная форма ссылки"

# Одинарные кавычки по тому же доводу, что у оси A″ выше: `″` — двойной штрих
# имени оси, подстановки в строке нет.
echo '== ось F″: БЛИЗНЕЦ — цитата свёрнута до ЧИСТОГО НОМЕРА раздела =='
d5="$(inj05_sandbox f_ref_number)"; b5="$(sandbox_digest "$d5")"
inj05_edit "$d5" ref_quote "$INJ05_REFFILE" "$INJ05_QUOTE" "$INJ05_NUM"
assert_fixture_changed "$d5" "$b5" "БЛИЗНЕЦ: цитата — номер нумерованного раздела"
capture "$d5" "$CH05"
assert_code 0 "номер раздела — самостоятельная законная ссылка"

echo "== ось G: база снята при живых исполнителях — НАХОДКА, а не VOID =="
# Антимаска: послабление не выдаётся удалением предмета, иначе снести базу было бы
# способом погасить гейт.
d5="$(inj05_sandbox g_no_base)"
rm -f "$d5/.claude/agents/dispatcher.md"
capture "$d5" "$CH05"
assert_code 1 "главный поток объявлен диспетчером, а базы нет ⇒ код 1"
assert_says "остаётся без маршрутизации" "  ...и названо, что снято именно это"

echo "== ось H: предмета нет — код 2, и это НЕ успех =="
d5="$(inj05_sandbox h_no_agents)"
rm -rf "$d5/.claude/agents"
capture "$d5" "$CH05"
assert_code 2 "исполнителей в дереве нет вовсе — маршрутизировать некого"

if [ "$INJ05_ALONE" = 1 ]; then
    echo
    echo "[CENSUS] инъекция $CH05: утверждений $((pass + fail)) — сошлось $pass, разошлось $fail"
    if [ "$((pass + fail))" -eq 0 ]; then
        echo "[VOID] инъекция $CH05 — не прогнано ни одного утверждения; это НЕ успех" >&2
        exit 2
    fi
    if [ "$fail" -ne 0 ]; then
        echo "[FAIL] инъекция $CH05 — разошлось $fail утверждений из $((pass + fail))" >&2
        exit 1
    fi
    echo "[PASS] инъекция $CH05 — каждая ось доказана парой: дефект краснеет, законный близнец молчит"
    exit 0
fi
