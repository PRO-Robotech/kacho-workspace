#!/usr/bin/env python3
"""check-01 — вердикт приёмки читается машинно, а не выводится из слова APPROVED.

Что запрещает эта проверка. Запрет #1 (`.claude/rules/00-kacho-core.md`) — «не
кодить без APPROVED acceptance-дока». Единственная величина, которой этот запрет
измеряется, — сколько приёмок APPROVED. Считать её по упоминанию слова нельзя:
`grep -l APPROVED docs/specs/*acceptance*.md` даёт 110 из 134 отслеживаемых
файлов, потому что слово стоит в КАЖДОМ документе, который объявляет себя
черновиком, ОЖИДАЮЩИМ APPROVED, и в каждом, который просто цитирует запрет.
Двадцать две строки состояния читаются как «DRAFT — awaiting `acceptance-reviewer`
APPROVED»; счёт по слову закрывает их все. Разница между 110 и настоящим числом —
не погрешность, а шестьдесят документов, которые читаются закрытыми, не будучи
закрытыми.

Что здесь считается ОБЪЯВЛЕНИЕМ вердикта — две формы, обе живые в дереве:

  A. помеченная строка: `Статус` / `Status` / `Вердикт` / `Verdict`, в любом
     оформлении (цитата, полужирный), с необязательным уточнением в скобках,
     затем двоеточие и значение — `> **Статус:** ✅ APPROVED (…)`,
     `**Статус (историч.):** ✅ APPROVED`, `> Статус: **APPROVED**`;
  B. строка шапки, начинающаяся с самого вердикта, без метки —
     `> **⛔ WITHDRAWN / SUPERSEDED (2026-07-22, owner-direction):** …`.

Вердикт — ПЕРВЫЙ токен закрытого набора в значении. Порядок несёт смысл:
документ называет своё нынешнее состояние первым, а историю — после. Поэтому
«DRAFT v2 — awaiting … APPROVED» читается как DRAFT, а «✅ APPROVED (round 2 —
все CHANGES REQUESTED раунда 1 адресованы)» — как APPROVED.

Ищется только в ШАПКЕ, до первого заголовка `##`. Ниже начинается тело, где то
же слово стоит в цитате запрета, в таблице трассировки и в чужих вердиктах;
читать его там значило бы вернуться к счёту по упоминанию.

Находка — документ, у которого объявления нет ни в одной форме. Это не «значит
черновик»: вердикт такого документа нельзя прочитать машинно, поэтому запрет #1
на нём не измеряется вовсе, а читатель достраивает вердикт догадкой.

Предмет проверки — `docs/specs/*-acceptance.md`. Он УЖЕ приёмки. Файлы, у
которых слово `acceptance` стоит в имени, но имя не оканчивается на
`-acceptance.md` (сегодня это единственный отчёт о ревью), приёмками не
являются и в предмет не входят — их перечень печатается поимённо, чтобы
сужение было видно, а не подразумевалось.

Исходы: 0 — у каждой приёмки вердикт прочитан; 1 — есть приёмки без
объявления (каждая названа); 2 — читать нечего.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-01-acceptance-verdict"

# Закрытый набор. Порядок ветвей значим: более длинный вердикт стоит раньше, иначе
# `CHANGES REQUESTED` распознался бы как `REQUESTED`, а `NOT APPROVED` — как
# `APPROVED`, то есть ровно наоборот по смыслу.
TOKEN = re.compile(
    r"CHANGES\s+REQUESTED|NOT\s+APPROVED|WITHDRAWN|SUPERSEDED|OBSOLETE|DEPRECATED"
    r"|REJECTED|APPROVED|DRAFT|PROPOSED|WIP|BLOCKED",
    re.I,
)
LABEL = re.compile(
    r"^[\s>*_]*(?:Статус|Status|Вердикт|Verdict)\**\s*(?:\([^)]*\))?\**\s*[:：]\**\s*(.+)$",
    re.I,
)
BARE = re.compile(r"^[\s>*_]*[^\w\s]*\s*\**\s*(" + TOKEN.pattern + r")", re.I)
HEADING = re.compile(r"^#{2,}\s")


def verdict(text):
    """(вердикт, строка-объявление); (None, строка|None) — если вердикта нет."""
    for line in text.split("\n"):
        if HEADING.match(line):
            break
        m = LABEL.match(line)
        if m:
            t = TOKEN.search(m.group(1))
            if t:
                return re.sub(r"\s+", " ", t.group(0).upper()), line.strip()
            # Метка состояния есть, значение вердиктом не читается. Это тоже
            # отсутствие вердикта, и оно обязано быть названо, а не пропущено
            # дальше по шапке: иначе следующая случайная строка станет ответом.
            return None, line.strip()
        m = BARE.match(line)
        if m:
            return re.sub(r"\s+", " ", m.group(1).upper()), line.strip()
    return None, None


def main():
    root = _lib.workspace_root()
    docs = _lib.tracked(root, "docs/specs/*-acceptance.md")
    if not docs:
        _lib.void(NAME, "отслеживаемых docs/specs/*-acceptance.md нет — читать нечего")
        return 2

    named = _lib.tracked(root, "docs/specs/*acceptance*.md")
    outside = [p for p in named if p not in set(docs)]
    _lib.census(
        "%s: приёмок осмотрено %d; файлов со словом acceptance в имени %d, "
        "из них приёмками не являются %d%s"
        % (NAME, len(docs), len(named), len(outside),
           (" (" + ", ".join(outside) + ")") if outside else "")
    )

    tally, missing = {}, []
    for rel in docs:
        v, line = verdict(_lib.read(root, rel))
        if v is None:
            missing.append((rel, line))
        tally[v] = tally.get(v, 0) + 1

    _lib.census(
        "%s: вердикты — %s" % (NAME, ", ".join(
            "%s %d" % (k if k else "БЕЗ ОБЪЯВЛЕНИЯ", n)
            for k, n in sorted(tally.items(), key=lambda kv: (-kv[1], str(kv[0])))))
    )

    if missing:
        for rel, line in missing:
            why = ("метка состояния есть, значение вердиктом не читается: %s" % line
                   if line else "в шапке нет объявления вердикта ни в одной форме")
            _lib.fail(NAME, "%s — %s" % (rel, why))
        _lib.fail(NAME, "приёмок без машинночитаемого вердикта: %d; "
                        "запрет #1 на них не измеряется" % len(missing))
        return 1

    _lib.passed(NAME, "вердикт прочитан у всех %d приёмок" % len(docs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
