#!/usr/bin/env python3
"""check-05 — номер проверки внутри набора — её адрес: он один на проверку и идёт без разрывов от 01.

ЧТО УТВЕРЖДАЕТ (ws#754). В каждом наборе дерева имя каждой проверки несёт номер
(`check-<NN>-<имя>`), номера различны, и множество номеров — ровно 01…N.

ЦЕНА. На номер ссылаются правила, отчёты и записки: «docs-gate check-03». Несколько
носителей одного номера означают, что ссылка разрешается в разные проверки, и
какая имелась в виду, выводится догадкой. Разрыв (01, 02, 04) означает либо
снятую проверку, на которую ещё ссылаются, либо номер, занятый в соседней ветке, —
обе вещи видны только тому, кто сверит глазами.

Находка называет набор и ВСЕХ носителей повторяющегося номера, каждый
пропущенный номер либо проверку с номером 00 (разрывы считаются от 01, и нулевой
номер вне ряда прежде проходил молча — круг 1). Перечень наборов и проверок выведен переписью
(`scripts/lib/suites.py`); ноль наборов либо ноль проверок — VOID.

Коды: 0 — номера каждого набора различны и сплошны; 1 — находка; 2 — нечего осматривать.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-05-check-numbers-are-unique-and-gapless"
NUMBERED = re.compile(r"^check-(\d{2,})-[^/]+$")


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

    findings = []
    numbers_seen = 0
    for s in names:
        carriers = {}
        for rel in by_suite[s]:
            base = rel.rsplit("/", 1)[1]
            m = NUMBERED.match(base)
            if not m:
                findings.append("%s — имя проверки без номера формы check-<NN>-<имя>: "
                                "адресовать её номером нельзя" % rel)
                continue
            carriers.setdefault(int(m.group(1)), []).append(rel)
        numbers_seen += len(carriers)
        for n in sorted(carriers):
            if len(carriers[n]) > 1:
                findings.append("%s: номер %02d несут %d проверки — %s; ссылка «check-%02d» "
                                "разрешается догадкой"
                                % (s, n, len(carriers[n]), ", ".join(carriers[n]), n))
        for rel in carriers.get(0, []):
            findings.append("%s — номер 00: номера проверок идут от 01, нулевой адрес вне "
                            "ряда 01…N и разрывом не считается — его не видно ни одной "
                            "другой оси" % rel)
        if carriers:
            gaps = [n for n in range(1, max(carriers) + 1) if n not in carriers]
            for n in gaps:
                findings.append("%s: номера check-%02d нет, а старшие есть (до check-%02d) — "
                                "разрыв: снятая проверка, на которую ещё ссылаются, либо номер, "
                                "занятый в другой ветке" % (s, n, max(carriers)))

    _lib.census(NAME, "наборов %d; проверок %d; различных номеров %d; находок %d"
                % (len(names), total, numbers_seen, len(findings)))
    if findings:
        for f in findings:
            _lib.finding(f)
        _lib.fail(NAME, "адреса проверок неоднозначны либо с разрывом: находок %d" % len(findings))
        return 1
    _lib.passed(NAME, "в каждом из %d наборов номера %d проверок различны и идут от 01 без разрывов"
                % (len(names), total))
    return 0


if __name__ == "__main__":
    sys.exit(main())
