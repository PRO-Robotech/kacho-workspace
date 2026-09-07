"""Общее для проверок набора docs-gate.

Состав дерева берётся из ИНДЕКСА git (`--cached --others --exclude-standard`), а
не с диска: посторонний каталог рядом с репозиторием иначе влияет на вердикт, а
ещё не закоммиченный, но и не игнорируемый файл обязан проверяться ровно в тот
коммит, где его заводят, — иначе гейт молчит в единственный день, когда он нужен.

`DOCS_GATE_ROOT` переопределяет корень. Этим пользуется ТОЛЬКО inject.sh, чтобы
прогонять проверки по временной копии дерева с внесённым дефектом.

Здесь же живёт РАСПОЗНАВАТЕЛЬ ВЕРДИКТА (`verdict`) — один на оба дома приёмок,
воркспейс и дерево продукта, — и резолюция дерева продукта (`monorepo`). Держать
их копиями у каждой проверки значило бы завести два места об одном предмете; они
разошлись бы молча и именно там, где обе отвечают «вердикт прочитан».
"""
import os
import re
import subprocess

_HERE = os.path.dirname(os.path.abspath(__file__))


def workspace_root():
    override = os.environ.get("DOCS_GATE_ROOT")
    if override:
        return os.path.abspath(override)
    return os.path.dirname(os.path.dirname(_HERE))


def tracked(root, pattern):
    """Отсортированный список путей индекса, подходящих под pathspec."""
    out = subprocess.run(
        ["git", "-C", root, "ls-files", "--cached", "--others",
         "--exclude-standard", pattern],
        capture_output=True, text=True,
    )
    return sorted(set(p for p in out.stdout.split("\n") if p))


def read(root, rel):
    with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
        return fh.read()


def census(text):
    print("[CENSUS] %s" % text)


def passed(name, detail):
    print("[PASS] %s — %s" % (name, detail))


def fail(name, detail):
    import sys
    print("[FAIL] %s — %s" % (name, detail), file=sys.stderr)


def void(name, detail):
    """«Проверять нечего» ≠ «находок ноль»."""
    import sys
    print("[VOID] %s — %s" % (name, detail), file=sys.stderr)


# ── Вердикт приёмки: ОДИН распознаватель на оба дома ─────────────────────────
#
# Приёмки живут в ДВУХ деревьях, и это решение, а не недосмотр: предмет, целиком
# лежащий внутри одного сервиса, описывается рядом с его кодом
# (`services/<svc>/docs/engineering/acceptance/`), а кросс-доменный — в
# воркспейсе (`docs/specs/*-acceptance.md`). Запрет #1 один и тот же на обоих,
# поэтому распознаватель обязан быть один: две копии разошлись бы молча, и
# разошлись бы ровно там, где обе отвечают «вердикт прочитан».
#
# ДВЕ ФОРМЫ ОБЪЯВЛЕНИЯ, обе живые в дереве:
#
#   A. помеченная строка: `Статус` / `Status` / `Вердикт` / `Verdict`, в любом
#      оформлении — цитата, полужирный, ЭЛЕМЕНТ СПИСКА, — с необязательным
#      уточнением в скобках, затем двоеточие и значение:
#      `> **Статус:** ✅ APPROVED (…)`, `- **Статус:** APPROVED — круг 3`;
#   B. строка шапки, начинающаяся с самого вердикта, без метки:
#      `> **⛔ WITHDRAWN / SUPERSEDED (2026-07-22, owner-direction):** …`.
#
# Элемент списка (`- `, `+ `) — не редкость и не край: в дереве продукта ИМ
# объявлены ВСЕ приёмки, и распознаватель, его не знавший, читал их как
# «вердикта нет» — то есть весь второй дом был вне наблюдения, а не нарушал
# (`testing.md` §«Гейт на класс», п. 7). Маркер `*` разбирался и прежде — его
# съедал класс оформления, — из-за чего слепота выглядела случайной.
# Контроль расширения: на корпусе воркспейса (170 приёмок) прочитанный вердикт
# не изменился НИ У ОДНОЙ — прибавка была слепой зоной, а не сменой смысла.
VERDICT_TOKEN = re.compile(
    r"CHANGES\s+REQUESTED|NOT\s+APPROVED|WITHDRAWN|SUPERSEDED|OBSOLETE|DEPRECATED"
    r"|REJECTED|APPROVED|DRAFT|PROPOSED|WIP|BLOCKED",
    re.I,
)
# Оформление строки объявления: цитата, полужирный, подчёркивание, маркер списка.
_ORNAMENT = r"[\s>*_+\-]*"
_LABEL = re.compile(
    _ORNAMENT + r"(?:Статус|Status|Вердикт|Verdict)\**\s*(?:\([^)]*\))?\**\s*[:：]\**\s*(.+)$",
    re.I,
)
_BARE = re.compile(_ORNAMENT + r"[^\w\s]*\s*\**\s*(" + VERDICT_TOKEN.pattern + r")", re.I)
_HEADING = re.compile(r"^#{2,}\s")


def verdict(text):
    """(вердикт, строка-объявление); (None, строка|None) — если вердикта нет.

    Вердикт — ПЕРВЫЙ токен закрытого набора в значении. Порядок несёт смысл:
    документ называет своё нынешнее состояние первым, а историю — после.
    «DRAFT v2 — awaiting … APPROVED» читается как DRAFT, а «✅ APPROVED (round 2
    — все CHANGES REQUESTED раунда 1 адресованы)» — как APPROVED.

    Ищется только в ШАПКЕ, до первого заголовка `##`. Ниже начинается тело, где
    то же слово стоит в цитате запрета, в таблице трассировки и в чужих
    вердиктах; читать его там значило бы вернуться к счёту по упоминанию.
    """
    for line in text.split("\n"):
        if _HEADING.match(line):
            break
        m = _LABEL.match(line)
        if m:
            t = VERDICT_TOKEN.search(m.group(1))
            if t:
                return re.sub(r"\s+", " ", t.group(0).upper()), line.strip()
            # Метка состояния есть, значение вердиктом не читается. Это тоже
            # отсутствие вердикта, и оно обязано быть названо, а не пропущено
            # дальше по шапке: иначе следующая случайная строка станет ответом.
            return None, line.strip()
        m = _BARE.match(line)
        if m:
            return re.sub(r"\s+", " ", m.group(1).upper()), line.strip()
    return None, None


def monorepo(root):
    """Путь дерева продукта: `KACHO_MONOREPO`, иначе `project/kacho`. None — нет.

    `.git` РАБОЧЕЙ КОПИИ — файл, а не каталог, поэтому проверяется существование,
    а не тип: требовать каталог значит не признавать рабочую копию монорепо
    вовсе. Резолюция та же, что у `scripts/vault-gate/_lib.sh`.
    """
    env = os.environ.get("KACHO_MONOREPO")
    if env and os.path.exists(os.path.join(env, ".git")):
        return env
    guess = os.path.join(root, "project", "kacho")
    if os.path.exists(os.path.join(guess, ".git")):
        return guess
    return None


# ── ПО ЧЕМУ СУДИТ НАБОР: СТВОЛ ПРОДУКТА, А НЕ РАБОЧАЯ КОПИЯ РЯДОМ ────────────
#
# Копия `project/kacho` ОБЩАЯ: её ревизию переключает соседняя сессия, не
# спрашивая отправляющего. Проверка, читающая её индекс, выносит вердикт, который
# есть ФУНКЦИЯ ЧУЖОГО ПЕРЕКЛЮЧЕНИЯ, — и блокирует отправку работой, к которой
# отправляющий не причастен.
#
# Расхождение копии со стволом двустороннее, и обе стороны обязаны быть названы
# ЧИСЛОМ. Только «отстаёт» недостаточно: копия, стоящая на релизной линии,
# отстаёт на 0 и опережает ствол на сотни коммитов, а односторонняя перепись на
# ней печатает ровно то же, что на копии вровень. Ровно этот класс наблюдался у
# хука свежести — `7ebb670d@HEAD — вровень со стволом main 1278df74`, две РАЗНЫЕ
# ревизии, названные согласованностью (`multi-agent-flow.md` §8).
#
# Ствол — `origin/main` продукта, и это ТА ЖЕ ссылка, что читает `check-04`:
# второй резолвер разошёлся бы с первым молча. Ссылка здесь НЕ ПОДТЯГИВАЕТСЯ
# (`fetch` — сеть, время и запись в чужой репозиторий, а набор гоняется на каждой
# отправке); вместо этого её отсутствие называется прямо, а не подставляется.
TRUNK_REF = "origin/main"


def _repo_git(repo, args):
    out = subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True)
    return out.stdout.strip() if out.returncode == 0 else None


def trunk(repo):
    """Ссылка ствола продукта, либо None — её в этом клоне нет."""
    if _repo_git(repo, ["rev-parse", "--verify", "--quiet", TRUNK_REF + "^{commit}"]):
        return TRUNK_REF
    return None


def provenance(repo):
    """По чему судили и насколько это расходится с рабочей копией — ЧИСЛОМ.

    «Вровень» — утверждение о РАВЕНСТВЕ РЕВИЗИЙ, а не о нуле в одном счётчике:
    ноль в `behind` означает лишь «ствол не содержит ничего, чего нет у меня», и
    копия, ушедшая вперёд, даёт тот же ноль. Поэтому `behind` и `ahead` считаются
    независимо, а равенство проверяется сравнением полных ревизий.
    """
    ref = trunk(repo)
    head_full = _repo_git(repo, ["rev-parse", "HEAD"]) or ""
    head_short = _repo_git(repo, ["rev-parse", "--short", "HEAD"]) or "?"
    branch = _repo_git(repo, ["rev-parse", "--abbrev-ref", "HEAD"]) or "?"
    rev_full = _repo_git(repo, ["rev-parse", ref]) if ref else None
    rev_short = _repo_git(repo, ["rev-parse", "--short", ref]) if ref else None
    behind = ahead = None
    if ref:
        b = _repo_git(repo, ["rev-list", "--count", "HEAD..%s" % ref])
        a = _repo_git(repo, ["rev-list", "--count", "%s..HEAD" % ref])
        behind = int(b) if b and b.isdigit() else None
        ahead = int(a) if a and a.isdigit() else None
    return {
        "ref": ref,
        "head": head_short,
        "head_full": head_full,
        "branch": branch,
        "rev": rev_short,
        "rev_full": rev_full,
        "behind": behind,
        "ahead": ahead,
        "same": bool(head_full) and head_full == rev_full,
    }


def provenance_line(repo, prov):
    """Строка переписи: что судилось и как рабочая копия с этим расходится.

    ОБА числа печатаются ВСЕГДА, когда они измерены. Печатать только ненулевое
    значило бы вернуть одностороннюю перепись, на которой «опережает на 407» и
    «вровень» выглядят одинаково.
    """
    where = "%s @ %s (%s)" % (repo, prov["head"], prov["branch"])
    if not prov["ref"]:
        return (where + "; ствол %s НЕ РЕЗОЛВИТСЯ — судится ИНДЕКС рабочей копии, "
                        "и вердикт зависит от того, на что она переключена" % TRUNK_REF)
    behind, ahead = prov["behind"], prov["ahead"]
    if behind is None or ahead is None:
        state = "расхождение с ним НЕ ИЗМЕРЕНО"
    else:
        pair = "(позади %d, впереди %d)" % (behind, ahead)
        if prov["same"]:
            state = "копия вровень с ним %s" % pair
        elif behind and ahead:
            state = "копия РАСХОДИТСЯ с ним %s" % pair
        elif behind:
            state = "копия ОТСТАЁТ от него %s" % pair
        elif ahead:
            state = "копия ОПЕРЕЖАЕТ его %s" % pair
        else:
            state = ("ревизии разные, а оба счётчика нулевые — расхождение НЕ ИЗМЕРЕНО "
                     "%s" % pair)
    return where + "; судится ствол %s %s, %s" % (prov["ref"], prov["rev"], state)


def head_and_lag(repo):
    """(ревизия, отставание от ствола|None) — узкий вид на `provenance`.

    Отдельного предиката здесь НЕТ намеренно: две копии одного счёта разошлись бы
    молча и ровно там, где обе отвечают «расхождение названо».
    """
    prov = provenance(repo)
    return prov["head"], prov["behind"]
