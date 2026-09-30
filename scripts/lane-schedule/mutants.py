#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""mutants — набор `inject.sh` обязан КРАСНЕТЬ на однофактной порче каждого
решения `lane-schedule.py`.

Зачем: приёмка ws#884 (check-verifier, ⛔ на fc25f8038) нашла две порчи
инструмента — граница guard `<=` → `<` и приоритет расписания по id вместо
остатка пути, — на которых `inject.sh` оставался зелёным 21/21, а числа на
реальных маршрутах менялись (пакетов 113 → 127; срок при 6 слотах 1075 → 1275
мин — замер приёмки на fc25f8038, notify 2915/2917/2919/2925). Второй возврат
(⛔ на a1b230728) нашёл ещё 13 решений и 4 отказа входа, на которых набор был
зелёным 47/47; при их разборе нашлось, что id со стадией (`S1-A1`) читался как
диапазон и терялся — внутренних рёбер 2919 не было, и те числа занижены. Перечень ниже — по РЕШЕНИЮ инструмента, а
не по найденным местам; у порчи в описании в скобках — проба `inject.sh`,
которая её держит. Чем перечень полон: разведочный прогон всех однофактных
порч разобранного дерева (сравнение, and/or, not, условие if, целая константа,
max/min, +/−) — выживших, кроме заведомо равносильных (`EQUIVALENT`) и печати
без решения, нет; перечень держит решения, а разведка — их полноту на момент
правки. Новое решение инструмента без строки здесь — та же дыра заново.

КАК: порча — точная замена фрагмента исходника копии инструмента. Копия
кладётся во временный каталог, `inject.sh` гонится против неё через
`LANE_SCHEDULE_TOOL`. Порча УБИТА, если набор вышел кодом 1 и напечатал хотя
бы одну строку «ПРОВАЛЕНО» (красное названо пробой, а не обрывом набора).

ПРЕДПОСЫЛКИ (их отказ — код 1 харнесса, а не «порча выжила»):
  - контроль: набор против НЕиспорченной копии зелёный (код 0) — иначе
    красное порчи неотличимо от красного набора;
  - фрагмент порчи встречается в исходнике РОВНО один раз — иначе порча
    устарела вместе с правкой инструмента и молча перестала что-либо портить;
  - порча меняет разобранное дерево (`ast.dump`), а не комментарий или
    пробел — иначе «выжила» значило бы «ничего не изменила».

ИСХОДЫ: 0 — все порчи убиты; 1 — выжила хоть одна порча либо отказала
предпосылка; 2 — порч ноль (перечень пуст — проверено ничего).

Порчи, заведомо РАВНОСИЛЬНЫЕ исходнику, в перечень не входят — у них нет
входа, на котором они отличимы (см. `EQUIVALENT` ниже, с доводом у каждой).
"""
import ast
import concurrent.futures
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'lane-schedule.py')
SUITE = os.path.join(HERE, 'inject.sh')
# Параллельных прогонов набора: каждый — bash и python на секунды, память — десятки МБ.
WORKERS = min(4, os.cpu_count() or 1)

# (имя, решение, фрагмент исходника, замена)
MUTANTS = [
    # ── граница guard ────────────────────────────────────────────────────────
    ('guard-strict', 'guard: склейка допустима при пути РАВНОМ базе',
     "cp_now() <= base", "cp_now() < base"),
    ('guard-off', 'guard: склейка проверяется на удлинение пути',
     "pack_mode == 'literal' or cp_now()", "True or cp_now()"),
    # ── счёт единиц ──────────────────────────────────────────────────────────
    ('unit-L-1', 'L весит 2 единицы', "UNIT = {'S': 1, 'M': 1, 'L': 2}",
     "UNIT = {'S': 1, 'M': 1, 'L': 1}"),
    ('unit-M-2', 'M весит 1 единицу', "UNIT = {'S': 1, 'M': 1, 'L': 2}",
     "UNIT = {'S': 1, 'M': 2, 'L': 2}"),
    ('cap-3', 'предел пакета 4 единицы', "CAP_UNITS = 4", "CAP_UNITS = 3"),
    ('cap-5', 'предел пакета 4 единицы', "CAP_UNITS = 4", "CAP_UNITS = 5"),
    ('chain-cap-strict', 'цепочка допустима РОВНО на пределе',
     "units(q) + UNIT[x['size']] <= CAP_UNITS", "units(q) + UNIT[x['size']] < CAP_UNITS"),
    ('merge-cap-strict', 'склейка допустима РОВНО на пределе',
     "units(t) + units(q) > CAP_UNITS", "units(t) + units(q) >= CAP_UNITS"),
    # ── прибавка ревью ───────────────────────────────────────────────────────
    ('review-dropped', 'ревью прибавляется к пакету',
     "                                            else review)",
     "                                            else 0)"),
    ('review-on-dispatcher', 'пакет диспетчера ревью не несёт',
     "(0 if all(L[g]['dispatcher'] for g in P[q])", "(review if all(L[g]['dispatcher'] for g in P[q])"),
    ('guard-base-own-duration', 'guard считает путь той же длительностью пакета, что итог',
     "        D0 = {q: pdur(q) for q in P}",
     "        D0 = {q: sum(dur(g) for g in P[q]) + review for q in P}"),
    ('review-per-lane', 'ревью — одно на ПАКЕТ, не на полосу',
     "                                            else review)",
     "                                            else review * len(P[q]))"),
    # ── межфазные рёбра ведомости ────────────────────────────────────────────
    ('edges-A-takes-cross', 'режим A не берёт межфазных строк',
     "if edges_mode == 'A' and src != dst:", "if False:"),
    ('edges-A-drops-intra', 'режим A берёт внутризадачные строки',
     "if edges_mode == 'A' and src != dst:", "if edges_mode == 'A':"),
    ('edges-target-wrong-phase', 'цель строки — полосы под-фазы-цели',
     "if x['issue'] == dst and not", "if x['issue'] == src and not"),
    ('edges-exclude-dst-carriers', 'носители исключаются только внутри своей под-фазы',
     "not (src == dst and carries(x, token))", "not carries(x, token)"),
    ('edges-keep-intra-carriers', 'внутри под-фазы носители друг друга не ждут',
     "not (src == dst and carries(x, token))", "True"),
    ('edges-phrase-in-cell', 'фраза-жетон узнаётся в ячейке без «ёлочек»',
     "return token in x['ext'] or token.strip('«»') in x['raw']",
     "return token in x['ext']"),
    ('edges-rows-dropped', 'строки ведомости дают рёбра',
     "            L[g]['deps'] |= targets - {g}", "            pass"),
    # ── поиск цикла ──────────────────────────────────────────────────────────
    ('cycle-never', 'цикл явных рёбер ищется',
     "            if color.get(v) == 1:", "            if False:"),
    ('cycle-on-finished', 'цикл — возврат в узел НА стеке, а не в пройденный',
     "            if color.get(v) == 1:", "            if color.get(v) == 2:"),
    ('stage-edge-kept', 'ребро раскрытия стадии, замыкающее цикл, снимается',
     "                if reaches(p, n):", "                if False:"),
    ('chain-no-cycle-check', 'цепочка не создаёт цикла пакетов',
     "                    if acyclic():\n                        placed = True",
     "                    if True:\n                        placed = True"),
    ('merge-dependent', 'склеиваются только НЕЗАВИСИМЫЕ пакеты',
     " or reach(t, q) or reach(q, t):", ":"),
    ('chain-cross-phase', 'цепочка — только внутри одной под-фазы',
     "if (y['issue'] == x['issue'] and y['ex']", "if (y['ex']"),
    # ── код пустого обхода ───────────────────────────────────────────────────
    ('empty-code-0', 'пустой обход — код 2', "        return 2\n", "        return 0\n"),
    ('empty-file-skipped', 'файл с нулём полос — пустой обход, даже среди непустых',
     "    if not lanes:\n        raise EmptyWalk(", "    if False:\n        raise EmptyWalk("),
    ('empty-ledger-is-A', 'пустая ведомость — пустой обход',
     "            if not rows:\n", "            if False:\n"),
    ('no-deps-column-silent', 'таблица без «зависит от» названа заметкой',
     "            if 'зависит от' not in c:\n", "            if False:\n"),
    # ── срок при N слотах ────────────────────────────────────────────────────
    ('sched-by-id', 'готовый пакет с наибольшим остатком пути стартует первым',
     "sorted(ready, key=lambda q: (-bl[q], q))", "sorted(ready, key=lambda q: (q,))"),
    ('sched-bl-no-self', 'остаток пути включает сам пакет',
     "            bl[q] = D[q] + max(", "            bl[q] = max("),
    ('sched-extra-slot', 'слотов ровно k', "    t, busy, free = 0, 0, k\n",
     "    t, busy, free = 0, 0, k + 1\n"),
    ('sched-dispatcher-frees', 'пакет диспетчера слота не освобождает',
     "            if D[q] > 0:\n                free += 1", "            if True:\n                free += 1"),
    ('sched-dispatcher-takes-slot', 'пакет диспетчера слота не занимает',
     "            if D[q] == 0:\n                started.add(q)", "            if False:\n                started.add(q)"),
    # ── второй возврат ws#884 (⛔ на a1b230728): решения, на которых набор был
    # зелёным 47/47; проба у каждой названа в `inject.sh` рядом с числом ──────
    # цепочка (fa-a2)
    ('chain-not-tail', 'цепочка — «подряд»: полоса продолжает пакет, чей хвост она ждёт [P1]',
     " and P[q][-1] == p\n", "\n"),
    ('chain-pred-order', 'из нескольких хвостов-предшественников — первый по файлу [P2]',
     "for p in sorted(x['deps'], key=pos.get):", "for p in sorted(x['deps'], key=pos.get, reverse=True):"),
    ('chain-dispatcher', 'полосы диспетчера в цепочку не идут [P3]',
     "if not x['multi'] and not x['dispatcher']:", "if not x['multi']:"),
    # склейка (fa-a3) и репозиторий
    ('merge-other-repo', 'склейка — по исполнителю И репозиторию [W1]',
     "return (L[P[q][0]]['ex'], L[P[q][0]]['repo'])", "return (L[P[q][0]]['ex'],)"),
    ('repo-workspace-alias', 'kacho-workspace и воркспейс — один репозиторий [W1]',
     "{'kacho-workspace': 'workspace', 'воркспейс': 'workspace'}.get(m, m)", "m"),
    ('repo-unknown-dash', 'неузнанный репозиторий — «—» [W1]',
     "                if not repos:\n", "                if False:\n"),
    ('multi-gt2', 'полоса на двух репозиториях — multi [W2]',
     "multi=len(repos) > 1", "multi=len(repos) > 2"),
    ('merge-multi', 'полоса на нескольких репозиториях не склеивается [W2]',
     " and not L[P[q][0]]['multi']]", "]"),
    ('merge-order-est', 'кандидаты склейки — по раннему старту [W3]',
     "(key(q), min(est[g] for g in P[q]), pos[P[q][0]])", "(key(q), pos[P[q][0]])"),
    ('repo-kacho-column', 'колонка «пути (kacho)» — репозиторий kacho [T1]',
     "if 'пути (kacho)' in d:", "if False:"),
    ('repo-vault-workspace', 'vault-scribe без колонки репозитория — workspace [T2]',
     "repos = {'workspace'} if ex == 'vault-scribe' else {'—'}", "repos = {'—'}"),
    # ссылки в «зависит от»
    ('range-open-right', 'диапазон включает правую границу [D1]',
     "for k in range(int(pa.group(2)), int(pb.group(2)) + 1)]",
     "for k in range(int(pa.group(2)), int(pb.group(2)))]"),
    ('range-ellipsis', 'разделитель диапазона — «–», «…» и «-» [D2]',
     r"re.fullmatch(r'\s*[–…-]\s*'", r"re.fullmatch(r'\s*[–-]\s*'"),
    ('range-stage-prefix', 'префикс стадии левой границы переносится на правую [D2]',
     "elif pa.group(1).endswith('-' + pb.group(1)):", "elif False:"),
    ('range-hyphen-token', 'дефисный диапазон `S1-S3`, прочитанный как один id [D9]',
     "r, step = (span(m.group(1), m.group(2)) if m else None), 1", "r, step = None, 1"),
    ('suffix-off', 'ссылка по суффиксу id (`A1` → `S2-A1`) [D3]',
     "suf = [x for x in ids if x.endswith('-' + t)]", "suf = []"),
    ('stage-inherit', 'заголовок без S<n> стадию не продолжает [D4]',
     "stage = ('S' + m.group(1)) if m else None", "stage = ('S' + m.group(1)) if m else stage"),
    ('stage-off', 'ссылка S<n> — все полосы стадии [D4]',
     "            if t in stages:\n", "            if False:\n"),
    ('s-tier-off', '«S-ярус» — все полосы с id S<n> [D5]',
     "if 'S-ярус' in s:", "if False:"),
    ('semicolon-off', 'после «;» — пояснение, не рёбра [D6]',
     "s, _, tail = cell.partition(';')", "s, tail = cell, ''"),
    ('semicolon-silent', 'отброшенное пояснение названо заметкой [D6]',
     "            if tail:\n", "            if False:\n"),
    ('alias-minus-explicit', 'явное ребро не снимается как раскрытие стадии [D8]',
     "alias_deps[n] = {p for p in a - e if p != n}", "alias_deps[n] = {p for p in a if p != n}"),
    ('size-default-L', 'размер вне S/M/L — S [Z2]', "                sz = 'S'\n", "                sz = 'L'\n"),
    ('hdr-reset-off', 'строка после прозы без своего заголовка — отказ [R13]',
     "            hdr = None\n            continue\n", "            continue\n"),
    # отказы входа
    ('unknown-phase-off', 'строка ведомости с неизвестной под-фазой — отказ [R6]',
     "if src not in tasks or dst not in tasks:", "if False:"),
    ('ledger-width-off', 'строка ведомости не из трёх полей — отказ [R7]',
     "if len(f) != 3 or not all(f):", "if not all(f):"),
    ('ledger-hole-off', 'пустое поле ведомости — отказ [R8]',
     "if len(f) != 3 or not all(f):", "if len(f) != 3:"),
    ('phase-repeat-off', 'повтор под-фазы — отказ [R9]',
     "if any(x['issue'] == name for x in L.values()):", "if False:"),
    ('minutes-set-off', '--minutes называет ровно S, M, L [R10]',
     "if set(minutes) != set(UNIT):", "if False:"),
    ('oserr-0', 'нечитаемый вход — код 1 [R11, R12]',
     "print('ОТКАЗ — вход не читается: %s' % e)\n        return 1",
     "print('ОТКАЗ — вход не читается: %s' % e)\n        return 0"),
    # печать итогов
    ('path-end-min', 'путь кончается пакетом с наибольшим ранним финишем [Z3]',
     "path = [max(sorted(P), key=eft)]", "path = [min(sorted(P), key=eft)]"),
    ('path-pred-min', 'путь идёт к предшественнику с наибольшим ранним финишем [Z3]',
     "path.append(max(sorted(PD[path[-1]]), key=eft))", "path.append(min(sorted(PD[path[-1]]), key=eft))"),
    ('mink-from-2', 'минимум слотов ищется с 1 [Z2]', "for k in range(1, 65)", "for k in range(2, 65)"),
    ('hours-exec-no-review', 'исполнение = агент-часы минус ревью [K1b]',
     "tot - a.review * len(worked), a.review", "tot, a.review"),
    ('load-per-slot', 'загрузка — занятость k слотов за срок [K1b]',
     "busy / (k * ms) * 100", "busy / ms * 100"),
    ('cp-before-merge', 'путь до склейки печатается отдельно от итога [K3]',
     "print('критический путь до склейки: %d мин' % r['cp_chain_only'])",
     "print('критический путь до склейки: %d мин' % r['cp'])"),
    # ── разведочный прогон всех однофактных порч дерева (см. шапку): выжившие,
    # не равносильные исходнику, получили пробу и строку здесь ──────────────
    ('ready-all-preds', 'пакет готов, когда готовы ВСЕ предшественники [Q2]',
     "if PD[s] <= done and s not in started:", "if s not in started:"),
    ('bl-min', 'остаток пути — по длиннейшему преемнику [Q3]',
     "bl[q] = D[q] + max([blev(s)", "bl[q] = D[q] + min([blev(s)"),
    ('batch-finish', 'одновременные финиши освобождают слоты до выбора [Q4]',
     "while running and running[0][0] == t:", "while running and running[0][1] == t:"),
    ('est-min', 'ранний старт полосы — по ПОСЛЕДНЕМУ предшественнику [W3]',
     "est[g] = max([est[p] + dur(p)", "est[g] = min([est[p] + dur(p)"),
    ('pkg-est-latest', 'ранний старт пакета — по его первой полосе [W4]',
     "min(est[g] for g in P[q])", "max(est[g] for g in P[q])"),
    ('pos-last-lane', 'при равном старте — по месту первой полосы пакета [W5]',
     "pos[P[q][0]]))", "pos[P[q][-1]]))"),
    ('merge-t-depends-on-q', 'склеиваются только независимые — и в сторону t ← q [W6]',
     " or reach(t, q) or reach(q, t):", " or reach(q, t):"),
    ('range-no-separator', 'диапазон — только через тире, запятая — перечень [D1b]',
     "\n                        and re.fullmatch(r'\\s*[–…-]\\s*', s[toks[i].end():toks[i + 1].start()])", ""),
    ('range-sep-other-token', 'разделитель диапазона — между СОСЕДНИМИ ссылками [D1c]',
     "s[toks[i].end():toks[i + 1].start()]", "s[toks[i].end():toks[i - 1].start()]"),
    ('range-right-other-token', 'правая граница — соседняя ссылка [D1c]',
     "r = span(a, toks[i + 1].group(0))", "r = span(a, toks[i - 1].group(0))"),
    ('range-step-skip', 'после диапазона следующая ссылка читается [D1d]',
     "r, step = None, 2", "r, step = None, 3"),
    ('range-hyphen-left', 'дефисный диапазон начинается с левой границы [D9]',
     "r, step = (span(m.group(1), m.group(2))", "r, step = (span(m.group(2), m.group(2))"),
    ('range-hyphen-step', 'после дефисного диапазона следующая ссылка читается [D9b]',
     "if m else None), 1", "if m else None), 2"),
    ('range-diff-prefix', 'тире между разными префиксами — две ссылки [D10]',
     "if pa.group(1) == pb.group(1):", "if True:"),
    ('range-stage-any-prefix', 'перенос префикса — только префикса стадии левой границы [D10]',
     "elif pa.group(1).endswith('-' + pb.group(1)):", "elif True:"),
    ('fallback-only-unresolved', 'id с дефисом, который есть в файле, — ссылка, не диапазон [D11]',
     "if r is None and resolve(a)[0] is None:", "if r is None:"),
    ('range-ext-kept', 'член диапазона вне файла — внешняя ссылка [X2]',
     "(explicit.add(t) if t in idset else ext.append(t))", "explicit.add(t)"),
    ('carries-ext', 'жетон узнаётся и среди раскрытых внешних ссылок [X2]',
     "return token in x['ext'] or token.strip('«»') in x['raw']",
     "return token.strip('«»') in x['raw']"),
    ('unknown-dst', 'цель строки ведомости не из входа — отказ [R6b]',
     "if src not in tasks or dst not in tasks:", "if src not in tasks:"),
    ('reaches-no-seen', 'обход достижимости завершается на цикле [C3]',
     "                if u in seen:\n                    continue\n                seen.add(u)\n                st += deps[u]",
     "                st += deps[u]"),
    ('one-minute-frees', 'пакет в 1 мин отдаёт слот [Z4]',
     "            if D[q] > 0:\n                free += 1", "            if D[q] > 1:\n                free += 1"),
    ('one-minute-worked', 'пакет в 1 мин — работа с ревью [Z4]',
     "worked = [q for q in P if D[q] > 0]", "worked = [q for q in P if D[q] > 1]"),
    ('mink-upper', 'минимум слотов ищется до 64 включительно [S64]',
     "range(1, 65)", "range(1, 64)"),
    ('mink-over', 'за 64 — «не достигается», а не число [S65]',
     "range(1, 65)", "range(1, 66)"),
    ('mink-message', 'недостижимый минимум назван словами [S65]',
     "(mink if mink else 'не достигается до 64')", "(mink)"),
    ('out-file', '--out пишет таблицу в файл [O1]', "    if a.out:\n", "    if False:\n"),
    ('census-tables', 'перепись считает таблицы [K1]', "            tables += 1\n", "            tables += 2\n"),
    ('coord-note', 'заметка о таблице называет её строку [N1]',
     "'независимыми' % (path, start + off + 1))", "'независимыми' % (path, start + off))"),
    ('coord-refusal', 'отказ ширины называет строку [R2]',
     "% (path, start + off + 1, len(c),", "% (path, start + off, len(c),"),
    ('refusal-hdr-width', 'отказ ширины называет ширину заголовка [R2]',
     "len(hdr) if hdr else 'нет'", "'нет'"),
    ('semicolon-empty-note', 'пояснение без ссылок названо [D6]',
     "', '.join(named) or 'ссылок на полосы нет'", "', '.join(named)"),
    ('size-note-empty', 'пустой размер назван «» [T2]', "sz or ''", "sz"),
    ('executor-first', 'исполнитель — первый названный [T2]', "ex = a[0] if a else", "ex = a[-1] if a else"),
    ('blank-ends-table', 'пустая строка кончает таблицу [R14]',
     "            hdr = None\n            continue\n",
     "            if l.strip():\n                hdr = None\n            continue\n"),
    ('ledger-blank-skip', 'пустая строка ведомости пропускается [K4]',
     "if not l.strip() or l.lstrip().startswith('#'):", "if l.lstrip().startswith('#'):"),
    ('refused-zero', 'нет отказов склейки — «0» [W2]', "dict(r['refused']) or 0", "dict(r['refused'])"),
    ('load-zero', 'загрузка при сроке 0 — 0 [P3]', "if ms else 0))", "if ms else 1))"),
]

# Порчи, которым нечем отличиться от исходника — доводом, не пропуском:
EQUIVALENT = [
    ('merge-no-acyclic', "в склейке `acyclic()` после `reach(t, q) or reach(q, t)`: цикл "
     "через склеенный пакет — это путь t…q либо q…t по пакетам, а его `reach` уже "
     "отверг; порча «if True» проверку не ослабляет"),
    ('guard-base-frozen', "снятие `base = cp_now()` после склейки: склейка пути не "
     "укорачивает (длительность пакета ≥ каждой из частей, рёбра только "
     "объединяются), а guard принимает лишь cp ≤ base, значит base после "
     "принятой склейки равна прежней"),
    ('chain-any-ex / chain-any-repo', "снятие `y['ex'] == x['ex']` либо `y['repo'] == x['repo']` "
     "в условии цепочки: `all(...)` по членам пакета, куда входит и сам `p` (он хвост), "
     "проверяет то же"),
    ('chain-x-multi / chain-y-multi', "снятие одного из `not x['multi']` и `not y['multi']`: "
     "цепочка требует `y['repo'] == x['repo']`, а multi — функция репозитория, значит "
     "x multi ⇔ y multi; снятие обоих держит `multi-gt2` (W2)"),
    ('ready-ignore-started', "снятие `s not in started` при готовности: каждый "
     "предшественник финиширует ровно один раз, и `PD[s] <= done` впервые истинно на "
     "последнем из них — до старта `s` повторного добавления в готовые нет"),
    ('refuse-ext-quotes', "снятие «ёлочек» из `ext`: `carries` ищет фразу и в `raw`, куда "
     "те же «ёлочки» входят"),
    ('pkg-first-lane-index', "`P[q][0]` → `P[q][-1]` в ключе склейки, отборе кандидатов и "
     "таблице: у полос пакета исполнитель, репозиторий и multi общие — цепочка и склейка "
     "собирают только такие"),
    ('memo-recompute', "снятие мемоизации `bl`, `fin`, `f` (`if q not in …`): чистая функция "
     "пересчитывается с тем же значением"),
    ('dfs-revisit / color-3', "обход в `find_cycle` по уже законченным узлам и цвет 3 вместо 2: "
     "потомки законченного узла закончены, серого среди них нет — ложного цикла не бывает; "
     "сравнивается только цвет 1"),
    ('plan-reach-no-seen', "`reach` в `plan` без `seen`: граф пакетов к этому моменту "
     "ацикличен (`acyclic()` после каждой перестановки), обход конечен и даёт то же"),
    ('pdeps-in-pk', "снятие `p in pk` в `pdeps`: полосы кладутся в топологическом порядке, "
     "предшественник размещён раньше, `pk[p]` есть всегда"),
    ('cands-q-deleted', "`if q not in P: continue` в склейке: `q` удаляется только на своём "
     "же шаге, на входе шага он в `P` всегда"),
    ('stage-none', "`if stage:` → `True`: полосы без стадии копятся под ключом None, а "
     "ссылка ищется по строке `S<n>` — None ею не бывает"),
    ('est-root-shift', "начальный ранний старт 0 → ±1: он сдвигает ранний старт всех полос "
     "на одно число (каждый путь начинается с корня), порядок кандидатов прежний"),
    ('nid-index', "`nid[0]` → `nid[-1]`: список из одного элемента"),
    ('script-guards', "`if __name__ == '__main__'` и индекс строки описания argparse — "
     "не решение расчёта"),
]

# Порчи, которые ОТЛИЧИМЫ от исходника, но пробы не имеют: форма входа не
# определена нормой, и проба закрепила бы случайное поведение. Печатаются
# каждый прогон — это «держится вниманием», а не «держится».
UNHELD = [
    ('range-chained', "`r, step = None, 2` → `1`: правая граница перечитывается и может "
     "начать новый диапазон; отличимо только на цепи «A1–A2–A5», смысл которой нормой "
     "не задан (в маршрутах notify её нет)"),
    ('separator-strict', "`<=` → `<` в узнавании строки-разделителя: отличимо только на "
     "строке, чьи ячейки состоят из «-», «:» и пробела внутри ячейки — это не "
     "разделитель GFM и не строка полосы"),
]


def run_suite(tool, box):
    env = dict(os.environ, LANE_SCHEDULE_TOOL=tool, TMPDIR=box)
    try:
        # Каждый вызов инструмента в наборе ограничен 10 с; предел набора целиком —
        # чтобы зависание харнесса не выглядело долгим прогоном.
        p = subprocess.run(['bash', SUITE], env=env, capture_output=True, text=True,
                           timeout=1800)
    except subprocess.TimeoutExpired:
        return -1, [], 'набор не завершился за 1800 с'
    failed = [l.split(' — ')[0].replace('ПРОВАЛЕНО ', '')
              for l in p.stdout.splitlines() if l.startswith('ПРОВАЛЕНО ')]
    return p.returncode, failed, p.stdout + p.stderr


def main():
    if not MUTANTS:
        print('ПУСТОЙ ОБХОД — порч ноль; вердикта нет')
        return 2
    src = open(TOOL, encoding='utf-8').read()
    base_ast = ast.dump(ast.parse(src))
    refused = []
    with tempfile.TemporaryDirectory(prefix='lane-mutants-') as box:
        ctl = os.path.join(box, 'control.py')
        with open(ctl, 'w', encoding='utf-8') as fh:
            fh.write(src)
        rc, failed, out = run_suite(ctl, box)
        m = re.search(r'утверждений (\d+); пройдено (\d+)', out)
        if rc != 0 or not m or m.group(1) != m.group(2):
            print('ОТКАЗ — контроль: набор против неиспорченной копии не зелёный (код %d, '
                  'провалено %s)' % (rc, failed or '—'))
            return 1
        print('контроль: неиспорченная копия — код 0, утверждений %s' % m.group(1))
        killed, survived = [], []
        todo = []
        for name, decision, old, new in MUTANTS:
            n = src.count(old)
            if n != 1:
                refused.append('%s: фрагмент встречается %d раз, ожидался 1 — порча устарела'
                               % (name, n))
                continue
            mutated = src.replace(old, new)
            try:
                if ast.dump(ast.parse(mutated)) == base_ast:
                    refused.append('%s: порча не меняет разобранного дерева' % name)
                    continue
            except SyntaxError as e:
                refused.append('%s: порча ломает разбор (%s) — это не порча решения' % (name, e))
                continue
            path = os.path.join(box, 'm-%s.py' % name)
            with open(path, 'w', encoding='utf-8') as fh:
                fh.write(mutated)
            todo.append((name, decision, path))
        # Прогоны независимы (у каждого свой каталог под TMPDIR); печать — в
        # порядке перечня, а не завершения.
        with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as pool:
            results = list(pool.map(lambda t: run_suite(t[2], box), todo))
        for (name, decision, _), (rc, failed, _) in zip(todo, results):
            if rc == 1 and failed:
                killed.append(name)
                print('УБИТА   %-28s %s — краснеют: %s' % (name, decision, ', '.join(sorted(set(failed)))))
            else:
                survived.append(name)
                print('ВЫЖИЛА  %-28s %s — код набора %d, провалено %s'
                      % (name, decision, rc, failed or '—'))
    for r in refused:
        print('ОТКАЗ ПРЕДПОСЫЛКИ — %s' % r)
    for name, why in EQUIVALENT:
        print('равносильна исходнику, не гонится: %s — %s' % (name, why))
    for name, why in UNHELD:
        print('ОТЛИЧИМА, ПРОБЫ НЕТ (держится вниманием): %s — %s' % (name, why))
    print('\nlane-schedule mutants: порч %d; убито %d, выжило %d, отказ предпосылки %d; '
          'равносильных %d; отличимых без пробы %d'
          % (len(MUTANTS), len(killed), len(survived), len(refused), len(EQUIVALENT),
             len(UNHELD)))
    return 1 if survived or refused else 0


if __name__ == '__main__':
    sys.exit(main())
