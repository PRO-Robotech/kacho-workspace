#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""no-wait-guard — ОТКАЗ командам ожидания в переднем плане (ws#1004).

Предмет: решение владельца 2026-10-11 «И реши проблему раз и навсегда что таски
уходят в часовые таймауты и ничего не делают а мы ждем». Замер ws#1001: агент сам
поллит свой фон или лог — 181,5 агент-ч; агент сам ждёт CI циклом — 131,2; тяжёлый
прогон в переднем плане и ожидание слота — 116,4. Норма — `CLAUDE.md` «Не жди»;
этот страж — её механизм на PreToolUse Bash (действует и в сабагентах).

ОТКАЗ (класс — пример):
  loop-sleep    — `until …; do sleep …; done`, `while …; do …; sleep N; done` — любой N;
  tail-pid      — `tail --pid …`, `tail -f/-F` без timeout < 600;
  ci-watch      — `gh run watch`, `gh pr checks --watch`;
  watch         — `watch …` (бесконечный повтор);
  long-sleep    — `sleep N`, N ≥ 300 с;
  long-timeout  — `timeout N …`, N ≥ 600 с;
  flock-wait    — `flock -w N` с N ≥ 300 и `flock` без -n/-w (ждёт без предела).
Всё перечисленное — в ПЕРЕДНЕМ плане. Отсоединённое (`… &` без `wait` в той же
строке, `setsid -f`) — законно: шаг возвращает «идёт», исход дочитывает короткий
шаг. `nohup` сам не отсоединяет: без `&` он ждёт в переднем плане. Флаг
run_in_background отсоединением не считается: живой фон держит агента workflow
так же, как передний план (корень класса 1, ws#1001).

РАЗРЕШЕНО: `sleep` < 300 вне цикла, `timeout` < 600, `flock -n`, `flock -w` < 300,
одно чтение CI (`gh pr checks` без --watch, `gh run view`), `heavy-slot.sh` (без
`--wait` он не ждёт; `--wait` ≤ 300 судит сам слот).

ИСКЛЮЧЕНИЕ — одно: метка `# no-wait-exempt ci-watcher <N>m` в команде, N ≤ 9, и
каждая форма ожидания стоит под `timeout` ≤ N·60 с. Агент другого типа (поле
agent_type входа хука, когда оно есть) меткой не пользуется.

Судит РАЗОБРАННУЮ строку: она режется на простые команды по операторам вне
кавычек, собирается в списки, конвейеры, группы и циклы (while/until/for/if/{ }/( )),
тела `bash -c`, `$(…)` и heredoc, поданного оболочке, разбираются тем же разбором.
Слова, присваивания и обёртки снимаются функциями heavy-guard (`words`, `unwrap`
логикой ниже) — второго лексера кавычек здесь нет.

Исходы: 0 без вывода — пропуск; 2 и текст в stderr — отказ; 0 и additionalContext
«СЛОМАН» — страж не смог судить (громко, но не запирая: страж, отказывающий всему,
остановил бы каждую полосу).

ГРАНИЦА (не ловится, известно): цикл `for` со sleep (ограничен перечнем — не
опрос без конца); ожидание внутри скрипта или рецепта make (страж судит строку, а
не текст файла); `wait <pid>` над чужим процессом; инструмент Monitor (его предмет —
ожидание по замыслу харнесса; матчер этого стража — Bash).
"""

import json
import os
import re
import shlex
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "heavy-guard"))
import guard as hg  # noqa: E402 — общий лексер слов с heavy-guard

SLEEP_MAX = 300      # с: sleep от этого — ожидание
TIMEOUT_MAX = 600    # с: timeout от этого — ожидание
FLOCK_MAX = 300      # с: flock -w от этого — ожидание
EXEMPT_MAX_MIN = 9   # мин: потолок метки ci-watcher
EXEMPT = re.compile(r"#\s*no-wait-exempt\s+([A-Za-z0-9_-]+)\s+(\d+)m\b")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
OPENERS = {"while", "until", "for", "if", "{", "case", "select"}
CLOSERS = {"done": ("while", "until", "for", "select"), "fi": ("if",), "}": ("{",), "esac": ("case",)}
TRANSPARENT = {"do", "then", "else", "elif", "!", "in"}

CLASS_TEXT = {
    "loop-sleep": "цикл until/while со sleep — опрос в переднем плане",
    "tail-pid": "tail --pid / tail -f — ожидание чужого процесса или лога",
    "ci-watch": "ожидание CI (gh run watch / gh pr checks --watch)",
    "watch": "watch — бесконечный повтор в переднем плане",
    "long-sleep": "sleep ≥ %d с" % SLEEP_MAX,
    "long-timeout": "timeout ≥ %d с без отсоединения" % TIMEOUT_MAX,
    "flock-wait": "flock ждёт замка ≥ %d с или без предела" % FLOCK_MAX,
}


def duration(s):
    """Секунды из записи sleep/timeout (`90`, `1.5m`, `2h`, `infinity`) либо None."""
    if s == "infinity":
        return float("inf")
    m = re.match(r"^(\d+(?:\.\d+)?)([smhd]?)$", s or "")
    if not m:
        return None
    return float(m.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]


# ── лексер: простые команды и операторы ─────────────────────────────────────
def tokens(text):
    """[(вид, значение)]: ('cmd', текст простой команды), ('op', оператор),
    ('kw', ключевое слово в позиции команды), ('subst', текст $(…)/`…`)."""
    out, cur, i, n, quote = [], [], 0, len(text), None

    def flush():
        seg = "".join(cur).strip()
        cur.clear()
        if not seg:
            return
        # ключевые слова в позиции команды — отдельными лексемами
        while True:
            m = re.match(r"^(\S+)(\s+|$)", seg)
            if not m or m.group(1) not in OPENERS | set(CLOSERS) | TRANSPARENT:
                break
            out.append(("kw", m.group(1)))
            seg = seg[m.end():].strip()
            if not seg:
                return
        out.append(("cmd", seg))

    while i < n:
        c = text[i]
        if quote == "'":
            cur.append(c)
            quote = None if c == "'" else quote
            i += 1
            continue
        if c == "\\" and i + 1 < n:
            cur.append(text[i:i + 2])
            i += 2
            continue
        if c == "$" and text[i + 1:i + 2] == "(" and text[i + 2:i + 3] != "(":
            depth, j = 1, i + 2
            while j < n and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            out.append(("subst", text[i + 2:j - 1]))
            cur.append("__SUBST__")
            i = j
            continue
        if c == "`":
            j = text.find("`", i + 1)
            j = n if j < 0 else j
            out.append(("subst", text[i + 1:j]))
            cur.append("__SUBST__")
            i = j + 1
            continue
        if quote == '"':
            cur.append(c)
            quote = None if c == '"' else quote
            i += 1
            continue
        if c in "'\"":
            quote = c
            cur.append(c)
            i += 1
            continue
        if c == "#" and (not cur or cur[-1] in " \t\n"):
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "&" and (text[i - 1:i] in ("<", ">") or text[i + 1:i + 2] == ">"):
            cur.append(c)
            i += 1
            continue
        if c in "<>" and text[i + 1:i + 2] == "(":  # <(…) >(…) — подстановка процесса
            depth, j = 1, i + 2
            while j < n and depth:
                depth += {"(": 1, ")": -1}.get(text[j], 0)
                j += 1
            out.append(("subst", text[i + 2:j - 1]))
            cur.append("__SUBST__")
            i = j
            continue
        two = text[i:i + 2]
        if two in ("&&", "||", ";;"):
            flush()
            out.append(("op", two))
            i += 2
            continue
        if c in ";&|\n()":
            flush()
            out.append(("op", c))
            i += 1
            continue
        cur.append(c)
        i += 1
    flush()
    return out


# ── разбор: дерево узлов ────────────────────────────────────────────────────
class Node:
    def __init__(self, kind, text=None, kids=None, loop=None):
        self.kind = kind          # simple | group
        self.text = text
        self.kids = kids or []
        self.loop = loop          # while/until/for — для группы-цикла
        self.bg = False
        self.substs = []


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def skip_redirs(self):
        """`done > журнал`, `) 2>&1` — хвост перенаправлений группы, не команда."""
        k, v = self.peek()
        if k != "cmd":
            return
        ws, j = v.split(), 0
        while j < len(ws):
            if hg.REDIR_OP.match(ws[j]):
                j += 2
            elif hg.REDIR_WORD.match(ws[j]):
                j += 1
            else:
                return
        self.i += 1

    def parse_list(self, stop):
        items = []
        while self.i < len(self.t):
            k, v = self.peek()
            if (k == "kw" and v in stop) or (k == "op" and v in stop):
                break
            if k == "op" and v in (";", "\n", ";;"):
                self.i += 1
                continue
            node = self.parse_andor(stop)
            if node is None:
                self.i += 1  # непонятная лексема — пропуск, а не зацикливание
                continue
            k, v = self.peek()
            if k == "op" and v == "&":
                node.bg = True
                self.i += 1
            items.append(node)
        return items

    def parse_andor(self, stop):
        kids = []
        while True:
            node = self.parse_command(stop)
            if node is None:
                break
            kids.append(node)
            k, v = self.peek()
            if k == "op" and v in ("&&", "||", "|"):
                self.i += 1
                continue
            break
        if not kids:
            return None
        return kids[0] if len(kids) == 1 else Node("group", kids=kids)

    def parse_command(self, stop):
        k, v = self.peek()
        substs = []
        while k == "subst":
            substs.append(v)
            self.i += 1
            k, v = self.peek()
        if k == "cmd":
            self.i += 1
            node = Node("simple", text=v)
            node.substs = substs
            # подстановки после текста команды (лексер кладёт их до неё)
            while self.peek()[0] == "subst":
                node.substs.append(self.peek()[1])
                self.i += 1
            return node
        if k == "op" and v == "(":
            self.i += 1
            kids = self.parse_list({")"})
            if self.peek() == ("op", ")"):
                self.i += 1
                self.skip_redirs()
            node = Node("group", kids=kids)
            node.substs = substs
            return node
        if k == "kw" and v in OPENERS:
            self.i += 1
            closer = {"while": "done", "until": "done", "for": "done", "select": "done",
                      "if": "fi", "{": "}", "case": "esac"}[v]
            if v == "case":  # образцы `x)` — не группы: тело — плоско до esac
                kids = []
                while self.i < len(self.t) and self.peek() != ("kw", "esac"):
                    kk, vv = self.peek()
                    if kk == "cmd":
                        kids.append(Node("simple", text=vv))
                    elif kk == "subst":
                        n = Node("simple", text=":")
                        n.substs = [vv]
                        kids.append(n)
                    self.i += 1
            else:
                kids = self.parse_list({closer})
            if self.peek() == ("kw", closer):
                self.i += 1
                self.skip_redirs()
            node = Node("group", kids=kids, loop=v if v in ("while", "until", "for", "select") else None)
            node.substs = substs
            return node
        if k == "kw" and v in TRANSPARENT:
            self.i += 1
            return self.parse_command(stop)
        if substs:
            node = Node("simple", text=":")
            node.substs = substs
            return node
        return None


# ── суждение ────────────────────────────────────────────────────────────────
class Finding:
    def __init__(self, cls, text, bound):
        self.cls = cls
        self.text = text
        self.bound = bound    # timeout над формой, с; None — без предела


def head(argv):
    """Снимает присваивания и обёртки: (argv команды, timeout над ней, отсоединена)."""
    tmo, detached, i = None, False, 0
    while i < len(argv):
        w = argv[i]
        base = os.path.basename(w)
        if hg.ASSIGN.match(w):
            i += 1
            continue
        if base in ("nohup", "nice", "ionice", "stdbuf", "time", "command", "exec", "builtin", "chrt", "taskset"):
            i += 1
            while i < len(argv) and argv[i].startswith("-"):
                i += 2 if argv[i] in ("-n", "-c", "-p", "-o", "-e", "-i") else 1
            if base in ("chrt", "taskset") and i < len(argv):
                i += 1
            continue
        if base == "setsid":
            i += 1
            while i < len(argv) and argv[i].startswith("-"):
                if argv[i] in ("-f", "--fork"):
                    detached = True
                i += 1
            continue
        if base == "env":
            i += 1
            while i < len(argv) and (argv[i].startswith("-") or hg.ASSIGN.match(argv[i])):
                i += 2 if argv[i] in ("-u", "--unset", "-C", "--chdir") else 1
            continue
        if base == "timeout":
            i += 1
            while i < len(argv) and argv[i].startswith("-"):
                i += 2 if argv[i] in ("-k", "--kill-after", "-s", "--signal") else 1
            d = duration(argv[i]) if i < len(argv) else None
            if d is not None:
                tmo = d if tmo is None else min(tmo, d)
            if d is not None and d >= TIMEOUT_MAX:
                return ["timeout", argv[i]] + argv[i + 1:], tmo, detached
            i += 1
            continue
        break
    return argv[i:], tmo, detached


class Judge:
    def __init__(self):
        self.found = []

    def add(self, cls, text, bound):
        self.found.append(Finding(cls, text, bound))

    def text(self, text, ctx):
        """ctx: dict(bg, loop, tmo) — унаследованное от охватывающего узла."""
        body, bodies = hg.strip_heredocs(text)
        toks = tokens(body)
        nodes = Parser(toks).parse_list(set())
        # `wait` в той же оболочке снимает отсоединение `&`: шаг ждёт фона сам
        waits = any(self.has_wait(n) for n in nodes)
        for n in nodes:
            self.node(n, ctx, waits)
        for line, hbody in bodies:  # heredoc, поданный оболочке, — команды
            ws = hg.words(line)
            argv, _, _ = head(ws)
            if argv and os.path.basename(argv[0]) in SHELLS:
                self.text(hbody, ctx)

    def has_wait(self, n):
        if n.kind == "simple":
            ws = hg.words(n.text)
            return bool(ws) and ws[0] == "wait"
        return any(self.has_wait(k) for k in n.kids)

    def node(self, n, ctx, waits):
        bg = ctx["bg"] or (n.bg and not waits)
        for s in n.substs:  # подстановку оболочка ждёт до команды
            self.text(s, dict(ctx, bg=ctx["bg"]))
        if n.kind == "group":
            c = dict(ctx, bg=bg, loop=ctx["loop"] or (n.loop in ("while", "until")))
            for k in n.kids:
                self.node(k, c, waits)
            return
        self.simple(n.text, dict(ctx, bg=bg))

    def simple(self, seg, ctx):
        argv, tmo, det = head(hg.words(seg))
        if not argv:
            return
        bg = ctx["bg"] or det
        bound = ctx["tmo"] if tmo is None else (tmo if ctx["tmo"] is None else min(tmo, ctx["tmo"]))
        base = os.path.basename(argv[0])
        args = argv[1:]
        shown = seg.strip()
        if base == "timeout" and len(argv) >= 2:  # head вернул timeout ≥ 600
            if not bg:
                self.add("long-timeout", shown, None)
            sub, _, sdet = head(argv[2:])
            if sub:
                self.simple(" ".join(shlex.quote(w) for w in argv[2:]), dict(ctx, bg=bg or sdet, tmo=None))
            return
        if base == "sleep":
            d = sum((duration(a) or 0) for a in args) if args else 0
            if ctx["loop"] and not bg:
                self.add("loop-sleep", shown, bound)
            elif d >= SLEEP_MAX and not bg:
                self.add("long-sleep", shown, bound)
            return
        if base == "tail" and not bg:
            pid = any(a == "--pid" or a.startswith("--pid=") for a in args)
            follow = any(a in ("-f", "-F", "--follow", "--retry") or a.startswith("--follow=")
                         or (re.match(r"^-[A-Za-z]*[fF][A-Za-z]*$", a) is not None) for a in args)
            if pid or (follow and (bound is None or bound >= TIMEOUT_MAX)):
                self.add("tail-pid", shown, bound)
            return
        if base == "watch" and not bg:
            self.add("watch", shown, bound)
            return
        if base == "gh" and not bg:
            sub = [a for a in args if not a.startswith("-")]
            if sub[:2] == ["run", "watch"] or (sub[:2] == ["pr", "checks"] and "--watch" in args):
                self.add("ci-watch", shown, bound)
            return
        if base == "flock" and not bg:
            w, nb, k = None, False, 0
            while k < len(args) and args[k].startswith("-"):
                a = args[k]
                if a in ("-n", "--nb", "--nonblock") or re.match(r"^-[a-z]*n[a-z]*$", a):
                    nb = True
                if a in ("-w", "--wait", "--timeout"):
                    w = duration(args[k + 1]) if k + 1 < len(args) else None
                    k += 2
                    continue
                if a.startswith(("--wait=", "--timeout=")):
                    w = duration(a.split("=", 1)[1])
                elif re.match(r"^-w\d", a):
                    w = duration(a[2:])
                k += 1
            if not nb and (w is None or w >= FLOCK_MAX):
                self.add("flock-wait", shown, bound)
            rest = args[k + 1:]  # после файла замка — команда или -c строка
            if rest[:1] in (["-c"], ["--command"]) and len(rest) > 1:
                self.text(rest[1], dict(ctx, bg=bg, tmo=bound))
            elif rest:
                self.simple(" ".join(shlex.quote(x) for x in rest), dict(ctx, bg=bg, tmo=bound))
            return
        if base in SHELLS:
            cmd, script, _, _ = hg.shell_args(args)
            if cmd is not None:
                self.text(cmd, dict(ctx, bg=bg, tmo=bound))
            return
        if base in ("xargs", "parallel"):
            return


def exemption(raw, agent_type):
    """(минуты, ошибка): метка ci-watcher либо None."""
    m = EXEMPT.search(raw)
    if not m:
        return None, None
    who, mins = m.group(1), int(m.group(2))
    if who != "ci-watcher":
        return None, "метка исключения «%s» — исключение есть только у ci-watcher" % who
    if agent_type and agent_type != "ci-watcher":
        return None, "метку ci-watcher несёт вызов агента «%s» — исключение только у ci-watcher" % agent_type
    if mins > EXEMPT_MAX_MIN or mins < 1:
        return None, "метка ci-watcher на %d мин — предел %d мин" % (mins, EXEMPT_MAX_MIN)
    return mins, None


def judge(cmd, agent_type=None):
    """(находки, ошибка метки). Пустые находки — пропуск."""
    j = Judge()
    j.text(cmd, {"bg": False, "loop": False, "tmo": None})
    if not j.found:
        return [], None
    mins, err = exemption(cmd, agent_type)
    if mins is not None:
        limit = mins * 60
        left = [f for f in j.found if f.bound is None or f.bound > limit]
        if left:
            err = "метка ci-watcher %d мин: форма ожидания без timeout ≤ %d с — %s" % (
                mins, limit, left[0].text[:120])
        return left, err
    return j.found, err


def deny(found, err, ws):
    f = found[0] if found else None
    lines = ["NO-WAIT-GUARD: отказ — команда ожидания в переднем плане."]
    if f:
        lines.append("  форма: %s — %s" % (CLASS_TEXT[f.cls], hg.clip(f.text, 200)))
    if err:
        lines.append("  метка: %s" % err)
    lines += [
        "Правило «Не жди» (CLAUDE.md, владелец 2026-10-11: «таски уходят в часовые таймауты и",
        "ничего не делают а мы ждем»): ни один вызов не держит ожидание дольше 10 минут.",
        "Правильная форма:",
        "  setsid nohup <команда> > <журнал> 2>&1 & echo $! > <pid-файл>",
        "  верни «идёт: pid, журнал, ожидаемое окончание»; исход дочитает отдельный короткий",
        "  шаг (`kill -0 $(cat <pid-файл>)`, `tail -n 50 <журнал>`) — без цикла и без sleep.",
        "  · CI — одно чтение (`gh pr checks` без --watch); повтор делает шаблон волны или диспетчер;",
        "  · слот тяжёлого — %s/scripts/heavy-slot.sh <класс> -- …: занят — код 74 сразу," % ws,
        "    ожидание только явным --wait N ≤ 300;",
        "  · разрешено: sleep < %d вне цикла, timeout < %d, flock -n / -w < %d." % (SLEEP_MAX, TIMEOUT_MAX, FLOCK_MAX),
        "Исключение — только ci-watcher: метка `# no-wait-exempt ci-watcher <N>m`, N ≤ %d, форма" % EXEMPT_MAX_MIN,
        "под timeout ≤ N·60 с. Флаг run_in_background отсоединением не считается.",
    ]
    if len(found) > 1:
        lines.append("  ещё форм в строке: %d" % (len(found) - 1))
    sys.stderr.write("\n".join(lines) + "\n")
    sys.exit(2)


def broken(why):
    msg = ("NO-WAIT-GUARD СЛОМАН: %s. Команды ожидания этим вызовом НЕ проверялись — это не "
           "«чисто»; правило «Не жди» (CLAUDE.md) действует: долгое — отсоединённо с журналом "
           "и pid-файлом, исход — коротким шагом; починка — tooling-maintainer." % why)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}, ensure_ascii=False))
    sys.exit(0)


def main():
    if sys.argv[1:2] == ["--judge"] and len(sys.argv) >= 3:
        # --judge <команда> [agent_type] — класс находки строкой для проб
        found, err = judge(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
        print(",".join(f.cls for f in found) or ("label" if err else "-"))
        return
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError) as exc:
        broken("вход хука не разобран как JSON (%s)" % exc)
    if data.get("tool_name") not in (None, "Bash"):
        return
    cmd = (data.get("tool_input") or {}).get("command")
    if not isinstance(cmd, str):
        broken("у вызова Bash нет tool_input.command")
    ws = os.environ.get("CLAUDE_PROJECT_DIR") or os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
    found, err = judge(cmd, data.get("agent_type"))
    if found or err:
        deny(found, err, ws)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — страж обязан сказать о своей поломке
        broken("%s: %s" % (type(exc).__name__, exc))
