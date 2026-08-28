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

Формы объявления и правило выбора вердикта живут в ОДНОМ месте — `_lib.verdict`,
и это не вынос ради опрятности: домов у приёмок ДВА — этот и дерево продукта
(`services/<svc>/docs/engineering/acceptance/`, читает `check-04`). Запрет #1 на
них один, значит и распознаватель обязан быть один: две копии разошлись бы молча
и ровно там, где обе отвечают «вердикт прочитан».

Находка — документ, у которого объявления нет ни в одной форме. Это не «значит
черновик»: вердикт такого документа нельзя прочитать машинно, поэтому запрет #1
на нём не измеряется вовсе, а читатель достраивает вердикт догадкой.

Предмет проверки — `docs/specs/*-acceptance.md`. Он УЖЕ приёмки. Файлы, у
которых слово `acceptance` стоит в имени, но имя не оканчивается на
`-acceptance.md` (сегодня это единственный отчёт о ревью), приёмками не
являются и в предмет не входят — их перечень печатается поимённо, чтобы
сужение было видно, а не подразумевалось. Приёмки дерева ПРОДУКТА сюда не
попадают by construction (другой репозиторий) — их читает `check-04`, тем же
распознавателем и с теми же исходами.

Исходы: 0 — у каждой приёмки вердикт прочитан; 1 — есть приёмки без
объявления (каждая названа); 2 — читать нечего.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-01-acceptance-verdict"


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
        v, line = _lib.verdict(_lib.read(root, rel))
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
