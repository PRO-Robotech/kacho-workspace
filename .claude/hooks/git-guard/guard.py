#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""git-guard — ОТКАЗ командам git, которые обходят хуки (ws#974).

Предмет. «Хук отправки не обходится никогда: `--no-verify` и `KACHO_SKIP_PREPUSH`
запрещены» (база диспетчера п.6, 2026-10-04; `git-issues.md#gi-no-hook-bypass`)
держалось вниманием, и класс повторился четырежды за 28–29.10: временный коммит с
`--no-verify` (полоса ws#1001), коммит с `-c core.hooksPath=…` (приёмка 273),
опытный коммит с `--no-verify` в отсоединённой копии (ws#1498), `core.hooksPath`
в никуда (check-verifier). heavy-guard судит `--no-verify` лишь как признак
лёгкости `push`, а у `commit` не судит вовсе. Страж стоит на PreToolUse Bash и
Monitor и отказывает (код 2, текст в stderr — его видит тот, кто звал Bash).
Исключений для временных и опытных копий нет: страж не смотрит, ЧЬЯ копия.

Что отказывается:
  · опция обхода хука: `--no-verify` у git commit/push/merge/pull/am/rebase и
    `--no-post-rewrite` у commit (полным именем и однозначным сокращением, см. ниже;
    перечень — HOOK_BYPASS, prove.sh выводит его из `git <sub> -h` по всем
    подкомандам `git --list-cmds=main`) и `-n` у commit и am, в том числе в связке
    коротких флагов (`-anm msg`, `am -3n`): в git 2.53 у обоих `-n` = `--no-verify`.
    У push `-n` — `--dry-run`, у merge, pull, rebase — `--no-stat`: законно, не
    судится. У cherry-pick и revert `--no-verify` нет вовсе (git 2.53 отвергает его
    как unknown option) — формы обхода у них нет, prove.sh проверяет это на git;
  · присваивание `<ИМЯ>_SKIP_PREPUSH` не нулём — класс по имени, а не перечень:
    KACHO_, KANAME_, CORELIB_ (их хуки отправки читают каждое; prove.sh выводит
    имена из хуков деревьев и судит каждое найденное). Перед командой, через
    `env`, `export`/`declare` и отдельным присваиванием;
  · перенаправление хуков: `git -c core.hooksPath[=…]` (ключ без учёта регистра),
    `--config-env[=]core.hooksPath=…`, `GIT_CONFIG_KEY_<n>=core.hooksPath`,
    `GIT_CONFIG_PARAMETERS` с ним, запись `git config [--global|--local|-f …]
    [set|--add|--replace-all] core.hooksPath …` и ЗАРАНЕЕ ЗАПИСАННЫЙ файл
    конфигурации с `core.hooksPath` (сам или через свой include):
    `GIT_CONFIG_GLOBAL=`/`GIT_CONFIG_SYSTEM=<файл>`, `-c include.path=<файл>`,
    `-c includeIf.<усл>.path=<файл>`, `GIT_CONFIG_KEY_<n>=include.path` с
    `GIT_CONFIG_VALUE_<n>=<файл>`, `git config include.path <файл>`. Файл читает
    сам git (`git config --file <файл> --includes --get-all core.hooksPath`);
  · алиас с обходом, заведённый той же строкой: `git -c alias.<имя>=<значение>`,
    `git config alias.<имя> <значение>`, `GIT_CONFIG_KEY_<n>=alias.<имя>` — значение
    судится как команда git (с `!` — как строка оболочки).

СОКРАЩЕНИЕ ОПЦИИ — класс, а не экземпляры. Git (parse-options) принимает любой
ОДНОЗНАЧНЫЙ префикс длинной опции, и однозначность считается по перечню опций
ИМЕННО ЭТОЙ подкоманды: `git am --no-v` — это `--no-verify`, а `git commit --no-v`
git отвергает как ambiguous (`--no-verbose`). Страж берёт перечень у самого git
(`git <sub> --git-completion-helper-all` в каталоге команды) и выводит минимальный
однозначный префикс (`min_prefix_len`). Неоднозначный префикс — пропуск: git его не
исполнит. Перечень не получен — порог три знака (`--n`): лишний отказ дешевле
пропуска.

Что НЕ отказывается (законные близнецы, prove.sh исполняет каждый): `git push -n`
(= `--dry-run`), `git log -n 5`, `git merge|pull|rebase -n`, `git commit -m -n`
(значение сообщения), `-n` после опции со значением в связке (`-mn` — сообщение
«n»), префикс на знак короче минимального, `KACHO_SKIP_PREPUSH=0`, чтение
`git config core.hooksPath` и `--get`, снятие `--unset` (лечение «hooksPath в
никуда», которое ловит hooks-wired.sh), конфиг без `core.hooksPath`, алиас без
обхода, и запрет, упомянутый ТЕКСТОМ: в echo/grep, в сообщении коммита, в
комментарии, в теле heredoc, которое пишется в файл, в аргументе не-git команды.

Разбор строки НЕ ЗАВОДИТСЯ ВТОРОЙ РАЗ: нарезка на простые команды, heredoc,
кавычки, `$(…)`, снятие обёрток (`timeout`, `env`, `sudo`, `xargs`…) и `bash -c`
берутся из heavy-guard/guard.py — у одного разборщика одна правка. Файлы скриптов
страж не читает: судится строка вызова (граница ниже).

Исходы: 0 без вывода — пропуск; 2 и текст — отказ; 0 и additionalContext
«СЛОМАН» — страж не смог судить. Последнее — пропуск, а не отказ, намеренно: страж
срабатывает и внутри сабагентов, и сломанный страж, отказывающий всему, остановил
бы все полосы на любой команде; но молчать о поломке он не вправе.

ГРАНИЦА — ИЗВЕСТНЫЕ классы того, чего страж НЕ ловит: BOUNDARY ниже. Перечень не
исчерпывающий: строку оболочки можно собрать бесконечным числом способов. prove.sh
исполняет каждый пример строкой [BOUND]; пойманный пример — [FAIL]: перечень
устарел. Новый найденный обход — ветвь стража со строкой отказа в prove.sh либо
строка BOUNDARY; третьего нет. Страж — напоминание против случайных форм, а не
барьер против намеренного обхода: предел держат хук отправки на сервере сборки
(CI гонит те же наборы) и защита ствола.
"""

import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PARSER = os.path.join(os.path.dirname(HERE), "heavy-guard", "guard.py")

# подкоманда → её длинные опции обхода хука: перечень ВЫВОДИТСЯ из `git <sub> -h`
# (строка опции, говорящая о hook) — prove.sh сверяет его с git в обе стороны.
# У cherry-pick и revert таких опций нет (git 2.53: `--no-verify` — unknown option).
HOOK_BYPASS = {"commit": ("--no-verify", "--no-post-rewrite"), "push": ("--no-verify",),
               "merge": ("--no-verify",), "pull": ("--no-verify",), "am": ("--no-verify",),
               "rebase": ("--no-verify",)}
# `-n` = `--no-verify` (git 2.53, `git <sub> -h`); у прочих подкоманд `-n` другое
SHORT_NO_VERIFY = {"commit", "am"}
# имя переменной обхода хука отправки — класс: KACHO_, KANAME_, CORELIB_ …
SKIP_ENV = re.compile(r"^[A-Z][A-Z0-9_]*_SKIP_PREPUSH$")
# порог, когда перечень опций подкоманды не получен: любой префикс от `--n`
MIN_PREFIX_FALLBACK = 3
GIT_GLOBAL_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix",
                    "--config-env", "--attr-source", "--exec-path", "--list-cmds"}
# опции подкоманды, берущие значение СЛЕДУЮЩИМ словом: оно — не флаг
SHORT_VALUE = {"commit": "mFcCt", "push": "o", "merge": "mFsX", "pull": "sX", "am": "Cp",
               "rebase": "sXx"}
LONG_VALUE = {
    "commit": {"--message", "--file", "--template", "--reuse-message", "--reedit-message",
               "--author", "--date", "--fixup", "--squash", "--cleanup", "--trailer",
               "--pathspec-from-file"},
    "push": {"--push-option", "--repo", "--receive-pack", "--exec"},
    "merge": {"--message", "--file", "--strategy", "--strategy-option", "--into-name"},
    "pull": {"--strategy", "--strategy-option", "--depth", "--shallow-since",
             "--shallow-exclude", "--deepen", "--upload-pack", "--negotiation-tip"},
    "am": {"--whitespace", "--directory", "--exclude", "--include", "--patch-format",
           "--resolvemsg", "--quoted-cr", "--empty"},
    "rebase": {"--onto", "--strategy", "--strategy-option", "--exec", "--empty"},
}
CONFIG_VALUE = {"-f", "--file", "--blob", "--type", "--default", "--comment", "--value"}
CONFIG_NOT_SET = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--get-color",
                  "--get-colorbool", "-l", "--list", "--unset", "--unset-all", "-e", "--edit",
                  "--remove-section", "--rename-section"}
RULE = ".claude/rules/git-issues.md#gi-no-hook-bypass"

# Граница: (класс формы, пример). prove.sh исполняет каждый пример.
BOUNDARY = (
    ("алиас git, заведённый вне строки", "git ci -m x"),
    ("флаг в переменной, присвоенной вне строки", 'git commit $FLAGS -m x'),
    ("текст, поданный оболочке трубой", "echo 'git commit --no-verify -m x' | bash"),
    ("файл, записанный и запущенный той же строкой",
     "printf 'git commit -n -m x\\n' > c.sh && bash c.sh"),
    ("запуск из другого языка", "python3 -c \"import os; os.system('git commit -n -m x')\""),
    ("вызов внутри скрипта или рецепта make", "bash scripts/some-script.sh"),
    ("конфиг с core.hooksPath, записанный той же строкой",
     "printf '[core]\\n\\thooksPath = /dev/null\\n' > g.cfg && GIT_CONFIG_GLOBAL=g.cfg git commit -m x"),
    ("include.path, взятый из переменной через --config-env",
     "git --config-env=include.path=INC commit -m x"),
)

DENY = {
    "no-verify": (
        "обход хуков git («%s»)",
        "хук коммита и хук отправки не обходятся никогда, в опытных и временных копиях\n"
        "тоже (база диспетчера п.6, 2026-10-04: «--no-verify и KACHO_SKIP_PREPUSH\n"
        "запрещены»). У commit и am `-n` — это `--no-verify`.",
        "убери флаг и повтори. Красный хук — вердикт: находку чини; «не выполнилось»\n"
        "  (код 2, нет инструмента или предмета) верни строкой «блокер» в ВОЗВРАТ, не обходи;\n"
        "  долгий хук — слотом и отсоединённо (heavy-slot.sh ci-local), а не мимо."),
    "skip-prepush": (
        "снятие наборов хука отправки («%s»)",
        "*_SKIP_PREPUSH снимает наборы хука отправки; запрещено (база диспетчера п.6, 2026-10-04).",
        "отправляй без него: scripts/heavy-slot.sh ci-local -- git push origin HEAD:refs/heads/<ветка>."),
    "hookspath": (
        "перенаправление хуков git («%s»)",
        "core.hooksPath отключает ВСЕ хуки клона из .git/hooks — молча (scripts/hooks/install.sh);\n"
        "временный worktree или опытная копия исключением не являются.",
        "хуки провязывает make install-hooks (переходники в .git/hooks), проверка —\n"
        "  make check-hooks; «hooksPath в никуда» лечится git config --unset core.hooksPath."),
}


def load_parser():
    spec = importlib.util.spec_from_file_location("heavy_guard_parser", PARSER)
    if spec is None or spec.loader is None:
        raise ImportError("не загружается %s" % PARSER)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def is_hookspath(key):
    return key.strip().strip("'\"").lower() == "core.hookspath"


def is_include(key):
    """`include.path` и `includeIf.<условие>.path` — подключение файла конфигурации."""
    key = key.strip().strip("'\"").lower()
    return key == "include.path" or (key.startswith("includeif.") and key.endswith(".path"))


def is_alias(key):
    return key.strip().strip("'\"").lower().startswith("alias.")


def file_sets_hookspath(path, cwd):
    """Файл конфигурации, уже лежащий на диске, задаёт `core.hooksPath` сам или через
    свой include. Читает его сам git — разбор формата не заводится второй раз. Файла
    ещё нет (записывается той же строкой) или путь в подстановке — не судится:
    граница стража, строка BOUNDARY."""
    path = path.strip("'\"")
    if not path or "$" in path or "__SUBST__" in path:
        return False
    full = os.path.join(cwd or os.getcwd(), os.path.expanduser(path))
    if not os.path.isfile(full):
        return False
    try:
        out = subprocess.run(["git", "config", "--file", full, "--includes", "--get-all",
                              "core.hookspath"], capture_output=True, text=True, timeout=3,
                             stdin=subprocess.DEVNULL,
                             env={k: v for k, v in os.environ.items() if not k.startswith("GIT_")})
    except (OSError, subprocess.SubprocessError):
        return False
    return out.returncode == 0 and out.stdout.strip() != ""


def long_options(sub, where, gitdir=None):
    """Перечень длинных опций подкоманды у того git, который её исполнит; None — не
    получен. `--git-completion-helper-all` требует репозитория, поэтому зовётся в
    каталоге команды (`-C`, `--git-dir`)."""
    cmd = ["git", "-C", where]
    if gitdir:
        cmd.append("--git-dir=" + os.path.join(where, os.path.expanduser(gitdir)))
    try:
        out = subprocess.run(cmd + [sub, "--git-completion-helper-all"], capture_output=True,
                             text=True, timeout=3, stdin=subprocess.DEVNULL,
                             env={k: v for k, v in os.environ.items() if k != "GIT_DIR"})
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    opts = {w.rstrip("=") for w in out.stdout.split() if w.startswith("--") and len(w) > 2}
    return opts or None


def min_prefix_len(target, options):
    """Длина минимального префикса `target`, который git этой подкоманды однозначно
    разрешает в `target`: полное имя — всегда (точное совпадение бьёт сокращение),
    короче — когда ни одна другая опция перечня с этого префикса не начинается."""
    if options is None:
        return MIN_PREFIX_FALLBACK
    for n in range(MIN_PREFIX_FALLBACK, len(target) + 1):
        p = target[:n]
        if p == target or all(o == target or not o.startswith(p) for o in options):
            return n  # порог: минимальный однозначный префикс
    return len(target)


class Options:
    """Перечень опций подкоманды, запрошенный у git не больше одного раза и только
    когда в команде есть СОКРАЩЕНИЕ запрещённой опции (полное имя судится без него)."""

    def __init__(self, sub, where, gitdir):
        self.sub, self.where, self.gitdir, self.got, self.opts = sub, where, gitdir, False, None

    def names(self, word, target):
        """`word` — запрещённая опция `target` полным именем или её сокращением."""
        head = word.split("=", 1)[0]
        if head == target:
            return True
        if len(head) < MIN_PREFIX_FALLBACK or not target.startswith(head):
            return False
        if not self.got:
            self.opts, self.got = long_options(self.sub, self.where, self.gitdir), True
        return len(head) >= min_prefix_len(target, self.opts)


def split_flags(sub, rest):
    """Флаги подкоманды; значения опций пропущены, `--` кончает опции."""
    flags, k = [], 0
    short_v, long_v = SHORT_VALUE.get(sub, ""), LONG_VALUE.get(sub, set())
    while k < len(rest):
        a = rest[k]
        if a == "--":
            break
        if a.startswith("--"):
            flags.append(a)
            k += 2 if a in long_v else 1
            continue
        if a.startswith("-") and len(a) > 1:
            flags.append(a)
            # связка коротких: значение берёт первая опция-со-значением; если она
            # последняя в связке — значение следующим словом
            for j, ch in enumerate(a[1:], 1):
                if ch in short_v:
                    k += 2 if j == len(a) - 1 else 1
                    break
            else:
                k += 1
            continue
        k += 1
    return flags


def bundle_has(a, ch, short_v):
    """Короткий флаг `ch` в связке `a` — до первой опции со значением."""
    if not a.startswith("-") or a.startswith("--"):
        return False
    for c in a[1:]:
        if c == ch:
            return True
        if c in short_v:
            return False
    return False


def env_gitdir(assignments):
    """Последнее присваивание GIT_DIR с буквальным значением; иначе None."""
    found = None
    for e in assignments:
        name, _, val = e.partition("=")
        if name == "GIT_DIR":
            val = val.strip("'\"")
            found = val if val and "$" not in val and "__SUBST__" not in val else None
    return found


class Judge:
    def __init__(self, hg):
        self.hg = hg

    def text(self, text, cwd, depth=0):
        hg = self.hg
        if depth > 6:
            return
        stripped, bodies = hg.strip_heredocs(text)
        vis, cur = [], cwd
        for seg in hg.split_commands(stripped):
            env, argv = hg.unwrap(hg.expand_words(hg.words(seg), vis))
            yield from self.env(env, cur, depth)
            if not argv:
                vis.extend(env)
                continue
            base = os.path.basename(argv[0])
            if base in ("cd", "pushd") and len(argv) > 1 and "$" not in argv[1] \
                    and "__SUBST__" not in argv[1]:
                cur = os.path.join(cur or os.getcwd(), os.path.expanduser(argv[1]))
                continue
            if base in hg.DECLARE:
                assigns = [a for a in argv[1:] if hg.ASSIGN.match(a)]
                yield from self.env(assigns, cur, depth)
                vis.extend(assigns)
                continue
            yield from self.argv(argv, cur, depth, vis + env)
        for intro, body in bodies:
            # heredoc, поданный оболочке (`bash <<EOF`), — её команды; прочие — данные
            for seg in hg.split_commands(intro):
                _, argv = hg.unwrap(hg.words(seg))
                if argv and os.path.basename(argv[0]) in hg.SHELLS and hg.shell_args(argv[1:])[3]:
                    yield from self.text(body, cur, depth + 1)
                    break

    def env(self, assignments, cwd, depth):
        values = dict(e.partition("=")[::2] for e in assignments)
        for e in assignments:
            name, _, val = e.partition("=")
            bare = val.strip("'\"")
            m = re.match(r"^GIT_CONFIG_KEY_(\d+)$", name)
            cval = values.get("GIT_CONFIG_VALUE_" + m.group(1), "") if m else ""
            if SKIP_ENV.match(name) and bare not in ("", "0"):
                yield "skip-prepush", e
            elif m and is_hookspath(bare):
                yield "hookspath", e
            elif m and is_include(bare) and file_sets_hookspath(cval, cwd):
                yield "hookspath", "%s GIT_CONFIG_VALUE_%s=%s" % (e, m.group(1), cval)
            elif m and is_alias(bare):
                yield from self.alias(cval, e, cwd, depth)
            elif name == "GIT_CONFIG_PARAMETERS" and "core.hookspath" in val.lower():
                yield "hookspath", e
            elif name in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM") and file_sets_hookspath(val, cwd):
                yield "hookspath", e

    def alias(self, value, shown, cwd, depth):
        """Значение алиаса, заведённого этой строкой, — команда git (с `!` — строка
        оболочки): обход внутри него — обход самой строки."""
        value = value.strip()
        if not value:
            return
        if value.startswith("!"):
            inner = self.text(value[1:], cwd, depth + 1)
        else:
            try:
                words = shlex.split(value)
            except ValueError:
                words = value.split()
            inner = self.git(words, cwd, None, depth + 1)
        for kind, _ in inner:
            yield kind, "алиас: " + shown
            return

    def argv(self, argv, cur, depth, env=()):
        hg = self.hg
        base, args = os.path.basename(argv[0]), argv[1:]
        if base == "git":
            yield from self.git(args, cur, env_gitdir(env), depth)
        elif base in hg.SHELLS:
            cmd, _, params, _ = hg.shell_args(args)
            if cmd is not None:
                yield from self.text(hg.positional(cmd, params), cur, depth + 1)
        elif base == "eval":
            yield from self.text(" ".join(args), cur, depth + 1)
        elif base == "find":
            for k, a in enumerate(args):
                if a in ("-exec", "-execdir", "-ok", "-okdir"):
                    sub = []
                    for w in args[k + 1:]:
                        if w in (";", "+"):
                            break
                        sub.append(w)
                    sub_env, sub = hg.unwrap(sub)
                    yield from self.env(sub_env, cur, depth)
                    if sub:
                        yield from self.argv(sub, cur, depth, list(env) + sub_env)

    def git(self, args, cwd, gitdir, depth):
        k, where = 0, cwd
        while k < len(args) and args[k].startswith("-"):
            a = args[k]
            head, eq, val = a.partition("=")
            if a == "-C" and k + 1 < len(args):
                where = os.path.join(where or os.getcwd(), os.path.expanduser(args[k + 1]))
            if a == "-c" and k + 1 < len(args):
                key, _, cval = args[k + 1].partition("=")
                if is_hookspath(key) or (is_include(key) and file_sets_hookspath(cval, where)):
                    yield "hookspath", "git -c " + args[k + 1]
                elif is_alias(key):
                    yield from self.alias(cval, "git -c " + args[k + 1], where, depth)
            if head == "--git-dir":
                gitdir = val if eq else (args[k + 1] if k + 1 < len(args) else gitdir)
            if head == "--config-env":
                spec = val if eq else (args[k + 1] if k + 1 < len(args) else "")
                if is_hookspath(spec.split("=", 1)[0]):
                    yield "hookspath", "git --config-env " + spec
            k += 2 if (a in GIT_GLOBAL_VALUE and not eq) else 1
        if k >= len(args):
            return
        sub, rest = args[k], args[k + 1:]
        if sub in HOOK_BYPASS:
            opts = Options(sub, where or os.getcwd(), gitdir)
            for a in split_flags(sub, rest):
                if (a.startswith("--") and any(opts.names(a, t) for t in HOOK_BYPASS[sub])) \
                        or (sub in SHORT_NO_VERIFY and bundle_has(a, "n", SHORT_VALUE[sub])):
                    yield "no-verify", " ".join(["git", sub] + rest)
                    return
        elif sub == "config":
            yield from self.config(rest, where or os.getcwd(), depth)

    def config(self, rest, where, depth):
        flags, pos, k = [], [], 0
        while k < len(rest):
            a = rest[k]
            if a == "--":
                pos.extend(rest[k + 1:])
                break
            if a.startswith("-"):
                flags.append(a.split("=", 1)[0])
                k += 2 if a in CONFIG_VALUE else 1
                continue
            pos.append(a)
            k += 1
        shown = " ".join(["git", "config"] + rest)
        if pos[:1] == ["set"]:  # форма подкоманд git ≥ 2.46: `git config set <ключ> <значение>`
            pos = pos[1:]
        elif pos[:1] and pos[0] in ("get", "list", "unset", "edit", "rename-section",
                                    "remove-section"):
            return
        elif any(f in CONFIG_NOT_SET for f in flags):
            return
        # запись — ключ И значение позиционными (`--add`/`--replace-all` без значения
        # git отвергает сам, поэтому отдельной ветви по этим флагам нет)
        if len(pos) < 2:
            return
        if is_hookspath(pos[0]) or (is_include(pos[0]) and file_sets_hookspath(pos[1], where)):
            yield "hookspath", shown
        elif is_alias(pos[0]):
            yield from self.alias(pos[1], shown, where, depth)


def deny(kind, shown):
    what, why, instead = DENY[kind]
    shown = shown if len(shown) <= 300 else shown[:297] + "…"
    sys.stderr.write(
        "GIT-GUARD: отказ [%s] — %s.\n%s\nПравило: %s.\nЧто делать вместо: %s\n"
        "Если команда законна и отказ ложный — не обходи его: верни строку «блокер» с этой\n"
        "командой в ВОЗВРАТ; страж правит tooling-maintainer.\n"
        % (kind, what % shown, why, RULE, instead))
    sys.exit(2)


def broken(why):
    msg = ("GIT-GUARD СЛОМАН: %s. Команды git этим вызовом НЕ проверялись — это не «чисто»: "
           "--no-verify (и -n у commit/am), *_SKIP_PREPUSH и core.hooksPath запрещены и без "
           "стража (%s); починка — tooling-maintainer." % (why, RULE))
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}, ensure_ascii=False))
    sys.exit(0)


def relevant(text):
    """Без «git» и «SKIP_PREPUSH» в тексте находки нет ни в одной ветви: всякая
    ветвь судит команду git, переменную GIT_CONFIG_* или переменную обхода."""
    low = text.lower()
    return "git" in low or "skip_prepush" in low


def find(text, cwd, hg=None):
    if not relevant(text):
        return None
    for hit in Judge(hg or load_parser()).text(text, cwd):
        return hit
    return None


def main():
    if sys.argv[1:] == ["--boundary"]:
        sys.stdout.write("".join("%s\0%s\0" % b for b in BOUNDARY))
        return
    if sys.argv[1:] == ["--table"]:  # перечни стража для сверки prove.sh с git
        for sub in sorted(HOOK_BYPASS):
            print("long %s %s" % (sub, " ".join(sorted(HOOK_BYPASS[sub]))))
        print("short-n %s" % " ".join(sorted(SHORT_NO_VERIFY)))
        return
    try:
        data = json.load(sys.stdin)
    except (ValueError, OSError) as exc:
        broken("вход хука не разобран как JSON (%s)" % exc)
    tool = data.get("tool_name")
    if tool not in (None, "Bash", "Monitor"):
        return
    cmd = (data.get("tool_input") or {}).get("command")
    if tool == "Monitor" and cmd is None:
        return
    if not isinstance(cmd, str):
        broken("у вызова %s нет tool_input.command" % (tool or "Bash"))
    if not relevant(cmd):
        return
    try:
        hg = load_parser()
    except Exception as exc:  # noqa: BLE001
        broken("разборщик heavy-guard/guard.py не загрузился (%s: %s)" % (type(exc).__name__, exc))
    hit = find(cmd, data.get("cwd") or os.getcwd(), hg)
    if hit:
        deny(*hit)


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001 — страж обязан сказать о своей поломке
        broken("%s: %s" % (type(exc).__name__, exc))
