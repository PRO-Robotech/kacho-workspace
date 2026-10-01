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
бы новой. Сведение ws#805 с веткой docfresh (ws#839) принесло 29 таких записей
(37 команд, все от 2026-09-22 при правиле от 2026-09-24), поэтому граница —
коммит этого слияния: на нём записи обеих линий, и только они.

ЛИНИИ ДО ПРАВИЛА. Граница одна, а линий, писавших записи до правила и
сходящихся с этой позже неё, может быть несколько (ws#822 и ws#824: записи от
2026-09-23, ws#775: от 2026-09-22 — при правиле от 2026-09-24). Двигать границу на каждое сведение
нельзя: ветки правили бы одну константу по-разному и конфликтовали бы при
сборке. Поэтому такие линии объявлены своими ВЕРШИНАМИ до правила
(`PRE_RULE_TIPS`), и запись в том же пути с той же командой на вершине из
истории HEAD унаследована так же, как с границы. Вершина, которая в клоне есть,
но вне истории HEAD, ещё не сошлась: она не судится и сосчитана в переписи.
Сведённая вершина судится:
- вершина, содержащая коммит правила (`RULE`) либо снятая не раньше его, знает
  правило — находка: перечень не прощает записей, снятых при правиле. Мерило —
  именно правило, а не граница: граница моложе правила, и вершина, снятая между
  ними, записи при правиле уже писала;
- вершина, с которой в HEAD не унаследовано ни одной команды сверх границы, —
  находка без предмета: её строку снимают вместе с предметом.
Строка перечня, не разрешающаяся в клоне, — без предмета (код 2) с её
координатой: опечатку строки гейт не отличает от клона без истории её линии, а
молча сосчитанная несошедшейся она жила бы вечно, и перечень был бы шире
предмета. Строка не полным sha (имя ветки, сокращение) — находка: имя движется
вместе с веткой, а сокращение с ростом клона становится неоднозначным (ws#818).

ЗАПИСИ ЧУЖОЙ ЛИНИИ ДО ПРАВИЛА (corelib#54). Запись, снятая до правила в
ДРУГОМ репозитории и перенесённая сюда побайтно, лежит здесь в новом пути, и ни
граница, ни вершины её не знают. Она признаётся унаследованной только по якорю —
строке `FOREIGN_ANCHORS`: путь здесь, репозиторий-источник, полный sha коммита в
нём, путь в нём. Признание — все условия сразу: клон источника найден
(`KACHO_HOME_<ИМЯ>` либо `project/<имя>`, опознание по origin); якорь в нём
есть и его содержит ссылка `refs/remotes/` либо `refs/tags/` — клон конвейера
несёт только опубликованное; якорь снят раньше коммита правила (мерило — то же,
что у вершин); файл на якоре в пути источника равен записи здесь по sha256. Тогда
команды записи на якоре унаследованы в её пути и только в нём. Иначе — находка с
координатой: якорь не полным sha, репозиторий не «владелец/имя», второй якорь у
записи, записи с якорем нет на ревизии, якорь в полном клоне не существует либо
не опубликован, снят не раньше правила, пути на якоре нет, sha256 не равен, и
якорь, которому прощать нечего сверх границы и вершин. Без якоря запись — новая,
как прежде. Клона источника нет, либо клон неглубокий и якоря не несёт, — якорь
судить нечем: запись отложена целиком (её команды ни наследство, ни находка) и
сосчитана «не судимо», код 2, если находок нет.

ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ. На границе записи несут команды без `--full-index`;
распознаватель, не увидевший там ни одной, слеп к форме, которой дерево пишет, —
это находка, а не «новых нарушений нет».

ЧЕГО НЕ УТВЕРЖДАЕТ. Дайджест, снятый в файл и захешированный отдельной командой,
либо иным хешем, не распознаётся. Цепочка `git diff … | <звено> | sha256sum` не
судится: ближайшее к хешу звено — не `git` (канонический набор
`git diff --raw --no-abbrev … | awk … | sort | sha256sum` — такой, его сокращение
держит `--no-abbrev`, а не `--full-index`); она видна в переписи числом «иных труб».
Вершина, которая в клоне есть, но так и не сведена ни в одну судимую ревизию,
не судится никогда: её несведённость видна только числом «не сошлись» в
переписи. Дата вершины и якоря — дата коммиттера, поставленная тем, кто
коммитил; подделку даты гейт не ловит. Что якорь — коммит, ВНЁСШИЙ запись в
источник, а не любой до правила с тем же содержимым, гейт не утверждает: довод
тот же — содержимое на якоре снято до правила.

Коды: 0 — записи прочитаны, контроль сошёлся, находок нет; 1 — находка (и
неразобранное звено, и вершина, знающая правило либо без предмета, и строка
перечня не полным sha, и якорь, не признанный либо без предмета), пустой обход
или слепой распознаватель; 2 — ревизия, граница, коммит правила или строка
перечня вершин в клоне не разрешаются, либо якорь судить нечем (клона источника
нет, клон неглубокий).
"""

import argparse
import collections
import hashlib
import os
import re
import subprocess
import sys

BOUNDARY = "e55b0e0ba76be2e1d899c0f069c6c970112e58bc"

# Коммит, которым правило ws#818 вошло в дерево. Вершина линии до правила
# обязана его не содержать и быть снятой раньше него.
RULE = "4e34df39e89458ee303f400ce9f623f5631315ed"

# Вершины линий, писавших записи до правила и сходящихся позже границы. Строка —
# полный sha: имя ветки движется, сокращение становится неоднозначным.
PRE_RULE_TIPS = (
    "cfbb53db6ddfb4017cbe7d138df24b808f1ccbd3",
    "42258def00d88929edd510793f32b55f70b50029",
    "7e08efb994cb78861491f82373fbea839d046abc",
)

# Записи ЧУЖОЙ линии до правила: снятые в другом репозитории до правила и
# перенесённые сюда побайтно. Строка — (путь записи здесь, репозиторий-источник
# `владелец/имя`, якорь — полный sha коммита в источнике, путь записи в
# источнике). Запись признаётся унаследованной только по якорю: он опубликован в
# клоне источника, снят раньше коммита правила, и файл на нём в том пути равен
# записи здесь по sha256.
FOREIGN_ANCHORS = (
    ("docs/changes/corelib-20/reviews/post-diff/go-style-reviewer/"
     "d05a397d0026fc6b875a00a2a1667a1b48858008328eba6ba34462f50eb5055c.yaml",
     "PRO-Robotech/corelib", "51ea0f106b7c21cdc5be26e0c1a3d79d81cf45c2",
     "docs/changes/corelib-20/reviews/post-diff/go-style-reviewer/"
     "d05a397d0026fc6b875a00a2a1667a1b48858008328eba6ba34462f50eb5055c.yaml"),
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
FULL_SHA = re.compile(r"[0-9a-f]{40}")
OWNER_NAME = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
# Якорь опубликован, если его содержит ссылка, которую несёт и клон конвейера.
PUBLISHED = ("refs/remotes/", "refs/tags/")


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
    не сошедшиеся, строки не полным sha, строки, не разрешающиеся в клоне).
    Мерило знания — коммит правила `rule`, а не граница."""
    good, knows, open_, malformed, lost = [], [], [], [], []
    for tip in PRE_RULE_TIPS:
        if not FULL_SHA.fullmatch(tip):
            malformed.append(tip)
            continue
        sha = commit(home, tip)
        if sha is None:
            lost.append(tip)
        elif not ancestor(home, sha, head):
            open_.append(tip)
        elif ancestor(home, rule, sha):
            knows.append((sha, "содержит коммит правила %s" % rule[:12]))
        elif stamp(home, sha) >= stamp(home, rule):
            knows.append((sha, "снята не раньше коммита правила %s" % rule[:12]))
        else:
            good.append(sha)
    return good, knows, open_, malformed, lost


def identity(path):
    """«владелец/имя» рабочей копии по её origin, либо None. Форма URL роли не
    играет: https, ssh (scp-подобная) и file:// дают один ответ."""
    rc, out = git(path, "remote", "get-url", "origin")
    url = out.decode().strip() if rc == 0 else ""
    if url.endswith(".git"):
        url = url[:-4]
    url = url.rstrip("/")
    if "/" not in url:
        return None
    head, name = url.rsplit("/", 1)
    owner = re.split(r"[:/]", head)[-1]
    return "%s/%s" % (owner, name) if owner and name else None


def source_clone(home, repo):
    """(корень клона, None) либо (None, причина). Кандидатов два, и обхода
    каталогов среди них нет: `KACHO_HOME_<ИМЯ>` и `project/<имя>` от корня. Клон
    опознаётся по origin, а не по имени каталога; причина перечисляет каждого
    отвергнутого кандидата."""
    name = repo.rsplit("/", 1)[-1]
    env = "KACHO_HOME_" + re.sub(r"[^A-Za-z0-9]", "_", name).upper()
    candidates = []
    if os.environ.get(env):
        candidates.append((os.environ[env], "$" + env))
    candidates.append((os.path.join(home, "project", name), "project/" + name))
    tried = []
    for path, whence in candidates:
        rc, top = git(path, "rev-parse", "--show-toplevel") if os.path.isdir(path) \
            else (1, b"")
        top = top.decode().strip()
        if rc != 0 or os.path.realpath(top) != os.path.realpath(path):
            tried.append("%s (%s) — корня рабочей копии там нет" % (path, whence))
            continue
        got = identity(top)
        if got is None:
            tried.append("%s (%s) — у копии нет origin, идентичность непроверяема"
                         % (path, whence))
        elif got.lower() != repo.lower():
            tried.append("%s (%s) — это копия %s, а не %s" % (path, whence, got, repo))
        else:
            return top, None
    return None, ("клон %s не найден [%s]; условие создаётся так: git clone "
                  "https://github.com/%s.git <путь> и %s=<путь>"
                  % (repo, "; ".join(tried), repo, env))


def blob_sha256(home, rev, path):
    """sha256 файла `path` на `rev`, либо None, если пути там нет."""
    rc, out = git(home, "cat-file", "blob", "%s:%s" % (rev, path))
    return hashlib.sha256(out).hexdigest() if rc == 0 else None


def foreign(home, head, rule, now):
    """Судит перечень FOREIGN_ANCHORS: (признанные [(путь, клон, якорь, путь в
    источнике)], находки [текст], без предмета {путь: причина}). Мерило даты —
    коммит правила, как у вершин линий до правила."""
    admitted, findings, void, seen = [], [], {}, set()
    clones = {}
    for row in FOREIGN_ANCHORS:
        if not (isinstance(row, tuple) and len(row) == 4
                and all(isinstance(f, str) for f in row)):
            findings.append("строка перечня FOREIGN_ANCHORS «%r» — не четыре поля "
                            "(путь здесь, репозиторий, якорь, путь в источнике)" % (row,))
            continue
        path, repo, sha, src = row
        if not FULL_SHA.fullmatch(sha):
            findings.append("строка перечня FOREIGN_ANCHORS «%s» — не полный sha: "
                            "сокращение с ростом клона становится неоднозначным, "
                            "имя движется вместе с веткой" % sha)
            continue
        if not OWNER_NAME.fullmatch(repo):
            findings.append("строка перечня FOREIGN_ANCHORS: репозиторий «%s» — не "
                            "«владелец/имя»" % repo)
            continue
        if path in seen:
            findings.append("перечень FOREIGN_ANCHORS: у записи %s второй якорь — "
                            "запись признаётся одним" % path)
            continue
        seen.add(path)
        if path not in now:
            findings.append("перечень FOREIGN_ANCHORS: записи с якорем нет на %s — "
                            "%s; строку снимают вместе с предметом" % (head[:12], path))
            continue
        if repo not in clones:
            clones[repo] = source_clone(home, repo)
        clone, why = clones[repo]
        if clone is None:
            void[path] = why
            continue
        at = commit(clone, sha)
        if at is None:
            if git(clone, "rev-parse", "--is-shallow-repository")[1].strip() == b"true":
                void[path] = ("клон %s неглубокий (%s) и якоря %s не несёт — отличить "
                              "несуществующий коммит от обрезанной истории нечем"
                              % (repo, clone, sha[:12]))
            else:
                findings.append("якорь %s записи %s в полном клоне источника не "
                                "существует (%s, %s)" % (sha, path, repo, clone))
            continue
        rc, refs = git(clone, "for-each-ref", "--count=1", "--contains", at,
                       "--format=%(refname)", *PUBLISHED)
        if rc != 0 or not refs.strip():
            findings.append("якорь %s записи %s не опубликован: его не содержит ни "
                            "одна ссылка %s клона %s — клон конвейера его не несёт"
                            % (sha[:12], path, " и ".join(PUBLISHED), repo))
            continue
        if stamp(clone, at) >= stamp(home, rule):
            findings.append("якорь %s записи %s снят не раньше коммита правила %s — "
                            "запись писалась при правиле и судится новой"
                            % (sha[:12], path, rule[:12]))
            continue
        theirs = blob_sha256(clone, at, src)
        if theirs is None:
            findings.append("в источнике %s на якоре пути %s нет — запись %s якорем "
                            "не признана" % (repo, src, path))
            continue
        mine = blob_sha256(home, head, path)
        if mine != theirs:
            findings.append("sha256 записи %s (%s) не равен sha256 записи в источнике "
                            "%s на якоре %s (%s) — перенос не побайтный либо запись "
                            "дописана" % (path, mine[:16], repo, sha[:12], theirs[:16]))
            continue
        admitted.append((path, clone, at, src))
    return admitted, findings, void


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

    # Строка перечня, не разрешающаяся в клоне, — без предмета: наследство с неё
    # судить нечем. Строка не полным sha — находка в самом дереве, от клона она
    # не зависит, и при ней код 1, а не 2: находка старше беспредметности.
    good, knows, open_, malformed, lost = tips(a.home, head, rule)
    for tip in lost:
        say("VOID", "вершина перечня PRE_RULE_TIPS %s в клоне не разрешается — "
            "опечатка строки либо клон без истории её линии: наследство с неё "
            "судить нечем" % tip, True)
    if lost and not malformed:
        return 2

    now, old = records(a.home, head), records(a.home, base)
    cur, was = commands(a.home, head, now), commands(a.home, base, old)

    # Наследство — граница и сведённые годные вершины, объединением по пути.
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

    # Записи чужой линии — поверх границы и вершин, только признанные якорем и
    # только в своём пути. Запись, чей якорь судить нечем (клона источника нет,
    # клон неглубокий), отложена целиком: её команды ни наследство, ни находка.
    tier_bad = {p: collections.Counter(c) for p, c in heir_bad.items()}
    tier_dark = {p: collections.Counter(c) for p, c in heir_dark.items()}
    admitted, stray, aside = foreign(a.home, head, rule, set(now))
    idle_anchor = []
    for path, clone, at, src in admitted:
        theirs = commands(clone, at, [src])
        gain = 0
        for mine, got, heir in ((cur.bad, theirs.bad, heir_bad),
                                (cur.unparsed, theirs.unparsed, heir_dark)):
            own = got[src] - heir.get(path, empty)
            gain += sum((mine[path] & own).values())
            heir[path] = heir.get(path, collections.Counter()) | got[src]
        if gain == 0:
            idle_anchor.append(path)

    def judge(bad_heir, dark_heir):
        findings, blind, inherited, held, put_bad, put_dark = [], [], 0, 0, 0, 0
        for path in now:
            if path in aside:
                put_bad += sum(cur.bad[path].values())
                put_dark += sum(cur.unparsed[path].values())
                continue
            extra = cur.bad[path] - bad_heir.get(path, empty)
            inherited += sum(cur.bad[path].values()) - sum(extra.values())
            findings += ["%s: %s" % (path, c) for c in sorted(extra.elements())]
            dark = cur.unparsed[path] - dark_heir.get(path, empty)
            held += sum(cur.unparsed[path].values()) - sum(dark.values())
            blind += ["%s: %s" % (path, c) for c in sorted(dark.elements())]
        return findings, blind, inherited, held, put_bad, put_dark

    findings, blind, inherited, held, put_bad, put_dark = judge(heir_bad, heir_dark)
    edge_only = judge(was.bad, was.unparsed)
    tier = judge(tier_bad, tier_dark)
    from_tips = tier[2] + tier[3] - edge_only[2] - edge_only[3]
    from_anchors = inherited + held - tier[2] - tier[3]
    control = sum(sum(c.values()) for c in was.bad.values()) + was.full
    digests = cur.full + inherited + len(findings) + put_bad
    say("CENSUS", "записей %d · команд дайджеста %d: с --full-index %d, "
        "без --full-index %d (унаследовано %d, новых %d%s) · труб в хеш %d: "
        "командой дайджеста %d, не разобрано %d (унаследовано %d, новых %d%s), "
        "иных труб %d · записей с трубой без команды дайджеста %d · граница %s: "
        "записей %d, команд %d · вершин линий до правила %d: в истории HEAD %d, "
        "не сошлись %d, унаследовано с них %d, строк не полным sha %d · якорей "
        "чужих линий %d: признано %d, не судимо %d, унаследовано с них %d" % (
            len(now), digests, cur.full, inherited + len(findings) + put_bad,
            inherited, len(findings),
            ", не судимо %d" % put_bad if put_bad else "",
            digests + held + len(blind) + put_dark + cur.other, digests,
            held + len(blind) + put_dark, held, len(blind),
            ", не судимо %d" % put_dark if put_dark else "",
            cur.other, cur.bare,
            base[:12], len(old), control, len(PRE_RULE_TIPS),
            len(good) + len(knows), len(open_), from_tips, len(malformed),
            len(FOREIGN_ANCHORS), len(admitted), len(aside), from_anchors))

    if not now:
        say("FAIL", "записей 0 на %s — обход пуст, о дереве не прочитано ничего"
            % head[:12], True)
        return 1
    if control == 0:
        say("FAIL", "положительный контроль: на границе не распознано ни одной "
            "команды дайджеста — распознаватель слеп к форме записей", True)
        return 1
    for tip in malformed:
        say("FAIL", "строка перечня PRE_RULE_TIPS «%s» — не полный sha: имя "
            "движется вместе с веткой, сокращение становится неоднозначным; "
            "вершину объявляют её полным sha" % tip, True)
    for sha, why in knows:
        say("FAIL", "вершина линии до правила %s знает правило ws#818 — %s: её "
            "записи судятся как новые, перечень PRE_RULE_TIPS не прощает "
            "записей, снятых при правиле" % (sha[:12], why), True)
    for sha in idle:
        say("FAIL", "вершина линии до правила %s без предмета: сведена в HEAD, а "
            "унаследовать с неё сверх границы нечего — строку PRE_RULE_TIPS "
            "снимают" % sha[:12], True)
    for f in stray:
        say("FAIL", f, True)
    for path in idle_anchor:
        say("FAIL", "якорь записи %s без предмета: прощать нечего — команд без "
            "--full-index сверх границы и вершин в ней нет; строку FOREIGN_ANCHORS "
            "снимают" % path, True)
    for f in findings:
        say("FAIL", "команда дайджеста без --full-index: " + f, True)
    for f in blind:
        say("FAIL", "команда дайджеста не разобрана распознавателем: " + f
            + " — форма вне наблюдения: распознаватель учат форме либо запись "
            "пишут разбираемой формой", True)
    for path, why in sorted(aside.items()):
        say("VOID", "якорь записи %s не судим — %s" % (path, why), True)
    if findings or blind or knows or idle or malformed or stray or idle_anchor:
        return 1
    return 2 if aside else 0


if __name__ == "__main__":
    sys.exit(main())
