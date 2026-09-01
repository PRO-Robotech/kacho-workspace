#!/usr/bin/env python3
"""Эмулятор DCL: манифест → права; сверка с реальным API; замер сходимости.

Не «проверяет YAML на форму», а воспроизводит то, что делал бы загрузчик:
выводит class/scope/имя права по объявленным правилам и сопоставляет
результат с фактическим API. Непокрытое печатается поимённо — «ноль
находок» обязано быть отличимо от «ноль прочитанного».
"""
import json
import re
import sys

import yaml

CANON = {"get", "list", "create", "update", "delete"}
CLASS_OF_CANON = {v: v for v in CANON}
PARENT_SCOPED = {"create", "list"}          # объекта ещё нет / перечисление в контейнере
KNOWN_CLASSES = CANON | {"dataAccess", "operate"}


class ManifestError(Exception):
    pass


def load_manifest(path):
    """Читает манифест и выводит всё, что загрузчик вывел бы сам."""
    doc = yaml.safe_load(open(path, encoding="utf-8"))
    module = doc["module"]
    perms = {}                               # имя права → свойства
    for res in doc["resources"]:
        rname = res["name"]
        parent = res.get("parent", "project")
        for a in res["actions"]:
            spec = {"name": a} if isinstance(a, str) else dict(a)
            an = spec["name"]

            # class: точное совпадение с каноническим именем, иначе объявляется
            cls = spec.get("class")
            if cls is None:
                if an not in CLASS_OF_CANON:
                    raise ManifestError(
                        f"{module}.{rname}.{an}: имя не каноническое, class обязателен")
                cls = CLASS_OF_CANON[an]
            if cls not in KNOWN_CLASSES:
                raise ManifestError(f"{module}.{rname}.{an}: неизвестный class {cls!r}")

            # scope выводится из class
            scope = "parent" if cls in PARENT_SCOPED else "self"

            perms[f"{module}.{rname}.{an}"] = {
                "module": module, "resource": rname, "action": an,
                "class": cls, "scope": scope, "parent": parent,
                "catalog": bool(res.get("catalog")),
                "internal": bool(spec.get("internal")),
                "admin": bool(spec.get("admin")),
                "acr": spec.get("acr", 1),
                "requires": spec.get("requires", []),
                "objects": spec.get("objects", "one"),
            }
    return module, perms, doc


# ─────────────────────── сверка с Kachō ───────────────────────

def norm_res(s):
    """instance_network_interfaces → instancenetworkinterface (для сопоставления)."""
    return re.sub(r"[^a-z0-9]", "", s.lower()).rstrip("s")


def check_kacho(perms, catalog_path, module):
    cat = json.load(open(catalog_path, encoding="utf-8"))
    rows = [e for e in cat if e.get("permission", "").startswith(module + ".")]
    # индекс манифеста: (нормализованный ресурс, нормализованный глагол) → имя
    idx = {}
    for name, p in perms.items():
        idx.setdefault((norm_res(p["resource"]), p["action"].lower()), []).append(name)

    covered, missing = [], []
    for e in rows:
        _, res, verb = e["permission"].split(".", 2)
        rn, vn = norm_res(res), verb.lower()
        hit = idx.get((rn, vn))
        if not hit:
            # подресурс: instance_disks.attachDisk → ресурс instance, глагол attach*
            # префикс internal_ сегодня в имени ресурса, в манифесте — флагом
            rn2 = rn[len("internal"):] if rn.startswith("internal") else rn
            for (r2, v2), names in idx.items():
                if rn2.startswith(r2) and (v2 in vn or vn in v2):
                    hit = names
                    break
        (covered if hit else missing).append(
            (e["permission"], hit[0] if hit else None, e))
    return rows, covered, missing


def main():
    manifest = sys.argv[1]
    try:
        module, perms, _ = load_manifest(manifest)
    except ManifestError as e:
        print("ОТКАЗ РАЗБОРА:", e)
        return 2

    print(f"манифест: модуль {module}, прав произведено {len(perms)}")

    rows, cov, miss = check_kacho(perms, "kacho-catalog.json", module)
    tot = len(rows)
    print(f"записей каталога {module}: {tot}")
    print(f"покрыто: {len(cov)}  ·  НЕ покрыто: {len(miss)}")
    print(f"СХОДИМОСТЬ: {len(cov) * 100.0 / tot:.1f}%")
    if miss:
        print("\nне покрыто:")
        for p, _, e in miss:
            se = e.get("scope_extractor") or {}
            print(f"  ✗ {p:56} rel={e.get('required_relation') or '—'} "
                  f"obj={se.get('object_type') or '—'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
