#!/usr/bin/env python3
# Отбор норм из описи в форму корпуса.
#   rows-from-inventory.py <файл.md> [...]          — сводка + строки в tmp/rules-compression/rows-<файл>.txt
#   rows-from-inventory.py --verify <файл.md> [...] — сверка, что все id есть в корпусе (код 1 при потере)
#
# ЧТО ОТБИРАЕТСЯ: классы A и B, плюс ЛЮБАЯ запись с названным гейтом — такая запись
# норма по построению, какой бы класс ей ни присвоила опись (52 в классе D и 41 в
# классе C). Остальное классов C и D уезжает в `.claude/backup/`.
import argparse
import json
import os
import pathlib
import re
import sys

# КОРЕНЬ — ИЗ РАСПОЛОЖЕНИЯ ЭТОГО ФАЙЛА, А НЕ ИЗ ТЕКУЩЕГО КАТАЛОГА (2026-09-22).
#
# Вторая законная форма того же класса, что `git rev-parse --show-toplevel`:
# ОТНОСИТЕЛЬНЫЙ путь. Здесь их было три — `INV`, `OUT` и `.claude/rules/<файл>`, —
# и все резолвились от cwd. Различающий опыт на чужом дереве, где `testing.md`
# укорочен на 500 Б (оба прогона — один и тот же файл прибора):
#   cwd = ЧУЖОЕ дерево: testing.md: ожидается 79, найдено 78, ПОТЕРЯНО 1, объём 19393 (код 1)
#   cwd = СВОЁ  дерево: testing.md: ожидается 79, найдено 79, ПОТЕРЯНО 0, объём 19723 (код 0)
# Для ПРИБОРА это хуже, чем для гейта: его число цитируют в отчётах и в шапках
# проверок, и разошедшееся число некому опровергнуть. Тот же класс — `check-11`,
# `corpus_ceiling.py`. Порядок источников один на весь набор: `RULES_GATE_ROOT`
# (им пользуется инъекция), затем своё расположение; cwd не участвует.
ROOT = os.path.abspath(
    os.environ.get('RULES_GATE_ROOT')
    or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
INV = os.path.join(ROOT, 'tmp/rules-compression/inventory-2026-09-19.json')
OUT = pathlib.Path(ROOT) / 'tmp/rules-compression'
RULES = os.path.join(ROOT, '.claude/rules')
DOT = ' · '
DASH = '—'
HAND = 'ПИСАТЬ РУКАМИ'


def gated(n):
    g = (n.get('gate') or '').strip()
    return bool(g) and g not in (DASH, 'None')


def keep(n):
    return n.get('k') in ('A', 'B') or gated(n)


def balance_bt(s):
    # Нечётное число backtick ломает markdown. Замер: 146 строк из 860 приходят такими.
    return s if s.count('`') % 2 == 0 else s.replace('`', '')


def holder(n, form_field):
    # Держатель обязан быть ИМЕНЕМ механизма либо честным `ЗАВЕСТИ <имя>`.
    # Замер: у 360 из 860 строк поле формы держателя не несёт.
    for src in (form_field, n.get('gate') or '', n.get('hold') or ''):
        s = (src or '').strip(' `')
        if s and s not in (DASH, '', 'None') and re.search(r'[A-Za-z_]{4,}', s):
            return balance_bt(s)
    return 'ЗАВЕСТИ ' + n['id']


def row(n):
    fm = (n.get('form') or '').strip()
    if not fm or fm == DASH:
        return None
    p = [x.strip(' `') for x in re.split(r'\s*\|\s*', fm) if x.strip(' `')]
    if len(p) >= 4:
        imp, hold_raw, red = p[1], p[2], ' | '.join(p[3:])
    elif len(p) == 3:
        imp, hold_raw, red = p[1], p[2], DASH
    elif len(p) == 2:
        imp, hold_raw, red = p[1], '', DASH
    else:
        imp, hold_raw, red = p[0], '', DASH
    return (n['id'] + DOT + balance_bt(imp) + DOT + holder(n, hold_raw)
            + DOT + 'red: ' + balance_bt(red))


def main(argv):
    verify = '--verify' in argv
    files = [a for a in argv if a != '--verify']
    if not files:
        print('нужен хотя бы один файл правил')
        return 1
    inv = json.load(open(INV, encoding='utf-8'))
    OUT.mkdir(parents=True, exist_ok=True)
    # Корень — первым: все числа ниже суть утверждения о ДЕРЕВЕ, и без имени
    # дерева два прогона нечем сверить между собой.
    print('корень %s; опись %s; записей %d'
          % (ROOT, os.path.relpath(INV, ROOT), len(inv)))
    rc = 0
    for f in files:
        sel = [n for n in inv if n['src'] == f and keep(n)]
        arch = [n for n in inv if n['src'] == f and not keep(n)]
        if not sel:
            print(f + ': КРАСНОЕ — в описи нет ни одной остающейся записи, отбор пуст')
            rc = 1
            continue
        if verify:
            have = set()
            for line in open(os.path.join(RULES, f), encoding='utf-8'):
                if DOT in line:
                    have.add(line.split(DOT)[0].strip())
            want = {n['id'] for n in sel}
            miss = sorted(want - have)
            size = len(open(os.path.join(RULES, f), encoding='utf-8').read())
            print('%s: ожидается %d, найдено %d, ПОТЕРЯНО %d, объём %d'
                  % (f, len(want), len(want & have), len(miss), size))
            if miss:
                print('   потеряны: ' + ', '.join(miss[:20]))
                rc = 1
            continue
        rows = [(n['id'], row(n)) for n in sel]
        hand = [i for i, r in rows if not r]
        dst = OUT / ('rows-' + f + '.txt')
        with open(dst, 'w', encoding='utf-8') as out:
            for i, r in rows:
                out.write((r or (i + DOT + HAND + DOT + 'ЗАВЕСТИ '
                                 + i + DOT + 'red: ' + DASH)) + '\n')
        chars = sum(len(r) + 1 for _, r in rows if r) + len(hand) * 160
        print('%s: строк %d, руками %d, в архив %d, символов ~%d -> %s'
              % (f, len(rows), len(hand), len(arch), chars, dst))
        if hand:
            print('   руками: ' + ', '.join(hand))
    return rc


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
