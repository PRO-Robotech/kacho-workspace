#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""mutants — набор `inject.sh` обязан КРАСНЕТЬ на однофактной порче каждого
решения `lane-schedule.py`.

Зачем: приёмка ws#884 (check-verifier, ⛔ на fc25f8038) нашла две порчи
инструмента — граница guard `<=` → `<` и приоритет расписания по id вместо
остатка пути, — на которых `inject.sh` оставался зелёным 21/21, а числа на
реальных маршрутах менялись (пакетов 113 → 127; срок при 6 слотах 1075 → 1275
мин). Перечень ниже — по РЕШЕНИЮ инструмента, а не по найденным местам: у
каждого решения хотя бы одна порча.

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
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, 'lane-schedule.py')
SUITE = os.path.join(HERE, 'inject.sh')

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
]


def run_suite(tool, box):
    env = dict(os.environ, LANE_SCHEDULE_TOOL=tool, TMPDIR=box)
    p = subprocess.run(['bash', SUITE], env=env, capture_output=True, text=True)
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
            rc, failed, _ = run_suite(path, box)
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
    print('\nlane-schedule mutants: порч %d; убито %d, выжило %d, отказ предпосылки %d; '
          'равносильных %d' % (len(MUTANTS), len(killed), len(survived), len(refused),
                               len(EQUIVALENT)))
    return 1 if survived or refused else 0


if __name__ == '__main__':
    sys.exit(main())
