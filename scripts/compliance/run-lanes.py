#!/usr/bin/env python3
"""Замер НАРЕЗКИ полосы: что делает её закрываемой.

ПРЕДМЕТ. Предмет `migration` не закрылся НИ В ОДНОЙ из трёх посадок замера
соблюдения: в двух файл не создан, в одной прогон оборван на 1200 с. Все
остальные семь предметов закрылись. Вопрос: чем эта полоса отличается.

ТРИ ОБЪЯСНЕНИЯ, и замер их РАЗДЕЛЯЕТ — каждая посадка меняет ровно один факт:

  D    задание ЦЕЛИКОМ, предел 2400 с вместо 1200   → «не хватило времени»?
  C    только МИГРАЦИЯ, путь записи объявлен чужим  → «слоёв слишком много»?
  B2   только ПУТЬ ЗАПИСИ при ГОТОВОЙ миграции      → вторая половина нарезки
  ctl  один слой, но объём работы сопоставим с D    → «объём слишком велик»?

`ctl` — несущий контроль. Без него «C закрылся» читалось бы как «слоёв меньше»,
тогда как верное объяснение могло быть «работы меньше». `ctl` даёт один слой при
сопоставимом объёме: закроется — виноваты слои, не закроется — виноват объём.

ЕДИНИЦА. Закрылось/нет · время · те же пять проверок регламента, что судили
предмет в замере соблюдения. Третья категория считается отдельно.
"""
from __future__ import annotations
import json, os, re, subprocess, sys, time

L = "/home/dk/tmp/lanes"
МИГРАЦИЯ = "services/vpc/internal/migrations/20260907120000_gateway_network_binding.sql"
ЗАПИСЬ = "services/vpc/internal/repo/kacho/pg/gateway.go"

ПОСАДКИ = [
    ("D",   "task-D.txt",   2400, МИГРАЦИЯ),
    ("C",   "task-C.txt",   1200, МИГРАЦИЯ),
    ("ctl", "task-ctl.txt", 1200, МИГРАЦИЯ),
    ("B2",  "task-B2.txt",  1200, ЗАПИСЬ),
]


def проверить(text: str, checks: list) -> tuple[int, list]:
    env = {"__builtins__": {"len": len, "any": any, "all": all, "sum": sum,
                            "min": min, "max": max, "sorted": sorted, "set": set,
                            "list": list, "str": str, "int": int, "bool": bool,
                            "enumerate": enumerate, "zip": zip, "map": map,
                            "filter": filter, "abs": abs},
           "re": re, "text": text}
    n, разбор = 0, []
    for c in checks:
        try:
            ок = bool(eval(c["python"], env, env))
        except Exception as e:
            разбор.append({"name": c["name"][:44], "исход": f"выражение отказало: {type(e).__name__}"})
            continue
        n += int(ок)
        разбор.append({"name": c["name"][:44], "исход": "соблюдено" if ок else "НАРУШЕНО"})
    return n, разбор


def main() -> int:
    checks = json.load(open(f"{L}/checks.json", encoding="utf-8"))
    итог = []
    for имя, файл_задачи, предел, артефакт in ПОСАДКИ:
        корень = f"{L}/ws-{имя}"
        продукт = f"{L}/{имя}"
        задание = open(f"{L}/{файл_задачи}", encoding="utf-8").read()
        задание = задание.replace("services/vpc/internal/migrations/", "services/vpc/internal/migrations/")
        путь = os.path.join(продукт, артефакт)
        было = os.path.getmtime(путь) if os.path.exists(путь) else 0
        # B2 получает готовую миграцию — её кладёт предыдущая посадка C.
        if имя == "B2":
            исток = os.path.join(f"{L}/C", МИГРАЦИЯ)
            if os.path.exists(исток):
                os.makedirs(os.path.dirname(os.path.join(продукт, МИГРАЦИЯ)), exist_ok=True)
                open(os.path.join(продукт, МИГРАЦИЯ), "w", encoding="utf-8").write(
                    open(исток, encoding="utf-8").read())
                print(f"  [B2] миграция от C подложена: {os.path.getsize(исток)} байт", flush=True)
            else:
                print("  [B2] ОТКАЗ: C миграции не произвёл, подкладывать нечего", flush=True)
        t0 = time.time()
        оборван = ""
        try:
            subprocess.run(["claude", "-p", "--permission-mode", "bypassPermissions",
                            "--model", "sonnet"], cwd=корень, input=задание,
                           capture_output=True, text=True, timeout=предел)
        except subprocess.TimeoutExpired:
            оборван = f"оборван по времени ({предел} с)"
        except OSError as e:
            оборван = f"не запустился: {type(e).__name__}"
        dt = time.time() - t0
        создан = os.path.exists(путь) and os.path.getmtime(путь) > было
        if оборван or not создан:
            r = {"посадка": имя, "исход": "НЕ ЗАКРЫЛОСЬ",
                 "почему": оборван or "артефакт не появился",
                 "секунд": round(dt, 1), "прошло": 0, "всего": len(checks)}
        else:
            text = open(путь, encoding="utf-8", errors="replace").read()
            n, разбор = проверить(text, checks) if артефакт == МИГРАЦИЯ else (0, [])
            r = {"посадка": имя, "исход": "закрылось", "секунд": round(dt, 1),
                 "прошло": n, "всего": len(checks) if артефакт == МИГРАЦИЯ else 0,
                 "байт": len(text), "разбор": разбор}
        # что ещё тронуто — число слоёв меряется по дереву, а не по заданию
        тронуто = subprocess.run(["git", "-C", продукт, "status", "--porcelain"],
                                 capture_output=True, text=True).stdout.strip().splitlines()
        r["файлов_тронуто"] = len(тронуто)
        r["слоёв"] = len({("миграция" if "/migrations/" in x else
                           "репозиторий" if "/repo/" in x else
                           "домен" if "/domain/" in x else
                           "прочее") for x in тронуто})
        итог.append(r)
        print(f"  [{имя:3s}] {r['исход']:12s} {r['секунд']:>7.0f}с · файлов {r['файлов_тронуто']} "
              f"· слоёв {r['слоёв']} · проверок {r['прошло']}/{r['всего']}"
              + (f"  ← {r.get('почему','')}" if r["исход"] != "закрылось" else ""), flush=True)
    json.dump(итог, open(f"{L}/out/result.json", "w"), ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
