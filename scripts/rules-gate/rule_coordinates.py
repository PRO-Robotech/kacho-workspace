#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Предмет: КООРДИНАТА ПРАВИЛА, НАПИСАННАЯ В ДЕРЕВЕ, обязана резолвиться — и её
ТРОЙКА обязана быть полной.

ЧТО УТВЕРЖДАЕТ. Всякая координата вида `.claude/rules/<имя>.md`, написанная в
отслеживаемом файле дерева, указывает на существующий файл правила, у которого
есть переходник `.claude/skills/rule-<имя>/SKILL.md` (символьная ссылка на своё
правило) и строка в таблице `.claude/rules/MANIFEST.md`. Механизм состоит из трёх
половин, и мёртвая любая из них означает одно и то же: `Skill rule-<имя>` зовётся
и не находит, а читатель идёт по адресу и не приходит.

ЧЕМ ЭТО ОТЛИЧАЕТСЯ ОТ check-04 И check-07, И ПОЧЕМУ ПРОВЕРКА ТРЕТЬЯ.
  · check-04 входит СО СТОРОНЫ ОБЪЯВЛЕНИЯ: перебирает строки манифеста и правила
    корпуса. Имя, которого нет ни там, ни там, но которое ШЕСТНАДЦАТЬ брифингов
    называют координатой, ему не встречается ВОВСЕ — он о нём не высказывается;
  · check-07 входит со стороны АДРЕСА РАЗДЕЛА (`файл.md §«Заголовок»`) и резолвит
    его по корпусу И АРХИВУ, потому что ссылка в архив верна: норма там лежит.
    Значит координата, чей файл уехал в `.claude/backup/`, у него резолвится —
    и именно этот класс остался незамеченным (12 имён, 1038 вхождений, замер
    2026-09-22);
  · эта проверка входит СО СТОРОНЫ УПОМИНАНИЯ: перечень имён она не берёт ниоткуда,
    а ВЫВОДИТ обходом дерева. Ноль упоминаний — отказ по беспредметности, а не
    зелёное.

ПРИЗНАК ФИКСТУРЫ ВЫВЕДЕН ИЗ ЕЁ РОЛИ, А НЕ ИЗ ПЕРЕЧНЯ ИМЁН. Перечень имён был бы
тем же объявлением полноты от руки, которое корпус ловит у продукта: он стареет
молча и в ту сторону, где живая ссылка попадает в «фикстуры». Поэтому фикстура
узнаётся по УСТРОЙСТВУ, и оснований ровно два, каждое — свойство, а не имя:

  (1) ФАЙЛ-РЕФЕРЕНТ РАБОТАЕТ НА КОПИИ КОРПУСА, А НЕ НА ЭТОМ ДЕРЕВЕ. Признак
      составной, и обе половины структурные: файл начинается с shebang (значит он
      АППАРАТУРА — его исполняют, а не читают) И содержит путь вида
      `$<переменная>/.claude/` (значит корпус, с которым он работает, лежит под
      ЧУЖИМ корнем — песочницей, которую он сам и заводит). Литерал
      `.claude/rules/<имя>.md` в таком файле — ВХОД, который аппаратура
      изготавливает, а не адрес в этом дереве. Никакой `inject-NN` и никакой
      `prove.sh` в перечне не назван: их берёт это свойство;

  (2) КООРДИНАТА НАПИСАНА С МАРКЕРОМ АВТОЗАГРУЗКИ `@` (`@.claude/rules/x.md`,
      `@./.claude/rules/x.md`, `@.claude//rules/x.md`). Это ОБРАЗЕЦ СИНТАКСИСА
      маркера, и предмет у него другой — что именно попадает в автозагрузку;
      его судит `check-02`, а не адрес, по которому идут читать.

ГРАНИЦА ПРИЗНАКА (1) НАЗВАНА ВСЛУХ: он освобождает ВСЕ координаты такого файла,
в том числе настоящую висячую. Цена принята сознательно — аппаратура падает
собственным прогоном, а не этой проверкой, — и печатается переписью: сколько
файлов признаны аппаратурой и сколько координат этим снято.

АРХИВ `.claude/backup/` ИЗ ПРЕДМЕТА ИСКЛЮЧЁН, и это тоже не список имён:
`check-02` судит его ОБЪЯВЛЕНИЕ архивом по двум предикатам (покрыт
`claudeMdExcludes`, ни один агент не тянет его файл через `skills:`). Объявленный
архив не делает утверждений о нынешнем дереве — он свидетельствует о снятом.

ВЕРДИКТ — В КОДЕ ВЫХОДА: 0 молчит, 1 находка, 2 обход беспредметен.
"""
import os
import re
import subprocess
import sys

RULES = '.claude/rules'
SKILLS = '.claude/skills'
ARCHIVE = '.claude/backup/'
MANIFEST = '.claude/rules/MANIFEST.md'

# Координата правила. `/+` — потому что законная запись маркера встречается и с
# удвоенным разделителем (`@.claude//rules/x.md`): для приведения путей это один
# и тот же файл, и разбор обязан видеть их одинаково.
COORD = re.compile(r'\.claude/+rules/([A-Za-z0-9_][A-Za-z0-9_.-]*)\.md')
# Хвост перед координатой: маркер автозагрузки с любым числом `./` между ним и путём.
AT_TAIL = re.compile(r'@[./]*$')
# Аппаратура: путь к корпусу под корнем-переменной.
SANDBOX_ROOT = re.compile(r'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/+\.claude/')


def root():
    r = os.environ.get('RULES_GATE_ROOT')
    if r:
        return r
    return subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                          capture_output=True, text=True).stdout.strip() or '.'


def tracked(base):
    out = subprocess.run(['git', '-C', base, 'ls-files', '-z'],
                         capture_output=True, text=True).stdout
    return [p for p in out.split('\0') if p]


def read(path):
    try:
        with open(path, encoding='utf-8') as fh:
            return fh.read()
    except (UnicodeDecodeError, OSError):
        return None


def is_apparatus(text):
    """Файл — аппаратура, работающая на КОПИИ корпуса: shebang плюс корень-переменная."""
    return text.startswith('#!') and bool(SANDBOX_ROOT.search(text))


def manifest_names(base):
    text = read(os.path.join(base, MANIFEST))
    if text is None:
        return None
    names = set()
    for line in text.split('\n'):
        if not line.startswith('| `'):
            continue
        m = re.match(r'\| `([^`]+\.md)` \|', line)
        if m:
            names.add(m.group(1))
    return names


def triple(base, name):
    """Три половины механизма. Возвращает перечень недостающих."""
    missing = []
    if not os.path.isfile(os.path.join(base, RULES, name + '.md')):
        missing.append('файла .claude/rules/%s.md нет' % name)
    link = os.path.join(base, SKILLS, 'rule-' + name, 'SKILL.md')
    want = '../../rules/%s.md' % name
    if not os.path.islink(link):
        missing.append('переходника .claude/skills/rule-%s/SKILL.md нет либо он не ссылка' % name)
    elif os.readlink(link) != want:
        missing.append('переходник rule-%s ведёт в «%s», а не в «%s»' % (name, os.readlink(link), want))
    return missing


def main():
    base = root()
    files = tracked(base)
    mf = manifest_names(base)

    walked = 0
    apparatus_files = []
    coords = []          # (src, line, name)
    by_marker = 0
    by_apparatus = 0

    for rel in files:
        if rel.startswith(ARCHIVE):
            continue
        text = read(os.path.join(base, rel))
        if text is None:
            continue
        walked += 1
        if not COORD.search(text):
            continue
        app = is_apparatus(text)
        if app:
            apparatus_files.append(rel)
        for m in COORD.finditer(text):
            if AT_TAIL.search(text[max(0, m.start() - 16):m.start()]):
                by_marker += 1
                continue
            if app:
                by_apparatus += 1
                continue
            coords.append((rel, text[:m.start()].count('\n') + 1, m.group(1)))

    names = sorted({n for _, _, n in coords})
    print('осмотрено отслеживаемых файлов: %d (архив .claude/backup/ исключён как объявленный);'
          ' координат живых %d, различных имён %d; снято как фикстуры: маркером `@` %d,'
          ' аппаратурой на копии корпуса %d (файлов-аппаратуры %d)'
          % (walked, len(coords), len(names), by_marker, by_apparatus, len(apparatus_files)))

    if not files:
        print('ОТКАЗ — отслеживаемых файлов 0: обход пуст, вердикт беспредметен')
        return 2
    if mf is None:
        print('ОТКАЗ — %s не прочитан: сверять тройку не с чем' % MANIFEST)
        return 2
    if not coords:
        print('ОТКАЗ — живых координат правил не найдено ни одной: либо дерево не то,'
              ' либо разборщик ослеп; «ноль находок» тут неотличимо от «ноль прочитанного»')
        return 2

    rc = 0
    for name in names:
        where = [(s, l) for s, l, n in coords if n == name][:4]
        miss = triple(base, name)
        if (name + '.md') not in mf:
            miss.append('строки в %s нет' % MANIFEST)
        if not miss:
            continue
        rc = 1
        print('КРАСНОЕ координата `.claude/rules/%s.md` — %s' % (name, '; '.join(miss)))
        for s, l in where:
            print('    названа в %s:%d' % (s, l))
    if rc == 0:
        print('находок 0: у каждого из %d имён есть файл, переходник и строка манифеста' % len(names))
    return rc


if __name__ == '__main__':
    sys.exit(main())
