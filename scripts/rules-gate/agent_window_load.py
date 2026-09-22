#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Предмет: СКОЛЬКО ТЕКСТА ПРИХОДИТ В ОКНО ОДНОМУ АГЕНТУ.

ЗАЧЕМ ОТДЕЛЬНО ОТ check-06. `check-06` судит СУММУ корпуса. Суммы не грузит
никто: решением владельца 2026-09-17 корпус снят с автозагрузки, и агент
получает ровно то, что перечислено в его `skills:`. Замер 2026-09-22 на
`978cc66c`: максимум по агенту 85 559 символов при сумме 197 784 — наибольшая
доля корпуса, доезжающая одному, 33,6 %; медиана 49 585. Величина, которую судит
потолок, адресата не имеет; величина с адресатом — вот эта.

ЧЕМ ЭТО СТРОЖЕ, А НЕ МЯГЧЕ. Сумма анти-коррелирована с вредом. Тот же замер:
полоса восстановления координат добавила в СУММУ 31 776 символов и связующему
агенту `rpc-implementer` — НОЛЬ (ни одно из её правил за ним не закреплено);
доливка добавила в сумму 37 032 и в реальную загрузку до +26 238. Сумма наказала
текст, который до края не доходит, и не заметила роста, который доходит до всех.

ПОРОГА ЗДЕСЬ НЕТ, И ЭТО СКАЗАНО ПРЯМО, А НЕ УМОЛЧАНО. Порог обязан быть
ВЫВЕДЕН, а выводить его сегодня не из чего — четыре основания проверены и
отвергнуты, разбор в возврате полосы. Поэтому проверка работает ПЕРЕПИСЬЮ:
считает, печатает и НЕ блокирует. Порог включается средой
`RULES_GATE_AGENT_WINDOW_MAX` — в тот день, когда он будет назначен или выведен,
проверка становится блокирующей БЕЗ переделки, и её инъекция доказывает оба
режима.

ДВЕ ФОРМЫ НУЛЯ РАЗЛИЧИМЫ СЛОВОМ, А НЕ ЧИСЛОМ. «У агента ноль правил» —
штатное состояние `dispatcher` и `client-simulator` (у первого база заменяет
корпус, у второго пустой контекст — предмет роли). «Агента не осмотрели» —
отказ. Первое печатается отдельной строкой с именами, второе роняет вердикт.

ВЕРДИКТ — В КОДЕ ВЫХОДА: 0 молчит, 1 находка (только при заданном пороге),
2 обход беспредметен.
"""
import glob
import os
import statistics
import subprocess
import sys

RULES = '.claude/rules'
SKILLS = '.claude/skills'
AGENTS = '.claude/agents'
# Агенты, у которых отсутствие правил — НОРМА, и почему. Перечень здесь закрыт
# намеренно: это не исключение по вкусу, а объявление двух ролей, чьё устройство
# описано в `ai-tooling.md`. Появится третья — она обязана быть названа тут же,
# иначе её ноль сольётся с непрочитанным.
LAWFUL_EMPTY = {
    'dispatcher': 'база маршрутизации заменяет корпус (решение владельца 2026-09-17)',
    'client-simulator': 'пустой контекст — предмет роли (ban #18)',
}


def root():
    r = os.environ.get('RULES_GATE_ROOT')
    if r:
        return r
    return subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                          capture_output=True, text=True).stdout.strip() or '.'


def chars(path):
    try:
        with open(path, encoding='utf-8') as fh:
            return len(fh.read())
    except (OSError, UnicodeDecodeError):
        return None


def skills_of(path):
    """Перечень `skills:` из frontmatter — то, что харнесс грузит агенту."""
    try:
        lines = open(path, encoding='utf-8').read().split('\n')
    except OSError:
        return None
    try:
        i = lines.index('skills:')
    except ValueError:
        return []
    out, j = [], i + 1
    while j < len(lines) and lines[j].startswith('  - '):
        out.append(lines[j][4:].strip())
        j += 1
    return out


def main():
    base = root()
    agents = sorted(glob.glob(os.path.join(base, AGENTS, '*.md')))
    limit = os.environ.get('RULES_GATE_AGENT_WINDOW_MAX')
    limit = int(limit) if limit and limit.isdigit() else None

    rows, unread, bindings, unresolved = [], [], 0, []
    for a in agents:
        name = os.path.basename(a)[:-3]
        own = chars(a)
        sk = skills_of(a)
        if own is None or sk is None:
            unread.append(name)
            continue
        load = own
        for s in sk:
            bindings += 1
            target = os.path.join(base, SKILLS, s, 'SKILL.md')
            c = chars(target)
            if c is None:
                unresolved.append('%s -> %s' % (name, s))
                continue
            load += c
        rows.append((load, name, own, len(sk)))
    rows.sort(reverse=True)

    empty = [n for _, n, _, k in rows if k == 0]
    lawful = [n for n in empty if n in LAWFUL_EMPTY]
    unlawful = [n for n in empty if n not in LAWFUL_EMPTY]

    corpus = sum(chars(f) or 0 for f in glob.glob(os.path.join(base, RULES, '*.md')))

    # ── ПЕРЕПИСЬ СО ЗНАМЕНАТЕЛЕМ ─────────────────────────────────────────────
    print('осмотрено агентов: %d из %d найденных; закреплений разобрано %d, '
          'не разобрано %d%s; не прочитано определений %d%s'
          % (len(rows), len(agents), bindings, len(unresolved),
             (' (' + ', '.join(unresolved[:5]) + ')') if unresolved else '',
             len(unread), (' (' + ', '.join(unread) + ')') if unread else ''))
    if rows:
        loads = [r[0] for r in rows]
        print('загрузка окна, символов: максимум %d (%s); медиана %d; минимум %d (%s)'
              % (rows[0][0], rows[0][1], statistics.median(loads), rows[-1][0], rows[-1][1]))
        print('сумма корпуса %d; наибольшая доля корпуса у одного агента %.1f%% '
              '— СУММУ не грузит никто, она печатается как наблюдение'
              % (corpus, 100.0 * (rows[0][0] - rows[0][2]) / corpus if corpus else 0.0))
    # Ноль правил: ДВЕ разные вещи, и обе названы словом.
    print('агентов без правил: %d, из них ШТАТНО %d (%s); необъявленных %d%s'
          % (len(empty), len(lawful),
             '; '.join('%s — %s' % (n, LAWFUL_EMPTY[n]) for n in lawful) or '—',
             len(unlawful), (': ' + ', '.join(unlawful)) if unlawful else ''))
    print('порог: %s' % ('%d (задан средой RULES_GATE_AGENT_WINDOW_MAX)' % limit
                         if limit else 'НЕ ЗАДАН — проверка считает и печатает, но не блокирует; '
                                       'выводить его сегодня не из чего, разбор в возврате полосы'))

    # ── ОТКАЗ ПО БЕСПРЕДМЕТНОСТИ ────────────────────────────────────────────
    if not agents:
        print('ОТКАЗ — определений агентов не найдено: обход пуст, вердикт беспредметен')
        return 2
    if not rows:
        print('ОТКАЗ — ни одно определение агента не прочитано: вердикт беспредметен')
        return 2
    if unread:
        print('ОТКАЗ — не прочитано определений %d: перепись усечена, максимум мог '
              'остаться непрочитанным' % len(unread))
        return 2

    rc = 0
    if unlawful:
        rc = 1
        for n in unlawful:
            print('КРАСНОЕ агент `%s` не несёт ни одного правила и не объявлен как '
                  'штатно пустой — его ноль неотличим от непрочитанного' % n)
    if unresolved:
        rc = 1
        for x in unresolved:
            print('КРАСНОЕ закрепление не резолвится: %s — скил назван, переходника нет' % x)
    if limit:
        for load, name, own, _ in rows:
            if load > limit:
                rc = 1
                print('КРАСНОЕ загрузка окна `%s` — %d символов при пороге %d, перевес %d '
                      '(тело %d)' % (name, load, limit, load - limit, own))
    if rc == 0:
        print('находок 0')
    return rc


if __name__ == '__main__':
    sys.exit(main())
