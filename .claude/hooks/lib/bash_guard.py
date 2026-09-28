#!/usr/bin/env python3
"""Страж команды Bash до исполнения (`PreToolUse`): два запрета, которые держались вниманием.

# Предмет

1. `git stash` в ОБЩЕЙ рабочей копии (ws#602). Общая копия — рабочее дерево, которым
   пользуются несколько агентов сразу: корень воркспейса и клон продукта. `pop` в ней
   вынимает ЧУЖОЙ схрон, а незакоммиченная чужая работа существует в единственном
   экземпляре. Запрет стоял в теле `git-operator`, `landing-reviewer`, `scout` и в
   архивном своде — и за одну сессию (2026-09-08) нарушен дважды.
2. `git push` полосы, чья база НЕ ЗНАЕТ проверок ствола (ws#717). Набор гейтов обходит
   свой каталог и печатает «рассмотрено N» по тому, что НАШЁЛ. Отставшая база даёт
   зелёный на меньшем числе проверок, и он неотличим от зелёного на полном: код один,
   число никто не сверяет. Новая проверка ствола не судит полосу, пока до неё не
   доберётся база, — и этого момента не наблюдает никто.

# Признаки — из git, а не из списка путей

«Общая копия» — ГЛАВНОЕ рабочее дерево (`--git-dir` совпадает с `--git-common-dir`)
репозитория, у которого есть хотя бы одно присоединённое. Своя копия полосы —
присоединённое дерево в `tmp/`: там `stash` законен и полезен, и запрет его не трогает.

«База не знает проверки ствола» — файл `scripts/<набор>-gate/check-*` есть на
`origin/main`, его нет в отправляемой ревизии И нет в их общей базе. Последнее
условие отличает ОТСТАВАНИЕ (ствол завёл проверку после развилки) от СНЯТИЯ (полоса
сама удалила проверку, которая была в базе): второе — решение полосы, и страж его
не судит.

# Обход — явный и видимый

Обход — присваивание в самой команде: `KACHO_STASH_SHARED=1 git stash …`,
`KACHO_PUSH_LAGGING=1 git push …`. Он остаётся в тексте команды, то есть в ленте
сессии, и исполнитель обязан назвать его в возврате (строка нормы в `ai-tooling.md`).

# Граница, объявленная, а не умолчанная

- Судится текст команды, разобранный лексером оболочки (`shell_lex.py` рядом —
  тот же разбор читает tooling-gate check-21), а не построчно: кавычки, `$(…)`, обратные кавычки и тело heredoc распознаются ДО того,
  как перевод строки становится разделителем. Прежняя редакция резала команду по
  строкам до `shlex`, и штатная форма коммита — `-m "$(cat <<'EOF' … EOF)"` — давала
  «не разобрана», а отправка в той же команде проходила несуженной.
- Разделители — `&&`, `||`, `;`, `|`, `&`, `|&` и перевод строки вне кавычек и вне
  тела heredoc. Тело heredoc — данные, не команды.
- Каталог выводится из `cd`, `pushd`/`popd` и `git -C`; подоболочка `( … )` каталог
  наружу не переносит. Команды внутри `$( … )`, обратных кавычек и `<( … )` судятся
  как вложенные, с каталогом точки подстановки.
- Префиксы перед git, которые исполняют его же: присваивания `ИМЯ=…`, слова `if`,
  `then`, `elif`, `else`, `do`, `while`, `until`, `!`, `{`, `time [-p]` и обёртки
  `env` (включая `-C <каталог>`), `builtin`, `command`, `exec`, `nice`, `nohup`,
  `setsid`, `stdbuf`, `ionice`, `timeout`. Снятие префиксов общее для `git` и для
  `cd`/`pushd`/`popd`: `builtin cd <каталог>` ведёт каталог так же, как `cd`.
- НЕ различается и этого страж не утверждает: команда, собранная иначе (`eval`,
  `bash -c '…'`, `sh -c`, имя подкоманды или каталог из переменной — переменные не
  раскрываются, алиас git, функция оболочки), обёртки `sudo`, `xargs`, `find -exec`,
  `watch`, `parallel`.
- Отправку не через `git push` (`gh pr create`, догоняющая отправку ветки) страж не видит.
- Ствол — локальная ссылка `origin/main`: страж не делает `fetch`, и отставание судится
  от ствола, каким его видела последняя выборка. Ссылки нет — отставание не судится
  (канала, которым сказать это агенту без отказа, у `PreToolUse` нет).
- Общий на все деревья репозитория список схронов (`refs/stash`) страж не судит: `pop`
  без явной ссылки в СВОЕЙ копии тоже может вынуть чужое.
- Команда, которую не разобрать (незакрытая кавычка или подстановка), — код 1: её не
  исполнит и сама оболочка, а страж, не понявший команду, не вправе её останавливать.

Исходы: 0 — пропустить; 2 — отказ (stderr уходит агенту, команда не исполняется);
1 — поломка самого стража (stderr видит человек, команда НЕ блокируется: страж,
упавший на своей ошибке, не вправе останавливать чужую работу).
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shell_lex import REDIRECT, SEP, Word, lex, strip_prefixes  # noqa: E402  — разбор оболочки
#   и снятие префиксов перед командой одни на страж и гейт (tooling-gate check-21)

TRUNK = "origin/main"
CHECK = re.compile(r"^scripts/[^/]+-gate/check-[^/]+$")
BYPASS_STASH = "KACHO_STASH_SHARED"
BYPASS_PUSH = "KACHO_PUSH_LAGGING"
STASH_READONLY = {"list", "show"}


def git(cwd: str, *args: str) -> tuple[int, str]:
    try:
        p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return 128, ""
    return p.returncode, p.stdout.strip()


def commands(command: str, cwd: str) -> list[tuple[list[str], str, dict]]:
    """→ [(слова простой команды, каталог её исполнения, присваивания перед ней)] —
    вложенные подстановки тоже.

    Каталог ведётся по `cd`, `pushd`/`popd`; подоболочка `( … )` возвращает его на
    выходе. Перенаправления и их цели из слов команды сняты.
    """
    out: list[tuple[list[str], str, dict]] = []
    here = cwd
    oldpwd = cwd
    dirstack: list[str] = []
    frames: list[tuple[str, str, list[str]]] = []
    words: list = []
    toks = lex(command)

    def flush() -> None:
        nonlocal here, oldpwd, words
        ws, i = [], 0
        while i < len(words):
            w = words[i]
            if isinstance(w, str) and not isinstance(w, Word) and w in REDIRECT:
                i += 2                          # оператор и его цель
                continue
            ws.append(w)
            i += 1
        words = []
        for w in ws:
            for sub in getattr(w, "subs", ()):
                out.extend(commands(sub, here))
        argv, env, at = strip_prefixes([str(w) for w in ws], here)
        if not argv:
            return
        name = argv[0]
        if name == "cd":
            args = [a for a in argv[1:] if not (a.startswith("-") and a != "-")]
            dest = args[0] if args else os.path.expanduser("~")
            new = oldpwd if dest == "-" else os.path.normpath(
                os.path.join(here, os.path.expanduser(dest)))
            oldpwd, here = here, new
            return
        if name == "pushd":
            args = [a for a in argv[1:] if not a.startswith("-")]
            if args and not re.fullmatch(r"[+-]\d+", args[0]):
                dirstack.append(here)
                oldpwd, here = here, os.path.normpath(
                    os.path.join(here, os.path.expanduser(args[0])))
            return
        if name == "popd":
            if dirstack:
                oldpwd, here = here, dirstack.pop()
            return
        out.append((argv, at, env))

    for t in toks:
        if isinstance(t, Word):
            words.append(t)
            continue
        if t == "(" and not words:
            frames.append((here, oldpwd, list(dirstack)))
            continue
        if t == ")":
            flush()
            if frames:
                here, oldpwd, dirstack = frames.pop()
            continue
        if t in SEP:
            flush()
            continue
        words.append(t)                          # перенаправление: снимется во flush
    flush()
    return out


GIT_OPT_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def parse_git(tokens: list[str], cwd: str) -> tuple[str, str, list[str], dict]:
    """→ (подкоманда, каталог, аргументы, присваивания окружения) либо ('', …)."""
    tokens, env, cwd = strip_prefixes(tokens, cwd)
    if not tokens or os.path.basename(tokens[0]) != "git":
        return "", cwd, [], env
    i = 1
    d = cwd
    while i < len(tokens) and tokens[i].startswith("-"):
        t = tokens[i]
        if t == "-C" and i + 1 < len(tokens):
            d = os.path.normpath(os.path.join(d, os.path.expanduser(tokens[i + 1])))
            i += 2
            continue
        if t in GIT_OPT_WITH_ARG and i + 1 < len(tokens):
            i += 2
            continue
        i += 1
    if i >= len(tokens):
        return "", d, [], env
    return tokens[i], d, tokens[i + 1:], env


def shared_copy(d: str) -> tuple[bool, str]:
    rc, top = git(d, "rev-parse", "--show-toplevel")
    if rc != 0:
        return False, ""
    _, gd = git(d, "rev-parse", "--path-format=absolute", "--git-dir")
    _, cd = git(d, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not gd or not cd:
        return False, top
    if os.path.realpath(gd) != os.path.realpath(cd):
        return False, top            # присоединённое дерево — своя копия полосы
    _, wl = git(d, "worktree", "list", "--porcelain")
    n = sum(1 for ln in wl.split("\n") if ln.startswith("worktree "))
    return n > 1, top


def checks_at(d: str, ref: str) -> set[str]:
    rc, out = git(d, "ls-tree", "-r", "--name-only", ref, "--", "scripts")
    if rc != 0:
        return set()
    return {p for p in out.split("\n") if CHECK.match(p)}


def push_source(d: str, args: list[str]) -> tuple[str, str]:
    """→ (ревизия, почему пропущено). Удаление, теги и зеркало не судятся."""
    pos = []
    skip_next = False
    for a in args:
        if skip_next:
            skip_next = False
            continue
        if a in ("--delete", "-d", "--tags", "--mirror", "--prune"):
            return "", f"`git push {a}` — не отправка ревизии полосы"
        if a in ("-o", "--push-option", "--repo", "--receive-pack", "--exec"):
            skip_next = True
            continue
        if a.startswith("-"):
            continue
        pos.append(a)
    refspecs = pos[1:]
    if not refspecs:
        return "HEAD", ""
    src = refspecs[0].lstrip("+").split(":", 1)[0]
    if not src:
        return "", "refspec `:<ветка>` — удаление"
    rc, sha = git(d, "rev-parse", "--verify", "--quiet", src + "^{commit}")
    if rc != 0:
        return "HEAD", ""
    return sha, ""


def judge_stash(d: str, args: list[str], env: dict) -> str:
    action = next((a for a in args if not a.startswith("-")), "push")
    if action in STASH_READONLY:
        return ""
    shared, top = shared_copy(d)
    if not shared or env.get(BYPASS_STASH) == "1":
        return ""
    return (f"`git stash {action}` в ОБЩЕЙ рабочей копии {top} — это главное дерево "
            "репозитория с присоединёнными копиями, им пользуются несколько агентов. "
            "`pop` вынимает ЧУЖОЙ схрон, а чужая незакоммиченная работа — в единственном "
            "экземпляре (ws#602). Своя копия полосы — присоединённое дерево в tmp/: там "
            f"stash законен. Обход, если он осознан: `{BYPASS_STASH}=1 git stash …` — и "
            "строка об этом в возврате.")


def judge_push(d: str, args: list[str], env: dict) -> str:
    rc, _ = git(d, "rev-parse", "--verify", "--quiet", TRUNK + "^{commit}")
    if rc != 0:
        return ""               # ствола нет — отставание судить не по чему
    src, _why = push_source(d, args)
    if not src:
        return ""
    _, head = git(d, "rev-parse", "--verify", "--quiet", src + "^{commit}")
    if not head:
        return ""
    rc, base = git(d, "merge-base", head, TRUNK)
    if rc != 0 or not base:
        return ""
    lag = sorted(checks_at(d, TRUNK) - checks_at(d, head) - checks_at(d, base))
    if not lag or env.get(BYPASS_PUSH) == "1":
        return ""
    _, top = git(d, "rev-parse", "--show-toplevel")
    shown = ", ".join(lag[:6]) + (f" и ещё {len(lag) - 6}" if len(lag) > 6 else "")
    return (f"`git push` из {top}: база полосы НЕ ЗНАЕТ проверок ствола — {len(lag)} "
            f"({shown}). Они заведены на {TRUNK} после развилки; наборы полосы "
            "печатают «рассмотрено N» по тому, что нашли, и зелёный на меньшем N "
            "неотличим от зелёного на полном (ws#717). Прежде отправки — влить ствол в "
            "ветку (git-operator) и прогнать наборы. Обход, если он осознан: "
            f"`{BYPASS_PUSH}=1 git push …` — и строка об этом в возврате.")


RULES = {"stash": judge_stash, "push": judge_push}


def judge(command: str, cwd: str) -> list[str]:
    denials: list[str] = []
    for argv, here, pre in commands(command, cwd):
        sub, d, args, env = parse_git(argv, here)
        env = {**pre, **env}
        rule = RULES.get(sub)
        if rule:
            msg = rule(d, args, env)
            if msg:
                denials.append(msg)
    return denials


def main() -> int:
    try:
        ev = json.load(sys.stdin)
    except Exception:  # noqa: BLE001
        sys.stderr.write("bash-guard СЛОМАН: вход не разобран как JSON — команда НЕ судилась "
                         "(пропущена). → tooling-maintainer\n")
        return 1
    if ev.get("tool_name") not in (None, "Bash"):
        return 0
    ti = ev.get("tool_input") or {}
    command = ti.get("command") or ""
    cwd = ti.get("cwd") or ev.get("cwd") or os.getcwd()
    try:
        denials = judge(command, cwd)
    except ValueError as e:
        # Незакрытая кавычка и подобное: команду не разобрать — не судим, но говорим.
        sys.stderr.write(f"bash-guard: команда не разобрана ({e}) — не судилась. "
                         "Запреты stash в общей копии и push с отставшей базой к ней не применены.\n")
        return 1
    if not denials:
        return 0
    sys.stderr.write("╔══ bash-guard: команда НЕ исполнена ══════════════════════════════\n")
    for d in denials:
        sys.stderr.write(f"║ {d}\n")
    sys.stderr.write("╚═════════════════════════════════════════════════════════════════\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
