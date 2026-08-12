#!/usr/bin/env python3
"""check-03 — строка Scope приёмки обязана иметь сценарий, который её проверяет.

Что запрещает эта проверка. Приёмка — документ СЦЕНАРИЕВ: запрет #1
(`.claude/rules/00-kacho-core.md`) велит не кодить без APPROVED приёмки
Given-When-Then, то есть основанием для кода служит сценарий, а не строка
перечня. Строка таблицы Scope без сценария не проверяется ничем: она называет
фичу, но не говорит, что должно быть наблюдаемо, поэтому по ней нельзя ни
написать пробу, ни отличить сделанное от заявленного. Такая строка читается как
покрытие и покрытием не является.

Класс найден на живой правке: продуктовое изменение внесло в приёмку одну строку
Scope и ни одного сценария, а её положение в перечне сделало неоднозначными
ссылки на соседний идентификатор. Строка при этом выглядела как работа —
описание в ней было подробным.

Предмет — приёмки, которые объявляют состав ФИЧАМИ: строками таблицы вида
`| F7 | … |`. Прочие приёмки объявляют состав иначе (решениями с колонкой
сценариев, темами, вопросами) — у них другой механизм, и он этой проверкой не
меряется. Оба числа печатаются, чтобы сужение предмета было видно, а «находок
ноль» не читалось как «прочитано ноль».

Что считается сценарием: в разделе фичи (`## F7 — …` до следующего заголовка
второго уровня) есть хотя бы одна полужирная строка `**When**` и хотя бы одна
`**Then**`. `**Given**` не требуется: предусловия у части сценариев нет вовсе, и
требовать его значило бы краснеть на законной форме.

Задокументированная передача. Раздел вправе не нести сценариев, если он прямо
называет ДОЧЕРНЮЮ приёмку, где они живут (родитель фиксирует контракт-инвариант,
ребёнок — сценарии). Послабление **истекает само**: проверка резолвит имя
дочернего документа в дереве и требует, чтобы в нём был раздел ТОГО ЖЕ
идентификатора и в нём был сценарий. Переименуют или выпотрошат ребёнка —
передача перестанет резолвиться и станет находкой.

Предпосылка собственного молчания. Единственный способ для этой проверки
промолчать без предмета — потерять сам предмет: перестанет совпадать строка
таблицы (сменился формат перечня) — и проверять станет нечего. Этот исход
объявлен отдельно (код 2), а не выдан за «находок ноль». Обратный отказ —
поломка распознавателя сценария — промолчать НЕ может по построению: если он
перестанет узнавать сценарии, каждая строка Scope станет находкой, то есть
поломка будет громкой. Поэтому отдельной ветки на неё здесь нет: ветка,
недостижимая по построению, — мёртвый код, а не защита.

Исходы: 0 — у каждой строки Scope есть сценарий (или резолвящаяся передача);
1 — есть строки без сценария (каждая названа координатой); 2 — предмета нет.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-03-scope-row-scenario"

# Строка таблицы Scope: первая ячейка — идентификатор фичи `F<число>[буква]`.
ROW = re.compile(r"^\|\s*\**\s*(F\d+[A-Za-z]?)\s*\**\s*\|")
# Заголовок раздела фичи. Граница слова не даёт `F7` совпасть с `F7a`, а `F1` — с `F10`.
HEAD = re.compile(r"^#{2,3}\s*\**\s*(F\d+[A-Za-z]?)\b")
LVL2 = re.compile(r"^##\s")
# Маркеры сценария — ПОЛУЖИРНЫЕ, как их пишут в корпусе. Голое слово в прозе
# маркером не считается: распознаватель, принимающий прозу, молчит там, где
# сценария нет.
WHEN = re.compile(r"^[\s>_-]*\*\*\s*(?:When|Когда)\b")
THEN = re.compile(r"^[\s>_-]*\*\*\s*(?:Then|Тогда)\b")
# Ссылка на дочернюю приёмку: имя файла или его начало (в корпусе встречается
# усечённая форма с многоточием).
CHILD = re.compile(r"sub-phase-[A-Za-z0-9._-]+")


def sections(lines):
    """id фичи -> (номер строки заголовка, тело раздела)."""
    out, cur, start, body = {}, None, 0, []
    for n, line in enumerate(lines, 1):
        m = HEAD.match(line)
        if m:
            if cur:
                out.setdefault(cur, (start, body))
            cur, start, body = m.group(1), n, []
            continue
        if LVL2.match(line) and cur:
            out.setdefault(cur, (start, body))
            cur, body = None, []
            continue
        if cur:
            body.append(line)
    if cur:
        out.setdefault(cur, (start, body))
    return out


def has_scenario(body):
    return any(WHEN.match(l) for l in body) and any(THEN.match(l) for l in body)


def scope_rows(lines):
    """[(id, номер строки)] в порядке объявления, без повторов."""
    seen, out = set(), []
    for n, line in enumerate(lines, 1):
        m = ROW.match(line)
        if m and m.group(1) not in seen:
            seen.add(m.group(1))
            out.append((m.group(1), n))
    return out


def delegation(body, fid, rel, parsed):
    """(имя дочернего документа, None) если передача резолвится; иначе (None, причина)."""
    names = []
    for tok in CHILD.findall("\n".join(body)):
        tok = tok.rstrip("-._")
        hits = [r for r in parsed if r != rel and os.path.basename(r).startswith(tok)]
        if len(hits) == 1:
            names.append(hits[0])
    if not names:
        return None, "раздел не называет дочернюю приёмку"
    for child in names:
        sec = parsed[child].get(fid)
        if sec and has_scenario(sec[1]):
            return child, None
    return None, ("названа дочерняя приёмка %s, но раздела %s со сценарием в ней нет"
                  % (", ".join(sorted(set(names))), fid))


def main():
    root = _lib.workspace_root()
    docs = _lib.tracked(root, "docs/specs/*-acceptance.md")
    if not docs:
        _lib.void(NAME, "отслеживаемых docs/specs/*-acceptance.md нет — читать нечего")
        return 2

    parsed, rows, other = {}, {}, []
    for rel in docs:
        lines = _lib.read(root, rel).split("\n")
        rs = scope_rows(lines)
        if not rs:
            other.append(rel)
            continue
        rows[rel] = rs
        parsed[rel] = sections(lines)
    # Дочерний документ может сам не объявлять фич строками таблицы — разобрать
    # его всё равно надо, иначе передача не резолвится по причине, к предмету
    # передачи отношения не имеющей.
    for rel in other:
        parsed.setdefault(rel, sections(_lib.read(root, rel).split("\n")))

    if not rows:
        _lib.void(NAME, "ни одна приёмка не объявляет фичи строками `| F<N> |` — "
                        "предмета у проверки нет")
        return 2

    total = sum(len(v) for v in rows.values())
    _lib.census(
        "%s: приёмок осмотрено %d; объявляют состав фичами `| F<N> |` — %d, "
        "остальные %d объявляют его иначе и в предмет не входят"
        % (NAME, len(docs), len(rows), len(other))
    )

    findings, ok, passed_on, handovers = [], 0, 0, []
    for rel, rs in rows.items():
        secs = parsed[rel]
        for fid, ln in rs:
            sec = secs.get(fid)
            if sec is None:
                findings.append((rel, ln, fid, "раздела `## %s` в документе нет вовсе" % fid))
                continue
            if has_scenario(sec[1]):
                ok += 1
                continue
            child, why = delegation(sec[1], fid, rel, parsed)
            if child:
                passed_on += 1
                handovers.append("%s %s → %s" % (os.path.basename(rel), fid,
                                                 os.path.basename(child)))
                continue
            findings.append((rel, ln, fid,
                             "раздел есть, сценария (`**When**` + `**Then**`) в нём нет; " + why))

    _lib.census(
        "%s: строк Scope прочитано %d; со сценарием %d; передано в дочернюю приёмку %d%s"
        % (NAME, total, ok, passed_on,
           (" (" + "; ".join(handovers) + ")") if handovers else "")
    )

    if findings:
        for rel, ln, fid, why in findings:
            _lib.fail(NAME, "%s:%d — %s: %s" % (rel, ln, fid, why))
        _lib.fail(NAME, "строк Scope без сценария: %d; по ним нельзя ни написать пробу, "
                        "ни отличить сделанное от заявленного" % len(findings))
        return 1

    _lib.passed(NAME, "у всех %d строк Scope есть сценарий (%d прямо, %d передачей)"
                      % (total, ok, passed_on))
    return 0


if __name__ == "__main__":
    sys.exit(main())
