#!/usr/bin/env python3
# Copyright (c) PRO-Robotech
# SPDX-License-Identifier: BUSL-1.1
"""cla.py — ведомость соглашения о вкладе воркспейса и ЕДИНСТВЕННОЕ суждение по ней.

Один читатель ведомости на три вопроса, и второго перечня личностей в дереве нет:
второй перечень разошёлся бы с первым молча (ws#729 п.4).

    tree        гейт дерева (ws#731): вклады в истории области — автор и соавтор из
                завершающего блока трейлеров — подтверждены ведомостью; запись без
                предмета — находка; объём осмотренного печатается всегда.
    push-range  суждение хука отправки (ws#729, ws#700): по каждому коммиту и
                объекту аннотированного тега, который ОТПРАВКА ОПУБЛИКУЕТ (строки
                pre-push на stdin), автор, коммиттер, автор тега и соавторы — личности
                ведомости. Судится диапазон, а не рабочее дерево и не `git config`:
                подстановка адреса окружением сильнее настройки и видна только в
                самом коммите. Опубликованное спрашивается у СЕРВЕРА ОТПРАВКИ
                (`git ls-remote <url>`), а не у ссылок отслеживания: те — память о
                сервере ВЫБОРКИ и бывают устаревшими.
                ПОЛНОМОЧИЯ БЕРУТСЯ ИЗ СТВОЛА, А НЕ ИЗ ПРОВЕРЯЕМОГО ИЗМЕНЕНИЯ: судит
                ведомость ствола сервера отправки — ветки, на которую указывает его
                HEAD, прочитанной у него же (`ls-remote`, объект при нужде — `fetch`).
                Ведомость внутри отправляемой ревизии круг допущенных не расширяет
                никогда: запись адреса садится в ствол ОТДЕЛЬНОЙ посадкой, и только
                потом по ней проходит отправка. Ствол без ведомости — «условие не
                создано» (исход 2); пропускает только явный флаг первой посадки
                (`KACHO_CLA_FIRST_LANDING=1`), и лишь ревизии, которая сама несёт
                ведомость, — в самой узкой её форме. Ведомость читается ПОСЛЕ
                вычитания опубликованного: ссылке, которая не публикует ничего, она не
                нужна. Исполнимое лечение отказа печатается строкой `лечение$ …`, и
                исполнимо в нём только снятие строки ключа атрибуции (автор, коммиттер
                и автор тега остаются прежними). Переподписи нет: лечения находки
                личности — посадки, «ведомость вашего адреса должна сначала сесть в
                ствол» и «влейте ствол».
    census      таблица суждения отправки по произвольному диапазону
                (`census --remote origin -- <ветка> --not --glob=refs/remotes/origin/*`) —
                диагностика по ведомости СТВОЛА названного remote (той же, что судит
                отправку) и по названным ссылкам. Вердиктом отправки она не является:
                отправка вычитает опубликованное у сервера отправки.

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
    автор тега своя личность · подписавший — объект аннотированного тега судится
               как коммит: автор тега и трейлеры его сообщения
    соавтор    своя личность · подписавший · освобождённый — по вопросу
               соглашения; сам ключ атрибуции (Co-authored-by, Claude-Session)
               в строке сообщения — отказ по имени ключа независимо от ведомости

УЗКАЯ ФОРМА ПЕРВОЙ ПОСАДКИ (флаг при стволе без ведомости): `owners` — только
пересечение с `user.email` копии; `signatories`, `waivers`, `committers`,
`history_only` и граница не действуют. Историей не считается ничего: граница,
опубликованная на сервере, уже вычла всё, что до неё, а неопубликованная —
объявление самой проверяемой ревизии, и полномочий у него нет.
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
import shlex
import subprocess
import sys
from collections import Counter

LEDGER = "contribution-ledger.yaml"
ZERO = "0" * 40
# Явный флаг первой посадки: ствол сервера отправки ведомости не несёт, а эта
# отправка её и вводит. Имя печатает отказ; флаг не расширяет ничего сверх узкой формы.
FIRST_LANDING_ENV = "KACHO_CLA_FIRST_LANDING"
# Префикс ИСПОЛНИМОЙ строки лечения: всё после него — команда целиком, и проба
# исполняет её дословно (находка приёмки круга 3: проба сверяла подстроку и
# переносила свой sha, а напечатанное лечение открывало адрес «только история»).
CURE = "  лечение$ "
SECTIONS = ("owners", "signatories", "waivers", "history_only", "committers")
# Разделы-послабления: их запись без предмета — находка (самоистечение).
EXPIRING = ("signatories", "waivers", "history_only", "committers")
TOP_KEYS = {"scope", "history_floor"} | set(SECTIONS)
ENTRY_KEYS = {"email", "note"}
FLOOR_KEYS = {"commit", "note"}

ROLE_AUTHOR, ROLE_COMMITTER, ROLE_COAUTHOR = "автор", "коммиттер", "соавтор"
ROLE_TAGGER = "автор тега"
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
        # Автор тега — тот, кто объявил тег, как автор коммита: `committers` (личность
        # сервера посадки) его не покрывает — сервер тег не создаёт, он его хранит.
        ROLE_TAGGER: ("owners", "signatories"),
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
    """Ведомость из дерева РЕВИЗИИ `rev` — ствола сервера отправки (либо ревизии,
    вводящей ведомость, при флаге первой посадки — и тогда в узкой форме).

    Рабочее дерево здесь не судья: незакоммиченная запись о личности не входит в
    отправляемый диапазон, и вердикт, зеленеющий от неё, — неявный обход помимо
    объявленного `--no-verify` (находка приёмки: `owners: evil@…` в рабочем дереве
    выпускал коммит evil на сервер). Отправляемая ревизия — тоже не судья: запись,
    внесённая самим проверяемым изменением, допускала бы его же (круг 3).
    """
    if git(root, "cat-file", "-e", rev + "^{commit}", check=False).returncode != 0:
        raise Unjudgeable("ревизии %s в клоне нет — ведомость отправляемого не прочесть" % rev[:12])
    r = git(root, "cat-file", "blob", "%s:%s" % (rev, rel), check=False)
    if r.returncode != 0:
        raise LedgerDefect("ведомости %s в дереве нет — различать своего и чужого нечем (дерево "
                           "ревизии %s)" % (rel, rev[:12]))

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
    __slots__ = ("kind", "sha", "an", "ae", "cn", "ce", "coauthors", "signoffs", "body")


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
        r.kind = "commit"
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
    if r.kind == "tag":
        # Объект тега: его автор — единственная личность объекта, соавторы — из
        # трейлеров сообщения тега, как у коммита.
        out.append((ROLE_TAGGER, r.an, r.ae))
    else:
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
                elif em in led.get("narrowed", {}):
                    why = ("первая посадка судит узкую форму ведомости: запись в %s не действует "
                           "(owners — только user.email копии «%s», прочие разделы — нет)"
                           % (led["narrowed"][em], led.get("own") or "не задан"))
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
              "отправку судит ведомость СТВОЛА сервера отправки, правка в копии не действует"
              % rel, file=sys.stderr)


REMOTE_NAME = re.compile(r"[A-Za-z0-9._-]+")
SHA_LINE = re.compile(r"^([0-9a-f]{40}|[0-9a-f]{64})\t(\S+)$")


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


def present(root, shas):
    """Те из sha, что есть в клоне коммитом либо объектом тега."""
    if not shas:
        return []
    out = git(root, "cat-file", "--batch-check=%(objectname) %(objecttype)",
              stdin="".join(x + "\n" for x in shas)).stdout
    return [ln.split()[0] for ln in out.splitlines()
            if len(ln.split()) == 2 and ln.split()[1] in ("commit", "tag")]


def published_on(root, target):
    """Что СЕРВЕР ОТПРАВКИ называет своим: (все sha, имя ствола, sha ствола).

    Спрашивается сам сервер (`git ls-remote --symref`). Ссылки отслеживания здесь
    не годятся ни в какой форме: это память о сервере ВЫБОРКИ, и она бывает
    устаревшей. Находки приёмки: ветку сняли на сервере, объект собран сборщиком, а
    `refs/remotes/origin/*` всё ещё его называл — и чужой коммит уходил
    неосуждённым; при `pushurl` на другой сервер чужой коммит, известный лишь
    серверу выборки, уходил на сервер отправки. И в обратную сторону: отправка по
    URL не вычитала НИЧЕГО и судила всю историю, включая посадки сервера.

    Ствол — ветка, на которую указывает HEAD сервера (строка `ref: … HEAD`); сервер,
    не назвавший HEAD (пуст либо HEAD висит), ствола не имеет. Сервер не ответил —
    вычесть нечем, исход 2 (хук отправки читает его как отказ).
    """
    r = git(root, "ls-remote", "--symref", "--", target, check=False)
    if r.returncode != 0:
        tail = (r.stderr.strip().splitlines() or ["—"])[0]
        raise Unjudgeable("сервер отправки %s не ответил на ls-remote (код %d: %s) — опубликованное "
                          "на нём не вычесть" % (target, r.returncode, tail[:200]))
    advertised, head_name, head_sha = set(), "", ""
    for ln in r.stdout.splitlines():
        if ln.startswith("ref: ") and ln.endswith("\tHEAD"):
            head_name = ln[len("ref: "):-len("\tHEAD")].strip()
            continue
        m = SHA_LINE.match(ln)
        if not m:
            continue
        advertised.add(m.group(1))
        if m.group(2) == "HEAD":
            head_sha = m.group(1)
    return sorted(advertised), (head_name or "HEAD", head_sha)


def fetch_trunk(root, target, trunk):
    """Объект ствола — в клоне: он есть либо получен у сервера отправки.

    Ведомость ствола читается из объекта, которым сервер НАЗВАЛ ствол в этом же
    прогоне, а не из ссылки отслеживания: та — память о сервере выборки. Ссылки
    клона выборка не трогает (`--no-write-fetch-head`, refspec без приёмника).
    """
    name, sha = trunk
    if git(root, "cat-file", "-e", sha + "^{commit}", check=False).returncode == 0:
        return False
    r = git(root, "-c", "gc.auto=0", "-c", "maintenance.auto=false", "fetch", "--quiet",
            "--no-tags", "--no-write-fetch-head", "--no-recurse-submodules", "--", target, name,
            check=False)
    if git(root, "cat-file", "-e", sha + "^{commit}", check=False).returncode != 0:
        tail = (r.stderr.strip().splitlines() or ["—"])[0]
        raise Unjudgeable("ствол %s@%s сервера отправки в клон не получен (fetch код %d: %s) — "
                          "ведомость ствола не прочесть" % (name, sha[:12], r.returncode, tail[:200]))
    return True


def ledger_blob(root, rev, rel):
    """Объект ведомости в дереве ревизии либо None — ведомости там нет."""
    r = git(root, "rev-parse", "--verify", "-q", "%s:%s" % (rev, rel), check=False)
    return r.stdout.strip() or None


def rev_list(root, revs, *opts):
    """sha коммитов диапазона. Ревизии подаются через stdin: у сервера отправки
    бывают тысячи ссылок, и в командную строку они не помещаются."""
    return git(root, "rev-list", *opts, "--stdin", stdin="".join(v + "\n" for v in revs)).stdout.split()


SIGNATURE_RE = re.compile(r"^-----BEGIN [A-Z ]*SIGNATURE-----$", re.M)
PERSON_RE = re.compile(r"^(.*?)\s*<([^<>]*)>")


def read_tag(root, sha):
    """(запись суждения, sha объекта, на который тег указывает, его тип)."""
    raw = git(root, "cat-file", "tag", sha).stdout
    head, _, msg = raw.partition("\n\n")
    fields = {}
    for ln in head.splitlines():
        k, _, v = ln.partition(" ")
        fields.setdefault(k, v)
    sig = SIGNATURE_RE.search(msg)
    if sig:
        msg = msg[:sig.start()]
    r = Rec()
    r.kind, r.sha, r.cn, r.ce, r.body = "tag", sha, "", "", msg
    m = PERSON_RE.match(fields.get("tagger", ""))
    # Тег без строки tagger (старый git) — личность не установлена, а не пропуск.
    r.an, r.ae = (m.group(1), norm(m.group(2))) if m else (fields.get("tagger", ""), "")
    # Трейлеры разбирает САМ git, по тем же правилам, что `%(trailers)` у коммита.
    r.coauthors, r.signoffs = [], set()
    for ln in git(root, "interpret-trailers", "--parse", stdin=msg).stdout.splitlines():
        k, _, v = ln.partition(":")
        k = k.strip().lower()
        if k == "co-authored-by":
            r.coauthors.append(email_of(v))
        elif k == "signed-off-by" and email_of(v)[0]:
            r.signoffs.add(email_of(v)[0])
    return r, fields.get("object", ""), fields.get("type", "")


def peel(root, sha):
    """(коммит, [объекты аннотированных тегов по цепочке]) для sha строки отправки."""
    chain, cur = [], sha
    for _ in range(32):
        t = git(root, "cat-file", "-t", cur, check=False)
        if t.returncode != 0:
            raise Unjudgeable("ревизии %s в клоне нет — судить отправляемое не по чему" % cur[:12])
        typ = t.stdout.strip()
        if typ == "commit":
            return cur, chain
        if typ != "tag":
            raise Unjudgeable("ссылка отправки указывает на %s %s, а не на коммит — судить не по чему"
                              % (typ, cur[:12]))
        chain.append(cur)
        cur = read_tag(root, cur)[1]
    raise Unjudgeable("цепочка тегов от %s длиннее 32 — не разобрана" % sha[:12])


def own_email(root):
    return norm(git(root, "config", "--get", "user.email", check=False).stdout)


def narrow(led, own):
    """Самая узкая форма ведомости ревизии, вводящей её (первая посадка под флагом).

    `owners` — только пересечение с `user.email` копии; остальные разделы и граница
    не действуют: это объявления самой проверяемой ревизии, и полномочий у них нет.
    """
    n = dict(led)
    n["own"] = own
    n["owners"] = {em: e for em, e in led["owners"].items() if own and em == own}
    n["narrowed"] = {em: s for em, s in led["by_email"].items() if em not in n["owners"]}
    for s in EXPIRING:
        n[s] = {}
    n["floor"] = None
    n["by_email"] = {em: "owners" for em in n["owners"]}
    n["path"] = "%s в узкой форме первой посадки (owners ∩ user.email «%s»)" % (led["path"], own or "не задан")
    return n


def q(s):
    return shlex.quote(s)


def short_ref(name):
    return name[len("refs/heads/"):] if name.startswith("refs/heads/") else name


def refspecs(items):
    return " ".join(q("%s:%s" % (it["lref"], it["rref"])) for it in items)


# ── лечение: только ключ атрибуции, и никогда — чужая личность ───────────────
#
# ПЕРЕПОДПИСИ В ЛЕЧЕНИИ НЕТ — ни командой, ни советом. Коммит и тег адреса вне
# ведомости ствола, переподписанные своей личностью, публикуют его вклад под вашим
# именем, и ведомость ствола об этом не узнаёт никогда (находка приёмки круга 1:
# печатавшееся для любой находки `rebase --exec 'commit --amend --reset-author'`
# покрывало весь диапазон от родителя первой находки и выпускало на сервер работу
# stranger@, слияние и боковой коммит, коммиты под флагом первой посадки — от имени
# отправителя; заодно переписывался законный коммит подписавшего). Лечений личности
# два, и оба — посадкой, а не правкой ветки: «ведомость вашего адреса должна сначала
# сесть в ствол» и «влейте ствол».
#
# Исполнимо ОДНО: снять строку ключа атрибуции из сообщения. Автор, коммиттер и даты
# остаются записанными в коммите (`git filter-branch --msg-filter` переносит их из
# исходного), автор тега — в теге. Снимается не всякая строка ключа: строка соавтора,
# которого ведомость соавтором не покрывает, после снятия скрыла бы его вклад, — её
# лечение не трогает, и отказ остаётся (лечение, открывающее то, что закрыто, хуже
# отсутствия лечения). Переписываются только коммиты с такой находкой: ветку
# `filter-branch` проходит целиком, но сообщение меняет лишь им (`$GIT_COMMIT`).

# Адрес, который безопасно подставить в выражение sed без экранирования смысла.
SED_SAFE_EMAIL = re.compile(r"[a-z0-9._%+@-]+")


def covered_coauthors(led):
    """Адреса, которые ведомость покрывает в роли соавтора отправки."""
    out = set()
    for s in ALLOW["push"][ROLE_COAUTHOR]:
        out |= set(led[s])
    return out


def strippable_keys(body, covered):
    """Строки ключа атрибуции, которые лечение вправе снять: `Claude-Session` (адреса
    не несёт) и `Co-authored-by` с адресом, покрытым ведомостью соавтором."""
    out = []
    for m in ATTRIBUTION_RE.finditer(body):
        line = body[m.start():].split("\n", 1)[0]
        if m.group(1).lower() == "claude-session":
            out.append(line)
            continue
        em = email_of(line.split(":", 1)[1])[0]
        if em and em in covered and SED_SAFE_EMAIL.fullmatch(em):
            out.append(line)
    return out


def strip_sed(covered):
    """Программа `sed -E` (флаг I — без учёта регистра), снимающая ровно те строки,
    что называет `strippable_keys`, — формы адреса те же, что у `email_of`."""
    addrs = sorted(e for e in covered if SED_SAFE_EMAIL.fullmatch(e))
    alt = "|".join(e.replace(".", "[.]").replace("+", "[+]") for e in addrs)
    coauthor = ("|co-authored-by[[:space:]]*:([[:space:]]*(%s)|.*<(%s)>)[[:space:]]*$" % (alt, alt)
                if alt else "")
    return "/^(claude-session[[:space:]]*:%s)/Id" % coauthor


def print_cures(root, items, neg, auth, trunk, strip):
    """Лечение находок. Строки `лечение$ …` — команда целиком, их исполняют дословно.

    `strip` — {sha коммита либо объекта тега: программа sed} для находок, у которых
    лечение снимает строку ключа атрибуции (`strippable_keys`). Находке личности
    исполнимого лечения нет: её лечения — посадки (см. выше). Опубликованное не
    переписывается никогда: команда печатается, только если весь переписываемый
    диапазон ветки не опубликован.
    """
    tsha = trunk[1] if trunk else ""
    print("  Лечение без обхода. Полномочия — у ведомости %s; ведомость ветки круг допущенных не "
          "расширяет." % auth, file=sys.stderr)
    print("  · Адресу место в перечне — ведомость вашего адреса должна сначала сесть в ствол "
          "(отдельное изменение через ревью и посадку), затем повторите ту же отправку.", file=sys.stderr)
    if tsha:
        print("  · Ветке нужна ведомость ствола — влейте ствол (git merge %s); прежние редакции "
              "ведомости в ветку не переносите: самая ранняя из них — самая широкая." % tsha[:12],
              file=sys.stderr)
    print("  · Переподписи здесь нет и не будет: коммит и тег адреса вне ведомости, переподписанные "
          "своей личностью, опубликовали бы его вклад под вашим именем.", file=sys.stderr)
    if strip:
        print("  · Ключ атрибуции снимается из сообщения; автор, коммиттер и автор тега остаются "
              "записанными в объекте:", file=sys.stderr)
    for it in items:
        order = [s for s in rev_list(root, [it["commit"], *neg], "--topo-order", "--reverse") if s in strip]
        if order:
            parents = git(root, "rev-list", "--parents", "-n", "1", order[0]).stdout.split()
            upstream = parents[1] if len(parents) > 1 else ""
            span = rev_list(root, [it["commit"]] + (["^" + upstream] if upstream else []))
            lref = it["lref"]
            if set(span) - set(it["fresh"]):
                print("    %s: в переписываемом диапазоне от %s есть опубликованные коммиты — команду не "
                      "печатаю: опубликованное не переписывается; снимите ключ вручную только в "
                      "названных выше" % (lref, order[0][:12]), file=sys.stderr)
            elif not lref.startswith("refs/heads/"):
                print("    %s — не ветка: снимите ключ в названных выше коммитах на ветке и отправьте её"
                      % lref, file=sys.stderr)
            else:
                branch = lref[len("refs/heads/"):]
                seds = {strip[s] for s in order}
                arms = " ".join("%s) sed -E %s ;;" % ("|".join(s for s in order if strip[s] == p), q(p))
                                for p in sorted(seds))
                rng = "%s..%s" % (upstream, branch) if upstream else branch
                print(CURE + "FILTER_BRANCH_SQUELCH_WARNING=1 git filter-branch -f --msg-filter %s -- %s"
                      % (q("case $GIT_COMMIT in %s *) cat ;; esac" % arms), q(rng)), file=sys.stderr)
        for t in it["tags"]:
            if t not in strip:
                continue
            if not it["lref"].startswith("refs/tags/") or it["tags"] != [it["lsha"]]:
                print("    %s — объект тега %s не единственный под локальным тегом: пересоздайте его без "
                      "строки ключа сами, автора тега не меняя" % (it["lref"], t[:12]), file=sys.stderr)
                continue
            head = git(root, "cat-file", "tag", t).stdout.partition("\n\n")[0]
            tagger = next((ln[len("tagger "):] for ln in head.splitlines() if ln.startswith("tagger ")), "")
            m = re.match(r"^(.*?)\s*<([^<>]*)>\s*(\d+ [+-]\d{4})$", tagger)
            if not m:
                print("    %s — автор тега %s не разобран: пересоздайте тег сами" % (it["lref"], t[:12]),
                      file=sys.stderr)
                continue
            obj = next((ln[len("object "):] for ln in head.splitlines() if ln.startswith("object ")), "")
            print(CURE + "git cat-file tag %s | sed '1,/^$/d' | sed '/^-----BEGIN .*SIGNATURE-----$/,$d' | "
                  "sed -E %s | GIT_COMMITTER_NAME=%s GIT_COMMITTER_EMAIL=%s GIT_COMMITTER_DATE=%s "
                  "git tag -f -a --cleanup=verbatim -F - %s %s"
                  % (t, q(strip[t]), q(m.group(1)), q(m.group(2)), q(m.group(3)),
                     q(it["lref"][len("refs/tags/"):]), obj), file=sys.stderr)
    # Под флагом первой посадки ствол ведомости по-прежнему не несёт: повторная
    # отправка без флага получила бы «условие не создано», и лечение не исполнилось бы.
    print("  Затем та же отправка:", file=sys.stderr)
    print(CURE + "%sgit push %s %s" % ("%s=1 " % FIRST_LANDING_ENV if not tsha else "",
                                       q(items[0]["remote"]), refspecs(items)), file=sys.stderr)


def judge_push(root, rel, pushes, remote, target, label, first):
    """Суждение по отправляемому. Полномочия — у ведомости СТВОЛА сервера отправки.

    ПОРЯДОК: сначала вычитается опубликованное (коммиты и объекты тегов, которые
    сервер отправки уже называет), потом читается ведомость. Ссылке, которая не
    публикует ничего, ведомость не нужна: отказ ей был бы вечным (находка приёмки
    круга 2 — тег на опубликованную историю без ведомости).

    Судит ведомость ствола — ветки, на которую указывает HEAD сервера отправки, в
    той редакции, которую сервер назвал в этом же прогоне. Ведомость отправляемой
    ревизии не судит никогда: запись о личности, внесённая самим проверяемым
    изменением, открывала бы его же (находка приёмки круга 3: лечение из отказа
    переносило в ветку самую раннюю и самую широкую редакцию, и адрес «только
    история» уходил на сервер). Ствол без ведомости — «условие не создано»; флаг
    первой посадки допускает лишь ревизию, несущую ведомость, в узкой форме.
    """
    advertised, trunk = published_on(root, target)
    adv = set(advertised)

    def census_items():
        published = set(present(root, advertised))
        published |= {p["rsha"] for p in pushes if p["rsha"]}
        neg = ["^" + n for n in sorted(published)]
        items, idle = [], 0
        for p in pushes:
            commit, chain = peel(root, p["lsha"])
            tags = [t for t in chain if t not in adv]
            fresh = rev_list(root, [commit, *neg])
            if not fresh and not tags:
                idle += 1
                continue
            items.append(dict(p, commit=commit, fresh=fresh, tags=tags))
        return items, idle, neg

    items, idle, neg = census_items()
    tname, tsha = trunk
    head = "%s; сервер отправки назвал sha %d" % (label, len(advertised))
    if items and tsha and fetch_trunk(root, target, trunk):
        # Объекты ствола получены только что: опубликованное пересчитывается ими.
        items, idle, neg = census_items()
    if not items:
        print("%s — публикуемых коммитов 0, объектов тегов 0; ссылок без нового %d (ведомость не "
              "читалась)" % (head, idle), file=sys.stderr)
        return 0

    tblob = ledger_blob(root, tsha, rel) if tsha else None
    trunk_txt = ("ствол %s@%s сервера отправки %s" % (short_ref(tname), tsha[:12], target) if tsha
                 else "сервер отправки %s ствола не называет (пуст либо HEAD висит)" % target)
    bad = False
    if tblob is not None:
        led = load_ledger_at(root, tsha, rel)
        judges = [(led, items)]
        auth = "%s (%s)" % (trunk_txt, led["path"])
        if first:
            print("pre-push: флаг %s не действует — ствол ведомость несёт, судит она" % FIRST_LANDING_ENV,
                  file=sys.stderr)
    else:
        if not first:
            print(head, file=sys.stderr)
            print("[VOID] cla-gate — условие не создано: %s, ведомости %s в нём нет — полномочий судить "
                  "отправку нет (они берутся из ствола, а не из отправляемой ревизии)"
                  % (trunk_txt, rel), file=sys.stderr)
            print("  Лечение без обхода: ведомость должна сначала сесть в ствол этого сервера "
                  "(посадкой через ревью), затем повторите отправку.", file=sys.stderr)
            print("  Если ЭТА отправка и есть первая посадка ведомости на этот сервер — явный флаг, "
                  "и он называется в отчёте:", file=sys.stderr)
            print(CURE + "%s=1 git push %s %s" % (FIRST_LANDING_ENV, q(items[0]["remote"]), refspecs(items)),
                  file=sys.stderr)
            print("  Флаг допускает лишь ревизию, которая сама несёт ведомость, и судит её самая узкая "
                  "форма: owners — только user.email копии («%s»); signatories, waivers, committers, "
                  "history_only и граница не действуют." % (own_email(root) or "не задан"),
                  file=sys.stderr)
            return 2
        own = own_email(root)
        by_blob = {}
        for it in items:
            b = ledger_blob(root, it["commit"], rel)
            if b is None:
                bad = True
                print("[FAIL] cla-gate — флаг %s допускает лишь ревизию, которая сама вводит ведомость; в "
                      "дереве %s (%s) ведомости %s нет" % (FIRST_LANDING_ENV, it["commit"][:12], it["lref"], rel),
                      file=sys.stderr)
                continue
            by_blob.setdefault(b, []).append(it)
        judges = [(narrow(load_ledger_at(root, its[0]["commit"], rel), own), its)
                  for _, its in sorted(by_blob.items())]
        auth = "первой посадки (%s)" % trunk_txt

    findings, by, ids, seen, past_n, tags_n, used = [], Counter(), set(), set(), 0, 0, []
    strip = {}
    for led, its in judges:
        used.append(led["path"])
        recs = [r for r in commits(root, [], stdin_revs=[*(it["commit"] for it in its), *neg])
                if r.sha not in seen]
        past, new, f, b, i, _ = judge_split(root, led, recs, "push")
        tag_recs = [read_tag(root, t)[0] for it in its for t in it["tags"] if t not in seen]
        f2, b2, i2, _ = judge(tag_recs, led, "push")
        # Ключ атрибуции судится только в новом (после границы) и в объектах тегов —
        # только там у лечения есть предмет.
        cov = covered_coauthors(led)
        for r in new + tag_recs:
            if strippable_keys(r.body, cov):
                strip[r.sha] = strip_sed(cov)
        findings += f + f2
        by += b + b2
        ids |= i | i2
        past_n += len(past)
        tags_n += len(tag_recs)
        seen |= {r.sha for r in recs} | {r.sha for r in tag_recs}
    print("%s — публикуемых коммитов %d (из них история до границы %d), объектов тегов %d, вкладов %d "
          "(автор %d, коммиттер %d, автор тега %d, соавтор %d), личностей %d; судит ведомость %s — "
          "%s; ссылок без нового %d"
          % (head, len(seen) - tags_n, past_n, tags_n, by["вкладов"], by[ROLE_AUTHOR],
             by[ROLE_COMMITTER], by[ROLE_TAGGER], by[ROLE_COAUTHOR], len(ids),
             ", ".join(used) or "—", trunk_txt, idle), file=sys.stderr)
    if tblob is not None:
        for it in items:
            b = ledger_blob(root, it["commit"], rel)
            if b is not None and b != tblob:
                print("pre-push: ведомость ревизии %s (%s) отличается от ведомости ствола и НЕ действует — "
                      "круг допущенных задаёт ствол; чтобы ветка несла его ведомость, влейте ствол "
                      "(git merge %s)" % (it["commit"][:12], it["lref"], tsha[:12]), file=sys.stderr)
    dirty_ledger_note(root, rel)
    if findings:
        print("pre-push: ОТКАЗ — отправка опубликовала бы подпись вне ведомости %s либо ключ атрибуции "
              "(%d):" % (auth, len(findings)), file=sys.stderr)
        print_findings(findings)
        print_cures(root, items, neg, auth, trunk if tblob is not None else None, strip)
        print("  Коммит и тег, уже опубликованные где-либо, не переписываются: их личность — решение "
              "владельца записью в ведомости ствола. Обход один и явный: git push --no-verify.",
              file=sys.stderr)
        return 1
    return 1 if bad else 0


def run_push_range(root, rel, remote, url, lines):
    pushes, refs, deletions = [], 0, 0
    for ln in lines:
        parts = ln.split()
        if len(parts) != 4:
            if ln.strip():
                raise Unjudgeable("строка pre-push не разобрана: %r" % ln)
            continue
        lref, lsha, rref, rsha = parts
        refs += 1
        if lsha == ZERO:
            deletions += 1
            continue
        known = rsha != ZERO and git(root, "cat-file", "-e", rsha, check=False).returncode == 0
        pushes.append({"lref": lref, "lsha": lsha, "rref": rref, "rsha": rsha if known else ""})
    if not pushes:
        print("pre-push: подпись и ведомость (%s) — ссылок %d, снятий %d — публиковать нечего"
              % (remote or url or "?", refs, deletions), file=sys.stderr)
        return 0
    target = push_target(root, remote, url)
    for p in pushes:
        p["remote"] = remote or target
    label = ("pre-push: подпись и ведомость (%s → %s) — ссылок %d, снятий %d"
             % (remote or "?", target, refs, deletions))
    return judge_push(root, rel, pushes, remote, target, label,
                      os.environ.get(FIRST_LANDING_ENV, "") == "1")


def run_census(root, rel, remote, revs):
    """Перепись по диапазону — ведомостью ствола названного remote, той же, что судит отправку."""
    target = push_target(root, remote, "")
    advertised, trunk = published_on(root, target)
    tname, tsha = trunk
    if not tsha:
        raise Unjudgeable("сервер %s ствола не называет — переписи судить нечем" % target)
    fetch_trunk(root, target, trunk)
    if ledger_blob(root, tsha, rel) is None:
        raise Unjudgeable("в стволе %s@%s сервера %s ведомости %s нет — переписи судить нечем"
                          % (short_ref(tname), tsha[:12], target, rel))
    led = load_ledger_at(root, tsha, rel)
    recs = commits(root, revs)
    if not recs:
        # Пустой обход — не «находок 0»: о диапазоне не прочитано ничего.
        raise Unjudgeable("диапазон %s не несёт ни одного коммита — переписи судить нечего" % " ".join(revs))
    past, _, findings, by, ids, _ = judge_split(root, led, recs, "push")
    print("[CENSUS] cla census %s — ведомость ствола %s@%s (%s); коммитов %d (история до границы %d), "
          "вкладов %d, личностей %d; находок %d"
          % (" ".join(revs), short_ref(tname), tsha[:12], target, len(recs), len(past), by["вкладов"], len(ids),
             len(findings)))
    if findings:
        print_findings(findings)
        return 1
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("mode", choices=("tree", "push-range", "census"))
    ap.add_argument("--root", default=None, help="корень судимого дерева (по умолчанию — рабочая копия)")
    ap.add_argument("--ledger", default=LEDGER)
    ap.add_argument("--remote", default="", help="remote отправки (для census — чей ствол судит; по "
                                                 "умолчанию origin)")
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
            raise Unjudgeable("census без диапазона — судить нечем")
        return run_census(root, a.ledger, a.remote or "origin", a.revs)
    except LedgerDefect as e:
        print("[FAIL] cla-gate — %s" % e, file=sys.stderr)
        return 1
    except Unjudgeable as e:
        print("[VOID] cla-gate — условие не создано: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
