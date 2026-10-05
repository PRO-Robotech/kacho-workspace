#!/usr/bin/env python3
"""check-02 — `close-wave.sh` закрывает волну: задачи с доказательством DoD — закрыты, остаток — в N+1.

ЧТО УТВЕРЖДАЕТ (ws#930). На подставном трекере: волна #10 с подзадачами #11 (открыта,
`DoD-proof @…`), #12 (открыта, доказательства нет), #13 (закрыта раньше), следующая
волна #20, коммит вливания в ветку эпика существует.
  * #11 закрыта с комментарием, где названы коммит вливания и адрес доказательства;
  * инъекция «Closes без доказательства»: #12 НЕ закрыта, ей комментарий «Остаток →
    волна #20», её родитель по sub-issue — #20; близнец — `DoD-proof @…` посреди прозы
    доказательством не является;
  * волна закрыта, и открытых подзадач у неё 0 — перечитано после действий;
  * остаток есть, а `--next` не назван — код 2 и НИ ОДНОГО изменяющего вызова;
  * коммит вливания не найден либо подзадач ноль — код 2 без изменений;
  * следующая волна закрыта — отказ кодом 1 без изменений.
Коды: 0 — пробы прошли; 1 — проба провалена; 2 — предпосылки нет.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _probe as P  # noqa: E402

R = "PRO-Robotech/rituals-probe"
SHA = "c0ffee" + "0" * 34


def issue(n, state="open"):
    return {"number": n, "id": 7000 + n, "title": "задача %d" % n, "state": state,
            "html_url": "https://github.com/%s/issues/%d" % (R, n)}


def world(proof12="обсуждение", next_state="open"):
    def c(n, text):
        return [{"id": 100 + n, "body": text, "html_url": "https://github.com/%s/issues/%d#issuecomment-%d" % (R, n, 100 + n)}]
    return {
        "issues": {"%s#%d" % (R, n): issue(n) for n in (10, 11, 12)} | {
            "%s#13" % R: issue(13, "closed"), "%s#20" % R: issue(20, next_state)},
        "parent": {"%s#11" % R: 10, "%s#12" % R: 10, "%s#13" % R: 10},
        "comments": {"%s#11" % R: c(11, "DoD-proof @abc1234\nпредикат — код 0"), "%s#12" % R: c(12, proof12)},
        "commits": {"%s@%s" % (R, SHA[:12]): {"sha": SHA}},
    }


def body(pr):
    rc, out, err, st = pr.run("close-wave", [R, "10", SHA[:12], "--next", "20"], pr.state(world()))
    iss = st["issues"]
    pr.ok("законный вход: код 0", rc == 0, err)
    pr.ok("#11 с доказательством закрыта", iss["%s#11" % R]["state"] == "closed", str(iss["%s#11" % R]))
    c11 = st["comments"]["%s#11" % R][-1]["body"]
    pr.ok("комментарий закрытия называет вливание и доказательство", SHA in c11 and "issuecomment-111" in c11, c11)
    pr.ok("инъекция: #12 без доказательства не закрыта", iss["%s#12" % R]["state"] == "open")
    c12 = st["comments"]["%s#12" % R][-1]["body"]
    pr.ok("#12: комментарий «Остаток → волна #20»", c12.startswith("Остаток → волна #20"), c12)
    pr.ok("#12 переведена подзадачей в #20", st["parent"]["%s#12" % R] == 20, str(st["parent"]))
    pr.ok("волна закрыта", iss["%s#10" % R]["state"] == "closed")
    pr.ok("у закрытой волны открытых подзадач 0 (перечитано)", "открытых 0" in err, err)
    pr.ok("#13, закрытая раньше, не тронута", not any(e["path"].endswith("/issues/13") or "/issues/13/" in e["path"]
                                                     for e in P.writes(st)))

    rc, out, err, st = pr.run("close-wave", [R, "10", SHA[:12], "--next", "20"],
                              pr.state(world(proof12="см. DoD-proof @abc1234 у соседа")))
    pr.ok("близнец: DoD-proof посреди прозы — #12 не закрыта",
          rc == 0 and st["issues"]["%s#12" % R]["state"] == "open", err)

    rc, out, err, st = pr.run("close-wave", [R, "10", SHA[:12]], pr.state(world()))
    pr.ok("остаток без --next: код 2", rc == 2, err)
    pr.ok("остаток без --next: изменений 0", not P.writes(st), str(P.writes(st)))

    rc, out, err, st = pr.run("close-wave", [R, "10", "deadbeef", "--next", "20"], pr.state(world()))
    pr.ok("коммит вливания не найден: код 2 без изменений", rc == 2 and not P.writes(st), err)

    w = world()
    w["parent"] = {}
    rc, out, err, st = pr.run("close-wave", [R, "10", SHA[:12], "--next", "20"], pr.state(w))
    pr.ok("подзадач ноль: код 2 без изменений", rc == 2 and not P.writes(st), err)

    rc, out, err, st = pr.run("close-wave", [R, "10", SHA[:12], "--next", "20"], pr.state(world(next_state="closed")))
    pr.ok("следующая волна закрыта: код 1 без изменений", rc == 1 and not P.writes(st), err)

    w = world(proof12="DoD-proof @def5678")
    rc, out, err, st = pr.run("close-wave", [R, "10", SHA[:12]], pr.state(w))
    pr.ok("все с доказательством: --next не нужен, код 0, остатка 0",
          rc == 0 and "перенесено 0" in err and st["issues"]["%s#12" % R]["state"] == "closed", err)


if __name__ == "__main__":
    sys.exit(P.main("check-02-close-wave", body))
