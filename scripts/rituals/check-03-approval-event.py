#!/usr/bin/env python3
"""check-03 — `approval-event.sh` публикует событие одобрения и ТЕМ ЖЕ ВЫЗОВОМ приводит блок event к факту.

ЧТО УТВЕРЖДАЕТ (ws#930). Подставной репозиторий с удалённым (голый клон), документ
приёмки и запись ревью с `event.status: not_performed` и `effective_approval.issued:
false`; подставной трекер.
  * законный вход: ровно одно событие в задаче-держателе, его заголовок — пять полей
    формы дома (`role · verdict · subject · subject_revision · subject_sha256`, образец
    kaname#549, комментарий 5944671740) до первой `---`; запись в HEAD несёт
    `event.status: performed`, `published: true` и адрес события, `issued: true`; прочие
    поля записи не тронуты; коммит без атрибуции, подписан корнем песочницы;
  * близнец формы: записи без блока event блок дописывается;
  * повтор по записи с исполненным событием — отказ, второго события нет;
  * инъекция «событие без правки блока»: запись не записываема — отказ ДО публикации,
    событий 0; коммит отвергнут хуком — отказ кодом 1, напечатано «СОБЫТИЕ ОПУБЛИКОВАНО»
    с адресом, чтобы недоделанное не уехало молча;
  * отпечаток документа не равен записи либо ревизия не опубликована — отказ, событий 0.
Коды: 0 — пробы прошли; 1 — проба провалена; 2 — предпосылки нет.
"""
import hashlib
import os
import stat
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _probe as P  # noqa: E402

import yaml  # noqa: E402 — наличие проверено песочницей (иначе VOID)

R = "PRO-Robotech/rituals-probe"
DOC = "docs/acceptance/a.md"
TEXT = "# приёмка\n\nДано — Когда — Тогда.\n"
SHA = hashlib.sha256(TEXT.encode()).hexdigest()
REC = "docs/specs/reviews/a/%s.yaml" % SHA


def record(event=True, path=DOC, sha=SHA):
    out = ("schema_version: 1\nkind: acceptance_review\n# комментарий записи сохраняется\nsubject:\n"
           "  path: %s\n  sha256: %s\nverdict: APPROVED\nreviewer_role: acceptance-reviewer\n"
           "effective_approval:\n  issued: false\n  why: ждёт события\n" % (path, sha))
    if event:
        out += "event:\n  type: none\n  status: not_performed\n"
    return out + "checks:\n  coverage: 3 из 3\n"


def world():
    return {"issues": {"%s#549" % R: {"number": 549, "id": 1, "title": "держатель", "state": "open"}},
            "user": {"login": "pointpu"}}


def fixture(pr, name, rec_text, push=True):
    origin = os.path.join(pr.tmp, name + "-origin.git")
    pr.git(pr.tmp, "init", "-q", "--bare", origin)
    d = pr.repo(name, {DOC: TEXT, REC: rec_text})
    pr.git(d, "remote", "add", "origin", origin)
    if push:
        pr.git(d, "push", "-q", "origin", "main")
    return d


def posts(st):
    return [e for e in P.writes(st) if e["path"].endswith("/comments")]


def body(pr):
    d = fixture(pr, "ok", record())
    head0 = pr.git(d, "rev-parse", "HEAD").strip()
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d)
    pr.ok("законный вход: код 0", rc == 0, err)
    ev = posts(st)
    pr.ok("событие ровно одно, в задаче-держателе", len(ev) == 1 and ev[0]["path"] == "repos/%s/issues/549/comments" % R,
          str(ev))
    text = ev[0]["body"]["body"] if ev else ""
    header = text.split("\n---", 1)[0].splitlines()
    want = ["role: acceptance-reviewer", "verdict: APPROVED", "subject: %s:%s" % (R, DOC),
            "subject_revision: %s" % head0, "subject_sha256: %s" % SHA]
    pr.ok("заголовок — пять полей формы дома", [h for h in header if h] == want, text)
    url = st["comments"]["%s#549" % R][0]["html_url"] if ev else "?"
    committed = yaml.safe_load(pr.git(d, "show", "HEAD:" + REC))
    cev = committed.get("event") or {}
    pr.ok("в HEAD: status performed, published true, адрес события",
          cev.get("status") == "performed" and cev.get("published") is True and cev.get("url") == url, str(cev))
    pr.ok("в HEAD: issued true", (committed.get("effective_approval") or {}).get("issued") is True,
          str(committed.get("effective_approval")))
    orig = yaml.safe_load(record())
    keep = lambda r: {k: v for k, v in r.items() if k not in ("event", "effective_approval")}  # noqa: E731
    pr.ok("прочие поля записи не тронуты", keep(committed) == keep(orig))
    pr.ok("комментарий записи сохранён", "# комментарий записи сохраняется" in pr.git(d, "show", "HEAD:" + REC))
    msg = pr.git(d, "log", "-1", "--format=%B")
    pr.ok("коммит без атрибуции", "co-authored-by" not in msg.lower() and "claude" not in msg.lower(), msg)
    pr.ok("коммит подписан корнем песочницы", pr.git(d, "log", "-1", "--format=%an").strip() ==
          pr.git(d, "config", "--global", "--get", "user.name").strip())
    pr.ok("коммит трогает только запись", pr.git(d, "show", "--name-only", "--format=", "HEAD").split() == [REC])
    pr.ok("адрес события напечатан в stdout", out.strip() == url, out)

    rc, out, err, st2 = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(st), cwd=d)
    pr.ok("повтор: отказ кодом 1, второго события нет", rc == 1 and len(posts(st2)) == len(posts(st)), err)

    d2 = fixture(pr, "noblock", record(event=False))
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d2)
    cev = (yaml.safe_load(pr.git(d2, "show", "HEAD:" + REC)).get("event") or {})
    pr.ok("близнец: блока event не было — дописан", rc == 0 and cev.get("status") == "performed", err)

    # инъекция: событие без правки блока → отказ
    d3 = fixture(pr, "readonly", record())
    os.chmod(os.path.join(d3, REC), stat.S_IRUSR)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d3)
    pr.ok("запись не записываема: отказ до публикации, событий 0", rc == 1 and not posts(st), err)

    d4 = fixture(pr, "hook", record())
    hook = os.path.join(d4, ".git", "hooks", "commit-msg")
    open(hook, "w").write("#!/bin/sh\necho 'проба: коммит отвергнут' >&2\nexit 1\n")
    os.chmod(hook, 0o755)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d4)
    url4 = st["comments"]["%s#549" % R][0]["html_url"] if posts(st) else "?"
    pr.ok("коммит отвергнут: код 1", rc == 1, err)
    pr.ok("коммит отвергнут: напечатано «СОБЫТИЕ ОПУБЛИКОВАНО» с адресом", "СОБЫТИЕ ОПУБЛИКОВАНО" in err and url4 in err, err)

    d5 = fixture(pr, "fp", record(sha="0" * 64))
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d5)
    pr.ok("отпечаток не равен записи: отказ, событий 0", rc == 1 and not posts(st), err)

    d6 = fixture(pr, "unpub", record(), push=False)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d6)
    pr.ok("ревизия не опубликована: отказ, событий 0", rc == 1 and not posts(st), err)


if __name__ == "__main__":
    sys.exit(P.main("check-03-approval-event", body))
