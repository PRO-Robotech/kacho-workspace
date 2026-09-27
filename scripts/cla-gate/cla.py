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
                (`census -- <ветка> --not --glob=refs/remotes/origin/*`): что отказала бы отправка.

ФОРМА ВЕДОМОСТИ — по соседу (`kaname/cla-ledger.yaml`, `tools/clagate`), не копией
байтов: одноимённый отслеживаемый путь в двух стволах запрещён, поэтому файл
называется иначе (`contribution-ledger.yaml`). Общее с соседом: закрытый словарь
разделов `owners` · `signatories` · `waivers`, обязательная причина у каждой записи,
область ОТНОСИТЕЛЬНО САМОЙ ВЕДОМОСТИ, единица счёта — адрес, а не имя; вклад — автор
и соавтор (`Co-authored-by`), коммиттер вкладчиком не считается; подтверждение —
запись либо `Signed-off-by` СВОЕЙ личности; `owners` из самоистечения исключены (это
политика, а не послабление), записи `signatories`/`waivers` без предмета — находка.

ОТЛИЧИЕ ОТ СОСЕДА, И ОНО ОБЪЯВЛЕНО: раздел `history_only` и граница
`history_floor`. История воркспейса несёт адреса, которые владелец отнёс к «только
история, вперёд запрет» (решение 2026-09-27, цитаты — в самой ведомости). Запись
`history_only` покрывает вклад ТОЛЬКО в коммитах, достижимых из границы; тот же адрес
в коммите после неё — находка, как если бы записи не было. Судится ВСЯ история:
до границы — по всем разделам, после — без `history_only`. Самоистечение: запись
`history_only` без вклада до границы — находка; граница без единой такой записи —
находка («больше ничего не разделяет»).

СУЖДЕНИЕ ОТПРАВКИ СТРОЖЕ СУЖДЕНИЯ ДЕРЕВА — по роли (для коммитов после границы;
история, опубликованная заново, судится как история):
    автор      своя личность · подписавший · Signed-off-by этой же личности
    коммиттер  своя личность · подписавший
    соавтор    своя личность · подписавший · освобождённый · Signed-off-by —
               по вопросу соглашения; сам ключ атрибуции (Co-authored-by,
               Claude-Session) в строке сообщения — отказ по имени ключа
               независимо от ведомости
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
SECTIONS = ("owners", "signatories", "waivers", "history_only")
TOP_KEYS = {"scope", "history_floor"} | set(SECTIONS)
ENTRY_KEYS = {"email", "note"}
FLOOR_KEYS = {"commit", "note"}

ROLE_AUTHOR, ROLE_COMMITTER, ROLE_COAUTHOR = "автор", "коммиттер", "соавтор"
ROLE_ATTRIBUTION = "атрибуция"

# Разрешения по роли. ОДНА таблица на все суждения — вторая копия разошлась бы.
# «history» — коммиты, достижимые из границы: только там действует `history_only`,
# и коммиттер там не судится (схлопывания GitHub подписаны сервером).
ALLOW = {
    "history": {
        ROLE_AUTHOR: ("owners", "signatories", "waivers", "history_only", "signoff"),
        ROLE_COAUTHOR: ("owners", "signatories", "waivers", "history_only", "signoff"),
    },
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
       "%(trailers:key=Signed-off-by,valueonly,separator=%x1e)%x1f%B%x1d")

# КЛЮЧИ АТРИБУЦИИ — запрет по ИМЕНИ КЛЮЧА, а не по адресу (git-issues.md,
# gi-no-attribution-trailers). Прежде трейлер ловился лишь тем, что его адреса нет
# в ведомости: освобождение адреса его пропускало, ключ без адреса (Claude-Session)
# не судился вовсе. Признак — строка сообщения, НАЧИНАЮЩАЯСЯ ключом, а не блок
# трейлеров git: абзац, где ключ соседствует с прозой, git трейлером не считает,
# а запрет от этого не слабеет. Упоминание внутри строки прозы — не находка.
# Судится только новое (после границы): история не переписывается (ws#730 п.4).
ATTRIBUTION_RE = re.compile(r"^(co-authored-by|claude-session)[ \t]*:", re.I | re.M)


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
    if led["history_only"] and not led["floor"] and not any("history_floor" in x for x in problems):
        problems.append("history_only без history_floor — «только история» нечем отличить от нового")
    if problems:
        raise LedgerDefect("ведомость %s негодна:\n  " % rel + "\n  ".join(problems))
    return led


# ── история ──────────────────────────────────────────────────────────────────

class Rec:
    __slots__ = ("sha", "an", "ae", "cn", "ce", "coauthors", "signoffs", "body")


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
        f = chunk.split("\x1f", 7)
        if len(f) != 8:
            raise Unjudgeable("запись git log не разобрана (%d полей вместо 8)" % len(f))
        r = Rec()
        r.sha, r.an, r.ae, r.cn, r.ce = f[0], f[1], norm(f[2]), f[3], norm(f[4])
        r.coauthors = [email_of(v) for v in f[5].split("\x1e") if v.strip()]
        r.signoffs = {email_of(v)[0] for v in f[6].split("\x1e") if v.strip()}
        r.body = f[7]
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
        if not em:
            # Значение без разборного адреса — не пропуск: вклад назван, а личность
            # не установлена (прежде такой соавтор отбрасывался молча).
            out.append((ROLE_COAUTHOR, name, ""))
            continue
        if em in seen:
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
                if not em:
                    why = "адрес соавтора не разобран — личность не установлена"
                elif em in led["history_only"]:
                    why = "адрес «только история» (history_only) — вперёд запрет"
                elif em in led["by_email"]:
                    why = "раздел %s этой роли не покрывает" % led["by_email"][em]
                else:
                    why = "личности нет в ведомости"
                findings.append((r.sha, role, name, em, why))
                continue
            by[basis] += 1
            if basis in ("signatories", "waivers", "history_only"):
                used.add(em)
        if mode != "history":
            for m in ATTRIBUTION_RE.finditer(r.body):
                line = r.body[m.start():].split("\n", 1)[0].strip()
                by["атрибуция"] += 1
                findings.append((r.sha, ROLE_ATTRIBUTION, line[:90], m.group(1),
                                 "ключ атрибуции «%s» запрещён независимо от ведомости "
                                 "(git-issues.md, gi-no-attribution-trailers)" % m.group(1)))
    return findings, by, ids, used


def floor_split(root, led, recs):
    """(история, новое): коммиты, достижимые из границы, и остальные."""
    floor = led["floor"]
    if not floor or not recs:
        return [], list(recs)
    if git(root, "cat-file", "-e", floor + "^{commit}", check=False).returncode != 0:
        raise Unjudgeable("граница %s в истории этого клона отсутствует (срез глубины?) — "
                          "историю от нового не отличить" % floor[:12])
    past = set(git(root, "rev-list", floor).stdout.split())
    return [r for r in recs if r.sha in past], [r for r in recs if r.sha not in past]


def judge_split(root, led, recs, mode):
    """Суждение с учётом границы: история — таблицей «history», новое — `mode`."""
    past, new = floor_split(root, led, recs)
    f1, by1, ids1, used1 = judge(past, led, "history")
    f2, by2, ids2, used2 = judge(new, led, mode)
    return past, new, f1 + f2, by1 + by2, ids1 | ids2, used1 | used2


def print_findings(findings, limit=40, prefix=""):
    for sha, role, name, em, why in findings[:limit]:
        if role == ROLE_ATTRIBUTION:
            print("%s  %s %s: строка «%s» — %s" % (prefix, sha[:12], role, name, why), file=sys.stderr)
        else:
            print("%s  %s %s «%s <%s>» — %s" % (prefix, sha[:12], role, name, em, why),
                  file=sys.stderr)
    if len(findings) > limit:
        print("%s  … и ещё %d" % (prefix, len(findings) - limit), file=sys.stderr)
    keys = Counter(f[3] for f in findings if f[1] == ROLE_ATTRIBUTION)
    if keys:
        print("%s  ключей атрибуции: %s" % (prefix, ", ".join("%s — %d" % kv for kv in sorted(keys.items()))),
              file=sys.stderr)
    per = Counter(f[3] or "<не разобран>" for f in findings if f[1] != ROLE_ATTRIBUTION)
    print("%s  личностей вне ведомости: %d" % (prefix, len(per)), file=sys.stderr)
    for em, n in sorted(per.items()):
        print("%s    %s — вкладов %d" % (prefix, em, n), file=sys.stderr)


# ── режим tree ───────────────────────────────────────────────────────────────

def run_tree(root, rel):
    led = load_ledger(root, rel)
    scope = led["scope"]
    print("[CENSUS] cla-gate: ведомость %s — своих %d, подписавших %d, освобождённых %d, "
          "«только история» %d; область %s" % (rel, len(led["owners"]), len(led["signatories"]),
                                                len(led["waivers"]), len(led["history_only"]), scope))
    paths = walk_paths(scope)
    whole = commits(root, ["HEAD"], paths)
    if not whole:
        raise LedgerDefect("у области %s нет ни одного коммита во всей истории HEAD — гейт слеп" % scope)
    floor = led["floor"]
    if floor and git(root, "cat-file", "-e", floor + "^{commit}", check=False).returncode == 0 and \
            git(root, "merge-base", "--is-ancestor", floor, "HEAD", check=False).returncode != 0:
        raise LedgerDefect("граница %s не предок HEAD — ведомость называет чужую историю" % floor[:12])
    past, new, findings, by, ids, used = judge_split(root, led, whole, "tree")
    print("[CENSUS] cla-gate: вся история HEAD — коммитов %d (история до границы %s включительно %d, "
          "после неё %d), вкладов %d (автор %d, соавтор %d), личностей %d; своих %d, по ведомости %d, "
          "освобождено %d, «только история» %d, подписью %d"
          % (len(whole), floor[:12] if floor else "—", len(past), len(new), by["вкладов"],
             by[ROLE_AUTHOR], by[ROLE_COAUTHOR], len(ids), by["owners"], by["signatories"],
             by["waivers"], by["history_only"], by["signoff"]))
    if led["history_only"]:
        per = Counter()
        for r in past:
            for role, _, em in contributions(r, "history"):
                if em in led["history_only"]:
                    per[em] += 1
        for em in sorted(led["history_only"]):
            print("    history_only %s — вкладов до границы %d" % (em, per[em]))

    bad = 0
    if findings:
        bad += 1
        print("[FAIL] cla-gate — вклады без подтверждения: %d" % len(findings), file=sys.stderr)
        print_findings(findings)
    for s_ in ("signatories", "waivers", "history_only"):
        for em in sorted(led[s_]):
            if em not in used:
                bad += 1
                where = "до границы" if s_ == "history_only" else "во всей истории области"
                print("[FAIL] cla-gate — %s: %s — записи нечего покрывать %s; снимите её, иначе "
                      "она молча покроет следующего с этим адресом" % (s_, em, where), file=sys.stderr)
    if floor and not led["history_only"]:
        bad += 1
        print("[FAIL] cla-gate — граница %s без единой записи history_only: она больше ничего не "
              "разделяет; снимите history_floor" % floor[:12], file=sys.stderr)
    if bad:
        return 1
    print("[PASS] cla-gate — вся история HEAD (%d коммитов) подтверждена ведомостью; записей без "
          "предмета нет" % len(whole))
    return 0


# ── режимы push-range и census ───────────────────────────────────────────────

def dirty_ledger_note(root, rel):
    r = git(root, "diff", "--quiet", "HEAD", "--", rel, check=False)
    if r.returncode == 1:
        print("pre-push: ВНИМАНИЕ — ведомость %s в рабочем дереве отличается от закоммиченной; "
              "суждение вынесено по рабочему дереву" % rel, file=sys.stderr)


REMOTE_NAME = re.compile(r"[A-Za-z0-9._-]+")


def published_on(root, remote):
    """Ссылки, которыми известно опубликованное НА ЭТОМ remote, — аргументы `git log`.

    Вычитается только отслеживаемое remote отправки. Прежде вычиталось `--remotes`
    — все remote сразу, — и чужой коммит, известный через ссылку ВТОРОГО remote,
    при отправке в первый не судился вовсе («публикуемых 0»), хотя в первом его
    нет. Отправка по URL (хук получает URL вместо имени) — вычитать нечего:
    остаётся только sha на сервере из строки отправки.
    """
    if not remote or not REMOTE_NAME.fullmatch(remote):
        return []
    if git(root, "config", "--get", "remote.%s.url" % remote, check=False).returncode != 0:
        return []
    return ["--glob=refs/remotes/%s/*" % remote]


def judge_push(root, rel, positives, negatives, label, remote=""):
    led = load_ledger(root, rel)
    recs = (commits(root, [*positives, "--not", *negatives, *published_on(root, remote)])
            if positives else [])
    past, _, findings, by, ids, _ = judge_split(root, led, recs, "push")
    print("%s — публикуемых коммитов %d (из них история до границы %d), вкладов %d (автор %d, "
          "коммиттер %d, соавтор %d), личностей %d; ведомость %s"
          % (label, len(recs), len(past), by["вкладов"], by[ROLE_AUTHOR], by[ROLE_COMMITTER],
             by[ROLE_COAUTHOR], len(ids), rel), file=sys.stderr)
    dirty_ledger_note(root, rel)
    if findings:
        print("pre-push: ОТКАЗ — отправка опубликовала бы подпись вне ведомости либо ключ "
              "атрибуции (%d):" % len(findings), file=sys.stderr)
        print_findings(findings)
        print("  Чинится ПЕРЕПОДПИСЬЮ неотправленного (git rebase -x 'git commit --amend "
              "--no-edit --reset-author' <база>), снятием ключа атрибуции из сообщения либо "
              "записью в %s с причиной — не обходом." % rel, file=sys.stderr)
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
    return judge_push(root, rel, positives, negatives, label, remote)


def run_census(root, rel, revs):
    led = load_ledger(root, rel)
    recs = commits(root, revs)
    past, _, findings, by, ids, _ = judge_split(root, led, recs, "push")
    print("[CENSUS] cla census %s — коммитов %d (история до границы %d), вкладов %d, личностей %d; "
          "находок %d" % (" ".join(revs), len(recs), len(past), by["вкладов"], len(ids), len(findings)))
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
