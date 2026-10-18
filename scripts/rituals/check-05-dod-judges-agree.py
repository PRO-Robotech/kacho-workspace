#!/usr/bin/env python3
"""check-05 — три судьи доказательства DoD выносят на одном PR один исход (ws#1162).

ЗАЧЕМ. Судей `DoD-proof @<ревизия>` у строки закрытия трое, и демон вливания гонит двоих
на одной голове: `scripts/merge-readiness.sh` (Closes PR), `scripts/landing-precheck.sh`
(пункт (ж)) и генератор тела `scripts/pr-body.sh` (`rituals.py`, Closes или Refs). До
ws#1162 merge-readiness засчитывал любую распознанную ревизию — `DoD-proof @deadbeef1` тоже,
— а двое других требовали коммит диапазона, каждый своим кодом: на одном PR исходы
расходились. Привязка теперь одна — `dod_proof_bound` в `scripts/lib/dod_proof.jq`.

ЧТО УТВЕРЖДАЕТ. Один подставной PR `PRO-Robotech/kacho-workspace#7` (голова `41-x`, тело
`Closes #41`): база `main` — коммит B; диапазон — C1 «#41 правка» и голова H, пустой коммит
(дерево H = дерево C1); вне диапазона — X, коммит с деревом C1 от родителя B. На каждый
случай доказательства в задаче #41 все трое судят НАСТОЯЩИМИ скриптами дерева через один
подставной `gh`, и исход каждого — «Closes засчитан» или «нет» — обязан совпасть с
ожидаемым:
  * @C1 — коммит диапазона, не голова, с деревом головы (законный близнец) — засчитан всеми;
  * @H — голова — засчитан всеми;
  * @B — ревизия базы, предок головы — не засчитан никем;
  * @X — то же дерево, но коммит вне диапазона — не засчитан никем (судят коммит, не дерево);
  * @deadbeef1 — ревизии нет — не засчитан никем;
  * доказательства нет — не засчитан никем.
Исход судьи читается по его НАЗВАННОЙ строке, а не по одному коду: merge-readiness — код 0 и
«с доказательством DoD: 1 · без: 0» либо код 1 и «Closes без доказательства DoD»;
landing-precheck — CENSUS «закрытие: Closes 1, с доказательством 1» либо REASON
CLOSES-WITHOUT-PROOF о #41; генератор — `Closes #41` либо `Refs #41`. Иной вывод — проба
провалена: судья, не вынесший вердикта, не «согласен».
Коды: 0 — пробы прошли; 1 — проба провалена; 2 — предпосылки нет (git, подпись, PyYAML, jq,
судьи в дереве).
"""
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _probe as P  # noqa: E402

R = "PRO-Robotech/kacho-workspace"
PR_N = 7
JUDGES = {"merge-readiness": os.path.join(P.ROOT, "scripts", "merge-readiness.sh"),
          "landing-precheck": os.path.join(P.ROOT, "scripts", "landing-precheck.sh")}

# Подставной gh всех троих: `pr view` (merge-readiness), `api <путь> [--paginate]`
# (merge-readiness, landing-precheck) и `api --method GET <путь>` (генератор). Ответ — из
# мира случая (`JUDGES_WORLD`); незнакомый путь — код 99, а не пустой ответ: пустой увёл бы
# судью в «не прочитано», и провязка пробы выглядела бы его вердиктом.
FAKE = r'''#!/usr/bin/env python3
import json, os, re, sys
w = json.load(open(os.environ["JUDGES_WORLD"], encoding="utf-8"))
a = [x for x in sys.argv[1:] if x != "--paginate"]
if a[:2] == ["pr", "view"]:
    print(json.dumps(w["prview"])); sys.exit(0)
if a[:1] != ["api"]:
    print("judges gh: незнакомый вызов %r" % a, file=sys.stderr); sys.exit(99)
a = a[1:]
if a[:1] == ["--method"]:
    a = a[2:]
path, _, q = a[0].partition("?")
page = int((re.search(r"(?:^|&)page=(\d+)", q) or [0, "1"])[1])
per = int((re.search(r"(?:^|&)per_page=(\d+)", q) or [0, "30"])[1])
def sl(xs):
    return xs[(page - 1) * per:page * per]
R = w["repo"]
if path == "rate_limit":
    sys.exit(1)
if path == "repos/%s/pulls/%d" % (R, w["pr"]):
    out = w["pull"]
elif path == "repos/%s/pulls/%d/commits" % (R, w["pr"]):
    out = sl(w["commits"])
elif path == "repos/%s/compare/%s...%s" % (R, w["base"], w["head"]):
    out = {"total_commits": len(w["commits"]), "commits": sl(w["commits"])}
elif path == "repos/%s/commits/%s/check-runs" % (R, w["head"]):
    out = w["checkruns"] if page == 1 else dict(w["checkruns"], check_runs=[])
elif path == "repos/%s/actions/runs" % R:
    out = {"total_count": 0, "workflow_runs": []}
elif path == "repos/%s/branches/main/protection" % R:
    out = w["protection"]
elif path == "repos/%s/issues/41" % R:
    out = w["issue"]
elif path == "repos/%s/issues/41/comments" % R:
    out = sl(w["comments"])
else:
    print("judges gh: незнакомый путь %s" % a[0], file=sys.stderr); sys.exit(99)
print(json.dumps(out))
'''


def verdicts(pr, d, world, sha):
    """Исход каждого судьи: True — Closes #41 засчитан, False — нет, строка — вердикта нет."""
    path = pr.state(world)
    env = dict(pr.env, JUDGES_WORLD=path, PATH=os.path.join(pr.tmp, "jbin") + os.pathsep + pr.env["PATH"],
               CI_READ_EXPECTED=os.path.join(pr.tmp, "ledger-none.tsv"))
    out = {}
    p = subprocess.run(["bash", JUDGES["merge-readiness"], R, str(PR_N)], capture_output=True, text=True,
                       env=env, cwd=pr.tmp)
    t = p.stdout + p.stderr
    if p.returncode == 0 and "с доказательством DoD: 1 · без: 0" in t:
        out["merge-readiness"] = True
    elif p.returncode == 1 and "СЛИВАТЬ НЕЛЬЗЯ — Closes без доказательства DoD" in t:
        out["merge-readiness"] = False
    else:
        out["merge-readiness"] = "код %d: %s" % (p.returncode, t.strip()[-300:])
    p = subprocess.run(["bash", JUDGES["landing-precheck"], R, str(PR_N)], capture_output=True, text=True,
                       env=dict(env, LANDING_PRECHECK_GH=os.path.join(pr.tmp, "jbin", "gh"),
                                LANDING_PRECHECK_MERGE_READINESS=os.path.join(pr.tmp, "mr-stub.sh")),
                       cwd=pr.tmp)
    t = p.stdout + p.stderr
    if "CENSUS\tзакрытие: Closes 1, с доказательством 1" in t and "CLOSES-WITHOUT-PROOF" not in t:
        out["landing-precheck"] = True
    elif re.search(r"^REASON\tCLOSES-WITHOUT-PROOF\t%s#41: " % re.escape(R), t, re.M):
        out["landing-precheck"] = False
    else:
        out["landing-precheck"] = "код %d: %s" % (p.returncode, t.strip()[-300:])
    p = subprocess.run(["bash", P.ENTRY["pr-body"], R, sha["B"], sha["H"]], capture_output=True, text=True,
                       env=dict(env, RITUAL_GH=os.path.join(pr.tmp, "jbin", "gh"), RITUAL_REPO_DIR=d,
                                RITUAL_LEDGER_CLONES=os.path.join(pr.tmp, "no-clones")), cwd=pr.tmp)
    tail = p.stdout.rstrip("\n").splitlines()[-1:] if p.returncode == 0 else []
    if tail == ["Closes #41"]:
        out["pr-body"] = True
    elif tail == ["Refs #41"]:
        out["pr-body"] = False
    else:
        out["pr-body"] = "код %d: %s" % (p.returncode, (p.stdout + p.stderr).strip()[-300:])
    return out


def body(pr):
    missing = [f for f in JUDGES.values() if not os.path.isfile(f)]
    if missing:
        raise P.Void("судей нет в дереве (%s) — судить нечего" % ", ".join(missing))
    os.makedirs(os.path.join(pr.tmp, "jbin"))
    fake = os.path.join(pr.tmp, "jbin", "gh")
    open(fake, "w", encoding="utf-8").write(FAKE)
    os.chmod(fake, 0o755)
    stub = os.path.join(pr.tmp, "mr-stub.sh")
    open(stub, "w", encoding="utf-8").write("#!/usr/bin/env bash\necho 'merge-readiness stub: код 0'\nexit 0\n")
    os.chmod(stub, 0o755)
    open(os.path.join(pr.tmp, "ledger-none.tsv"), "w", encoding="utf-8").write("")

    d = pr.repo("repo", {"f.txt": "0\n"})
    sha = {"B": pr.git(d, "rev-parse", "HEAD").strip()}
    pr.git(d, "checkout", "-qb", "41-x")
    sha["C1"] = pr.commit(d, "#41 правка")
    pr.git(d, "commit", "-q", "--allow-empty", "-m", "#41 пустой коммит головы")
    sha["H"] = pr.git(d, "rev-parse", "HEAD").strip()
    sha["X"] = pr.git(d, "commit-tree", sha["C1"] + "^{tree}", "-p", sha["B"], "-m", "#41 та же правка вне диапазона").strip()
    if pr.git(d, "rev-parse", sha["H"] + "^{tree}") != pr.git(d, "rev-parse", sha["X"] + "^{tree}"):
        raise P.Void("посев: дерево X не совпало с деревом головы — близнец «то же дерево» не построен")

    commits = [{"sha": s, "commit": {"message": m}, "parents": [{"sha": p}]}
               for s, m, p in ((sha["C1"], "#41 правка", sha["B"]), (sha["H"], "#41 пустой коммит головы", sha["C1"]))]

    def world(proof):
        return {
            "repo": R, "pr": PR_N, "base": sha["B"], "head": sha["H"], "commits": commits,
            "prview": {"state": "OPEN", "baseRefName": "main", "headRefName": "41-x", "headRefOid": sha["H"],
                       "baseRefOid": sha["B"], "mergeStateStatus": "CLEAN", "body": "Closes #41",
                       "statusCheckRollup": [{"name": "ci", "conclusion": "SUCCESS"}],
                       "closingIssuesReferences": []},
            "pull": {"state": "open", "title": "#41 правка", "body": "Closes #41", "commits": len(commits),
                     "head": {"ref": "41-x", "sha": sha["H"]}, "base": {"ref": "main", "sha": sha["B"]}},
            "checkruns": {"total_count": 1, "check_runs": [{"name": "ci", "status": "completed", "conclusion": "success",
                                                             "head_sha": sha["H"], "check_suite": {"id": 1}}]},
            "protection": {"required_status_checks": {"contexts": ["ci"]}},
            "issue": {"number": 41, "id": 7041, "title": "задача 41", "state": "open", "labels": [],
                      "sub_issues_summary": {"total": 0, "completed": 0},
                      "html_url": "https://github.com/%s/issues/41" % R},
            "comments": [{"id": 1, "body": "обсуждение", "html_url": "https://github.com/%s/issues/41#issuecomment-1" % R}]
            + ([{"id": 2, "body": "DoD-proof @%s\nкоманда — код 0" % proof,
                 "html_url": "https://github.com/%s/issues/41#issuecomment-2" % R}] if proof else []),
        }

    cases = (
        ("@C1 — коммит диапазона с деревом головы (близнец)", sha["C1"][:9], True),
        ("@H — голова", sha["H"][:12], True),
        ("@B — ревизия базы, предок головы", sha["B"][:9], False),
        ("@X — то же дерево, коммит вне диапазона", sha["X"][:9], False),
        ("@deadbeef1 — ревизии нет", "deadbeef1", False),
        ("доказательства нет", None, False),
    )
    for label, proof, want in cases:
        got = verdicts(pr, d, world(proof), sha)
        bad = {k: v for k, v in got.items() if v is not want}
        pr.ok("%s: все трое — %s" % (label, "засчитан" if want else "не засчитан"), not bad,
              "; ".join("%s → %s" % (k, v) for k, v in bad.items()))


if __name__ == "__main__":
    sys.exit(P.main("check-05-dod-judges-agree", body))
