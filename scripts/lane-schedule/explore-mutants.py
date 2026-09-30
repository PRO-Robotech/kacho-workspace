#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
r"""explore-mutants — разведка: ВСЕ однофактные порчи разобранного дерева
`lane-schedule.py`, каждая против `inject.sh`; печатает выживших с координатой.

Не гейт и не шаг конвейера (порч около тысячи, прогон — десятки минут). Им
сверяется ПОЛНОТА перечня `mutants.py`: выживший здесь — либо решение без пробы
(проба в `inject.sh` и строка в `MUTANTS`), либо равносильная исходнику порча
(`EQUIVALENT`, с доводом), либо отличимая без нормы (`UNHELD`). Разбор выживших —
руками, по доводу у каждого; скрипт его не делает.

Операторы: сравнение (любой из шести), `in` ↔ `not in`, `and` ↔ `or` и снятие
члена конъюнкции, снятие `not`, условие `if` и тернарного → True/False, целая
константа ±1, `max` ↔ `min`, `+` ↔ `−`; у регулярного выражения (первый аргумент
`re.*`) — снятие `\s*`, `\b`, `?`, `-`, `^`, `$`, `+`, `*`, `\d`; у строкового
операнда сравнения или вызова — пустая строка и дописанный символ; методы
`fullmatch`/`match`/`search`, `endswith`/`startswith`, `partition`, `strip`; подмена
переменной ячейки (`s`, `cell`, `tail`, `head`).

Запуск: python3 explore-mutants.py [<инструмент> <набор> [<потоков>]]
Исходы: 0 — разведка прошла (выжившие напечатаны, разбирать их — работа);
1 — контроль (неиспорченная копия) не зелёный; 2 — порч ноль.
"""

import ast
import concurrent.futures
import copy
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'lane-schedule.py')
SUITE = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, 'inject.sh')
WORKERS = int(sys.argv[3]) if len(sys.argv) > 3 else 4
with open(TOOL, encoding='utf-8') as fh:
    src = fh.read()
tree = ast.parse(src)
base = ast.dump(tree)

CMP = [ast.Lt, ast.LtE, ast.Gt, ast.GtE, ast.Eq, ast.NotEq]
REGEX_ATOMS = [r'\s*', r'\b', '?', '-', '^', '$', '+', '*', r'\d']
METH = {'fullmatch': ['match', 'search'], 'match': ['fullmatch', 'search'], 'search': ['match'],
        'endswith': ['startswith'], 'startswith': ['endswith'], 'partition': ['rpartition'],
        'findall': [], 'strip': ['lstrip', 'rstrip']}
VARSETS = [{'s', 'cell', 'tail', 'head'}]


def is_docstring(parent, node):
    return isinstance(parent, ast.Expr)


muts = []  # (desc, lineno, transform(tree)->bool)


def collect():
    parents = {}
    for p in ast.walk(tree):
        for c in ast.iter_child_nodes(p):
            parents[c] = p
    nodes = list(ast.walk(tree))
    for idx, n in enumerate(nodes):
        ln = getattr(n, 'lineno', 0)
        if isinstance(n, ast.Compare):
            for k, op in enumerate(n.ops):
                if type(op) in CMP:
                    for alt in CMP:
                        if alt is not type(op):
                            muts.append(('cmp %s->%s' % (type(op).__name__, alt.__name__), ln, idx, ('ops', k, alt)))
                if isinstance(op, (ast.In, ast.NotIn)):
                    muts.append(('in-flip', ln, idx, ('ops', k, ast.NotIn if isinstance(op, ast.In) else ast.In)))
        if isinstance(n, ast.BoolOp):
            muts.append(('boolop flip', ln, idx, ('boolop',)))
            for k in range(len(n.values)):
                muts.append(('boolop drop %d' % k, ln, idx, ('bdrop', k)))
        if isinstance(n, ast.UnaryOp) and isinstance(n.op, ast.Not):
            muts.append(('not drop', ln, idx, ('notdrop',)))
        if isinstance(n, ast.If):
            muts.append(('if True', ln, idx, ('iftest', True)))
            muts.append(('if False', ln, idx, ('iftest', False)))
        if isinstance(n, ast.IfExp):
            muts.append(('ifexp True', ln, idx, ('iftest', True)))
            muts.append(('ifexp False', ln, idx, ('iftest', False)))
        if isinstance(n, ast.Constant) and type(n.value) is int:
            muts.append(('int +1', ln, idx, ('int', 1)))
            muts.append(('int -1', ln, idx, ('int', -1)))
        if isinstance(n, ast.Constant) and isinstance(n.value, str) and not is_docstring(parents.get(n), n):
            p = parents.get(n)
            # регулярное выражение: первый аргумент re.*
            if (isinstance(p, ast.Call) and isinstance(p.func, ast.Attribute)
                    and isinstance(p.func.value, ast.Name) and p.func.value.id == 're'
                    and p.args and p.args[0] is n):
                for atom in REGEX_ATOMS:
                    c = n.value.count(atom)
                    for j in range(c):
                        muts.append(('regex drop %r #%d' % (atom, j), ln, idx, ('rxdrop', atom, j)))
            # строковый операнд сравнения/in/метода
            if isinstance(p, (ast.Compare, ast.Call, ast.BinOp)) and not (
                    isinstance(p, ast.Call) and isinstance(p.func, ast.Name) and p.func.id == 'print'):
                if len(n.value) <= 20 and '%' not in n.value:
                    muts.append(('str empty %r' % n.value, ln, idx, ('str', '')))
                    muts.append(('str x %r' % n.value, ln, idx, ('str', n.value + 'x')))
        if isinstance(n, ast.Name) and n.id in ('max', 'min'):
            muts.append(('maxmin', ln, idx, ('name', 'min' if n.id == 'max' else 'max')))
        if isinstance(n, ast.Name) and isinstance(n.ctx, ast.Load):
            for vs in VARSETS:
                if n.id in vs:
                    for alt in sorted(vs - {n.id}):
                        muts.append(('var %s->%s' % (n.id, alt), ln, idx, ('name', alt)))
        if isinstance(n, ast.BinOp) and isinstance(n.op, (ast.Add, ast.Sub)):
            muts.append(('binop flip', ln, idx, ('binop',)))
        if isinstance(n, ast.Attribute) and n.attr in METH:
            for alt in METH[n.attr]:
                muts.append(('meth %s->%s' % (n.attr, alt), ln, idx, ('attr', alt)))


def apply(spec, idx):
    t = copy.deepcopy(tree)
    n = list(ast.walk(t))[idx]
    k = spec[0]
    if k == 'ops':
        n.ops[spec[1]] = spec[2]()
    elif k == 'boolop':
        n.op = ast.Or() if isinstance(n.op, ast.And) else ast.And()
    elif k == 'bdrop':
        if len(n.values) < 2:
            return None
        del n.values[spec[1]]
    elif k == 'notdrop':
        # заменить сам узел операндом — через родителя
        for p in ast.walk(t):
            for f, v in ast.iter_fields(p):
                if v is n:
                    setattr(p, f, n.operand)
                elif isinstance(v, list) and any(x is n for x in v):
                    v[[i for i, x in enumerate(v) if x is n][0]] = n.operand
    elif k == 'iftest':
        n.test = ast.Constant(spec[1])
    elif k == 'int':
        n.value = n.value + spec[1]
    elif k == 'rxdrop':
        atom, j = spec[1], spec[2]
        v = n.value
        pos = -1
        for _ in range(j + 1):
            pos = v.find(atom, pos + 1)
        n.value = v[:pos] + v[pos + len(atom):]
        try:
            re.compile(n.value)
        except re.error:
            return None
    elif k == 'str':
        n.value = spec[1]
    elif k == 'name':
        n.id = spec[1]
    elif k == 'binop':
        n.op = ast.Sub() if isinstance(n.op, ast.Add) else ast.Add()
    elif k == 'attr':
        n.attr = spec[1]
    ast.fix_missing_locations(t)
    if ast.dump(t) == base:
        return None
    return ast.unparse(t)


def run(path, box):
    env = dict(os.environ, LANE_SCHEDULE_TOOL=path, TMPDIR=box)
    try:
        p = subprocess.run(['bash', SUITE], env=env, capture_output=True, text=True, timeout=900)
    except subprocess.TimeoutExpired:
        return -1, 0
    return p.returncode, p.stdout.count('ПРОВАЛЕНО ')


collect()
# Полосы не живут в /tmp: каталог прогона — под TMPDIR вызывающего либо рядом.
with tempfile.TemporaryDirectory(prefix='lane-explore-') as box:
    ctl = os.path.join(box, 'ctl.py')
    with open(ctl, 'w', encoding='utf-8') as fh:
        fh.write(ast.unparse(tree))
    rc, f = run(ctl, box)
    print('контроль (unparse): код %d, провалено %d' % (rc, f))
    if rc != 0:
        sys.exit(1)
    todo = []
    for i, (desc, ln, idx, spec) in enumerate(muts):
        m = apply(spec, idx)
        if m is None:
            continue
        pth = os.path.join(box, 'x%04d.py' % i)
        with open(pth, 'w', encoding='utf-8') as fh:
            fh.write(m)
        todo.append((desc, ln, pth))
    print('порч построено %d из %d' % (len(todo), len(muts)), flush=True)
    if not todo:
        print('ПУСТОЙ ОБХОД — порч ноль; разведки нет')
        sys.exit(2)
    with concurrent.futures.ThreadPoolExecutor(WORKERS) as pool:
        res = list(pool.map(lambda t: run(t[2], box), todo))
    surv = [(d, ln) for (d, ln, _), (rc, f) in zip(todo, res) if not (rc == 1 and f)]
    print('выжило %d' % len(surv))
    lines = src.split('\n')
    for d, ln in surv:
        print('ВЫЖИЛА строка %d: %s | %s' % (ln, d, lines[ln - 1].strip()[:110]))
