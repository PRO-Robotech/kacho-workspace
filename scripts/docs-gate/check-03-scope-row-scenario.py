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

Где строка Scope. Строкой Scope считается строка `| F<N> |` ТОЛЬКО внутри
раздела второго уровня, в заголовке которого стоит слово `Scope` (до следующего
заголовка первого или второго уровня). Первая ячейка вида `F<N>` встречается и
в других таблицах: приёмка NTF-1 нумерует сценарии `F02…F19` и сводит их в
таблицы «сценарий → производитель» и «близнецы» — это ссылки на сценарии, а не
состав, и при прежнем распознавателе (любая строка документа) они давали
четырнадцать ложных находок «раздела нет вовсе». Строки `| F<N> |` вне раздела
Scope не судятся, но СЧИТАЮТСЯ и печатаются переписью: сужение предмета видно
числом, а документ, чей состав переехал из раздела Scope, переходит в «объявляют
состав иначе» и тоже виден в переписи.

Неотображаемые области. Внутри блока кода (ограда ``` или ~~~, в том числе
после маркера пункта списка) и внутри HTML-комментария `<!-- … -->` строка `# …`
не заголовок, `| F<N> |` не строка таблицы, `**When**` не маркер сценария.
Распознаватель, не знающий этих областей, принимал `# комментарий` из блока
`bash` за заголовок первого уровня: раздел Scope закрывался, весь состав ниже
выпадал из предмета, а итог оставался PASS. Поэтому ВСЯ структура документа —
разделы Scope, разделы фич, строки, маркеры сценария — читается по тексту, из
которого эти области вынуты (`rendered`). Строки `| F<N> |`, оказавшиеся внутри
них, не судятся, но считаются переписью. Незакрытая область поглощает остаток
документа — и для читателя, и для проверки; если в поглощённом есть непустые
строки, это находка с координатой открытия, а не молчание. Ограда на последней
строке документа не поглощает ничего и находкой не является.

Исходы: 0 — у каждой строки Scope есть сценарий (или резолвящаяся передача);
1 — есть строки без сценария либо незакрытая область, поглощающая текст (каждая
названа координатой); 2 — предмета нет.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

NAME = "check-03-scope-row-scenario"

# Строка таблицы с первой ячейкой — идентификатором `F<число>[буква]`. Строкой
# Scope она становится только внутри раздела SCOPE_HEAD (см. `scope_rows`).
ROW = re.compile(r"^\|\s*\**\s*(F\d+[A-Za-z]?)\s*\**\s*\|")
# Заголовок раздела Scope: ровно второй уровень, слово `Scope` целиком. Раздел
# длится до следующего заголовка первого или второго уровня; подразделы `###`
# внутри него остаются в разделе.
SCOPE_HEAD = re.compile(r"^##(?!#)\s.*\bScope\b")
TOP = re.compile(r"^#{1,2}(?!#)\s")
# Заголовок раздела фичи. Граница слова не даёт `F7` совпасть с `F7a`, а `F1` — с `F10`.
HEAD = re.compile(r"^#{2,3}\s*\**\s*(F\d+[A-Za-z]?)\b")
LVL2 = re.compile(r"^##\s")
# Маркеры сценария — ПОЛУЖИРНЫЕ, как их пишут в корпусе. Голое слово в прозе
# маркером не считается: распознаватель, принимающий прозу, молчит там, где
# сценария нет.
WHEN = re.compile(r"^[\s>_-]*\*\*\s*(?:When|Когда)\b")
THEN = re.compile(r"^[\s>_-]*\*\*\s*(?:Then|Тогда)\b")
# Ограда блока кода: необязательный отступ, необязательный маркер пункта списка,
# три и более одинаковых символа. У ограды из обратных кавычек в строке сведений
# обратной кавычки быть не может (иначе это встроенный код, а не ограда).
FENCE = re.compile(r"^[ \t]*(?:(?:[-*+]|\d+[.)])[ \t]+)?(`{3,}|~{3,})(.*)$")
COMMENT_OPEN = "<!--"
COMMENT_CLOSE = "-->"
# Ссылка на дочернюю приёмку: имя файла или его начало (в корпусе встречается
# усечённая форма с многоточием).
CHILD = re.compile(r"sub-phase-[A-Za-z0-9._-]+")


def rendered(lines):
    """Текст, из которого вынуты блоки кода и HTML-комментарии.

    Возвращает (строки той же длины — вынутая строка заменена пустой, поэтому
    номера строк сохраняются; число строк `| F<N> |` внутри вынутого; незакрытая
    область как (номер строки открытия, вид, непустых поглощённых строк) либо None).
    """
    out, hidden_rows = [], 0
    fence, comment = None, None  # fence: (символ, длина, строка); comment: строка
    for n, line in enumerate(lines, 1):
        if fence:
            m = FENCE.match(line)
            if (m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1]
                    and not m.group(2).strip()):
                fence = None
            elif ROW.match(line):
                hidden_rows += 1
            out.append("")
            continue
        if comment:
            if COMMENT_CLOSE in line:
                comment = None
            elif ROW.match(line):
                hidden_rows += 1
            out.append("")
            continue
        m = FENCE.match(line)
        if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
            fence = (m.group(1)[0], len(m.group(1)), n)
            out.append("")
            continue
        if line.lstrip().startswith(COMMENT_OPEN):
            if COMMENT_CLOSE not in line.split(COMMENT_OPEN, 1)[1]:
                comment = n
            out.append("")
            continue
        out.append(line)
    unclosed = None
    if fence or comment:
        start = fence[2] if fence else comment
        kind = "блок кода (%s)" % (fence[0] * fence[1]) if fence else "HTML-комментарий"
        swallowed = sum(1 for l in lines[start:] if l.strip())
        if swallowed:
            unclosed = (start, kind, swallowed)
    return out, hidden_rows, unclosed


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
    """([(id, номер строки)] строк раздела Scope в порядке объявления, без
    повторов; число строк `| F<N> |` ВНЕ раздела Scope)."""
    seen, out, outside, in_scope = set(), [], 0, False
    for n, line in enumerate(lines, 1):
        if TOP.match(line):
            in_scope = bool(SCOPE_HEAD.match(line))
            continue
        m = ROW.match(line)
        if not m:
            continue
        if not in_scope:
            outside += 1
            continue
        if m.group(1) not in seen:
            seen.add(m.group(1))
            out.append((m.group(1), n))
    return out, outside


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

    parsed, rows, other, texts = {}, {}, [], {}
    outside_rows, outside_docs = 0, 0
    hidden_rows, hidden_docs, unclosed = 0, 0, []
    for rel in docs:
        lines, hidden, open_at = rendered(_lib.read(root, rel).split("\n"))
        texts[rel] = lines
        if hidden:
            hidden_rows += hidden
            hidden_docs += 1
        if open_at:
            unclosed.append((rel,) + open_at)
        rs, outside = scope_rows(lines)
        if outside:
            outside_rows += outside
            outside_docs += 1
        if not rs:
            other.append(rel)
            continue
        rows[rel] = rs
        parsed[rel] = sections(lines)
    # Дочерний документ может сам не объявлять фич строками таблицы — разобрать
    # его всё равно надо, иначе передача не резолвится по причине, к предмету
    # передачи отношения не имеющей.
    for rel in other:
        parsed.setdefault(rel, sections(texts[rel]))

    # Незакрытая область судится ДО вопроса о предмете: поглотив раздел Scope,
    # она увела бы документ в «объявляют состав иначе» или весь обход — в VOID.
    for rel, ln, kind, swallowed in unclosed:
        _lib.fail(NAME, "%s:%d — незакрытый %s поглощает %d непустых строк до конца "
                        "документа: ни читатель, ни проверка их структуры не видят"
                  % (rel, ln, kind, swallowed))

    if not rows and not unclosed:
        _lib.void(NAME, "ни одна приёмка не объявляет фичи строками `| F<N> |` в "
                        "разделе `## … Scope …` (строк `| F<N> |` вне раздела Scope: "
                        "%d) — предмета у проверки нет" % outside_rows)
        return 2

    total = sum(len(v) for v in rows.values())
    _lib.census(
        "%s: приёмок осмотрено %d; объявляют состав фичами `| F<N> |` в разделе "
        "Scope — %d, остальные %d объявляют его иначе и в предмет не входят; строк "
        "`| F<N> |` вне раздела Scope (не состав, не судятся) — %d в %d документах; "
        "в блоках кода и HTML-комментариях (не таблица, не судятся) — %d в %d документах"
        % (NAME, len(docs), len(rows), len(other), outside_rows, outside_docs,
           hidden_rows, hidden_docs)
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

    if findings or unclosed:
        for rel, ln, fid, why in findings:
            _lib.fail(NAME, "%s:%d — %s: %s" % (rel, ln, fid, why))
        _lib.fail(NAME, "строк Scope без сценария: %d; незакрытых областей, поглощающих "
                        "текст: %d; по ним нельзя ни написать пробу, ни отличить "
                        "сделанное от заявленного" % (len(findings), len(unclosed)))
        return 1

    _lib.passed(NAME, "у всех %d строк Scope есть сценарий (%d прямо, %d передачей)"
                      % (total, ok, passed_on))
    return 0


if __name__ == "__main__":
    sys.exit(main())
