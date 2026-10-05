"""Общее для самопроб ритуалов: песочница git, двойник трекера, счёт проб и три исхода.

Каждая самопроба гонит НАСТОЯЩИЙ вход ритуала (`<ритуал>.sh` этого каталога) на
подставном репозитории и подставном трекере (`fake_gh.py` через `RITUAL_GH`) и судит
не только код выхода, но и то, что ритуал сделал: тело, комментарии и закрытия на
трекере (журнал двойника), файл записи и коммит.

Подпись коммитов песочницы — её HOME с корневой подписью вызывающего
(`scripts/lib/sandbox-git-home.sh`, норма ws#785); своей копии этой логики здесь нет.
Нет корневой подписи, git или PyYAML — у пробы нет предмета: `[VOID]`, код 2.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "lib"))
from gate_root import gate_root  # noqa: E402

# Предмет — ритуалы ДЕРЕВА, на которое проба направлена (`RITUALS_GATE_ROOT`, затем
# общий `GATE_ROOT`, затем расположение файла; `scripts/lib/gate_root.py`); двойник
# трекера и песочница подписи — оснастка самой пробы, они берутся рядом с ней.
ROOT = gate_root("RITUALS_GATE_ROOT", __file__)
RIT = os.path.join(ROOT, "scripts", "rituals")
WS = os.environ.get("RITUALS_WS") or ROOT
FAKE = os.path.join(HERE, "fake_gh.py")
SUBJECT = ("rituals.py", "pr-body.sh", "close-wave.sh", "approval-event.sh", "vault-trails.sh")
SIGNATURE_VARS = ("GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL", "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL",
                  "GIT_CONFIG_GLOBAL", "GIT_CONFIG_PARAMETERS", "GIT_CONFIG_COUNT",
                  "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR")


class Void(Exception):
    pass


class Probe:
    def __init__(self, name):
        self.name = name
        self.tmp = tempfile.mkdtemp(prefix="rituals-probe-")
        self.passed, self.failed = 0, []
        self.env = self._sandbox_env()

    def _sandbox_env(self):
        missing = [f for f in SUBJECT if not os.path.isfile(os.path.join(RIT, f))]
        if missing:
            raise Void("в дереве %s нет ритуалов (%s) — судить нечего" % (ROOT, ", ".join(missing)))
        lib = os.path.join(os.path.dirname(HERE), "lib", "sandbox-git-home.sh")
        home = os.path.join(self.tmp, "home")
        p = subprocess.run(["bash", "-c", '. "$1" && sandbox_git_home "$2"', "probe", lib, home],
                           capture_output=True, text=True)
        if p.returncode != 0:
            raise Void("песочница без подписи: %s" % (p.stderr.strip() or "код %d" % p.returncode))
        env = {k: v for k, v in os.environ.items() if k not in SIGNATURE_VARS}
        env.update(HOME=home, XDG_CONFIG_HOME=os.path.join(home, ".config"))
        try:
            import yaml
        except ImportError:
            raise Void("PyYAML нет — ритуал записи ревью судить нечем")
        # HOME песочницы уводит пользовательский каталог библиотек: путь разборщика
        # передаётся явно, иначе ритуал ответил бы «не выполнилось» не по предмету.
        env["PYTHONPATH"] = os.pathsep.join(filter(None, [os.path.dirname(os.path.dirname(yaml.__file__)),
                                                           env.get("PYTHONPATH")]))
        return env

    def git(self, cwd, *args):
        p = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, env=self.env)
        if p.returncode != 0:
            raise Void("посев git %s: %s" % (" ".join(args), p.stderr.strip()))
        return p.stdout

    def repo(self, name, files, branch="main"):
        d = os.path.join(self.tmp, name)
        os.makedirs(d)
        self.git(d, "init", "-q", "-b", branch)
        for rel, text in files.items():
            os.makedirs(os.path.dirname(os.path.join(d, rel)) or d, exist_ok=True)
            open(os.path.join(d, rel), "w", encoding="utf-8").write(text)
        self.git(d, "add", "-A")
        self.git(d, "commit", "-qm", "посев")
        return d

    def commit(self, d, msg, rel="f.txt"):
        with open(os.path.join(d, rel), "a", encoding="utf-8") as fh:
            fh.write(msg[:20] + "\n")
        self.git(d, "add", "-A")
        self.git(d, "commit", "-qm", msg)
        return self.git(d, "rev-parse", "HEAD").strip()

    def state(self, data):
        path = os.path.join(self.tmp, "state-%d.json" % len(os.listdir(self.tmp)))
        json.dump(data, open(path, "w", encoding="utf-8"), ensure_ascii=False)
        return path

    def run(self, ritual, args, state_path, cwd=None, extra=None):
        env = dict(self.env, RITUAL_GH=FAKE, RITUAL_FAKE_STATE=state_path)
        env.update(extra or {})
        p = subprocess.run(["bash", os.path.join(RIT, ritual + ".sh"), *args], capture_output=True,
                           text=True, env=env, cwd=cwd or self.tmp)
        st = json.load(open(state_path, encoding="utf-8"))
        return p.returncode, p.stdout, p.stderr, st

    def ok(self, label, cond, detail=""):
        if cond:
            self.passed += 1
        else:
            self.failed.append("%s%s" % (label, (" — " + detail.strip()[:400]) if detail else ""))

    def finish(self):
        shutil.rmtree(self.tmp, ignore_errors=True)
        total = self.passed + len(self.failed)
        if total == 0:
            print("[VOID] %s — проб исполнено 0" % self.name, file=sys.stderr)
            return 2
        if self.failed:
            print("[FAIL] %s — проб %d, пройдено %d, провалено %d" % (self.name, total, self.passed, len(self.failed)),
                  file=sys.stderr)
            for f in self.failed:
                print("        " + f, file=sys.stderr)
            return 1
        print("[PASS] %s — проб %d, пройдено %d, провалено 0" % (self.name, total, self.passed))
        return 0


def main(name, body):
    try:
        pr = Probe(name)
    except Void as e:
        print("[VOID] %s — %s" % (name, e), file=sys.stderr)
        return 2
    try:
        body(pr)
    except Void as e:
        shutil.rmtree(pr.tmp, ignore_errors=True)
        print("[VOID] %s — %s" % (name, e), file=sys.stderr)
        return 2
    return pr.finish()


def writes(st):
    """Изменяющие вызовы трекера из журнала двойника."""
    return [e for e in st.get("log", []) if e["method"] != "GET"]
