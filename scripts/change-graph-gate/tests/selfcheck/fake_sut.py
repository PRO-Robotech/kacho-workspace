#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Подставной SUT — ТОЛЬКО для проб самого harness'а.

Он ничего не вычисляет и Change Graph не проверяет: он объявляет набор
capability и печатает тройку, заданную переменной окружения. Его единственный
предмет — предъявить driver'у ПРИСУТСТВУЮЩИЙ SUT, не написав ни строки
implementation.

Достижим он только через переменную `KACHO_CG_SUT`, которой матрица из всех
кейсов не выставляет никогда; это проверяется отдельной пробой, а не обещанием.

Подделка структурно неспособна выдать зелёное за настоящий вердикт: тройку она
берёт снаружи и своего мнения о мире не имеет.
"""

import json
import os
import sys

CAPABILITIES_ENV = "KACHO_CG_FAKE_CAPABILITIES"
TRIPLE_ENV = "KACHO_CG_FAKE_TRIPLE"
PROBE_MODE_ENV = "KACHO_CG_FAKE_PROBE_MODE"
EXIT_OVERRIDE_ENV = "KACHO_CG_FAKE_EXIT_OVERRIDE"


def main():
    argv = sys.argv[1:]

    if "--capabilities" in argv:
        mode = os.environ.get(PROBE_MODE_ENV, "ok")
        if mode == "crash":
            sys.stderr.write("подставной SUT: проба capability намеренно сломана\n")
            return 3
        if mode == "garbage":
            sys.stdout.write("не JSON вовсе\n")
            return 0
        if mode == "wrong-shape":
            sys.stdout.write(json.dumps({"capabilities": []}) + "\n")
            return 0
        declared = os.environ.get(CAPABILITIES_ENV, "")
        tokens = [item for item in declared.split(",") if item]
        sys.stdout.write(json.dumps(tokens) + "\n")
        return 0

    triple = os.environ.get(TRIPLE_ENV, "GREEN · CG_OK · exit 0")
    sys.stdout.write(triple + "\n")
    override = os.environ.get(EXIT_OVERRIDE_ENV)
    if override is not None:
        return int(override)
    return int(triple.rsplit("exit", 1)[1].strip())


if __name__ == "__main__":
    raise SystemExit(main())
