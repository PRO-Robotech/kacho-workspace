"""Общие помощники набора suites-gate. Только для импорта.

Предмет набора — свойства, общие ВСЕМ наборам проверок воркспейса: откуда проверка
берёт корень, различает ли она «ноль осмотренного» и «ноль находок», печатает ли
объём, зовёт ли конвейер каждый набор, различимы ли адреса проверок, держатся ли
числа в шапках, не берётся ли вердикт из трубы, задаёт ли доказательство своё
окружение. Каждое из них прежде держалось вниманием того, кто писал очередной набор.

Перепись наборов и проверок — `scripts/lib/suites.py`, корень — `scripts/lib/gate_root.py`:
у набора нет своей копии ни того, ни другого.
"""
import os
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "lib"))

import gate_root as _gate_root  # noqa: E402
import suites as S  # noqa: E402

SUITE_VAR = "SUITES_GATE_ROOT"


def root(check_file):
    """Корень, который судит проверка. Не выводится — VOID с причиной."""
    try:
        return _gate_root.gate_root(SUITE_VAR, check_file)
    except _gate_root.RootUnresolved as exc:
        void(os.path.basename(check_file), str(exc))
        sys.exit(2)


def census(name, text):
    print("[CENSUS] %s: %s" % (name, text))


def passed(name, text):
    print("[PASS] %s — %s" % (name, text))


def fail(name, text):
    print("[FAIL] %s — %s" % (name, text), file=sys.stderr)


def finding(text):
    print("  находка: %s" % text, file=sys.stderr)


def void(name, text):
    print("[VOID] %s — %s" % (name, text), file=sys.stderr)


def suite_census(name, ws):
    """(наборы, {набор: [проверки]}) либо VOID при несчитанной переписи."""
    try:
        names = S.suites(ws)
        return names, {s: S.checks(ws, s) for s in names}
    except S.CensusUnreadable as exc:
        void(name, "перепись наборов не снята: %s" % exc)
        sys.exit(2)


# ── Пустой мир: одна и та же проба для ws#757 и ws#762 ──────────────────────
#
# Проверку направляют на ПУСТОЕ дерево общим переопределением `GATE_ROOT`, сняв
# все прочие указатели на деревья: переопределения наборов (`*GATE_ROOT`) и
# клоны продукта (`KACHO_MONOREPO`, `KACHO_HOME_*`). Иначе проверка, чей предмет —
# дерево продукта, судила бы настоящий клон, и «пусто» было бы неправдой.

STRIPPED_PREFIXES = ("KACHO_MONOREPO", "KACHO_HOME_")
# Окружение git снимается (`S.clean_env`): `git push` выставляет `GIT_DIR`, и
# переменная сильнее рабочего каталога — проба судила бы рабочую копию, а
# `git init` пустого мира писал бы в неё.
TIMEOUT = 900
clean_env = S.clean_env


def empty_world(tmp_parent=None):
    """Пустой git-репозиторий: корень, в котором нечего осматривать."""
    d = tempfile.mkdtemp(prefix="empty-world.", dir=tmp_parent)
    subprocess.run(["git", "-C", d, "init", "-q"], check=True, env=clean_env())
    return d


def world_env(empty):
    env = {k: v for k, v in clean_env().items()
           if not k.endswith("GATE_ROOT") and not k.startswith(STRIPPED_PREFIXES)}
    env["GATE_ROOT"] = empty
    return env


def run_check(ws, rel, cwd, env):
    """Код выхода проверки; 'timeout' при превышении предела."""
    return run_check_output(ws, rel, cwd, env)[0]


def run_check_output(ws, rel, cwd, env):
    """(код выхода либо 'timeout', объединённый вывод stdout и stderr)."""
    try:
        out = subprocess.run(S.interpreter(os.path.join(ws, rel)), cwd=cwd, env=env,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return "timeout", ""
    return out.returncode, out.stdout.decode("utf-8", "replace")
