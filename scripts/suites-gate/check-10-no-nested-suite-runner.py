#!/usr/bin/env python3
"""check-10 — `run-all.sh` лежит только на глубине набора: `scripts/<имя>/run-all.sh`.

ЧТО УТВЕРЖДАЕТ (ws#753). Под `scripts/` нет отслеживаемого файла `run-all.sh` глубже
каталога набора (`scripts/<набор>/tests/fixture/run-all.sh` и т. п.).

ЦЕНА, РАДИ КОТОРОЙ ПРОВЕРКА ЗАВЕДЕНА. «Что такое набор» в дереве определено ДВАЖДЫ.
Перепись `scripts/lib/suites.py` (её зовёт конвейер через `scripts/lib/run-suites.sh`)
берёт только `scripts/<имя>/run-all.sh`. Хук отправки (`scripts/hooks/pre-push`)
перечисляет наборы своим pathspec `git ls-files 'scripts/*/run-all.sh'`, а `*` в
pathspec git проходит через `/`. Измерено в круге 1: песочница с
`scripts/a-gate/run-all.sh` и `scripts/a-gate/tests/fixture/run-all.sh` — хук видит 2,
перепись 1: хук исполнил бы фикстуру как набор, конвейер — нет, и исход отправки
разошёлся бы с исходом ствола молча. Сегодня вложенного `run-all.sh` нет, и два
определения совпадают по факту дерева, а не по устройству.

ПОЧЕМУ ЗАПРЕТ ФОРМЫ, А НЕ СВЕРКА ДВУХ ПРЕДИКАТОВ. Сверка переписывала бы предикат хука
сюда — третий носитель того же определения, который отстал бы от хука так же молча.
Запрет вложенного `run-all.sh` делает расхождение непредставимым при ЛЮБОМ из двух
определений. Перевод хука на `scripts/lib/suites.py` снял бы второе определение совсем;
хук — предмет другой полосы, и до тех пор определение одно по этой проверке, а не по
тексту.

Перепись печатает, сколько `run-all.sh` под `scripts/` отслеживается, сколько из них на
глубине набора и сколько вложенных. Ни одного — VOID.

Коды: 0 — каждый `run-all.sh` на глубине набора; 1 — находка; 2 — ни одного `run-all.sh`.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-10-no-nested-suite-runner"


def main():
    ws = _lib.root(__file__)
    try:
        tracked = _lib.S.tracked(ws, "scripts/")
    except _lib.S.CensusUnreadable as exc:
        _lib.void(NAME, "перепись scripts/ не снята: %s" % exc)
        return 2
    runners = [r for r in tracked if r.rsplit("/", 1)[-1] == _lib.S.RUNNER]
    if not runners:
        _lib.void(NAME, "под scripts/ в %s отслеживаемых %s нет — осматривать нечего"
                  % (ws, _lib.S.RUNNER))
        return 2
    top = [r for r in runners if r.count("/") == 2]
    nested = [r for r in runners if r.count("/") != 2]
    findings = ["%s — %s глубже каталога набора: перепись scripts/lib/suites.py (конвейер) "
                "набором его не считает, а хук отправки (pathspec `scripts/*/run-all.sh`, "
                "`*` проходит через `/`) исполнил бы его как набор — два определения набора "
                "разошлись; переименуй прогонщик фикстуры" % (r, _lib.S.RUNNER) for r in nested]

    _lib.census(NAME, "%s под scripts/ отслеживается %d; на глубине набора %d; вложенных %d; "
                "находок %d" % (_lib.S.RUNNER, len(runners), len(top), len(nested),
                                len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "вложенных %s: %d" % (_lib.S.RUNNER, len(nested)))
        return 1
    _lib.passed(NAME, "все %d %s под scripts/ лежат на глубине набора — перепись и хук "
                "отправки видят одни и те же наборы" % (len(runners), _lib.S.RUNNER))
    return 0


if __name__ == "__main__":
    sys.exit(main())
