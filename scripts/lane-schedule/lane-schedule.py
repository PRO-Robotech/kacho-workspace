#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""lane-schedule — упаковка полос в пакеты и расписание до раздачи.

ОРИЕНТИР ПЛАНИРОВАНИЯ, НЕ ГЕЙТ (Д43): инструмент ничего не пропускает и не
блокирует; его числа — оценка до раздачи, окончательно — реальный прогон волны.
Утверждение о нём одно: ребро не теряется МОЛЧА — ячейка «зависит от», не
прочитанная целиком, даёт ОТКАЗ с координатой, а не расчёт без ребра.

Норма, которую инструмент исполняет: `.claude/rules/flow-acceleration.md`
§«Раздача» (fa-a1…fa-a7). Приёмка инструмента — `scripts/lane-schedule/inject.sh`;
что набор краснеет на порче каждого решения — `scripts/lane-schedule/mutants.py`.

ВХОД — один или несколько `tasks.md` (маршрут работ под-фазы). Из каждого берётся
раздел `## <N>. Полосы` до следующего `## `: таблицы с колонкой «исполнитель»;
первая ячейка строки — id полосы; колонки «зависит от», «размер» (S/M/L),
«репозиторий · пути» либо «пути (kacho)». Заголовок `### … S<n> …` объявляет
стадию: ссылка `S<n>` в «зависит от» означает все полосы стадии. Имя под-фазы —
имя каталога файла без префикса `issue-`. Таблица без колонки «зависит от» даёт
независимые полосы — и заметку об этом, а не молчание.

ЯЧЕЙКА «ЗАВИСИТ ОТ»: список ссылок — до первой «;», дальше пояснение, и его id
рёбрами не становятся (заметка называет их поимённо). Ссылка — id полосы; id по
суффиксу (`A1` → единственная `S2-A1`; суффикс нескольких полос — ОТКАЗ); стадия
`S<n>`; «S-ярус» — все полосы с id ровно `S<n>`; диапазон `A1–A3`, `N0…N4`,
`S1-S3` с правой границей включительно, каждый член которого узнаётся как
отдельная ссылка (`A1–A2` → `S1-A1`, `S1-A2`; `S1–S2` → полосы стадий);
`S2-A1…A3` — префикс стадии левой границы переносится на правую; id с
буквенным суффиксом (`X2-F`, вход 2918 @d3387fcd4) — одна полоса; имя под-фазы
(`NTF-1`) — внешняя ссылка; обратный
диапазон (`A3–A1`) — ОТКАЗ; тире или дефис между разными префиксами (`X1–Y2`,
`X1-Y2`) — две ссылки. Прочее — внешние ссылки (жетоны ведомости); внешняя
ссылка без строки ведомости своей под-фазы печатается заметкой — опечатка в id
иначе неотличима от жетона. РАЗБОР FAIL-CLOSED: цифра до «;» вне `кода`,
«фразы» и номера окна `(0)`, не ставшая частью целой ссылки, либо id,
приклеенный к букве, цифре или «-буква» (`a1`, `X2-Fx`, `A1b`), — ОТКАЗ с
`файл:строка`, полосой и текстом ячейки: ссылка на полосу всегда несёт цифру, и
такой фрагмент иначе выпал бы без ребра и без заметки. Дефисоподобный знак
(U+2010–U+2015, U+2212, U+FE58, U+FE63, U+FF0D) вплотную к букве или цифре
перед буквой читается как ASCII-дефис (`X2–F` — полоса X2-F), перед id с
цифрой — как тире диапазона (`A1‑A3` — A1…A3); пробел
между id и «-буква» (`X2 -F`, `X2 – F`) — ОТКАЗ «неоднозначна». До ws#884 id с префиксом стадии (`S1-A1`) читался
как диапазон `S1…A1` и терялся: у 2919 из 41 полосы рёбра были у 8 (38 рёбер),
после правки — у 35 (83 ребра); замер `build()` @a1b230728 против @bfe2d9c91.

ПОРЯДОК ФАЙЛОВ — часть входа: он разрывает равенства (цепочка продолжает первого
по файлу предшественника, кандидаты склейки при равном раннем старте идут по месту
первой полосы, пакеты нумеруются по порядку). Прогоны сравнимы только при одном
порядке; строки «перепись» печатаются в порядке входа и его называют. Замер
@bfe2d9c91 на notify: 2915 2917 2919 2924 2925 — пакетов 137, срок при 6 слотах
1300 мин, минимум слотов 10; 2915 2917 2919 2925 2924 — 136, 1305, 9.

РЕЖИМЫ
  --edges A      рёбра только внутри задач (и внутризадачные строки ведомости);
  --edges B      плюс смысловые рёбра между под-фазами из `--semantic`;
  --pack literal склейка однотипных независимых пакетов без оглядки на путь;
  --pack guard   склейка только если она не удлиняет критический путь (норма).

ВЕДОМОСТЬ СМЫСЛОВЫХ РЁБЕР (`--semantic`, TSV, `#` — комментарий):
  <под-фаза> <TAB> <жетон> <TAB> <под-фаза-цель>
Полоса под-фазы, чья ячейка «зависит от» несёт жетон (внешняя ссылка вида `Е5`
либо фраза, в ведомости её можно взять в «ёлочки»), зависит от ВСЕХ полос цели;
внутри своей под-фазы — кроме полос, несущих тот же жетон. Цель, равная своей
под-фазе, — внутризадачное ребро (действует и в A).
Строка без полосы-носителя — ОТКАЗ: запись, которой нечего связывать, лжёт о
графе так же, как пропущенное ребро.

ИСХОДЫ (код выхода — вердикт, печать — пояснение):
  0 — рассчитано; перепись и числа напечатаны;
  1 — ОТКАЗ: цикл из явных рёбер (назван путь), строка таблицы не той ширины
      либо без заголовка, раздела «Полосы» нет, повтор id полосы либо под-фазы,
      строка ведомости не из трёх непустых полей, без носителя либо с под-фазой
      не из входа, ссылка по суффиксу неоднозначна, диапазон обратный,
      ячейка «зависит от» не распознана целиком,
      `--minutes` не ровно S, M, L, отрицательные `--minutes` или `--review`,
      `--slots` меньше 1, вход не читается;
  2 — обход ПУСТ: файлов нет либо в файле ноль полос. Ноль полос — не «ноль
      пакетов, срок 0», а «не прочитано ничего».

Цикл, замкнутый только РАСКРЫТИЕМ стадии (полоса стадии S2 зависит от «S2» и
тем самым от своих же потомков), — не отказ: ссылка на стадию значит «на
остальных её членов»; снятые рёбра печатаются поимённо в «заметках».

ДЛИТЕЛЬНОСТИ — ориентир, не замер: S=15, M=25, L=45 минут исполнения и 25 минут
ревью на пакет (решение 2026-09-27: один круг ревью плюс проверка исполнения).
Переопределяются `--minutes` и `--review`; число без перемера на новой модели
основанием срока не служит. Полоса исполнителя «диспетчер» длится 0 и слота не
занимает.
"""
import argparse
import collections
import heapq
import os
import re
import sys

UNIT = {'S': 1, 'M': 1, 'L': 2}
CAP_UNITS = 4
# Исполнители, чьи полосы однотипны по построению: склейка их независимых
# полос из разных под-фаз не смешивает предметы (fa-a3).
SAME_KIND = {'proto-sync', 'migration-writer', 'deploy-engineer', 'tooling-maintainer',
             'docs-writer', 'vault-scribe', 'git-operator'}
ID = r'[A-ZА-ЯЁ]+\d+(?:-[A-ZА-ЯЁ]+\d*)?'
# Имя под-фазы в ячейке (`NTF-1 на стенде`): внешняя ссылка, как жетон `Е<n>`.
PHASE = r'(?<![\w-])[A-ZА-ЯЁ]+-\d+(?![\w-])'
# Дефисоподобные знаки (U+2010–U+2015, U+2212, U+FE58, U+FE63, U+FF0D), стоящие
# вплотную к букве или цифре: перед буквенным суффиксом без цифры (`X2–F`,
# `X2‑F`) — ASCII-дефис, иначе «X2–F» давал бы ребро на X2 вместо X2-F без отказа
# и без заметки; перед границей с цифрой (`A1‑A3`) — тире диапазона «–», чтобы
# диапазон шёл прежним путём разделителя. Замена знак-в-знак — позиции фрагментов
# в тексте отказа совпадают с исходной ячейкой.
DASHLIKE = '\u2010-\u2015\u2212\ufe58\ufe63\uff0d'
DASH_NEAR_WORD = r'(?<=\w)[%s]|[%s](?=\w)' % (DASHLIKE, DASHLIKE)


def dashes(cell):
    return re.sub(DASH_NEAR_WORD,
                  lambda m: '-' if re.match(r'[^\W\d_]+(?!\w)', cell[m.end():]) else '–',
                  cell)


# Пробел между id и «-буква» (`X2 -F`, `X2- F`, `X2 – F`): суффикс это или
# отдельное слово — не определено; ОТКАЗ, а не ребро на X2. Буква без цифры
# границей диапазона не бывает, так что `A1 - A3` сюда не попадает.
SPACED_SUFFIX = r'(?:\s+[-%s]\s*|[-%s]\s+)[A-ZА-ЯЁ]+(?!\w)' % (DASHLIKE, DASHLIKE)
REPO_TOKEN = r'(?:^|[;,]\s*|\s)(kacho-workspace|воркспейс|corelib|kacho|kaname|GitHub)\s*(?:·|\||$)'


class Refusal(Exception):
    """Код 1: вход не описывает ациклический граф полос."""


class EmptyWalk(Exception):
    """Код 2: прочитано ноль полос."""


def cells(line):
    line = line.replace('\\|', '\x00')
    return [c.strip().replace('\x00', '|') for c in line.strip().strip('|').split('|')]


def parse_file(path, notes):
    name = os.path.basename(os.path.dirname(os.path.abspath(path))).replace('issue-', '')
    with open(path, encoding='utf-8') as fh:
        txt = fh.read().split('\n')
    start = next((i for i, l in enumerate(txt) if re.match(r'^## .*Полосы', l)), None)
    if start is None:
        raise Refusal('%s: раздела «## … Полосы» нет — маршрут работ не опознан' % path)
    end = next((i for i, l in enumerate(txt) if i > start and l.startswith('## ')), len(txt))
    lanes, hdr, stage = [], None, None
    stages = collections.defaultdict(list)
    tables = 0
    for off, l in enumerate(txt[start:end]):
        if l.startswith('### '):
            m = re.search(r'\bS(\d+)\b', l)
            stage = ('S' + m.group(1)) if m else None
        if not l.startswith('|'):
            # Любая строка вне таблицы — пустая тоже — таблицу кончает: строка `|…|`
            # после неё без своего заголовка в разметке не таблица, а абзац.
            hdr = None
            continue
        c = cells(l)
        if 'исполнитель' in c:
            hdr = c
            tables += 1
            if 'зависит от' not in c:
                notes.append('%s:%d таблица без колонки «зависит от» — её полосы считаются '
                             'независимыми' % (path, start + off + 1))
            continue
        if set(''.join(c)) <= set('-: '):
            continue
        if hdr is None or len(c) != len(hdr):
            raise Refusal('%s:%d: строка таблицы полос шириной %d при заголовке %s — разбор '
                          'по колонкам недостоверен' % (path, start + off + 1, len(c),
                                                        len(hdr) if hdr else 'нет'))
        d = dict(zip(hdr, c))
        d['_id'] = c[0]
        d['_line'] = start + off + 1
        lanes.append(d)
        if stage:
            stages[stage].append(c[0])
    if not lanes:
        raise EmptyWalk('%s: в разделе «Полосы» ноль полос (таблиц %d) — прочитано ничего'
                        % (path, tables))
    ids = [d['_id'] for d in lanes]
    dup = sorted(x for x, n in collections.Counter(ids).items() if n > 1)
    if dup:
        raise Refusal('%s: id полос повторяются %s — ребро неадресуемо' % (path, dup))
    return name, lanes, stages, tables


def build(paths, semantic_rows, edges_mode, notes):
    L = {}
    census = []
    ext_of = {}
    for path in paths:
        name, lanes, stages, tables = parse_file(path, notes)
        if any(x['issue'] == name for x in L.values()):
            raise Refusal('%s: под-фаза %s уже прочитана из другого файла' % (path, name))
        census.append((name, path, tables, len(lanes)))
        ids = [d['_id'] for d in lanes]
        idset = set(ids)
        order = {x: i for i, x in enumerate(ids)}

        def resolve(t, n):
            """Ссылка → (полосы, раскрытие стадии?); (None, False) — не полоса файла.
            Суффикс, общий нескольким полосам, — отказ: ребро неадресуемо."""
            if t in idset:
                return [t], False
            suf = [x for x in ids if x.endswith('-' + t)]
            if len(suf) > 1:
                raise Refusal('%s:%s: ссылка «%s» по суффиксу неоднозначна — %s; ребро '
                              'неадресуемо' % (name, n, t, ', '.join(suf)))
            if suf:
                return suf, False
            if t in stages:
                return list(stages[t]), True
            return None, False

        def known(t):
            # Для заметки о пояснении: ссылка ли это на полосу — без отказа.
            return t in idset or t in stages or any(x.endswith('-' + t) for x in ids)

        def span(a, b, n):
            # Диапазон `A1–A3` / `N0…N4`: общий префикс, правая граница входит.
            # `S2-A1…A3`: префикс стадии у левой границы переносится на правую.
            # Разные префиксы — не диапазон (None): две ссылки.
            pa, pb = re.fullmatch(r'(.*?)(\d+)', a), re.fullmatch(r'(.*?)(\d+)', b)
            if pa is None or pb is None:
                # Граница без номера на конце (`X2-F`) — не диапазон: две ссылки.
                return None
            if pa.group(1) == pb.group(1):
                pre = pa.group(1)
            elif pa.group(1).endswith('-' + pb.group(1)):
                pre = pa.group(1)
            else:
                return None
            lo, hi = int(pa.group(2)), int(pb.group(2))
            if lo > hi:
                raise Refusal('%s:%s: диапазон «%s–%s» обратный — какие полосы в нём, не '
                              'определено' % (name, n, a, b))
            return [pre + str(k) for k in range(lo, hi + 1)]

        def whole(s, orig, n, line, cell):
            # Fail-closed разбора (Д43): ячейка, которую разборщик не прочёл
            # ЦЕЛИКОМ, — ОТКАЗ с координатой, а не ребро, выпавшее молча. Ссылка на
            # полосу всегда несёт цифру; вне `кода`, «фразы» и номера окна `(0)`
            # цифра обязана лежать внутри целого id (или имени под-фазы `NTF-1`), а
            # id — не быть приклеен к букве, цифре или «-буква» (`X2-Fx`, `a1`, `A1b`).
            # `s` уже нормализован `dashes()` знак-в-знак; фрагменты отказа
            # берутся из `orig` по тем же позициям — автор видит свою запись.
            t = re.sub(r'`[^`]*`|«[^»]*»|\(\d+\)', lambda m: ' ' * len(m.group(0)), s)
            t = re.sub(PHASE, lambda m: ' ' * len(m.group(0)), t)
            bad, amb = [], []
            for m in re.finditer(ID, t):
                pre = t[m.start() - 1:m.start()]
                post = t[m.end():m.end() + 2]
                if re.match(r'\w', pre) or re.match(r'\w|-\w', post):
                    bad.append(orig[max(0, m.start() - 1):m.end() + 2].strip())
                sp = re.match(SPACED_SUFFIX, t[m.end():])
                if sp:
                    amb.append(orig[m.start():m.end() + sp.end()])
                    t = t[:m.end()] + ' ' * sp.end() + t[m.end() + sp.end():]
                t = t[:m.start()] + ' ' * (m.end() - m.start()) + t[m.end():]
            if amb:
                raise Refusal('%s:%d: %s: ячейка «зависит от» «%s» неоднозначна — фрагмент %s: '
                              'пробел между id и «-буква», суффикс это или отдельное слово, '
                              'не определено; ребро потерялось бы молча'
                              % (path, line, n, cell, ', '.join('«%s»' % b for b in amb)))
            bad += [orig[m.start():m.end()] for m in re.finditer(r'\S*\d\S*', t)]
            if bad:
                raise Refusal('%s:%d: %s: ячейка «зависит от» «%s» не распознана целиком — '
                              'фрагмент %s не стал ни ссылкой, ни пояснением; ребро '
                              'потерялось бы молча' % (path, line, n, cell,
                                                       ', '.join('«%s»' % b for b in bad)))

        def expand(cell, n, line):
            explicit, alias, ext = set(), set(), []

            def take(t):
                # Каждая ссылка — и член диапазона тоже — узнаётся одинаково: id,
                # суффикс id, стадия; не узнанная — внешняя (жетон ведомости).
                res, is_alias = resolve(t, n)
                if res:
                    (alias if is_alias else explicit).update(res)
                else:
                    ext.append(t)

            # Список ссылок — до первой «;»; дальше пояснение («N5 сюда не входит —
            # она зависит от C4»), и его id рёбрами не становятся. Отброшенное
            # печатается заметкой, а не исчезает молча.
            raw = cell
            orig = raw.partition(';')[0]
            cell = dashes(raw)
            s, _, tail = cell.partition(';')
            whole(s, orig, n, line, raw)
            toks = list(re.finditer(ID, s))
            i = 0
            while i < len(toks):
                a = toks[i].group(0)
                r = None
                if (i + 1 < len(toks)
                        and re.fullmatch(r'\s*[–…-]\s*', s[toks[i].end():toks[i + 1].start()])):
                    r = span(a, toks[i + 1].group(0), n)
                if r is not None:
                    for t in r:
                        take(t)
                    i += 2
                    continue
                m = re.fullmatch(r'(.*?\d+)-(.*?\d+)', a)
                if m and resolve(a, n)[0] is None:
                    # ID читает `S1-S3` и `X1-Y2` как один id с суффиксом. Полосы с
                    # таким id нет: это дефисный диапазон либо, при разных
                    # префиксах, две ссылки — как через тире.
                    for t in span(m.group(1), m.group(2), n) or m.groups():
                        take(t)
                else:
                    take(a)
                i += 1
            if 'S-ярус' in s:
                alias.update(x for x in ids if re.fullmatch(r'S\d+', x))
            ext += ['«%s»' % q for q in re.findall(r'«([^»]+)»', s)]
            ext += re.findall(PHASE, re.sub(r'`[^`]*`|«[^»]*»', ' ', s))
            return explicit, alias, ext, s, tail.strip()

        deps, alias_deps, raw_of = {}, {}, {}
        for d in lanes:
            n = d['_id']
            e, a, x, head, tail = expand(d.get('зависит от', ''), n, d['_line'])
            deps[n] = {p for p in e | a if p != n}
            alias_deps[n] = {p for p in a - e if p != n}
            ext_of[(name, n)] = x
            raw_of[n] = head
            if tail:
                named = [t for t in re.findall(ID, tail) if known(t)]
                notes.append('%s:%s после «;» — пояснение, рёбер не даёт: %s'
                             % (name, n, ', '.join(named) or 'ссылок на полосы нет'))

        def reaches(a, b):
            st, seen = [a], set()
            while st:
                u = st.pop()
                if u == b:
                    return True
                if u in seen:
                    continue
                seen.add(u)
                st += deps[u]
            return False

        for n in ids:
            for p in sorted(alias_deps[n], key=order.get):
                if reaches(p, n):
                    deps[n].discard(p)
                    notes.append('%s:%s ребро от %s снято: раскрытие стадии замкнуло бы цикл'
                                 % (name, n, p))
        for d in lanes:
            n = d['_id']
            a = re.findall(r'`([a-z-]+)`', d.get('исполнитель', ''))
            ex = a[0] if a else d.get('исполнитель', '—')
            if 'пути (kacho)' in d:
                repos = {'kacho'}
            elif 'репозиторий · пути' in d:
                repos = set()
                for m in re.findall(REPO_TOKEN, d['репозиторий · пути']):
                    repos.add({'kacho-workspace': 'workspace', 'воркспейс': 'workspace'}.get(m, m))
                if not repos:
                    repos = {'—'}
            else:
                repos = {'workspace'} if ex == 'vault-scribe' else {'—'}
                notes.append('%s:%s нет колонки репозитория -> %s' % (name, n, '+'.join(repos)))
            sz = d.get('размер')
            if sz not in UNIT:
                notes.append('%s:%s размер «%s» не S/M/L -> S' % (name, n, sz or ''))
                sz = 'S'
            L[name + ':' + n] = dict(issue=name, id=n, ex=ex, repo='+'.join(sorted(repos)),
                                     multi=len(repos) > 1, size=sz,
                                     deps={name + ':' + p for p in deps[n]},
                                     ext=ext_of[(name, n)], raw=raw_of[n],
                                     dispatcher=(ex == 'диспетчер'))
    tasks = {x['issue'] for x in L.values()}
    for src, token, dst in semantic_rows:
        if src not in tasks or dst not in tasks:
            raise Refusal('ведомость: строка «%s %s %s» — под-фазы %s нет во входе'
                          % (src, token, dst, sorted({src, dst} - tasks)))
        carriers = [g for g, x in L.items() if x['issue'] == src and carries(x, token)]
        if not carriers:
            raise Refusal('ведомость: строка «%s %s %s» без полосы-носителя — связывать нечего'
                          % (src, token, dst))
        if edges_mode == 'A' and src != dst:
            continue
        # Жетоны `Е<n>` нумеруются в каждом файле заново: исключать носителей
        # имеет смысл только внутри своей под-фазы.
        targets = {g for g, x in L.items()
                   if x['issue'] == dst and not (src == dst and carries(x, token))}
        for g in carriers:
            L[g]['deps'] |= targets - {g}
        notes.append('%s: %s %s -> все полосы %s (%d), носителей %d'
                     % (edges_mode, src, token, dst, len(targets), len(carriers)))
    # Ссылка, не узнанная полосой файла и не названная строкой ведомости своей
    # под-фазы (в любом режиме), ребра не даёт — и это печатается: опечатка в id и
    # жетон без строки неотличимы от законной внешней ссылки иначе как глазами.
    covered = collections.defaultdict(set)
    for src, token, _ in semantic_rows:
        covered[src].add(token.strip('«»'))
    for g, x in L.items():
        loose = [t for t in x['ext'] if t.strip('«»') not in covered[x['issue']]]
        if loose:
            notes.append('%s ссылки без полосы в файле и без строки ведомости — рёбер не '
                         'дают: %s' % (g, ', '.join(loose)))
    return L, census


def carries(x, token):
    # Жетон — внешняя ссылка (`Е5`) либо фраза: «ёлочки» в ведомости необязательны,
    # в ячейке фраза может стоять без них («посадка линий»).
    return token in x['ext'] or token.strip('«»') in x['raw']


def find_cycle(nodes, succ_of):
    color, stack = {}, []

    def dfs(u):
        color[u] = 1
        stack.append(u)
        for v in sorted(succ_of(u)):
            if color.get(v) == 1:
                return stack[stack.index(v):] + [v]
            if v not in color:
                c = dfs(v)
                if c:
                    return c
        stack.pop()
        color[u] = 2
        return None

    for u in sorted(nodes):
        if u not in color:
            c = dfs(u)
            if c:
                return c
    return None


def plan(L, pack_mode, minutes, review, notes):
    G = list(L)
    pos = {g: i for i, g in enumerate(G)}
    cyc = find_cycle(G, lambda g: L[g]['deps'])
    if cyc:
        raise Refusal('цикл в графе полос: %s' % ' <- '.join(cyc))
    succ = collections.defaultdict(list)
    indeg = {g: len(L[g]['deps']) for g in G}
    for g in G:
        for p in L[g]['deps']:
            succ[p].append(g)
    h = [(pos[g], g) for g in G if indeg[g] == 0]
    heapq.heapify(h)
    topo = []
    while h:
        _, g = heapq.heappop(h)
        topo.append(g)
        for s in succ[g]:
            indeg[s] -= 1
            if indeg[s] == 0:
                heapq.heappush(h, (pos[s], s))

    def dur(g):
        return 0 if L[g]['dispatcher'] else minutes[L[g]['size']]

    est = {}
    for g in topo:
        est[g] = max([est[p] + dur(p) for p in L[g]['deps']], default=0)

    pk, P = {}, {}
    nid = [0]

    def pdeps(q):
        return {pk[p] for g in P[q] for p in L[g]['deps'] if p in pk and pk[p] != q}

    def units(q):
        return sum(UNIT[L[g]['size']] for g in P[q])

    def acyclic():
        return find_cycle(list(P), pdeps) is None

    def newp(g):
        nid[0] += 1
        q = 'P%03d' % nid[0]
        P[q] = [g]
        pk[g] = q

    refused = collections.Counter()
    # fa-a2: цепочка — подряд зависимые полосы одного исполнителя и репозитория.
    for g in topo:
        x = L[g]
        placed = False
        if not x['multi'] and not x['dispatcher']:
            for p in sorted(x['deps'], key=pos.get):
                q = pk[p]
                y = L[p]
                if (y['issue'] == x['issue'] and y['ex'] == x['ex'] and y['repo'] == x['repo']
                        and not y['multi'] and P[q][-1] == p
                        and all(L[m]['ex'] == x['ex'] and L[m]['repo'] == x['repo'] for m in P[q])
                        and units(q) + UNIT[x['size']] <= CAP_UNITS):
                    P[q].append(g)
                    pk[g] = q
                    if acyclic():
                        placed = True
                        break
                    P[q].pop()
                    del pk[g]
                    refused['цепочка: цикл пакетов'] += 1
        if not placed:
            newp(g)
    chains = sum(1 for q in P if len(P[q]) > 1)

    def pdur(q):
        # Одна длительность пакета на guard, путь и расписание. До ws#884 путь для
        # guard считался с ревью и на пакете диспетчера, а итоговый — без него:
        # «путь до склейки» печатался на 25 мин длиннее, а guard сравнивал склейку
        # с завышенной базой и пропускал удлинение пути меньше одного ревью.
        return sum(dur(g) for g in P[q]) + (0 if all(L[g]['dispatcher'] for g in P[q])
                                            else review)

    def cp_now():
        D0 = {q: pdur(q) for q in P}
        f = {}

        def e(q):
            if q not in f:
                f[q] = D0[q] + max([e(p) for p in pdeps(q)], default=0)
            return f[q]
        return max(e(q) for q in P)

    def reach(a, b):
        st, seen = [a], set()
        while st:
            u = st.pop()
            if u == b:
                return True
            if u in seen:
                continue
            seen.add(u)
            st += list(pdeps(u))
        return False

    # fa-a3: однотипные независимые пакеты одного исполнителя и репозитория.
    def key(q):
        return (L[P[q][0]]['ex'], L[P[q][0]]['repo'])

    cands = [q for q in P if L[P[q][0]]['ex'] in SAME_KIND and not L[P[q][0]]['multi']]
    cands.sort(key=lambda q: (key(q), min(est[g] for g in P[q]), pos[P[q][0]]))
    base = cp_now()
    cp_chain_only = base
    merged = 0
    for i, q in enumerate(cands):
        if q not in P:
            continue
        for t in cands[:i]:
            if t not in P or key(t) != key(q):
                continue
            if units(t) + units(q) > CAP_UNITS or reach(t, q) or reach(q, t):
                continue
            saved = P[q]
            P[t] = P[t] + saved
            del P[q]
            for g in saved:
                pk[g] = t
            if acyclic() and (pack_mode == 'literal' or cp_now() <= base):
                merged += 1
                base = cp_now()
                break
            del P[t][-len(saved):]
            P[q] = saved
            for g in saved:
                pk[g] = q
            refused['склейка: цикл или удлинение пути'] += 1

    D = {q: pdur(q) for q in P}
    PD = {q: pdeps(q) for q in P}
    PS = collections.defaultdict(set)
    for q in P:
        for p in PD[q]:
            PS[p].add(q)
    bl, fin = {}, {}

    def blev(q):
        if q not in bl:
            bl[q] = D[q] + max([blev(s) for s in PS[q]], default=0)
        return bl[q]

    def eft(q):
        if q not in fin:
            fin[q] = D[q] + max([eft(p) for p in PD[q]], default=0)
        return fin[q]

    for q in P:
        blev(q)
        eft(q)
    cp = max(fin.values())
    path = [max(sorted(P), key=eft)]
    while PD[path[-1]]:
        path.append(max(sorted(PD[path[-1]]), key=eft))
    path.reverse()
    return dict(P=P, D=D, PD=PD, PS=PS, bl=bl, cp=cp, path=path, units=units, chains=chains,
                merged=merged, refused=refused, cp_chain_only=cp_chain_only)


def schedule(r, k):
    """Список готовых по bottom-level; освободился слот — стартует следующий
    готовый пакет, барьера волны нет (fa-a6)."""
    P, D, PD, PS, bl = r['P'], r['D'], r['PD'], r['PS'], r['bl']
    t, busy, free = 0, 0, k
    running, started, done = [], set(), set()
    ready = {q for q in P if not PD[q]}
    rem = set(P)
    while rem:
        for q in sorted(ready, key=lambda q: (-bl[q], q)):
            if D[q] == 0:
                started.add(q)
                heapq.heappush(running, (t, q))
                ready.discard(q)
                continue
            if free == 0:
                break
            free -= 1
            started.add(q)
            busy += D[q]
            heapq.heappush(running, (t + D[q], q))
            ready.discard(q)
        te, q = heapq.heappop(running)
        t = te
        batch = [q]
        while running and running[0][0] == t:
            batch.append(heapq.heappop(running)[1])
        for q in batch:
            if D[q] > 0:
                free += 1
            rem.discard(q)
            done.add(q)
            for s in PS[q]:
                if PD[s] <= done and s not in started:
                    ready.add(s)
    return t, busy


def hours(m):
    return '%.2f ч' % (m / 60)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('tasks', nargs='*')
    ap.add_argument('--edges', choices=['A', 'B'], default='A')
    ap.add_argument('--pack', choices=['literal', 'guard'], default='guard')
    ap.add_argument('--semantic', help='TSV смысловых рёбер (обязателен для --edges B)')
    ap.add_argument('--slots', default='6,7,8')
    ap.add_argument('--minutes', default='S=15,M=25,L=45')
    ap.add_argument('--review', type=int, default=25)
    ap.add_argument('--out', help='куда записать таблицу пакетов (TSV); без него — в вывод')
    a = ap.parse_args(argv)
    notes = []
    try:
        minutes = {kv.split('=')[0]: int(kv.split('=')[1]) for kv in a.minutes.split(',')}
        if set(minutes) != set(UNIT):
            raise Refusal('--minutes обязан назвать ровно S, M, L')
        if min(minutes.values()) < 0 or a.review < 0:
            raise Refusal('--minutes и --review не бывают отрицательными')
        slots = [int(s) for s in a.slots.split(',')]
        if min(slots) < 1:
            # Ноль слотов не запускает ни одного пакета: расписание не кончилось бы.
            raise Refusal('--slots — число слотов от 1, названо %s' % a.slots)
        if not a.tasks:
            raise EmptyWalk('входных tasks.md ноль — прочитано ничего')
        rows = []
        if a.edges == 'B' and not a.semantic:
            raise Refusal('--edges B без --semantic: смысловых рёбер не из чего взять')
        if a.semantic:
            with open(a.semantic, encoding='utf-8') as fh:
                for ln, l in enumerate(fh, 1):
                    if not l.strip() or l.lstrip().startswith('#'):
                        continue
                    f = [x.strip() for x in l.rstrip('\n').split('\t')]
                    if len(f) != 3 or not all(f):
                        raise Refusal('%s:%d: строка ведомости не из трёх полей' % (a.semantic, ln))
                    rows.append(tuple(f))
            if not rows:
                raise EmptyWalk('%s: в ведомости ноль строк — режим B вырожден в A' % a.semantic)
        L, census = build(a.tasks, rows, a.edges, notes)
        r = plan(L, a.pack, minutes, a.review, notes)
    except Refusal as e:
        print('ОТКАЗ — %s' % e)
        return 1
    except EmptyWalk as e:
        print('ПУСТОЙ ОБХОД — %s; вердикта нет' % e)
        return 2
    except (OSError, ValueError) as e:
        print('ОТКАЗ — вход не читается: %s' % e)
        return 1

    P, D = r['P'], r['D']
    for name, path, tables, n in census:
        print('перепись: %s — %s: таблиц %d, полос %d' % (name, path, tables, n))
    worked = [q for q in P if D[q] > 0]
    tot = sum(D.values())
    print('режим: рёбра %s, склейка %s; длительности %s, ревью %d мин на пакет'
          % (a.edges, a.pack, a.minutes, a.review))
    print('полос: %d; пакетов: %d; цепочек (>1 полосы): %d; склеек: %d; отказов склейки: %s'
          % (len(L), len(P), r['chains'], r['merged'], dict(r['refused']) or 0))
    print('агент-часы: %s (%d мин; исполнение %d + ревью %d)'
          % (hours(tot), tot, tot - a.review * len(worked), a.review * len(worked)))
    print('критический путь: %d мин (%s), пакетов %d: %s'
          % (r['cp'], hours(r['cp']), len(r['path']),
             ' -> '.join('%s[%s]' % (q, '+'.join(P[q])) for q in r['path'])))
    print('критический путь до склейки: %d мин' % r['cp_chain_only'])
    for k in slots:
        ms, busy = schedule(r, k)
        print('слотов %d: срок %d мин (%s); загрузка %.1f%%' % (k, ms, hours(ms),
                                                               busy / (k * ms) * 100 if ms else 0))
    mink = next((k for k in range(1, 65) if schedule(r, k)[0] == r['cp']), None)
    print('слотов до срока = пути: %s' % (mink if mink else 'не достигается до 64'))
    for n in notes:
        print('заметка: %s' % n)
    lines = ['id\tполосы\tисполнитель\tрепозиторий\tединицы\tмин\tbottom-level_мин\tзависимости']
    for q in sorted(P):
        x = L[P[q][0]]
        lines.append('\t'.join([q, ' '.join(P[q]), x['ex'], x['repo'], str(r['units'](q)),
                                str(D[q]), str(r['bl'][q]), ' '.join(sorted(r['PD'][q])) or '—']))
    if a.out:
        with open(a.out, 'w', encoding='utf-8') as fh:
            fh.write('\n'.join(lines) + '\n')
        print('таблица: %s (%d строк)' % (a.out, len(P)))
    else:
        print('\n'.join(lines))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
