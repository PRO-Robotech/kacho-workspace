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

ЗАКРЕПЛЁННЫЕ РЕВИЗИИ, А НЕ СТВОЛ КЛОНА (возврат check-verifier, #724). Предмет —
стволы трёх продуктов, а ведомость живёт в воркспейсе. Точный храповик по стволу
КЛОНА краснил воркспейс на каждом шаге ствола, ничего в воркспейсе не меняя
(53 → 52 пересъёмкой 2026-09-22 — ушло сходство, а не работа), и шёл за
состоянием `fetch`: клон, отставший от ствола, давал ложный «РОСТ». Поэтому в
ведомости у каждого продукта закреплена ревизия (`ceiling.rev`), и судится так:

  · числа на закреплённых ревизиях воспроизводятся ТОЧНО. Объявленное выше
    замера — ПРОСРОЧКА: потолок прощает возврат уже вынесенного; объявленное
    ниже замера — число занижено. Обе стороны — находка (`testing.md`
    ledger-exact-not-ceiling: ведомость, прощающая 42 при 36, храповиком не
    является). Этим храповик и УБЫВАЮЩИЙ: затягивается он перезакреплением
    ревизий с числами замера на них, событием воркспейса в диффе ведомости;
  · закреплённая ревизия — предок ствола клона либо он сам. Ствол ПОЗАДИ —
    «считать не по чему» (клон не подтянут), ни предок, ни потомок — находка;
  · на стволе клона, ушедшем вперёд, РОСТ против объявленного — находка; УБЫЛЬ —
    не находка, а запас, и он печатается числом.

ЦЕНА ФОРМЫ названа вслух: между перезакреплениями ствол может вернуть копию, уже
ушедшую со ствола, до объявленного числа — красного не будет, пока запас не
перерасходован. Та же цена принята у `scripts/comment-language-gate` (ws#789);
закрывается она перезакреплением, а не этим файлом.

СЧЁТ ЕСТЬ ВЕРХНЯЯ ГРАНИЦА второй прописки, а не мера требования владельца:
предмет, обязанный быть в фундаменте по собственной шапке, но живущий по одному
экземпляру в каждом продукте, второй прописки не имеет и здесь не виден
(измерено: `kacho:pkg/refusal/lane.go` ↔ `kaname:…/shared/reference_refusal.go`,
J = 0.105 при пороге 0.70). Это названо вслух и в норме, и здесь.

Исходы: 0 — числа сошлись; 1 — находка; 2 — считать не по чему. Находка
объявляется раньше беспредметности.
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
        m = re.match(r"  (\w+):\s*(\d+)\s*$", raw)
        if m and m.group(1) in KEYS:
            res[m.group(1)] = int(m.group(2))
    return res


def nums(m):
    return {"subjects": m["subjects"], "files": m["subject_files"],
            "actionable": len(m["candidates"])}


def fmt(d):
    return ", ".join("%s=%d" % (k, d[k]) for k in KEYS)


def revs_line(revs):
    return ", ".join("%s@%s" % (n, revs[n][:11]) for n in sorted(revs))


def main():
    root = _lib.workspace_root()
    threshold = float(os.environ.get("J", "0.70"))

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
    revs, bad = _core.declared_revs(text)
    if bad:
        _lib.void(NAME, "ведомость %s не разобрана в блоке `ceiling.rev`: %s"
                  % (LEDGER, "; ".join(bad)))
        return 2

    ps = _core.pin_state(root, revs)
    if ps["findings"] or ps["voids"]:
        for f in ps["findings"]:
            _lib.fail(NAME, f)
        for v in ps["voids"]:
            _lib.void(NAME, "%s — храповик считать не по чему" % v)
        return 1 if ps["findings"] else 2

    # Храповик меряет ПРИ СНЯТЫХ лицензионных исключениях — всегда, независимо
    # от переключателей прогона: неопубликованное решение владельца не должно
    # прятать рост числа копий.
    mp = _core.measure(root, threshold, relicense_busl=True, relicense_agpl=True,
                       revs=ps["pins"])
    if "void" in mp:
        _lib.void(NAME, "%s — храповик считать не по чему" % mp["void"])
        return 2
    if mp["walked"] == 0:
        _lib.void(NAME, "обход ПУСТ — ни одного `.go` ни в одном стволе; «рост 0» здесь "
                        "означало бы «ноль прочитанного»")
        return 2
    at_pin = nums(mp)

    moved = ps["trunks"] != ps["pins"]
    mt = mp
    if moved:
        mt = _core.measure(root, threshold, relicense_busl=True, relicense_agpl=True,
                           revs=ps["trunks"])
        if "void" in mt:
            _lib.void(NAME, "на стволах клонов — %s" % mt["void"])
            return 2
    got = nums(mt)
    slack = dict((k, max(0, want[k] - got[k])) for k in KEYS)

    _lib.census("%s: закреплено %s, осмотрено `.go` %d, сравнимых %d, замерено на нём %s; "
                "объявлено %s; стволы клонов %s%s"
                % (NAME, revs_line(ps["pins"]), mp["walked"], mp["comparable"],
                   fmt(at_pin), fmt(want), revs_line(ps["trunks"]),
                   ("; осмотрено на них `.go` %d, замерено %s, запас %s"
                    % (mt["walked"], fmt(got), fmt(slack))) if moved
                   else " — вровень с закреплёнными"))

    findings = []
    for k in KEYS:
        if at_pin[k] < want[k]:
            findings.append("%s: на закреплённых ревизиях замерено %d, объявлено %d — "
                            "ведомость ПРОСРОЧЕНА на %d. Объявленное сверх замера "
                            "прощает возврат уже вынесенного; затягивается потолок "
                            "перезакреплением ревизий с числами замера на них"
                            % (k, at_pin[k], want[k], want[k] - at_pin[k]))
        elif at_pin[k] > want[k]:
            findings.append("%s: на закреплённых ревизиях замерено %d, объявлено %d — "
                            "ведомость НЕ ВОСПРОИЗВОДИТСЯ, число занижено на %d. Число "
                            "есть утверждение о названных ревизиях; поднять его вместо "
                            "выноса значит снять храповик"
                            % (k, at_pin[k], want[k], at_pin[k] - want[k]))
        if moved and got[k] > want[k]:
            findings.append("%s: на стволах клонов %s замерено %d, объявлено %d — РОСТ на "
                            "%d. Предмет получил прописку, которой у него не было. Исход "
                            "один — вынос: «оставить все три» исходом не является (запрет "
                            "#20, poly-copy-atomic). Перезакрепить ревизии ради роста "
                            "значит снять храповик"
                            % (k, revs_line(ps["trunks"]), got[k], want[k], got[k] - want[k]))

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        return 1
    _lib.passed(NAME, "храповик сошёлся: на закреплённых ревизиях числа воспроизводятся "
                      "точно (%s), на стволах клонов не выросли" % fmt(at_pin))
    return 0


if __name__ == "__main__":
    sys.exit(main())
