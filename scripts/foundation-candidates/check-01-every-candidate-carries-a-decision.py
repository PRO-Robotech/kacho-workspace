#!/usr/bin/env python3
"""check-01 — у предмета со второй пропиской есть ЗАПИСАННОЕ решение.

ЧТО ЭТА ПРОВЕРКА СУДИТ

Требование владельца 2026-09-20 дословно: «все общие библиотеки, которые могут
быть вынесены должны быть вынесены в corelib а не хорониться в проекте». Норма,
которую оно порождает, ОБЯЗЫВАЕТ, а не разрешает; но обязывает она к тому, что
предикат УМЕЕТ ИЗМЕРИТЬ. «Переносимость» он не измеряет — это показано семью
контрпримерами опровержения 2026-09-20, из которых два несут вывод компилятора.
Отсутствие РЕШЕНИЯ он измеряет точно: кандидат без записи в
`docs/foundation-candidates.yaml` — находка; запись, которой в деревьях не
соответствует предмет, — тоже находка.

ПОЧЕМУ НЕ «ОБЯЗАН БЫТЬ ВЫНЕСЕН»

Ложно зачисленный опаснее ложно исключённого: он ломает направление
зависимостей, и ошибка НЕОБРАТИМА — опубликованный тег фундамента из базы
контрольных сумм не отзывается. Поэтому исход записи — два: `move` с задачей
либо `keep` с доводом. Похоронить предмет молчанием нельзя: молчание и есть
находка.

СЕГОДНЯШНЯЯ СИЛА ЭТОЙ ПРОВЕРКИ НАЗЫВАЕТСЯ ЧЕСТНО. Ярус 0 нормы — предусловие:
пока решение владельца о перелицензировании не опубликовано, исключения 4а/4б
держат класс целиком и очередь пуста ПО ПОСТРОЕНИЮ. Значит сегодня здесь
работает вторая половина — САМОИСТЕЧЕНИЕ записи; первая включается в день
публикации. Зубы яруса 1 (третья прописка запрещена) — в `check-02`, и они
работают сегодня.

Исходы: 0 — каждый кандидат несёт решение, записей без предмета нет;
1 — находка; 2 — считать не по чему (клонов нет либо обход пуст).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs-gate"))
import _core  # noqa: E402
import _lib  # noqa: E402

NAME = "check-01-every-candidate-carries-a-decision"
LEDGER = "docs/foundation-candidates.yaml"
DECISIONS = ("move", "keep", "sunset")


def parse(text):
    """{пакет: (решение, задача, довод, строка)}."""
    rows, cur, ln = {}, None, 0
    for i, raw in enumerate(text.split("\n"), 1):
        s = raw.strip()
        if s.startswith("#"):
            continue
        if s.startswith("- package:"):
            if cur:
                rows[cur[0]] = (cur[1], cur[2], cur[3], ln)
            cur = [s.split(":", 1)[1].strip().strip('"'), "", "", ""]
            ln = i
        elif cur is not None and s.startswith("decision:"):
            cur[1] = s.split(":", 1)[1].strip()
        elif cur is not None and s.startswith("issue:"):
            cur[2] = s.split(":", 1)[1].strip().strip('"')
        elif cur is not None and s.startswith("why:"):
            cur[3] = s.split(":", 1)[1].strip().strip('"')
    if cur:
        rows[cur[0]] = (cur[1], cur[2], cur[3], ln)
    return rows


def main():
    root = _lib.workspace_root()
    threshold = float(os.environ.get("J", "0.70"))
    busl = os.environ.get("RELICENSE_BUSL_DECIDED") == "1" or \
        os.environ.get("RELICENSE_DECIDED") == "1"
    agpl = os.environ.get("RELICENSE_AGPL_DECIDED") == "1"

    m = _core.measure(root, threshold, busl, agpl)
    if "void" in m:
        _lib.void(NAME, "%s — второй прописки считать не по чему" % m["void"])
        return 2
    if m["walked"] == 0:
        _lib.void(NAME, "обход ПУСТ — ни одного `.go` ни в одном стволе; «кандидатов 0» "
                        "здесь означало бы «ноль прочитанного»")
        return 2

    text = _lib.read(root, LEDGER)
    if text is None:
        _lib.void(NAME, "ведомость %s не прочитана — судить решения не по чему" % LEDGER)
        return 2
    rows = parse(text)

    _lib.census("%s: стволов %d (%s); осмотрено `.go` %d, сравнимых %d; ПРЕДМЕТОВ со "
                "второй пропиской %d (файлов %d); КАНДИДАТОВ после восьми исключений %d; "
                "записей ведомости %d"
                % (NAME, len(m["trees"]),
                   ", ".join("%s@%s=%d" % (n, m["trees"][n][2], m["trees"][n][3])
                             for n in sorted(m["trees"])),
                   m["walked"], m["comparable"], m["subjects"], m["subject_files"],
                   len(m["candidates"]), len(rows)))

    findings = []
    for c in m["candidates"]:
        pkgs = sorted({"%s:%s" % (f.split(":", 1)[0], os.path.dirname(f.split(":", 1)[1]))
                       for f in c["files"]})
        if not any(p in rows for p in pkgs):
            findings.append("предмет в домах %s (адрес выноса: %s) НЕ несёт решения: "
                            "копии %s. Исходы два — `move` с задачей либо `keep` с доводом; "
                            "молчание исходом не является"
                            % ("+".join(c["homes"]), c["address"], ", ".join(c["files"])))
    for pkg, (dec, issue, why, ln) in sorted(rows.items()):
        if dec not in DECISIONS:
            findings.append("%s:%d — решение %r вне закрытого словаря %s"
                            % (LEDGER, ln, dec, list(DECISIONS)))
            continue
        if dec in ("move", "sunset") and not issue:
            findings.append("%s:%d — %s без задачи: за обязанностью никто не отвечает"
                            % (LEDGER, ln, dec))
            continue
        if dec == "keep" and not why:
            findings.append("%s:%d — отказ от выноса без довода: «по усмотрению» под эту "
                            "строку подставляется что угодно" % (LEDGER, ln))
            continue
        if pkg not in m["second_home_dirs"]:
            findings.append("%s:%d — запись о %s, у которого второй прописки в стволах "
                            "БОЛЬШЕ НЕТ: самоистечение. Снимите запись тем же изменением, "
                            "которым снят её предмет" % (LEDGER, ln, pkg))

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        return 1

    if not m["candidates"]:
        _lib.passed(NAME, "очередь пуста при %d предметах со второй пропиской — сегодня "
                          "по построению: решение владельца о перелицензировании не "
                          "опубликовано, исключения 4а/4б держат класс целиком. Пустая "
                          "ведомость есть ЦЕЛЬ; записей без предмета нет (%d)"
                    % (m["subjects"], len(rows)))
    else:
        _lib.passed(NAME, "решение несут все %d кандидатов; записей без предмета нет "
                          "(записей %d)" % (len(m["candidates"]), len(rows)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
