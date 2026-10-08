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
  · `--no-verify` у git commit/push/merge/pull/am/rebase/cherry-pick/revert, в
    том числе сокращением (`--no-veri`) и `-n` в связке коротких флагов commit
    (`-anm msg`); у merge и push `-n` — другое (--no-stat, --dry-run), не судится;
  · присваивание `KACHO_SKIP_PREPUSH` не нулём — перед командой и `export`;
  · git push с `--force`, `-f` (и в связке), `--force-with-lease[=…]`, refspec с
    `+`, а также `--mirror`/`--all`/`--branches` (переписывают либо шлют ствол);
  · git push, чья цель — `main`/`master` (`origin main`, `HEAD:main`,
    `refs/heads/main`, удаление `:main`), и голый `git push` / `push origin [HEAD]`,
    когда текущая ветка — `main`/`master` (ветка читается `git symbolic-ref` в
    каталоге команды: `cd`, `-C` учтены);
  · `gh pr merge … --admin`;
  · перенаправление хуков: `git -c core.hooksPath=…`, `--config-env=core.hooksPath=…`,
    `GIT_CONFIG_KEY_<n>=core.hooksPath`, `GIT_CONFIG_PARAMETERS` с ним и запись
    `git config [set|--add|--replace-all] core.hooksPath …`.

Что НЕ отказывается (законные близнецы, prove.sh исполняет каждый): обычный
`git push -u origin <N>-<суть>`, удаление своей ветки (`push -d`, `:ветка`),
`--no-force-with-lease`, чтение `git config core.hooksPath` и `--get`, его снятие
`--unset` (лечение «hooksPath в никуда», которое ловит hooks-wired.sh),
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

ГРАНИЦА — то, чего страж НЕ ловит, перечнем: BOUNDARY ниже; prove.sh исполняет
каждый пример строкой [BOUND] («известно, не ловится»), пойманный пример — [FAIL]:
перечень устарел. Предел держит сервер (защита ветки, способ вливания), страж —
напоминание против случайных форм, а не барьер против намеренного обхода.
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
NO_VERIFY_SUBS = {"commit", "push", "merge", "pull", "am", "rebase", "cherry-pick", "revert"}
GIT_GLOBAL_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix",
                    "--config-env", "--attr-source"}
# опции подкоманды, берущие значение СЛЕДУЮЩИМ словом: оно — не флаг и не refspec
SHORT_VALUE = {
    "commit": "mFcCt",
    "push": "o",
    "merge": "mFsX",
    "pull": "sX",
}
LONG_VALUE = {
    "commit": {"--message", "--file", "--template", "--reuse-message", "--reedit-message",
               "--author", "--date", "--fixup", "--squash", "--cleanup", "--trailer",
               "--pathspec-from-file"},
    "push": {"--push-option", "--repo", "--receive-pack", "--exec"},
    "merge": {"--message", "--file", "--strategy", "--strategy-option", "--into-name"},
    "pull": {"--strategy", "--strategy-option", "--depth", "--shallow-since",
             "--shallow-exclude", "--deepen", "--upload-pack", "--negotiation-tip"},
}
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


def env_findings(assignments):
    for e in assignments:
        name, _, val = e.partition("=")
        if name == SKIP_ENV and val.strip("'\"") not in ("", "0"):
            yield "skip-prepush", e
        elif re.match(r"^GIT_CONFIG_KEY_\d+$", name) and is_hookspath(val.strip("'\"")):
            yield "hookspath", e
        elif name == "GIT_CONFIG_PARAMETERS" and "core.hookspath" in val.lower():
            yield "hookspath", e


def no_verify_word(a):
    """`--no-verify` и его однозначные сокращения (git принимает префикс длинной опции)."""
    head = a.split("=", 1)[0]
    return len(head) >= len("--no-veri") and "--no-verify".startswith(head)


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


def current_branch(path):
    try:
        out = subprocess.run(["git", "-C", path, "symbolic-ref", "--quiet", "--short", "HEAD"],
                             capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() if out.returncode == 0 else None


def strip_heads(ref):
    ref = ref.lstrip("+")
    return ref[len("refs/heads/"):] if ref.startswith("refs/heads/") else ref


def push_findings(flags, pos, where):
    shown = " ".join(["git", "push"] + flags + pos)
    for a in flags:
        head = a.split("=", 1)[0]
        if head == "--force" or (len(head) >= len("--force-w") and "--force-with-lease".startswith(head)) \
                or bundle_has(a, "f", SHORT_VALUE["push"]):
            yield "force", shown
            return
        if head in ("--mirror", "--all", "--branches"):
            yield "push-all", shown
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
            branch = branch or current_branch(where)
            dst = branch or dst
        if dst in PROTECTED:
            yield "trunk", shown
            return
    if not refspecs and not tags_only:
        if current_branch(where) in PROTECTED:
            yield "trunk", shown


def config_findings(rest):
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
        if len(pos) > 1 and is_hookspath(pos[1]):
            yield "hookspath", shown
        return
    if pos[:1] and pos[0] in ("get", "list", "unset", "edit", "rename-section", "remove-section"):
        return
    if any(f in CONFIG_NOT_SET for f in flags):
        return
    writes = any(f in ("--add", "--replace-all") for f in flags) or len(pos) >= 2
    if writes and pos and is_hookspath(pos[0]):
        yield "hookspath", shown


def git_findings(args, cwd):
    k, where = 0, cwd
    while k < len(args) and args[k].startswith("-"):
        a = args[k]
        head, eq, val = a.partition("=")
        if a == "-C" and k + 1 < len(args):
            where = os.path.join(where or os.getcwd(), os.path.expanduser(args[k + 1]))
        if a == "-c" and k + 1 < len(args) and is_hookspath(args[k + 1].split("=", 1)[0]):
            yield "hookspath", "git -c " + args[k + 1]
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
        for a in flags:
            if no_verify_word(a) or (sub == "commit" and bundle_has(a, "n", SHORT_VALUE["commit"])):
                yield "no-verify", " ".join(["git", sub] + rest)
                return
        if sub == "push":
            yield from push_findings(flags, pos, where or os.getcwd())
    elif sub == "config":
        yield from config_findings(rest)


def gh_findings(args):
    words = [a for a in args if not a.startswith("-")]
    if words[:2] != ["pr", "merge"]:
        return
    for a in args:
        if a == "--":
            break
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
            yield from env_findings(env)
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
                yield from env_findings(assigns)
                vis.extend(assigns)
                continue
            yield from self.argv(argv, cur, depth)
        for intro, body in bodies:
            # heredoc, поданный оболочке (`bash <<EOF`), — её команды; прочие — данные
            for seg in hg.split_commands(intro):
                _, argv = hg.unwrap(hg.words(seg))
                if argv and os.path.basename(argv[0]) in hg.SHELLS and hg.shell_args(argv[1:])[3]:
                    yield from self.text(body, cur, depth + 1)
                    break

    def argv(self, argv, cur, depth):
        hg = self.hg
        base, args = os.path.basename(argv[0]), argv[1:]
        if base == "git":
            yield from git_findings(args, cur)
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
                    env, sub = hg.unwrap(sub)
                    yield from env_findings(env)
                    if sub:
                        yield from self.argv(sub, cur, depth)


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
