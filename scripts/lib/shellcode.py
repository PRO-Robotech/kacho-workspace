"""shellcode — исполняемая часть текста оболочки: код отделён от комментария и строки.

Проверка, которая ищет имя скрипта или форму команды в тексте оболочки, обязана
читать КОД: имя стоит и в объяснении рядом с командой, и предикат по подстроке
зеленел бы на собственном комментарии (а краснел бы на чужом). Здесь снимаются
комментарии — целой строкой и хвостовые, — с учётом кавычек: решётка внутри
литерала комментарием не является.

Кавычки и `\\`-продолжения прослеживаются через строки: многострочный литерал не
рвётся на «код» посередине. Здесь-документы (`<<EOF`) считаются ТЕКСТОМ до
закрывающего слова — то, что в них, исполняет не эта оболочка.

Труба, продолженная на следующую строку (`… |` в конце строки либо `\\`-перенос),
сводится в ОДИН конвейер (`pipelines`): звено на второй строке — звено той же
трубы, и построчный разбор его не видел бы вовсе. Подключение (`.`/`source`)
разбирается до слова-аргумента (`sourced_words`), переменная цикла — до слов
его перечня (`loop_words`): подключаемый файл исполняется в оболочке
подключившего и наследует её режимы.

Разбор приближённый и знает это о себе: полного грамматического разбора оболочки
тут нет. Он не путает комментарий с кодом и не видит труб внутри кавычек — этого
достаточно предикатам, которые на нём стоят (`scripts/suites-gate/check-04-*`,
`check-07-*`), и их инъекции доказывают обе границы.
"""
import re

_HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def code_lines(text, mask_quotes=False):
    """[(номер строки, исполняемая часть строки)] — комментарии сняты, здесь-документы
    выброшены. При `mask_quotes` содержимое кавычек заменено пробелами той же длины
    (координаты целы): так ищут форму КОМАНДЫ — труба внутри литерала трубой не
    является. Без него содержимое кавычек сохранено: так ищут ИМЯ скрипта, которое
    законно стоит в кавычках.

    Подстановка команды ВНУТРИ двойных кавычек (`"$(… | grep -q …)"`) — КОД, а не
    литерал: её содержимое не маскируется, и кавычки внутри неё — свои. Прежде
    разбор считал его текстом строки, и труба в такой подстановке не была видна
    ни одному предикату."""
    out = []
    # Стек контекстов: "'" и '"' — литерал; ("$(", глубина) — код подстановки
    # внутри двойных кавычек. Пустой стек — код верхнего уровня.
    stack = []
    heredoc = None
    for n, raw in enumerate(text.split("\n"), 1):
        if heredoc is not None:
            if raw.strip() == heredoc:
                heredoc = None
            continue
        kept = []
        masked = []
        i = 0
        while i < len(raw):
            ch = raw[i]
            top = stack[-1] if stack else None
            if top == "'":
                kept.append(ch)
                if ch == "'":
                    stack.pop()
                    masked.append(ch)
                else:
                    masked.append(" ")
                i += 1
                continue
            if top == '"':
                if ch == "\\" and i + 1 < len(raw):
                    kept.append(raw[i:i + 2])
                    masked.append("  ")
                    i += 2
                    continue
                if raw.startswith("$(", i):
                    stack.append(["$(", 0])
                    kept.append("$(")
                    masked.append("$(")
                    i += 2
                    continue
                kept.append(ch)
                if ch == '"':
                    stack.pop()
                    masked.append(ch)
                else:
                    masked.append(" ")
                i += 1
                continue
            # Код: верхний уровень либо подстановка внутри двойных кавычек.
            if ch == "\\" and i + 1 < len(raw):
                kept.append(raw[i:i + 2])
                masked.append(raw[i:i + 2])
                i += 2
                continue
            if ch in ("'", '"'):
                stack.append(ch)
                kept.append(ch)
                masked.append(ch)
                i += 1
                continue
            if isinstance(top, list):
                if ch == "(":
                    top[1] += 1
                elif ch == ")":
                    if top[1] == 0:
                        stack.pop()
                    else:
                        top[1] -= 1
            elif ch == "#" and (i == 0 or raw[i - 1] in " \t;|&("):
                break
            kept.append(ch)
            masked.append(ch)
            i += 1
        code = "".join(kept)
        shown = "".join(masked)
        if not stack:
            # Оператор здесь-документа ищется в КОДЕ (вне кавычек), слово-граница —
            # в несмаскированном тексте той же позиции.
            for m in _HEREDOC.finditer(code):
                if shown[m.start():m.start() + 2] == "<<":
                    heredoc = m.group(2)
                    break
        out.append((n, shown if mask_quotes else code))
    return out


def code_text(text, mask_quotes=False):
    """Исполняемая часть целиком, строками."""
    return "\n".join(c for _, c in code_lines(text, mask_quotes))


def pipe_stages(code):
    """Звенья трубы в строке кода: разрез по `|`, но не по `||` и не по `|&`-хвосту."""
    stages = []
    cur = []
    i = 0
    while i < len(code):
        ch = code[i]
        if ch == "|":
            if i + 1 < len(code) and code[i + 1] == "|":
                cur.append("||")
                i += 2
                continue
            stages.append("".join(cur))
            cur = []
            i += 1
            if i < len(code) and code[i] == "&":
                i += 1
            continue
        cur.append(ch)
        i += 1
    stages.append("".join(cur))
    return stages


def _continues(code):
    """Строка кода продолжается на следующей: `\\`-перенос либо труба в конце."""
    s = code.rstrip()
    if s.endswith("\\"):
        return True
    if s.endswith("|&"):
        return True
    return s.endswith("|") and not s.endswith("||")


def pipelines(lines):
    """Логические конвейеры: [[(номер строки начала звена, текст звена)], …].

    `lines` — вывод `code_lines(…, mask_quotes=True)`. Строки, продолженные трубой
    в конце либо переносом, сведены в один конвейер; первое звено — писатель,
    остальные — читатели. Номер у звена — строка, где стоит его первое слово: так
    находку можно назвать координатой читателя, а не началом конвейера."""
    out = []
    buf = []
    for n, code in lines:
        buf.append((n, code))
        if _continues(code):
            continue
        out.append(_split(buf))
        buf = []
    if buf:
        out.append(_split(buf))
    return out


def _split(pieces):
    text = []
    owner = []
    for n, code in pieces:
        s = code.rstrip()
        if s.endswith("\\") and not s.endswith("\\\\"):
            s = s[:-1]
        text.append(s + " ")
        owner.extend([n] * (len(s) + 1))
    joined = "".join(text)
    stages = []
    start = 0
    i = 0
    while i < len(joined):
        ch = joined[i]
        if ch == "|":
            if i + 1 < len(joined) and joined[i + 1] == "|":
                i += 2
                continue
            stages.append((start, joined[start:i]))
            i += 1
            if i < len(joined) and joined[i] == "&":
                i += 1
            start = i
            continue
        i += 1
    stages.append((start, joined[start:]))
    out = []
    for begin, stage in stages:
        lead = len(stage) - len(stage.lstrip())
        at = min(begin + lead, len(owner) - 1) if owner else 0
        out.append((owner[at] if owner else 0, stage))
    return out


def read_word(s, i):
    """Одно слово оболочки с позиции `i`: кавычки и `$( … )` не рвут его на части.
    Возвращает (слово, позиция после него)."""
    while i < len(s) and s[i] in " \t":
        i += 1
    start = i
    quote = None
    depth = 0
    while i < len(s):
        ch = s[i]
        if quote:
            if ch == "\\" and quote == '"':
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
        elif ch == "\\":
            i += 2
            continue
        elif ch == "(" :
            depth += 1
        elif ch == ")":
            if depth == 0:
                break
            depth -= 1
        elif depth == 0 and ch in " \t;&|<>":
            break
        i += 1
    return s[start:i], i


_SOURCE = re.compile(r"(?:^|[;&|({]|\b(?:then|do|else|elif)\b)\s*(?:\.|source)(?=[ \t])")
_FOR = re.compile(r"\bfor\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b")


def sourced_words(code):
    """Слова-аргументы подключений (`. <слово>`, `source <слово>`) в строке кода
    (без маскировки кавычек: путь законно стоит в кавычках)."""
    out = []
    for m in _SOURCE.finditer(code):
        word, _ = read_word(code, m.end())
        # `source = …` — присваивание в чужом языке (здесь-документ, вставка), а не
        # подключение файла по имени «=».
        if word and not word.startswith("="):
            out.append(word)
    return out


def loop_words(lines):
    """{переменная: [слова перечня]} для `for <переменная> in <слова>` файла."""
    loops = {}
    for _, code in lines:
        for m in _FOR.finditer(code):
            i = m.end()
            words = []
            while True:
                word, j = read_word(code, i)
                if not word or word in ("do", ";") or j == i:
                    break
                words.append(word)
                i = j
                while i < len(code) and code[i] in " \t":
                    i += 1
                if i < len(code) and code[i] == ";":
                    break
            loops.setdefault(m.group(1), []).extend(words)
    return loops
