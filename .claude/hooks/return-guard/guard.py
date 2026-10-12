#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""return-guard — исполнитель не завершает ход без блока «### ВОЗВРАТ» (ws#1030).

ПРИЗНАК. За сессию 2026-10-12 четыре исполнителя закончили ход ожиданием события
Monitor («Waiting for events.», «I'll wait for the monitor notification.», «Waiting
for the Monitor event…»). Диспетчер получил этот текст как итог полосы: работа не
сдана, состояние неизвестно, полоса стоит (kaname#468: прогон кончился красным, а
полоса час «ждала»). Страж no-wait-guard этого не видит: он судит команды Bash, а
ожидание события — не команда. Решение владельца 2026-10-11 дословно: «И реши
проблему раз и навсегда что таски уходят в часовые таймауты и ничего не делают а
мы ждем».

СОБЫТИЕ. SubagentStop: харнесс зовёт его, когда сабагент заканчивает ход, и
отклонение (`{"decision":"block","reason":…}`) возвращает ему ход с текстом reason.
Измерено опытом 2026-10-12 на Claude Code 2.1.295 (`claude -p --settings`, свой
агент с `disallowedTools: Agent`): событие пришло с полями agent_type,
last_assistant_message, stop_hook_active; отклонение вернуло ход, агент дописал
блок, второй вызов пришёл с stop_hook_active=true и блоком в сообщении.

ЧТО СУДИТСЯ. Агент, у которого есть определение `.claude/agents/<agent_type>.md`
в корне проекта, кроме `dispatcher` (главный поток зовёт Stop, а не SubagentStop).
Его последнее сообщение обязано нести строку `### ВОЗВРАТ`, после неё — строку
`- статус: <значение>` из словаря контракта `CLAUDE.md`, и после блока — ни одного
заголовка (блок ПОСЛЕДНИЙ).

ЧТО НЕ СУДИТСЯ — и почему:
  · агент шаблона волны (Workflow): путь его стенограммы лежит под
    `/subagents/workflows/`, отвечает он полями схемы, а не текстом, и поля
    last_assistant_message у него нет (тот же опыт). Его исход судит шаблон;
  · встроенный агент без определения в `.claude/agents/` (general-purpose, Explore):
    контракта ВОЗВРАТа у него нет;
  · второе завершение подряд (stop_hook_active=true): отклонение уже было; второе
    отказало бы по кругу без предела. Пропуск с громким systemMessage — итог без
    ВОЗВРАТА диспетчер читает недействительным (`CLAUDE.md` «Не жди»).

ГРАНИЦА (BOUNDARY; известно, не ловится):
  · содержимое строки «- статус: идёт» (pid, журнал, срок) не разбирается — судится
    наличие блока и значение статуса из словаря;
  · блок, написанный ради стража при работе, не сданной по сути, — предмет приёмки,
    а не этого стража;
  · ожидание ВНУТРИ хода (агент держит Monitor и не заканчивает ход) — предмет
    stall-census.sh (STALL-AGENT), а не этого события.

ПРЕДПОСЫЛКА. Поле last_assistant_message у сабагента вне шаблона. Нет поля — страж
не знает, что судить: пропуск со словом «СЛОМАН» (громко, не запирая).

Коды: 0 всегда. Отклонение — JSON на stdout; поломка — systemMessage «СЛОМАН».
"""
import json
import os
import re
import sys

STATUSES = ('готово', 'идёт', 'блокер', 'вопрос-владельцу', 'не-выполнилось')
HEAD = re.compile(r'^\s*###\s+ВОЗВРАТ\s*$')
STATUS = re.compile(r'^\s*-\s*статус:\s*(\S+)')
HEADING = re.compile(r'^\s*#{1,6}\s+\S')
WORKFLOW_PATH = '/subagents/workflows/'

RULE = ('Последний блок ответа исполнителя — «### ВОЗВРАТ» по контракту CLAUDE.md, '
        'строка «- статус: готово | идёт | блокер | вопрос-владельцу | не-выполнилось». '
        'Ход НЕ завершается ожиданием события (Monitor, уведомление о фоновой задаче): '
        'долгое — отсоединённо (setsid nohup <команда> > <журнал> 2>&1 & echo $! > <pid-файл>), '
        'и ход кончается ВОЗВРАТОМ со статусом «идёт» — pid, журнал, срок; исход дочитает '
        'следующий короткий шаг. Итог без блока «### ВОЗВРАТ» недействителен. '
        'Допиши блок сейчас — по фактам, которые у тебя есть (CLAUDE.md «Не жди», ws#1030).')


def out(obj):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(0)


def broken(why):
    out({'systemMessage': 'RETURN-GUARD СЛОМАН: %s. Завершение исполнителя этим вызовом НЕ '
                          'проверялось — это не «чисто»; итог без «### ВОЗВРАТ» недействителен '
                          '(CLAUDE.md «Не жди»); починка — tooling-maintainer.' % why})


def verdict(msg):
    """Причина отказа либо None: блок есть, статус из словаря, блок последний."""
    lines = (msg or '').splitlines()
    at = [i for i, l in enumerate(lines) if HEAD.match(l)]
    if not at:
        return 'в последнем сообщении нет строки «### ВОЗВРАТ»'
    tail = lines[at[-1] + 1:]
    if any(HEADING.match(l) for l in tail):
        return 'после блока «### ВОЗВРАТ» идёт заголовок — блок не последний'
    st = [m.group(1) for m in (STATUS.match(l) for l in tail) if m]
    if not st:
        return 'в блоке «### ВОЗВРАТ» нет строки «- статус: …»'
    if st[0] not in STATUSES:
        return 'статус «%s» вне словаря контракта (%s)' % (st[0], ' | '.join(STATUSES))
    return None


def main():
    try:
        ev = json.load(sys.stdin)
    except Exception as e:
        broken('вход не разобран как JSON (%s)' % type(e).__name__)
    if ev.get('hook_event_name') != 'SubagentStop':
        sys.exit(0)
    if WORKFLOW_PATH in (ev.get('agent_transcript_path') or ''):
        sys.exit(0)
    kind = ev.get('agent_type') or ''
    root = os.environ.get('CLAUDE_PROJECT_DIR') or ev.get('cwd') or ''
    adir = os.path.join(root, '.claude', 'agents')
    if not os.path.isdir(adir):
        broken('каталога определений агентов нет: %s' % adir)
    if kind == 'dispatcher' or not re.fullmatch(r'[A-Za-z0-9_-]+', kind) \
            or not os.path.isfile(os.path.join(adir, kind + '.md')):
        sys.exit(0)
    if 'last_assistant_message' not in ev:
        broken('у исполнителя %s нет поля last_assistant_message — судить нечего' % kind)
    why = verdict(ev.get('last_assistant_message'))
    if why is None:
        sys.exit(0)
    if ev.get('stop_hook_active'):
        out({'systemMessage': 'RETURN-GUARD: исполнитель %s завершил ход без ВОЗВРАТА и после '
                              'отказа (%s). Итог недействителен: диспетчер читает его как '
                              '«не-выполнилось», полоса — новым коротким шагом (CLAUDE.md «Не жди»).'
                              % (kind, why)})
    out({'decision': 'block',
         'reason': 'ОТКАЗ ЗАВЕРШЕНИЮ ХОДА (return-guard): %s. %s' % (why, RULE)})


if __name__ == '__main__':
    main()
