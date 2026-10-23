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
                  любом N, в фоне и под timeout тоже (предел не снимает горящее ядро).
Всё перечисленное — в ПЕРЕДНЕМ плане. Отдельный предмет того же стража (ws#1159):
  pattern-kill  — снятие процессов НЕ по pid: адресаты вычислены сопоставлением (имя,
                  строка запуска, владелец, терминал, файл или порт, «все процессы uid») —
                  `pkill -f x`, `pkill newman`, `killall node`, `killall5`, `skill`, `fuser -k`,
                  `kill -9 -1`, `kill <имя>`, `kill $(pgrep …)`, `pgrep … | xargs kill`,
                  `pgrep … | while read p; do kill $p; done`, `for p in $(pidof …); do kill $p; done`,
                  вход xargs/read/цикла от выборщика (`xargs kill < <(pgrep x)`, `… done < <(pgrep x)`,
                  `xargs kill <<< "$(pgrep x)"`), id-значение от выборщика (`pkill -P $(pgrep x)`);
                  число — по ЗНАЧЕНИЮ (`kill -9 -01` = `-1`, `pkill -P 01` = `-P 1`);
                  отказ — и в фоне, и под timeout, и с меткой ci-watcher: снятие чужого не
                  зависит от того, ждут ли его. Классы строятся от двух ролей (ВЫБОРЩИК, ДОСТАВКА —
                  комментарий у PID_MATCHERS), а не перечнем строк.
  Почему здесь, а не отдельным хуком: разбор строки (bash -c, $(…), heredoc, конвейеры,
  обёртки sudo/env/setsid/timeout) один, второй процесс python на каждый вызов Bash не
  заводится, провязку PreToolUse Bash уже держит tooling-gate check-19.
Отсоединённое (`… &` без `wait` в той же
оболочке, `setsid -f`) — законно: шаг возвращает «идёт», исход дочитывает короткий
шаг. `nohup` сам не отсоединяет: без `&` он ждёт в переднем плане. Флаг
run_in_background отсоединением не считается: живой фон держит агента workflow
так же, как передний план (корень класса 1, ws#1001).

РАЗРЕШЕНО (снятие): `kill <pid>`, `kill -- -<pgid>`, `kill $(cat <pid-файл>)`, `kill %1`, `kill "$pid"`,
`kill -0 …` и `pkill -0 …` (сигнал 0 ничего не шлёт), `pkill -F <pid-файл>`, `pkill -P <pid>` (кроме 1),
`pkill -g <pgid>`, `pkill -s <sid>`, `pgrep`, `pidof`, `ps` без снятия.
РАЗРЕШЕНО: `read` из файла (`read -r l < f`, `while read …; done < f`), `head -c N
/dev/urandom`, `yes | <не read>`; `sleep` < 300 вне цикла, `timeout` < 600, `flock -n`, `flock -w` < 300,
одно чтение CI (`gh pr checks` без --watch, `gh run view`), `heavy-slot.sh` (без
`--wait` он не ждёт; `--wait` ≤ 300 судит сам слот).

ИСКЛЮЧЕНИЕ — одно: метка `# no-wait-exempt ci-watcher <N>m` в команде, N ≤ 9, и
каждая форма ожидания стоит под `timeout` ≤ N·60 с. Агент другого типа (поле
agent_type входа хука, когда оно есть) меткой не пользуется.

Судит РАЗОБРАННУЮ строку: она режется на простые команды по операторам вне
кавычек, собирается в списки, конвейеры, группы и циклы (while/until/for/if/{ }/( )),
тела `bash -c`, `$(…)` и heredoc, поданного оболочке (`bash <<EOF`, `cat <<EOF | bash`),
разбираются тем же разбором; тело иного heredoc — данные. Тело, несущее вложенный
открыватель того же ограничителя, оболочка закрывает его первой строкой — хвост после неё
судится командами, и отказ называет это строками (ws#1279).
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
Снятие — страховка кооперативного агента, не граница безопасности (решение диспетчера,
приёмка ws#1159): не разбираются запуск под другим пользователем и в другом окружении —
`su -c`, `doas`, `runuser`, `nsenter`, `unshare`, `systemd-run`, `script -qc`, `strace`
(не обёртки этого разбора: их команда — слово, а не argv); `find -exec`, `env -S` (команда
собирается из довода); `eval`, переменная-команда (`K=pkill; $K -f x`). Также: адресат,
переданный через переменную из ДРУГОЙ команды (`p=$(pgrep x); kill $p` —
поток значений между командами не прослеживается), через файл (`pgrep x > f; kill $(cat f)`),
`eval`, скрипт и иной интерпретатор (`python3 -c "os.kill(…)"`).
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
EXEMPT_MAX_MIN = 9   # мин: потолок метки ci-watcher
EXEMPT = re.compile(r"#\s*no-wait-exempt\s+([A-Za-z0-9_-]+)\s+(\d+)m\b")
SHELLS = {"bash", "sh", "zsh", "dash", "ksh"}
OPENERS = {"while", "until", "for", "if", "{", "case", "select"}
CLOSERS = {"done": ("while", "until", "for", "select"), "fi": ("if",), "}": ("{",), "esac": ("case",)}
BUSY_DEV = {"/dev/zero", "/dev/urandom", "/dev/random"}  # чтение из них не кончается
TRANSPARENT = {"do", "then", "else", "elif", "!", "in"}
SUDO_ARG = {"-u", "-g", "-p", "-C", "-D", "-r", "-t", "-T", "-U", "-R", "-h"}  # флаги sudo со значением
# флаги обёрток СО значением отдельным словом; прочие флаги — без значения
WRAP_VAL = {"nice": ("-n", "--adjustment"), "ionice": ("-c", "-n", "-p", "-P", "-u", "--class",
            "--classdata", "--pid", "--pgid", "--uid"), "stdbuf": ("-i", "-o", "-e"),
            "time": ("-o", "--output", "-f", "--format"), "exec": ("-a",), "command": (),
            "builtin": (), "nohup": (), "chrt": (), "taskset": ()}
# ── снятие процессов (ws#1159) ──
# КЛАСС: сигнал, чьи адресаты ВЫЧИСЛЕНЫ сопоставлением по машине (имя, строка запуска,
# владелец, терминал, файл или порт, «все процессы uid»), а не названы pid, группой или
# записанным pid-файлом. На общем uid такое сопоставление задевает чужие прогоны и саму
# оболочку агента (строка `bash -c '… pkill -f образец'` совпадает с образцом).
# Формы класса выводятся из двух ролей, а не перечнем строк:
#   ВЫБОРЩИК — команда, печатающая или снимающая множество pid по признаку, отличному
#     от идентичности: pgrep/pkill (вне -P/-g/-s/-F), pidof, killall, killall5, skill, ps
#     без выбора по id, lsof, fuser;
#   ДОСТАВКА — сигнал: сам выборщик-снимающий (pkill, killall, killall5, skill, fuser -k)
#     либо `kill`, чьи адресаты пришли от выборщика — подстановкой `$(…)`, конвейером
#     в xargs или в цикл `while read`, заголовком `for … in $(…)`, — либо названы
#     именем или `-1` («все процессы uid»).
# Сигнал 0 (`kill -0`, `pkill -0`) ничего не доставляет — вне класса.
PID_MATCHERS = {"pkill", "pgrep"}                      # выбор по признаку, если нет id-выбора
KILL_BY_MATCH = {"killall", "killall5", "skill"}       # снимают только сопоставлением
# флаги pgrep/pkill, выбирающие по ИДЕНТИЧНОСТИ (родитель, группа, сеанс, pid-файл)
PG_ID_OPTS = {"-P": "--parent", "-g": "--pgroup", "-s": "--session", "-F": "--pidfile"}
# флаги pgrep/pkill со значением, выбирающие по признаку (владелец, терминал, cgroup, ns)
PG_ATTR_OPTS = {"-u", "--euid", "-U", "--uid", "-G", "--group", "-t", "--terminal",
                "--cgroup", "--ns", "--env"}
PG_VAL_OPTS = {"--signal", "-d", "--delimiter", "--nslist", "-q", "--queue", "-r", "--runstates"}
# ps: выбор по id — не выборщик (`ps -o pgid= -p <pid>` законен)
PS_ID_OPTS = {"-p", "--pid", "-q", "--quick-pid", "--ppid", "--sid", "-s", "-g", "--Group", "--pgid"}
PS_VAL_OPTS = {"-o", "-O", "--format", "-u", "-U", "--user", "-G", "--group", "-t", "--tty",
               "--sort", "-C", "-N", "--cols", "--columns", "--rows", "-w"}
XARGS_VAL = {"-a", "--arg-file", "-d", "--delimiter", "-E", "-e", "-I", "-L", "-l", "-n",
             "--max-args", "-P", "--max-procs", "-s", "--max-chars", "--process-slot-var"}

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
    "pattern-kill": "снятие процессов не по pid: цель выбрана по имени, строке запуска, ресурсу или «все процессы uid»",
}
# Классы снятия по шаблону (ws#1159) — другой предмет, чем ожидание: свой текст отказа,
# метка ci-watcher их не снимает.
KILL_CLASSES = {"pattern-kill"}
CLASS_HINT = {
    "pattern-kill": "снимай по pid — по записанному pid-файлу: `kill $(cat <pid-файл>)` либо "
                    "`pkill -F <pid-файл>`; по pid — `kill <pid>`; группу своего сеанса — "
                    "`kill -TERM -- -<pgid>`; детей своего pid — `pkill -P <pid>`",
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
        self.redir_substs = []    # подстановки в этом хвосте (`done < <(pgrep x)`)
        self.feed = None          # предыдущее звено конвейера `a | b`


class Parser:
    def __init__(self, toks):
        self.t = toks
        self.i = 0

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else (None, None)

    def skip_redirs(self):
        """`done > журнал`, `) 2>&1`, `done < <(…)` — хвост перенаправлений группы, не
        команда: (текст, подстановки хвоста) либо (None, [])."""
        j0, substs = self.i, []
        while self.peek()[0] == "subst":  # лексер кладёт подстановку до текста
            substs.append(self.peek()[1])
            self.i += 1
        k, v = self.peek()
        if k != "cmd":
            self.i = j0
            return None, []
        ws, j = v.split(), 0
        while j < len(ws):
            if hg.REDIR_OP.match(ws[j]):
                j += 2
            elif hg.REDIR_WORD.match(ws[j]):
                j += 1
            else:
                self.i = j0
                return None, []
        self.i += 1
        return v, substs

    def past_substs(self):
        """Лексема после подряд идущих подстановок: `done < <(…)` лексер отдаёт как
        подстановку ДО `done` — она принадлежит хвосту закрывающего слова."""
        j = self.i
        while j < len(self.t) and self.t[j][0] == "subst":
            j += 1
        return self.t[j] if j < len(self.t) else (None, None)

    def parse_list(self, stop):
        items = []
        while self.i < len(self.t):
            k, v = self.past_substs()
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
            redir, rsub = None, []
            if self.peek() == ("op", ")"):
                self.i += 1
                redir, rsub = self.skip_redirs()
            node = Node("group", kids=kids)
            node.substs = substs
            node.redir = redir
            node.redir_substs = rsub
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
            redir, rsub, pre = None, [], []
            while self.peek()[0] == "subst" and self.past_substs() == ("kw", closer):
                pre.append(self.peek()[1])
                self.i += 1
            if self.peek() == ("kw", closer):
                self.i += 1
                redir, rsub = self.skip_redirs()
                rsub = pre + rsub
            elif pre:
                substs = substs + pre
            node = Node("group", kids=kids, loop=v if v in ("while", "until", "for", "select") else None)
            node.substs = substs
            node.redir = redir
            node.redir_substs = rsub
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
            # флаги СО значением — у каждой обёртки свои (ws#1159: `time -p`, `command -p` —
            # флаги без значения; прежний общий перечень съедал следующее слово — команду)
            vals = WRAP_VAL.get(base, ())
            i += 1
            while i < len(argv) and argv[i].startswith("-") and argv[i] != "-":
                if argv[i] == "--":
                    i += 1
                    break
                i += 2 if argv[i] in vals else 1
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


# ── снятие по шаблону (ws#1159): роли ВЫБОРЩИК и ДОСТАВКА ────────────────────
def opt_value(args, k, a, long_names, short_names):
    """(имя, значение, сколько слов съедено) для `--x=v`, `--x v`, `-xv`, `-x v`; None — не флаг со значением."""
    if a.startswith("--"):
        name, eq, val = a.partition("=")
        if name not in long_names:
            return None
        return (name, val, 1) if eq else (name, args[k + 1] if k + 1 < len(args) else "", 2)
    for j in range(1, len(a)):
        f = "-" + a[j]
        if f in short_names:
            rest = a[j + 1:]
            return (f, rest, 1) if rest else (f, args[k + 1] if k + 1 < len(args) else "", 2)
    return None


def num_is(v, n):
    """Слово — целое n по ЗНАЧЕНИЮ (`-01`, `-0001` = -1; `01` = 1), а не по написанию."""
    return re.match(r"^-?\d+$", v or "") is not None and int(v) == n


def stdin_selects(text, substs):
    """Источник входа команды или хвоста группы (`< <(…)`, `<<< "$(…)"`, `<<< $(…)`,
    `0< <(…)`) — подстановка, печатающая pid выборщика. Подстановка берётся ПО МЕСТУ:
    n-е `__SUBST__` текста — n-я подстановка узла."""
    for m in re.finditer(r"(?<![<\w])0?(<<<|<>|<)(?!<)\s*[\"']?([^\s\"']*__SUBST__)", text or ""):
        k = (text or "")[:m.start(2)].count("__SUBST__") + m.group(2).count("__SUBST__") - 1
        if 0 <= k < len(substs) and text_selects(substs[k]):
            return True
    return False


def pg_by_pattern(args, sub_sel=False, var_sel=False):
    """pgrep/pkill: (выбор по признаку, сигнал 0). Законен выбор ТОЛЬКО по идентичности:
    -P/--parent (кроме 1 — это все переподчинённые), -g/--pgroup, -s/--session, -F/--pidfile."""
    longs = set(PG_ID_OPTS.values()) | {o for o in PG_ATTR_OPTS | PG_VAL_OPTS if o.startswith("--")}
    shorts = set(PG_ID_OPTS) | {o for o in PG_ATTR_OPTS | PG_VAL_OPTS if not o.startswith("--")}
    pattern = attr = zero = False
    ids = []
    k, opts = 0, True
    while k < len(args):
        a = args[k]
        if opts and a == "--":
            opts, k = False, k + 1
            continue
        if opts and a.startswith("-") and len(a) > 1:
            # сигнал: -9, -TERM, -SIGUSR1 (два знака и больше заглавными); одна заглавная — флаг (-P, -F, -G, -U)
            got = None if re.match(r"^-(\d+|[A-Z][A-Z0-9+-]+)$", a) else opt_value(args, k, a, longs, shorts)
            if got is None:  # флаг без значения либо сигнал
                zero = zero or a in ("-0", "-SIG0")
                k += 1
                continue
            name, val, eaten = got
            if name in PG_ID_OPTS or name in PG_ID_OPTS.values():
                ids.append((name, val))
                # id-значение от выборщика — `-P $(pgrep x)`, `-g $(pgrep -f x)` (ws#1159)
                if ("__SUBST__" in val and sub_sel) or (("$" in val or hg.SQ in val or hg.DQ in val) and var_sel):
                    attr = True
            elif name in PG_ATTR_OPTS:
                attr = True
            elif name == "--signal":
                zero = zero or val.upper() in ("0", "SIG0")
            k += eaten
            continue
        pattern = True  # позиционное — образец
        k += 1
    parent_all = any(n in ("-P", "--parent") and any(num_is(x, 1) for x in v.split(",")) for n, v in ids)
    return (pattern or attr or parent_all or not ids), zero


def ps_by_pattern(args):
    """ps — выборщик, если не ограничен id: -p/--pid/-q/--ppid/--sid/-s/-g или pid позиционно."""
    longs = {o for o in PS_ID_OPTS | PS_VAL_OPTS if o.startswith("--")}
    shorts = {o for o in PS_ID_OPTS | PS_VAL_OPTS if not o.startswith("--")}
    k = 0
    while k < len(args):
        a = args[k]
        if a.startswith("-") and len(a) > 1:
            got = opt_value(args, k, a, longs, shorts)
            if got is None:
                k += 1
                continue
            if got[0] in PS_ID_OPTS:
                return False
            k += got[2]
            continue
        if re.match(r"^\d+$", a) or "$" in a or hg.SQ in a or hg.DQ in a or "__SUBST__" in a:
            return False  # `ps -o pgid= "$pid"` — pid позиционно
        k += 1             # `ps aux` — BSD-флаги
    return True


def selects_by_pattern(argv, substs=()):
    """argv (после head) — ВЫБОРЩИК: печатает или снимает pid по признаку, а не по id."""
    if not argv:
        return False
    base, args = os.path.basename(argv[0]), argv[1:]
    if base in PID_MATCHERS:
        return pg_by_pattern(args, any(text_selects(x) for x in substs))[0]
    if base in KILL_BY_MATCH or base in ("pidof", "lsof", "fuser"):
        return True
    if base == "ps":
        return ps_by_pattern(args)
    return False


def text_selects(text, depth=0):
    """В тексте (`$(…)`, звено конвейера) есть выборщик — в любой простой команде."""
    if depth > 4:
        return False
    stack = Parser(tokens(text or "")).parse_list(set())
    while stack:
        n = stack.pop()
        stack.extend(n.kids)
        if any(text_selects(x, depth + 1) for x in n.substs):
            return True
        if n.kind == "simple" and selects_by_pattern(head(hg.words(n.text))[0], n.substs):
            return True
    return False


def node_selects(n):
    """Узел конвейера (простой или группа) печатает pid выборщика."""
    stack = [n]
    while stack:
        x = stack.pop()
        if x is None:
            continue
        stack.extend(x.kids)
        if any(text_selects(t) for t in x.substs):
            return True
        if x.kind == "simple" and selects_by_pattern(head(hg.words(x.text))[0], x.substs):
            return True
    return False


def feed_selects(n):
    """Выше по конвейеру (`a | b | <n>`) есть выборщик."""
    f = n.feed if n is not None else None
    while f is not None:
        if node_selects(f):
            return True
        f = f.feed
    return False


def kill_parse(args):
    """kill (встроенный, procps, util-linux): (сигнал 0 либо ничего не шлёт, адресаты)."""
    zero, sig, k, targets = False, False, 0, []
    while k < len(args):
        a = args[k]
        if a == "--":
            targets += args[k + 1:]
            break
        if a in ("-l", "-L", "--list", "--table", "-p", "--pid"):
            return True, []          # список сигналов, печать pid — ничего не шлёт
        if a in ("-s", "-n", "--signal") or a.startswith("--signal="):
            v = a.split("=", 1)[1] if "=" in a else (args[k + 1] if k + 1 < len(args) else "")
            zero, sig = num_is(v, 0) or v.upper() == "SIG0", True
            k += 1 if "=" in a else 2
            continue
        if a in ("-q", "--queue"):
            k += 2
            continue
        if a == "--timeout":
            k += 3
            continue
        if a in ("-a", "--all", "--verbose", "-r", "--require-handler"):
            k += 1
            continue
        if not sig and not targets and re.match(r"^-(\d+|[A-Za-z][A-Za-z0-9+-]*)$", a):
            zero, sig = num_is(a, 0) or a == "-SIG0", True   # первый `-N`/`-NAME` — сигнал
            k += 1
            continue
        targets.append(a)
        k += 1
    return zero, targets


class Judge:
    def __init__(self):
        self.found = []

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
        # адресаты от выборщика (ws#1159): конвейер `pgrep … | xargs kill`,
        # `pgrep … | while read p; do kill $p; done`, `for p in $(pgrep …); do kill $p; done`
        # класс: вход xargs/read/цикла — выборщик, каким бы путём он ни пришёл (конвейер,
        # `< <(…)`, `<<< "$(…)"`), либо заголовок for — его подстановка
        own_in = stdin_selects(n.redir, n.redir_substs) if n.kind == "group" else stdin_selects(n.text, n.substs)
        head_in = n.kind == "group" and n.loop and n.kids and n.kids[0].kind == "simple" \
            and stdin_selects(n.kids[0].text, n.kids[0].substs)
        if feed_selects(n) or own_in or head_in or (n.loop == "for" and any(text_selects(x) for x in n.substs)):
            ctx = dict(ctx, sel=True)
        elif n.feed is not None:
            ctx = dict(ctx, sel=False)
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
            for k in n.kids:
                self.node(k, c)
            return
        self.simple(n.text, dict(ctx, bg=bg), n.substs)

    def kill_form(self, base, args, substs, ctx, shown):
        """Снятие процессов (ws#1159): находка pattern-kill либо ничего. Фон и предел
        времени класса не меняют: снятие чужого происходит и отсоединённым."""
        if base in KILL_BY_MATCH:
            if base == "killall" and any(a in ("-0", "-s0") for a in args):
                return True
            self.add("pattern-kill", shown, None)
            return True
        if base == "pkill":
            pattern, zero = pg_by_pattern(args, any(text_selects(x) for x in substs), ctx.get("sel"))
            if pattern and not zero:
                self.add("pattern-kill", shown, None)
            return True
        if base == "fuser":
            if any(a in ("-k", "--kill") or re.match(r"^-[a-zA-Z]*k[a-zA-Z]*$", a) for a in args):
                self.add("pattern-kill", shown, None)
            return True
        if base == "kill":
            zero, targets = kill_parse(args)
            if zero:
                return True
            from_sel = any(text_selects(x) for x in substs)
            for t in targets:
                bad = (num_is(t, -1)                                     # все процессы uid (-01 = -1)
                       or ("__SUBST__" in t and from_sel)                 # kill $(pgrep …)
                       or (("$" in t or hg.SQ in t or hg.DQ in t) and ctx.get("sel"))
                       or not re.match(r"^(-?\d+|%.*|-?\$.*|-?[\ue000\ue001].*|-?.*__SUBST__.*)$", t))
                if bad:
                    self.add("pattern-kill", shown, None)
                    return True
            if not targets and ctx.get("xargs") and ctx.get("sel"):   # pgrep … | xargs kill
                self.add("pattern-kill", shown, None)
            return True
        return False

    def simple(self, seg, ctx, substs=()):
        argv, tmo, det = head(hg.words(seg))
        if not argv:
            return
        bg = ctx["bg"] or det
        bound = ctx["tmo"] if tmo is None else (tmo if ctx["tmo"] is None else min(tmo, ctx["tmo"]))
        base = os.path.basename(argv[0])
        args = argv[1:]
        shown = seg.strip()
        if self.kill_form(base, args, substs, ctx, shown):
            return
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
                self.simple(" ".join(shlex.quote(w) for w in argv[2:]), dict(ctx, bg=bg or sdet, tmo=None), substs)
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
                self.simple(" ".join(shlex.quote(x) for x in rest), dict(ctx, bg=bg, tmo=bound), substs)
            return
        if base in SHELLS:
            cmd, script, _, _ = hg.shell_args(args)
            if cmd is not None:
                self.text(cmd, dict(ctx, bg=bg, tmo=bound))
            return
        if base in ("xargs", "parallel"):
            # команда после флагов xargs получает адресаты со входа (ws#1159)
            k = 0
            while k < len(args) and args[k].startswith("-"):
                got = opt_value(args, k, args[k], {o for o in XARGS_VAL if o.startswith("--")},
                                {o for o in XARGS_VAL if not o.startswith("--")})
                k += got[2] if got else 1
            if k < len(args):
                self.simple(" ".join(shlex.quote(x) for x in args[k:]), dict(ctx, bg=bg, xargs=True), substs)
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
    # снятие по шаблону метка не снимает: её предмет — ожидание (ws#1159)
    kills = [f for f in j.found if f.cls in KILL_CLASSES]
    waits = [f for f in j.found if f.cls not in KILL_CLASSES]
    if not waits:
        return kills, None
    mins, err = exemption(cmd, agent_type)
    if mins is not None:
        limit = mins * 60
        left = [f for f in waits if f.bound is None or f.bound > limit]
        if left:
            err = "метка ci-watcher %d мин: форма ожидания без timeout ≤ %d с — %s" % (
                mins, limit, left[0].text[:120])
        return kills + left, err
    return kills + waits, err


def deny_kill(f):
    """Текст отказа снятию по шаблону (ws#1159): форма, почему, как снимать по pid."""
    return [
        "NO-WAIT-GUARD: отказ — снятие процессов по шаблону.",
        "  форма: %s — %s" % (CLASS_TEXT[f.cls], hg.clip(f.text, 200)),
        "  подсказка: %s." % CLASS_HINT[f.cls],
        "Машина и uid общие: сопоставление по имени или строке запуска задевает чужие прогоны —",
        "отсоединённые демоны, билеты heavy-slot --enqueue соседних полос — и саму оболочку агента",
        "(строка `bash -c '… pkill -f <образец>'` совпадает с образцом). pid своего прогона —",
        "в pid-файле, который пишет его запуск (`echo $! > <pid-файл>`); проверка жизни — `kill -0`.",
    ]


def heredoc_early_close(text):
    """Тело heredoc несёт вложенный открыватель ТОГО ЖЕ ограничителя (ws#1279): оболочка
    закрывает внешний heredoc первой строкой-ограничителем, и текст после неё — уже команды,
    а не данные. (ограничитель, строка открывателя, строка вложенного, строка закрытия) либо
    None. Разбор тел — тот же, что у hg.strip_heredocs."""
    lines, i = text.split("\n"), 0
    while i < len(lines):
        line = lines[i]
        ends = [m.group(2) for m in hg.HEREDOC.finditer(line) if "<<<" not in line[max(0, m.start() - 1):m.start() + 3]]
        opener, i = i, i + 1
        for word in ends:
            nested = None
            while i < len(lines) and lines[i].strip() != word:
                if nested is None and any(m.group(2) == word for m in hg.HEREDOC.finditer(lines[i])):
                    nested = i
                i += 1
            if nested is not None and i < len(lines) and any(x.strip() for x in lines[i + 1:]):
                return word, opener + 1, nested + 1, i + 1
            i += 1
    return None


def early_close_hint(cmd):
    """Строки отказа о преждевременно закрытом heredoc: без них полоса принимает отказ на
    исполняемом хвосте за суждение о данных (урок 2026-10-19, ws#1279)."""
    e = heredoc_early_close(cmd or "")
    if e is None:
        return []
    return [
        "  heredoc закрыт раньше задуманного: тело «%s» (строка %d) несёт вложенный открыватель того" % (e[0], e[1]),
        "    же ограничителя (строка %d); оболочка закрывает внешний первой строкой «%s» (строка %d)," % (e[2], e[0], e[3]),
        "    и текст после неё ИСПОЛНЯЕТ как команды — отказ судит его, а не данные. Смени ограничитель",
        "    внешнего heredoc (например «%s_OUTER») либо положи текст файлом." % e[0],
    ]


def deny(found, err, ws, cmd=None):
    kill = next((x for x in found if x.cls in KILL_CLASSES), None)
    found = [x for x in found if x.cls not in KILL_CLASSES]
    if kill is not None and not found and not err:
        sys.stderr.write("\n".join(deny_kill(kill) + early_close_hint(cmd)) + "\n")
        sys.exit(2)
    f = found[0] if found else None
    lines = deny_kill(kill) if kill is not None else []
    lines.append("NO-WAIT-GUARD: отказ — команда ожидания в переднем плане.")
    if f:
        lines.append("  форма: %s — %s" % (CLASS_TEXT[f.cls], hg.clip(f.text, 200)))
        if f.cls in CLASS_HINT:
            lines.append("  подсказка: %s" % CLASS_HINT[f.cls])
    if err:
        lines.append("  метка: %s" % err)
    lines += early_close_hint(cmd)
    lines += [
        "Правило «Не жди» (CLAUDE.md, владелец 2026-10-11: «таски уходят в часовые таймауты и",
        "ничего не делают а мы ждем»): ни один вызов не держит ожидание дольше 10 минут.",
        "Правильная форма — %s/scripts/detach.sh start <каталог> -- <команда>: печатает" % ws,
        "  «идёт: pid, журнал, rc, срок»; исход — одним шагом `detach.sh status <.rc>` (0/1/3/2/4/5). Без скрипта:",
        "  setsid env --default-signal=PIPE sh -c '<команда>; echo $? > <журнал>.rc' > <журнал> 2>&1 & echo $! > <pid-файл>",
        "  (имя журнала и .rc — уникальное: $$ либо sha в имени; .rc снять до запуска);",
        "  (без nohup: он глушит SIGHUP детям, пробы сигналов краснеют; код — в .rc, не EXIT setsid);",
        "  верни «идёт: pid, журнал, ожидаемое окончание»; исход дочитает отдельный короткий",
        "  шаг (`kill -0 $(cat <pid-файл>)`, `tail -n 50 <журнал>`) — без цикла и без sleep.",
        "  · CI — одно чтение (`gh pr checks` без --watch); повтор делает шаблон волны или диспетчер;",
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
        deny(found, err, ws, cmd)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — страж обязан сказать о своей поломке
        broken("%s: %s" % (type(exc).__name__, exc))
