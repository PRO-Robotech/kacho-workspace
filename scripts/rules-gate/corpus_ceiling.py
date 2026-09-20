#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Предмет: ОБЪЁМ и ФОРМА корпуса `.claude/rules/*.md` как целого.

Потолок и форма судятся ОДНИМ обходом, потому что оба — свойства корпуса, а не
файла: объём складывается, а строка-норма формы «id · императив · держатель ·
red: признак» проверяется у каждой. Гейт называет ось, а не «что-то не так».

ОТКАЗ (код 2), а не «находок 0»: обход, увидевший меньше 17 файлов правил либо
ни одной строки-нормы, беспредметен — сумма такого обхода МЕНЬШЕ настоящей, и
зелёный потолок был бы вычислен из недочитанного дерева.
"""
import glob
import sys

CEILING = 200_000
FLOOR_FILES = 17


def rows_of(path):
    with open(path, encoding='utf-8') as fh:
        return [l.rstrip('\n') for l in fh if ' · ' in l]


def main():
    files = sorted(glob.glob('.claude/rules/*.md'))
    total = sum(len(open(f, encoding='utf-8').read()) for f in files)
    rows = [(f, l) for f in files for l in rows_of(f)]

    print('осмотрено файлов правил: %d; строк-норм: %d; объём: %d из %d'
          % (len(files), len(rows), total, CEILING))

    if len(files) < FLOOR_FILES or not rows:
        print('ОТКАЗ — файлов правил %d (ожидалось не меньше %d), строк-норм %d: обход'
              ' усечён, сумма меньше настоящей, вердикт о потолке беспредметен'
              % (len(files), FLOOR_FILES, len(rows)))
        return 2

    rc = 0
    if total > CEILING:
        print('КРАСНОЕ объём — %d символов, потолок %d, перевес %d'
              % (total, CEILING, total - CEILING))
        rc = 1

    # ── форма строки-нормы: каждая ось названа отдельно ──────────────────────
    def red(axis, predicate):
        nonlocal rc
        hits = [(f, l) for f, l in rows if predicate(l)]
        if not hits:
            return
        rc = 1
        print('КРАСНОЕ %s — строк %d' % (axis, len(hits)))
        for f, l in hits[:5]:
            print('  %s: %s' % (f, l[:120]))

    def field(l, i):
        parts = l.split(' · ')
        return parts[i].strip() if len(parts) > i else ''

    red('строка без поля red:', lambda l: 'red:' not in l)
    red('нечётный backtick', lambda l: l.count('`') % 2 == 1)
    red('пустой императив (поле 2)', lambda l: field(l, 1) in ('—', ''))
    red('пустой держатель (поле 3)', lambda l: field(l, 2) in ('—', ''))
    red('пустой признак красноты', lambda l: l.rstrip().endswith('red: —'))
    # «держится» — слово отчёта о себе, а не императив: норма либо несёт
    # названный механизм в поле 3, либо стоит в долге с `ЗАВЕСТИ`.
    held = [(f, l) for f, l in rows if 'держится' in l]
    if held:
        rc = 1
        print('КРАСНОЕ слово «держится» вместо названного механизма — строк %d' % len(held))
        for f, l in held[:5]:
            print('  %s: %s' % (f, l[:120]))
    return rc


if __name__ == '__main__':
    sys.exit(main())
