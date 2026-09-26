#!/usr/bin/env python3
"""Перечень предметов со ВТОРОЙ ПРОПИСКОЙ — очередь решений о выносе.

Координата, названная нормой `arch-second-home-needs-a-decision`
(`.claude/rules/architecture.md` §«Переиспользование»).

ЭТО ИЗМЕРИТЕЛЬ, А НЕ ГЕЙТ. Вердикт выносят `check-01` и `check-02` рядом; здесь
код возврата говорит только о том, БЫЛО ЛИ ЧТО МЕРИТЬ:

  0 — обход состоялся: прочитано > 0 файлов, перечень напечатан (пустой перечень
      это ЦЕЛЬ, и он код не портит);
  2 — БЕЗ ПРЕДМЕТА: клонов нет, ствол не резолвится, либо обход пуст.

Ненулевой код на пустом ПЕРЕЧНЕ стоял бы на цели — так была построена первая
редакция, и это её отдельный дефект: падать обязан пустой ОБХОД.

ПЕРЕКЛЮЧАТЕЛИ:
  J=<0..1>                    порог близости (умолчание 0.70)
  RELICENSE_BUSL_DECIDED=1    решение владельца о перелицензировании BUSL-части
  RELICENSE_AGPL_DECIDED=1    отдельное решение по AGPL-части
  RELICENSE_DECIDED=1         прежнее имя; снимает ТОЛЬКО BUSL-половину

Почему переключателя два, а не один. Класс «не Apache-2.0» НЕ ОДНОРОДЕН: в нём
два режима с противоположными обязательствами — 16 файлов BUSL-1.1 и 3 файла
AGPL-3.0-or-later при Apache-2.0 фундаменте. Снятие «одним решением на класс»
внесло бы AGPL-код службы доступа в Apache-библиотеку, которую линкует
BUSL-продукт, и §13 AGPL (сетевое взаимодействие) достал бы до каждого сетевого
двоичного платформы. Ошибка необратима: опубликованный тег из базы контрольных
сумм не отзывается, и у того, кто код получил, права остаются.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs-gate"))
import _core  # noqa: E402
import _lib  # noqa: E402

NAME = "list-candidates"


def main():
    root = _lib.workspace_root()
    threshold = float(os.environ.get("J", "0.70"))
    busl = os.environ.get("RELICENSE_BUSL_DECIDED") == "1" or \
        os.environ.get("RELICENSE_DECIDED") == "1"
    agpl = os.environ.get("RELICENSE_AGPL_DECIDED") == "1"

    m = _core.measure(root, threshold, busl, agpl)
    if "void" in m:
        _lib.void(NAME, "%s — второй прописки считать не по чему. Условие создаётся "
                        "клоном в project/<продукт> либо переменной KACHO_HOME_<ПРОДУКТ>"
                  % m["void"])
        return 2
    if m["walked"] == 0:
        _lib.void(NAME, "обход ПУСТ — ни одного `.go` ни в одном стволе. «Кандидатов 0» "
                        "здесь означало бы «ноль прочитанного»")
        return 2

    print("ревизии: " + " · ".join(
        "%s@%s" % (n, m["trees"][n][2]) for n in sorted(m["trees"])))
    _lib.census("%s: осмотрено `.go` %d, из них сравнимых (≥%d строк) %d · порог J=%.2f · "
                "неподвижная точка СВЕРХУ: кругов %d, в очереди каталогов %d · "
                "решение о перелицензировании: BUSL %s, AGPL %s"
                % (NAME, m["walked"], _core.MIN_LINES, m["comparable"], m["threshold"],
                   m["fixpoint_rounds"], len(m["queued_dirs"]),
                   "принято" if m["relicense"][0] else "НЕ опубликовано",
                   "принято" if m["relicense"][1] else "НЕ опубликовано"))
    print("ПРЕДМЕТОВ со второй пропиской: %d (файлов в них %d) · КАНДИДАТОВ после "
          "исключений: %d · файлов в них: %d"
          % (m["subjects"], m["subject_files"], len(m["candidates"]),
             sum(len(c["files"]) for c in m["candidates"])))
    for i, c in enumerate(m["candidates"], 1):
        print(" %2d. копий %d · продуктов %d · адрес выноса: %s"
              % (i, len(c["files"]), len(c["products"]), c["address"]))
        for f in c["files"]:
            print("      %s" % f)
    if m["cut"]:
        print("--- отсечено, по исключениям (перечень закрыт, восемь):")
        for k in sorted(m["cut"], key=lambda x: -m["cut"][x]):
            print("   %3d  %s" % (m["cut"][k], k))
    print("СЧЁТ ЕСТЬ ВЕРХНЯЯ ГРАНИЦА: продуктовая политика ПО СУЩЕСТВУ, не написавшая "
          "имени продукта ни одним литералом, признака не имеет и здесь не видна.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
