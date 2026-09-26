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
вызов `git [глобальные опции] diff …`, чей вывод трубой уходит ПРЯМО в `sha256sum`
либо `shasum -a 256`; пробелы и переводы строк сводятся к одному пробелу, поэтому
команда, разнесённая по строкам YAML или абзаца, распознаётся так же. Инлайн-код
(`` ` ``) команду обрывает: `git diff --quiet …` и `git show … | sha256sum` в
соседних кавычках одной командой не являются.

ФОРМЫ ГЛОБАЛЬНОЙ ОПЦИИ перед `diff` — каждая доказана парой в `inject.sh`:
`-C`/`-c` со словом; `--опция` и `--опция=слово`; опции с ОТДЕЛЬНЫМ аргументом по
грамматике git 2.53 (`SEPARATE` ниже) со словом через пробел. Слово — путь,
заполнитель `<…>` с пробелами внутри (`-C <копия полосы>`, ws#827), часть в
двойных или одинарных кавычках с пробелами внутри, и их склейка.

НЕРАЗОБРАННОЕ ЗВЕНО — находка, а не молчание. Труба в хеш, чьё ближайшее звено
(от разделителя до трубы) после последнего слова `git` несёт слово `diff`, но
которую распознаватель не разобрал, — форма вне наблюдения: новая краснеет с
координатой и с `--full-index` тоже (судить её гейт не может), унаследованная с
границы в том же пути сосчитана. Перепись печатает все трубы в хеш: командой
дайджеста, неразобранных, иных — и записи с трубой, но без команды дайджеста.

ГРАНИЦА. Влитые записи не правятся: имя файла и есть их дайджест. Команда без
`--full-index`, стоявшая в ТОМ ЖЕ пути на `BOUNDARY` либо на сведённой вершине
линии до правила (ниже), унаследована; любая другая (новый путь или дописанная в
старый) — находка. Граница объявлена одним местом — константой ниже.

Граница — коммит, где СОШЛИСЬ линии, писавшие записи до правила: запись с
параллельной линии, снятая до ws#818, на прежней границе отсутствует и читалась
бы новой. Сведение 805 с веткой docfresh (ws#839) принесло 29 таких записей
(37 команд, все от 2026-09-22 при правиле от 2026-09-24), поэтому граница —
коммит этого слияния: на нём записи обеих линий, и только они.

ЛИНИИ ДО ПРАВИЛА. Граница одна, а линий, писавших записи до правила и
сходящихся с этой позже неё, может быть несколько (ws#822 и ws#824: записи от
2026-09-23 при правиле от 2026-09-24). Двигать границу на каждое сведение
нельзя: ветки правили бы одну константу по-разному и конфликтовали бы при
сборке. Поэтому такие линии объявлены своими ВЕРШИНАМИ до правила
(`PRE_RULE_TIPS`), и запись в том же пути с той же командой на вершине из
истории HEAD унаследована так же, как с границы. Вершина вне истории HEAD ещё не
сошлась: она не судится и сосчитана в переписи. Сведённая вершина судится:
- вершина, содержащая коммит правила (`RULE`) либо снятая не раньше его, знает
  правило — находка: перечень не прощает записей, снятых при правиле;
- вершина, с которой в HEAD не унаследовано ни одной команды сверх границы, —
  находка без предмета: её строку снимают вместе с предметом.

ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ. На границе записи несут команды без `--full-index`;
распознаватель, не увидевший там ни одной, слеп к форме, которой дерево пишет, —
это находка, а не «новых нарушений нет».

ЧЕГО НЕ УТВЕРЖДАЕТ. Дайджест, снятый в файл и захешированный отдельной командой,
либо иным хешем, не распознаётся. Цепочка `git diff … | <звено> | sha256sum` не
судится: ближайшее к хешу звено — не `git` (канонический набор
`git diff --raw --no-abbrev … | awk … | sort | sha256sum` — такой, его сокращение
держит `--no-abbrev`, а не `--full-index`); она видна в переписи числом «иных труб».
Вершина, так и не сведённая ни в одну судимую ревизию, не судится никогда: её
несведённость видна только числом «не сошлись» в переписи. Дата вершины —
дата коммиттера, поставленная тем, кто коммитил; подделку даты гейт не ловит.

Коды: 0 — записи прочитаны, контроль сошёлся, находок нет; 1 — находка (и
неразобранное звено, и вершина, знающая правило либо без предмета), пустой
обход или слепой распознаватель; 2 — ревизия, граница или коммит правила в
клоне не разрешаются.
"""

import argparse
import collections
import re
import subprocess
import sys

BOUNDARY = "e55b0e0ba76be2e1d899c0f069c6c970112e58bc"

# Коммит, которым правило ws#818 вошло в дерево. Вершина линии до правила
# обязана его не содержать и быть снятой раньше него.
RULE = "4e34df39e89458ee303f400ce9f623f5631315ed"

# Вершины линий, писавших записи до правила и сходящихся позже границы.
PRE_RULE_TIPS = (
    "cfbb53db6ddfb4017cbe7d138df24b808f1ccbd3",
    "42258def00d88929edd510793f32b55f70b50029",
)

# Аргумент — слово без `;`, тире, стрелки, инлайн-кода и трубы, не кончающееся
# двоеточием: иначе команда «тянулась» бы через прозу и ключи YAML до чужой трубы.
ARG = r"[^\s;—−→`|]*[^\s;—−→`|:]"
# Слово глобальной опции: заполнитель `<…>` и кавычки несут пробелы внутри, и
# длина каждой такой части ограничена — через прозу слово не растягивается.
WORD = (r"(?:<[^<>`|]{1,120}>|\"[^\"`|]{0,200}\"|'[^'`|]{0,200}'"
        r"|[^\s\"'<`|])+")
# Глобальные опции git с аргументом ОТДЕЛЬНЫМ словом (git 2.53, `git help git`):
# `git --git-dir <путь> diff` законна так же, как `--git-dir=<путь>`.
SEPARATE = r"--(?:git-dir|work-tree|namespace|config-env|attr-source)"
OPTION = (r"(?:-[Cc] +" + WORD + r"|" + SEPARATE + r" +" + WORD
          + r"|--[\w-]+(?:=" + WORD + r")?)")
DIGEST = re.compile(
    r"\bgit((?: +" + OPTION + r")*) +diff\b((?: +" + ARG + r")*)"
    r" *\| *(?:sha256sum|shasum +-a *256)\b"
)
# Любая труба в хеш — знаменатель переписи: разобранная командой дайджеста и нет.
HASH = re.compile(r"\| *(?:sha256sum|shasum +-a *256)\b")
# Звено кончается там же, где распознаватель обрывает команду.
LINK_START = re.compile(r"[|`;—−→]")
GIT = re.compile(r"\bgit\b")


def say(tag, text, err=False):
    (sys.stderr if err else sys.stdout).write("[%s] %s\n" % (tag, text))


def git(home, *args):
    out = subprocess.run(["git", "-C", home] + list(args),
                         capture_output=True, check=False)
    return out.returncode, out.stdout


def commit(home, rev):
    rc, out = git(home, "rev-parse", "--verify", "-q", rev + "^{commit}")
    return out.decode().strip() if rc == 0 else None


def ancestor(home, older, newer):
    return git(home, "merge-base", "--is-ancestor", older, newer)[0] == 0


def stamp(home, rev):
    """Дата коммиттера, секунды эпохи."""
    return int(git(home, "show", "-s", "--format=%ct", rev)[1].decode().strip())


def tips(home, head, rule):
    """Вершины линий до правила: (сведённые и годные, знающие правило с причиной,
    не сошедшиеся). Вершина, которой нет в клоне, в истории HEAD быть не может."""
    good, knows, open_ = [], [], []
    for tip in PRE_RULE_TIPS:
        sha = commit(home, tip)
        if sha is None or not ancestor(home, sha, head):
            open_.append(tip)
        elif ancestor(home, rule, sha):
            knows.append((sha, "содержит коммит правила %s" % rule[:12]))
        elif stamp(home, sha) >= stamp(home, rule):
            knows.append((sha, "снята не раньше коммита правила %s" % rule[:12]))
        else:
            good.append(sha)
    return good, knows, open_


def records(home, rev):
    rc, out = git(home, "ls-tree", "-r", "-z", "--name-only", rev, "--", "docs")
    paths = [p for p in out.decode("utf-8", "replace").split("\0") if p]
    return [p for p in paths if p.startswith("docs/changes/") or "/reviews/" in p]


Census = collections.namedtuple("Census", "bad full unparsed other bare")


def link(flat, at):
    """Звено перед трубой `at`, если в нём после последнего `git` есть `diff`."""
    head = flat[:at]
    cut = max((m.end() for m in LINK_START.finditer(head)), default=0)
    seg = head[cut:]
    gits = list(GIT.finditer(seg))
    if gits and "diff" in seg[gits[-1].start():].split():
        return seg[gits[-1].start():].strip()
    return None


def commands(home, rev, paths):
    """Перепись труб в хеш: {путь: Counter(команда без --full-index)}, число
    команд с ним, {путь: Counter(неразобранное звено git … diff)}, число иных
    труб и число записей с трубой, но без команды дайджеста."""
    feed = "".join("%s:%s\n" % (rev, p) for p in paths).encode()
    out = subprocess.run(["git", "-C", home, "cat-file", "--batch"], input=feed,
                         capture_output=True, check=True).stdout
    bad, unparsed, full, other, bare, pos = {}, {}, 0, 0, 0, 0
    for path in paths:
        end = out.index(b"\n", pos)
        size = int(out[pos:end].split()[2])
        text = out[end + 1:end + 1 + size].decode("utf-8", "replace")
        pos = end + 2 + size
        bad[path], unparsed[path] = collections.Counter(), collections.Counter()
        flat = " ".join(text.split())
        spans = []
        for m in DIGEST.finditer(flat):
            spans.append(m.span())
            if "--full-index" in m.group(2).split():
                full += 1
            else:
                bad[path][m.group(0)] += 1
        pipes = 0
        for h in HASH.finditer(flat):
            pipes += 1
            if any(a <= h.start() < b for a, b in spans):
                continue
            seg = link(flat, h.start())
            if seg is None:
                other += 1
            else:
                unparsed[path][seg + " | " + h.group(0)[1:].strip()] += 1
        bare += 1 if pipes and not spans else 0
    return Census(bad, full, unparsed, other, bare)


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

    rule = commit(a.home, RULE)
    if rule is None:
        say("VOID", "коммит правила %s в клоне не разрешается (неглубокий клон?)"
            % RULE[:12], True)
        return 2

    now, old = records(a.home, head), records(a.home, base)
    cur, was = commands(a.home, head, now), commands(a.home, base, old)

    # Наследство — граница и сведённые годные вершины, объединением по пути.
    good, knows, open_ = tips(a.home, head, rule)
    empty = collections.Counter()
    heir_bad = {p: collections.Counter(c) for p, c in was.bad.items()}
    heir_dark = {p: collections.Counter(c) for p, c in was.unparsed.items()}
    idle = []
    for sha in good:
        at = commands(a.home, sha, records(a.home, sha))
        gain = 0
        for mine, theirs, edge, heir in ((cur.bad, at.bad, was.bad, heir_bad),
                                         (cur.unparsed, at.unparsed,
                                          was.unparsed, heir_dark)):
            for path in now:
                own = theirs.get(path, empty) - edge.get(path, empty)
                gain += sum((mine[path] & own).values())
                heir[path] = heir.get(path, collections.Counter()) \
                    | theirs.get(path, empty)
        if gain == 0:
            idle.append(sha)

    def judge(bad_heir, dark_heir):
        findings, blind, inherited, held = [], [], 0, 0
        for path in now:
            extra = cur.bad[path] - bad_heir.get(path, empty)
            inherited += sum(cur.bad[path].values()) - sum(extra.values())
            findings += ["%s: %s" % (path, c) for c in sorted(extra.elements())]
            dark = cur.unparsed[path] - dark_heir.get(path, empty)
            held += sum(cur.unparsed[path].values()) - sum(dark.values())
            blind += ["%s: %s" % (path, c) for c in sorted(dark.elements())]
        return findings, blind, inherited, held

    findings, blind, inherited, held = judge(heir_bad, heir_dark)
    edge_only = judge(was.bad, was.unparsed)
    from_tips = inherited + held - edge_only[2] - edge_only[3]
    control = sum(sum(c.values()) for c in was.bad.values()) + was.full
    digests = cur.full + inherited + len(findings)
    say("CENSUS", "записей %d · команд дайджеста %d: с --full-index %d, "
        "без --full-index %d (унаследовано %d, новых %d) · труб в хеш %d: "
        "командой дайджеста %d, не разобрано %d (унаследовано %d, новых %d), "
        "иных труб %d · записей с трубой без команды дайджеста %d · граница %s: "
        "записей %d, команд %d · вершин линий до правила %d: в истории HEAD %d, "
        "не сошлись %d, унаследовано с них %d" % (
            len(now), digests, cur.full, inherited + len(findings), inherited,
            len(findings), digests + held + len(blind) + cur.other, digests,
            held + len(blind), held, len(blind), cur.other, cur.bare,
            base[:12], len(old), control, len(PRE_RULE_TIPS),
            len(good) + len(knows), len(open_), from_tips))

    if not now:
        say("FAIL", "записей 0 на %s — обход пуст, о дереве не прочитано ничего"
            % head[:12], True)
        return 1
    if control == 0:
        say("FAIL", "положительный контроль: на границе не распознано ни одной "
            "команды дайджеста — распознаватель слеп к форме записей", True)
        return 1
    for sha, why in knows:
        say("FAIL", "вершина линии до правила %s знает правило ws#818 — %s: её "
            "записи судятся как новые, перечень PRE_RULE_TIPS не прощает "
            "записей, снятых при правиле" % (sha[:12], why), True)
    for sha in idle:
        say("FAIL", "вершина линии до правила %s без предмета: сведена в HEAD, а "
            "унаследовать с неё сверх границы нечего — строку PRE_RULE_TIPS "
            "снимают" % sha[:12], True)
    for f in findings:
        say("FAIL", "команда дайджеста без --full-index: " + f, True)
    for f in blind:
        say("FAIL", "команда дайджеста не разобрана распознавателем: " + f
            + " — форма вне наблюдения: распознаватель учат форме либо запись "
            "пишут разбираемой формой", True)
    return 1 if findings or blind or knows or idle else 0


if __name__ == "__main__":
    sys.exit(main())
