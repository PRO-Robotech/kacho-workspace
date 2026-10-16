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
  for-sleep     — `for …; do …; sleep N; done`, если итераций × sleep ≥ 300 с либо число
                  итераций не вычислимо по тексту (`$(seq N)`, `{1..N}`, `$x`, `*`, `for i;`,
                  `for ((…))`) или sleep не вычислим; `for i in 1 2 3; do …; sleep 5; done` — законно;
  bg-wait       — `wait` / `wait <pid>` в переднем плане той же оболочки, где был фоновый
                  запуск `… &`: это ожидание фона, а не отсоединение;
  tail-pid      — `tail --pid …`, `tail -f/-F` без timeout < 600;
  ci-watch      — `gh run watch`, `gh pr checks --watch`;
  watch         — `watch …` (бесконечный повтор);
  long-sleep    — `sleep N`, N ≥ 300 с;
  long-timeout  — `timeout N …`, N ≥ 600 с;
  flock-wait    — `flock -w N` с N ≥ 300 и `flock` без -n/-w (ждёт без предела);
  busy-read     — `read` из бесконечного источника: `read -t N < /dev/zero` (/dev/urandom,
                  /dev/random; свой `<`, `<>` либо `done < …` охватывающего цикла) и `read`
                  после `yes |` / `cat /dev/zero |`: ожидание, держащее 100 % ядра; отказ — при
                  любом N, в фоне и под timeout тоже (предел не снимает горящее ядро);
  ci-wait       — `ci-wait.sh`: срок ожидания CI за вызов > 540 с либо запуск в цикле
                  (ниже «ОЖИДАНИЕ CI»).
Всё перечисленное — в ПЕРЕДНЕМ плане. Отсоединённое (`… &` без `wait` в той же
оболочке, `setsid -f`) — законно: шаг возвращает «идёт», исход дочитывает короткий
шаг. `nohup` сам не отсоединяет: без `&` он ждёт в переднем плане. Флаг
run_in_background отсоединением не считается: живой фон держит агента workflow
так же, как передний план (корень класса 1, ws#1001).

РАЗРЕШЕНО: `read` из файла (`read -r l < f`, `while read …; done < f`), `head -c N
/dev/urandom`, `yes | <не read>`; `sleep` < 300 вне цикла, `timeout` < 600, `flock -n`, `flock -w` < 300,
одно чтение CI (`gh pr checks` без --watch, `gh run view`), `heavy-slot.sh` (без
`--wait` он не ждёт; `--wait` ≤ 300 судит сам слот).

ОЖИДАНИЕ CI — отдельный разрешённый случай, а не ослабление (ws#1114): одна команда
`scripts/ci-state/ci-wait.sh <репо> <PR> <голова> --max N` — блокирующее чтение FIFO
демона состояния без цикла sleep; срок держат сам скрипт (выше 540 — его отказ кодом 2)
и этот страж. Отказ (класс ci-wait):
  · срок ожидания CI за вызов > 540 с — сумма --max запусков переднего плана (последний
    --max запуска, без --max — 540; не вычислим по тексту — без предела): цепочка `&&`/`;`,
    подстановка; timeout над командой ограничивает срок всего, что она запускает;
  · запуск в ЦИКЛЕ while/until/for/select — при любом сроке, под timeout и меткой: повтор
    ожидания делает шаблон волны, а не агент (код ≠ 3 ci-wait.sh возвращает сразу — цикл
    без паузы опрашивает GitHub подряд).
Судится УЗЕЛ запуска, а не слово: путь командой, оболочка со скриптом (кроме `-n`),
`.`/source, рецепт «ЗАПУСК» (`S=…/ci-wait.sh … bash -c "$R" _ <доводы>`), переменная,
которой путь присвоен в той же строке (`CW=…/ci-wait.sh; bash "$CW" …`). Путь в данных —
довод grep/shellcheck, заголовок for, `bash -n` — не запуск.

ИСКЛЮЧЕНИЕ — одно: метка `# no-wait-exempt ci-watcher <N>m` в команде, N ≤ 9, и
каждая форма ожидания стоит под `timeout` ≤ N·60 с. Агент другого типа (поле
agent_type входа хука, когда оно есть) меткой не пользуется.

Судит РАЗОБРАННУЮ строку: она режется на простые команды по операторам вне
кавычек, собирается в списки, конвейеры, группы и циклы (while/until/for/if/{ }/( )),
тела `bash -c`, `$(…)` и heredoc, поданного оболочке (`bash <<EOF`, `cat <<EOF | bash`),
разбираются тем же разбором.
Слова, присваивания и обёртки (nohup, nice, env, setsid, timeout, sudo и др.) снимаются
функциями heavy-guard (`words`, `unwrap` логикой ниже) — второго лексера кавычек здесь нет.

Исходы: 0 без вывода — пропуск; 2 и текст в stderr — отказ; 0 и additionalContext
«СЛОМАН» — страж не смог судить (громко, но не запирая: страж, отказывающий всему,
остановил бы каждую полосу).

ГРАНИЦА (не ловится, известно): ожидание внутри вызываемого скрипта или рецепта
make (страж судит строку, а не текст файла); `wait <pid>` без фонового запуска в той
же строке (чужой процесс не потомок этой оболочки — `wait` возвращается сразу);
инструмент Monitor (его предмет — ожидание по замыслу харнесса; матчер этого
стража — Bash); команда, собранная во время исполнения, — `eval "sleep 900"`
(строка eval не разбирается), `exec 3< /dev/zero; read -t 9 -u 3` (источник — дескриптор,
открытый другой командой), `read -t 9 -u 3 3< /dev/zero` (свой редирект на дескриптор
не 0: источником судится лишь `<`, `0<`, `<>`), `yes | grep y | read x` (бесконечный поток через фильтр:
судится лишь звено прямо перед `read`), `echo 900 | xargs sleep` (argv собирает xargs из
входа), `python3 -c "import time; time.sleep(900)"` (и любой иной интерпретатор:
страж судит команды оболочки, а не текст программы на другом языке).
Путь ci-wait.sh из переменной цикла for (`for f in …/ci-wait.sh; do bash "$f" …; done`) —
раскрытие при исполнении. Цикл БЕЗ sleep вокруг иного блокирующего чтения или чтения CI
(`while :; do timeout 500 head -n1 fifo; done`, `while :; do gh pr checks 7; done`) —
дыра старше ws#1114 (у циклов судится лишь sleep и ci-wait.sh), своя задача ws#1124.
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
FOR_MAX = 300        # с: итераций × sleep в цикле for от этого — ожидание
CI_WAIT_MAX = 540    # с: предел --max ci-wait.sh (ws#1114); больше — ожидание сверх «Не жди»
EXEMPT_MAX_MIN = 9   # мин: потолок метки ci-watcher
EXEMPT = re.compile(r"#\s*no-wait-exempt\s+([A-Za-z0-9_-]+)\s+(\d+)m\b")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
OPENERS = {"while", "until", "for", "if", "{", "case", "select"}
CLOSERS = {"done": ("while", "until", "for", "select"), "fi": ("if",), "}": ("{",), "esac": ("case",)}
BUSY_DEV = {"/dev/zero", "/dev/urandom", "/dev/random"}  # чтение из них не кончается
TRANSPARENT = {"do", "then", "else", "elif", "!", "in"}
SUDO_ARG = {"-u", "-g", "-p", "-C", "-D", "-r", "-t", "-T", "-U", "-R", "-h"}  # флаги sudo со значением

CLASS_TEXT = {
    "loop-sleep": "цикл until/while со sleep — опрос в переднем плане",
    "for-sleep": "цикл for со sleep: итераций × sleep ≥ %d с или не вычислимо по тексту" % FOR_MAX,
    "bg-wait": "wait после фонового запуска — ожидание фона в переднем плане",
    "tail-pid": "tail --pid / tail -f — ожидание чужого процесса или лога",
    "ci-watch": "ожидание CI (gh run watch / gh pr checks --watch)",
    "watch": "watch — бесконечный повтор в переднем плане",
    "long-sleep": "sleep ≥ %d с" % SLEEP_MAX,
    "long-timeout": "timeout ≥ %d с без отсоединения" % TIMEOUT_MAX,
    "flock-wait": "flock ждёт замка ≥ %d с или без предела" % FLOCK_MAX,
    "busy-read": "read из /dev/zero, /dev/urandom или после yes | — ожидание на 100 % ядра",
    "ci-wait": "ci-wait.sh: срок ожидания CI за вызов больше %d с либо запуск в цикле (ws#1114)" % CI_WAIT_MAX,
}
VAR_REF = re.compile(r"^\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?$")  # слово — одна переменная
CLASS_HINT = {
    "busy-read": "жди через heavy-slot --enqueue или короткий шаг: чтение бесконечного источника "
                 "не ждёт, а жжёт ядро",
}


def stdin_source(text):
    """Цель входного перенаправления (`< f`, `<f`, `0< f`, `<> f`) простой команды
    либо хвоста группы; None — его нет. `<<`/`<<<` — данные строки, не источник."""
    try:
        ws = shlex.split(text or "", posix=True)
    except ValueError:
        ws = (text or "").split()
    src = None
    for k, w in enumerate(ws):
        m = re.match(r"^0?(<>|<)(?!<)(.*)$", w)
        if not m:
            continue
        src = m.group(2) or (ws[k + 1] if k + 1 < len(ws) else None)
    return src


def busy_feed(n):
    """Звено конвейера, бесконечно пишущее в трубу: `yes`, `cat /dev/zero`."""
    if n is None or n.kind != "simple":
        return False
    argv, _, _ = head(hg.words(n.text))
    base = os.path.basename(argv[0]) if argv else ""
    return base == "yes" or (base == "cat" and any(a in BUSY_DEV for a in argv[1:]))


def duration(s):
    """Секунды из записи sleep/timeout (`90`, `1.5m`, `2h`, `infinity`) либо None."""
    if s == "infinity":
        return float("inf")
    m = re.match(r"^(\d+(?:\.\d+)?)([smhd]?)$", s or "")
    if not m:
        return None
    return float(m.group(1)) * {"": 1, "s": 1, "m": 60, "h": 3600, "d": 86400}[m.group(2)]


def plain(w):
    """Слово без разметки `$` лексера heavy-guard (SQ/DQ) — как его увидит оболочка."""
    return w.replace(hg.SQ, "$").replace(hg.DQ, "$")


def names_ci_wait(w, civars):
    """Слово — путь к ci-wait.sh (`…/ci-wait.sh`, `"$WS"/…/ci-wait.sh`) либо ссылка на
    переменную, которой он присвоен в той же строке (`"$CW"`, `${CW}`)."""
    w = plain(w)
    if os.path.basename(w) == "ci-wait.sh":
        return True
    m = VAR_REF.match(w)
    return bool(m and m.group(1) in civars)


def max_of(args):
    """Срок по доводам ci-wait.sh, с: без --max — CI_WAIT_MAX (умолчание скрипта);
    inf — значение не вычислимо по тексту (`--max "$M"`)."""
    vals = []
    for k, w in enumerate(args):
        w = plain(w)
        if w == "--max":
            vals.append(plain(args[k + 1]) if k + 1 < len(args) else "")
        elif w.startswith("--max="):
            vals.append(w.split("=", 1)[1])
    if not vals:
        return float(CI_WAIT_MAX)
    v = vals[-1]  # последний --max — так доводы разбирает ci-wait.sh
    return float(v) if re.match(r"^\d+$", v) else float("inf")


def noexec(args):
    """Оболочка с `-n` (в связке `-xn`) либо `-o noexec` скрипт только разбирает — не запуск."""
    k = 0
    while k < len(args) and args[k] != "--" and len(args[k]) > 1 and args[k][0] in "-+":
        a = args[k]
        if a in ("--rcfile", "--init-file"):
            k += 2
            continue
        vals = [] if a.startswith("--") else args[k + 1:k + 1 + a[1:].count("o") + a[1:].count("O")]
        if a[0] == "-" and not a.startswith("--") and ("n" in a[1:] or "noexec" in vals):
            return True
        k += 1 + len(vals)
    return False


def ci_wait_call(argv, env, civars):
    """Срок запуска ci-wait.sh простой командой, с (max_of), либо None — она его не
    запускает. argv — команда после присваиваний и обёрток (head), env — её присваивания.
    Судится УЗЕЛ, а не слово: путь командой (`…/ci-wait.sh …`, `"$CW" …`); оболочка со
    скриптом (`bash [опции] …/ci-wait.sh …`, кроме `-n`); `. …/ci-wait.sh`, source; рецепт
    «ЗАПУСК» — `S=…/ci-wait.sh … bash -c "$R" _ <доводы>`: строка -c — одна переменная,
    скрипт назван присваиванием этой же команды."""
    if not argv:
        return None
    if names_ci_wait(argv[0], civars):
        return max_of(argv[1:])
    base = os.path.basename(plain(argv[0]))
    if base in (".", "source"):
        return max_of(argv[2:]) if len(argv) > 1 and names_ci_wait(argv[1], civars) else None
    if base not in SHELLS or noexec(argv[1:]):
        return None
    cmd, script, sargs, _ = hg.shell_args(argv[1:])
    if script is not None:
        return max_of(sargs) if names_ci_wait(script, civars) else None
    if cmd is not None and VAR_REF.match(plain(cmd)) and any(
            names_ci_wait(a.split("=", 1)[1], civars) for a in env):
        return max_of(sargs[1:])  # sargs[0] — $0 строки -c
    return None


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
        self.redir = None         # хвост перенаправлений группы (`done < f`)
        self.feed = None          # предыдущее звено конвейера `a | b`


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
            return None
        ws, j = v.split(), 0
        while j < len(ws):
            if hg.REDIR_OP.match(ws[j]):
                j += 2
            elif hg.REDIR_WORD.match(ws[j]):
                j += 1
            else:
                return None
        self.i += 1
        return v

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
        kids, piped = [], False
        while True:
            node = self.parse_command(stop)
            if node is None:
                break
            if piped:
                node.feed = kids[-1]
            kids.append(node)
            k, v = self.peek()
            piped = k == "op" and v == "|"
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
            redir = None
            if self.peek() == ("op", ")"):
                self.i += 1
                redir = self.skip_redirs()
            node = Node("group", kids=kids)
            node.substs = substs
            node.redir = redir
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
            redir = None
            if self.peek() == ("kw", closer):
                self.i += 1
                redir = self.skip_redirs()
            node = Node("group", kids=kids, loop=v if v in ("while", "until", "for", "select") else None)
            node.substs = substs
            node.redir = redir
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


def head(argv, env=None):
    """Снимает присваивания и обёртки: (argv команды, timeout над ней, отсоединена);
    присваивания команды (свои и `env X=…`) — в список env, когда он дан."""
    env = [] if env is None else env
    tmo, detached, i = None, False, 0
    while i < len(argv):
        w = argv[i]
        base = os.path.basename(w)
        if hg.ASSIGN.match(w):
            env.append(w)
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
        if base == "sudo":
            # повышение прав не меняет ожидания: `sudo sleep 900` ждёт так же
            i += 1
            while i < len(argv) and argv[i].startswith("-"):
                if argv[i] == "--":
                    i += 1
                    break
                i += 2 if argv[i] in SUDO_ARG else 1
            continue
        if base == "env":
            i += 1
            while i < len(argv) and (argv[i].startswith("-") or hg.ASSIGN.match(argv[i])):
                if hg.ASSIGN.match(argv[i]):
                    env.append(argv[i])
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
        self.frames = [0.0]   # срок ci-wait.sh, с: вызов и команды под своим timeout
        self.ciw = []         # запуски ci-wait.sh переднего плана, по порядку
        self.civars = set()   # переменные, которым присвоен путь ci-wait.sh

    def add(self, cls, text, bound):
        self.found.append(Finding(cls, text, bound))

    def text(self, text, ctx):
        """ctx: dict(bg, loop, tmo) — унаследованное от охватывающего узла."""
        # тело `bash -c` приходит из hg.words с размеченным `$` (SQ/DQ): для дочерней
        # оболочки это снова `$` — иначе `$(…)` в теле не узнаётся подстановкой
        text = text.replace(hg.SQ, "$").replace(hg.DQ, "$")
        body, bodies = hg.strip_heredocs(text)
        toks = tokens(body)
        nodes = Parser(toks).parse_list(set())
        # фоновый запуск в этой оболочке — `wait` в ней же ждёт его (класс bg-wait):
        # отсоединение `&` при `wait` в той же оболочке снято, отказ называет `wait`
        c = dict(ctx, launched=any(self.has_bg(n) for n in nodes))
        for n in nodes:
            self.node(n, c)
        for line, hbody in bodies:  # heredoc, поданный оболочке, — команды
            # оболочка — сама команда строки (`bash <<EOF`) либо звено конвейера после
            # неё (`cat <<EOF | bash`): тело исполняется так же
            for seg in line.split("|"):
                argv, _, _ = head(hg.words(seg))
                if argv and os.path.basename(argv[0]) in SHELLS:
                    self.text(hbody, ctx)
                    break

    def has_bg(self, n):
        return n.bg or any(self.has_bg(k) for k in n.kids)

    # ── цикл for: итераций × sleep за итерацию ──
    def for_count(self, n):
        """Число итераций по тексту заголовка `for v in w…` либо None (не вычислимо)."""
        if n.substs or not n.kids or n.kids[0].kind != "simple" or n.kids[0].substs:
            return None
        hdr = n.kids[0].text
        if re.search(r"[$`{}*?\[]|__SUBST__", hdr):
            return None
        ws = hdr.split()
        if len(ws) < 2 or ws[1] != "in" or not re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", ws[0]):
            return None  # `for v;` — по "$@"; `for ((…))` — арифметика: не по тексту
        return len(ws) - 2

    def sleep_sum(self, nodes):
        """Секунды sleep переднего плана за один проход узлов либо None (не вычислимо)."""
        total = 0.0
        for k in nodes:
            if k.bg:
                continue
            if k.kind == "group":
                if k.loop == "for":
                    d = self.for_total(k)
                elif k.loop:
                    d = 0.0  # while/until — свой класс loop-sleep
                else:
                    d = self.sleep_sum(k.kids)
            else:
                argv, _, det = head(hg.words(k.text))
                if det or not argv or os.path.basename(argv[0]) != "sleep":
                    continue
                ds = [duration(a) for a in argv[1:]]
                d = None if not ds or None in ds else sum(ds)
            if d is None:
                return None
            total += d
        return total

    def for_total(self, n):
        """Секунды sleep цикла for целиком; 0 — sleep нет; None — не вычислимо."""
        per = self.sleep_sum(n.kids[1:])
        if per == 0:
            return 0.0
        cnt = self.for_count(n)
        return None if per is None or cnt is None else cnt * per

    def node(self, n, ctx):
        bg = ctx["bg"] or n.bg
        # вход узла: своё `< f` группы, иначе труба от `yes |`, иначе унаследованный
        src = stdin_source(n.redir) if n.redir else None
        if src is not None:
            ctx = dict(ctx, busy=src in BUSY_DEV)
        elif busy_feed(n.feed):
            ctx = dict(ctx, busy=True)
        elif n.feed is not None:
            ctx = dict(ctx, busy=False)
        for s in n.substs:  # подстановку оболочка ждёт до команды
            self.text(s, dict(ctx, bg=ctx["bg"]))
        if n.kind == "group":
            # timeout < FOR_MAX над циклом ограничивает его сам — не ожидание
            bounded = ctx["tmo"] is not None and ctx["tmo"] < FOR_MAX
            if n.loop in ("for", "select") and not bg and not ctx["loop"] and not bounded:
                total = self.for_total(n) if n.loop == "for" else None
                if total is None and n.loop == "select":
                    total = None if self.sleep_sum(n.kids[1:]) != 0 else 0.0
                if total is None or total >= FOR_MAX:
                    self.add("for-sleep", " ".join(k.text or "…" for k in n.kids[:3]), ctx["tmo"])
            c = dict(ctx, bg=bg, loop=ctx["loop"] or (n.loop in ("while", "until")))
            mark = len(self.ciw)  # запуски ci-wait.sh в теле группы (ws#1114)
            for k in n.kids:
                self.node(k, c)
            if n.loop and len(self.ciw) > mark:
                self.add("ci-wait", "%s — в цикле %s: повтор ожидания CI делает шаблон волны, а не агент"
                         % (self.ciw[mark], n.loop), None)
            return
        self.simple(n.text, dict(ctx, bg=bg))

    def simple(self, seg, ctx):
        """Суждение простой команды (_simple) и её срок ожидания CI (ws#1114): запуск
        ci-wait.sh ею самой и вложенными телами (`bash -c`, flock, timeout), не дольше её timeout."""
        env = []
        argv, tmo, det = head(hg.words(seg), env)
        decl = argv[1:] if argv and os.path.basename(argv[0]) in hg.DECLARE else []
        for a in env + decl:  # `CW=…/ci-wait.sh`, `export CW=…` — `bash "$CW"` тот же запуск
            if hg.ASSIGN.match(a) and names_ci_wait(a.split("=", 1)[1], ()):
                self.civars.add(a.split("=", 1)[0])
        self.frames.append(0.0)
        self._simple(seg, ctx)
        got = self.frames.pop()
        own = None if ctx["bg"] or det else ci_wait_call(argv, env, self.civars)
        if own is not None:
            self.ciw.append(seg.strip())
            got += own
        if tmo is not None:
            got = min(got, tmo)
        self.frames[-1] += got

    def budget(self):
        """Срок ожидания CI за вызов — сумма запусков ci-wait.sh — выше CI_WAIT_MAX: отказ."""
        total = self.frames[0]
        if total > CI_WAIT_MAX:
            why = "не вычислим по тексту (--max)" if total == float("inf") else "%d с" % total
            self.add("ci-wait", "%s — за вызов %s, запусков %d" % (self.ciw[0], why, len(self.ciw)), None)

    def _simple(self, seg, ctx):
        argv, tmo, det = head(hg.words(seg))
        if not argv:
            return
        bg = ctx["bg"] or det
        bound = ctx["tmo"] if tmo is None else (tmo if ctx["tmo"] is None else min(tmo, ctx["tmo"]))
        base = os.path.basename(argv[0])
        args = argv[1:]
        shown = seg.strip()
        if base == "read":
            own = stdin_source(seg)
            if (own in BUSY_DEV) if own is not None else ctx.get("busy"):
                self.add("busy-read", shown, None)  # предел не снимает горящее ядро
            return
        if base == "wait" and not bg and ctx.get("launched"):
            self.add("bg-wait", shown, None)
            return
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
    j.budget()
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
        if f.cls in CLASS_HINT:
            lines.append("  подсказка: %s" % CLASS_HINT[f.cls])
    if err:
        lines.append("  метка: %s" % err)
    lines += [
        "Правило «Не жди» (CLAUDE.md, владелец 2026-10-11: «таски уходят в часовые таймауты и",
        "ничего не делают а мы ждем»): ни один вызов не держит ожидание дольше 10 минут.",
        "Правильная форма:",
        "  setsid env --default-signal=PIPE sh -c '<команда>; echo $? > <журнал>.rc' > <журнал> 2>&1 & echo $! > <pid-файл>",
        "  (имя журнала и .rc — уникальное: $$ либо sha в имени; .rc снять до запуска);",
        "  (без nohup: он глушит SIGHUP детям, пробы сигналов краснеют; код — в .rc, не EXIT setsid);",
        "  верни «идёт: pid, журнал, ожидаемое окончание»; исход дочитает отдельный короткий",
        "  шаг (`kill -0 $(cat <pid-файл>)`, `tail -n 50 <журнал>`) — без цикла и без sleep.",
        "  · CI — одно чтение (`gh pr checks` без --watch); повтор делает шаблон волны или диспетчер;",
        "    ожидание CI — одна команда `scripts/ci-state/ci-wait.sh <репо> <PR> <голова> --max N`, N ≤ %d, без цикла;" % CI_WAIT_MAX,
        "  · слот тяжёлого — %s/scripts/heavy-slot.sh <класс> -- …: занят — код 74 сразу," % ws,
        "    ожидание только явным --wait N ≤ 300; дольше — ОДИН раз --enqueue <каталог> (билет",
        "    держится до 2 ч; перезапуск на 74/75 ставит в конец очереди — запрещён);",
        "  · разрешено: sleep < %d вне цикла, timeout < %d, flock -n / -w < %d," % (SLEEP_MAX, TIMEOUT_MAX, FLOCK_MAX),
        "    цикл for с перечнем в тексте и итераций × sleep < %d; `&` без wait." % FOR_MAX,
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
