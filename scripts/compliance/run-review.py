#!/usr/bin/env python3
"""Ревью с ПОЛНЫМИ правилами над работой дешёвой полосы.

ЧТО ПРОВЕРЯЕТСЯ. Предложение владельца: согласиться на 76% от исполнителя без
правил в окне и добрать регламент обязательным ревью, у которого правила есть.
Мерится ровно это: поднимает ли ревью долю выполненных требований — теми же
проверками, что судили исполнителя.

ЧЕГО РЕВЬЮЕР НЕ ЗНАЕТ — и это несущее условие. Ему НЕ говорят, какие проверки
существуют и какие из них провалены. Скажи — и он починит названное, а замер
покажет послушание вместо знания регламента. Ему дают ровно то, что дали бы в
работе: задание, произведённый артефакт и требование привести к регламенту.

ЕДИНИЦА. Те же 29 проверок. Плюс цена: сколько токенов и секунд стоил круг.
"""
from __future__ import annotations
import json, os, re, subprocess, sys, time

R = "/home/dk/tmp/review"


def оценить(text, checks):
    env = {"__builtins__": {"len": len, "any": any, "all": all, "sum": sum,
                            "min": min, "max": max, "sorted": sorted, "set": set,
                            "list": list, "str": str, "int": int, "bool": bool,
                            "enumerate": enumerate, "zip": zip, "map": map,
                            "filter": filter, "abs": abs}, "re": re, "text": text}
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
    items = json.load(open(f"{R}/items.json", encoding="utf-8"))
    корень = f"{R}/ws"
    итог = []
    for it in items:
        # артефакт кладём в копию ревьюера по тому же относительному пути
        цель = os.path.join(корень, it["отн"])
        os.makedirs(os.path.dirname(цель), exist_ok=True)
        исход_текст = open(it["artifact"], encoding="utf-8", errors="replace").read()
        open(цель, "w", encoding="utf-8").write(исход_текст)

        задание = (
            "Работу ниже сделала соседняя полоса. Твоё дело — ПРИНЯТЬ ЕЁ ПО РЕГЛАМЕНТУ:\n"
            "найти, чем она регламенту не отвечает, и привести в соответствие.\n\n"
            "Правь ФАЙЛ на месте: " + os.path.join(корень, it["отн"]) + "\n"
            "Других файлов не трогай. Верни: что нашёл и что исправил, по пунктам.\n\n"
            "ЗАДАНИЕ, которое выполняла полоса:\n---\n" + it["task"] + "\n---\n\n"
            "Регламент тебе известен — он в твоих инструкциях. Ищи расхождения сам:\n"
            "перечня нарушений тебе НЕ дают, потому что проверяется знание нормы, а не\n"
            "исполнение подсказки."
        )
        t0 = time.time(); оборван = ""
        try:
            subprocess.run(["claude", "-p", "--permission-mode", "bypassPermissions",
                            "--model", "sonnet"], cwd=корень, input=задание,
                           capture_output=True, text=True, timeout=1200)
        except subprocess.TimeoutExpired:
            оборван = "оборван по времени (1200 с)"
        dt = time.time() - t0
        после = open(цель, encoding="utf-8", errors="replace").read() if os.path.exists(цель) else ""
        n, разбор = оценить(после, it["checks"])
        было_n = int(it["было"].split("/")[0])
        r = {"id": it["id"], "было": it["было"], "стало": f"{n}/{len(it['checks'])}",
             "сдвиг": n - было_n, "секунд": round(dt, 1),
             "тронут": после != исход_текст, "оборван": оборван, "разбор": разбор}
        итог.append(r)
        print(f"  [{it['id']:10s}] {it['было']} → {n}/{len(it['checks'])} "
              f"({r['сдвиг']:+d}) · {r['секунд']:>6.0f}с · файл "
              f"{'тронут' if r['тронут'] else 'НЕ ТРОНУТ'}"
              + (f"  ← {оборван}" if оборван else ""), flush=True)
    б = sum(int(x["было"].split("/")[0]) for x in итог)
    с = sum(int(x["стало"].split("/")[0]) for x in итог)
    в = sum(int(x["стало"].split("/")[1]) for x in итог)
    print(f"\n  ДО РЕВЬЮ  {б}/{в} = {б/в*100:.0f}%")
    print(f"  ПОСЛЕ     {с}/{в} = {с/в*100:.0f}%   ({с-б:+d} требований)")
    json.dump(итог, open(f"{R}/out/result.json", "w"), ensure_ascii=False, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
