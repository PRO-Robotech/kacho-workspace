#!/usr/bin/env python3
"""check-02 — храповик: число предметов со второй пропиской не РАСТЁТ.

ЯРУС 1 НОРМЫ, ЕДИНСТВЕННЫЙ, КОТОРЫЙ РАБОТАЕТ БЕЗ ЗАДАЧ И БЕЗ СРОКОВ.

Событие, а не дата: предмет получает копию в доме, которого у него не было, либо
в дереве заводится новый предмет со второй пропиской. Исход у такого события
один — вынос, потому что «оставить все три» исходом не является (запрет #20,
`poly-copy-atomic`). Обязанность, привязанная к событию, исполнима; обязанность
со словом «потом» — пожелание.

ТРИ ЧИСЛА, А НЕ ОДНО, И КАЖДОЕ ЛОВИТ СВОЁ:

  subjects    предметов со второй пропиской. Растёт, когда скопировали НОВОЕ.
  files       файлов в этих предметах. ТРЕТЬЯ прописка счёт предметов НЕ меняет
              — она меняет счёт файлов; без этого числа ярус 1 был бы слеп ровно
              к тому событию, ради которого он заведён.
  actionable  кандидатов при СНЯТЫХ лицензионных исключениях — очередь, которая
              появится в день публикации решения владельца. Мерится независимо
              от сегодняшних переключателей: иначе неопубликованное решение
              прятало бы рост.

ТОЧНОЕ ЧИСЛО, НЕ ПОТОЛОК. Ведомость, прощающая 42 при 36, перестаёт быть
храповиком (`testing.md` ledger-exact-not-ceiling). Поэтому красное и на росте
(ухудшение), и на просрочке (убыло — затяните ведомость тем же изменением,
которым сняли предмет). Убывающий он именно этим.

СЧЁТ ЕСТЬ ВЕРХНЯЯ ГРАНИЦА второй прописки, а не мера требования владельца:
предмет, обязанный быть в фундаменте по собственной шапке, но живущий по одному
экземпляру в каждом продукте, второй прописки не имеет и здесь не виден
(измерено: `kacho:pkg/refusal/lane.go` ↔ `kaname:…/shared/reference_refusal.go`,
J = 0.105 при пороге 0.70). Это названо вслух и в норме, и здесь.

Исходы: 0 — числа сошлись; 1 — находка; 2 — считать не по чему.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs-gate"))
import _core  # noqa: E402
import _lib  # noqa: E402

NAME = "check-02-second-home-count-does-not-grow"
LEDGER = "docs/foundation-candidates.yaml"
KEYS = ("subjects", "files", "actionable")


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
    threshold = float(os.environ.get("J", "0.70"))

    # Храповик меряет ПРИ СНЯТЫХ лицензионных исключениях — всегда, независимо
    # от переключателей прогона: неопубликованное решение владельца не должно
    # прятать рост числа копий.
    m = _core.measure(root, threshold, relicense_busl=True, relicense_agpl=True)
    if "void" in m:
        _lib.void(NAME, "%s — храповик считать не по чему" % m["void"])
        return 2
    if m["walked"] == 0:
        _lib.void(NAME, "обход ПУСТ — ни одного `.go` ни в одном стволе; «рост 0» здесь "
                        "означало бы «ноль прочитанного»")
        return 2

    text = _lib.read(root, LEDGER)
    if text is None:
        _lib.void(NAME, "ведомость %s не прочитана — сверять число не с чем" % LEDGER)
        return 2
    want = declared(text)
    missing = [k for k in KEYS if k not in want]
    if missing:
        _lib.void(NAME, "ведомость %s не объявляет %s в блоке `ceiling:` — храповика нет"
                  % (LEDGER, ", ".join(missing)))
        return 2

    got = {"subjects": m["subjects"], "files": m["subject_files"],
           "actionable": len(m["candidates"])}
    _lib.census("%s: стволов %d; осмотрено `.go` %d, сравнимых %d; замерено %s; "
                "объявлено %s"
                % (NAME, len(m["trees"]), m["walked"], m["comparable"],
                   ", ".join("%s=%d" % (k, got[k]) for k in KEYS),
                   ", ".join("%s=%d" % (k, want[k]) for k in KEYS)))

    findings = []
    for k in KEYS:
        if got[k] > want[k]:
            findings.append("%s: замерено %d, объявлено %d — РОСТ на %d. Предмет получил "
                            "прописку, которой у него не было. Исход один — вынос: "
                            "«оставить все три» исходом не является (запрет #20, "
                            "poly-copy-atomic). Поднять число в ведомости вместо выноса "
                            "значит снять храповик"
                            % (k, got[k], want[k], got[k] - want[k]))
        elif got[k] < want[k]:
            findings.append("%s: замерено %d, объявлено %d — ведомость ПРОСРОЧЕНА на %d. "
                            "Потолок затягивается тем же изменением, которым снят предмет; "
                            "иначе он прощает возврат уже вынесенного"
                            % (k, got[k], want[k], want[k] - got[k]))

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        return 1
    _lib.passed(NAME, "храповик сошёлся точным числом: %s"
                % ", ".join("%s=%d" % (k, got[k]) for k in KEYS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
