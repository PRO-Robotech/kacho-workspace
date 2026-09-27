#!/usr/bin/env python3
"""Настройки харнесса в корне ОТСТАЮТ от ствола: чего из `origin/main` в них нет.

# Предмет (ws#796)

Харнесс читает `.claude/settings.json` из КОРНЯ сессии при её старте. Корень стоит на
чьей-то ветке, и если она старше настройки, настройка не действует — а сигнала об
этом нет. Замер 2026-09-27: корень на ветке без #715, ключа `attribution` в его
настройках нет, на стволе есть; сессия получала от среды напоминание дописывать
трейлеры атрибуции, запрет держался вниманием исполнителя.

# Единица — лист настроек, а не имя ключа

Сравнение идёт по листьям пути словаря (`attribution.commit`). Отставание — путь,
который есть на стволе и которого нет в корне. Обратное (в корне есть, на стволе нет)
— работа ветки корня, не отставание, и не называется. РАЗНОЕ ЗНАЧЕНИЕ одного пути
тоже не называется: это может быть правка ветки корня, и судить её здесь не по чему.

# Элемент списка — ЗАПИСЬ, и корень вправе её расширить

Элемент списка (группа хуков события, регистрация хука) — запись. Элемент ствола
покрыт, если в том же списке корня есть запись-НАДМНОЖЕСТВО: те же скаляры (matcher,
команда, тип — это личность записи), а её списки содержат покрытие каждого элемента
списков ствола. Корень, ушедший вперёд (добавил хук в существующую группу), так не
отстаёт. До 2026-09-28 элемент сравнивался целиком по JSON, и группа ствола из трёх
хуков считалась отсутствующей в корне, где их четыре: сигнал звал влить ствол, а
вливание ничего не меняло — предикат снятия был недостижим.

Не покрыт — называется РАЗНИЦА, а не запись целиком: запись корня с той же личностью
есть — названы её недостающие части (сам отсутствующий хук); такой нет — названа
запись ствола. Скаляр ВНУТРИ записи сравнивается на равенство: другой matcher или
другая команда — другая запись, и она называется (граница: изменённый корнем
`timeout` регистрации тоже прочтётся отставанием этой регистрации).

# Граница

Хук, печатающий это, исполняется из КОРНЯ — то есть только там, где ветка корня
уже несёт сам хук. Корень, отставший раньше, чем хук появился, этот сигнал не
получит никогда: там отставание снимается вливанием ствола в ветку корня.

Именно это условие называет сама задача (корень на ветке старше #715), и в нём
механизм НЕ действует: провязка хука приезжает вместе с настройками, где
`attribution` уже есть. Держатель, который сработал бы и там, обязан лежать ВНЕ
ветки корня (личный `~/.claude/settings.json`, policy) — любой держатель в дереве
стареет вместе с ним. Проверить, покрыт ли корень, — предикатом, не вниманием:
`git -C <корень> show HEAD:.claude/settings.json | grep -c settings-lag.sh` →
0 значит «этот корень сигнала не получит».

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


def _is_scalar(v) -> bool:
    return not isinstance(v, (dict, list))


def _same_record(t: dict, r) -> bool:
    """Личность записи — её скаляры (matcher, команда, тип): у записи корня те же."""
    return isinstance(r, dict) and all(k in r and r[k] == v for k, v in t.items() if _is_scalar(v))


def _record_missing(t: dict, r: dict, path: str) -> list[str]:
    """Чего в записи корня `r` нет из записи ствола `t` той же личности. Пусто — покрыта."""
    out: list[str] = []
    for k, v in t.items():
        p = f"{path}.{k}"
        if k not in r:
            out += sorted(leaves(v, p))
        elif isinstance(v, list):
            out += _list_missing(v, r[k], p)
        elif isinstance(v, dict):
            out += (_record_missing(v, r[k], p) if isinstance(r[k], dict)
                    else sorted(leaves(v, p)))
        elif r[k] != v:
            out.append(f"{p}=" + json.dumps(v, ensure_ascii=False))
    return out


def _list_missing(tl: list, rl, path: str) -> list[str]:
    """Каждый элемент списка ствола — запись; покрыта записью корня-надмножеством."""
    if not isinstance(rl, list):
        return sorted(leaves(tl, path))
    out: list[str] = []
    for item in tl:
        if not isinstance(item, dict):
            if item not in rl:
                out.append(f"{path}[]" + json.dumps(item, ensure_ascii=False, sort_keys=True))
            continue
        same = [ri for ri in rl if _same_record(item, ri)]
        if not same:
            out.append(f"{path}[]" + json.dumps(item, ensure_ascii=False, sort_keys=True))
            continue
        # Покрыта, если хоть одна запись той же личности — надмножество (разница пуста);
        # иначе называется разница с ближайшей из них, а не запись целиком.
        out += min((_record_missing(item, ri, f"{path}[]") for ri in same), key=len)
    return out


def missing(trunk, mine, path: str = "") -> list[str]:
    """Листья ствола, которых нет в корне. Путь словаря — как прежде; список — записи."""
    if isinstance(trunk, dict):
        if not isinstance(mine, dict):
            return []            # тот же путь, другая форма значения — правка ветки корня
        out: list[str] = []
        for k, v in trunk.items():
            p = f"{path}.{k}" if path else k
            if k not in mine:
                out += sorted(leaves(v, p))
            else:
                out += missing(v, mine[k], p)
        return out
    if isinstance(trunk, list):
        return _list_missing(trunk, mine, path)
    return []                    # путь есть; другое значение — не отставание


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
    lagging = sorted(set(missing(trunk, mine)))
    return lagging, sha


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
