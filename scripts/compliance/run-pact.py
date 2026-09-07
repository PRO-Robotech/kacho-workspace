#!/usr/bin/env python3
"""Посадка `pact`: минимум правил в окне + КОНТРАКТ ПОЛОСЫ.

ГИПОТЕЗА, ЗАПИСАННАЯ ДО ПРОГОНА. Требование приложить к работе команду, которая
её опровергает, вынуждает ровно те действия, которые проверки и ищут: инъекцию
у гейта, перепись объёма осмотренного, предикат при числе. Поэтому `pact`
обязан обогнать и `base` (85%, все правила в окне), и `lane` (76%, правило в
задании) — при преамбуле как у `lane`.

ЧЕМ ОПРОВЕРГАЕТСЯ. Не обгонит — схема отвергнута. Обгонит, но контракт съест
время — отвергнута по цене, и время считается здесь же.

ЧЕГО ИСПОЛНИТЕЛЮ НЕ ГОВОРЯТ. Ни одной из 39 проверок. Контракт требует
СПОСОБНОСТИ работу опровергнуть, а не прохождения названного списка: иначе
мерилось бы послушание.
"""
from __future__ import annotations
import json, os, re, subprocess, sys, time

PT = "/home/dk/tmp/pact"
W = "/home/dk/workspace/github/PRO-Robotech/cloud-demo/kacho-workspace"


def оценить(text, checks):
    env = {"__builtins__": {"len": len, "any": any, "all": all, "sum": sum, "min": min,
                            "max": max, "sorted": sorted, "set": set, "list": list,
                            "str": str, "int": int, "bool": bool, "enumerate": enumerate,
                            "zip": zip, "map": map, "filter": filter, "abs": abs},
           "re": re, "text": text}
    n, разбор = 0, []
    for c in checks:
        try:
            ок = bool(eval(c["python"], env, env))
        except Exception as e:
            разбор.append({"name": c["name"][:44], "исход": f"отказ: {type(e).__name__}"}); continue
        n += int(ок)
        разбор.append({"name": c["name"][:44], "исход": "соблюдено" if ок else "НАРУШЕНО"})
    return n, разбор


def main() -> int:
    контракт = open(f"{PT}/contract.txt", encoding="utf-8").read()
    пункты = json.load(open("/home/dk/tmp/comp/bench.json", encoding="utf-8"))
    корень = f"{PT}/ws"
    итог = []
    for п in пункты:
        сыр = п["artifact_path"]
        отн = сыр.replace(W, "").lstrip("/")
        if os.path.isabs(сыр) and W not in сыр:
            отн = os.path.join("tmp/bench", os.path.basename(сыр))
        путь = os.path.realpath(os.path.join(корень, отн))
        if not путь.startswith(os.path.realpath(корень) + os.sep):
            итог.append({"id": п["id"], "исход": "НЕ ВЫПОЛНИЛОСЬ", "почему": "путь вне копии",
                         "прошло": 0, "всего": len(п["checks"]), "секунд": 0.0}); continue
        os.makedirs(os.path.dirname(путь), exist_ok=True)
        if os.path.exists(путь):
            os.remove(путь)
        задание = п["task_text"].replace(W, корень)
        if os.path.isabs(сыр) and W not in сыр:
            задание = задание.replace(сыр, путь)
        задание = задание + "\n" + контракт
        t0 = time.time(); оборван = ""
        try:
            subprocess.run(["claude", "-p", "--permission-mode", "bypassPermissions",
                            "--model", "sonnet"], cwd=корень, input=задание,
                           capture_output=True, text=True, timeout=1200)
        except subprocess.TimeoutExpired:
            оборван = "оборван по времени (1200 с)"
        except OSError as e:
            оборван = f"не запустился: {type(e).__name__}"
        dt = time.time() - t0
        pact_путь = путь + ".pact.md"
        if оборван or not os.path.exists(путь):
            r = {"id": п["id"], "исход": "НЕ ВЫПОЛНИЛОСЬ", "почему": оборван or "файл не создан",
                 "прошло": 0, "всего": len(п["checks"]), "секунд": round(dt, 1),
                 "тройка": os.path.exists(pact_путь)}
        else:
            text = open(путь, encoding="utf-8", errors="replace").read()
            n, разбор = оценить(text, п["checks"])
            r = {"id": п["id"], "исход": "прогнан", "прошло": n, "всего": len(п["checks"]),
                 "секунд": round(dt, 1), "разбор": разбор,
                 "тройка": os.path.exists(pact_путь),
                 "тройка_байт": os.path.getsize(pact_путь) if os.path.exists(pact_путь) else 0}
        итог.append(r)
        print(f"  [pact] {r['id']:10s} {r['прошло']}/{r['всего']} · {r['секунд']:>6.0f}с "
              f"· тройка {'ЕСТЬ' if r['тройка'] else 'НЕТ'}"
              + (f"  ← {r.get('почему','')}" if r["исход"] != "прогнан" else ""), flush=True)
    пр = sum(r["прошло"] for r in итог if r["исход"] == "прогнан")
    вс = sum(r["всего"] for r in итог if r["исход"] == "прогнан")
    if вс == 0:
        # Третья категория целиком: вердикта нет НИ У ОДНОГО предмета.
        # Печатать «0%» здесь значило бы выдать отказ инфраструктуры за
        # нарушение регламента — ровно то, что правило запрещает.
        print(f"\n  ПОСАДКА pact: ВЕРДИКТА НЕТ — прогнан 0 предметов из {len(итог)}. "
              f"Причины: {sorted({r.get('почему','?') for r in итог})}")
        json.dump(итог, open(f"{PT}/out/pact.json", "w"), ensure_ascii=False, indent=1)
        return 3
    с_тройкой = sum(1 for r in итог if r.get("тройка"))
    print(f"\n  ПОСАДКА pact: соблюдено {пр}/{вс} = {пр/вс*100:.0f}% "
          f"· тройку приложили {с_тройкой} из {len(итог)} "
          f"· не выполнилось {sum(1 for r in итог if r['исход'] != 'прогнан')}")
    json.dump(итог, open(f"{PT}/out/pact.json", "w"), ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
