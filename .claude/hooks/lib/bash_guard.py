#!/usr/bin/env python3
"""Страж команды Bash до исполнения (`PreToolUse`): запрет, который держался вниманием.

# Предмет

`git push` полосы, чья база НЕ ЗНАЕТ проверок ствола (ws#717). Набор гейтов обходит
   свой каталог и печатает «рассмотрено N» по тому, что НАШЁЛ. Отставшая база даёт
   зелёный на меньшем числе проверок, и он неотличим от зелёного на полном: код один,
   число никто не сверяет. Новая проверка ствола не судит полосу, пока до неё не
   доберётся база, — и этого момента не наблюдает никто.

# Признаки — из git, а не из списка путей

«База не знает проверки ствола» — файл `scripts/<набор>-gate/check-*` есть на
`origin/main`, его нет в отправляемой ревизии И нет в их общей базе. Последнее
условие отличает ОТСТАВАНИЕ (ствол завёл проверку после развилки) от СНЯТИЯ (полоса
сама удалила проверку, которая была в базе): второе — решение полосы, и страж его
не судит.

# Обход — явный и видимый

Обход — присваивание в самой команде: `KACHO_PUSH_LAGGING=1 git push …`. Он остаётся
в тексте команды, то есть в ленте сессии, и исполнитель обязан назвать его в возврате
(строка нормы в `ai-tooling.md`).

# Граница, объявленная, а не умолчанная

- Судится текст команды, разобранный `shlex`, по сегментам (`&&`, `||`, `;`, `|`,
  перевод строки) с учётом `cd <каталог>` и `git -C <каталог>`. Команду, собранную
  иначе (`eval`, переменная с именем подкоманды, `bash -c '…'`, алиас git), страж не
  различает и этого не утверждает.
- Отправку не через `git push` (`gh pr create`, догоняющая отправку ветки) страж не видит.
- Ствол — локальная ссылка `origin/main`: страж не делает `fetch`, и отставание судится
  от ствола, каким его видела последняя выборка. Ссылки нет — отставание не судится
  (канала, которым сказать это агенту без отказа, у `PreToolUse` нет).

Исходы: 0 — пропустить; 2 — отказ (stderr уходит агенту, команда не исполняется);
1 — поломка самого стража (stderr видит человек, команда НЕ блокируется: страж,
упавший на своей ошибке, не вправе останавливать чужую работу).
"""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
import sys

TRUNK = "origin/main"
CHECK = re.compile(r"^scripts/[^/]+-gate/check-[^/]+$")
BYPASS_PUSH = "KACHO_PUSH_LAGGING"
SEP = {"&&", "||", ";", "|", "&", "\n", "|&"}


def git(cwd: str, *args: str) -> tuple[int, str]:
    try:
        p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return 128, ""
    return p.returncode, p.stdout.strip()


def segments(command: str) -> list[list[str]]:
    out: list[list[str]] = [[]]
    # Перевод строки — тоже разделитель команд: shlex его глотает, поэтому команда
    # режется по строкам заранее.
    for line in command.split("\n"):
        lex = shlex.shlex(line, posix=True, punctuation_chars=";&|")
        lex.whitespace_split = True
        lex.commenters = "#"
        for tok in lex:
            if tok in SEP or set(tok) <= set(";&|"):
                out.append([])
            else:
                out[-1].append(tok)
        out.append([])
    return [s for s in out if s]


GIT_OPT_WITH_ARG = {"-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"}


def parse_git(tokens: list[str], cwd: str) -> tuple[str, str, list[str], dict]:
    """→ (подкоманда, каталог, аргументы, присваивания окружения) либо ('', …)."""
    env: dict[str, str] = {}
    i = 0
    while i < len(tokens) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[i]):
        k, _, v = tokens[i].partition("=")
        env[k] = v
        i += 1
    if i < len(tokens) and tokens[i] in ("env", "command", "exec"):
        i += 1
        while i < len(tokens) and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[i]):
            k, _, v = tokens[i].partition("=")
            env[k] = v
            i += 1
    if i >= len(tokens) or os.path.basename(tokens[i]) != "git":
        return "", cwd, [], env
    i += 1
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


RULES = {"push": judge_push}


def judge(command: str, cwd: str) -> list[str]:
    denials: list[str] = []
    here = cwd
    for seg in segments(command):
        if seg and seg[0] == "cd":
            if len(seg) > 1:
                here = os.path.normpath(os.path.join(here, os.path.expanduser(seg[1])))
            continue
        sub, d, args, env = parse_git(seg, here)
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
                         "Запрет push с отставшей базой к ней не применён.\n")
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
