#!/usr/bin/env python3
"""check-01 — УБЫВАЮЩИЙ ПОТОЛОК: не-русской прозы комментария не становится больше.

ЯРУС, КОТОРЫЙ РАБОТАЕТ БЕЗ СРОКОВ. Требование владельца 2026-09-21 дословно:
«комментарии только на русском. Существующие правки привести к виду». «Привести
к виду» — обязанность, привязанная к СОБЫТИЮ (рука в файле), а не к дате;
обязанность со словом «потом» есть пожелание. Чтобы событийная обязанность не
оказалась несходящейся молча — файл, которого никто не трогает, к виду не
приводится никогда, — её несходимость обязана быть видна ЧИСЛОМ.

ТРИ ЧИСЛА, А НЕ ОДНО, И КАЖДОЕ ЛОВИТ СВОЁ:

  files   файлов с находкой. Растёт, когда не-русская проза появилась там, где
          её не было.
  blocks  блоков комментария с находкой. Новый английский блок в УЖЕ красном
          файле счёт файлов не меняет — он меняет счёт блоков.
  lines   строк-находок. Разрастание УЖЕ красного блока не меняет ни того, ни
          другого; без третьего числа потолок был бы слеп ровно к самому
          дешёвому способу ухудшения.

ТОЧНОЕ ЧИСЛО, НЕ ПОТОЛОК: ведомость, прощающая 42 при 36 находках, перестаёт
быть храповиком (`testing.md` ledger-exact-not-ceiling). Поэтому красное и на
РОСТЕ (ухудшение), и на ПРОСРОЧКЕ (убыло — затяните ведомость тем же
изменением, которым привели файл к виду; иначе она прощает возврат английского
в уже вычищенное место). Убывающий потолок — именно это.

ПОЧЕМУ НЕ «ПЕРЕВЕСТИ ВСЁ ОДНИМ ЗАХОДОМ». Довод не в сборке — при соблюдении
исключений не краснеет ничего, и это измерено четырьмя инъекциями. Довод в том,
что перевод пятидесяти тысяч строк НЕВОЗМОЖНО ОТРЕЦЕНЗИРОВАТЬ, а
неотрецензированный перевод комментария есть ровно тот класс дефекта, который
называет `doc-truthfulness`: утверждение, пережившее свой предмет. Английский
оригинал, разошедшийся с кодом, вызывает подозрение; правдоподобный русский
перевод, разошедшийся с кодом, — нет.

Исходы: 0 — числа сошлись; 1 — находка; 2 — считать не по чему.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "docs-gate"))
import _core  # noqa: E402
import _lib  # noqa: E402

NAME = "check-01-comment-language-does-not-grow"
LEDGER = "docs/comment-language.yaml"
KEYS = ("files", "blocks", "lines")


def declared(text):
    res, inside = {}, False
    for raw in text.split("\n"):
        if raw.startswith("ceiling:"):
            inside = True
            continue
        if inside and raw[:1] not in (" ", "\t", "#", ""):
            inside = False
        if not inside:
            continue
        m = re.match(r"\s+(\w+):\s*(\d+)\s*$", raw)
        if m and m.group(1) in KEYS:
            res[m.group(1)] = int(m.group(2))
    return res


def main():
    root = _lib.workspace_root()
    m = _core.measure(root)
    if "void" in m:
        _lib.void(NAME, "%s — храповик считать не по чему" % m["void"])
        return 2
    if m["walked"] == 0:
        _lib.void(NAME, "обход ПУСТ — ни одного `.go` ни в одном из четырёх деревьев; "
                        "«находок 0» здесь означало бы «ноль прочитанного»")
        return 2
    if m["parsefail"]:
        # Отказ разбора — НЕ находка и НЕ зелёное. Лексер, переставший понимать
        # файл, занижает все три числа молча, и потолок зеленеет от слепоты.
        _lib.void(NAME, "отказов разбора %d, первый: %s — при недочитанном дереве "
                        "числа меньше настоящих"
                  % (len(m["parsefail"]), m["parsefail"][0]))
        return 2

    text = _lib.read(root, LEDGER) if os.path.exists(os.path.join(root, LEDGER)) else None
    if text is None:
        _lib.void(NAME, "ведомость %s не прочитана — сверять число не с чем" % LEDGER)
        return 2
    want = declared(text)
    missing = [k for k in KEYS if k not in want]
    if missing:
        _lib.void(NAME, "ведомость %s не объявляет %s в блоке `ceiling:` — храповика нет"
                  % (LEDGER, ", ".join(missing)))
        return 2

    got = {"files": m["files"], "blocks": m["blocks"], "lines": m["lines"]}
    _lib.census("%s: деревьев %d; осмотрено `.go` %d, отказов разбора 0; снято "
                "порождённых %d, ввезённых %d; замерено %s; объявлено %s"
                % (NAME, len(m["trees"]), m["walked"], m["generated"], m["vendored"],
                   ", ".join("%s=%d" % (k, got[k]) for k in KEYS),
                   ", ".join("%s=%d" % (k, want[k]) for k in KEYS)))

    findings = []
    for k in KEYS:
        if got[k] > want[k]:
            findings.append(
                "%s: замерено %d, объявлено %d — РОСТ на %d. Новая или изменённая "
                "проза комментария в нашем Go пишется по-русски (`ban22-comment-prose-ru`). "
                "Поднять число в ведомости вместо правки комментария значит снять "
                "храповик" % (k, got[k], want[k], got[k] - want[k]))
        elif got[k] < want[k]:
            findings.append(
                "%s: замерено %d, объявлено %d — ведомость ПРОСРОЧЕНА на %d. Потолок "
                "затягивается тем же изменением, которым файл приведён к виду; иначе "
                "он прощает возврат английского в уже вычищенное место"
                % (k, got[k], want[k], want[k] - got[k]))

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        _lib.fail(NAME, "перепись координат — `python3 scripts/comment-language-gate/"
                        "list-findings.py --coords`")
        return 1
    _lib.passed(NAME, "храповик сошёлся точным числом: %s"
                % ", ".join("%s=%d" % (k, got[k]) for k in KEYS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
