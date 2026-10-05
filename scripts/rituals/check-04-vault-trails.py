#!/usr/bin/env python3
"""check-04 — `vault-trails.sh` пишет trail закрытой задачи по оболочке записки и гонит vault-gate.

ЧТО УТВЕРЖДАЕТ (ws#930). Подставное хранилище — копия `obsidian/kacho`,
`scripts/vault-gate` и `scripts/vault-index` из HEAD воркспейса в своём репозитории;
подставной трекер.
  * закрытая задача без записки — `KAC/issue-N-ws.md` с оболочкой (title, category kac,
    status done), PR, sha и адресом доказательства DoD; исход ритуала равен исходу
    vault-gate на этом хранилище, и ни одной находки `[FAIL]` (контроль — тот же гейт
    на хранилище до ритуала);
  * повтор не множит блок закрытия; записке, которая уже была, правятся только
    `status`, `prs` и блок закрытия;
  * задача без комментария-доказательства — строка DoD говорит «нет», а не адрес;
  * задача, закрытая как не планируемая, — `wontfix`;
  * задача открыта — отказ кодом 1, файла нет.
Коды: 0 — пробы прошли; 1 — проба провалена; 2 — предпосылки нет либо хранилище
красное ещё до ритуала (контроль).
"""
import os
import subprocess
import sys
import tarfile
import io

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _probe as P  # noqa: E402

import yaml  # noqa: E402 — наличие проверено песочницей (иначе VOID)

R = "PRO-Robotech/kacho-workspace"
N1, N2, N3, N4 = 990001, 990002, 990003, 990004
PR_URL = "https://github.com/%s/pull/990100" % R
CLOSE_SHA = "5" * 40


def issue(n, state="closed", reason="completed"):
    return {"number": n, "id": n, "title": "проба \"ритуала\" %d" % n, "state": state, "state_reason": reason,
            "html_url": "https://github.com/%s/issues/%d" % (R, n), "created_at": "2026-10-01T00:00:00Z",
            "closed_at": "2026-10-06T00:00:00Z", "labels": []}


def world():
    proof = [{"id": 1, "body": "DoD-proof @abcdef1\nкод 0", "html_url": "https://github.com/%s/issues/%d#issuecomment-1" % (R, N1)}]
    tl = [{"event": "cross-referenced", "source": {"issue": {"html_url": PR_URL, "pull_request": {}}}},
          {"event": "closed", "commit_id": CLOSE_SHA}]
    return {"issues": {"%s#%d" % (R, N1): issue(N1), "%s#%d" % (R, N2): issue(N2, "open"),
                       "%s#%d" % (R, N3): issue(N3), "%s#%d" % (R, N4): issue(N4, reason="not_planned")},
            "comments": {"%s#%d" % (R, N1): proof, "%s#%d" % (R, N3): proof},
            "timeline": {"%s#%d" % (R, N1): tl, "%s#%d" % (R, N3): tl}}


def vault(pr):
    root = os.path.join(pr.tmp, "ws")
    os.makedirs(root)
    p = subprocess.run(["git", "-C", P.WS, "archive", "HEAD", "obsidian/kacho", "scripts/vault-gate", "scripts/vault-index", "scripts/lib", ".gitattributes"],
                       capture_output=True)
    if p.returncode != 0:
        raise P.Void("хранилище воркспейса не выгружено из HEAD: %s" % p.stderr.decode(errors="replace").strip())
    tarfile.open(fileobj=io.BytesIO(p.stdout)).extractall(root, filter="data")
    pr.git(root, "init", "-q")
    pr.git(root, "add", "-A")
    return root


def gate(pr, root):
    p = subprocess.run(["bash", os.path.join(root, "scripts", "vault-gate", "run-all.sh")], capture_output=True,
                       text=True, env=dict(pr.env, VAULT_GATE_ROOT=root))
    return p.returncode, p.stdout + p.stderr


def note(root, n):
    return os.path.join(root, "obsidian", "kacho", "KAC", "issue-%d-ws.md" % n)


def front(path):
    text = open(path, encoding="utf-8").read()
    return yaml.safe_load(text.split("---\n")[1]), text


def body(pr):
    root = vault(pr)
    ctrl, ctrl_out = gate(pr, root)
    if ctrl == 1:
        raise P.Void("хранилище красное ещё до ритуала (контроль vault-gate код 1) — пробе не с чем сравнивать")
    extra = {"RITUAL_WS": root}

    rc, out, err, _ = pr.run("vault-trails", [R, str(N1)], pr.state(world()), extra=extra)
    pr.ok("исход ритуала равен контролю vault-gate (%d)" % ctrl, rc == ctrl, err[-600:])
    pr.ok("vault-gate после ритуала без [FAIL]", "[FAIL]" not in err, err[-600:])
    path = note(root, N1)
    pr.ok("trail заведён", os.path.isfile(path))
    if os.path.isfile(path):
        fm, text = front(path)
        pr.ok("оболочка: category kac, status done, ticket_id",
              fm.get("category") == "kac" and fm.get("status") == "done" and fm.get("ticket_id") == N1, str(fm))
        pr.ok("PR в prs и в блоке", PR_URL in (fm.get("prs") or []) and ("PR: " + PR_URL) in text, text)
        pr.ok("sha закрытия в блоке", "`%s`" % CLOSE_SHA in text, text)
        pr.ok("адрес доказательства DoD в блоке", "issuecomment-1" in text and "DoD-proof @abcdef1" in text, text)

    rc, out, err, _ = pr.run("vault-trails", [R, str(N1)], pr.state(world()), extra=extra)
    pr.ok("повтор: блок закрытия один", open(path, encoding="utf-8").read().count("<!-- ritual:closure -->") == 1)

    existing = note(root, N3)
    open(existing, "w", encoding="utf-8").write(
        "---\ntitle: \"ws#%d: была раньше\"\ncategory: kac\nstatus: test\nprs: []\n---\n\n# ws#%d\n\nсвой текст\n" % (N3, N3))
    rc, out, err, _ = pr.run("vault-trails", [R, str(N3)], pr.state(world()), extra=extra)
    fm, text = front(existing)
    pr.ok("бывшая записка: status done, PR добавлен", fm.get("status") == "done" and fm.get("prs") == [PR_URL], str(fm))
    pr.ok("бывшая записка: свой текст и title сохранены", "свой текст" in text and fm.get("title") == "ws#%d: была раньше" % N3)

    w = world()
    w["comments"] = {}
    rc, out, err, _ = pr.run("vault-trails", [R, str(N4)], pr.state(w), extra=extra)
    fm, text = front(note(root, N4))
    pr.ok("не планируемая — wontfix", fm.get("status") == "wontfix", str(fm))
    pr.ok("без доказательства: строка DoD говорит «нет»", "комментария-доказательства DoD нет" in text, text)

    rc, out, err, _ = pr.run("vault-trails", [R, str(N2)], pr.state(world()), extra=extra)
    pr.ok("открытая задача: отказ кодом 1, файла нет", rc == 1 and not os.path.exists(note(root, N2)), err)

    # хранилище красное — ритуал обязан сказать это кодом, а не «записано»
    broken = os.path.join(root, "obsidian", "kacho", "KAC", "zz-ritual-probe-broken.md")
    open(broken, "w", encoding="utf-8").write("---\ntitle: проба\ncategory: resource\n---\n\nтекст\n")
    rc, out, err, _ = pr.run("vault-trails", [R, str(N1)], pr.state(world()), extra=extra)
    pr.ok("хранилище красное: исход ритуала 1, находка напечатана", rc == 1 and "zz-ritual-probe-broken" in err, err[-600:])
    os.remove(broken)


if __name__ == "__main__":
    sys.exit(P.main("check-04-vault-trails", body))
