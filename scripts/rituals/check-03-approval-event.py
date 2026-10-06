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
  * в записи нет `verdict` либо `reviewer_role` — отказ, событий 0 (событие с
    `verdict: None` не публикуется);
  * отпечаток документа не равен записи, отпечаток из одних цифр без кавычек (YAML
    читает его числом), запись судит другой документ, ревизия не опубликована — отказ,
    событий 0;
  * повтор судится на ОПУБЛИКОВАННОЙ ревизии (коммит ритуала отправлен), чтобы отказ
    пришёл от запрета повтора, а не от «ревизия не опубликована»;
  * многострочное значение другого поля обманывает текстовую границу блока event —
    правка проверяется ДО публикации: отказ, событий 0, запись не тронута;
  * правка, задевшая другое поле записи, — отказ «задела другие поля»: блок event с
    лишним ключом верхнего уровня подаётся в `edited_record` ритуала ПРОВЕРЯЕМОГО дерева
    (в настоящем пути значения ответа трекера в кавычках, и такой блок не собрать —
    поэтому сама сверка доказывается прямым входом, а кавычки — пробой ниже);
  * ответ трекера с переводом строки в поле не заводит в записи нового ключа;
  * первая строка коммита ритуала — «#<N> review: …», N из имени ветки (ws#941): ветка
    `526` → `#526`, ветка `896-x` → `#896`, ветка `896-r8-526` → `#896` (число до первого
    дефиса, а не последнее), и такой коммит проходит хук, требующий префикс номера
    ветки; ветка не по форме (`main`, `896x`, `x-896`, `0526`,
    отсоединённая голова) — отказ ДО публикации, событий 0, запись и HEAD не тронуты;
  * ветка берётся из рабочей копии `RITUAL_REPO_DIR`, а не из каталога запуска: cwd на
    ветке `777-other`, переменная — на `896-r8` → `#896`, копия cwd не тронута.
Каждый отказ судится по коду И по причине в выводе: красное от соседнего отказа пробу
не проходит (возврат check-verifier к ws#930).
Коды: 0 — пробы прошли; 1 — проба провалена; 2 — предпосылки нет.
"""
import hashlib
import importlib.util
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


def record(event=True, path=DOC, sha=SHA, quoted=True, note="", drop=()):
    out = ("schema_version: 1\nkind: acceptance_review\n# комментарий записи сохраняется\n%ssubject:\n"
           "  path: %s\n  sha256: %s\nverdict: APPROVED\nreviewer_role: acceptance-reviewer\n"
           "effective_approval:\n  issued: false\n  why: ждёт события\n"
           % (note, path, ('"%s"' % sha) if quoted else sha))
    for key in drop:
        out = "".join(ln for ln in out.splitlines(True) if not ln.startswith(key + ":"))
    if event:
        out += "event:\n  type: none\n  status: not_performed\n"
    return out + "checks:\n  coverage: 3 из 3\n"


def world():
    return {"issues": {"%s#549" % R: {"number": 549, "id": 1, "title": "держатель", "state": "open"}},
            "user": {"login": "pointpu"}}


def fixture(pr, name, rec_text, push=True, branch="526"):
    origin = os.path.join(pr.tmp, name + "-origin.git")
    pr.git(pr.tmp, "init", "-q", "--bare", origin)
    d = pr.repo(name, {DOC: TEXT, REC: rec_text}, branch=branch)
    pr.git(d, "remote", "add", "origin", origin)
    if push:
        pr.git(d, "push", "-q", "origin", "HEAD")
    return d


# Хук коммита веток вида <N> и <N>-…: первая строка обязана начинаться с «#<N> », где N —
# номер ветки (форма хука kaname `scripts/hooks/commit-msg`, правило ws для веток задач).
PREFIX_HOOK = """#!/bin/sh
b=$(git symbolic-ref -q --short HEAD) || { echo 'проба: ветки нет' >&2; exit 1; }
n=$(printf '%s' "$b" | sed -n 's/^\\([0-9][0-9]*\\)\\(-.*\\)\\{0,1\\}$/\\1/p')
[ -n "$n" ] || { echo "проба: ветка $b без номера" >&2; exit 1; }
head -n 1 "$1" | grep -q "^#$n " || { echo "проба: первая строка не начинается с #$n" >&2; exit 1; }
"""


def prefix_hook(d):
    hook = os.path.join(d, ".git", "hooks", "commit-msg")
    open(hook, "w").write(PREFIX_HOOK)
    os.chmod(hook, 0o755)


def subject_line(pr, d):
    return pr.git(d, "log", "-1", "--format=%s").strip()


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
    pr.ok("ветка 526: первая строка — «#526 review: …»", subject_line(pr, d).startswith("#526 review: "),
          subject_line(pr, d))
    pr.ok("коммит подписан корнем песочницы", pr.git(d, "log", "-1", "--format=%an").strip() ==
          pr.git(d, "config", "--global", "--get", "user.name").strip())
    pr.ok("коммит трогает только запись", pr.git(d, "show", "--name-only", "--format=", "HEAD").split() == [REC])
    pr.ok("адрес события напечатан в stdout", out.strip() == url, out)

    pr.git(d, "push", "-q", "origin", "HEAD")
    rc, out, err, st2 = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(st), cwd=d)
    pr.refused("повтор", rc, err, "событие уже исполнено")
    pr.ok("повтор: второго события нет", len(posts(st2)) == len(posts(st)), str(posts(st2)))

    # ветка <N>-…: номер берётся до первого дефиса, коммит проходит хук, требующий «#<N> »
    db = fixture(pr, "branch-dash", record(), branch="896-x")
    prefix_hook(db)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=db)
    pr.ok("ветка 896-x: код 0 под хуком префикса", rc == 0, err)
    pr.ok("ветка 896-x: первая строка — «#896 review: …»", subject_line(pr, db).startswith("#896 review: "),
          subject_line(pr, db))
    cev = (yaml.safe_load(pr.git(db, "show", "HEAD:" + REC)).get("event") or {})
    pr.ok("ветка 896-x: блок event в HEAD к факту", cev.get("status") == "performed", str(cev))

    # ветка <N>-…<цифры>: номер — число ДО первого дефиса, а не последнее число имени
    # (реальные ветки `896-f6b-r8-526`, `2915-n12-fixture-sources`; возврат landing-reviewer, E7)
    dm = fixture(pr, "branch-multi", record(), branch="896-r8-526")
    prefix_hook(dm)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=dm)
    pr.ok("ветка 896-r8-526: код 0 под хуком префикса", rc == 0, err)
    pr.ok("ветка 896-r8-526: первая строка — «#896 review: …»", subject_line(pr, dm).startswith("#896 review: "),
          subject_line(pr, dm))

    # RITUAL_REPO_DIR сильнее cwd: ветка берётся из рабочей копии переменной, а не из каталога
    # запуска (cwd — другая рабочая копия на ветке с другим номером; возврат landing-reviewer, E8)
    dr = fixture(pr, "repo-dir", record(), branch="896-r8")
    prefix_hook(dr)
    dc = fixture(pr, "repo-dir-cwd", record(), branch="777-other")
    head_c = pr.git(dc, "rev-parse", "HEAD").strip()
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=dc,
                              extra={"RITUAL_REPO_DIR": dr})
    pr.ok("RITUAL_REPO_DIR ≠ cwd: код 0", rc == 0, err)
    pr.ok("RITUAL_REPO_DIR ≠ cwd: первая строка — «#896 review: …» (номер ветки переменной, не cwd)",
          subject_line(pr, dr).startswith("#896 review: "), subject_line(pr, dr))
    pr.ok("RITUAL_REPO_DIR ≠ cwd: рабочая копия cwd не тронута", pr.git(dc, "rev-parse", "HEAD").strip() == head_c
          and open(os.path.join(dc, REC), encoding="utf-8").read() == record())

    # ветка не по форме — отказ ДО публикации: событий 0, запись и HEAD не тронуты
    for label, br in (("без номера", "main"), ("номер без дефиса", "896x"), ("номер не в начале", "x-896"),
                      ("номер с ведущим нулём", "0526")):
        dn = fixture(pr, "branch-" + br, record(), branch=br)
        head0 = pr.git(dn, "rev-parse", "HEAD").strip()
        rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=dn)
        pr.refused("ветка %s («%s»)" % (label, br), rc, err, "не в форме <N> либо <N>-…")
        pr.ok("ветка %s: событий 0, HEAD и запись не тронуты" % label,
              not posts(st) and pr.git(dn, "rev-parse", "HEAD").strip() == head0
              and open(os.path.join(dn, REC), encoding="utf-8").read() == record(), str(posts(st)))
    dd = fixture(pr, "detached", record())
    pr.git(dd, "checkout", "-q", "--detach")
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=dd)
    pr.refused("отсоединённая голова", rc, err, "ветки нет")
    pr.ok("отсоединённая голова: событий 0", not posts(st), str(posts(st)))

    d2 = fixture(pr, "noblock", record(event=False))
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d2)
    cev = (yaml.safe_load(pr.git(d2, "show", "HEAD:" + REC)).get("event") or {})
    pr.ok("близнец: блока event не было — дописан", rc == 0 and cev.get("status") == "performed", err)

    # инъекция: событие без правки блока → отказ
    d3 = fixture(pr, "readonly", record())
    os.chmod(os.path.join(d3, REC), stat.S_IRUSR)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d3)
    pr.refused("запись не записываема", rc, err, "не записываема — событие без правки блока event не публикуется")
    pr.ok("запись не записываема: событий 0", not posts(st), str(posts(st)))

    d4 = fixture(pr, "hook", record())
    hook = os.path.join(d4, ".git", "hooks", "commit-msg")
    open(hook, "w").write("#!/bin/sh\necho 'проба: коммит отвергнут' >&2\nexit 1\n")
    os.chmod(hook, 0o755)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d4)
    url4 = st["comments"]["%s#549" % R][0]["html_url"] if posts(st) else "?"
    pr.ok("коммит отвергнут: код 1", rc == 1, err)
    pr.ok("коммит отвергнут: напечатано «СОБЫТИЕ ОПУБЛИКОВАНО» с адресом", "СОБЫТИЕ ОПУБЛИКОВАНО" in err and url4 in err, err)

    for key in ("verdict", "reviewer_role"):
        dk = fixture(pr, "no-" + key, record(drop=(key,)))
        rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=dk)
        pr.refused("в записи нет %s" % key, rc, err, "нет verdict, reviewer_role либо subject.sha256")
        pr.ok("в записи нет %s: событий 0" % key, not posts(st), str(posts(st)))

    d5 = fixture(pr, "fp", record(sha="f" * 64))
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d5)
    pr.refused("отпечаток не равен записи", rc, err, "не равен subject.sha256 записи")
    pr.ok("отпечаток не равен записи: событий 0", not posts(st), str(posts(st)))

    d5n = fixture(pr, "fpnum", record(sha="0" * 64, quoted=False))
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d5n)
    pr.refused("отпечаток из цифр без кавычек", rc, err, "не строка из 64 шестнадцатеричных знаков")
    pr.ok("отпечаток из цифр без кавычек: событий 0", not posts(st), str(posts(st)))

    d5p = fixture(pr, "path", record(path="docs/acceptance/other.md"))
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d5p)
    pr.refused("запись судит другой документ", rc, err, "запись судит docs/acceptance/other.md")
    pr.ok("запись судит другой документ: событий 0", not posts(st), str(posts(st)))

    d6 = fixture(pr, "unpub", record(), push=False)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d6)
    pr.refused("ревизия не опубликована", rc, err, "не опубликована ни в одной удалённой ветке")
    pr.ok("ревизия не опубликована: событий 0", not posts(st), str(posts(st)))

    # многострочное значение поля, строка которого начинается с «event:» — текстовая
    # граница блока ошибается; правка проверена до публикации
    tricky = record(note='note: "первая строка\nevent: в прозе"\n')
    d7 = fixture(pr, "tricky", tricky)
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(world()), cwd=d7)
    pr.refused("граница блока обманута", rc, err, "— событие не публикуется")
    pr.ok("граница блока обманута: событий 0, запись не тронута",
          not posts(st) and open(os.path.join(d7, REC), encoding="utf-8").read() == tricky, str(posts(st)))

    # сверка «прочие поля не тронуты» — прямым входом ритуала проверяемого дерева
    spec = importlib.util.spec_from_file_location("rituals_under_test", os.path.join(P.RIT, "rituals.py"))
    rit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rit)
    url9 = "https://github.com/%s/issues/549#issuecomment-9" % R
    text9 = record()
    extra = "event:\n  status: performed\n  url: %s\nstray: подкинуто\n" % url9
    try:
        rit.edited_record(text9, yaml.safe_load(text9), REC, extra, url9, "")
        why = "отказа нет"
    except rit.Refused as e:
        why = str(e)
    pr.ok("правка задела другое поле: отказ «задела другие поля»", "задела другие поля записи" in why, why)
    fine = "event:\n  status: performed\n  url: %s\n" % url9
    try:
        rit.edited_record(text9, yaml.safe_load(text9), REC, fine, url9, "")
        why = ""
    except rit.Refused as e:
        why = str(e)
    pr.ok("близнец: правка только блока event — без отказа", why == "", why)

    # ответ трекера с переводом строки в поле не заводит ключа в записи
    w = world()
    w["comment_extra"] = {"url": "https://api.example/x\nchecks:\n  coverage: подменено"}
    d8 = fixture(pr, "inject", record())
    rc, out, err, st = pr.run("approval-event", [R, DOC, REC, "549"], pr.state(w), cwd=d8)
    got = yaml.safe_load(pr.git(d8, "show", "HEAD:" + REC))
    pr.ok("перевод строки в ответе трекера: код 0, прочие поля не тронуты, значение цело",
          rc == 0 and keep(got) == keep(orig) and (got.get("event") or {}).get("api_url") == w["comment_extra"]["url"],
          err + str(got))


if __name__ == "__main__":
    sys.exit(P.main("check-03-approval-event", body))
