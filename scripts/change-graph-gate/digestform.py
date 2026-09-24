#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Команда дайджеста содержимого в записях ревью несёт `--full-index`.

ЗАЧЕМ. Запись ревью ключуется дайджестом диффа (`git diff A...B | sha256sum`).
Без `--full-index` строки `index` несут СОКРАЩЁННЫЕ хеши объектов, а длина
сокращения (`core.abbrev=auto`) растёт с числом объектов клона: один и тот же
дифф даёт разные дайджесты в свежем, неглубоком и конвейерном клоне, и запись
перестаёт воспроизводиться собственной командой (ws#818).

ЧТО СУДИТСЯ. Записи — отслеживаемые файлы `docs/changes/**` и `docs/**/reviews/**`
на коммите `--rev` (индекс и рабочее дерево не читаются). Команда дайджеста —
вызов `git [опции] diff …`, чей вывод трубой уходит в `sha256sum` либо
`shasum -a 256`; пробелы и переводы строк сводятся к одному пробелу, поэтому
команда, разнесённая по строкам YAML или абзаца, распознаётся так же. Инлайн-код
(`` ` ``) команду обрывает: `git diff --quiet …` и `git show … | sha256sum` в
соседних кавычках одной командой не являются.

ГРАНИЦА. Влитые записи не правятся: имя файла и есть их дайджест. Команда без
`--full-index`, стоявшая в ТОМ ЖЕ пути на `BOUNDARY`, унаследована; любая другая
(новый путь или дописанная в старый) — находка. Граница объявлена одним местом —
константой ниже.

ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ. На границе записи несут команды без `--full-index`;
распознаватель, не увидевший там ни одной, слеп к форме, которой дерево пишет, —
это находка, а не «новых нарушений нет».

ЧЕГО НЕ УТВЕРЖДАЕТ. Дайджест, снятый в файл и захешированный отдельной командой,
либо иным хешем, не распознаётся.

Коды: 0 — записи прочитаны, контроль сошёлся, находок нет; 1 — находка, пустой
обход или слепой распознаватель; 2 — ревизия или граница в клоне не разрешаются.
"""

import argparse
import collections
import re
import subprocess
import sys

BOUNDARY = "fb7a2cbbb7c8bd14b175682e189d64583bd89e5b"

# Аргумент — слово без `;`, тире, стрелки, инлайн-кода и трубы, не кончающееся
# двоеточием: иначе команда «тянулась» бы через прозу и ключи YAML до чужой трубы.
ARG = r"[^\s;—−→`|]*[^\s;—−→`|:]"
DIGEST = re.compile(
    r"\bgit((?: +(?:-[Cc] +\S+|--[\w-]+(?:=\S+)?))*) +diff\b((?: +" + ARG + r")*)"
    r" *\| *(?:sha256sum|shasum +-a *256)\b"
)


def say(tag, text, err=False):
    (sys.stderr if err else sys.stdout).write("[%s] %s\n" % (tag, text))


def git(home, *args):
    out = subprocess.run(["git", "-C", home] + list(args),
                         capture_output=True, check=False)
    return out.returncode, out.stdout


def commit(home, rev):
    rc, out = git(home, "rev-parse", "--verify", "-q", rev + "^{commit}")
    return out.decode().strip() if rc == 0 else None


def records(home, rev):
    rc, out = git(home, "ls-tree", "-r", "-z", "--name-only", rev, "--", "docs")
    paths = [p for p in out.decode("utf-8", "replace").split("\0") if p]
    return [p for p in paths if p.startswith("docs/changes/") or "/reviews/" in p]


def commands(home, rev, paths):
    """{путь: Counter(команда без --full-index)} и число команд с ним."""
    feed = "".join("%s:%s\n" % (rev, p) for p in paths).encode()
    out = subprocess.run(["git", "-C", home, "cat-file", "--batch"], input=feed,
                         capture_output=True, check=True).stdout
    bad, full, pos = {}, 0, 0
    for path in paths:
        end = out.index(b"\n", pos)
        size = int(out[pos:end].split()[2])
        text = out[end + 1:end + 1 + size].decode("utf-8", "replace")
        pos = end + 2 + size
        bad[path] = collections.Counter()
        for m in DIGEST.finditer(" ".join(text.split())):
            if "--full-index" in m.group(2).split():
                full += 1
            else:
                bad[path][m.group(0)] += 1
    return bad, full


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--rev", default="HEAD")
    ap.add_argument("--home", default=".")
    a = ap.parse_args(argv)

    head = commit(a.home, a.rev)
    if head is None:
        say("VOID", "ревизия %s не разрешается — судить нечего" % a.rev, True)
        return 2
    base = commit(a.home, BOUNDARY)
    if base is None:
        say("VOID", "граница %s в клоне не разрешается (неглубокий клон?)"
            % BOUNDARY[:12], True)
        return 2

    now, old = records(a.home, head), records(a.home, base)
    bad, full = commands(a.home, head, now)
    was, was_full = commands(a.home, base, old)
    findings = []
    inherited = 0
    for path in now:
        extra = bad[path] - was.get(path, collections.Counter())
        inherited += sum(bad[path].values()) - sum(extra.values())
        findings += ["%s: %s" % (path, c) for c in sorted(extra.elements())]
    control = sum(sum(c.values()) for c in was.values()) + was_full
    say("CENSUS", "записей %d · команд дайджеста %d: с --full-index %d, "
        "без --full-index %d (унаследовано %d, новых %d) · граница %s: "
        "записей %d, команд %d" % (
            len(now), full + inherited + len(findings), full,
            inherited + len(findings), inherited, len(findings),
            base[:12], len(old), control))

    if not now:
        say("FAIL", "записей 0 на %s — обход пуст, о дереве не прочитано ничего"
            % head[:12], True)
        return 1
    if control == 0:
        say("FAIL", "положительный контроль: на границе не распознано ни одной "
            "команды дайджеста — распознаватель слеп к форме записей", True)
        return 1
    for f in findings:
        say("FAIL", "команда дайджеста без --full-index: " + f, True)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
