#!/usr/bin/env python3
"""check-04 — вердикт приёмки, живущей в дереве ПРОДУКТА, читается так же машинно.

ЗАЧЕМ ЭТА ПРОВЕРКА СУЩЕСТВУЕТ

Запрет #1 (`.claude/rules/00-kacho-core.md`) — «не кодить без APPROVED
acceptance-дока» — один на весь продукт, а домов у приёмок ДВА, и это решение, а
не недосмотр: предмет, целиком лежащий внутри одного сервиса, описывается рядом
с его кодом (`services/<svc>/docs/engineering/acceptance/`), потому что держать
решение и код в разных деревьях хуже; кросс-доменный предмет живёт в воркспейсе
(`docs/specs/*-acceptance.md`, читает `check-01`).

Пока читался только первый дом, слово APPROVED в шапке второго не отличалось
ничем от слова, которое туда вписали: вердикт не проверялся, и запрет #1 на этих
документах не измерялся вовсе (`PRO-Robotech/kacho-workspace#402`).

ЧТО ЗДЕСЬ ПРЕДМЕТ — ВИД ДОКУМЕНТА, А НЕ КАТАЛОГ

Приёмкой считается отслеживаемый `.md` дерева продукта, у которого ЛИБО путь
несёт сегмент `acceptance/`, ЛИБО имя оканчивается на `-acceptance.md`. Два
условия, а не одно, потому что дома называют свои документы по-разному, и
предикат, знающий одно имя, мерил бы КАТАЛОГ: на 2026-08-28 сегмент даёт в
дереве продукта 4 документа и 0 в воркспейсе, а имя — 0 в продукте и 170 в
воркспейсе. Тот же предикат целиком, применённый к воркспейсу, находит его
приёмки — значит он измеряет вид документа, а не место. Перепись печатает вклад
каждой формы отдельно: форма, давшая ноль, обязана быть видна, иначе слепая зона
неотличима от чистого дерева.

ЧЕМ ЧИТАЕТСЯ ВЕРДИКТ

Тем же `_lib.verdict`, что и у `check-01`, — одна функция, а не копия: две копии
разошлись бы молча и ровно там, где обе отвечают «вердикт прочитан». Формы
объявления и правило «первый токен в значении» описаны там.

ГДЕ СУДИТСЯ — В СТВОЛЕ ПРОДУКТА, А НЕ В РАБОЧЕЙ КОПИИ РЯДОМ

Дерево читается по `origin/main` продукта, а не по индексу лежащей рядом копии.
Копия общая и отстаёт: в день заведения проверки она отставала на 103 коммита и
несла ОДНУ приёмку из четырёх — то есть три документа были бы не «без находок», а
непрочитанными, и строка «осмотрено 1» выглядела бы ровно так же уверенно, как
«осмотрено 4». Тот же выбор и по той же причине сделан у хука свежести
(`multi-agent-flow.md` §8): вердикт выносится по стволу, отставание копии
называется ЧИСЛОМ.

Ствол не резолвится (клон без этой ссылки) — судится индекс копии, и перепись
говорит это прямо, а не подставляет молча.

ПРЕДПОСЫЛКА И ЕЁ ИСХОД

Нужно дерево продукта: `KACHO_MONOREPO`, иначе `project/kacho` от корня
воркспейса (резолюция та же, что у `vault-gate`). Нет дерева — **VOID**, а не
успех: «нечего проверять» обязано быть отличимо от «находок ноль», и `run-all.sh`
третий исход в успех не засчитывает.

Исходы: 0 — у каждой приёмки продукта вердикт прочитан; 1 — есть приёмки без
объявления (каждая названа); 2 — читать нечего.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-04-product-acceptance-verdict"

# Обе формы имени, которыми дома называют приёмки. Перечень закрыт и печатается
# переписью пофомно — форма, давшая ноль, обязана быть видна.
BY_DIR = "приёмка в каталоге `acceptance/`"
BY_NAME = "имя `*-acceptance.md`"


def _git(repo, args):
    out = subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True)
    return out.stdout if out.returncode == 0 else None


def source(repo):
    """(ссылка|None, как называть источник) — ствол продукта либо индекс копии."""
    if _git(repo, ["rev-parse", "--verify", "--quiet", "origin/main"]):
        return "origin/main", "ствол origin/main"
    return None, "ИНДЕКС рабочей копии (ствол origin/main не резолвится)"


def product_docs(repo, ref):
    """[(путь, форма)] — приёмки дерева продукта на названном источнике."""
    if ref:
        raw = _git(repo, ["ls-tree", "-r", "--name-only", ref]) or ""
    else:
        raw = _git(repo, ["ls-files", "--cached", "--others",
                          "--exclude-standard", "*.md"]) or ""
    found = []
    for rel in sorted(set(p for p in raw.split("\n") if p.endswith(".md"))):
        parts = rel.split("/")
        if "acceptance" in parts[:-1]:
            found.append((rel, BY_DIR))
        elif rel.endswith("-acceptance.md"):
            found.append((rel, BY_NAME))
    return found


def _read(repo, ref, rel):
    if ref:
        return _git(repo, ["show", "%s:%s" % (ref, rel)])
    path = os.path.join(repo, rel)
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return None


def main():
    root = _lib.workspace_root()
    repo = _lib.monorepo(root)
    if repo is None:
        _lib.void(NAME, "дерево продукта не найдено (ни KACHO_MONOREPO, ни "
                        "project/kacho) — второй дом приёмок читать не в чем")
        return 2

    ref, how = source(repo)
    docs = product_docs(repo, ref)
    head, behind = _lib.head_and_lag(repo)
    where = "%s, %s" % (repo, how)
    if behind:
        where += "; рабочая копия @ %s ОТСТАЁТ от него на %d" % (head, behind)

    if not docs:
        _lib.void(NAME, "в дереве продукта (%s) приёмок не найдено ни одной из "
                        "двух форм — читать нечего" % where)
        return 2

    by_form = {}
    for _, form in docs:
        by_form[form] = by_form.get(form, 0) + 1
    _lib.census(
        "%s: дерево продукта %s; приёмок осмотрено %d — %s"
        % (NAME, where, len(docs),
           ", ".join("%s: %d" % (f, by_form.get(f, 0)) for f in (BY_DIR, BY_NAME)))
    )

    UNREADABLE = object()
    tally, missing = {}, []
    for rel, _form in docs:
        text = _read(repo, ref, rel)
        if text is None:
            # Путь назван источником, содержимого нет. Это не «вердикта нет» —
            # это «прочитать не удалось», и молча зачесть его в любую корзину
            # значило бы соврать в обе стороны сразу.
            missing.append((rel, UNREADABLE))
            tally["НЕ ПРОЧИТАНО"] = tally.get("НЕ ПРОЧИТАНО", 0) + 1
            continue
        v, line = _lib.verdict(text)
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
            if line is UNREADABLE:
                why = "источник называет путь, содержимое не читается"
            elif line:
                why = "метка состояния есть, значение вердиктом не читается: %s" % line
            else:
                why = "в шапке нет объявления вердикта ни в одной форме"
            _lib.fail(NAME, "%s — %s" % (rel, why))
        _lib.fail(NAME, "приёмок продукта без машинночитаемого вердикта: %d; "
                        "запрет #1 на них не измеряется" % len(missing))
        return 1

    _lib.passed(NAME, "вердикт прочитан у всех %d приёмок дерева продукта" % len(docs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
