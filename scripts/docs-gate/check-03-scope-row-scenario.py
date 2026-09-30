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

Разбор — CommonMark, а не строки. Всю структуру документа (заголовки разделов
Scope и фич, строки таблиц, маркеры сценария, ссылку на дочернюю приёмку)
проверка берёт из дерева разбора `markdown-it-py` (набор правил CommonMark плюс
таблицы) — тем же, что видит читатель. Два прежних круга построчных регулярок
ошибались в одну сторону: `# комментарий` из блока `bash` закрывал раздел Scope,
отступленная ограда внутри блока или ограда после маркера списка открывала
«блок», которого нет, комментарий посреди строки и блок кода внутри цитаты не
узнавались — и каждый раз состав или сценарий выпадал из предмета при итоге PASS.
Правила вложенности (отступ ограды, контейнер-цитата, пункт списка, HTML-блок
против встроенного HTML) — ровно то, что держит разборщик, и переписывать их
здесь третий раз значило бы завести третью неполную копию. Разборщик — внешняя
зависимость проверки: его нет — это VOID с причиной, а не зелёное; версия
печатается переписью и в конвейере закреплена.

Что из дерева разбора берётся. Раздел Scope — заголовок второго уровня (ATX или
setext) вне контейнера со словом `Scope`; длится до следующего заголовка первого
или второго уровня вне контейнера. Строка Scope — строка таблицы (любой
вложенности) внутри раздела, первая ячейка — `F<N>`, в том числе полужирная.
Раздел фичи — заголовок второго или третьего уровня вне контейнера, текст
которого начинается с `F<N>`; закрывается следующим заголовком второго уровня.
Маркер сценария — полужирный фрагмент `When`/`Когда` (`Then`/`Тогда`) в начале
строки видимого текста; встроенный HTML-комментарий и пробелы перед ним начала
строки не отменяют. Текст раздела для передачи — видимый текст, встроенный код и
адреса ссылок.

Неотображаемое. Строки вида `| F<N> |` внутри блока кода или HTML-блока не
таблица и не судятся, но считаются переписью. Незакрытая ограда или незакрытый
HTML-комментарий, поглотившие непустой текст, — находка с координатой открытия:
поглощённого не видят ни читатель, ни проверка. Ограда на последней строке
документа не поглощает ничего и находкой не является.

Исходы: 0 — у каждой строки Scope есть сценарий (или резолвящаяся передача);
1 — есть строки без сценария либо незакрытая область, поглощающая текст (каждая
названа координатой); 2 — предмета нет либо нечем разбирать.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _lib  # noqa: E402

try:
    import markdown_it  # noqa: E402
    from markdown_it import MarkdownIt  # noqa: E402
except ImportError:  # pragma: no cover — исход объявлен в main()
    markdown_it = None

NAME = "check-03-scope-row-scenario"

# Первая ячейка строки состава: `F<число>[буква]`, возможно полужирная.
CELL = re.compile(r"^\**\s*(F\d+[A-Za-z]?)\s*\**$")
# Слово `Scope` целиком в тексте заголовка второго уровня.
SCOPE_WORD = re.compile(r"\bScope\b")
# Текст заголовка раздела фичи. Граница слова не даёт `F7` совпасть с `F7a`, а `F1` — с `F10`.
HEAD = re.compile(r"^\s*\**\s*(F\d+[A-Za-z]?)\b")
# Маркеры сценария — ПОЛУЖИРНЫЕ, как их пишут в корпусе. Голое слово в прозе
# маркером не считается: распознаватель, принимающий прозу, молчит там, где
# сценария нет.
WHEN = re.compile(r"^\s*(?:When|Когда)\b")
THEN = re.compile(r"^\s*(?:Then|Тогда)\b")
# Строка, похожая на строку состава, в исходном тексте — для переписи того, что
# оказалось внутри неотображаемого.
ROWLIKE = re.compile(r"^\s*\|\s*\**\s*F\d+[A-Za-z]?\s*\**\s*\|")
# Ссылка на дочернюю приёмку: имя файла или его начало (в корпусе встречается
# усечённая форма с многоточием).
CHILD = re.compile(r"sub-phase-[A-Za-z0-9._-]+")
# Префикс контейнеров перед закрывающей оградой: цитаты и отступ пункта списка.
CONTAINER = re.compile(r"^(?:[ \t]*>)*[ \t]*")


def parser():
    return MarkdownIt("commonmark").enable("table")


class Section:
    __slots__ = ("start", "text", "when", "then")

    def __init__(self, start):
        self.start, self.text, self.when, self.then = start, [], False, False


def _markers(inline, sec):
    """Маркеры сценария и видимый текст одного встроенного фрагмента."""
    line_start, pending = True, None
    for c in inline.children or []:
        t = c.type
        if t == "text":
            sec.text.append(c.content)
            if pending is not None:
                if WHEN.match(c.content):
                    sec.when = True
                if THEN.match(c.content):
                    sec.then = True
                pending = None
            if c.content.strip():
                line_start = False
            continue
        pending = None
        if t == "code_inline":
            sec.text.append(c.content)
            line_start = False
        elif t == "link_open":
            sec.text.append(c.attrGet("href") or "")
        elif t in ("softbreak", "hardbreak"):
            line_start = True
        elif t == "strong_open":
            pending = True if line_start else None
            line_start = False
        elif t in ("em_open", "html_inline"):
            pass  # не видимый текст: начала строки не отменяют
        else:
            line_start = False


def _fence_closed(lines, tok):
    first, end = tok.map
    if end - 1 <= first or end > len(lines):
        return False
    tail = CONTAINER.sub("", lines[end - 1], count=1).rstrip()
    ch, n = tok.markup[0], len(tok.markup)
    return len(tail) >= n and set(tail) == {ch}


def analyse(src):
    """Структура документа по дереву разбора.

    Возвращает dict: rows — [(id, строка)] строк раздела Scope без повторов;
    outside — строк состава вне раздела Scope; secs — id -> Section; hidden —
    строк вида `| F<N> |` внутри блоков кода и HTML-блоков; unclosed —
    [(строка открытия, вид, непустых поглощённых строк)].
    """
    lines = src.split("\n")
    toks = parser().parse(src)
    rows, seen, outside, hidden, unclosed = [], set(), 0, 0, []
    secs, cur, in_scope = {}, None, False
    for i, tok in enumerate(toks):
        t = tok.type
        if t == "heading_open":
            text = toks[i + 1].content
            if tok.level == 0 and tok.tag in ("h1", "h2"):
                in_scope = tok.tag == "h2" and bool(SCOPE_WORD.search(text))
            if tok.level == 0 and tok.tag in ("h2", "h3") and HEAD.match(text):
                fid = HEAD.match(text).group(1)
                cur = Section(tok.map[0] + 1)
                if fid not in secs:
                    secs[fid] = cur
                else:
                    cur = Section(tok.map[0] + 1)  # повтор: первый раздел в силе
                continue
            if tok.level == 0 and tok.tag == "h2":
                cur = None
            continue
        if t == "tr_open":
            j = i + 1
            while toks[j].type not in ("td_open", "th_open"):
                j += 1
            m = CELL.match(toks[j + 1].content.strip())
            if m:
                if not in_scope:
                    outside += 1
                elif m.group(1) not in seen:
                    seen.add(m.group(1))
                    rows.append((m.group(1), tok.map[0] + 1))
            continue
        if t in ("fence", "code_block", "html_block"):
            hidden += sum(1 for l in tok.content.split("\n") if ROWLIKE.match(l))
            body = [l for l in tok.content.split("\n")[1:] if l.strip()]
            if t == "fence" and not _fence_closed(lines, tok) and tok.content.strip():
                unclosed.append((tok.map[0] + 1, "блок кода (%s)" % tok.markup,
                                 sum(1 for l in tok.content.split("\n") if l.strip())))
            elif (t == "html_block" and tok.content.lstrip().startswith("<!--")
                    and "-->" not in tok.content and body):
                unclosed.append((tok.map[0] + 1, "HTML-комментарий", len(body)))
            continue
        if t == "inline" and cur is not None:
            _markers(tok, cur)
    return {"rows": rows, "outside": outside, "secs": secs,
            "hidden": hidden, "unclosed": unclosed}


def has_scenario(sec):
    return sec.when and sec.then


def delegation(sec, fid, rel, parsed):
    """(имя дочернего документа, None) если передача резолвится; иначе (None, причина)."""
    names = []
    for tok in CHILD.findall("\n".join(sec.text)):
        tok = tok.rstrip("-._")
        hits = [r for r in parsed if r != rel and os.path.basename(r).startswith(tok)]
        if len(hits) == 1:
            names.append(hits[0])
    if not names:
        return None, "раздел не называет дочернюю приёмку"
    for child in names:
        sec = parsed[child].get(fid)
        if sec and has_scenario(sec):
            return child, None
    return None, ("названа дочерняя приёмка %s, но раздела %s со сценарием в ней нет"
                  % (", ".join(sorted(set(names))), fid))


def main():
    root = _lib.workspace_root()
    docs = _lib.tracked(root, "docs/specs/*-acceptance.md")
    if not docs:
        _lib.void(NAME, "отслеживаемых docs/specs/*-acceptance.md нет — читать нечего")
        return 2

    if markdown_it is None:
        _lib.void(NAME, "разборщика CommonMark нет (`import markdown_it` не удался) — "
                        "структуру приёмок читать нечем; установить `markdown-it-py`")
        return 2

    parsed, rows, other = {}, {}, []
    outside_rows, outside_docs = 0, 0
    hidden_rows, hidden_docs, unclosed = 0, 0, []
    for rel in docs:
        doc = analyse(_lib.read(root, rel))
        parsed[rel] = doc["secs"]
        if doc["hidden"]:
            hidden_rows += doc["hidden"]
            hidden_docs += 1
        unclosed.extend((rel,) + u for u in doc["unclosed"])
        if doc["outside"]:
            outside_rows += doc["outside"]
            outside_docs += 1
        if not doc["rows"]:
            other.append(rel)
            continue
        rows[rel] = doc["rows"]

    # Незакрытая область судится ДО вопроса о предмете: поглотив раздел Scope,
    # она увела бы документ в «объявляют состав иначе» или весь обход — в VOID.
    for rel, ln, kind, swallowed in unclosed:
        _lib.fail(NAME, "%s:%d — незакрытый %s поглощает %d непустых строк до конца "
                        "документа или контейнера: ни читатель, ни проверка их "
                        "структуры не видят"
                  % (rel, ln, kind, swallowed))

    if not rows and not unclosed:
        _lib.void(NAME, "ни одна приёмка не объявляет фичи строками `| F<N> |` в "
                        "разделе `## … Scope …` (строк `| F<N> |` вне раздела Scope: "
                        "%d) — предмета у проверки нет" % outside_rows)
        return 2

    total = sum(len(v) for v in rows.values())
    _lib.census(
        "%s: разбор markdown-it-py %s (CommonMark + таблицы); приёмок осмотрено %d; объявляют состав фичами `| F<N> |` в разделе "
        "Scope — %d, остальные %d объявляют его иначе и в предмет не входят; строк "
        "`| F<N> |` вне раздела Scope (не состав, не судятся) — %d в %d документах; "
        "в блоках кода и HTML-блоках (не таблица, не судятся) — %d в %d документах"
        % (NAME, markdown_it.__version__, len(docs), len(rows), len(other), outside_rows, outside_docs,
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
            if has_scenario(sec):
                ok += 1
                continue
            child, why = delegation(sec, fid, rel, parsed)
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
