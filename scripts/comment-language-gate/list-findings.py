#!/usr/bin/env python3
"""Перепись находок: где в нашем Go проза комментария не по-русски.

Это ИЗМЕРИТЕЛЬ, а не проверка: вердикт выносит `check-01`. Печатает координаты,
чтобы очередь приведения к виду бралась из дерева, а не из памяти.

Дерево продукта меряется на стволе `origin/main` клона, а не в его рабочей копии,
и полная ревизия печатается рядом с числами: строка ведомости `rev:` берётся
отсюда. Воркспейс меряется по рабочей копии.

  python3 scripts/comment-language-gate/list-findings.py            # свод
  python3 scripts/comment-language-gate/list-findings.py --coords   # координаты
  python3 scripts/comment-language-gate/list-findings.py --split    # пробы/не-пробы

Исходы: 0 — замер состоялся; 2 — считать не по чему (клона нет).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "docs-gate"))
import _core  # noqa: E402
import _lib  # noqa: E402


def main(argv):
    m = _core.measure(_lib.workspace_root())
    if "void" in m:
        sys.stderr.write("БЕЗ ПРЕДМЕТА — %s\n" % m["void"])
        return 2
    for t in m["trees"]:
        print("%-10s осмотрено `.go` %5d · порождённых снято %3d · ввезённых снято %2d"
              " | файлов %4d · блоков %5d · строк %6d · отказов разбора %d · %s"
              % (t["tree"], t["walked"], t["generated"], t["vendored"],
                 len(t["files"]), t["blocks"], t["lines"], len(t["parsefail"]),
                 "%s %s" % (_core.TRUNK_REF, t["rev"]) if t["rev"] else "рабочая копия"))
    print("ИТОГО осмотрено `.go` %d · отказов разбора %d | файлов %d · блоков %d · строк %d"
          % (m["walked"], len(m["parsefail"]), m["files"], m["blocks"], m["lines"]))
    for p in m["parsefail"]:
        print("ОТКАЗ РАЗБОРА %s" % p)

    if "--split" in argv:
        tf, pf, tl, pl = set(), set(), 0, 0
        for tree, rel, ln, cnt, sample in m["findings"]:
            if rel.endswith("_test.go"):
                tf.add((tree, rel))
                tl += cnt
            else:
                pf.add((tree, rel))
                pl += cnt
        print("пробы %d/%d · не-пробы %d/%d" % (len(tf), tl, len(pf), pl))
    if "--coords" in argv:
        for tree, rel, ln, cnt, sample in sorted(m["findings"]):
            print("%s\t%s:%d\tстрок %d\t%s" % (tree, rel, ln, cnt, sample))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
