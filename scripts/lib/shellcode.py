"""shellcode — исполняемая часть текста оболочки: код отделён от комментария и строки.

Проверка, которая ищет имя скрипта или форму команды в тексте оболочки, обязана
читать КОД: имя стоит и в объяснении рядом с командой, и предикат по подстроке
зеленел бы на собственном комментарии (а краснел бы на чужом). Здесь снимаются
комментарии — целой строкой и хвостовые, — с учётом кавычек: решётка внутри
литерала комментарием не является.

Кавычки и `\\`-продолжения прослеживаются через строки: многострочный литерал не
рвётся на «код» посередине. Здесь-документы (`<<EOF`) считаются ТЕКСТОМ до
закрывающего слова — то, что в них, исполняет не эта оболочка.

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
    законно стоит в кавычках."""
    out = []
    quote = None
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
            if quote:
                if ch == "\\" and quote == '"' and i + 1 < len(raw):
                    kept.append(raw[i:i + 2])
                    masked.append("  ")
                    i += 2
                    continue
                kept.append(ch)
                if ch == quote:
                    quote = None
                    masked.append(ch)
                else:
                    masked.append(" ")
                i += 1
                continue
            if ch == "\\" and i + 1 < len(raw):
                kept.append(raw[i:i + 2])
                masked.append(raw[i:i + 2])
                i += 2
                continue
            if ch in ("'", '"'):
                quote = ch
                kept.append(ch)
                masked.append(ch)
                i += 1
                continue
            if ch == "#" and (i == 0 or raw[i - 1] in " \t;|&("):
                break
            kept.append(ch)
            masked.append(ch)
            i += 1
        code = "".join(kept)
        m = _HEREDOC.search(code) if quote is None else None
        if m:
            heredoc = m.group(2)
        out.append((n, "".join(masked) if mask_quotes else code))
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
