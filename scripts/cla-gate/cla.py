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
                сильнее настройки и видна только в самом коммите. Опубликованное
                спрашивается у СЕРВЕРА ОТПРАВКИ (`git ls-remote <url>`), а не у
                ссылок отслеживания: те — память о сервере ВЫБОРКИ и бывают
                устаревшими. Ведомость читается из ОТПРАВЛЯЕМОЙ ревизии, а не из
                рабочего дерева: незакоммиченная правка отправку не открывает.
    census      таблица суждения отправки по произвольному диапазону
                (`census -- <ветка> --not --glob=refs/remotes/origin/*`) — диагностика
                по ведомости РАБОЧЕГО дерева и по названным ссылкам. Вердиктом отправки
                она не является: отправка вычитает опубликованное у сервера отправки и
                судит ведомостью отправляемой ревизии.

ФОРМА ВЕДОМОСТИ — по соседу (`kaname/cla-ledger.yaml`, `tools/clagate`), не копией
байтов: одноимённый отслеживаемый путь в двух стволах запрещён, поэтому файл
называется иначе (`contribution-ledger.yaml`). Общее с соседом: закрытый словарь
разделов `owners` · `signatories` · `waivers`, обязательная причина у каждой записи,
область ОТНОСИТЕЛЬНО САМОЙ ВЕДОМОСТИ, единица счёта — адрес, а не имя; вклад — автор
и соавтор (`Co-authored-by`), коммиттер вкладчиком не считается; `owners` из
самоистечения исключены (это политика, а не послабление), записи
`signatories`/`waivers` без предмета — находка. Подтверждение `Signed-off-by` СВОЕЙ
личности, как у соседа, действует ТОЛЬКО в истории (до границы): вперёд — решение
владельца «только своя личность», перечень закрыт ведомостью (ws#729 п.1), а строку
сообщения дописывает кто угодно. Пустой адрес (`--author="X <>"`, неразборная
подпись) не совпадает ни с чем, в том числе с другим пустым адресом.

ОТЛИЧИЕ ОТ СОСЕДА, И ОНО ОБЪЯВЛЕНО (два раздела). Раздел `committers` — личности,
допустимые ТОЛЬКО в роли коммиттера: коммит произвёл сервер при посадке (ws#700:
«committer noreply@github.com у схлопывающих слияний … находкой НЕ является»).
Вкладчиком такая личность не является, автором и соавтором не покрыта; запись без
единого коммита с этим коммиттером во всей истории — находка.

Раздел `history_only` и граница
`history_floor`. История воркспейса несёт адреса, которые владелец отнёс к «только
история, вперёд запрет» (решение 2026-09-27, цитаты — в самой ведомости). Запись
`history_only` покрывает вклад ТОЛЬКО в коммитах, достижимых из границы; тот же адрес
в коммите после неё — находка, как если бы записи не было. Судится ВСЯ история:
до границы — по всем разделам, после — без `history_only`. Самоистечение: запись
`history_only` без вклада до границы — находка; граница без единой такой записи —
находка («больше ничего не разделяет»).

СУЖДЕНИЕ ОТПРАВКИ СТРОЖЕ СУЖДЕНИЯ ДЕРЕВА — по роли (для коммитов после границы;
история, опубликованная заново, судится как история):
    автор      своя личность · подписавший
    коммиттер  своя личность · подписавший · сервер посадки (`committers`)
    соавтор    своя личность · подписавший · освобождённый — по вопросу
               соглашения; сам ключ атрибуции (Co-authored-by, Claude-Session)
               в строке сообщения — отказ по имени ключа независимо от ведомости
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
SECTIONS = ("owners", "signatories", "waivers", "history_only", "committers")
# Разделы-послабления: их запись без предмета — находка (самоистечение).
EXPIRING = ("signatories", "waivers", "history_only", "committers")
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
    # После границы `signoff` нет ни в одной роли: строка сообщения — не запись
    # ведомости, и одной дописанной строкой закрытый перечень не открывается
    # (находка приёмки: адрес «только история» проходил с собственной подписью).
    "tree": {
        ROLE_AUTHOR: ("owners", "signatories", "waivers"),
        ROLE_COAUTHOR: ("owners", "signatories", "waivers"),
    },
    "push": {
        ROLE_AUTHOR: ("owners", "signatories"),
        ROLE_COMMITTER: ("owners", "signatories", "committers"),
        ROLE_COAUTHOR: ("owners", "signatories", "waivers"),
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


def git(root, *args, check=True, stdin=None):
    r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True, env=git_env(),
                       input=stdin)
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
    """Ведомость РАБОЧЕГО ДЕРЕВА — для гейта дерева и переписи."""
    try:
        with open(os.path.join(root, rel), encoding="utf-8") as f:
            text = f.read()
    except FileNotFoundError:
        raise LedgerDefect("ведомости %s в дереве нет — различать своего и чужого нечем" % rel)
    return parse_ledger(text, rel, lambda p: os.path.exists(os.path.join(root, p)))


def load_ledger_at(root, rev, rel=LEDGER):
    """Ведомость из дерева РЕВИЗИИ `rev` — той, что отправка публикует.

    Рабочее дерево здесь не судья: незакоммиченная запись о личности не входит в
    отправляемый диапазон, и вердикт, зеленеющий от неё, — неявный обход помимо
    объявленного `--no-verify` (находка приёмки: `owners: evil@…` в рабочем дереве
    выпускал коммит evil на сервер).
    """
    if git(root, "cat-file", "-e", rev + "^{commit}", check=False).returncode != 0:
        raise Unjudgeable("ревизии %s в клоне нет — ведомость отправляемого не прочесть" % rev[:12])
    r = git(root, "cat-file", "blob", "%s:%s" % (rev, rel), check=False)
    if r.returncode != 0:
        raise LedgerDefect("ведомости %s в дереве нет — различать своего и чужого нечем (дерево "
                           "отправляемой ревизии %s)" % (rel, rev[:12]))

    def exists(p):
        obj = rev + "^{tree}" if p in (".", "") else "%s:%s" % (rev, p)
        return git(root, "cat-file", "-e", obj, check=False).returncode == 0
    return parse_ledger(r.stdout, "%s@%s" % (rel, rev[:12]), exists)


def parse_ledger(text, rel, exists):
    """Ведомость, сведённая к адресам. Любой дефект — LedgerDefect со ВСЕМИ причинами."""
    try:
        import yaml  # noqa: WPS433 — зависимость объявлена в шапке набора
    except ImportError as e:
        raise Unjudgeable("разборщик YAML (python3-yaml) не установлен: %s" % e)
    try:
        raw = yaml.safe_load(text)
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
            if not exists(joined):
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


def commits(root, revs, paths=None, stdin_revs=None):
    # Порядок и адреса — ИЗ КОММИТА: `%ae`/`%ce`, а не `%aE`/`%cE`, которые
    # подменяются `.mailmap` дерева (замок — проба E5m в inject).
    args = ["log", "--format=" + FMT, *revs]
    if stdin_revs is not None:
        # Ревизии — через stdin: ссылок у сервера отправки бывают тысячи, и в
        # командную строку они не лезут.
        args.append("--stdin")
    if paths:
        # Область уже дерева: коммит вне неё не судится, но слияния и боковые
        # ветки внутри неё — судятся, упрощение истории снимается.
        args += ["--full-history", "--", *paths]
    stdin = "".join(v + "\n" for v in stdin_revs) if stdin_revs is not None else None
    out = git(root, *args, stdin=stdin).stdout
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
        # Неразборная подпись («Signed-off-by: Mallory») адреса не несёт и
        # подтверждать ей нечего: пустая строка совпала бы с пустым адресом автора.
        r.signoffs = {e for e in (email_of(v)[0] for v in f[6].split("\x1e") if v.strip()) if e}
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
            for how in (ALLOW[mode][role] if em else ()):
                if how == "signoff":
                    if em in r.signoffs:
                        basis = how
                        break
                elif em in led[how]:
                    basis = how
                    break
            if basis is None:
                if not em:
                    why = "адрес не разобран — личность не установлена"
                elif em in led["history_only"]:
                    why = "адрес «только история» (history_only) — вперёд запрет"
                elif em in led["by_email"]:
                    why = "раздел %s этой роли не покрывает" % led["by_email"][em]
                else:
                    why = "личности нет в ведомости"
                findings.append((r.sha, role, name, em, why))
                continue
            by[basis] += 1
            if basis in EXPIRING:
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
          "«только история» %d, коммиттеров-серверов %d; область %s"
          % (rel, len(led["owners"]), len(led["signatories"]), len(led["waivers"]),
             len(led["history_only"]), len(led["committers"]), scope))
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
    # `committers` — роль коммиттера, которую гейт дерева не судит (вкладчиком
    # коммиттер не считается); предмет записи — коммит с этим коммиттером где
    # угодно в истории, и без него запись — находка.
    if led["committers"]:
        per_c = Counter(r.ce for r in whole if r.ce in led["committers"])
        used |= set(per_c)
        for em in sorted(led["committers"]):
            print("    committers %s — коммитов коммиттером %d" % (em, per_c[em]))

    bad = 0
    if findings:
        bad += 1
        print("[FAIL] cla-gate — вклады без подтверждения: %d" % len(findings), file=sys.stderr)
        print_findings(findings)
    for s_ in EXPIRING:
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
              "отправку судит ведомость ОТПРАВЛЯЕМОЙ ревизии, незакоммиченная правка не "
              "действует" % rel, file=sys.stderr)


REMOTE_NAME = re.compile(r"[A-Za-z0-9._-]+")


def push_target(root, remote, url):
    """Адрес сервера ОТПРАВКИ.

    Хук получает его от git вторым аргументом (при нескольких pushurl — свой на
    каждый вызов). Без него — pushurl названного remote (`get-url --push`), а не
    его url: выборка и отправка бывают разными серверами. Имя, не являющееся
    remote, — это и есть URL (отправка по адресу).
    """
    if url:
        return url
    if remote and REMOTE_NAME.fullmatch(remote):
        r = git(root, "remote", "get-url", "--push", remote, check=False)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip().splitlines()[0]
    if remote:
        return remote
    raise Unjudgeable("сервер отправки не назван (нет ни URL, ни remote) — опубликованное на нём "
                      "не вычесть")


def published_on(root, target):
    """sha, которые СЕРВЕР ОТПРАВКИ называет своими ссылками, и те из них, что есть в клоне.

    Спрашивается сам сервер (`git ls-remote`). Ссылки отслеживания здесь не
    годятся ни в какой форме: это память о сервере ВЫБОРКИ, и она бывает
    устаревшей. Находки приёмки: ветку сняли на сервере, объект собран сборщиком, а
    `refs/remotes/origin/*` всё ещё его называл — и чужой коммит уходил
    неосуждённым; при `pushurl` на другой сервер чужой коммит, известный лишь
    серверу выборки, уходил на сервер отправки. И в обратную сторону: отправка по
    URL не вычитала НИЧЕГО и судила всю историю, включая посадки сервера.
    Сервер не ответил — вычесть нечем, исход 2 (хук отправки читает его как отказ).
    """
    r = git(root, "ls-remote", "--", target, check=False)
    if r.returncode != 0:
        tail = (r.stderr.strip().splitlines() or ["—"])[0]
        raise Unjudgeable("сервер отправки %s не ответил на ls-remote (код %d: %s) — опубликованное "
                          "на нём не вычесть" % (target, r.returncode, tail[:200]))
    advertised = sorted({ln.split("\t", 1)[0] for ln in r.stdout.splitlines() if "\t" in ln})
    known = []
    if advertised:
        out = git(root, "cat-file", "--batch-check=%(objectname) %(objecttype)",
                  stdin="".join(x + "\n" for x in advertised)).stdout
        known = [ln.split()[0] for ln in out.splitlines()
                 if len(ln.split()) == 2 and ln.split()[1] in ("commit", "tag")]
    return advertised, known


def ledger_blob(root, rev, rel):
    """Объект ведомости в дереве ревизии: одинаковые ведомости судят одной группой."""
    if git(root, "cat-file", "-e", rev + "^{commit}", check=False).returncode != 0:
        raise Unjudgeable("ревизии %s в клоне нет — судить отправляемое не по чему" % rev[:12])
    r = git(root, "rev-parse", "--verify", "-q", "%s:%s" % (rev, rel), check=False)
    return r.stdout.strip() or ("нет@" + rev)


def judge_push(root, rel, tips, negatives, label):
    """Суждение по отправляемому: группа ссылок — одна ведомость ИХ ревизии."""
    groups = {}
    for t in tips:
        groups.setdefault(ledger_blob(root, t, rel), []).append(t)
    findings, by, ids, seen, past_n, ledgers = [], Counter(), set(), set(), 0, []
    for _, ts in sorted(groups.items()):
        led = load_ledger_at(root, ts[0], rel)
        ledgers.append(led["path"])
        recs = commits(root, [], stdin_revs=[*ts, *("^" + n for n in negatives)])
        past, _, f, b, i, _ = judge_split(root, led, recs, "push")
        findings += f
        by += b
        ids |= i
        past_n += len({r.sha for r in past} - seen)
        seen |= {r.sha for r in recs}
    print("%s — публикуемых коммитов %d (из них история до границы %d), вкладов %d (автор %d, "
          "коммиттер %d, соавтор %d), личностей %d; ведомость %s"
          % (label, len(seen), past_n, by["вкладов"], by[ROLE_AUTHOR], by[ROLE_COMMITTER],
             by[ROLE_COAUTHOR], len(ids), ", ".join(ledgers) or "— (публиковать нечего)"),
          file=sys.stderr)
    dirty_ledger_note(root, rel)
    if findings:
        print("pre-push: ОТКАЗ — отправка опубликовала бы подпись вне ведомости либо ключ "
              "атрибуции (%d):" % len(findings), file=sys.stderr)
        print_findings(findings)
        print("  Чинится переподписью ТОЛЬКО того, что нигде не опубликовано (git rebase -x "
              "'git commit --amend --no-edit --reset-author' <база>), снятием ключа атрибуции "
              "из сообщения либо записью в %s ОТПРАВЛЯЕМОЙ ревизии с причиной. Коммит, уже "
              "опубликованный где-либо, не переписывается: его личность — решение владельца "
              "записью в ведомости. Обход один и явный: git push --no-verify." % rel,
              file=sys.stderr)
        return 1
    return 0


def run_push_range(root, rel, remote, url, lines):
    tips, rshas, refs, deletions = [], [], 0, 0
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
        tips.append(lsha)
        if rsha != ZERO and git(root, "cat-file", "-e", rsha + "^{commit}", check=False).returncode == 0:
            rshas.append(rsha)
    if not tips:
        print("pre-push: подпись и ведомость (%s) — ссылок %d, снятий %d — публиковать нечего"
              % (remote or url or "?", refs, deletions), file=sys.stderr)
        return 0
    target = push_target(root, remote, url)
    advertised, known = published_on(root, target)
    label = ("pre-push: подпись и ведомость (%s → %s) — ссылок %d, снятий %d; сервер отправки "
             "назвал sha %d, из них в клоне %d"
             % (remote or "?", target, refs, deletions, len(advertised), len(known)))
    return judge_push(root, rel, tips, sorted(set(rshas) | set(known)), label)


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
    ap.add_argument("--url", default="", help="сервер ОТПРАВКИ (второй аргумент хука pre-push)")
    ap.add_argument("revs", nargs="*")
    a = ap.parse_args()
    root = a.root
    try:
        if root is None:
            root = git(os.getcwd(), "rev-parse", "--show-toplevel").stdout.strip()
        if a.mode == "tree":
            return run_tree(root, a.ledger)
        if a.mode == "push-range":
            return run_push_range(root, a.ledger, a.remote, a.url, sys.stdin.read().splitlines())
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
