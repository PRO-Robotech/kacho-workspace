#!/usr/bin/env python3
"""Ритуалы потока скриптами, а не агентами: тело PR, закрытие волны, событие одобрения, trail.

ОСНОВАНИЕ — постановка задачи ws#930 (подзадача эпика ws#896), пересказом, а не
цитатой: ритуалы потока — записи, события, тела PR, закрытие волны, trail хранилища —
исполняются скриптами, а не агентами. Дословных слов владельца об этом в дереве нет. Входы — четыре обёртки рядом (`pr-body.sh`, `close-wave.sh`,
`approval-event.sh`, `vault-trails.sh`); вся логика — здесь, одна на всех.

ТРЕКЕР — ЧЕРЕЗ ОБЁРТКУ. Каждый вызов трекера идёт командой из `RITUAL_GH` (по умолчанию
`gh`) в форме `api --method <М> <путь> [--input -]`. Самопробы подставляют туда
двойника с файлом состояния и в сеть не ходят. Ответ, который не прочитан, — исход
«не выполнилось» (код 2), а не пустой список.

ДОКАЗАТЕЛЬСТВО DoD — комментарий задачи со строкой `DoD-proof @<ревизия>` в начале
строки (`git-issues.md#gi-closes-last-line`). Распознаватель — общий файл
`scripts/lib/dod_proof.jq`, тот же, что подключают `scripts/merge-readiness.sh` и
`scripts/cascade-census.sh --proof`; своего выражения здесь нет. Нет файла или `jq` —
судить нечем, код 2. Задача без доказательства закрывающей строки не получает: `Refs`,
а не `Closes`.

АТРИБУЦИЯ — предикатом хуков дерева `scripts/hooks/attribution-rule.sh` (функция
`attribution_line`), а не своей копией: два распознавателя одной нормы разъехались бы
молча. Нет предиката — судить нечем, код 2.

ИСХОДЫ у каждого ритуала: 0 — сделано; 1 — отказ (названа причина, необратимое не
выполнено, либо выполнено и названо, что осталось недоделанным); 2 — не выполнилось
(вход не прочитан, предпосылки нет).
"""

from __future__ import annotations

import datetime
import fnmatch
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ATTRIBUTION_RULE = os.path.join(HERE, "..", "hooks", "attribution-rule.sh")
DOD_LIB = os.path.join(HERE, "..", "lib")

OK, REFUSED, UNMET = 0, 1, 2

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
REPO_RE = re.compile(r"^[\w.-]+/[\w.-]+$")
EVENT_FIELDS = ("role", "verdict", "subject", "subject_revision", "subject_sha256")


class Unmet(Exception):
    """Вход не прочитан либо предпосылки нет — вердикта нет."""


class NotFound(Unmet):
    """Трекер ответил 404 «Not Found»: предмета по адресу нет — исход, а не «не прочитано».

    Форма — настоящая, gh 2.100.0 (замер 2026-10-18): тело `{"message":"Not Found",…,
    "status":"404"}` в stdout и код 1. Прочие отказы (403, 410, сеть, лимит) — `Unmet`:
    непрочитанный ответ за «номера нет» не выдаётся. Кто 404 не ждёт, ловит его как `Unmet`.
    """


class Refused(Exception):
    """Отказ: причина названа."""


def say(msg: str) -> None:
    print(msg, file=sys.stderr)


# ── трекер ──────────────────────────────────────────────────────────────────


def gh(method: str, path: str, body: dict | None = None):
    cmd = [os.environ.get("RITUAL_GH") or "gh", "api", "--method", method, path]
    data = None
    if body is not None:
        cmd += ["--input", "-"]
        data = json.dumps(body)
    try:
        p = subprocess.run(cmd, input=data, capture_output=True, text=True)
    except OSError as e:
        raise Unmet("трекер не вызывается (%s): %s" % (cmd[0], e))
    if p.returncode != 0:
        why = "трекер: %s %s — код %d: %s" % (method, path, p.returncode, (p.stderr or p.stdout).strip()[:300])
        try:
            got = json.loads(p.stdout)
        except ValueError:
            got = None
        if isinstance(got, dict) and got.get("message") == "Not Found" and str(got.get("status")) == "404":
            raise NotFound(why)
        raise Unmet(why)
    try:
        return json.loads(p.stdout) if p.stdout.strip() else None
    except ValueError:
        raise Unmet("трекер: %s %s — ответ не JSON" % (method, path))


def gh_list(path: str) -> list:
    out, page = [], 1
    sep = "&" if "?" in path else "?"
    while True:
        chunk = gh("GET", "%s%sper_page=100&page=%d" % (path, sep, page))
        if not isinstance(chunk, list):
            raise Unmet("трекер: %s — ожидался массив" % path)
        out += chunk
        if len(chunk) < 100:
            return out
        page += 1


def issue(repo: str, n: int) -> dict:
    got = gh("GET", "repos/%s/issues/%d" % (repo, n))
    if not isinstance(got, dict) or "state" not in got:
        raise Unmet("задача %s#%d не разобрана" % (repo, n))
    return got


_DOD_COMMENTS = ('include "dod_proof"; [.[] | {url: (.html_url // ""), revs: ((.body // "") | dod_proof_revisions)}'
                 ' | select(.revs | length > 0)]')


def _dod_query(repo: str, n: int, tail: str, rng: list | None = None):
    """Комментарии задачи через общий распознаватель `scripts/lib/dod_proof.jq` и хвост `tail`.

    `rng` — полные sha диапазона запроса (`$range` хвоста, привязка `dod_proof_bound`).
    """
    comments = gh_list("repos/%s/issues/%d/comments" % (repo, n))
    if not os.path.isfile(os.path.join(DOD_LIB, "dod_proof.jq")):
        raise Unmet("распознавателя доказательства DoD нет (%s) — судить нечем"
                    % os.path.normpath(os.path.join(DOD_LIB, "dod_proof.jq")))
    try:
        p = subprocess.run(["jq", "-L", DOD_LIB, "-c", "--argjson", "range", json.dumps(rng or []),
                            _DOD_COMMENTS + tail], input=json.dumps(comments),
                           capture_output=True, text=True)
    except OSError as e:
        raise Unmet("jq не вызывается: %s — доказательство DoD судить нечем" % e)
    if p.returncode != 0:
        raise Unmet("распознаватель доказательства DoD вышел кодом %d: %s" % (p.returncode, p.stderr.strip()[:200]))
    return json.loads(p.stdout or "null")


def dod_proof(repo: str, n: int):
    """(адрес комментария, ревизия) последнего доказательства DoD либо None.

    Распознаёт общий `scripts/lib/dod_proof.jq` — тот же, что у merge-readiness и
    cascade-census; ревизия — первая строка-доказательство последнего такого комментария.
    """
    got = _dod_query(repo, n, ' | last | if . == null then null else [.url, .revs[0]] end')
    return tuple(got) if got else None


def dod_proofs(repo: str, n: int, rng: list) -> list:
    """Все доказательства DoD задачи по порядку: [(адрес комментария, ревизия, привязана ли к диапазону)].

    Привязка — общая `dod_proof_bound` (`scripts/lib/dod_proof.jq`), та же, что у
    merge-readiness и landing-precheck (ws#1162); своей сверки с диапазоном здесь нет.
    """
    return [tuple(x) for x in _dod_query(repo, n, ' | [.[] | .url as $u | .revs[] | [$u, ., dod_proof_bound($range)]]',
                                         rng) or []]


def dod_partial(repo: str, n: int):
    """Ревизия последнего ЧАСТИЧНОГО доказательства (`dod_proof_partial_revisions`) либо None — для текста."""
    comments = gh_list("repos/%s/issues/%d/comments" % (repo, n))
    p = subprocess.run(["jq", "-L", DOD_LIB, "-r", 'include "dod_proof"; [.[] | (.body // "") | dod_proof_partial_revisions[]] | last // empty'],
                       input=json.dumps(comments), capture_output=True, text=True)
    return (p.stdout.strip() or None) if p.returncode == 0 else None


# ── атрибуция ───────────────────────────────────────────────────────────────


def attribution(text: str):
    """Строка атрибуции из текста либо None — предикатом хуков дерева."""
    if not os.path.isfile(ATTRIBUTION_RULE):
        raise Unmet("предиката атрибуции нет (%s) — судить нечем" % os.path.normpath(ATTRIBUTION_RULE))
    p = subprocess.run(
        ["bash", "-c", '. "$1" && attribution_line "$2"', "attribution", ATTRIBUTION_RULE, text],
        capture_output=True, text=True,
    )
    if p.returncode == 0:
        return p.stdout.strip() or "(пустая строка)"
    if p.returncode == 1:
        return None
    raise Unmet("предикат атрибуции вышел кодом %d: %s" % (p.returncode, p.stderr.strip()[:200]))


# ── git ─────────────────────────────────────────────────────────────────────


def git(*args: str, check: bool = True) -> str:
    root = os.environ.get("RITUAL_REPO_DIR") or os.getcwd()
    p = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True)
    if check and p.returncode != 0:
        raise Unmet("git %s: %s" % (" ".join(args), (p.stderr.strip() or "код %d" % p.returncode)[:300]))
    return p.stdout


# РЕПОЗИТОРИИ ВЛАДЕЛЬЦА, где ищется номер первой строки, которого нет в репозитории
# запроса (ws#1164): строки ведомости стволов `scripts/ci-read-expected.tsv` — тех, чьи
# запросы оснастка судит. Перечень выводится из неё, а не пишется здесь: задача ствола,
# заведённого без строки, разрешится в упоминание (без закрытия), а не в чужое Closes.
TRUNKS = os.path.join(HERE, "..", "ci-read-expected.tsv")


def sibling_repos(repo: str) -> list[str]:
    """Прочие репозитории владельца `repo` из ведомости стволов; ни одного — код 2."""
    path = os.path.normpath(TRUNKS)
    try:
        rows = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        raise Unmet("ведомость стволов %s не читается (%s) — номер другого репозитория разрешить не в чем" % (path, e))
    owner = repo.split("/", 1)[0].lower()
    got = sorted({r.split("\t", 1)[0].strip() for r in rows if r.strip() and not r.lstrip().startswith("#")})
    out = [r for r in got if REPO_RE.match(r) and r.split("/", 1)[0].lower() == owner and r.lower() != repo.lower()]
    if not out:
        raise Unmet("в ведомости стволов %s нет репозиториев владельца %s, кроме %s — номер другого репозитория "
                    "разрешить не в чем" % (path, owner, repo))
    return out


def need_repo(repo: str) -> str:
    if not REPO_RE.match(repo or ""):
        raise Unmet("репозиторий «%s» не в форме <владелец>/<имя>" % repo)
    return repo


# ── pr-body ─────────────────────────────────────────────────────────────────
#
# Тело PR выводится из git, а не пишется (ws#1146, решение владельца 2026-10-17).
# Каждое правило ниже — то, чем судят `scripts/landing-precheck.sh` (пункты (в), (ж)) и
# `scripts/merge-readiness.sh`, выведенное заранее:
#   * состав — каждый коммит `база..голова` назван своим sha (BODY-MISSING-COMMIT), по
#     полосам: слияния линии первого родителя головы, вложенные — уровнем ниже;
#   * `#N` — ТОЛЬКО номер из первой строки коммита диапазона (BODY-FOREIGN-TASK): тем же
#     выражением `NUM`, что у landing-precheck; задача своего репозитория, названная в первой
#     строке полной формой (`kaname#719`), — задача тоже и пишется полной формой
#     `<владелец>/<имя>#N` (её BODY-FOREIGN-TASK не судит, Closes судит пункт (ж)); прочие
#     номера — без `#`;
#   * `Closes` — задаче с доказательством DoD, чья ревизия — коммит диапазона (предок
#     головы, не предок базы; CLOSES-WITHOUT-PROOF), не частичным (`dod_proof.jq`), чья работа
#     не откачена в диапазоне (`Reverts`, ws#1320), и не держателю записи долга;
#   * закрывающие строки — последними (`git-issues.md#gi-closes-last-line`).

# Номер задачи так, как его судит landing-precheck (пункт (в), `NUM`): `#N` не после
# буквы, цифры, `_`, `/` и `#`. Одно выражение на обе стороны — иначе тело, собранное
# здесь, судилось бы иначе, чем там.
NUM_RE = re.compile(r"(?<![\w/#])#([0-9]+)\b")

# ВЕДОМОСТИ ДОЛГА — где запись держится задачей, и закрытая задача её роняет. Закрытый
# перечень: у каждой строки — судья, для которого закрытый держатель — находка (замер
# 2026-10-17 по origin/main kaname и kacho: `git grep` проверок состояния задачи).
# Поля: репозиторий ведомости · пути (образцы `fnmatch` от корня, `*` идёт и через `/`) · форма держателя (`{ref}` — ссылка на
# задачу в любой законной записи, `{n}` — голый номер, только задача того же репозитория) ·
# судья. Строка своего репозитория, не нашедшая на голове ни одного файла, — код 2:
# перечень разошёлся с деревом, и «держателей 0» было бы ложью.
DEBT_LEDGERS = (
    ("PRO-Robotech/kaname", (".github/scripts/newman-suite-debt.py",), r"{ref} — ",
     "newman-suite-debt.py: держатель записи (`HOLDER_RE`) жив — reconcile_holder_liveness"),
    ("PRO-Robotech/kaname", ("tests/newman/docs/RESULTS.md",), r"{ref}",
     "tools/knownfailingexpiry: запись прощения истекает с закрытием задачи"),
    ("PRO-Robotech/kacho", ("tests/newman/docs/RESULTS.md", "*/tests/newman/docs/RESULTS.md"), r"{ref}",
     "tools/knownfailingsubject: закрытая задача объявления — находка"),
    ("PRO-Robotech/kacho", ("tests/newman/cases/*.py", "*/tests/newman/cases/*.py"), r"#\s*verifies\b[^\n]*{ref}",
     "tools/knownfailingsubject: `# verifies` красного кейса"),
    ("PRO-Robotech/kacho", ("internal/repohygiene/foundationadoption_test.go",), r"\bIssue:\s*{n}\b",
     "internal/repohygiene LedgerRecordsWhoseIssueIsClosed"),
    ("PRO-Robotech/kacho", ("internal/repohygiene/subscriptionformreach.go",), r"\bSubscriptionFormTaker\s*=\s*{n}\b",
     "internal/repohygiene SubscriptionReachFindings"),
)


# ССЫЛКА НА ЗАДАЧУ — ОДНО правило на ритуалы (ws#1155): им ищутся и номера задач своего
# репозитория в тексте (`issue_refs`), и держатель записи долга (`task_ref_re`). До ws#1155
# правил было два, и они разошлись: `task_ref_re` засчитывал `OtherOrg/kacho#5` своей
# задачей (перед краткой формой не отсекался `/`), а `issue_refs` — нет; адрес с владельцем в
# нижнем регистре не засчитывал ни один, краткую форму в нижнем регистре — первый.
#
# Ссылка на задачу `<владелец>/<имя>#N` — одна из форм: полная `<владелец>/<имя>#N`, краткая
# `<имя>#N`, адрес `github.com/<владелец>/<имя>/issues/N` и голый `#N` (только где текст —
# свой репозиторий). Границы — по КЛАССУ знака, не по перечню чужих владельцев:
#   * перед владельцем полной формы и перед `github.com` — не знак имени (буква, цифра, `_`,
#     `.`, `-`): `xPRO-Robotech/…`, `x.github.com/…` — не ссылка;
#   * перед краткой — ещё и не `/`: `<любой владелец>/<имя>#N` — либо полная форма своего
#     владельца, либо задача ЧУЖОГО, и `<имя>#N` внутри неё своей не засчитывается;
#   * перед голым `#N` — не знак имени, не `/` и не `#` (как `NUM_RE` и `NUM` landing-precheck);
#   * после номера — не знак слова: `kacho#55`, `#5a` — не задача 5;
#   * владелец и имя — без регистра во ВСЕХ формах: трекер их регистр не различает.
def task_ref_pattern(trepo: str, n: int | None = None, bare: bool = True) -> str:
    """Выражение ссылки на задачу репозитория `trepo` (номер — группа 1); `n` — только этот номер."""
    owner, name = (re.escape(x) for x in trepo.split("/", 1))
    lead = [r"(?<![\w.-])(?i:%s/%s)#" % (owner, name),
            r"(?<![\w./-])(?i:%s)#" % name,
            r"(?<![\w.-])(?i:github\.com/%s/%s)/issues/" % (owner, name)]
    if bare:
        lead.append(r"(?<![\w/#])#")
    return r"(?:%s)(%s)(?!\w)" % ("|".join(lead), r"[0-9]+" if n is None else str(n))


def task_ref_re(trepo: str, n: int, lrepo: str) -> str:
    """Ссылка на задачу `trepo#n` в тексте ведомости репозитория `lrepo`: голый `#n` — только в своём."""
    return task_ref_pattern(trepo, n, bare=trepo.lower() == lrepo.lower())


def ledger_source(lrepo: str, trepo: str, head: str):
    """(каталог git, ревизия) ведомостей репозитория `lrepo` либо None — клона нет.

    Свой репозиторий — голова запроса (ведомость после вливания); чужой — `origin/main`
    клона `RITUAL_LEDGER_CLONES/<имя>` (по умолчанию `project/` воркспейса).
    """
    if lrepo == trepo:
        return os.environ.get("RITUAL_REPO_DIR") or os.getcwd(), head
    root = os.environ.get("RITUAL_LEDGER_CLONES")
    if not root:
        # Корень воркспейса — единственным выводом дерева (`scripts/lib/ws-home.sh`): из копии
        # под `tmp/` каталог над скриптом — копия, а клоны продуктов — в `project/` основной.
        w = subprocess.run(["bash", "-c", '. "$1" && ws_home "$2"', "ws-home",
                            os.path.join(HERE, "..", "lib", "ws-home.sh"), HERE], capture_output=True, text=True)
        root = os.path.join(w.stdout.strip() or os.path.join(HERE, "..", ".."), "project")
    d = os.path.join(root, lrepo.split("/", 1)[1])
    p = subprocess.run(["git", "-C", d, "rev-parse", "--verify", "-q", "origin/main^{commit}"],
                       capture_output=True, text=True)
    return (d, "origin/main") if p.returncode == 0 else None


def read_ledgers(trepo: str, head: str):
    """Тексты ведомостей долга: [(репо, путь, текст, форма, судья)] и перепись строками."""
    out, census, trees = [], [], {}
    for lrepo, specs, form, judge in DEBT_LEDGERS:
        src = ledger_source(lrepo, trepo, head)
        if src is None:
            census.append("ведомость %s %s — НЕ СВЕРЕНА: клона %s нет" % (lrepo, " ".join(specs), lrepo))
            continue
        d, rev = src
        if (d, rev) not in trees:
            p = subprocess.run(["git", "-C", d, "ls-tree", "-r", "--name-only", "-z", rev],
                               capture_output=True, text=True)
            if p.returncode != 0:
                raise Unmet("дерево %s на %s не перечислено: %s" % (lrepo, rev, p.stderr.strip()[:200]))
            trees[(d, rev)] = [f for f in p.stdout.split("\0") if f]
        files = [f for f in trees[(d, rev)] if any(fnmatch.fnmatchcase(f, s) for s in specs)]
        if not files and lrepo == trepo:
            raise Unmet("ведомость долга %s не найдена на голове — перечень DEBT_LEDGERS разошёлся с деревом; "
                        "«держателей 0» было бы ложью" % " ".join(specs))
        for f in files:
            q = subprocess.run(["git", "-C", d, "show", "%s:%s" % (rev, f)], capture_output=True)
            if q.returncode != 0:
                raise Unmet("ведомость %s:%s не прочитана на %s" % (lrepo, f, rev))
            out.append((lrepo, f, q.stdout.decode("utf-8", "replace"), form, judge))
        census.append("ведомость %s %s @%s: файлов %d" % (lrepo, " ".join(specs), rev[:12], len(files)))
    return out, census


def debt_holder(trepo: str, n: int, ledgers) -> str | None:
    """Первая запись ведомости долга, которую держит задача `trepo#n`: «репо:путь:строка» либо None."""
    for lrepo, f, text, form, _ in ledgers:
        if "{n}" in form and trepo != lrepo:
            continue
        rx = re.compile(form.replace("{ref}", task_ref_re(trepo, n, lrepo)).replace("{n}", str(n)))
        for i, line in enumerate(text.splitlines(), 1):
            if rx.search(line):
                return "%s:%s:%d" % (lrepo.split("/", 1)[1], f, i)
    return None


def issue_refs(repo: str, text: str) -> set[int]:
    """Номера задач ЭТОГО репозитория, названные в тексте любой законной формой (`task_ref_pattern`)."""
    return {int(m.group(1)) for m in re.finditer(task_ref_pattern(repo), text)}


def first_line(msg: str) -> str:
    """Первая СТРОКА сообщения — не `%s` git: тот склеивает первый абзац в одну строку."""
    return (msg.split("\n", 1)[0] if msg else "").rstrip("\r")


# ДОГОН — слияние базы (ствола либо ветки эпика) в ветку запроса: `#870 merge main: … (#856)`,
# `Merge branch 'main' …`, `слияние origin/main`, `#3258 merge 3172-…`. Признак — СТРУКТУРА, не
# текст (ws#1146, приёмка check-verifier на 2975fdd18): коммит-слияние, все сторонние родители
# которого достижимы из базы, — его ветвь в `lanes()` пуста. Перечень словесных форм не полон
# по построению (kaname — 49 таких строк, kacho — 22, воркспейс — 7), а обычный коммит со
# словами «merge main» слиянием не является. Номера строки догона, кроме префикса `#N` своей
# задачи, — номера базы, а не предмета запроса (kaname 870 @9d692d7fe дал `Refs #856`): в
# задачи и в упомянутые они не идут, в составе пишутся без `#`.
PREFIX_RE = re.compile(r"^#[0-9]+(?=\s)")


def is_ancestor(a: str, b: str) -> bool:
    root = os.environ.get("RITUAL_REPO_DIR") or os.getcwd()
    p = subprocess.run(["git", "-C", root, "merge-base", "--is-ancestor", a, b], capture_output=True, text=True)
    if p.returncode not in (0, 1):
        raise Unmet("git merge-base --is-ancestor %s %s: %s" % (a[:12], b[:12], p.stderr.strip()[:200]))
    return p.returncode == 0


def catch_up(parents: list[str], base: str) -> bool:
    """Догон базы: слияние, все сторонние родители которого достижимы из базы."""
    side = parents[1:]
    return bool(side) and all(is_ancestor(p, base) for p in side)


def judged(msg: str, catchup: bool) -> tuple[str, str, str]:
    """(строка состава, текст номеров задач, текст упоминаний) коммита.

    Обычный коммит — первая строка, первая строка, всё сообщение. Догон базы — номера
    берутся лишь из префикса `#N` своей задачи; прочие номера строки — без `#`.
    """
    line = first_line(msg)
    if not catchup:
        return line, line, msg
    m = PREFIX_RE.match(line)
    head = m.group(0) if m else ""
    return head + no_hash(line[len(head):]), head, head


def no_hash(text: str) -> str:
    """Номер, который судился бы как `#N`, — без `#` (заголовок задачи не из первых строк)."""
    return NUM_RE.sub(lambda m: "№" + m.group(1), text)


def rev_commit(rev: str) -> str:
    out = git("rev-parse", "--verify", "-q", "--end-of-options", rev + "^{commit}", check=False).strip()
    if not re.fullmatch(r"[0-9a-f]{40}", out):
        raise Unmet("ревизия «%s» не коммит в %s" % (rev, os.environ.get("RITUAL_REPO_DIR") or os.getcwd()))
    return out


# ОТКАТ РАБОТЫ В ДИАПАЗОНЕ (ws#1320). Доказательство привязано к коммиту диапазона, но работа
# могла быть откачена тем же диапазоном: kaname#881 — `DoD-proof @7292501e3` задачи #836,
# слияние полосы `5f4f2c041` обращено коммитом `8e621ca5a` («#853 revert merge 836»), правки в
# дереве головы нет, а тело давало `Closes #836`. Единица работы — коммит доказательства и
# каждое слияние диапазона, внёсшее его стороной (ревизия достижима из стороннего родителя и не
# из первого). Откат единицы X — коммит диапазона C после X, чей ОБРАТНЫЙ дифф равен диффу X по
# `git patch-id --stable` (слияние — к первому родителю, как `git revert -m 1`), либо чьё
# сообщение несёт строку git `This reverts [merge] commit <X>` (откат с разрешённым конфликтом
# дифф не повторяет). Откат не действует, если откачен сам (откат отката) либо X внесён заново
# после него коммитом того же диффа, который сам стоит (не откачен следом). Работа откачена —
# `Refs` с причиной, а не `Closes`.
REVERTS_RE = re.compile(r"^This reverts (?:merge )?commit ([0-9a-f]{7,40})\b", re.M)


def _patch_ids(span: str, reverse: bool) -> dict[str, str]:
    """Коммит диапазона → patch-id его диффа (`reverse` — диффа наоборот); пустой дифф не входит."""
    root = os.environ.get("RITUAL_REPO_DIR") or os.getcwd()
    lg = subprocess.run(["git", "-C", root, "log", "--no-color", "--no-ext-diff", "--no-textconv", "--no-prefix",
                         "-p", "--diff-merges=first-parent", *(["-R"] if reverse else []), "--format=commit %H", span],
                        capture_output=True)
    if lg.returncode != 0:
        raise Unmet("git log -p %s: %s" % (span, lg.stderr.decode(errors="replace").strip()[:300]))
    pid = subprocess.run(["git", "-C", root, "patch-id", "--stable"], input=lg.stdout, capture_output=True)
    if pid.returncode != 0:
        raise Unmet("git patch-id: %s" % pid.stderr.decode(errors="replace").strip()[:300])
    out = {}
    for ln in pid.stdout.decode().splitlines():
        p = ln.split()
        if len(p) == 2:
            out[p[1]] = p[0]
    return out


class Reverts:
    """Откаты единиц работы в диапазоне `база..голова`; считается один раз и лишь по запросу."""

    def __init__(self, base_sha: str, head_sha: str, meta: dict, msgs: dict):
        self.span, self.meta, self.msgs = "%s..%s" % (base_sha, head_sha), meta, msgs
        self.undoers = None

    def _load(self):
        fwd, rev = _patch_ids(self.span, False), _patch_ids(self.span, True)
        by_fwd: dict[str, list[str]] = {}
        for c, p in fwd.items():
            by_fwd.setdefault(p, []).append(c)
        self.fwd, self.by_fwd, self.undoers = fwd, by_fwd, {}
        for c in self.meta:
            cands = set(by_fwd.get(rev.get(c, ""), []))
            for m in REVERTS_RE.finditer(self.msgs[c]):
                x = git("rev-parse", "--verify", "-q", "--end-of-options", m.group(1) + "^{commit}", check=False).strip()
                if x in self.meta:
                    cands.add(x)
            for x in cands - {c}:
                if is_ancestor(x, c):
                    self.undoers.setdefault(x, []).append(c)

    def _stands(self, x: str) -> bool:
        """Изменение X стоит на голове: ни один его откат не действует."""
        return self._undone_by(x) is None

    def _undone_by(self, x: str):
        for c in self.undoers.get(x, []):
            again = [d for d in self.by_fwd.get(self.fwd.get(x, ""), [])
                     if d not in (x, c) and is_ancestor(c, d) and self._stands(d)]
            if self._stands(c) and not again:
                return c
        return None

    def undone(self, rev: str):
        """(откат, единица) — живой откат работы ревизии `rev` (полный sha коммита диапазона), либо None."""
        if self.undoers is None:
            self._load()
        for x in sorted(self.undoers):
            parents = self.meta[x][0]
            if x == rev or (len(parents) > 1 and not is_ancestor(rev, parents[0])
                            and any(is_ancestor(rev, p) for p in parents[1:])):
                c = self._undone_by(x)
                if c:
                    return c, x
        return None


def lanes(tip: str, excl: list[str], meta: dict) -> list:
    """Линия первого родителя `tip` за вычетом `excl`, старшим вперёд: [(sha, [ветви слияния])].

    Ветвь слияния — линия его стороннего родителя за вычетом первого родителя и сторонних,
    стоящих раньше; коммит, внесённый раньше по линии, вычтен первым родителем.
    """
    line = git("rev-list", "--first-parent", tip, *("^" + e for e in excl)).split()
    out = []
    for c in reversed(line):
        parents = meta[c][0]
        subs, seen = [], [parents[0]] if parents else []
        for p in parents[1:]:
            subs.append(lanes(p, excl + seen, meta))
            seen.append(p)
        out.append((c, subs))
    return out


def lane_lines(nodes: list, meta: dict, depth: int) -> tuple[list[str], int]:
    lines, n = [], 0
    for c, subs in nodes:
        mark = " (слияние)" if subs else ""
        lines.append("%s- `%s` %s%s" % ("  " * depth, c[:9], meta[c][1], mark))
        n += 1
        for s in subs:
            sl, sn = lane_lines(s, meta, depth + 1)
            lines += sl
            n += sn
    return lines, n


def pr_body(argv: list[str]) -> int:
    if len(argv) != 3:
        raise Unmet("usage: pr-body.sh <владелец/имя> <база> <голова>")
    repo, base, head = need_repo(argv[0]), argv[1], argv[2]
    base_sha, head_sha = rev_commit(base), rev_commit(head)
    span = "%s..%s" % (base, head)

    meta, order, msgs = {}, [], {}
    log = git("log", "--no-color", "--encoding=UTF-8", "--format=%H%x1f%P%x1f%B%x1e", "%s..%s" % (base_sha, head_sha))
    for rec in log.split("\x1e"):
        rec = rec.lstrip("\n")
        if rec:
            h, par, msg = rec.split("\x1f", 2)
            parents = par.split()
            meta[h] = (parents, *judged(msg, catch_up(parents, base_sha)))
            order.append(h)
            msgs[h] = msg
    if not meta:
        raise Unmet("в диапазоне %s коммитов ноль — тело собирать не из чего" % span)

    bad = ["%s «%s»" % (h[:10], line) for h in order for line in [attribution(msgs[h])] if line]
    if bad:
        raise Refused("атрибуция в сообщениях коммитов (%d) — тело не собрано; перепишите коммиты "
                      "без неё:\n  %s" % (len(bad), "\n  ".join(bad)))

    # Состав по полосам: слияния линии первого родителя головы.
    top = lanes(head_sha, [base_sha], meta)
    merges = [(c, subs) for c, subs in top if subs]
    direct = [(c, subs) for c, subs in top if not subs]
    lines = ["Состав `%s` — коммитов %d: полос (слияний первого родителя) %d, коммитов линии головы вне полос %d."
             % (span, len(meta), len(merges), len(direct)), ""]
    listed = 0
    for i, (c, subs) in enumerate(merges, 1):
        lines.append("### Полоса %d — `%s` %s" % (i, c[:9], meta[c][1]))
        lines.append("")
        listed += 1
        for s in subs:
            sl, sn = lane_lines(s, meta, 0)
            lines += sl
            listed += sn
        lines.append("")
    if direct:
        lines += ["### Линия головы вне полос", ""]
        for c, _ in direct:
            lines.append("- `%s` %s" % (c[:9], meta[c][1]))
            listed += 1
        lines.append("")
    if listed != len(meta):
        raise Unmet("разбиение по полосам назвало коммитов %d из %d диапазона %s — состав неполон"
                    % (listed, len(meta), span))

    # Номера: с `#` — только из первых строк; задача первой строки в полной форме — полной
    # формой; прочие упомянутые — без `#`.
    first = {int(x) for h in order for x in NUM_RE.findall(meta[h][2])}
    qual = set()
    for h in order:
        qual |= issue_refs(repo, meta[h][2])
    qual -= first
    mentioned = set()
    for h in order:
        mentioned |= issue_refs(repo, meta[h][3])
    mentioned -= first | qual

    home: dict[int, str] = {}      # номер первой строки → репозиторий задачи, когда он не `repo`
    orphans: dict[int, str] = {}   # номер первой строки без задачи ни в одном репозитории → почему

    def label(n: int) -> str:
        return "#%d" % n if n in first and n not in home else "%s#%d" % (home.get(n, repo), n)

    ledgers, census = read_ledgers(repo, head_sha)
    range_shas = list(meta)
    reverts = Reverts(base_sha, head_sha, meta, msgs)
    closes, refs, pulls, rows = [], [], [], []
    for n in sorted(first | qual):
        try:
            it = issue(repo, n)
        except NotFound:
            # Номера в репозитории запроса нет (404). Голый `#N` первой строки — ссылка на
            # задачу другого репозитория владельца (kacho-workspace PR приёмки kacho#3274):
            # он ищется в прочих стволах ведомости. Задача ровно одного — `Refs` полной формой:
            # закрывает её каскад своего репозитория, а не запрос чужого. Нигде либо в
            # нескольких — номер без задачи, без `#` и без закрытия. Отказ чтения кандидата
            # (не 404) — код 2: непрочитанное за «нет нигде» не выдаётся.
            if n in qual:
                orphans[n] = "в %s номера нет, а назван он полной формой этого репозитория" % repo
                continue
            cands = sibling_repos(repo)
            hits = []
            for c in cands:
                try:
                    got = issue(c, n)
                except NotFound:
                    continue
                if not got.get("pull_request"):
                    hits.append((c, got))
            if len(hits) == 1:
                home[n], got = hits[0]
                refs.append(n)
                rows.append("- %s «%s» — задача %s, не %s: `Refs`, закрывает её каскад своего репозитория"
                            % (label(n), no_hash(got.get("title") or ""), home[n], repo))
            elif hits:
                orphans[n] = "в нескольких: %s" % ", ".join(c for c, _ in hits)
            else:
                orphans[n] = "ни в одном из %s" % ", ".join([repo] + cands)
            continue
        if it.get("pull_request"):
            pulls.append(n)
            continue
        title = no_hash(it.get("title") or "")
        if it.get("state") != "open":
            refs.append(n)
            rows.append("- %s «%s» — уже закрыта: `Refs`" % (label(n), title))
            continue
        holder = debt_holder(repo, n, ledgers)
        if holder:
            refs.append(n)
            rows.append("- %s «%s» — держит запись долга `%s`: `Refs`, не `Closes`" % (label(n), title, holder))
            continue
        proofs = dod_proofs(repo, n, range_shas)
        inside = [(u, r) for u, r, bound in proofs if bound]
        undone = None
        if inside:
            full = next(s for s in range_shas if s.startswith(inside[-1][1]))
            undone = reverts.undone(full)
        if undone:
            refs.append(n)
            rows.append("- %s «%s» — `DoD-proof @%s`, но работа откачена в диапазоне: `%s` обращает `%s`: `Refs`, не `Closes`"
                        % (label(n), title, inside[-1][1], undone[0][:9], undone[1][:9]))
        elif inside:
            url, rev = inside[-1]
            closes.append(n)
            rows.append("- %s «%s» — доказательство DoD: %s (`DoD-proof @%s`, коммит диапазона)" % (label(n), title, url, rev))
        elif proofs:
            refs.append(n)
            rows.append("- %s «%s» — `DoD-proof @%s` не коммит диапазона `%s`: `Refs`, не `Closes`"
                        % (label(n), title, proofs[-1][1], span))
        elif dod_partial(repo, n):
            refs.append(n)
            rows.append("- %s «%s» — `DoD-proof @%s` частичный (пункт, не задача): `Refs`, не `Closes`"
                        % (label(n), title, dod_partial(repo, n)))
        else:
            refs.append(n)
            rows.append("- %s «%s» — доказательства DoD нет: `Refs`, не `Closes`" % (label(n), title))

    lines += ["Задачи первых строк (%d):" % len(rows), ""]
    lines += rows or ["- в первых строках коммитов номеров задач нет"]
    if pulls:
        lines += ["", "Запросы в первых строках (не задачи): %s" % ", ".join(label(n) for n in pulls)]
    if orphans:
        lines += ["", "Номера первых строк без задачи (без закрытия): %s"
                  % "; ".join("%d — %s" % (n, orphans[n]) for n in sorted(orphans))]
    if mentioned:
        lines += ["", "Упомянуты вне первых строк (без закрытия): %s" % ", ".join(str(n) for n in sorted(mentioned))]
    tail = ["Refs %s" % label(n) for n in refs] + ["Closes %s" % label(n) for n in closes]
    if tail:
        lines += [""] + tail
    body = "\n".join(lines) + "\n"

    line = attribution(body)
    if line:
        raise Refused("атрибуция в собранном теле: «%s» — тело не выдано" % line)
    sys.stdout.write(body)
    for c in census:
        say("pr-body: " + c)
    say("pr-body: коммитов %d (полос %d, вне полос %d), номеров первых строк %d — задач %d: Closes %d, Refs %d, "
        "из них полной формой %d; другого репозитория %d, без задачи %d; запросов %d; упомянуто без # %d"
        % (len(meta), len(merges), len(direct), len(first), len(rows), len(closes), len(refs),
           len(qual), len(home), len(orphans), len(pulls), len(mentioned)))
    return OK


# ── close-wave ──────────────────────────────────────────────────────────────


def close_wave(argv: list[str]) -> int:
    nxt = None
    if "--next" in argv:
        i = argv.index("--next")
        if i + 1 >= len(argv) or not argv[i + 1].isdigit():
            raise Unmet("--next требует номер следующей волны")
        nxt = int(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    if len(argv) != 3 or not argv[1].isdigit() or not re.match(r"^[0-9a-f]{7,40}$", argv[2]):
        raise Unmet("usage: close-wave.sh <владелец/имя> <волна> <sha вливания в ветку эпика> [--next <волна N+1>]")
    repo, wave, sha = need_repo(argv[0]), int(argv[1]), argv[2]

    w = issue(repo, wave)
    commit = gh("GET", "repos/%s/commits/%s" % (repo, sha))
    if not isinstance(commit, dict) or not commit.get("sha"):
        raise Unmet("коммит вливания %s в %s не найден" % (sha, repo))
    sha = commit["sha"]
    children = gh_list("repos/%s/issues/%d/sub_issues" % (repo, wave))
    if not children:
        raise Unmet("у волны %s#%d подзадач ноль — пустая волна не «открытых ноль»" % (repo, wave))

    to_close, remainder, already = [], [], 0
    for c in children:
        n = int(c.get("number"))
        if c.get("state") != "open":
            already += 1
            continue
        proof = dod_proof(repo, n)
        (to_close if proof else remainder).append((c, proof))

    if remainder and nxt is None:
        raise Unmet("остаток без доказательства DoD (%s), а следующая волна не названа (--next) — "
                    "ничего не изменено" % ", ".join("#%d" % c["number"] for c, _ in remainder))
    if remainder:
        nw = issue(repo, nxt)
        if nw.get("state") != "open":
            raise Refused("следующая волна #%d закрыта — остаток переносить некуда; ничего не изменено" % nxt)

    for c, proof in to_close:
        n = int(c["number"])
        gh("POST", "repos/%s/issues/%d/comments" % (repo, n), {"body": (
            "Закрыта вместе с волной #%d: её запрос влит в ветку эпика коммитом слияния `%s`.\n"
            "Доказательство DoD — %s (`DoD-proof @%s`)." % (wave, sha, proof[0], proof[1]))})
        gh("PATCH", "repos/%s/issues/%d" % (repo, n), {"state": "closed", "state_reason": "completed"})
    for c, _ in remainder:
        n = int(c["number"])
        gh("POST", "repos/%s/issues/%d/comments" % (repo, n), {"body": (
            "Остаток → волна #%d. Комментария-доказательства DoD (`DoD-proof @<ревизия>`) нет, поэтому "
            "задача не закрывается вместе с волной #%d (вливание `%s`) и переведена подзадачей в #%d."
            % (nxt, wave, sha, nxt))})
        gh("POST", "repos/%s/issues/%d/sub_issues" % (repo, nxt), {"sub_issue_id": c["id"], "replace_parent": True})

    if w.get("state") == "open":
        gh("POST", "repos/%s/issues/%d/comments" % (repo, wave), {"body": (
            "Волна закрыта: запрос влит в ветку эпика коммитом слияния `%s`. Закрыто задач %d, "
            "перенесено остатком%s %d, закрытых до этого %d."
            % (sha, len(to_close), (" в #%d" % nxt) if nxt else "", len(remainder), already))})
        gh("PATCH", "repos/%s/issues/%d" % (repo, wave), {"state": "closed", "state_reason": "completed"})

    after = gh_list("repos/%s/issues/%d/sub_issues" % (repo, wave))
    still = [c for c in after if c.get("state") == "open"]
    state = issue(repo, wave).get("state")
    say("close-wave: волна %s#%d — подзадач было %d; закрыто %d, перенесено %d, закрытых до этого %d; "
        "после: подзадач %d, открытых %d, волна %s"
        % (repo, wave, len(children), len(to_close), len(remainder), already, len(after), len(still), state))
    if still or state != "closed":
        raise Refused("у закрытой волны открытые подзадачи (%s) либо волна не закрыта (%s)"
                      % (", ".join("#%d" % c["number"] for c in still) or "—", state))
    return OK


# ── approval-event ──────────────────────────────────────────────────────────


def top_block(text: str, key: str):
    """(начало, конец) блока верхнего уровня `key:` в тексте YAML либо None."""
    m = re.search(r"(?m)^%s:.*\n?" % re.escape(key), text)
    if not m:
        return None
    end = re.compile(r"(?m)^(?=[^\s#\n])").search(text, m.end())
    return m.start(), (end.start() if end else len(text))


def yaml_load(text: str, where: str):
    try:
        import yaml
    except ImportError:
        raise Unmet("разборщика YAML нет (PyYAML) — запись не судится")
    try:
        doc = yaml.safe_load(text)
    except Exception as e:  # noqa: BLE001 — любой отказ разбора есть «запись не разобрана»
        raise Refused("%s не разбирается как YAML: %s" % (where, str(e).splitlines()[0]))
    if not isinstance(doc, dict):
        raise Refused("%s — не отображение YAML" % where)
    return doc


def q(v) -> str:
    """Скаляр YAML в двойных кавычках: значение ответа трекера с переводом строки или
    двоеточием не заведёт в записи нового ключа, а отпечаток из одних цифр не станет числом."""
    return json.dumps(str(v), ensure_ascii=False)


def event_block(posted: dict, url: str, actor: str, hrepo: str, hnum: int, role, verdict, body: str, want: str,
                revision: str) -> str:
    """Текст блока `event` записи по ответу трекера; каждое значение ответа — в кавычках."""
    return "\n".join([
        "event:",
        "  type: issue_comment",
        "  target: %s#%d" % (hrepo, hnum),
        "  status: performed",
        "  published: true",
        "  database_id: %s" % (posted["id"] if type(posted.get("id")) is int else q(posted.get("id") or "")),
        "  node_id: %s" % q(posted.get("node_id") or ""),
        "  url: %s" % q(url),
        "  api_url: %s" % q(posted.get("url") or ""),
        "  actor: %s" % q((posted.get("user") or {}).get("login") or actor),
        "  role: %s" % q(role),
        "  author_association: %s" % q(posted.get("author_association") or ""),
        "  created_at: %s" % q(posted.get("created_at") or ""),
        "  body_sha256: %s" % q(hashlib.sha256(body.encode("utf-8")).hexdigest()),
        "  subject_sha256: %s" % q(want),
        "  subject_revision_commit: %s" % q(revision),
        "  verdict: %s" % q(verdict),
        "  publication_mode: scripts/rituals/approval-event.sh",
        "",
    ])


def edited_record(before: str, rec: dict, record: str, event: str, url: str, issued_at: str) -> str:
    """Текст записи с блоком `event` и `effective_approval.issued: true`; отказ, если правка
    не дала события с адресом либо задела другие поля (границу блока ищет текстовый
    разбор, и многострочное значение другого поля способно её обмануть)."""
    span = top_block(before, "event")
    after = (before[:span[0]] + event + before[span[1]:]) if span else (before.rstrip("\n") + "\n\n" + event)
    ea = top_block(after, "effective_approval")
    if ea:
        blk = after[ea[0]:ea[1]]
        blk2 = re.sub(r"(?m)^  issued: false\s*$", "  issued: true", blk)
        if blk2 != blk and not re.search(r"(?m)^  issued_at:", blk2):
            stamp = "  issued: true\n  issued_at: %s" % q(issued_at)
            blk2 = re.sub(r"(?m)^  issued: true$", lambda _m: stamp, blk2, count=1)
        after = after[:ea[0]] + blk2 + after[ea[1]:]
    check = yaml_load(after, record + " (после правки)")
    cev = check.get("event") or {}
    if cev.get("status") != "performed" or cev.get("url") != url:
        raise Refused("правка блока event не дала status: performed с адресом события")
    drop = lambda d: {k: v for k, v in d.items() if k not in ("event", "effective_approval")}  # noqa: E731
    if drop(check) != drop(rec):
        raise Refused("правка блока event задела другие поля записи %s" % record)
    return after


# Ветка задачи — `<N>` (kaname) либо `<N>-…` (воркспейс, kacho): хук commit-msg таких
# веток требует первую строку «#<N> » с номером ветки (ws#941). Ведущий ноль — не номер.
BRANCH_TASK_RE = re.compile(r"^([1-9][0-9]*)(?:-|$)")


def branch_task() -> int:
    """Номер задачи из имени текущей ветки; ветки нет либо она не по форме — отказ."""
    p = subprocess.run(["git", "-C", os.environ.get("RITUAL_REPO_DIR") or os.getcwd(), "symbolic-ref", "-q",
                        "--short", "HEAD"], capture_output=True, text=True)
    branch = p.stdout.strip()
    if p.returncode != 0 or not branch:
        raise Refused("ветки нет (отсоединённая голова) — номера для первой строки коммита «#<N> review: …» "
                      "взять неоткуда; событие не публикуется")
    m = BRANCH_TASK_RE.match(branch)
    if not m:
        raise Refused("ветка «%s» не в форме <N> либо <N>-… — хук commit-msg отверг бы коммит записи без «#<N> »; "
                      "событие не публикуется" % branch)
    return int(m.group(1))


def approval_event(argv: list[str]) -> int:
    if len(argv) != 4:
        raise Unmet("usage: approval-event.sh <владелец/имя> <документ> <запись> <задача-держатель>")
    repo, doc, record, holder = need_repo(argv[0]), argv[1], argv[2], argv[3]
    m = re.match(r"^(?:([\w.-]+/[\w.-]+)#)?(\d+)$", holder)
    if not m:
        raise Unmet("держатель «%s» не в форме <N> либо <владелец/имя>#<N>" % holder)
    hrepo, hnum = (m.group(1) or repo), int(m.group(2))

    top = git("rev-parse", "--show-toplevel").strip()
    # Номер ветки — ДО публикации: иначе коммит записи отвергался бы уже после события.
    task = branch_task()
    rec_path = os.path.join(top, record)
    try:
        before = open(rec_path, encoding="utf-8").read()
    except OSError as e:
        raise Unmet("запись %s не читается: %s" % (record, e))
    rec = yaml_load(before, record)
    ev = rec.get("event") if isinstance(rec.get("event"), dict) else {}
    if ev.get("status") == "performed" or ev.get("published") is True:
        raise Refused("в записи %s событие уже исполнено (%s) — второе не публикуется" % (record, ev.get("url") or "адрес не назван"))
    verdict, role = rec.get("verdict"), rec.get("reviewer_role")
    subj = rec.get("subject") if isinstance(rec.get("subject"), dict) else {}
    want = subj.get("sha256")
    if not verdict or not role or want is None:
        raise Refused("в записи %s нет verdict, reviewer_role либо subject.sha256" % record)
    # Отпечаток из одних цифр YAML читает ЧИСЛОМ и теряет ведущие нули: сравнивать
    # было бы уже не то значение. Такая запись — отказ с причиной, а не «нет поля».
    if not isinstance(want, str) or not SHA256_RE.match(want):
        raise Refused("subject.sha256 записи %s — не строка из 64 шестнадцатеричных знаков (YAML прочёл %s %r); "
                      "заключите отпечаток в кавычки" % (record, type(want).__name__, want))
    if subj.get("path") and subj["path"] != doc:
        raise Refused("запись судит %s, а назван документ %s" % (subj["path"], doc))

    revision = git("rev-parse", "HEAD").strip()
    blob = subprocess.run(["git", "-C", top, "show", "HEAD:%s" % doc], capture_output=True)
    if blob.returncode != 0:
        raise Unmet("документа %s нет в HEAD" % doc)
    got = hashlib.sha256(blob.stdout).hexdigest()
    if got != want:
        raise Refused("отпечаток документа в HEAD %s… не равен subject.sha256 записи %s… — событие не о той редакции"
                      % (got[:12], want[:12]))
    if not git("branch", "-r", "--contains", revision).strip():
        raise Refused("ревизия %s не опубликована ни в одной удалённой ветке — событие ссылалось бы на "
                      "непроверяемую редакцию" % revision[:12])
    if not os.access(rec_path, os.W_OK):
        raise Refused("запись %s не записываема — событие без правки блока event не публикуется" % record)

    body = "\n".join([
        "role: %s" % role,
        "verdict: %s" % verdict,
        "subject: %s:%s" % (repo, doc),
        "subject_revision: %s" % revision,
        "subject_sha256: %s" % want,
        "",
        "---",
        "",
        "Событие полномочия к вердикту записи `%s`. Одобрена редакция с отпечатком выше, и только она." % record,
        "",
    ])
    line = attribution(body)
    if line:
        raise Refused("атрибуция в теле события: «%s»" % line)
    actor = (gh("GET", "user") or {}).get("login")
    if not actor:
        raise Unmet("учётка трекера не прочитана")

    # Правка записи проверяется ДО публикации на пробном ответе трекера: запись, блок
    # которой не правится без порчи других полей, события не получает вовсе — иначе
    # событие осталось бы опубликованным при записи, не приведённой к факту.
    probe_url = "https://github.com/%s/issues/%d#issuecomment-0" % (hrepo, hnum)
    try:
        edited_record(before, rec, record, event_block({"id": 0, "html_url": probe_url}, probe_url, actor, hrepo,
                                                       hnum, role, verdict, body, want, revision), probe_url, "")
    except Refused as e:
        raise Refused("%s — событие не публикуется" % e)

    posted = gh("POST", "repos/%s/issues/%d/comments" % (hrepo, hnum), {"body": body})
    url = (posted or {}).get("html_url")
    if not url:
        raise Unmet("ответ трекера о событии без адреса — опубликовано ли событие, неизвестно; сверьте задачу %s#%d" % (hrepo, hnum))

    try:
        after = edited_record(before, rec, record, event_block(posted, url, actor, hrepo, hnum, role, verdict,
                                                                 body, want, revision), url,
                              posted.get("created_at") or "")
        with open(rec_path, "w", encoding="utf-8") as fh:
            fh.write(after)
        git("add", "--", record)
        head = "#%d " % task
        msg = (head + "review: событие одобрения опубликовано — блок event записи к факту\n\n"
               "Запись %s, документ %s:%s (%s…), событие %s.\n" % (record, repo, doc, want[:12], url))
        if attribution(msg):
            raise Refused("атрибуция в сообщении коммита")
        git("commit", "-q", "-m", msg, "--", record)
        committed = yaml_load(git("show", "HEAD:%s" % record), record + " (HEAD)")
        if (committed.get("event") or {}).get("url") != url:
            raise Refused("в коммите HEAD блок event не несёт адреса события")
    except (Refused, Unmet, OSError) as e:
        raise Refused("СОБЫТИЕ ОПУБЛИКОВАНО (%s), а блок event записи %s к факту НЕ приведён: %s. "
                      "Приведите блок вручную тем же заходом — второе событие не публикуйте." % (url, record, e))
    say("approval-event: событие %s; запись %s — event.status performed, коммит %s"
        % (url, record, git("rev-parse", "--short", "HEAD").strip()))
    print(url)
    return OK


# ── vault-trails ────────────────────────────────────────────────────────────

VAULT_KAC = os.path.join("obsidian", "kacho", "KAC")
BEGIN, END = "<!-- ritual:closure -->", "<!-- /ritual:closure -->"


def trail_name(repo: str, n: int) -> tuple[str, str]:
    """(имя файла без .md, префикс заголовка) по раскладке каталога KAC."""
    name = repo.split("/")[1]
    if name == "kacho":
        return "issue-%d" % n, "#%d" % n
    if name == "kacho-workspace":
        return "issue-%d-ws" % n, "ws#%d" % n
    return "issue-%d-%s" % (n, name), "%s#%d" % (name, n)


def closing_facts(repo: str, n: int, it: dict):
    prs, sha = [], None
    for e in gh_list("repos/%s/issues/%d/timeline" % (repo, n)):
        if e.get("event") == "closed" and e.get("commit_id"):
            sha = e["commit_id"]
        src = (e.get("source") or {}).get("issue") or {}
        if e.get("event") == "cross-referenced" and src.get("pull_request") is not None and src.get("html_url"):
            if src["html_url"] not in prs:
                prs.append(src["html_url"])
    proof = dod_proof(repo, n)
    if not sha and proof:
        sha = proof[1]
    return prs, sha, proof


def closure_block(it: dict, prs: list, sha, proof, today: str) -> str:
    reason = it.get("state_reason") or "completed"
    rows = [
        BEGIN,
        "## Закрытие",
        "",
        "- состояние: закрыта %s (`%s`)" % ((it.get("closed_at") or "")[:10], reason),
        "- PR: %s" % (", ".join(prs) if prs else "в трекере не назван"),
        "- sha: %s" % (("`%s`" % sha) if sha else "не назван"),
        "- DoD: %s" % (("%s (`DoD-proof @%s`)" % proof) if proof else "комментария-доказательства DoD нет"),
        "",
        "Блок записан `scripts/rituals/vault-trails.sh` по трекеру %s; дерево продукта этой записью не сверялось." % today,
        END,
    ]
    return "\n".join(rows)


def vault_trails(argv: list[str]) -> int:
    if len(argv) < 2 or not all(a.isdigit() for a in argv[1:]):
        raise Unmet("usage: vault-trails.sh <владелец/имя> <закрытая задача>…")
    repo = need_repo(argv[0])
    root = os.environ.get("RITUAL_WS") or os.path.normpath(os.path.join(HERE, "..", ".."))
    kac = os.path.join(root, VAULT_KAC)
    if not os.path.isdir(kac):
        raise Unmet("каталога %s нет — писать trail некуда" % kac)
    today = datetime.date.today().isoformat()

    plan = []
    for a in argv[1:]:
        n = int(a)
        it = issue(repo, n)
        if it.get("pull_request"):
            raise Refused("%s#%d — запрос, а не задача" % (repo, n))
        if it.get("state") != "closed":
            raise Refused("%s#%d открыта — trail закрытия пишется закрытой задаче; ничего не записано" % (repo, n))
        plan.append((n, it) + closing_facts(repo, n, it))

    written = []
    for n, it, prs, sha, proof in plan:
        fname, prefix = trail_name(repo, n)
        path = os.path.join(kac, fname + ".md")
        status = "wontfix" if it.get("state_reason") == "not_planned" else "done"
        block = closure_block(it, prs, sha, proof, today)
        title = (it.get("title") or "").replace('"', "'")
        if not os.path.exists(path):
            prs_yaml = "\n".join("  - %s" % u for u in prs) if prs else None
            text = "\n".join([
                "---",
                "title: \"%s: %s\"" % (prefix, title),
                "aliases:",
                "  - %s" % fname,
                "ticket_id: %d" % n,
                "category: kac",
                "status: %s" % status,
                "type: %s" % ("fix" if any((lb.get("name") or "") == "bug" for lb in it.get("labels") or []) else "feature"),
                "repos:",
                "  - %s" % repo.split("/")[1],
                ("prs:\n" + prs_yaml) if prs_yaml else "prs: []",
                "issue_url: %s" % (it.get("html_url") or ""),
                "opened: %s" % (it.get("created_at") or "")[:10],
                "tags:",
                "  - kac",
                "verified_against: \"трекер %s: состояние задачи, PR, sha и комментарий-доказательство DoD — gh api; "
                "дерево продукта не сверялось\"" % today,
                "---",
                "",
                "# %s: %s" % (prefix, title),
                "",
                "## Что и зачем",
                "",
                "Предмет и DoD — в теле задачи: %s." % (it.get("html_url") or ""),
                "",
                block,
                "",
                "#kac",
                "",
            ])
        else:
            text = open(path, encoding="utf-8").read()
            fm = re.match(r"^---\n(.*?)\n---\n", text, re.S)
            if not fm:
                raise Refused("%s без frontmatter — оболочку не правлю вслепую" % path)
            head = re.sub(r"(?m)^status:.*$", "status: %s" % status, fm.group(1)) \
                if re.search(r"(?m)^status:", fm.group(1)) else fm.group(1) + "\nstatus: %s" % status
            for u in prs:
                if u in head:
                    continue
                if re.search(r"(?m)^prs:\s*\[\]\s*$", head):
                    head = re.sub(r"(?m)^prs:\s*\[\]\s*$", "prs:\n  - %s" % u, head)
                elif re.search(r"(?m)^prs:\s*$", head):
                    head = re.sub(r"(?m)^prs:\s*$", "prs:\n  - %s" % u, head, count=1)
                else:
                    head += "\nprs:\n  - %s" % u
            rest = text[fm.end():]
            if BEGIN in rest and END in rest:
                rest = rest[:rest.index(BEGIN)] + block + rest[rest.index(END) + len(END):]
            else:
                rest = rest.rstrip("\n") + "\n\n" + block + "\n"
            text = "---\n" + head + "\n---\n" + rest
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        written.append(os.path.relpath(path, root))

    env = dict(os.environ, VAULT_GATE_ROOT=root)
    gen = subprocess.run(["python3", os.path.join(root, "scripts", "vault-index", "generate.py")],
                         env=env, capture_output=True, text=True)
    if gen.returncode != 0:
        raise Refused("генератор указателя хранилища вышел кодом %d: %s" % (gen.returncode, gen.stderr.strip()[:300]))
    gate = subprocess.run(["bash", os.path.join(root, "scripts", "vault-gate", "run-all.sh")],
                          env=env, capture_output=True, text=True)
    sys.stderr.write(gate.stdout + gate.stderr)
    say("vault-trails: записано trail %d (%s); vault-gate код %d" % (len(written), ", ".join(written), gate.returncode))
    return gate.returncode if gate.returncode in (OK, REFUSED, UNMET) else REFUSED


COMMANDS = {"pr-body": pr_body, "close-wave": close_wave, "approval-event": approval_event, "vault-trails": vault_trails}


def main(argv: list[str]) -> int:
    if not argv or argv[0] not in COMMANDS:
        say("usage: rituals.py {%s} …" % "|".join(COMMANDS))
        return UNMET
    try:
        return COMMANDS[argv[0]](argv[1:])
    except Refused as e:
        say("%s: ОТКАЗ — %s" % (argv[0], e))
        return REFUSED
    except Unmet as e:
        say("%s: НЕ ВЫПОЛНИЛОСЬ — %s" % (argv[0], e))
        return UNMET


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
