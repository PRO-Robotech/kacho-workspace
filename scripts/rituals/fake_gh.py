#!/usr/bin/env python3
"""Двойник трекера для самопроб ритуалов: `api --method <М> <путь> [--input -]` над файлом состояния.

Состояние — JSON в `RITUAL_FAKE_STATE`; каждый вызов дописывается в его `log`, чтобы проба
могла спросить, ЧТО ритуал сделал на трекере (а не только каким кодом вышел). Сети нет.

Ключи состояния (все необязательны):
  issues      {"<вл>/<имя>#N": {number, id, title, state, state_reason, html_url, labels,
               created_at, closed_at, pull_request?}}
  comments    {"<вл>/<имя>#N": [{id, body, html_url, ...}]}
  parent      {"<вл>/<имя>#N": W} — родитель подзадачи (отношение sub-issue)
  pulls       {"<вл>/<имя>#P": {head: {ref}, base: {ref}}}
  pull_commits {"<вл>/<имя>#P": [{sha, commit: {message}}]}
  commits     {"<вл>/<имя>@<sha-префикс>": {sha}}
  timeline    {"<вл>/<имя>#N": [событие]}
  user        {login}
  fail        ["<М> <путь без запроса>"] — эти вызовы выходят кодом 1

Неизвестный путь — отказ с текстом, как у настоящего трекера на 404: двойник не
сочиняет ответа, которого ему не задали.
"""

import json
import os
import re
import sys


def main(argv):
    path_state = os.environ["RITUAL_FAKE_STATE"]
    st = json.load(open(path_state, encoding="utf-8"))
    if argv[:1] != ["api"]:
        print("fake gh: только api", file=sys.stderr)
        return 1
    args = argv[1:]
    method, body = "GET", None
    if "--method" in args:
        i = args.index("--method")
        method = args[i + 1]
        args = args[:i] + args[i + 2:]
    if "--input" in args:
        i = args.index("--input")
        args = args[:i] + args[i + 2:]
        body = json.loads(sys.stdin.read() or "null")
    raw = args[0]
    path, _, query = raw.partition("?")
    page = int((re.search(r"(?:^|&)page=(\d+)", query) or [None, "1"])[1])
    st.setdefault("log", []).append({"method": method, "path": path, "body": body})

    def done(out, rc=0):
        json.dump(st, open(path_state, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        if out is not None:
            print(json.dumps(out, ensure_ascii=False))
        return rc

    if "%s %s" % (method, path) in st.get("fail", []):
        print("fake gh: отказ, заданный пробой: %s %s" % (method, path), file=sys.stderr)
        return done(None, 1)

    if path == "user":
        return done(st.get("user", {"login": "pointpu"}))

    m = re.match(r"^repos/([\w.-]+/[\w.-]+)/(issues|pulls|commits)/([\w]+)(?:/(\w+))?$", path)
    if not m:
        print("fake gh: путь не задан: %s" % path, file=sys.stderr)
        return done(None, 1)
    repo, kind, num, sub = m.groups()
    key = "%s#%s" % (repo, num)
    issues = st.setdefault("issues", {})

    def paged(items):
        return items if page == 1 else []

    if kind == "commits":
        for k, v in st.get("commits", {}).items():
            r, _, pre = k.partition("@")
            if r == repo and (v["sha"].startswith(num) or pre.startswith(num)):
                return done(v)
        print("fake gh: No commit found for SHA: %s" % num, file=sys.stderr)
        return done(None, 1)

    if kind == "pulls":
        if sub is None and key in st.get("pulls", {}):
            return done(st["pulls"][key])
        if sub == "commits" and key in st.get("pull_commits", {}):
            return done(paged(st["pull_commits"][key]))
        print("fake gh: Not Found (pulls %s)" % key, file=sys.stderr)
        return done(None, 1)

    if key not in issues:
        print("fake gh: Not Found (issue %s)" % key, file=sys.stderr)
        return done(None, 1)
    it = issues[key]

    if sub is None and method == "GET":
        return done(it)
    if sub is None and method == "PATCH":
        it.update(body or {})
        if it.get("state") == "closed":
            it.setdefault("closed_at", "2026-10-06T00:00:00Z")
        return done(it)
    if sub == "comments" and method == "GET":
        return done(paged(st.get("comments", {}).get(key, [])))
    if sub == "comments" and method == "POST":
        lst = st.setdefault("comments", {}).setdefault(key, [])
        cid = 9000000000 + len(st["log"])
        c = {
            "id": cid,
            "node_id": "IC_fake%d" % cid,
            "body": (body or {}).get("body", ""),
            "html_url": "https://github.com/%s/issues/%s#issuecomment-%d" % (repo, num, cid),
            "url": "https://api.github.com/repos/%s/issues/comments/%d" % (repo, cid),
            "user": st.get("user", {"login": "pointpu"}),
            "author_association": "MEMBER",
            "created_at": "2026-10-06T00:00:00Z",
        }
        lst.append(c)
        return done(c)
    if sub == "sub_issues" and method == "GET":
        kids = [v for k, v in issues.items() if st.get("parent", {}).get(k) == int(num) and k.startswith(repo + "#")]
        return done(paged(sorted(kids, key=lambda v: v["number"])))
    if sub == "sub_issues" and method == "POST":
        sid = (body or {}).get("sub_issue_id")
        for k, v in issues.items():
            if v.get("id") == sid:
                if k in st.get("parent", {}) and not (body or {}).get("replace_parent"):
                    print("fake gh: sub-issue уже имеет родителя", file=sys.stderr)
                    return done(None, 1)
                st.setdefault("parent", {})[k] = int(num)
                return done(it)
        print("fake gh: sub_issue_id %s не найден" % sid, file=sys.stderr)
        return done(None, 1)
    if sub == "timeline" and method == "GET":
        return done(paged(st.get("timeline", {}).get(key, [])))
    print("fake gh: путь не задан: %s %s" % (method, path), file=sys.stderr)
    return done(None, 1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
