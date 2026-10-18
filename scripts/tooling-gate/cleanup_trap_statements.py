#!/usr/bin/env python3
"""Перепись ловушек на выход для check-26 (ws#1189, ws#1193): БЕЛЫЙ СПИСОК.

Предмет — каждая ловушка, срабатывающая на выходе из оболочки: `trap` в позиции
команды (начало строки, после `;`, `&&`, `||`, `|`, `(`, `{`, `then`, `do`, `else`),
вне комментария, heredoc и строкового литерала; сигнал `EXIT` или `0` в любом
регистре, после `--`, среди нескольких сигналов. Действие — прямо или через
функцию файла, транзитивно — раскрывается в плоский список команд и либо
совпадает с КАНОНИЧЕСКИМ ШАБЛОНОМ уборки

    ПЕР=$?; rm -rf "$V" 2>/dev/null || rm -rf "$V" || echo "…$V…" >&2; exit $ПЕР

(код сохранён до уборки → снятие с повтором → предупреждение с путём → выход
кодом), либо это находка «не в форме»: форма вне шаблона не доказана, и молчать
о ней нельзя. Чёрного списка форм здесь нет.

ГРАНИЦА ПРЕДМЕТА (названа, не умолчана): ловушка внутри подстановки `$( )`,
собранная `eval` либо переданная строкой в `bash -c` не отбирается; действие,
собираемое подстановкой (`$` в нём), — находка «не в форме»; функция вне файла
ловушки не раскрывается и — находка.

Использование: cleanup_trap_statements.py <корень> <каталог-вывода> <файл>…
Вывод: <каталог>/index.tsv — строки
  N<TAB>файл<TAB>строка<TAB>вид<TAB>форма<TAB>позиция<TAB>переменные<TAB>причина
(пустое поле — «-») и <каталог>/N.sh — исполняемый текст: определения
использованных функций и оператор `trap` как написан.
Вид: cleanup (по шаблону) · noncanon (EXIT-ловушка вне шаблона) · unknown (оператор
не разобран) · other (не на выходе, сброс, перечень).
"""
import os
import re
import sys

IDENT = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
RM_VARS = re.compile(r'rm\s+-rf\s+(?:--\s+)?((?:"\$\{?[A-Za-z_][A-Za-z_0-9]*\}?"\s*)+)')
VAR = re.compile(r'"\$\{?([A-Za-z_][A-Za-z_0-9]*)\}?"')
TEMPLATE = re.compile(
    r'(?P<rc>[A-Za-z_][A-Za-z_0-9]*)=\$\?; '
    r'rm -rf "\$(?P<v>[A-Za-z_][A-Za-z_0-9]*)" 2>/dev/null \|\| '
    r'rm -rf "\$(?P=v)" \|\| '
    r'echo "[^"\\]*\$\{?(?P=v)\}?[^"\\]*" >&2; '
    r'exit \$(?:\{(?P=rc)\}|(?P=rc))'
)
TRAP = re.compile(r"(?<![\w./-])trap(?=[ \t\n]|$)")
DEF = re.compile(
    r"(?<![\w-])(?:function[ \t]+(?P<f>[A-Za-z_][A-Za-z_0-9-]*)[ \t]*(?:\([ \t]*\))?"
    r"|(?P<g>[A-Za-z_][A-Za-z_0-9-]*)[ \t]*\([ \t]*\))[ \t\n]*\{"
)
KEYWORDS = {"then", "do", "else", "elif", "if", "while", "until"}


def code_mask(t):
    """True там, где символ — код: не комментарий, не heredoc, не внутри кавычек."""
    n, mask, i, state, pending = len(t), bytearray(len(t)), 0, None, []
    while i < n:
        c = t[i]
        if state == "s":
            if c == "'":
                state = None
            i += 1
        elif state == "d":
            if c == "\\":
                i += 2
                continue
            if c == '"':
                state = None
            i += 1
        else:
            if c == "\n":
                mask[i] = 1
                i += 1
                while pending:
                    delim, strip = pending.pop(0)
                    while i < n:
                        j = t.find("\n", i)
                        j = n if j < 0 else j
                        line = t[i:j]
                        i = min(j + 1, n)
                        if (line.strip() if strip else line) == delim:
                            break
                continue
            if c == "\\":
                mask[i] = 1
                i += 2
                continue
            if c == "#" and (i == 0 or t[i - 1] in " \t\n;&|(){"):
                j = t.find("\n", i)
                i = n if j < 0 else j
                continue
            if c == "'":
                state = "s"
                i += 1
                continue
            if c == '"':
                state = "d"
                i += 1
                continue
            if c == "<" and t.startswith("<<", i) and not t.startswith("<<<", i):
                j, strip = i + 2, False
                if t[j : j + 1] == "-":
                    strip, j = True, j + 1
                while t[j : j + 1] in (" ", "\t"):
                    j += 1
                m = re.match(r"""(["']?)([A-Za-z_][A-Za-z_0-9]*)\1""", t[j:])
                if m and re.search(r"(?m)^%s%s$" % ("[ \t]*" if strip else "", re.escape(m.group(2))), t[j + m.end() :]):
                    pending.append((m.group(2), strip))
                    for k in range(i, j + m.end()):
                        mask[k] = 1
                    i = j + m.end()
                    continue
            mask[i] = 1
            i += 1
    return mask


def command_position(t, p):
    k = p - 1
    while k >= 0 and t[k] in " \t":
        k -= 1
    if k < 0 or t[k] == "\n":
        return not (k > 0 and t[k - 1] == "\\")
    if t[k] in ";&|({!":
        return True
    m = re.search(r"([A-Za-z]+)$", t[: k + 1])
    return bool(m and m.group(1) in KEYWORDS)


def skip_paren(t, i):
    depth = 0
    while i < len(t):
        if t[i] == "(":
            depth += 1
        elif t[i] == ")":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return len(t)


def read_words(t, p):
    """Слова оператора с p до разделителя; слово: значение и признак подстановки."""
    n, i, words, cur, dyn, started = len(t), p, [], [], False, False

    def push():
        nonlocal cur, dyn, started
        if started:
            words.append(("".join(cur), dyn))
        cur, dyn, started = [], False, False

    while i < n:
        c = t[i]
        if c in " \t":
            push()
            i += 1
        elif c == "\\" and i + 1 < n:
            if t[i + 1] == "\n":
                push()
            else:
                cur.append(t[i + 1])
                started = True
            i += 2
        elif c == "'":
            j = t.find("'", i + 1)
            j = n if j < 0 else j
            cur.append(t[i + 1 : j])
            started = True
            i = j + 1
        elif c == '"':
            j, buf = i + 1, []
            while j < n and t[j] != '"':
                if t[j] == "\\" and j + 1 < n and t[j + 1] in '"\\$`\n':
                    if t[j + 1] != "\n":
                        buf.append(t[j + 1])
                    j += 2
                    continue
                if t[j] in "$`":
                    dyn = True
                buf.append(t[j])
                j += 1
            cur.append("".join(buf))
            started = True
            i = j + 1
        elif c == "$":
            dyn = started = True
            cur.append(c)
            if t[i + 1 : i + 2] == "(":
                j = skip_paren(t, i + 1)
                cur.append(t[i + 1 : j])
                i = j
            else:
                i += 1
        elif c == "`":
            dyn = started = True
            j = t.find("`", i + 1)
            j = n if j < 0 else j + 1
            cur.append(t[i:j])
            i = j
        elif c in ";\n&|)":
            break
        elif c == "#" and not started:
            j = t.find("\n", i)
            i = n if j < 0 else j
        else:
            cur.append(c)
            started = True
            i += 1
    push()
    return words, i


def scan_block(t, i):
    """Индекс закрывающей `}` блока, чьё `{` стоит перед i; -1 — не найдена."""
    n, depth, state = len(t), 0, None
    while i < n:
        c = t[i]
        if state == "s":
            if c == "'":
                state = None
        elif state == "d":
            if c == "\\":
                i += 1
            elif c == '"':
                state = None
        elif c == "\\":
            i += 1
        elif c == "'":
            state = "s"
        elif c == '"':
            state = "d"
        elif c == "#" and (t[i - 1] in " \t\n;&|(){"):
            j = t.find("\n", i)
            i = n if j < 0 else j
            continue
        elif c == "$" and t[i + 1 : i + 2] == "{":
            d = 0
            while i < n:
                d += t[i] == "{"
                d -= t[i] == "}"
                i += 1
                if d == 0:
                    break
            continue
        elif c == "{" and t[i - 1] in " \t\n;&|(" and t[i + 1 : i + 2] in (" ", "\t", "\n"):
            depth += 1
        elif c == "}" and t[i - 1] in " \t\n;" and (i + 1 == n or t[i + 1] in " \t\n;)&|"):
            if depth == 0:
                return i
            depth -= 1
        i += 1
    return -1


def definitions(t, mask):
    defs = {}
    for m in DEF.finditer(t):
        name = m.group("f") or m.group("g")
        if not mask[m.start()] or name in defs:
            continue
        end = scan_block(t, m.end())
        if end >= 0:
            defs[name] = (m.start(), end + 1, t[m.end() : end])
    return defs


def split_commands(body):
    out, cur, state, i, n = [], [], None, 0, len(body)
    while i < n:
        c = body[i]
        if state == "s":
            cur.append(c)
            state = None if c == "'" else state
        elif state == "d":
            cur.append(c)
            if c == "\\" and i + 1 < n:
                cur.append(body[i + 1])
                i += 1
            elif c == '"':
                state = None
        elif c == "\\" and i + 1 < n:
            cur.append(c + body[i + 1])
            i += 1
        elif c == "'":
            state = "s"
            cur.append(c)
        elif c == '"':
            state = "d"
            cur.append(c)
        elif c in ";\n":
            out.append("".join(cur))
            cur = []
        else:
            cur.append(c)
        i += 1
    out.append("".join(cur))
    return out


def collapse(s):
    return re.sub(r"\s+", " ", s.replace("\\\n", " ")).strip()


def flatten(body, defs, used, stack=()):
    cmds = []
    for seg in split_commands(body):
        cmd = collapse(seg)
        if not cmd or cmd.startswith("#"):
            continue
        first = cmd.split(" ", 1)[0]
        if first in defs:
            if first in stack or len(stack) > 8:
                cmds.append(cmd)
                continue
            used.append(first)
            cmds.extend(flatten(defs[first][2], defs, used, stack + (first,)))
        else:
            cmds.append(cmd)
    return cmds


def judge(t, p, defs):
    words, end = read_words(t, p)
    base = t[p:end]
    if not words or words[0][0] != "trap":
        return ("unknown", "-", "-", "оператор не начинается с trap", base)
    rest = words[1:]
    if rest and rest[0][0] == "--":
        rest = rest[1:]
    elif rest and rest[0][0].startswith("-") and rest[0][0] != "-":
        return ("other", "-", "-", "перечень ловушек", base)
    if not rest:
        return ("other", "-", "-", "trap без аргументов", base)
    action, adyn = rest[0]
    sigs = rest[1:]
    if action == "-" and not adyn:
        return ("other", "-", "-", "сброс ловушки", base)
    if not sigs:
        return ("unknown", "-", "-", "нет списка сигналов", base)
    if any(d for _, d in sigs):
        return ("unknown", "-", "-", "сигнал собирается подстановкой", base)
    if not any(s.upper() in ("EXIT", "0") for s, _ in sigs):
        return ("other", "-", "-", "ловушка не на выходе", base)
    if action == "" and not adyn:
        return ("other", "-", "-", "пустое действие", base)
    form = "multi" if "\n" in base else "single"
    if adyn:
        return ("noncanon", form, "-", "действие собирается подстановкой ($ в нём): форма не выводится", base)
    used, plain = [], IDENT.fullmatch(action.strip() or "?") is not None
    if plain and action.strip() not in defs:
        return ("noncanon", "func", "-", "функция уборки не найдена в файле: %s" % action.strip(), base)
    cmds = flatten(action, defs, used)
    if used:
        form = "func"
    flat = "; ".join(cmds)
    names = []
    for m in RM_VARS.finditer(flat):
        for v in VAR.findall(m.group(1)):
            if v not in names:
                names.append(v)
    text = ""
    seen = []
    for f in used:
        if f not in seen:
            seen.append(f)
            s, e, _ = defs[f]
            text += t[s:e] + "\n"
    run_text = text + base
    vars_ = ",".join(names) if names else "-"
    if TEMPLATE.fullmatch(flat):
        return ("cleanup", form, vars_, "-", run_text)
    return ("noncanon", form, vars_, "не сводится к шаблону уборки (код сохранён → rm -rf с повтором → предупреждение с путём каталога → exit кода)", run_text)


def main(argv):
    root, out, files = argv[1], argv[2], argv[3:]
    os.makedirs(out, exist_ok=True)
    rows, starts = [], 0
    for f in files:
        with open(os.path.join(root, f), encoding="utf-8", errors="replace") as fh:
            t = fh.read()
        mask = code_mask(t)
        defs = definitions(t, mask)
        for m in TRAP.finditer(t):
            p = m.start()
            if not mask[p] or not command_position(t, p):
                continue
            starts += 1
            kind, form, vars_, reason, run_text = judge(t, p, defs)
            line = t.count("\n", 0, p) + 1
            col0 = p == 0 or t[t.rfind("\n", 0, p) + 1 : p].strip() == ""
            rows.append((f, line, kind, form, "строка" if col0 else "внутри", vars_, reason, run_text))
    with open(os.path.join(out, "index.tsv"), "w", encoding="utf-8") as idx:
        for n, (f, line, kind, form, pos, vars_, reason, run_text) in enumerate(rows, 1):
            with open(os.path.join(out, "%d.sh" % n), "w", encoding="utf-8") as fh:
                fh.write(run_text + "\n")
            idx.write("\t".join([str(n), f, str(line), kind, form, pos, vars_, reason.replace("\t", " ")]) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
