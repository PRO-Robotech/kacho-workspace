#!/usr/bin/env python3
"""Настройки харнесса в корне ОТСТАЮТ от ствола: чего из `origin/main` в них нет.

# Предмет (ws#796)

Харнесс читает `.claude/settings.json` из КОРНЯ сессии при её старте. Корень стоит на
чьей-то ветке, и если она старше настройки, настройка не действует — а сигнала об
этом нет. Замер 2026-09-27: корень на ветке без #715, ключа `attribution` в его
настройках нет, на стволе есть; сессия получала от среды напоминание дописывать
трейлеры атрибуции, запрет держался вниманием исполнителя.

# Единица — лист настроек, а не имя ключа

Сравнение идёт по листьям: путь словаря (`attribution.commit`) и элемент списка по
его каноническому JSON (регистрация хука целиком). Отставание — лист, который есть
на стволе и которого нет в корне. Обратное (в корне есть, на стволе нет) — работа
ветки корня, не отставание, и не называется. РАЗНОЕ ЗНАЧЕНИЕ одного пути тоже не
называется: это может быть правка ветки корня, и судить её здесь не по чему.

# Граница

Хук, печатающий это, исполняется из КОРНЯ — то есть только там, где ветка корня
уже несёт сам хук. Корень, отставший раньше, чем хук появился, этот сигнал не
получит никогда: там отставание снимается вливанием ствола в ветку корня.

CLI: `settings_lag.py <корень>` → код 0 и строки отставших листьев на stdout
(пусто — отставания нет); код 2 — судить не по чему (нет ствола, нет файла, не
разбирается), причина на stderr.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

TRUNK = "origin/main"
REL = ".claude/settings.json"


def leaves(node, path: str = "") -> set[str]:
    out: set[str] = set()
    if isinstance(node, dict):
        if not node and path:
            out.add(path + "={}")
        for k, v in node.items():
            out |= leaves(v, f"{path}.{k}" if path else k)
    elif isinstance(node, list):
        for item in node:
            out.add(f"{path}[]" + json.dumps(item, ensure_ascii=False, sort_keys=True))
    else:
        out.add(f"{path}=" + json.dumps(node, ensure_ascii=False))
    return out


def lag(root: Path) -> tuple[list[str], str]:
    local = root / REL
    if not local.is_file():
        raise LookupError(f"в корне {root} нет {REL}")
    try:
        mine = json.loads(local.read_text(encoding="utf-8"))
    except ValueError as e:
        raise LookupError(f"{local} не разбирается как JSON: {e}") from e
    p = subprocess.run(["git", "-C", str(root), "show", f"{TRUNK}:{REL}"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise LookupError(f"{TRUNK}:{REL} не читается в {root} — ствола нет или файла на нём нет")
    try:
        trunk = json.loads(p.stdout)
    except ValueError as e:
        raise LookupError(f"{TRUNK}:{REL} не разбирается как JSON: {e}") from e
    sha = subprocess.run(["git", "-C", str(root), "rev-parse", "--short", TRUNK],
                         capture_output=True, text=True).stdout.strip()
    have = leaves(mine)
    # Лист «ключ=значение» отстаёт, только если ПУТИ нет вовсе: другое значение того же
    # пути — работа ветки корня, а не отставание.
    have_paths = {x.split("=", 1)[0] for x in have if "=" in x and "[]" not in x.split("=", 1)[0]}
    missing = []
    for x in sorted(leaves(trunk) - have):
        if "=" in x and "[]" not in x.split("=", 1)[0] and x.split("=", 1)[0] in have_paths:
            continue
        missing.append(x)
    return missing, sha


def main(argv: list[str]) -> int:
    root = Path(argv[0] if argv else ".").resolve()
    try:
        missing, sha = lag(root)
    except LookupError as e:
        sys.stderr.write(f"{e}\n")
        return 2
    for m in missing:
        print(m)
    sys.stderr.write(f"ствол {TRUNK} {sha}: отставших листьев {len(missing)}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
