#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""git-guard — ОТКАЗ командам git/gh, которые обходят хуки, переписывают
опубликованную историю или обходят защиту ствола.

Предмет (ws#974): запреты «хук отправки не обходится никогда: `--no-verify` и
`KACHO_SKIP_PREPUSH` запрещены» (база диспетчера, 2026-10-04), «прямой push в
`main` отвергается защитой», «без --force/--admin» (решение владельца 2026-10-06)
держались вниманием: ни один хук сессии их не судил. Страж стоит на PreToolUse
Bash и Monitor и отказывает (код 2, текст в stderr — видит тот, кто звал Bash)
такой команде, называя, ЧТО делать вместо.

Что отказывается:
  · `--no-verify` у git commit/push/merge/pull/am/rebase и `-n` в связке коротких
    флагов commit и am (`-anm msg`, `am -n`: в git 2.53 у обоих `-n` = `--no-verify`);
    у merge, rebase, pull, push `-n` — другое (--no-stat, --dry-run), не судится.
    У cherry-pick и revert `--no-verify` нет вовсе (git 2.53, `git <sub> -h`: git
    отвергает его как unknown option) — формы обхода у них нет, и они не судятся;
  · присваивание `KACHO_SKIP_PREPUSH` не нулём — перед командой и `export`;
  · git push с `--force`, `-f` (и в связке), `--force-with-lease[=…]`, refspec с
    `+`, а также `--mirror`/`--all`/`--branches` (переписывают либо шлют ствол);
  · git push, чья цель — `main`/`master` (`origin main`, `HEAD:main`,
    `refs/heads/main`, удаление `:main`), и голый `git push` / `push origin [HEAD]`,
    когда текущая ветка — `main`/`master` (ветка читается `git symbolic-ref` в
    каталоге команды: `cd`, `-C`, `--git-dir` и `GIT_DIR` учтены);
  · `gh pr merge … --admin`, в том числе с `-R`/`--repo <репо>` перед `pr`;
  · перенаправление хуков: `git -c core.hooksPath=…`, `--config-env=core.hooksPath=…`,
    `GIT_CONFIG_KEY_<n>=core.hooksPath`, `GIT_CONFIG_PARAMETERS` с ним, запись
    `git config [set|--add|--replace-all] core.hooksPath …` и ЗАРАНЕЕ ЗАПИСАННЫЙ
    файл конфигурации, задающий `core.hooksPath` (сам или через свой include):
    `GIT_CONFIG_GLOBAL=`/`GIT_CONFIG_SYSTEM=<файл>`, `-c include.path=<файл>`,
    `-c includeIf.<усл>.path=<файл>`, `GIT_CONFIG_KEY_<n>=include.path` с
    `GIT_CONFIG_VALUE_<n>=<файл>`, `git config include.path <файл>`. Файл читает
    сам git (`git config --file <файл> --includes --get-all core.hooksPath`).

СОКРАЩЕНИЕ ОПЦИИ — класс, а не экземпляры. Git (parse-options) принимает любой
ОДНОЗНАЧНЫЙ префикс длинной опции, и однозначность считается по перечню опций
ИМЕННО ЭТОЙ подкоманды: `git am --no-v` — это `--no-verify` (у am нет
`--no-verbose`), а `git commit --no-v` git отвергает как ambiguous. Поэтому порога
«одна длина на всех» нет: страж берёт перечень у самого git, который будет
исполнять команду (`git <sub> --git-completion-helper-all` в каталоге команды), и
выводит для запрещённой опции минимальный однозначный префикс (`min_prefix_len`).
Неоднозначный префикс — пропуск: git его не исполнит. Полное имя отказывается и без
перечня. Перечень не получен (каталог не репозиторий, git не ответил) — порог
опускается до трёх знаков (`--x`): лишний отказ на команде, которую git всё равно
не исполнил бы, дешевле пропуска. У gh (pflag) сокращений нет: `--admi` — unknown
flag, отказывается только `--admin`.

Что НЕ отказывается (законные близнецы, prove.sh исполняет каждый): обычный
`git push -u origin <N>-<суть>`, удаление своей ветки (`push -d`, `:ветка`),
`--no-force-with-lease`, префикс на знак короче минимального (git называет его
ambiguous), `--no-verify` у cherry-pick/revert, чтение `git config core.hooksPath` и
`--get`, его снятие `--unset` (лечение «hooksPath в никуда», которое ловит
hooks-wired.sh), `GIT_CONFIG_GLOBAL=/dev/null` и конфиг без `core.hooksPath`,
`gh pr merge` без `--admin` любым способом (способ вливания судит сервер
настройкой репозитория, а не страж), и запрет, упомянутый ТЕКСТОМ: в echo/grep,
в сообщении коммита, в комментарии, в теле heredoc, которое пишется в файл.

Разбор строки НЕ ЗАВОДИТСЯ ВТОРОЙ РАЗ: нарезка на простые команды, heredoc,
комментарии, кавычки, `$(…)`, снятие обёрток (`timeout`, `env`, `sudo`, `xargs`…)
и `bash -c` берутся из heavy-guard/guard.py — у одного разборщика одна правка.
Исполняемое отличается от текста ровно так, как у heavy-guard.

Исходы: 0 без вывода — пропуск; 2 и текст — отказ; 0 и additionalContext
«СЛОМАН» — страж не смог судить. Последнее — пропуск, а не отказ, намеренно: страж
срабатывает и внутри сабагентов, и сломанный страж, отказывающий всему, остановил
бы все полосы на любой команде; но молчать о поломке он не вправе.

ГРАНИЦА — ИЗВЕСТНЫЕ классы того, чего страж НЕ ловит: BOUNDARY ниже. Перечень
НЕ исчерпывающий: это классы, найденные и проверенные к ревизии стража, а не
доказанное «всё прочее ловится» — строку оболочки можно собрать бесконечным
числом способов. prove.sh исполняет каждый пример строкой [BOUND] («известно, не
ловится»), пойманный пример — [FAIL]: перечень устарел. Найденный новый обход —
либо ветвь стража со строкой отказа в prove.sh, либо строка BOUNDARY; третьего
нет. Предел держит сервер (защита ветки, способ вливания), страж — напоминание
против случайных форм, а не барьер против намеренного обхода.
"""

import importlib.util
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PARSER = os.path.join(os.path.dirname(HERE), "heavy-guard", "guard.py")

PROTECTED = {"main", "master"}
# у cherry-pick и revert `--no-verify` нет (git 2.53: unknown option) — не судятся
NO_VERIFY_SUBS = {"commit", "push", "merge", "pull", "am", "rebase"}
# запрещённые длинные опции push сверх `--no-verify`: вид отказа по полному имени
PUSH_FORBIDDEN = (("--force", "force"), ("--force-with-lease", "force"),
                  ("--mirror", "push-all"), ("--all", "push-all"), ("--branches", "push-all"))
# порог, когда перечень опций подкоманды не получен: любой префикс от `--x`
MIN_PREFIX_FALLBACK = 3
GIT_GLOBAL_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix",
                    "--config-env", "--attr-source"}
# опции подкоманды, берущие значение СЛЕДУЮЩИМ словом: оно — не флаг и не refspec
SHORT_VALUE = {
    "commit": "mFcCt",
    "push": "o",
    "merge": "mFsX",
    "pull": "sX",
    "am": "Cp",
}
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
}
# `-n` = `--no-verify` (git 2.53, `git <sub> -h`); у прочих подкоманд `-n` другое
SHORT_NO_VERIFY = {"commit", "am"}
# опции gh, берущие значение СЛЕДУЮЩИМ словом: оно — не подкоманда и не флаг
GH_VALUE = {"-R", "--repo", "-b", "--body", "-F", "--body-file", "-t", "--subject",
            "--match-head-commit", "-A", "--author-email"}
CONFIG_VALUE = {"-f", "--file", "--blob", "--type", "--default", "--comment", "--value"}
CONFIG_NOT_SET = {"--get", "--get-all", "--get-regexp", "--get-urlmatch", "--get-color",
               "--get-colorbool", "-l", "--list", "--unset", "--unset-all", "-e", "--edit",
               "--remove-section", "--rename-section"}
SKIP_ENV = "KACHO_SKIP_PREPUSH"

# Граница: (класс формы, пример). prove.sh исполняет каждый пример.
BOUNDARY = (
    ("алиас git, заведённый вне строки", "git ci -m x"),
    ("алиас, заведённый той же строкой", "git config alias.pf 'push --force' && git pf origin 974-x"),
    ("ветка-цель в переменной вне строки", 'git push origin "$TARGET"'),
    ("текст, поданный оболочке трубой", "echo 'git push --force' | bash"),
    ("файл, записанный и запущенный той же строкой", "printf 'git push -f\\n' > p.sh && bash p.sh"),
    ("запуск из другого языка", "python3 -c \"import os; os.system('git push --force')\""),
    ("настройка remote.*.push, сохранённая заранее", "git push origin"),
    ("конфиг с core.hooksPath, записанный той же строкой",
     "printf '[core]\\n\\thooksPath = /dev/null\\n' > g.cfg && GIT_CONFIG_GLOBAL=g.cfg git commit -m x"),
    ("include.path, взятый из переменной через --config-env", "git --config-env=include.path=INC commit -m x"),
)

DENY = {
    "no-verify": (
        "обход хуков git («%s»)",
        "хук коммита и хук отправки не обходятся никогда (база диспетчера: «--no-verify и\n"
        "KACHO_SKIP_PREPUSH запрещены», 2026-10-04).",
        "убери флаг и повтори. Красный хук — это вердикт: находку чини; «не выполнилось»\n"
        "  (код 2, нет инструмента или предмета) верни строкой «блокер» в ВОЗВРАТ, не обходи."),
    "skip-prepush": (
        "снятие наборов хука отправки («%s»)",
        "KACHO_SKIP_PREPUSH снимает наборы хука отправки; запрещено (база диспетчера, 2026-10-04).",
        "отправляй без него; долгий хук — run_in_background: true, а не обход."),
    "force": (
        "переписывание опубликованной истории («%s»)",
        "push с --force / -f / --force-with-lease / «+refspec» затирает чужие коммиты на\n"
        "удалённом; запрещено (решение владельца 2026-10-06: без --force, reset, rebase).",
        "догони удалённую ветку слиянием (git fetch && git merge origin/<ветка>) и отправь\n"
        "  обычным git push; если удалённая ушла неожиданно — это вопрос диспетчеру, не повод затирать."),
    "push-all": (
        "отправка всех веток разом («%s»)",
        "--all / --branches / --mirror шлют и ствол, а --mirror ещё и затирает удалённое.",
        "отправляй одну свою ветку: git push -u origin <N>-<суть>."),
    "trunk": (
        "прямая отправка в ствол («%s»)",
        "main/master меняется только вливанием запроса (защита ствола, enforce_admins);\n"
        "прямой push и удаление ствола запрещены.",
        "отправь свою ветку (git push -u origin <N>-<суть>); вливание — git-operator:\n"
        "  gh pr merge <N> --merge --match-head-commit <sha вердикта>."),
    "admin": (
        "вливание в обход защиты ветки («%s»)",
        "--admin снимает обязательные проверки и ревью; запрещено (решение владельца 2026-10-06).",
        "дождись зелёных обязательных проверок и вердикта; красная проверка — ci-watcher,\n"
        "  недостающий вердикт — диспетчеру."),
    "hookspath": (
        "перенаправление хуков git («%s»)",
        "core.hooksPath отключает ВСЕ хуки клона из .git/hooks — молча (scripts/hooks/install.sh).",
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
    return key.strip().lower() == "core.hookspath"


def is_include(key):
    """`include.path` и `includeIf.<условие>.path` — подключение файла конфигурации."""
    key = key.strip().lower()
    return key == "include.path" or (key.startswith("includeif.") and key.endswith(".path"))


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


def env_findings(assignments, cwd=None):
    values = dict(e.partition("=")[::2] for e in assignments)
    for e in assignments:
        name, _, val = e.partition("=")
        bare = val.strip("'\"")
        m = re.match(r"^GIT_CONFIG_KEY_(\d+)$", name)
        if name == SKIP_ENV and bare not in ("", "0"):
            yield "skip-prepush", e
        elif m and is_hookspath(bare):
            yield "hookspath", e
        elif m and is_include(bare) and \
                file_sets_hookspath(values.get("GIT_CONFIG_VALUE_" + m.group(1), ""), cwd):
            yield "hookspath", "%s GIT_CONFIG_VALUE_%s=%s" % (e, m.group(1),
                                                              values["GIT_CONFIG_VALUE_" + m.group(1)])
        elif name == "GIT_CONFIG_PARAMETERS" and "core.hookspath" in val.lower():
            yield "hookspath", e
        elif name in ("GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM") and file_sets_hookspath(val, cwd):
            yield "hookspath", e


def long_options(sub, where, gitdir=None):
    """Перечень длинных опций подкоманды у того git, который её исполнит; None — не
    получен. `--git-completion-helper-all` требует репозитория, поэтому зовётся в
    каталоге команды (`-C`, `--git-dir`), как и `current_branch`."""
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


def split_opts(sub, rest):
    """(флаги, позиционные) подкоманды; значения опций пропущены, `--` кончает опции."""
    flags, pos, k = [], [], 0
    short_v, long_v = SHORT_VALUE.get(sub, ""), LONG_VALUE.get(sub, set())
    while k < len(rest):
        a = rest[k]
        if a == "--":
            pos.extend(rest[k + 1:])
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
        pos.append(a)
        k += 1
    return flags, pos


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


def current_branch(path, gitdir=None):
    """Текущая ветка каталога `path`; `gitdir` (`--git-dir`/`GIT_DIR`) перекрывает
    обнаружение репозитория по каталогу — так же, как у самого git."""
    cmd = ["git", "-C", path]
    if gitdir:
        cmd.append("--git-dir=" + os.path.join(path, os.path.expanduser(gitdir)))
    try:
        out = subprocess.run(cmd + ["symbolic-ref", "--quiet", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=3,
                             env={k: v for k, v in os.environ.items() if k != "GIT_DIR"})
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def strip_heads(ref):
    ref = ref.lstrip("+")
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def push_findings(flags, pos, where, gitdir=None, opts=None):
    shown = " ".join(["git", "push"] + flags + pos)
    opts = opts or Options("push", where, gitdir)
    for a in flags:
        if bundle_has(a, "f", SHORT_VALUE["push"]):
            yield "force", shown
            return
        if a.startswith("--"):
            for target, kind in PUSH_FORBIDDEN:
                if opts.names(a, target):
                    yield kind, shown
                    return
    refspecs = pos[1:]
    if any(r.startswith("+") for r in refspecs):
        yield "force", shown
        return
    tags_only = any(a.split("=", 1)[0] == "--tags" for a in flags)
    branch = None
    for r in refspecs:
        dst = strip_heads(r.split(":", 1)[1] if ":" in r else r)
        if dst in ("HEAD", "@"):
            branch = branch or current_branch(where, gitdir)
            dst = branch or dst
        if dst in PROTECTED:
            yield "trunk", shown
            return
    if not refspecs and not tags_only:
        if current_branch(where, gitdir) in PROTECTED:
            yield "trunk", shown


def config_findings(rest, where=None):
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
        if len(pos) > 2 and (is_hookspath(pos[1])
                             or (is_include(pos[1]) and file_sets_hookspath(pos[2], where))):
            yield "hookspath", shown
        return
    if pos[:1] and pos[0] in ("get", "list", "unset", "edit", "rename-section", "remove-section"):
        return
    if any(f in CONFIG_NOT_SET for f in flags):
        return
    # запись — ключ И значение позиционными (`--add`/`--replace-all` без значения
    # git отвергает сам, поэтому отдельной ветви по этим флагам нет)
    if len(pos) >= 2 and (is_hookspath(pos[0])
                          or (is_include(pos[0]) and file_sets_hookspath(pos[1], where))):
        yield "hookspath", shown


def env_gitdir(assignments):
    """Последнее присваивание GIT_DIR с буквальным значением; иначе None."""
    found = None
    for e in assignments:
        name, _, val = e.partition("=")
        if name == "GIT_DIR":
            val = val.strip("'\"")
            found = val if val and "$" not in val and "__SUBST__" not in val else None
    return found


def git_findings(args, cwd, gitdir=None):
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
    if sub in NO_VERIFY_SUBS:
        flags, pos = split_opts(sub, rest)
        opts = Options(sub, where or os.getcwd(), gitdir)
        for a in flags:
            if (a.startswith("--") and opts.names(a, "--no-verify")) \
                    or (sub in SHORT_NO_VERIFY and bundle_has(a, "n", SHORT_VALUE[sub])):
                yield "no-verify", " ".join(["git", sub] + rest)
                return
        if sub == "push":
            yield from push_findings(flags, pos, where or os.getcwd(), gitdir, opts)
    elif sub == "config":
        yield from config_findings(rest, where or os.getcwd())


def gh_findings(args):
    """`gh [-R репо] pr [-R репо] merge … --admin`. Значения опций (`-R X`,
    `--body X`) пропускаются: иначе `X` встаёт на место подкоманды и `--admin`
    уходит мимо (возврат check-verifier ws#974)."""
    words, flags, k = [], [], 0
    while k < len(args):
        a = args[k]
        if a == "--":
            break
        if a.startswith("-") and len(a) > 1:
            flags.append(a)
            k += 2 if a in GH_VALUE else 1
            continue
        words.append(a)
        k += 1
    if words[:2] != ["pr", "merge"]:
        return
    for a in flags:
        head, eq, val = a.partition("=")
        if head == "--admin" and (not eq or val.lower() not in ("false", "0")):
            yield "admin", " ".join(["gh"] + args)
            return


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
            yield from env_findings(env, cur)
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
                yield from env_findings(assigns, cur)
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

    def argv(self, argv, cur, depth, env=()):
        hg = self.hg
        base, args = os.path.basename(argv[0]), argv[1:]
        if base == "git":
            yield from git_findings(args, cur, env_gitdir(env))
        elif base == "gh":
            yield from gh_findings(args)
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
                    yield from env_findings(sub_env, cur)
                    if sub:
                        yield from self.argv(sub, cur, depth, list(env) + sub_env)


def deny(kind, shown):
    what, why, instead = DENY[kind]
    shown = shown if len(shown) <= 300 else shown[:297] + "…"
    sys.stderr.write(
        "GIT-GUARD: отказ [%s] — %s.\n%s\nЧто делать вместо: %s\n"
        "Если команда законна и отказ ложный — не обходи его: верни строку «блокер» с этой\n"
        "командой в ВОЗВРАТ; страж правит tooling-maintainer.\n"
        % (kind, what % shown, why, instead))
    sys.exit(2)


def broken(why):
    msg = ("GIT-GUARD СЛОМАН: %s. Команды git этим вызовом НЕ проверялись — это не «чисто»: "
           "--no-verify, KACHO_SKIP_PREPUSH, push --force/+refspec, push в main/master, "
           "gh pr merge --admin и core.hooksPath запрещены и без стража; починка — "
           "tooling-maintainer." % why)
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "additionalContext": msg}}, ensure_ascii=False))
    sys.exit(0)


def find(text, cwd, hg=None):
    for hit in Judge(hg or load_parser()).text(text, cwd):
        return hit
    return None


def main():
    if sys.argv[1:] == ["--boundary"]:
        sys.stdout.write("".join("%s\0%s\0" % b for b in BOUNDARY))
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
