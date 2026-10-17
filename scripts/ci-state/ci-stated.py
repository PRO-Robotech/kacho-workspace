#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""ci-stated — демон состояния открытых запросов kacho, kaname и воркспейса (ws#1113, ws#1151).

ЗАЧЕМ. Заказ владельца 2026-10-16: «Переделай ci флоу так что бы время потрачено на
проверку состояния было минимально, очереди быстро рассасывались». Агенты ci-watcher
за две недели ждали CI 239 агент-часов; каждое чтение ci-read.sh — 9–10 вызовов gh и
8 единиц лимита REST, общий на учётку лимит 5000/ч кончался дважды. Демон опрашивает
ОДНИМ запросом GraphQL на репозиторий раз в 60 с и перечитывает ci-read.sh живьём
только при смене состояния; ожидающие читают снимок (`ci-read.sh --from-state`) без
единого вызова gh.

ЧТО ДЕЛАЕТ ОПРОС. На каждый открытый запрос — ключ (repo, pr, head, base, draft) и
отпечаток: ключ, голова базы, state свода, счёт контекстов по состояниям. Ключ и
отпечаток прежние — у снимка обновляется только checked_at (подтверждён). Иначе —
ci-read.sh живьём (тот же решатель, что у вызывающего), и снимок пишется атомарно:
временный файл 0600 в том же каталоге, fsync, rename. Ключ снимка берётся из вывода
ci-read.sh (строка CENSUS «запрос …: голова …, база …, черновик …»), а не из опроса:
между опросом и чтением голову могли сменить. Ключ опроса пишется рядом как seen —
разошлись, и ci-read.sh --from-state читает живьём (STATE-KEY-MISMATCH). Чтение не
удалось (код 2, лимит) — снимок не подтверждается и через 180 с перестаёт быть годным.
Смена кода или ключа — строка в FIFO запроса (wait/<repo>__<pr>.fifo): ожидающий
читает её `timeout 540 head -n1 <fifo>`, а не опрашивает. Закрытые запросы снимаются.

БЮДЖЕТ. Перечитывание по смене счёта — не чаще раза в 120 с на запрос; смена ключа,
state свода или конец счёта (незавершённых 0) — сразу. Остаток REST ниже 1000 — не
перечитывается вовсе (резерв посадки); снимки тогда стареют, и вызывающий читает живьём.

СТРАЖ ЗАПИСИ — у самого демона, а не у прав токена (Д1–Д3): единственный выход в
сеть — http_json(), и первым она зовёт guard(): GET — любой путь; POST — только
/graphql с текстом, РАВНЫМ одному из литералов LITERALS, без слова mutation; прочее —
отказ (код 3). Токен — из keyring (gh auth status: tokenSource == keyring), иначе
отказ старта (код 4): токен из файла настроек или переменной окружения демон не берёт.
keyring НЕДОСТУПЕН (gh auth status или auth token не ответили) — код 6, а не 4: при
Linger=yes менеджер пользователя стартует службу при загрузке раньше, чем вход открывает
keyring (замер 2026-10-17: default.target 00:55:21, gnome-keyring-daemon 00:56:34), и
служба повторяет старт (Restart=on-failure); токен не из keyring — 4, повтор запрещён.
Токен живёт только в памяти и в заголовке Authorization к api.github.com.

ИСПОЛЬЗОВАНИЕ
  ci-stated.py [--repos A,B] [--interval 60] [--once] [--poll-file F]
  ci-stated.py --print-query <имя>                 — литерал запроса (для проб)
  ci-stated.py --probe-request <метод> <путь> [файл] — пройти страж и сеть одним запросом

ИСХОДЫ: 0 — опрос прошёл (--once) либо служба остановлена сигналом; 2 — довод не тот;
3 — отказ стража; 4 — отказ старта (токен не из keyring, каталог состояния, адрес
площадки); 5 — сеть не ответила (--probe-request); 6 — keyring недоступен (повторимо).

ВХОД ПОДМЕНЯЕМ — ради доказательства (scripts/ci-state/inject.sh):
  CI_STATE_DIR      — каталог состояния вместо ~/.cache/kacho-ci-state;
  CI_STATED_GH      — gh для auth status / auth token;
  CI_STATED_CI_READ — путь ci-read.sh;
  CI_STATED_API     — адрес площадки: https://api.github.com либо http://127.0.0.1:<порт>;
  --poll-file       — ответ GraphQL из файла вместо сети (снимок пишется тем же кодом).
Сцены (д), (е) пробы зовут one_pass() в одном процессе, подменяя часы (имя time модуля)
и ответ об остатке REST (core_remaining): бюджет перечитывания живёт в памяти процесса.
"""
import argparse
import hashlib
import json
import os
import re
import signal
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.request

MAX_REFRESH_EVERY = 120   # с: перечитывание по смене одного лишь счёта
CORE_RESERVE = 1000       # остаток REST, ниже которого демон не перечитывает
# Перечень — тот же, что в --repos юнита ci-stated.service; расхождение — отказ install.sh (код 2).
DEFAULT_REPOS = "PRO-Robotech/kacho,PRO-Robotech/kaname,PRO-Robotech/kacho-workspace"

# Литералы — единственные тексты, которые демон отправляет в /graphql.
LITERALS = {
    "open_prs": (
        "query($owner:String!,$name:String!){repository(owner:$owner,name:$name){"
        "pullRequests(states:OPEN,first:100){nodes{number isDraft headRefOid baseRefName "
        "baseRef{target{oid}} commits(last:1){nodes{commit{statusCheckRollup{state "
        "contexts(first:1){totalCount checkRunCountsByState{state count} "
        "statusContextCountsByState{state count}}}}}}}}} rateLimit{cost remaining resetAt}}"
    ),
}
MUTATION_RE = re.compile(r"\bmutation\b", re.IGNORECASE)
LITERAL_TEXTS = set(LITERALS.values())
TERMINAL = {"SUCCESS", "FAILURE", "ERROR", "NEUTRAL", "SKIPPED", "CANCELLED",
            "TIMED_OUT", "ACTION_REQUIRED", "STALE", "STARTUP_FAILURE", "COMPLETED"}
CENSUS_RE = re.compile(
    r"^CENSUS\tзапрос (?P<repo>\S+)#(?P<pr>\d+): состояние \S+, голова (?P<head>[0-9a-f]{40}), "
    r"база (?P<base>.+), черновик (?P<draft>true|false)$", re.M)


class Refused(Exception):
    """Отказ стража записи."""


class StartRefused(Exception):
    """Отказ старта: код 4 — запрет, повтор бесполезен; KeyringDown — код 6, повторимо."""
    code = 4


class KeyringDown(StartRefused):
    """keyring не ответил: повторимо (служба перезапускается)."""
    code = 6


def log(msg):
    print(f"ci-stated: {msg}", file=sys.stderr, flush=True)


def guard(method, path, body):
    """Пропускает только чтение: GET; POST — лишь /graphql с литералом без mutation."""
    if method != "GET":
        if not (method == "POST" and path == "/graphql"):
            raise Refused(f"метод {method} {path}: демон только читает (GET; POST — лишь /graphql)")
        if not isinstance(body, dict) or set(body) - {"query", "variables"}:
            raise Refused("тело /graphql — только query и variables")
        text = body.get("query")
        if not isinstance(text, str):
            raise Refused("в теле /graphql нет текста query")
        if MUTATION_RE.search(text):
            raise Refused("слово mutation в тексте /graphql: демон не пишет")
        if text not in LITERAL_TEXTS:
            raise Refused("текст /graphql — не литерал демона")


def api_base():
    base = os.environ.get("CI_STATED_API", "https://api.github.com").rstrip("/")
    if base != "https://api.github.com" and not re.fullmatch(r"http://127\.0\.0\.1:\d+", base):
        raise StartRefused(f"адрес площадки {base}: только https://api.github.com либо http://127.0.0.1:<порт>")
    return base


def http_json(method, path, body=None, token=""):
    """Единственный выход демона в сеть; страж — первым."""
    guard(method, path, body)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(api_base() + path, data=data, method=method)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("User-Agent", "kacho-ci-stated")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode())


def keyring_token():
    """Токен — только из keyring; иначе отказ старта."""
    gh = os.environ.get("CI_STATED_GH", "gh")
    env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN")}
    try:
        st = subprocess.run([gh, "auth", "status", "--json", "hosts"], capture_output=True, text=True,
                            timeout=30, env=env)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise KeyringDown(f"keyring недоступен: gh auth status не исполнился ({e.__class__.__name__})")
    if st.returncode != 0:
        raise KeyringDown(f"keyring недоступен: gh auth status код {st.returncode}")
    try:
        accts = json.loads(st.stdout)["hosts"]["github.com"]
        act = next(a for a in accts if a.get("active"))
        src = act.get("tokenSource")
    except (ValueError, KeyError, TypeError, StopIteration):
        raise KeyringDown("keyring недоступен: ответ gh auth status не разбирается")
    if src != "keyring":
        raise StartRefused(f"токен не из keyring (источник «{src}»): демон его не берёт")
    tok = subprocess.run([gh, "auth", "token", "-h", "github.com"], capture_output=True, text=True,
                         timeout=30, env=env)
    token = tok.stdout.strip()
    if tok.returncode != 0 or not token:
        raise KeyringDown("keyring недоступен: gh auth token не отдал токен")
    return token


def state_dir():
    d = os.environ.get("CI_STATE_DIR") or os.path.join(
        os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"), "kacho-ci-state")
    for sub in ("", "snap", "wait", "etag"):
        p = os.path.join(d, sub) if sub else d
        os.makedirs(p, mode=0o700, exist_ok=True)
        s = os.lstat(p)
        if not stat.S_ISDIR(s.st_mode) or s.st_uid != os.getuid():
            raise StartRefused(f"каталог состояния {p} не мой либо не каталог")
        os.chmod(p, 0o700)
    return d


def write_atomic(path, obj):
    tmp = f"{path}.{os.getpid()}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def read_snapshot(path):
    try:
        s = os.lstat(path)
        if not stat.S_ISREG(s.st_mode) or s.st_uid != os.getuid():
            return None
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def signal_waiters(d, name, line):
    """Строка в FIFO ожидающих; читающего нет — молча (O_NONBLOCK)."""
    fifo = os.path.join(d, "wait", name + ".fifo")
    try:
        if not os.path.exists(fifo):
            os.mkfifo(fifo, 0o600)
        fd = os.open(fifo, os.O_WRONLY | os.O_NONBLOCK)
    except OSError:
        return
    try:
        os.write(fd, (line + "\n").encode())
    except OSError:
        pass
    finally:
        os.close(fd)


def poll_repo(repo, token, poll_file):
    if poll_file:
        with open(poll_file, encoding="utf-8") as f:
            return json.load(f)
    owner, name = repo.split("/", 1)
    return http_json("POST", "/graphql", {"query": LITERALS["open_prs"],
                                          "variables": {"owner": owner, "name": name}}, token)


def pr_records(repo, resp):
    nodes = (((resp or {}).get("data") or {}).get("repository") or {}).get("pullRequests", {}).get("nodes")
    if not isinstance(nodes, list):
        raise ValueError(f"ответ GraphQL о {repo} не разбирается")
    for n in nodes:
        roll = None
        commits = (n.get("commits") or {}).get("nodes") or []
        if commits:
            roll = (commits[-1].get("commit") or {}).get("statusCheckRollup")
        roll = roll or {}
        ctx = roll.get("contexts") or {}
        counts = {}
        for kind in ("checkRunCountsByState", "statusContextCountsByState"):
            for c in ctx.get(kind) or []:
                counts[f"{kind[:5]}:{c.get('state')}"] = c.get("count", 0)
        key = {"repo": repo, "pr": str(n["number"]), "head": n["headRefOid"],
               "base": n["baseRefName"], "draft": "true" if n.get("isDraft") else "false"}
        base_oid = ((n.get("baseRef") or {}).get("target") or {}).get("oid")
        pending = sum(v for k, v in counts.items() if k.split(":", 1)[1] not in TERMINAL)
        fp_src = json.dumps({"key": key, "base_oid": base_oid, "state": roll.get("state"),
                             "total": ctx.get("totalCount"), "counts": counts}, sort_keys=True)
        yield key, hashlib.sha256(fp_src.encode()).hexdigest(), roll.get("state"), pending


def ci_read(repo, pr, d):
    cr = os.environ.get("CI_STATED_CI_READ") or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ci-read.sh")
    env = {k: v for k, v in os.environ.items() if k not in ("GH_TOKEN", "GITHUB_TOKEN")}
    env["CI_STATE_DIR"] = d
    env.setdefault("GH_NO_UPDATE_NOTIFIER", "1")
    try:
        r = subprocess.run(["bash", cr, repo, pr], capture_output=True, timeout=300, env=env)
    except (OSError, subprocess.TimeoutExpired) as e:
        return 2, f"VOID\tci-read.sh не исполнился: {e.__class__.__name__}\n"
    return r.returncode, r.stdout.decode("utf-8", "replace")


def core_remaining(token, poll_file):
    if poll_file:
        return None
    try:
        return http_json("GET", "/rate_limit", None, token)["resources"]["core"]["remaining"]
    except Exception:  # noqa: BLE001 — нет ответа о лимите: решают сами чтения
        return None


def one_pass(repos, d, token, poll_file, last_refresh):
    open_names = set()
    polled = set()   # снимки снимаются лишь у репозитория, чей опрос прошёл
    for repo in repos:
        try:
            resp = poll_repo(repo, token, poll_file)
            recs = list(pr_records(repo, resp))
        except (Refused, urllib.error.URLError, OSError, ValueError, KeyError, TypeError) as e:
            log(f"опрос {repo} не прошёл: {e}")
            continue
        polled.add(repo)
        for key, fp, roll_state, pending in recs:
            name = f"{repo.replace('/', '__')}__{key['pr']}"
            open_names.add(name)
            path = os.path.join(d, "snap", name + ".json")
            now = time.time()
            snap = read_snapshot(path)
            if snap and snap.get("seen") == key and snap.get("key") == key and snap.get("fp") == fp:
                snap["checked_at"] = now
                write_atomic(path, snap)
                continue
            changed_key = (not snap or snap.get("seen") != key or snap.get("key") != key
                           or snap.get("roll") != roll_state or pending == 0)
            due = now - last_refresh.get(name, 0) >= MAX_REFRESH_EVERY
            if not (changed_key or due):
                if snap:
                    snap["seen"] = key
                    write_atomic(path, snap)
                continue
            rem = core_remaining(token, poll_file)
            if rem is not None and rem < CORE_RESERVE:
                log(f"{name}: остаток REST {rem} < {CORE_RESERVE} — не перечитываю, снимок стареет")
                if snap:
                    snap["seen"] = key
                    write_atomic(path, snap)
                continue
            last_refresh[name] = now
            code, out = ci_read(repo, key["pr"], d)
            m = CENSUS_RE.search(out)
            if code == 2 or not m or not out.rstrip("\n").split("\n")[-1].startswith("VERDICT\t"):
                log(f"{name}: живое чтение не вынесло вердикта (код {code}) — снимок не подтверждён")
                if snap:
                    snap["seen"] = key
                    write_atomic(path, snap)
                continue
            got = {k: m.group(k) for k in ("repo", "pr", "head", "base", "draft")}
            new = {"key": got, "seen": key, "fp": fp, "roll": roll_state, "code": code, "out": out,
                   "checked_at": now, "written_at": now}
            write_atomic(path, new)
            if not snap or snap.get("code") != code or snap.get("key") != got:
                signal_waiters(d, name, f"{repo} {key['pr']} {got['head']} код {code}")
    if not poll_file:
        for f in os.listdir(os.path.join(d, "snap")):
            if f.endswith(".json") and f[:-5] not in open_names and any(
                    f.startswith(r.replace("/", "__") + "__") for r in polled):
                os.unlink(os.path.join(d, "snap", f))
        cutoff = time.time() - 2 * 86400
        ed = os.path.join(d, "etag")
        for f in os.listdir(ed):
            p = os.path.join(ed, f)
            if os.lstat(p).st_mtime < cutoff:
                os.unlink(p)


def main(argv):
    ap = argparse.ArgumentParser(prog="ci-stated.py", add_help=True)
    ap.add_argument("--repos", default=DEFAULT_REPOS)
    ap.add_argument("--interval", type=int, default=60)
    ap.add_argument("--once", action="store_true")
    ap.add_argument("--poll-file")
    ap.add_argument("--print-query")
    ap.add_argument("--probe-request", nargs="+")
    a = ap.parse_args(argv)

    if a.print_query:
        if a.print_query not in LITERALS:
            log(f"литерала {a.print_query} нет")
            return 2
        sys.stdout.write(LITERALS[a.print_query])
        return 0
    if a.probe_request:
        method, path = a.probe_request[0], a.probe_request[1] if len(a.probe_request) > 1 else "/"
        body = None
        if len(a.probe_request) > 2:
            with open(a.probe_request[2], encoding="utf-8") as f:
                body = {"query": f.read()}
        try:
            http_json(method, path, body, "")
        except Refused as e:
            log(f"ОТКАЗ стража: {e}")
            return 3
        except StartRefused as e:
            log(f"ОТКАЗ: {e}")
            return e.code
        except (urllib.error.URLError, OSError) as e:
            log(f"страж пройден; сеть не ответила: {e.__class__.__name__}")
            return 5
        return 0

    repos = [r for r in a.repos.split(",") if r]
    if not repos or not all(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", r) for r in repos):
        log(f"--repos «{a.repos}» не перечень <владелец>/<имя>")
        return 2
    if a.interval < 30:
        log("--interval меньше 30 с: опрос дороже, чем ожидание")
        return 2
    try:
        api_base()
        token = keyring_token()
        d = state_dir()
    except StartRefused as e:
        log(f"ОТКАЗ СТАРТА: {e}")
        return e.code
    os.umask(0o077)
    stop = []
    signal.signal(signal.SIGTERM, lambda *_: stop.append(1))
    last_refresh = {}
    while True:
        one_pass(repos, d, token, a.poll_file, last_refresh)
        if a.once or stop:
            return 0
        for _ in range(a.interval):
            if stop:
                return 0
            time.sleep(1)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
