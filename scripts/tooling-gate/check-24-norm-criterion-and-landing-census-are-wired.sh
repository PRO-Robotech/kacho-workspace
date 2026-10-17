#!/usr/bin/env bash
# check-24 — КРИТЕРИЙ НОРМЫ И ПЕРЕПИСЬ ГЕЙТОВ ПОСАДКИ РАЗОМ ПРОВЯЗАНЫ (ws#1071): К и М1–М5.
#
# ОСНОВАНИЕ. Решение владельца 2026-10-14 дословно: «Запиши с правило с учетом что все
# правила пишутся так что бы выжить максимум скорости разработки, минимум затрат на
# токены , и максимальное качество кода или не хуже чем есть сейчас» (расхождение оценки
# и факта в 3 раза — архив правила).
#
# ОСИ (каждая — своя находка с координатой). Якоря — САМО требование, а не ключ
# (`testing.md#anchor-judges-substance-not-key`); текст читается без переносов (`flat`).
#   К.  `ai-tooling.md` несёт `at-norm-criterion` (оси скорости, токенов и качества, число, отказ, сжатие), архив —
#       цитату; `CLAUDE.md` — строку критерия; `tooling-maintainer` — входной фильтр;
#   М1. `at-red-ci-one-round` — все гейты посадки одним шагом, «по одной за круг —
#       нарушение»; база §6 «Посадка изменения» — «Перепись гейтов»; `wave.js` — шаг
#       переписи шести гейтов ДО старта демона вливания (позиция, не только присутствие; ws#1152),
#       итог несёт таблицу;
#   М2. `lane-precheck.sh --premise` — четыре предусловия словаря и PREMISE-FALSE; его
#       инъекция — раздел ws#1071; база §3 — предусловия до раздачи;
#   М3. `at-agent-does-not-wait` — ответ без «### ВОЗВРАТ» не подставляется; `wave.js` —
#       `textStep` у трёх текстовых шагов (прямого `agent` у них нет); проба шаблона —
#       раздел ws#1071 и его мутанты;
#   М4. `at-red-ci-one-round` — правки ветки эпика одной сборкой на круг;
#   М5. база §8 — оценка от переписи гейтов и замеров, без неё — «нижняя граница».
#
# ПРЕДПОСЫЛКА (VOID, код 2): все носители есть в дереве.
# Коды: 0 — находок нет; 1 — находка с координатой; 2 — предмета нет.
set -uo pipefail

name="$(basename "${BASH_SOURCE[0]}" .sh)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$here/_lib.sh"
root="$(tooling_gate_workspace_root)" || exit 2

python3 - "$root" "$name" <<'PY'
import os, re, sys
root, name = sys.argv[1], sys.argv[2]
RULE = '.claude/rules/ai-tooling.md'
ARCH = '.claude/backup/ai-tooling.md'
PROTO = 'CLAUDE.md'
TM = '.claude/agents/tooling-maintainer.md'
BASE = '.claude/agents/dispatcher.md'
WAVE = '.claude/workflows/wave.js'
PROBE = 'scripts/wave-template-inject.sh'
LP = 'scripts/lane-precheck.sh'
LPI = 'scripts/lane-precheck-inject.sh'
QUOTE = ('Запиши с правило с учетом что все правила пишутся так что бы выжить максимум скорости '
         'разработки, минимум затрат на токены , и максимальное качество кода или не хуже чем есть сейчас')


def void(msg):
    print('[VOID] %s — %s' % (name, msg), file=sys.stderr)
    sys.exit(2)


def flat(t):
    return re.sub(r'\s+', ' ', t)


texts = {}
for p in (RULE, ARCH, PROTO, TM, BASE, WAVE, PROBE, LP, LPI):
    try:
        texts[p] = open(os.path.join(root, p), encoding='utf-8').read()
    except OSError:
        void('носителя %s нет: судить нечего' % p)
finds = []


def need(where, text, frags, what):
    t = flat(text)
    for f in frags:
        if f not in t:
            finds.append('%s: %s — не найдено «%s»' % (where, what, f))


def norm(key):
    """Строка-норма от `<key> · ` до следующей единицы корпуса; перенос внутри не рвёт."""
    r = texts[RULE]
    k = r.find('\n%s · ' % key)
    if k < 0:
        return ''
    m = re.compile(r'\n(?:\n|#|[a-z][a-z0-9-]* · )').search(r, k + 1)
    return r[k + 1:m.start() if m else len(r)]


def unit(text, start, stop_re):
    k = text.find(start)
    if k < 0:
        return ''
    m = re.compile(stop_re).search(text, k + len(start))
    return text[k:m.start() if m else len(text)]


# К. критерий нормы.
line = norm('at-norm-criterion')
if not line:
    finds.append('%s: нормы at-norm-criterion нет' % RULE)
else:
    need(RULE, line, ['лишь если скорость разработки не ниже, токены не выше, качество кода не ниже текущего',
                      'по замеру до/после либо доводу с числом',
                      'качество ниже — отказ, ось хуже — лишь при выигрыше другой, названном числом',
                      'корпус на потолке — только со сжатием',
                      'tooling-gate check-24',
                      'red: норма без числа по осям; корпус вырос'],
         'at-norm-criterion без требования')
need(ARCH, texts[ARCH], [QUOTE, 'время не сходится в 3 раза?', '## 2026-10-14 (ws#1071)'],
     'архив: цитата владельца 2026-10-14')
need(PROTO, texts[PROTO], ['Норма и урок — при скорости не ниже, токенах не выше, качестве кода не ниже, с числом (`ai-tooling.md#at-norm-criterion`)'],
     'строка критерия в протоколе обоих концов')
need(TM, unit(texts[TM], '## Роль и границы', r'\n## '),
     ['**Входной фильтр правки правил** (`ai-tooling.md#at-norm-criterion`',
      'лишь если скорость разработки не ниже, токены не выше, качество кода не ниже текущего',
      'на потолке — только со сжатием, в возврате — строки и символы до/после'],
     'входной фильтр в шапке исполнителя')

# М1, М4. правило; М3. правило.
rc = norm('at-red-ci-one-round')
need(RULE, rc, ['до посадки эпика и первого круга схождения — все гейты посадки одним шагом (`wave.js` «Перепись гейтов»), по одной за круг — нарушение',
                'правки ветки эпика — одной сборкой на круг',
                'гейт посадки — вторым кругом'],
     'at-red-ci-one-round без переписи гейтов (М1) и одной сборки правок (М4)')
need(RULE, norm('at-agent-does-not-wait'),
     ['ответ без «### ВОЗВРАТ» — «не-выполнилось»: `wave.js` не подставляет его и повторяет шаг: дочитать `.rc`',
      'ждёт лишь `ci-watcher`', 'tooling-gate check-24', '«жду монитора» в следующем задании'],
     'at-agent-does-not-wait без нормы ответа без ВОЗВРАТ (М3)')

# База диспетчера: §3 (М2), §6 (М1), §8 (М5).
b = texts[BASE]
need(BASE, unit(b, '\n## 3. Задание агенту', r'\n## '),
     ['Предусловия (PR MERGED/OPEN, ветка на origin, DoD-proof, вердикт роли) — `lane-precheck.sh --premise` до раздачи, код не 0 — не раздаётся'],
     '§3: предусловия скриптом до раздачи (М2)')
need(BASE, unit(b, '\n| Посадка изменения | ', r'\n'),
     ['`wave.js` «Перепись гейтов»: все разом до первой починки и схождения (`ai-tooling.md#at-red-ci-one-round`)'],
     '§6 «Посадка изменения»: перепись гейтов (М1)')
need(BASE, unit(b, '\n## 8. Волна, общее дерево, лимиты', r'\n## '),
     ['Оценка — от переписи гейтов (§6) и замеренных длительностей CI и newman с коэффициентом расхождения прошлых оценок (`metrics.json`); без переписи — «нижняя граница»'],
     '§8: оценка срока (М5)')

# Шаблон волны: М1 — шаг и позиция; М3 — textStep у трёх текстовых шагов.
w = texts[WAVE]
need(WAVE, w, ["const GATES = ['landing-precheck.sh (рецепт «ЗАПУСК»)', 'merge-readiness.sh', 'ci-read.sh (рецепт «ЗАПУСК», без ожидания)', 'пробное схождение и applicability.py обоих пакетов', 'cascade-census.sh --proof по каждой задаче', 'branch-audit.sh']",
               'ДО первой починки прогони КАЖДЫЙ гейт по разу, ничего не чини',
               "label: 'mech:gates'",
               'const gatesOf = () => ({ gates: { file: GATES_FILE,',
               "reasons: alStatus ? alStatus.reasons || [] : [], ...gatesOf(), remainder",
               "const RET_MARK = '### ВОЗВРАТ'",
               'const hasRet = t => typeof t === \'string\' && t.includes(RET_MARK)',
               'дочитай .rc и журнал своего прогона и верни блок ВОЗВРАТ с фактом',
               'return hasRet(b) ? b : null',
               "if (!a1) return noRet(out, l, 'acceptance-' + r)",
               "if (!s1) return noRet(out, l, 'client-sim')",
               "if (!c1) return noRet(out, l, 'surface-census')"],
     'провязка переписи гейтов и ответа без ВОЗВРАТ')
ig, il = w.find('const gates = await agent('), w.find('const alStart = await agent(')
if not (0 <= ig < il):
    finds.append('%s: перепись гейтов не стоит в теле ДО старта демона вливания' % WAVE)
for step in ('Приёмка полосы', 'Имитация клиента ДО кода', 'Перепись поверхности ДО кода'):
    if "await agent(C + '\\n\\n%s" % step in w:
        finds.append('%s: текстовый шаг «%s» зовётся agent напрямую — ответ без ВОЗВРАТ уйдёт дальше' % (WAVE, step))
need(PROBE, texts[PROBE], ["console.log('== перепись гейтов посадки разом; ответ без ВОЗВРАТ — не-выполнилось (ws#1071)')",
                           'mutant "перепись гейтов не зовётся (ws#1071)"',
                           'mutant "перепись гейтов чинит по одному (ws#1071)"',
                           'mutant "ответ без ВОЗВРАТ принят (ws#1071)"',
                           'mutant "не-выполнилось подставлено дальше (ws#1071)"'],
     'поведение доказывается исполнением шаблона')

# М2. предпроверка предусловий и её инъекция.
need(LP, texts[LP], ['lane-precheck.sh --premise <файл предусловий>',
                     'pr <владелец/репо>#<N> <MERGED|OPEN|CLOSED>', 'branch <владелец/репо> <ветка>',
                     'proof <владелец/репо>#<N>', 'verdict <файл записи роли> <accept|return>',
                     'reasons+=("PREMISE-FALSE $line: состояние $got")',
                     '[ "${#voids[@]}" -eq 0 ] && [ "$n" -gt 0 ] || exit 2'],
     'режим предусловий')
need(LPI, texts[LPI], ['echo "== предусловия задания до раздачи (ws#1071)"',
                       '"PR открыт, задание считает влитым → PREMISE-FALSE"',
                       '"роль вернула, задание считает принятым → PREMISE-FALSE"',
                       '"ноль предусловий — не «все верны» → код 2"'],
     'режим предусловий доказан инъекцией')

print('[CENSUS] %s: носителей осмотрено %d (правило, архив, протокол, tooling-maintainer, база, шаблон, проба шаблона, предпроверка, её инъекция); находок %d'
      % (name, len(texts), len(finds)))
for f in finds:
    print('[FAIL] %s — %s' % (name, f), file=sys.stderr)
if finds:
    sys.exit(1)
print('[PASS] %s — критерий нормы и пять механик провязаны: at-norm-criterion в правиле, протоколе и фильтре исполнителя; '
      'перепись гейтов до первой починки; предусловия скриптом; ответ без ВОЗВРАТ не подставляется; оценка от переписи' % name)
PY
