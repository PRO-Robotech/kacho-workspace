#!/usr/bin/env bash
# check-21 — РАБОТА НАД ОШИБКАМИ ПО КАЖДОЙ ПОЛОСЕ ПРОВЯЗАНА ОТ ВОЗВРАТА ДО ПАЧКИ (ws#1036).
#
# ОСНОВАНИЕ. Решение владельца 2026-10-12 дословно: «Запиши рул для мастер процесса
# что по результату каждой полосы нужно сделать работу над ошибками и обогатить рулы и
# скилы так что бы 1) потребление токенов было минимально 2) скорость разработки
# максимальна 3) качество кода и тестов аналогичное или выше».
#
# ОСИ (каждая — своя находка с координатой). Якоря — САМО требование, а не ключ
# (`testing.md#anchor-judges-substance-not-key`): тело, вывернутое при сохранённом id,
# ключ переживает. Текст читается без переносов строк (`flat`): перенос — не разрыв.
#   A. правило `ai-tooling.md` несёт `at-lane-retro` с требованием: место правки —
#      где предотвратить дешевле всего, три критерия владельца ДОСЛОВНО по порядку,
#      «2+ случая — механизм», признак нарушения; архив правила — цитату целиком;
#   B. протокол `CLAUDE.md` несёт поле «урок» ВНУТРИ блока контракта ВОЗВРАТ (между
#      `### ВОЗВРАТ` и концом блока кода) и ссылку на норму;
#   C. база диспетчера — норму §4: пачка уроков раз за волну одной полосой
#      `tooling-maintainer`, отбор, «механизм, не фраза», признак нарушения;
#   D. `tooling-maintainer` — режим «пачка уроков» с отбором и механизмом;
#   E. шаблон `wave.js` — один файл уроков волны, поле `lesson` обязательно в схеме
#      исполнителя, итог несёт уроки (поведение доказывает `wave-template-inject.sh`);
#   F. засев первой пачки держится: форма отсоединённого запуска без `setsid nohup`
#      (протокол, шаблон, подсказка `no-wait-guard`) и тема вливания
#      `#<N> merge #<PR>: …` у `git-operator` (ws#1029) — прежней формы нет;
#   G. пачка 2026-10-16 (ws#1110) держится словами нормы там, где её читают: протокол —
#      уникальные .rc, пауза лишь у `ci-watcher`, долгое ожидание ОДИН раз `--enqueue`,
#      отправка в файл, 141 после хука — снятый простоем ssh (keepalive ставит слот); `ci-watcher` — `--enqueue`; база —
#      номер задачи числом в предусловиях, форма вливания `--merge --subject … --body ""
#      --match-head-commit`, пауза лишь у `ci-watcher`; шаблон — `--body ""`, `--enqueue`,
#      суд RATE-LIMIT (поведение — heavy-slot-inject, ci-read-inject, landing-precheck-inject,
#      lane-precheck-inject, wave-template-inject).
#
# ПРЕДПОСЫЛКА (VOID, код 2): все девять носителей есть в дереве.
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
BASE = '.claude/agents/dispatcher.md'
TM = '.claude/agents/tooling-maintainer.md'
GO = '.claude/agents/git-operator.md'
WAVE = '.claude/workflows/wave.js'
GUARD = '.claude/hooks/no-wait-guard/guard.py'
CIW = '.claude/agents/ci-watcher.md'
QUOTE = ('Запиши рул для мастер процесса что по результату каждой полосы нужно сделать работу '
         'над ошибками и обогатить рулы и скилы так что бы 1) потребление токенов было минимально '
         '2) скорость разработки максимальна 3) качество кода и тестов аналогичное или выше')


def void(msg):
    print('[VOID] %s — %s' % (name, msg), file=sys.stderr)
    sys.exit(2)


def raw(p):
    return open(os.path.join(root, p), encoding='utf-8').read()


def flat(t):
    # мягкий перенос строки внутри абзаца — не разрыв нормы
    return re.sub(r'\s+', ' ', t)


texts = {}
for p in (RULE, ARCH, PROTO, BASE, TM, GO, WAVE, GUARD, CIW):
    try:
        texts[p] = raw(p)
    except OSError:
        void('носителя %s нет: судить нечего' % p)
finds = []


def need(p, frags, what):
    t = flat(texts[p])
    for f in frags:
        if f not in t:
            finds.append('%s: %s — не найдено «%s»' % (p, what, f))


# A. правило: требование при ключе, три критерия дословно и ПО ПОРЯДКУ.
rule = flat(texts[RULE])
# Норма — от ключа до начала следующей строки-нормы, заголовка или пустой строки:
# перенос внутри неё нормы не рвёт.
rr = texts[RULE]
k = rr.find('\nat-lane-retro · ')
line = ''
if k >= 0:
    m = re.compile(r'\n(?:\n|#|[a-z][a-z0-9-]* · )').search(rr, k + 1)
    line = rr[k + 1:m.start() if m else len(rr)]
if not line:
    finds.append('%s: нормы at-lane-retro нет' % RULE)
else:
    L = flat(line)
    for f in ('по возврату каждой полосы — работа над ошибками',
              'урок правь там, где его предотвратить дешевле всего',
              'урок без места — не урок',
              '2+ случая — механизм, не фраза',
              'проверки не сняты и не ослаблены',
              'red: тот же класс ошибки третий раз'):
        if f not in L:
            finds.append('%s: at-lane-retro без требования — не найдено «%s»' % (RULE, f))
    crit = ['«потребление токенов было минимально»', '«скорость разработки максимальна»',
            '«качество кода и тестов аналогичное или выше»']
    pos = [L.find(c) for c in crit]
    if any(x < 0 for x in pos):
        finds.append('%s: at-lane-retro — нет критерия владельца дословно: %s'
                     % (RULE, ', '.join(c for c, x in zip(crit, pos) if x < 0)))
    elif pos != sorted(pos):
        finds.append('%s: at-lane-retro — критерии владельца не в его порядке (токены, скорость, качество)' % RULE)
if QUOTE not in flat(texts[ARCH]):
    finds.append('%s: нет цитаты владельца 2026-10-12 целиком' % ARCH)

# B. протокол: поле «урок» ВНУТРИ блока контракта.
pt = texts[PROTO]
i = pt.find('### ВОЗВРАТ')
j = pt.find('```', i) if i >= 0 else -1
block = pt[i:j] if i >= 0 and j > i else ''
if not block:
    finds.append('%s: блок контракта ВОЗВРАТ не найден' % PROTO)
elif '- урок: <класс> · <где предотвратить> | —' not in block:
    finds.append('%s: поля «урок» нет в блоке контракта ВОЗВРАТ' % PROTO)
need(PROTO, ['«урок» — `ai-tooling.md#at-lane-retro`'], 'ссылка поля на норму')

# C. база диспетчера.
need(BASE, ['Работа над ошибками по каждой полосе',
            'поле «урок» и `lessons.md` волны — `tooling-maintainer` одной полосой за волну',
            'Правка — где урок дешевле предотвратить: меньше токенов, выше скорость, проверки не ослаблены',
            '2+ случая — механизм, не фраза',
            'Нарушение: тот же класс ошибки третий раз',
            'Когда: пачка уроков волны (§4)'], 'норма §4')

# D. исполнитель пачки.
need(TM, ['Пачка уроков волны (`ai-tooling.md#at-lane-retro`)',
          'По каждому классу — одна правка там, где урок предотвратить дешевле всего',
          'класс с 2+ случаями',
          'механизм: хук, скрипт, шаблон, страж, а не фраза',
          'проверки не сняты и не ослаблены'], 'режим «пачка уроков»')

# E. шаблон волны: провязка (поведение — wave-template-inject.sh).
need(WAVE, ["const LESSONS = R + '/lessons.md'",
            "'report', 'lesson'] }",
            "lessons: lessonsOf() }"], 'сбор уроков')

# F. засев первой пачки.
for p in (PROTO, WAVE):
    if 'setsid nohup' in texts[p]:
        finds.append('%s: снова предписан «setsid nohup» (глушит SIGHUP детям, пробы краснеют)' % p)
    if 'setsid env --default-signal=PIPE' not in texts[p]:
        finds.append('%s: нет формы «setsid env --default-signal=PIPE»' % p)
if 'setsid nohup <команда>' in texts[GUARD]:
    finds.append('%s: подсказка отказа предписывает «setsid nohup»' % GUARD)
need(GO, ['--subject "#<N> merge #<PR>: <суть>"'], 'тема вливания по форме правила ветки (ws#1029)')
if '--subject "#<N> <суть>"' in texts[GO]:
    finds.append('%s: прежняя тема вливания «--subject "#<N> <суть>"» (без merge #<M>)' % GO)

# G. пачка 2026-10-16 (ws#1110).
need(PROTO, ['имя журнала и `.rc` уникально', '`.rc` снят до старта',
             'ждёт и читает с паузой лишь `ci-watcher`',
             'дольше 300 с — ОДИН раз `heavy-slot.sh --enqueue <каталог>`; повтор — `--resume <билет>`',
             '`git push origin HEAD:refs/heads/<ветка> > <журнал> 2>&1` (141 после хука — снятый простоем ssh, слот ставит ему keepalive)'],
     'пачка 2026-10-16')
need(CIW, ['долгое ставится в очередь ОДИН раз (`heavy-slot.sh --enqueue <каталог>`',
           'повтор 74/75 — `--resume <билет>`'], 'пачка 2026-10-16 и ws#1115')
need(BASE, ['задача — `task <репо>#<N>`, N `^[0-9]+$`',
            '`gh pr merge <PR> --merge --subject "#<N> merge #<PR>: …" --body "" --match-head-commit <sha>`',
            'ждёт и дочитывает с паузой лишь `ci-watcher`',
            'долгий прогон — ОДИН раз `heavy-slot.sh --enqueue`, перезапуск на 74/75 — нарушение'], 'пачка 2026-10-16')
need(WAVE, ['--subject "\' + mergeTitle + \'"\'', 'heavy-slot.sh --enqueue', 'if (rateOf(ci)) return'],
     'пачка 2026-10-16')

print('[CENSUS] %s: носителей осмотрено %d (правило, архив, протокол, база, три агента, шаблон, хук); находок %d'
      % (name, len(texts), len(finds)))
for f in finds:
    print('[FAIL] %s — %s' % (name, f), file=sys.stderr)
if finds:
    sys.exit(1)
print('[PASS] %s — работа над ошибками провязана: норма с тремя критериями владельца, поле «урок» в контракте, '
      'пачка за волну в базе и у tooling-maintainer, сбор в wave.js; засев держится' % name)
PY
