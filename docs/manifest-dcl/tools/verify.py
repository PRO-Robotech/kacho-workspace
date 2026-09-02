#!/usr/bin/env python3
"""Итоговый замер сходимости DCL на ВСЕХ доступных методах двух API.

Проверяет три вещи, а не одну:
  1. манифест грузится по правилам схемы (иначе он не манифест, а текст);
  2. каждая операция API находит своё право (покрытие);
  3. одно право не обслуживает две операции РАЗНОГО смысла (различимость) —
     без этого 100% достигается склейкой всего в одно право.
"""
import glob
import importlib.util
import json
import re
import sys
from collections import defaultdict

spec = importlib.util.spec_from_file_location("dcl", "dcl.py")
dcl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dcl)


import os as _os
_HERE = _os.path.dirname(_os.path.abspath(__file__))
_UP = _os.path.dirname(_HERE)


def _dirs(*cands):
    """Каталог порождённых манифестов ищется по нескольким раскладкам:
    рядом со скриптом (как в проработке) и в ../generated (как в дереве)."""
    import glob as _g
    for c in cands:
        for base in (_HERE, _UP):
            pat = _os.path.join(base, c, "*.yaml")
            # Проверяется НАЛИЧИЕ ФАЙЛОВ, а не каталога: `../generated`
            # существует и пуст на верхнем уровне — манифесты лежат в его
            # подкаталогах, и проверка по isdir возвращала пустую выборку.
            if _g.glob(pat):
                return pat
    return _os.path.join(_HERE, cands[0], "*.yaml")


def load_all(pattern):
    perms, errs = {}, []
    for f in sorted(glob.glob(pattern)):
        try:
            _, p, _ = dcl.load_manifest(f)
            perms.update(p)
        except Exception as e:
            errs.append((f, str(e)))
    return perms, errs


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


# ─────────────── Kachō: сверка по ВСЕМ RPC, не только по каталогу ───────────
# Сопоставление ТОЧНОЕ: verify зовёт ту же функцию разбора, что и генератор.
# Нечёткий поиск по подстроке давал ложные попадания и «лишние» права.
gspec = importlib.util.spec_from_file_location("gen", "gen.py")
gen = importlib.util.module_from_spec(gspec)
gspec.loader.exec_module(gen)


def verify_kacho(perms):
    rpcs = json.load(open("kacho-rpcs.json", encoding="utf-8"))
    cat = {e["fqn"]: e for e in json.load(open("kacho-catalog.json", encoding="utf-8"))}
    covered, missing = [], []
    for r in rpcs:
        e = cat.get(r["fqn"]) or {"fqn": r["fqn"], "permission": "",
                                  "exempt_reason": "NOT_IN_CATALOG"}
        pn = gen.perm_name(e)
        if pn is None:
            missing.append((r["fqn"], None))
            continue
        name = pn[0]
        (covered if name in perms else missing).append(
            (r["fqn"], name if name in perms else None))
    return covered, missing, len(rpcs)


def kacho_distinctness(covered):
    """Одно право на два РАЗНЫХ RPC — склейка, а не покрытие."""
    by = defaultdict(list)
    for fqn, perm in covered:
        if perm:
            by[perm].append(fqn)
    return [(p, sorted(v)) for p, v in by.items() if len(v) > 1]


def main():
    print("═" * 72)
    print("ЭМУЛЯЦИЯ DCL — ВСЕ RPC КАТАЛОГА KACHŌ")
    print("═" * 72)

    kdir = _dirs("generated", "generated/kacho")
    kp, kerr = load_all(kdir)
    print(f"\nманифестов Kachō: {len(glob.glob(kdir))}, "
          f"прав {len(kp)}, отказов разбора {len(kerr)}")
    for f, e in kerr:
        print(f"  ✗ {f}: {e}")

    kc, km, ktot = verify_kacho(kp)

    print(f"\n── Kachō ── операций (RPC): {ktot}")
    print(f"   покрыто {len(kc)} · не покрыто {len(km)} · "
          f"СХОДИМОСТЬ {len(kc) * 100.0 / ktot:.1f}%")
    for f, _ in km[:25]:
        print(f"     ✗ {f}")
    if len(km) > 25:
        print(f"     … ещё {len(km) - 25}")

    kcl = kacho_distinctness(kc)
    print(f"\n── различимость (Kachō) ── прав на несколько RPC: {len(kcl)}")
    for perm, fqns in kcl[:15]:
        print(f"     ⚠ {perm}")
        for f in fqns[:4]:
            print(f"         {f}")

    used_k = {p for _, p in kc if p}
    extra_k = sorted(set(kp) - used_k)
    print(f"\n── лишние права ── {len(extra_k)}")
    for x in extra_k[:12]:
        print(f"     ⚠ {x}")

    print("\n" + "═" * 72)
    print(f"ИТОГО операций: {ktot} · покрыто {len(kc)} · "
          f"СХОДИМОСТЬ {len(kc) * 100.0 / ktot:.1f}%")
    print(f"различимость: {len(kcl)} нарушений · лишних прав: {len(extra_k)}")
    print("═" * 72)
    clean = not (km or kcl or extra_k)
    print("ВЕРДИКТ:", "100% и без склеек" if clean else "есть дефекты, см. выше")
    return 0 if clean else 1


if __name__ == "__main__":
    sys.exit(main())
