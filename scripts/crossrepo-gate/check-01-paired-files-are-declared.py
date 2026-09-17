#!/usr/bin/env python3
"""check-01 — одноимённый файл в двух стволах объявлен решением, а не молчанием.

ЗАЧЕМ ЭТА ПРОВЕРКА СУЩЕСТВУЕТ

Запрет #20: файл, чей владелец — другой репозиторий, в этом дереве не лежит.
Правило само называло своего держателя: «сегодня — НИЧЕМ, гейта на парные файлы
между репозиториями в дереве нет; он выразим и заводится своим изменением»
(`.claude/rules/polyrepo.md` §«Копия между репозиториями ЗАПРЕЩЕНА»). Это он.

ПОЧЕМУ ГЕЙТ ЖИВЁТ В ВОРКСПЕЙСЕ

Пара — свойство ДВУХ деревьев, и ни одно из них себя с соседом не сверяет by
construction: каждое по отдельности исправно. Воркспейс — единственное место, где
под рукой все три клона (`project/<репо>`), поэтому дом проверки здесь.

ЧТО СЧИТАЕТСЯ ПАРОЙ

Одинаковый ОТСЛЕЖИВАЕМЫЙ путь, лежащий более чем в одном стволе. Единица счёта —
ПУТЬ, не «контракт» и не «инструмент»: пары считаются механически, а классами их
делит уже ведомость.

Совпадение содержимого пару НЕ снимает и нарушением не смягчает: одинаковы копии
сегодня, а держателя у одинаковости нет ни одного — расхождение наступит молча.
Поэтому содержимое читается ТОЛЬКО ради одной находки: решение `own` («предмет
разный») на побайтово совпадающей паре само себе противоречит.

ЧТО НАХОДКА

  1. пара в деревьях, которой нет в ведомости — молчаливая копия;
  2. запись ведомости, которой в деревьях не соответствует пара — САМОИСТЕЧЕНИЕ:
     послабление, которому нечего прощать, не истечёт больше никогда;
  3. решение вне закрытого словаря либо `debt` без задачи — долг без ответственного;
  4. `own` на побайтово совпадающей паре — два утверждения, из которых верно одно.

ТРЕТЬЯ КАТЕГОРИЯ

Нет клона хотя бы одного репозитория либо не резолвится его ствол — **VOID**:
пары считать не по чему, и «находок ноль» здесь означало бы «ноль прочитанного».

Исходы: 0 — каждая пара объявлена; 1 — есть находка; 2 — считать нечем.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs-gate"))
import _lib  # noqa: E402

NAME = "check-01-paired-files-are-declared"

# REPOS — закрытый перечень репозиториев продукта. Пустым он быть не может: ноль
# деревьев означал бы ноль пар при любом состоянии мира.
REPOS = ("kacho", "kaname", "corelib")

LEDGER = "docs/crossrepo-pairs.yaml"

# DECISIONS — закрытый словарь решений. Решение вне словаря — находка: иначе
# запись «решим потом» была бы неотличима от решения.
DECISIONS = ("vendored", "own", "debt")


def clone(root, name):
    """Путь клона репозитория либо None."""
    env = os.environ.get("KACHO_HOME_" + name.upper().replace("-", "_"))
    if env and os.path.exists(os.path.join(env, ".git")):
        return env
    guess = os.path.join(root, "project", name)
    if os.path.exists(os.path.join(guess, ".git")):
        return guess
    return None


def trunk_paths(repo, ref):
    out = subprocess.run(["git", "-C", repo, "ls-tree", "-r", ref, "--name-only"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return {p for p in out.stdout.split("\n") if p}


def blob_id(repo, ref, path):
    out = subprocess.run(["git", "-C", repo, "rev-parse", "%s:%s" % (ref, path)],
                         capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def parse_ledger(text):
    """{путь: (решение, задача, строка)} — записи ведомости."""
    entries, cur, line_no = {}, None, 0
    for i, raw in enumerate(text.split("\n"), 1):
        s = raw.strip()
        if s.startswith("- path:"):
            if cur:
                entries[cur[0]] = (cur[1], cur[2], line_no)
            cur = [s.split(":", 1)[1].strip(), "", ""]
            line_no = i
        elif cur is not None and s.startswith("decision:"):
            cur[1] = s.split(":", 1)[1].strip()
        elif cur is not None and s.startswith("issue:"):
            cur[2] = s.split(":", 1)[1].strip()
    if cur:
        entries[cur[0]] = (cur[1], cur[2], line_no)
    return entries


def main():
    root = _lib.workspace_root()

    trees, missing = {}, []
    for name in REPOS:
        path = clone(root, name)
        if path is None:
            missing.append(name)
            continue
        ref = _lib.provenance(path)["ref"]
        if not ref:
            missing.append(name + " (ствол не резолвится)")
            continue
        paths = trunk_paths(path, ref)
        if paths is None:
            missing.append(name + " (ствол не читается)")
            continue
        trees[name] = (path, ref, paths)

    if missing:
        _lib.void(NAME, "клонов нет либо ствол не резолвится: %s — пары считать не по чему. "
                        "Условие создаётся клоном в project/<репо> либо переменной "
                        "KACHO_HOME_<РЕПО>" % ", ".join(missing))
        return 2

    every = set()
    for _, _, paths in trees.values():
        every |= paths
    pairs = {}
    for p in sorted(every):
        holders = [n for n in trees if p in trees[n][2]]
        if len(holders) > 1:
            pairs[p] = holders

    ledger_text = _lib.read(root, LEDGER)
    if ledger_text is None:
        _lib.void(NAME, "ведомость %s не прочитана — судить пары не по чему" % LEDGER)
        return 2
    declared = parse_ledger(ledger_text)

    _lib.census("%s: стволов прочитано %d (%s); отслеживаемых путей %d; ПАР %d; "
                "записей ведомости %d"
                % (NAME, len(trees),
                   ", ".join("%s=%d" % (n, len(trees[n][2])) for n in REPOS),
                   len(every), len(pairs), len(declared)))

    if not every:
        _lib.void(NAME, "обход пуст — ни одного отслеживаемого пути ни в одном стволе")
        return 2

    findings = []
    for p, holders in sorted(pairs.items()):
        if p not in declared:
            findings.append("%s — пара в стволах %s НЕ объявлена: копия, о которой никто "
                            "не решал. Исходы: один владелец и пин · осознанное расхождение "
                            "(own) · ввезённое чужое (vendored) · признанный долг с задачей "
                            "(debt)" % (p, "+".join(holders)))
            continue
        decision, issue, _ = declared[p]
        if decision not in DECISIONS:
            findings.append("%s — решение %r вне словаря %s" % (p, decision, list(DECISIONS)))
            continue
        if decision == "debt" and not issue:
            findings.append("%s — признан долгом и не называет задачи: за долгом никто "
                            "не отвечает" % p)
            continue
        if decision == "own":
            ids = {blob_id(trees[n][0], trees[n][1], p) for n in holders}
            if len(ids) == 1:
                findings.append("%s — объявлен `own` («предмет разный»), а содержимое в "
                                "%s ПОБАЙТОВО совпадает: два утверждения, из которых верно "
                                "одно" % (p, "+".join(holders)))

    for p in sorted(declared):
        if p not in pairs:
            findings.append("%s — запись ведомости, которой в стволах не соответствует пара: "
                            "самоистечение. Снимите запись тем же изменением, которым снят её "
                            "предмет" % p)

    if findings:
        for f in findings:
            _lib.fail(NAME, f)
        return 1

    _lib.passed(NAME, "все %d пар объявлены решением, записей без предмета нет" % len(pairs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
