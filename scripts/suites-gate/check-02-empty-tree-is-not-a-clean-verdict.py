#!/usr/bin/env python3
"""check-02 — ни одна проверка ни одного набора не выдаёт «ноль осмотренного» за «ноль находок».

ЧТО УТВЕРЖДАЕТ (ws#762 п.3). Каждая проверка, направленная на ПУСТОЕ дерево, выходит
НЕ нулём: либо «без предмета» (2), либо находкой (1). Ноль на пустом дереве значит,
что проверка объявила «чисто», ничего не прочитав, — и читатель, не заглядывая в её
исходник, отличить это от настоящего зелёного не может.

ПРОБА ПОВЕДЕНЧЕСКАЯ. Проверку зовут с общим переопределением `GATE_ROOT` на пустой
git-репозиторий, из него же как рабочего каталога, сняв указатели на клоны продукта
(`_lib.world_env`). Предмет, которого в дереве нет, обязан дать ненулевой исход — не
по совпадению текста, а по коду.

ГРАНИЦА С СОСЕДЯМИ — названа, чтобы две проверки об одном не разошлись:
  * `check-01` судит, из какого дерева проверка берёт корень; проверку, которая
    берёт его из рабочего каталога И выходит нулём на пустом, ловит ЭТА: в обоих
    её прогонах исход одинаков, а здесь ноль — находка;
  * проверку, не читающую переопределение корня вовсе, ловит тоже эта: она судит
    своё настоящее дерево, выходит нулём, и находка говорит об обеих причинах;
  * печатает ли проверка объём на НАСТОЯЩЕМ дереве, судит общий прогонщик
    (`scripts/lib/suite-runner.sh`), а что каждый прогонщик набора это умеет —
    `check-03-runner-demands-a-printed-volume.py`.

Коды: 0 — каждая проверка отличает пустое дерево от чистого; 1 — находка; 2 —
осматривать нечего.
"""
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-02-empty-tree-is-not-a-clean-verdict"


def main():
    ws = _lib.root(__file__)
    names, by_suite = _lib.suite_census(NAME, ws)
    total = sum(len(v) for v in by_suite.values())
    if not names:
        _lib.void(NAME, "наборов scripts/*/run-all.sh в %s нет — осматривать нечего" % ws)
        return 2
    if total == 0:
        _lib.void(NAME, "наборов %d, проверок check-* в них 0 — осматривать нечего" % len(names))
        return 2

    empty = _lib.empty_world()
    outcomes = {}
    findings = []
    try:
        env = _lib.world_env(empty)
        for s in names:
            for rel in by_suite[s]:
                rc = _lib.run_check(ws, rel, empty, env)
                outcomes[rc] = outcomes.get(rc, 0) + 1
                if rc == 0:
                    findings.append(
                        "%s — направлена на пустое дерево и вышла нулём: ноль осмотренного "
                        "выдан за ноль находок (либо проверка не читает переопределение "
                        "корня и судит не то дерево, на которое её направили)" % rel)
    finally:
        shutil.rmtree(empty, ignore_errors=True)

    _lib.census(NAME, "наборов %d; проверок %d, каждая направлена на пустое дерево; "
                "исходы — %s; находок %d"
                % (len(names), total,
                   ", ".join("код %s: %d" % (k, outcomes[k]) for k in sorted(outcomes, key=str)),
                   len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "проверок, зеленеющих на пустом дереве: %d" % len(findings))
        return 1
    _lib.passed(NAME, "все %d проверок в %d наборах отличают пустое дерево от чистого"
                % (total, len(names)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
