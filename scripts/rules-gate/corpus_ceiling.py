#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Предмет: ОБЪЁМ и ФОРМА корпуса `.claude/rules/*.md` как целого.

Потолок и форма судятся ОДНИМ обходом, потому что оба — свойства корпуса, а не
файла: объём складывается, а строка-норма формы «id · императив · держатель ·
red: признак» проверяется у каждой. Гейт называет ось, а не «что-то не так».

ПОЛНОТА ОБХОДА СВЕРЯЕТСЯ С ОБЪЯВЛЕНИЕМ СОСТАВА, А НЕ С ЧИСЛОМ В КОДЕ (ws#854).
Сумма обхода, не дошедшего до файла корпуса, МЕНЬШЕ настоящей, и зелёный
потолок был бы вычислен из недочитанного дерева. Здесь стоял пол `FLOOR_FILES =
17` при 18 файлах: снятие одного файла правил проходило молча (корпус 190 619 из
200 000, код 0), и держал это только `check-01`. Теперь ожидаемый состав — имена
таблицы `.claude/rules/MANIFEST.md`, разобранные ОБЩИМ разборщиком набора
`manifest-rows.awk` (своего разбора таблицы проверка не заводит — шапка
разборщика): пол равен корпусу и растёт вместе с ним без правки этого файла.
Объявленный файл, которого обход не нашёл, — находка (код 1) и называется по
имени. Законное снятие правила снимает и его строку таблицы — тогда объявленное
и осмотренное снова совпадают, и эта ось молчит; остальное о снятии судят
`check-01` и `check-04`.

ОТКАЗ (код 2), а не «находок 0»: объявления состава нет (нет таблицы, разборщик
отказал либо не разобрал ни одной строки) — полноту обхода сверить не с чем; либо
обход не нашёл ни одной строки-нормы.

ФОРМА НОРМАЛИЗАЦИИ ЗАКРЕПЛЕНА ЗДЕСЬ, В ПРИБОРЕ, А НЕ В УТВЕРЖДЕНИИ О НЁМ.
Символ как единица счёта определён только вместе с формой записи: `й` — это ОДИН
символ в NFC и ДВА в NFD, и «ни одной изменённой буквы» на форму не влияет.
Измерено на этом корпусе 2026-09-22: NFC 198 613, NFD 200 412 — разница 1 799
БОЛЬШЕ всего запаса (1 387), то есть вердикт переворачивался бы САМ СОБОЙ от
формы, в которой файл случайно сохранён редактором или инструментом переноса.
Пока форма не закреплена, «потолок 200 000 символов» — не утверждение, а
свойство чужой настройки. Здесь весь текст читается через `read()`, и ни один
счёт в этом файле не идёт мимо него.

ЧТО ЭТИМ НЕ ЗАКРЫТО, И ЭТО ГРАНИЦА: объём считается по ФАЙЛАМ НА ДИСКЕ, а не по
тому, что доезжает В ОКНО агента. При снятой автозагрузке корпуса (решение
владельца 2026-09-17) правило попадает в окно скилл-ссылкой, и сколько его туда
приезжает, эта проверка не знает. Число здесь — ПРОКСИ бюджета окна, а не его
измерение; сказано вслух, потому что «потолок корпуса» читается как второе.
"""
import glob
import os
import subprocess
import sys
import unicodedata

CEILING = 200_000
MANIFEST_REL = '.claude/rules/MANIFEST.md'
# Разборщик — РЯДОМ С ПРИБОРОМ, а не в дереве: инъекция гоняет проверку на копии
# дерева, куда `scripts/` не копируется (тот же довод, что у `check-01`).
PARSER = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'manifest-rows.awk')
# Закреплённая форма. NFC, а не NFD: в ней корпус уже записан (проверено
# `unicodedata.is_normalized`), и она короче — выбор формы влияет на ЧИСЛО, а не
# только на его устойчивость, поэтому назван и он.
FORM = 'NFC'


def read(path):
    """Текст файла в ЗАКРЕПЛЁННОЙ форме: единственная дверь к содержимому."""
    with open(path, encoding='utf-8') as fh:
        return unicodedata.normalize(FORM, fh.read())


def rows_of(path):
    return [l for l in read(path).split('\n') if ' · ' in l]


def workspace_root(argv):
    """Корень дерева — ИЗ РАСПОЛОЖЕНИЯ ЭТОГО ФАЙЛА, а не из текущего каталога.

    Здесь стоял относительный `glob.glob('.claude/rules/*.md')`, а звавший его
    `check-06` делал `cd "$(git rev-parse --show-toplevel)"`: корнем обоих был
    cwd. Измерено 2026-09-22 на том же классе в `check-11`: запуск с cwd в
    СОСЕДНЕМ worktree полосы судил ЧУЖОЕ дерево и выходил нулём — «полоса
    получает чужой вердикт». Порядок источников: явный аргумент (им пользуется
    инъекция, гоняющая проверку по КОПИИ дерева), затем `RULES_GATE_ROOT` —
    контракт набора (`run-all.sh`), затем своё расположение. cwd не участвует.
    """
    if len(argv) > 1 and argv[1]:
        return os.path.abspath(argv[1])
    env = os.environ.get('RULES_GATE_ROOT')
    if env:
        return os.path.abspath(env)
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def declared_rules(root):
    """Имена файлов корпуса по объявлению: `(множество, причина отказа)`.

    Таблица читается ОБЩИМ разборщиком набора под `LC_ALL=C` — так же, как её
    читают `check-01`, `check-03` и `check-04`; второе прочтение грамматики
    разошлось бы с первым молча. Любой отказ разбора возвращает причину, а не
    пустое множество: пустое объявление неотличимо от «сверять не с чем».
    """
    manifest = os.path.join(root, MANIFEST_REL)
    if not os.path.isfile(PARSER):
        return None, 'разборщика %s нет рядом с прибором' % os.path.basename(PARSER)
    if not os.path.isfile(manifest):
        return None, '%s в дереве нет' % MANIFEST_REL
    proc = subprocess.run(['awk', '-f', PARSER, manifest],
                          env=dict(os.environ, LC_ALL='C'),
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        return None, 'разборщик таблицы отказал (код %d): %s' % (
            proc.returncode, proc.stderr.decode('utf-8', 'replace').strip()[:200])
    names = set()
    for line in proc.stdout.decode('utf-8', 'replace').split('\n'):
        cells = line.split('\t')
        if len(cells) >= 2 and cells[1]:
            names.add(cells[1])
    if not names:
        return None, 'в таблице %s не разобрано ни одной строки' % MANIFEST_REL
    return names, ''


def main():
    root = workspace_root(sys.argv)
    files = sorted(glob.glob(os.path.join(root, '.claude/rules/*.md')))
    total = sum(len(read(f)) for f in files)
    rows = [(f, l) for f in files for l in rows_of(f)]
    # Координаты печатаются ОТ КОРНЯ: находка обязана указывать на файл так, как
    # его зовёт дерево, а не так, как он лёг в абсолютный путь этой машины.
    files = [os.path.relpath(f, root) for f in files]
    rows = [(os.path.relpath(f, root), l) for f, l in rows]
    declared, why = declared_rules(root)
    seen = set(os.path.basename(f) for f in files)

    # Корень — первым числом переписи: все прочие суть утверждения о ДЕРЕВЕ, и
    # без имени дерева два прогона нечем сверить между собой. Объявленное —
    # вторым: без него «осмотрено 17» не отличить от «осмотрено всё».
    print('корень %s; объявлено файлов правил: %s; осмотрено файлов правил: %d; '
          'строк-норм: %d; объём: %d из %d'
          % (root, len(declared) if declared is not None else 'НЕ РАЗОБРАНО',
             len(files), len(rows), total, CEILING))

    if declared is None:
        print('ОТКАЗ — объявления состава нет (%s): полноту обхода сверить не с чем,'
              ' вердикт о потолке беспредметен' % why)
        return 2
    if not rows:
        print('ОТКАЗ — строк-норм 0 при файлах правил %d: обход беспредметен,'
              ' вердикт о потолке и форме не о чем выносить' % len(files))
        return 2

    rc = 0
    missing = sorted(declared - seen)
    if missing:
        print('КРАСНОЕ состав — объявленных файлов правил нет на диске: %d из %d (%s):'
              ' обход не дошёл до них, объём %d меньше настоящего'
              % (len(missing), len(declared), ', '.join(missing), total))
        rc = 1
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
