#!/usr/bin/env python3
"""check-01 — `pr-body.sh` собирает тело PR: `Closes` лишь задаче с доказательством DoD, атрибуции нет.

ЧТО УТВЕРЖДАЕТ (ws#930). На подставном репозитории (ветка `41-feature`, коммиты с
ссылками на задачи в формах `#N`, `<вл>/<имя>#N`, на чужой репозиторий и на PR) и
подставном трекере:
  * задача с комментарием `DoD-proof @<ревизия>` в начале строки — `Closes`, и
    закрывающие строки идут последними; без него — `Refs`; закрытая — `Refs`;
    номер-PR в перечень не попадает, ссылка на чужой репозиторий не запрашивается;
  * инъекция «Closes без доказательства»: то же дерево, комментария нет — `Refs`, ни
    одной строки `Closes`; близнец — `DoD-proof @…` посреди прозы доказательством не
    является;
  * инъекция «атрибуция»: коммит с трейлером `Co-Authored-By:` — отказ кодом 1, тело не
    выдано, sha назван; близнец — слово в середине строки прозы — тело собрано;
  * тот же разбор по номеру PR (коммиты — из трекера);
  * задача не прочитана либо коммитов ноль — код 2, а не тело.
Коды: 0 — пробы прошли; 1 — проба провалена; 2 — предпосылки нет (git, подпись, PyYAML).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _probe as P  # noqa: E402

R = "PRO-Robotech/rituals-probe"


def issue(n, state="open", pr=False):
    it = {"number": n, "id": 7000 + n, "title": "задача %d" % n, "state": state,
          "html_url": "https://github.com/%s/issues/%d" % (R, n)}
    if pr:
        it["pull_request"] = {"url": "x"}
    return it


def closes(out):
    return [ln for ln in out.splitlines() if ln.startswith("Closes #")]


def world(proof="DoD-proof @abc1234\nкоманда — код 0"):
    return {
        "issues": {"%s#41" % R: issue(41), "%s#42" % R: issue(42), "%s#43" % R: issue(43, "closed"),
                   "%s#50" % R: issue(50, pr=True)},
        "comments": {"%s#41" % R: [{"id": 1, "body": proof, "html_url": "https://github.com/%s/issues/41#issuecomment-1" % R}]},
    }


def body(pr):
    d = pr.repo("repo", {"f.txt": "0\n"})
    pr.git(d, "checkout", "-qb", "41-feature")
    pr.commit(d, "оснастка: первая правка (#41)")
    pr.commit(d, "оснастка: вторая — %s#42 и #43, после PR #50; соседу PRO-Robotech/other#44" % R)
    args = [R, "41-feature", "main", "41-feature"]

    rc, out, err, st = pr.run("pr-body", args, pr.state(world()), cwd=d)
    tail = out.rstrip("\n").splitlines()
    pr.ok("законный вход: код 0", rc == 0, err)
    pr.ok("Closes #41 последней строкой", tail[-1:] == ["Closes #41"], out)
    pr.ok("Refs #42 и Refs #43", "Refs #42" in tail and "Refs #43" in tail, out)
    pr.ok("номер-PR #50 не в перечне", "#50" not in "\n".join(tail[-4:]) and "задача 50" not in out, out)
    pr.ok("чужой репозиторий не запрошен", not any("other" in e["path"] for e in st["log"]), str(st["log"]))
    pr.ok("коммиты перечислены", out.count("- `") == 2, out)
    pr.ok("перепись в stderr", "Closes 1, Refs 2" in err, err)
    pr.ok("трекер не изменён", not P.writes(st), str(P.writes(st)))

    # инъекция: Closes без доказательства → Refs
    rc, out, err, _ = pr.run("pr-body", args, pr.state(world(proof="обсуждение без доказательства")), cwd=d)
    pr.ok("без доказательства: код 0", rc == 0, err)
    pr.ok("без доказательства: Refs #41, ни одного Closes", "Refs #41" in out and not closes(out), out)
    rc, out, err, _ = pr.run("pr-body", args, pr.state(world(proof="см. DoD-proof @abc1234 в соседней")), cwd=d)
    pr.ok("близнец: DoD-proof посреди прозы — не доказательство", rc == 0 and not closes(out), out + err)

    # по номеру PR: коммиты — из трекера
    w = world()
    w["pulls"] = {"%s#60" % R: {"head": {"ref": "41-feature"}, "base": {"ref": "main"}}}
    w["pull_commits"] = {"%s#60" % R: [{"sha": "a" * 40, "commit": {"message": "правка #42"}}]}
    rc, out, err, _ = pr.run("pr-body", [R, "60"], pr.state(w))
    pr.ok("по номеру PR: Closes #41 из имени ветки, Refs #42", rc == 0 and out.rstrip().endswith("Closes #41")
          and "Refs #42" in out, out + err)

    # инъекция: атрибуция → отказ
    pr.git(d, "checkout", "-qb", "41-twin")
    pr.commit(d, "оснастка: про строку co-authored-by: в середине прозы (#41)")
    rc, out, err, _ = pr.run("pr-body", [R, "41-twin", "main", "41-twin"], pr.state(world()), cwd=d)
    pr.ok("близнец атрибуции: ключ посреди прозы — тело собрано", rc == 0 and "Closes #41" in out, err)
    bad = pr.commit(d, "оснастка: третья (#41)\n\nCo-Authored-By: Someone <x@example.com>")
    rc, out, err, _ = pr.run("pr-body", [R, "41-twin", "main", "41-twin"], pr.state(world()), cwd=d)
    pr.ok("атрибуция: код 1", rc == 1, err)
    pr.ok("атрибуция: тело не выдано", out == "", out)
    pr.ok("атрибуция: sha назван", bad[:10] in err, err)

    # не выполнилось
    w = world()
    w["fail"] = ["GET repos/%s/issues/42" % R]
    rc, out, err, _ = pr.run("pr-body", args, pr.state(w), cwd=d)
    pr.ok("задача не прочитана: код 2, тела нет", rc == 2 and out == "", err)
    rc, out, err, _ = pr.run("pr-body", [R, "41-feature", "41-feature", "41-feature"], pr.state(world()), cwd=d)
    pr.ok("коммитов ноль: код 2", rc == 2 and out == "", err)


if __name__ == "__main__":
    sys.exit(P.main("check-01-pr-body", body))
