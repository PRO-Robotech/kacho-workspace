#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Предмет: СТАРТОВОЕ ОКНО каждого агента не выше своего потолка (ws#1084).

ЧТО МЕРЯЕТСЯ. Решение владельца 2026-10-14: «сами рулы ограничивать в
размересовакупном нету смысла вопрос какие скилы будут существовать и какими
рулами будут обладать». Токенами платится не корпус, а то, что агент получает
при запуске: `CLAUDE.md` (кроме агента с `omitClaudeMd: true`), файл агента и
каждый скилл из его `skills:` целиком (харнесс грузит их при старте). Это и есть
СТАРТ, и он судится потолком ЭТОГО агента из ведомости `agent-window-budget.tsv`.

ПОДГРУЗКА ПО ТРИГГЕРУ (`Skill <имя>` в теле, имени нет в `skills:`) считается
ОТДЕЛЬНО, печатается и НЕ ограничивается: она приезжает лишь при условии, и её
цена — свойство задачи, а не агента.

ВНЕ СЧЁТА, и это граница прокси: системный промпт харнесса, описания инструментов
и чужих агентов, личная память пользователя (`MEMORY.md` лежит вне дерева, CI её
не видит). Единица — символ в NFC; токены печатаются оценкой по `CHARS_PER_TOKEN`.

ВЕДОМОСТЬ — ХРАПОВИК. Строка: `<агент>\\t<потолок, символов>\\t<основание>`.
Начальный потолок — старт агента 2026-10-14 плюс запас не больше 10 %; рост сверх
него — только правкой числа с основанием (задача, замер до/после). Находки:
старт выше потолка · агент без строки · строка без агента · строка без числа или
без основания · скилл из `skills:`, которого нет в дереве (харнесс пропустил бы
его молча, и старт был бы посчитан неверно). Запас больше 10 % печатается
напоминанием опустить число, но не краснеет: сжатие правила, общего для
тридцати агентов, не обязано красить их всех.

ОТКАЗ (код 2): нет `CLAUDE.md`, каталога агентов, ведомости, либо в ведомости ни
одной строки — судить нечего.
"""
import glob
import os
import re
import sys
import unicodedata

FORM = 'NFC'
# Измерено разведчиком 2026-10-14 (`tok.py`, 317 пар «символы промпта → usage»
# журналов сессии 3f44acf5): 2,09–2,16 символа на токен. Прежняя оценка 3,3
# занижала токены в 1,57 раза. Оценка печатается, вердикт — по символам.
CHARS_PER_TOKEN = 2.1
RATCHET = 0.10
LEDGER_DEFAULT = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                              'agent-window-budget.tsv')
SKILL_RE = re.compile(r'\bSkill\s+`?([A-Za-z0-9][A-Za-z0-9:_-]*)')


def read(path):
    with open(path, encoding='utf-8') as fh:
        return unicodedata.normalize(FORM, fh.read())


def workspace_root(argv):
    if len(argv) > 1 and argv[1]:
        return os.path.abspath(argv[1])
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
    from gate_root import gate_root  # noqa: E402
    return gate_root('RULES_GATE_ROOT', __file__)


def frontmatter(text):
    """(строки frontmatter, тело) — frontmatter между первыми двумя `---`."""
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        return [], text
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            return lines[1:i], '\n'.join(lines[i + 1:])
    return [], text


def skills_of(fm):
    """Имена из `skills:` — списком `  - имя` либо строкой `skills: a, b`."""
    out, inside = [], False
    for line in fm:
        if re.match(r'^skills\s*:', line):
            rest = line.split(':', 1)[1].strip().strip('[]')
            out += [x.strip() for x in rest.split(',') if x.strip()]
            inside = True
            continue
        if inside:
            m = re.match(r'^\s+-\s*(\S+)', line)
            if m:
                out.append(m.group(1))
                continue
            if line.strip() and not line.startswith((' ', '\t')):
                inside = False
    return out


def omits_claude_md(fm):
    return any(re.match(r'^omitClaudeMd\s*:\s*true\s*$', l) for l in fm)


def load_ledger(path):
    """{агент: (потолок|None, основание, номер строки)} и список отказов формы."""
    rows, bad = {}, []
    for n, line in enumerate(read(path).split('\n'), 1):
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        cells = line.split('\t')
        name = cells[0].strip()
        num = cells[1].strip() if len(cells) > 1 else ''
        why = cells[2].strip() if len(cells) > 2 else ''
        if not re.fullmatch(r'[0-9]+', num) or not why:
            bad.append('%s:%d: «%s» — нужно «агент<TAB>потолок<TAB>основание»' % (
                os.path.basename(path), n, line[:80]))
            rows[name] = (None, why, n)
            continue
        rows[name] = (int(num), why, n)
    return rows, bad


def main():
    root = workspace_root(sys.argv)
    ledger_path = os.environ.get('RULES_GATE_WINDOW_BUDGET') or LEDGER_DEFAULT
    claude_md = os.path.join(root, 'CLAUDE.md')
    agents = sorted(glob.glob(os.path.join(root, '.claude/agents/*.md')))
    if not os.path.isfile(claude_md):
        print('[VOID] ОТКАЗ — в корне %s нет CLAUDE.md: старт без него не посчитать' % root)
        return 2
    if not agents:
        print('[VOID] ОТКАЗ — в %s/.claude/agents нет ни одного агента: судить нечего' % root)
        return 2
    if not os.path.isfile(ledger_path):
        print('[VOID] ОТКАЗ — ведомости потолков %s нет: сверять не с чем' % ledger_path)
        return 2
    ledger, bad = load_ledger(ledger_path)
    if not ledger:
        print('[VOID] ОТКАЗ — в ведомости %s ни одной строки' % ledger_path)
        return 2

    base = len(read(claude_md))
    rc, report, seen = 0, [], set()
    for path in agents:
        name = os.path.splitext(os.path.basename(path))[0]
        seen.add(name)
        text = read(path)
        fm, body = frontmatter(text)
        pre = skills_of(fm)
        start = len(text) + (0 if omits_claude_md(fm) else base)
        missing = []
        for s in pre:
            p = os.path.join(root, '.claude/skills', s, 'SKILL.md')
            if os.path.isfile(p):
                start += len(read(p))
            else:
                missing.append(s)
        trig = []
        for s in sorted(set(SKILL_RE.findall(body)) - set(pre)):
            p = os.path.join(root, '.claude/skills', s, 'SKILL.md')
            if os.path.isfile(p):
                trig.append((s, len(read(p))))
        report.append((name, start, len(pre), trig, missing))

    print('корень %s; агентов осмотрено: %d; строк ведомости: %d; CLAUDE.md: %d символов; '
          'единица — символ NFC, токены ≈ символы / %.1f'
          % (root, len(agents), len(ledger), base, CHARS_PER_TOKEN))
    starts = sorted(r[1] for r in report)
    top = max(report, key=lambda r: r[1])
    print('старт: максимум %d (%s, ≈%d ток.), медиана %d (≈%d ток.)'
          % (top[1], top[0], top[1] / CHARS_PER_TOKEN, starts[len(starts) // 2],
             starts[len(starts) // 2] / CHARS_PER_TOKEN))
    for name, start, npre, trig, missing in report:
        cap = ledger.get(name, (None, '', 0))[0]
        tsum = sum(n for _, n in trig)
        print('  %-24s старт %7d / потолок %7s · skills: %d · по триггеру +%d (%d, не ограничено)'
              % (name, start, cap if cap is not None else '—', npre, tsum, len(trig)))
        if missing:
            rc = 1
            print('КРАСНОЕ скилл — %s: в skills: %s, в .claude/skills их нет' % (name, ', '.join(missing)))
        if name not in ledger:
            rc = 1
            print('КРАСНОЕ ведомость — у агента %s нет потолка: строка «%s\\t%d\\t<основание>»'
                  % (name, name, start))
        elif cap is not None and start > cap:
            rc = 1
            print('КРАСНОЕ окно — %s: старт %d, потолок %d, перевес %d (≈%d ток.)'
                  % (name, start, cap, start - cap, (start - cap) / CHARS_PER_TOKEN))
        elif cap is not None and cap > start * (1 + RATCHET):
            print('  храповик: у %s запас %.0f%% больше %d%% — опустить потолок до %d'
                  % (name, 100.0 * (cap - start) / start, RATCHET * 100, int(start * (1 + RATCHET))))
    for line in bad:
        rc = 1
        print('КРАСНОЕ форма ведомости — %s' % line)
    for name in sorted(set(ledger) - seen):
        rc = 1
        print('КРАСНОЕ ведомость — строка %d о «%s»: такого агента нет, запись пережила предмет'
              % (ledger[name][2], name))
    return rc


if __name__ == '__main__':
    sys.exit(main())
