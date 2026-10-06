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
        raise Unmet("трекер: %s %s — код %d: %s" % (method, path, p.returncode, (p.stderr or p.stdout).strip()[:300]))
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


def dod_proof(repo: str, n: int):
    """(адрес комментария, ревизия) последнего доказательства DoD либо None.

    Распознаёт общий `scripts/lib/dod_proof.jq` — тот же, что у merge-readiness и
    cascade-census; ревизия — первая строка-доказательство последнего такого комментария.
    """
    comments = gh_list("repos/%s/issues/%d/comments" % (repo, n))
    if not os.path.isfile(os.path.join(DOD_LIB, "dod_proof.jq")):
        raise Unmet("распознавателя доказательства DoD нет (%s) — судить нечем"
                    % os.path.normpath(os.path.join(DOD_LIB, "dod_proof.jq")))
    expr = ('include "dod_proof"; [.[] | {url: (.html_url // ""), revs: ((.body // "") | dod_proof_revisions)}'
            ' | select(.revs | length > 0)] | last | if . == null then null else [.url, .revs[0]] end')
    try:
        p = subprocess.run(["jq", "-L", DOD_LIB, "-c", expr], input=json.dumps(comments),
                           capture_output=True, text=True)
    except OSError as e:
        raise Unmet("jq не вызывается: %s — доказательство DoD судить нечем" % e)
    if p.returncode != 0:
        raise Unmet("распознаватель доказательства DoD вышел кодом %d: %s" % (p.returncode, p.stderr.strip()[:200]))
    got = json.loads(p.stdout or "null")
    return tuple(got) if got else None


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


def need_repo(repo: str) -> str:
    if not REPO_RE.match(repo or ""):
        raise Unmet("репозиторий «%s» не в форме <владелец>/<имя>" % repo)
    return repo


# ── pr-body ─────────────────────────────────────────────────────────────────


def issue_refs(repo: str, text: str) -> set[int]:
    """Номера задач ЭТОГО репозитория, названные в тексте.

    Формы: `#N` (не после буквы, цифры и `/`), `<владелец>/<имя>#N` и адрес
    `https://github.com/<владелец>/<имя>/issues/N` — две последние только своего
    репозитория. Ссылка на чужой репозиторий закрывающей строкой этого PR не станет.
    """
    nums: set[int] = set()
    for m in re.finditer(r"(?<![\w/])#(\d+)\b", text):
        nums.add(int(m.group(1)))
    own = re.escape(repo)
    for m in re.finditer(r"(?<![\w.-])%s#(\d+)\b" % own, text):
        nums.add(int(m.group(1)))
    for m in re.finditer(r"https://github\.com/%s/issues/(\d+)\b" % own, text):
        nums.add(int(m.group(1)))
    return nums


def pr_body(argv: list[str]) -> int:
    if len(argv) == 2:
        repo, pr = need_repo(argv[0]), argv[1]
        if not pr.isdigit():
            raise Unmet("номер PR «%s» не число" % pr)
        meta = gh("GET", "repos/%s/pulls/%s" % (repo, pr))
        branch = ((meta or {}).get("head") or {}).get("ref") or ""
        base = ((meta or {}).get("base") or {}).get("ref") or ""
        span = "%s..%s" % (base, branch)
        commits = [(c.get("sha") or "", ((c.get("commit") or {}).get("message") or ""))
                   for c in gh_list("repos/%s/pulls/%s/commits" % (repo, pr))]
    elif len(argv) == 4:
        repo, branch, base, head = need_repo(argv[0]), argv[1], argv[2], argv[3]
        span = "%s..%s" % (base, head)
        log = git("log", "--reverse", "--no-color", "--encoding=UTF-8", "--format=%H%x1f%B%x1e", span)
        commits = []
        for rec in log.split("\x1e"):
            rec = rec.lstrip("\n")
            if rec:
                h, _, msg = rec.partition("\x1f")
                commits.append((h, msg))
    else:
        raise Unmet("usage: pr-body.sh <владелец/имя> <PR> | <владелец/имя> <ветка> <база> <голова>")

    if not commits:
        raise Unmet("в диапазоне %s коммитов ноль — тело собирать не из чего" % span)

    bad = []
    for h, msg in commits:
        line = attribution(msg)
        if line:
            bad.append("%s «%s»" % (h[:10], line))
    if bad:
        raise Refused("атрибуция в сообщениях коммитов (%d) — тело не собрано; перепишите коммиты "
                      "без неё:\n  %s" % (len(bad), "\n  ".join(bad)))

    nums: set[int] = set()
    m = re.match(r"^(\d+)-", branch)
    if m:
        nums.add(int(m.group(1)))
    for _, msg in commits:
        nums |= issue_refs(repo, msg)

    closes, refs, pulls, rows = [], [], [], []
    for n in sorted(nums):
        it = issue(repo, n)
        if it.get("pull_request"):
            pulls.append(n)
            continue
        title = it.get("title") or ""
        if it.get("state") != "open":
            refs.append(n)
            rows.append("- #%d «%s» — уже закрыта: `Refs`" % (n, title))
            continue
        proof = dod_proof(repo, n)
        if proof:
            closes.append(n)
            rows.append("- #%d «%s» — доказательство DoD: %s (`DoD-proof @%s`)" % (n, title, proof[0], proof[1]))
        else:
            refs.append(n)
            rows.append("- #%d «%s» — доказательства DoD нет: `Refs`, не `Closes`" % (n, title))

    lines = ["Коммиты `%s` (%d):" % (span, len(commits)), ""]
    for h, msg in commits:
        lines.append("- `%s` %s" % (h[:9], (msg.strip().splitlines() or [""])[0]))
    lines += ["", "Задачи (%d):" % len(rows), ""]
    lines += rows or ["- задач в коммитах и имени ветки не названо"]
    tail = ["Refs #%d" % n for n in refs] + ["Closes #%d" % n for n in closes]
    if tail:
        lines += [""] + tail
    body = "\n".join(lines) + "\n"

    line = attribution(body)
    if line:
        raise Refused("атрибуция в собранном теле: «%s» — тело не выдано" % line)
    sys.stdout.write(body)
    say("pr-body: коммитов %d, задач %d — Closes %d, Refs %d; номеров-PR пропущено %d"
        % (len(commits), len(rows), len(closes), len(refs), len(pulls)))
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


def approval_event(argv: list[str]) -> int:
    if len(argv) != 4:
        raise Unmet("usage: approval-event.sh <владелец/имя> <документ> <запись> <задача-держатель>")
    repo, doc, record, holder = need_repo(argv[0]), argv[1], argv[2], argv[3]
    m = re.match(r"^(?:([\w.-]+/[\w.-]+)#)?(\d+)$", holder)
    if not m:
        raise Unmet("держатель «%s» не в форме <N> либо <владелец/имя>#<N>" % holder)
    hrepo, hnum = (m.group(1) or repo), int(m.group(2))

    top = git("rev-parse", "--show-toplevel").strip()
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
        msg = ("review: событие одобрения опубликовано — блок event записи к факту\n\n"
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
