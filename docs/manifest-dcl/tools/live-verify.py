#!/usr/bin/env python3
"""Сходимость манифеста DCL с ДЕЙСТВУЮЩИМИ ролями и выдачами.

Источник — снимок живой базы iam (live-*.txt), а не реконструкция миграций:
134 миграции переопределяют друг друга, и итог из них выводится с ошибкой.

Замер отвечает на четыре ВОПРОСА, а не печатает одно число: сходимость по
разным осям разная, и среднее по ним лгало бы.
"""
import json
import re
import sys
from collections import defaultdict

import yaml

CANON = {"get", "list", "create", "update", "delete"}


def live_roles(path):
    out = {}
    for ln in open(path, encoding="utf-8"):
        ln = ln.rstrip("\n")
        if not ln or "|" not in ln:
            continue
        name, perms = ln.split("|", 1)
        out[name] = json.loads(perms)
    return out


def manifest(path):
    d = yaml.safe_load(open(path, encoding="utf-8"))
    res = {}
    for r in d["resources"]:
        vs = {}
        for v in r["verbs"]:
            if isinstance(v, str):
                vs[v] = (v, False, False)
            else:
                vs[v["name"]] = (v.get("class") or v["name"],
                                 bool(v.get("internal")), bool(v.get("admin")))
        res[r["name"]] = vs
    return d, d["module"], res


def snake(s):
    return re.sub(r"(?<!^)(?=[A-Z])", "_", s).lower()


def main(mpath, rpath, module):
    d, mod, res = manifest(mpath)
    live = {k: v for k, v in live_roles(rpath).items() if k.startswith(module + ".")}

    print("═" * 74)
    print(f"СХОДИМОСТЬ МАНИФЕСТА С ДЕЙСТВУЮЩИМИ РОЛЯМИ — модуль {module}")
    print("═" * 74)
    print(f"снимок живой базы: ролей {module} — {len(live)}; "
          f"манифест: ресурсов {len(res)}, ролей {len(d.get('roles', []))}")

    # ── A. Ресурс роли резолвится в манифест ────────────────────────────
    live_res, gram, verbs_used = set(), defaultdict(int), defaultdict(int)
    for name, perms in live.items():
        for p in perms:
            seg = p.split(".")
            gram[len(seg)] += 1
            if len(seg) == 4:
                live_res.add(seg[1]); verbs_used[seg[3]] += 1
    known = set(res)
    hit = sorted(live_res & known)
    miss = sorted(live_res - known)
    print(f"\n── A. Ресурсы, названные ролями ── {len(live_res)}")
    print(f"   резолвятся манифестом: {len(hit)} · нет: {len(miss)}")
    for m in miss:
        print(f"     ✗ {module}.{m}")
    only_manifest = sorted(known - live_res)
    print(f"   есть в манифесте, но НИ ОДНА роль их не называет: {len(only_manifest)}")
    for m in only_manifest:
        print(f"     · {module}.{m}")

    # ── B. Грамматика ───────────────────────────────────────────────────
    print(f"\n── B. Грамматика права ──")
    for n, c in sorted(gram.items()):
        print(f"   сегментов {n}: {c} прав")
    print(f"   манифест производит: 3 сегмента (module.resource.verb)")

    # ── C. Словарь глаголов ─────────────────────────────────────────────
    dep = d.get("deprecatedVerbs") or {}
    man_verbs = {v for vs in res.values() for v in vs}
    man_classes = {c for vs in res.values() for c, _, _ in vs.values()}
    print(f"\n── C. Глаголы ролей ── различных {len(verbs_used)}")
    for v, c in sorted(verbs_used.items(), key=lambda x: -x[1]):
        if v == "*":
            verdict = "подстановка — все действия ресурса"
        elif v in man_verbs:
            verdict = "есть действием"
        elif v in dep:
            verdict = f"принят совместимостью → класс {dep[v]['class']}"
        elif v in man_classes:
            verdict = "есть КЛАССОМ, действия с таким именем нет"
        else:
            verdict = "✗ НЕТ НИ ДЕЙСТВИЕМ, НИ КЛАССОМ"
        print(f"   {v:16} ×{c:<3} {verdict}")

    # ── D. Каждая живая роль воспроизводима манифестом? ─────────────────
    print(f"\n── D. Воспроизводимость каждой роли ──")
    ok = bad = 0
    for name in sorted(live):
        perms = live[name]
        reasons = []
        for p in perms:
            seg = p.split(".")
            if len(seg) != 4:
                reasons.append(f"грамматика {len(seg)} сегм."); continue
            _, r, rn, v = seg
            if r not in res:
                reasons.append(f"ресурса {r} нет"); continue
            if v == "*":
                continue                     # все действия ресурса
            if v in res[r] or v in {c for c, _, _ in res[r].values()} or v in dep:
                continue
            reasons.append(f"глагол {v} не выражается")
        if reasons:
            bad += 1
            print(f"   ✗ {name:28} {'; '.join(sorted(set(reasons)))}")
        else:
            ok += 1
    print(f"   воспроизводимо {ok} из {len(live)} — {ok*100.0/max(1,len(live)):.1f}%")
    return 0 if not (miss or bad) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "vpc"))
