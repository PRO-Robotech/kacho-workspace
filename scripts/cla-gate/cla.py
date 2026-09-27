#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""cla.py — ведомость соглашения о вкладе воркспейса и ЕДИНСТВЕННОЕ суждение по ней.

Один читатель ведомости на три вопроса, и второго перечня личностей в дереве нет:
второй перечень разошёлся бы с первым молча (ws#729 п.4).

    tree        гейт дерева (ws#731): вклады в истории области — автор и соавтор из
                завершающего блока трейлеров — подтверждены ведомостью; запись без
                предмета — находка; объём осмотренного печатается всегда.
    push-range  суждение хука отправки (ws#729, ws#700): по каждому коммиту,
                который ОТПРАВКА ОПУБЛИКУЕТ (строки pre-push на stdin), автор,
                коммиттер и соавторы — личности ведомости. Судится диапазон, а не
                рабочее дерево и не `git config`: подстановка адреса окружением
                сильнее настройки и видна только в самом коммите.
    census      то же суждение, что push-range, по произвольному диапазону
                (`census -- --branches --not --remotes`): что отказала бы отправка.

ФОРМА ВЕДОМОСТИ — по соседу (`kaname/cla-ledger.yaml`, `tools/clagate`), не копией
байтов: одноимённый отслеживаемый путь в двух стволах запрещён, поэтому файл
называется иначе (`contribution-ledger.yaml`). Общее с соседом: закрытый словарь
разделов `owners` · `signatories` · `waivers`, обязательная причина у каждой записи,
область ОТНОСИТЕЛЬНО САМОЙ ВЕДОМОСТИ, единица счёта — адрес, а не имя; вклад — автор
и соавтор (`Co-authored-by`), коммиттер вкладчиком не считается; подтверждение —
запись либо `Signed-off-by` СВОЕЙ личности; `owners` из самоистечения исключены (это
политика, а не послабление), записи `signatories`/`waivers` без предмета — находка.

ОТЛИЧИЕ ОТ СОСЕДА ОДНО, И ОНО ОБЪЯВЛЕНО: `history_floor`. История воркспейса несёт
адреса, которых этот файл классифицировать не вправе (перепись в самой ведомости):
отнести личность к своим, подписавшим или машинным — решение владельца. Граница
делит историю на судимую (после неё — строго) и перечисляемую (до неё — вердикт НЕ
выносится, но каждый адрес без записи назван числом). Граница самоистекает: когда за
ней не останется ни одного вклада без записи, она сама становится находкой.

СУЖДЕНИЕ ОТПРАВКИ СТРОЖЕ СУЖДЕНИЯ ДЕРЕВА — по роли:
    автор      своя личность · подписавший · Signed-off-by этой же личности
    коммиттер  своя личность · подписавший
    соавтор    своя личность · подписавший · освобождённый · Signed-off-by
Освобождение (`waivers`) отвечает на вопрос соглашения — «нужна ли подпись под
этим вкладом», — а не на вопрос подписи коммита: машинная личность, подписавшая
отправляемый коммит, и есть подстановка, которую ловит ws#700.

Исходы: 0 — находок нет, объём назван; 1 — находка (либо ведомость негодна, либо
обход пуст); 2 — без предмета (условие не создано: история не несёт границы,
git не отвечает). Хук отправки читает 2 как отказ: «проверить было нечем» — не проход.
"""

import argparse
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

LEDGER = "contribution-ledger.yaml"
ZERO = "0" * 40
SECTIONS = ("owners", "signatories", "waivers")
TOP_KEYS = {"scope", "history_floor"} | set(SECTIONS)
ENTRY_KEYS = {"email", "note"}
FLOOR_KEYS = {"commit", "note"}

ROLE_AUTHOR, ROLE_COMMITTER, ROLE_COAUTHOR = "автор", "коммиттер", "соавтор"

# Разрешения по роли. ОДНА таблица на оба суждения — вторая копия разошлась бы.
ALLOW = {
    "tree": {
        ROLE_AUTHOR: ("owners", "signatories", "waivers", "signoff"),
        ROLE_COAUTHOR: ("owners", "signatories", "waivers", "signoff"),
    },
    "push": {
        ROLE_AUTHOR: ("owners", "signatories", "signoff"),
        ROLE_COMMITTER: ("owners", "signatories"),
        ROLE_COAUTHOR: ("owners", "signatories", "waivers", "signoff"),
    },
}

# Разделители — управляющие символы: тело трейлера и имя содержат пробелы и
# переводы строк. Трейлер разбирает САМ git (`%(trailers:key=…)`): завершающий
# блок и регистр ключа — по его правилам, а не по самописному разбору, и строка в
# прозе тела трейлером не становится.
FMT = ("%H%x1f%an%x1f%ae%x1f%cn%x1f%ce%x1f"
       "%(trailers:key=Co-authored-by,valueonly,separator=%x1e)%x1f"
       "%(trailers:key=Signed-off-by,valueonly,separator=%x1e)%x1d")


class Unjudgeable(Exception):
    """Условие не создано — исход 2."""


class LedgerDefect(Exception):
    """Ведомость негодна — исход 1: она часть дерева, а не внешнее условие."""


def git_env():
    # Переменные git сильнее рабочего каталога: унаследованный от хука `GIT_DIR`
    # увёл бы суждение в ЧУЖОЙ репозиторий, и вердикт выглядел бы обычным.
    env = {k: v for k, v in os.environ.items()
           if k not in ("GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_PREFIX")}
    env["GIT_TERMINAL_PROMPT"] = "0"
    return env


def git(root, *args, check=True):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, env=git_env())
    if check and r.returncode != 0:
        raise Unjudgeable("git %s: код %d: %s" % (" ".join(args[:3]), r.returncode, r.stderr.strip()))
    return r


def norm(s):
    return (s or "").strip().lower()


EMAIL_RE = re.compile(r"<([^<>]+)>\s*$")


def email_of(value):
    v = value.strip()
    m = EMAIL_RE.search(v)
    if m:
        return norm(m.group(1)), v[:m.start()].strip()
    if "@" in v and not re.search(r"\s", v):
        return norm(v), ""
    return "", v


# ── ведомость ────────────────────────────────────────────────────────────────

def load_ledger(root, rel=LEDGER):
    """Ведомость, сведённая к адресам. Любой дефект — LedgerDefect со ВСЕМИ причинами."""
    try:
        import yaml  # noqa: WPS433 — зависимость объявлена в шапке набора
    except ImportError as e:
        raise Unjudgeable("разборщик YAML (python3-yaml) не установлен: %s" % e)
    path = os.path.join(root, rel)
    try:
        with open(path, encoding="utf-8") as f:
            raw = yaml.safe_load(f)
    except FileNotFoundError:
        raise LedgerDefect("ведомости %s в дереве нет — различать своего и чужого нечем" % rel)
    except yaml.YAMLError as e:
        raise LedgerDefect("ведомость %s не разобрана: %s" % (rel, e))
    problems = []
    if not isinstance(raw, dict):
        raise LedgerDefect("ведомость %s — не словарь разделов" % rel)
    unknown = set(raw) - TOP_KEYS
    if unknown:
        # Принятое-и-проигнорированное: ключ, который ведомость объявляет, а
        # суждение не читает, выглядел бы действующим.
        problems.append("неизвестные разделы %s — словарь закрыт: %s" % (sorted(unknown), sorted(TOP_KEYS)))
    led = {"path": rel, "scope": [], "floor": None, "floor_note": "", "by_email": {}}
    for s in SECTIONS:
        led[s] = {}
        entries = raw.get(s) or []
        if not isinstance(entries, list):
            problems.append("%s: не список записей" % s)
            continue
        for i, e in enumerate(entries):
            if not isinstance(e, dict):
                problems.append("%s[%d]: запись не словарь" % (s, i))
                continue
            extra = set(e) - ENTRY_KEYS
            if extra:
                problems.append("%s[%d]: неизвестные поля %s" % (s, i, sorted(extra)))
            em = norm(e.get("email"))
            if not em:
                problems.append("%s[%d]: запись без адреса — покрывать нечего" % (s, i))
                continue
            if not str(e.get("note") or "").strip():
                problems.append("%s: запись %s без названной причины — «не спрашиваем» без "
                                "основания и есть искомый дефект" % (s, em))
                continue
            if em in led["by_email"]:
                problems.append("%s: адрес %s уже объявлен в %s — у личности одно основание"
                                % (s, em, led["by_email"][em]))
                continue
            led[s][em] = e
            led["by_email"][em] = s
    if not led["owners"]:
        problems.append("owners пуст — своей личности нет, различать своего и чужого нечем")
    ledger_dir = os.path.dirname(rel)
    scope = raw.get("scope")
    if not isinstance(scope, list) or not scope:
        problems.append("scope не назван — обход был бы пуст, а вердикт беспредметен")
    else:
        for p in scope:
            joined = os.path.normpath(os.path.join(ledger_dir, str(p)))
            if joined.startswith(".."):
                problems.append("область %r уводит за корень дерева" % p)
                continue
            if not os.path.exists(os.path.join(root, joined)):
                problems.append("область %r в дереве не разрешается — обход был бы пуст" % p)
                continue
            led["scope"].append(joined)
    fl = raw.get("history_floor")
    if fl is not None:
        if not isinstance(fl, dict) or set(fl) - FLOOR_KEYS:
            problems.append("history_floor: ожидались поля %s" % sorted(FLOOR_KEYS))
        else:
            c = str(fl.get("commit") or "").strip()
            if not re.fullmatch(r"[0-9a-f]{40}", c):
                problems.append("history_floor.commit — не полная sha: %r" % c)
            elif not str(fl.get("note") or "").strip():
                problems.append("history_floor без причины")
            else:
                led["floor"], led["floor_note"] = c, str(fl["note"])
    if problems:
        raise LedgerDefect("ведомость %s негодна:\n  " % rel + "\n  ".join(problems))
    return led


# ── история ──────────────────────────────────────────────────────────────────

class Rec:
    __slots__ = ("sha", "an", "ae", "cn", "ce", "coauthors", "signoffs")


def walk_paths(scope):
    """Пути для `git log` либо None — «вся история».

    Область `.` — это ВСЁ дерево, и pathspec ей не передаётся: `git log -- .`
    упрощает историю — снимает пустые коммиты, слияние, совпавшее деревом с одним
    из родителей, и ветку, влитую `-s ours`. Каждая из этих форм — вклад, и
    суждение, прошедшее мимо неё, выносило «подтверждено» о непрочитанном
    (перепись давала «коммитов 6» там, где `census` на том же диапазоне — 8).
    """
    if not scope or any(p in (".", "") for p in scope):
        return None
    return scope


def commits(root, revs, paths=None):
    # Порядок и адреса — ИЗ КОММИТА: `%ae`/`%ce`, а не `%aE`/`%cE`, которые
    # подменяются `.mailmap` дерева (замок — проба E5m в inject).
    args = ["log", "--format=" + FMT, *revs]
    if paths:
        # Область уже дерева: коммит вне неё не судится, но слияния и боковые
        # ветки внутри неё — судятся, упрощение истории снимается.
        args += ["--full-history", "--", *paths]
    out = git(root, *args).stdout
    recs = []
    for chunk in out.split("\x1d"):
        chunk = chunk.lstrip("\n")
        if not chunk:
            continue
        f = chunk.split("\x1f")
        if len(f) != 7:
            raise Unjudgeable("запись git log не разобрана (%d полей вместо 7)" % len(f))
        r = Rec()
        r.sha, r.an, r.ae, r.cn, r.ce = f[0], f[1], norm(f[2]), f[3], norm(f[4])
        r.coauthors = [email_of(v) for v in f[5].split("\x1e") if v.strip()]
        r.signoffs = {email_of(v)[0] for v in f[6].split("\x1e") if v.strip()}
        recs.append(r)
    return recs


def contributions(r, mode):
    out = []
    roles = ALLOW[mode]
    if ROLE_AUTHOR in roles:
        out.append((ROLE_AUTHOR, r.an, r.ae))
    if ROLE_COMMITTER in roles:
        out.append((ROLE_COMMITTER, r.cn, r.ce))
    seen = {r.ae}
    for em, name in r.coauthors:
        if not em or em in seen:
            continue
        seen.add(em)
        out.append((ROLE_COAUTHOR, name, em))
    return out


def judge(recs, led, mode):
    """Находки, счётчики, использованные записи — по таблице ALLOW."""
    findings, used = [], set()
    by = Counter()
    ids = set()
    for r in recs:
        for role, name, em in contributions(r, mode):
            by["вкладов"] += 1
            by[role] += 1
            ids.add(em)
            basis = None
            for how in ALLOW[mode][role]:
                if how == "signoff":
                    if em in r.signoffs:
                        basis = how
                        break
                elif em in led[how]:
                    basis = how
                    break
            if basis is None:
                findings.append((r.sha, role, name, em))
                continue
            by[basis] += 1
            if basis in ("signatories", "waivers"):
                used.add(em)
    return findings, by, ids, used


def print_findings(findings, limit=40, prefix=""):
    for sha, role, name, em in findings[:limit]:
        print("%s  %s %s «%s <%s>» — личности нет в ведомости" % (prefix, sha[:12], role, name, em),
              file=sys.stderr)
    if len(findings) > limit:
        print("%s  … и ещё %d" % (prefix, len(findings) - limit), file=sys.stderr)
    per = Counter(em for _, _, _, em in findings)
    print("%s  личностей вне ведомости: %d" % (prefix, len(per)), file=sys.stderr)
    for em, n in sorted(per.items()):
        print("%s    %s — вкладов %d" % (prefix, em, n), file=sys.stderr)


# ── режим tree ───────────────────────────────────────────────────────────────

def run_tree(root, rel):
    led = load_ledger(root, rel)
    scope = led["scope"]
    print("[CENSUS] cla-gate: ведомость %s — своих %d, подписавших %d, освобождённых %d; "
          "область %s" % (rel, len(led["owners"]), len(led["signatories"]), len(led["waivers"]), scope))
    paths = walk_paths(scope)
    whole = commits(root, ["HEAD"], paths)
    if not whole:
        raise LedgerDefect("у области %s нет ни одного коммита во всей истории HEAD — гейт слеп" % scope)
    floor = led["floor"]
    if floor:
        if git(root, "cat-file", "-e", floor + "^{commit}", check=False).returncode != 0:
            raise Unjudgeable("граница %s в истории этого клона отсутствует (срез глубины?) — "
                              "судимый диапазон не построить" % floor[:12])
        if git(root, "merge-base", "--is-ancestor", floor, "HEAD", check=False).returncode != 0:
            raise LedgerDefect("граница %s не предок HEAD — ведомость называет чужую историю" % floor[:12])
        judged = commits(root, [floor + "..HEAD"], paths)
        rng = "%s..HEAD" % floor[:12]
    else:
        judged, rng = whole, "HEAD (вся история)"
    if not judged:
        raise LedgerDefect("обход пуст: диапазон %s в области %s не несёт ни одного коммита — "
                           "граница названа на голове или за ней" % (rng, scope))

    findings, by, ids, _ = judge(judged, led, "tree")
    # Предмет записи ищется во ВСЕЙ истории области: освобождение, чей вклад лежит
    # за границей, предмет имеет — граница снимает вердикт, а не историю.
    _, _, _, used_all = judge(whole, led, "tree")
    print("[CENSUS] cla-gate: судимый диапазон %s — коммитов %d, вкладов %d (автор %d, соавтор %d), "
          "личностей %d; своих %d, по ведомости %d, освобождено %d, подписью %d"
          % (rng, len(judged), by["вкладов"], by[ROLE_AUTHOR], by[ROLE_COAUTHOR], len(ids),
             by["owners"], by["signatories"], by["waivers"], by["signoff"]))

    bad = 0
    if floor:
        before = commits(root, [floor], paths)
        bf, bby, _, _ = judge(before, led, "tree")
        per = defaultdict(Counter)
        for _, role, _, em in bf:
            per[em][role] += 1
        print("[CENSUS] cla-gate: ЗА ГРАНИЦЕЙ (история до %s включительно, вердикт НЕ выносится) — "
              "коммитов %d, вкладов %d, без записи %d, личностей без записи %d"
              % (floor[:12], len(before), bby["вкладов"], len(bf), len(per)))
        for em in sorted(per):
            c = per[em]
            print("    %s — вкладов %d (автор %d, соавтор %d)"
                  % (em, sum(c.values()), c[ROLE_AUTHOR], c[ROLE_COAUTHOR]))
        if not bf:
            bad += 1
            print("[FAIL] cla-gate — граница %s больше ничего не прикрывает: за ней нет ни одного "
                  "вклада без записи. Снимите history_floor — судиться будет вся история"
                  % floor[:12], file=sys.stderr)

    if findings:
        bad += 1
        print("[FAIL] cla-gate — вклады без подтверждения соглашения в диапазоне %s: %d"
              % (rng, len(findings)), file=sys.stderr)
        print_findings(findings)
    for s in ("signatories", "waivers"):
        for em in sorted(led[s]):
            if em not in used_all:
                bad += 1
                print("[FAIL] cla-gate — %s: %s — записи нечего покрывать во всей истории области; "
                      "снимите её, иначе она молча покроет следующего с этим адресом" % (s, em),
                      file=sys.stderr)
    if bad:
        return 1
    print("[PASS] cla-gate — в диапазоне %s каждый вклад подтверждён; записей без предмета нет"
          % rng)
    return 0


# ── режимы push-range и census ───────────────────────────────────────────────

def dirty_ledger_note(root, rel):
    r = git(root, "diff", "--quiet", "HEAD", "--", rel, check=False)
    if r.returncode == 1:
        print("pre-push: ВНИМАНИЕ — ведомость %s в рабочем дереве отличается от закоммиченной; "
              "суждение вынесено по рабочему дереву" % rel, file=sys.stderr)


def judge_push(root, rel, positives, negatives, label):
    led = load_ledger(root, rel)
    recs = commits(root, [*positives, "--not", *negatives, "--remotes"]) if positives else []
    findings, by, ids, _ = judge(recs, led, "push")
    print("%s — публикуемых коммитов %d, вкладов %d (автор %d, коммиттер %d, соавтор %d), "
          "личностей %d; ведомость %s" % (label, len(recs), by["вкладов"], by[ROLE_AUTHOR],
                                          by[ROLE_COMMITTER], by[ROLE_COAUTHOR], len(ids), rel),
          file=sys.stderr)
    dirty_ledger_note(root, rel)
    if findings:
        print("pre-push: ОТКАЗ — отправка опубликовала бы подпись вне ведомости (%d):"
              % len(findings), file=sys.stderr)
        print_findings(findings)
        print("  Чинится ПЕРЕПОДПИСЬЮ неотправленного (git rebase -x 'git commit --amend "
              "--no-edit --reset-author' <база>) либо записью в %s с причиной — не обходом."
              % rel, file=sys.stderr)
        return 1
    return 0


def run_push_range(root, rel, remote, lines):
    positives, negatives, refs, deletions = [], [], 0, 0
    for ln in lines:
        parts = ln.split()
        if len(parts) != 4:
            if ln.strip():
                raise Unjudgeable("строка pre-push не разобрана: %r" % ln)
            continue
        _lref, lsha, _rref, rsha = parts
        refs += 1
        if lsha == ZERO:
            deletions += 1
            continue
        positives.append(lsha)
        if rsha != ZERO and git(root, "cat-file", "-e", rsha + "^{commit}", check=False).returncode == 0:
            negatives.append(rsha)
    label = "pre-push: подпись и ведомость (%s) — ссылок %d, снятий %d" % (remote or "?", refs, deletions)
    return judge_push(root, rel, positives, negatives, label)


def run_census(root, rel, revs):
    led = load_ledger(root, rel)
    recs = commits(root, revs)
    findings, by, ids, _ = judge(recs, led, "push")
    print("[CENSUS] cla census %s — коммитов %d, вкладов %d, личностей %d; вне ведомости %d"
          % (" ".join(revs), len(recs), by["вкладов"], len(ids), len(findings)))
    if findings:
        print_findings(findings)
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("mode", choices=("tree", "push-range", "census"))
    ap.add_argument("--root", default=None, help="корень судимого дерева (по умолчанию — рабочая копия)")
    ap.add_argument("--ledger", default=LEDGER)
    ap.add_argument("--remote", default="")
    ap.add_argument("revs", nargs="*")
    a = ap.parse_args()
    root = a.root
    try:
        if root is None:
            root = git(os.getcwd(), "rev-parse", "--show-toplevel").stdout.strip()
        if a.mode == "tree":
            return run_tree(root, a.ledger)
        if a.mode == "push-range":
            return run_push_range(root, a.ledger, a.remote, sys.stdin.read().splitlines())
        if not a.revs:
            raise Unjudgeable("census без диапазона — судить нечего")
        return run_census(root, a.ledger, a.revs)
    except LedgerDefect as e:
        print("[FAIL] cla-gate — %s" % e, file=sys.stderr)
        return 1
    except Unjudgeable as e:
        print("[VOID] cla-gate — условие не создано: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
