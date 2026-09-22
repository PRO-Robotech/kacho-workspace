#!/usr/bin/env python3
"""Признак дельты у сигнала хука: печатается РАЗНИЦА, а не состояние.

# Предмет

Сигнал хука печатал СОСТОЯНИЕ. Один и тот же блок выходил десятки ходов подряд при
неизменном дереве. Замер 2026-09-20: подряд идущих одинаковых строк переписи в
`.claude/hooks/docfresh/.state/census.log` — 42 в 17:26 и 51 в 17:55, то есть число
не константа, а РАСТЁТ с каждым ходом сессии; предикат —
`python3 .claude/hooks/lib/hook_signal.py --streak .claude/hooks/docfresh/.state/census.log`.
Повторённый сигнал неотличим от новой находки, поэтому НОВАЯ находка теряется в
фоне. Адресат — диспетчер: у него нет ни `Read`, ни `Bash`, он обязан верить
напечатанному и перепроверить его не может.

Класс уже опознавался ОДИН РАЗ внутри docfresh (`docfresh.py`, `census_append`:
«наблюдалось семь ходов подряд с одинаковым текстом») и был решён сменой канала
для ОДНОЙ строки. Разрез неверен: пока признак дельты не принадлежит сигналу КАК
ТАКОВОМУ, следующая печатаемая строка прибавится — и всё вернётся. Поэтому
механизм здесь один и общий, а не по одному на источник.

# Механизм

Отпечаток прошлого сигнала лежит в
`.claude/hooks/.state/signal/<сессия>/<id>.json` (каталог git-ignored, переопределяется
`HOOK_SIGNAL_STATE`). В нём: отпечаток тела, время и ревизия последней ПОЛНОЙ печати,
число повторов с тех пор.

  отпечатка нет (ПЕРВЫЙ ход сессии, новый id, снесённый каталог) → печатается ПОЛНОЕ
      тело. Отсутствие отпечатка НИКОГДА не читается как «уже говорили»: иначе
      потеря состояния глушила бы находку — ровно тот отказ, который механизм и ловит;
  отпечаток совпал                                              → одна строка
      «без изменений с <sha>@<время>»;
  отпечаток разошёлся (появилась находка, исчезла прежняя, сменились числа) → ПОЛНОЕ
      тело и новый отпечаток.

Летучие поля из отпечатка вычитаются (`_VOLATILE`): миллисекунды прогона и часы —
это не дельта предмета, а дельта прибора, и по ним блок печатался бы всегда.

# Два поля, без которых сигнал не печатается

`addressee` — агент, который предмет закрывает: диспетчер сам не чинит ничего.
`clear_when` — МАШИННО ПРОВЕРЯЕМЫЙ предикат снятия, команда с названным исходом, а
не словесное пожелание. Отсутствие любого из двух — собственная поломка сигнала
(код 2, громко): текст, о котором нельзя ни сказать «кому», ни проверить «когда
уйдёт», занимает канал находок и снимается вместе с каналом.

Образец самоистекающего предиката такого рода — послабление `allow.json`: «координата
больше не упоминается ни одним LIVE-документом» проверяется прогоном, а не чтением.

# Границы

Перепись объёма осмотренного НЕ снимается: «ноль находок» обязано остаться отличимо
от «ноль прочитанного» (`testing.md` §«Гейт на класс», п. 3). Меняется канал и форма
ПОВТОРА, а не утверждение: полное тело каждого сигнала уходит в
`<state>/<сессия>/<id>.log` при каждом прогоне, независимо от того, напечатан он или
свёрнут в строку. Проверяемость после факта от свёртки не страдает.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_STATE = Path(os.environ.get("HOOK_SIGNAL_STATE") or (HERE.parent / ".state" / "signal"))

# Летучее — то, что меняется без изменения предмета. Список закрытый и назван: молча
# вычитать из отпечатка что-либо ещё значило бы глушить настоящую дельту.
#
# Здесь только то, что летуче у ЛЮБОГО сигнала — время. Летучее своего прибора каждый
# источник объявляет сам (`volatile=` у `gate`, `--volatile` у CLI): «кэш тёплый»
# докfresh знает про себя, а общий механизм про его словарь знать не должен — иначе
# словарь одного источника вычитался бы из отпечатков всех.
_VOLATILE = (
    re.compile(r"\d+\s*мс"),                      # время прогона прибора
    re.compile(r"\d+\s*ms"),
    re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}"),   # отметка времени
    re.compile(r"(?<!\d)\d{2}:\d{2}:\d{2}(?!\d)"),
)

SESSIONS_KEEP = 40          # каталогов сессий на диске
SESSION_TTL_DAYS = 7
LOG_KEEP = 200              # строк в журнале полного тела сигнала


def _norm(body: str, volatile: tuple[str, ...] = ()) -> str:
    out = body
    for pat in _VOLATILE:
        out = pat.sub("", out)
    for raw in volatile:
        try:
            out = re.sub(raw, "", out)
        except re.error:
            # Негодное выражение НЕ отменяет свёртку и НЕ глушит сигнал: отпечаток
            # берётся без него, то есть в сторону ЛИШНЕЙ печати, а не молчания.
            pass
    return "\n".join(line.rstrip() for line in out.split("\n")).strip()


def fingerprint(sid: str, body: str, volatile: tuple[str, ...] = ()) -> str:
    h = hashlib.sha256()
    h.update(sid.encode("utf-8"))
    h.update(b"\x00")
    h.update(_norm(body, volatile).encode("utf-8"))
    return h.hexdigest()[:16]


def _safe(token: str, fallback: str) -> str:
    out = re.sub(r"[^A-Za-z0-9_.-]", "-", token or "")[:64].strip("-")
    return out or fallback


def _prune(root: Path) -> None:
    """Каталоги сессий не растут без предела. Отказ уборки вердикт не меняет."""
    try:
        dirs = sorted((p for p in root.iterdir() if p.is_dir()),
                      key=lambda p: p.stat().st_mtime, reverse=True)
    except OSError:
        return
    cutoff = time.time() - SESSION_TTL_DAYS * 86400
    for i, d in enumerate(dirs):
        try:
            if i < SESSIONS_KEEP and d.stat().st_mtime >= cutoff:
                continue
            for f in d.iterdir():
                f.unlink()
            d.rmdir()
        except OSError:
            pass


def _journal(path: Path, body: str) -> None:
    try:
        prev = ([x for x in path.read_text(encoding="utf-8").split("\n") if x.strip()]
                if path.is_file() else [])
        prev.append(time.strftime("%Y-%m-%dT%H:%M:%S") + " " + body.replace("\n", "\\n"))
        path.write_text("\n".join(prev[-LOG_KEEP:]) + "\n", encoding="utf-8")
    except OSError:
        pass


def gate(sid: str, body: str, *, addressee: str, clear_when: str,
         session: str | None = None, sha: str = "",
         state: Path | None = None,
         volatile: tuple[str, ...] = (),
         repeat_silent: bool = False) -> tuple[str, str]:
    """Возвращает (что печатать, исход). Исход: `full` · `repeat` · `void`.

    `void` — тело пустое: сигналу нечего сказать, печати нет. Предмет пустоты —
    забота вызывающего: он один знает, чего именно не было.
    """
    if not sid:
        raise ValueError("сигнал без имени: отпечаток не к чему привязать")
    if not addressee or not clear_when:
        raise ValueError(
            f"сигнал `{sid}` не называет " +
            ("агента-адресата" if not addressee else "") +
            (" и " if not addressee and not clear_when else "") +
            ("машинно проверяемый предикат снятия" if not clear_when else ""))
    if not body.strip():
        return "", "void"

    root = Path(state) if state else DEFAULT_STATE
    sess = _safe(session or os.environ.get("CLAUDE_SESSION_ID", ""), "no-session")
    name = _safe(sid, "signal")
    d = root / sess
    fp = fingerprint(sid, body, tuple(volatile))
    prev: dict = {}
    try:
        prev = json.loads((d / f"{name}.json").read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001  — нет отпечатка ⇒ печатаем полностью
        prev = {}

    repeated = prev.get("fp") == fp
    now = time.strftime("%Y-%m-%dT%H:%M:%S")
    rec = {
        "fp": fp,
        "at": prev.get("at", now) if repeated else now,
        "sha": prev.get("sha", sha) if repeated else sha,
        "n": int(prev.get("n", 0)) + 1 if repeated else 0,
    }
    try:
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{name}.json").write_text(json.dumps(rec, ensure_ascii=False), encoding="utf-8")
        _journal(d / f"{name}.log", body)
        _prune(root)
    except OSError:
        # Записать не удалось — печатаем ПОЛНОЕ тело. Сигнал, замолчавший из-за
        # недоступного состояния, — потерянная находка; лишняя печать — только шум.
        return body, "full"

    if not repeated:
        tail = (f"\n[сигнал `{sid}`] предикат снятия: {clear_when}"
                f" · адресат: {addressee}"
                f" · повтор без дельты будет свёрнут в строку")
        return body + tail, "full"

    if repeat_silent:
        # Молчание на повторе выдаётся ТОЛЬКО сигналу, у которого предмет пуст: ему
        # нечего повторять, и строка «без изменений» о пустоте — тот же фон, только
        # короче. Проверяемость после факта держит журнал (`<id>.log`) и перепись
        # прибора: они пишутся и при молчании, поэтому «ноль прочитанного» остаётся
        # отличимо от «ноль находок» — по журналу, а не по каналу находок.
        return "", "repeat"
    where = str((d / f"{name}.log"))
    when = f"{rec['sha'] or 'ревизия не названа'}@{rec['at']}"
    return (f"[сигнал `{sid}`] без изменений с {when} — повтор {rec['n']}-й, дельты нет."
            f" Предмет тот же, предикат снятия тот же: {clear_when} · адресат: {addressee}."
            f" Полное тело каждого прогона: {where}"), "repeat"


def _streak(path: Path, volatile: tuple[str, ...] = ()) -> int:
    """Сколько последних строк журнала совпадают после вычитания летучего.

    Это предикат для ОПИСАНИЯ дефекта и для приёмки, а не часть механизма.
    """
    lines = [l for l in path.read_text(encoding="utf-8").split("\n") if l.strip()]
    norm = [_norm(re.sub(r"^\S+\s", "", l), volatile) for l in lines]
    if not norm:
        return 0
    n = 0
    for x in reversed(norm):
        if x == norm[-1]:
            n += 1
        else:
            break
    return n


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(add_help=True, description=__doc__)
    ap.add_argument("--id")
    ap.add_argument("--addressee", default="")
    ap.add_argument("--clear-when", default="")
    ap.add_argument("--session", default="")
    ap.add_argument("--sha", default="")
    ap.add_argument("--state", default="")
    ap.add_argument("--volatile", action="append", default=[],
                    help="выражение, летучее у ЭТОГО прибора (можно несколько)")
    ap.add_argument("--repeat-silent", action="store_true",
                    help="на повторе не печатать ничего — только для сигнала с ПУСТЫМ предметом")
    ap.add_argument("--streak", default="")
    a = ap.parse_args(argv)

    if a.streak:
        p = Path(a.streak)
        if not p.is_file():
            sys.stderr.write(f"signal --streak: нет файла {p} — не прочитано НИ ОДНОЙ строки\n")
            return 2
        print(_streak(p, tuple(a.volatile)))
        return 0

    body = sys.stdin.read()
    try:
        text, mode = gate(a.id or "", body, addressee=a.addressee, clear_when=a.clear_when,
                          session=a.session, sha=a.sha,
                          state=Path(a.state) if a.state else None,
                          volatile=tuple(a.volatile), repeat_silent=a.repeat_silent)
    except ValueError as e:
        sys.stderr.write(
            "╔══ СИГНАЛ ХУКА СЛОМАН ═══════════════════════════════════════════\n"
            f"║ {e}\n"
            "║ Печатаемый сигнал обязан называть двоих: агента, который предмет\n"
            "║ закрывает, и МАШИННО ПРОВЕРЯЕМЫЙ предикат своего снятия. Без них\n"
            "║ сигнал нельзя ни адресовать, ни снять — он остаётся фоном навсегда.\n"
            "║ → tooling-maintainer: провязка сигнала (.claude/hooks/lib/hook_signal.py).\n"
            "╚═════════════════════════════════════════════════════════════════\n")
        return 2
    if mode != "void":
        sys.stdout.write(text + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
