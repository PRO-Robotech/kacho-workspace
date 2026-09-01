#!/usr/bin/env python3
"""Расхождение снимков этой проработки с сегодняшним стволом продукта.

Снимки `live-model.fga` и `kacho-catalog.json` — КОПИИ отслеживаемых файлов
дерева продукта, снятые на одной ревизии. Копия стареет молча: за девять дней
после снятия обе разошлись со стволом, а проверки, которые их читают,
продолжали печатать «✓ идентично». Этот замер делает расхождение видимым — он
ничего не чинит и ничего не прощает, он называет дельту числом.

Исходов три, и читать надо КОД ВОЗВРАТА, а не вид вывода:
  0 — снимки вровень со стволом;
  1 — расхождение (перечислено поимённо);
  2 — БЕЗ ПРЕДМЕТА: дерева продукта не видно, сверять не с чем. Это не
      «расхождений ноль»: ноль находок обязано быть отличимо от ноль
      прочитанного.

Дерево продукта берётся из KACHO_MONOREPO либо из `project/kacho` рядом с
корнем воркспейса.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PINNED = "8fab73ab"          # ревизия, на которой сняты снимки

MODEL = "proto/kacho/cloud/iam/v1/fga_model.fga"
CATALOG = "gateway/internal/middleware/embed/permission_catalog.json"


def monorepo():
    env = os.environ.get("KACHO_MONOREPO")
    if env:
        return env
    root = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
    return os.path.join(root, "project", "kacho")


def vpc_defines(text):
    """Строки `define` блоков типов vpc_* — по типам, в порядке объявления.

    Комментарии отбрасываются намеренно: проза о снятом отношении есть
    утверждение человека, а не контракт, и генератор её не производит.
    """
    out, cur = {}, None
    for line in text.split("\n"):
        if line.startswith("type "):
            name = line[5:].strip()
            cur = name if name.startswith("vpc_") else None
            if cur:
                out[cur] = []
        elif cur is not None:
            if line and not line[0].isspace():
                cur = None
            elif line.strip().startswith("define "):
                out[cur].append(line.strip())
    return out


def compare_model(tree):
    path = os.path.join(tree, MODEL)
    if not os.path.exists(path):
        return None, [f"нет файла {MODEL}"]
    live = vpc_defines(open(path, encoding="utf-8").read())
    snap = vpc_defines(open(os.path.join(HERE, "live-model.fga"), encoding="utf-8").read())
    findings = []
    for name in sorted(set(snap) | set(live)):
        a, b = snap.get(name), live.get(name)
        if a is None:
            findings.append(f"тип {name}: есть в стволе, нет в снимке")
            continue
        if b is None:
            findings.append(f"тип {name}: есть в снимке, нет в стволе")
            continue
        for x in a:
            if x not in b:
                findings.append(f"{name}: снимок держит `{x}` — в стволе такого нет")
        for x in b:
            if x not in a:
                findings.append(f"{name}: ствол держит `{x}` — снимок такого не знает")
    return len(snap), findings


def compare_catalog(tree):
    path = os.path.join(tree, CATALOG)
    if not os.path.exists(path):
        return None, [f"нет файла {CATALOG}"]
    live = {e["fqn"] for e in json.load(open(path, encoding="utf-8"))}
    snap = {e["fqn"] for e in json.load(
        open(os.path.join(HERE, "kacho-catalog.json"), encoding="utf-8"))}
    findings = []
    for fqn in sorted(live - snap):
        findings.append(f"каталог: запись `{fqn}` заведена после снимка")
    for fqn in sorted(snap - live):
        findings.append(f"каталог: запись `{fqn}` снята после снимка")
    return len(snap), findings


def main():
    tree = monorepo()
    print(f"снимки сняты на ревизии {PINNED}")
    print(f"ствол продукта: {tree}")
    if not os.path.isdir(tree):
        print("БЕЗ ПРЕДМЕТА: дерева продукта не видно — сверять не с чем.")
        print("  задай KACHO_MONOREPO либо склонируй продукт в project/kacho")
        return 2

    types_seen, model_findings = compare_model(tree)
    entries_seen, catalog_findings = compare_catalog(tree)
    if types_seen is None or entries_seen is None:
        print("БЕЗ ПРЕДМЕТА: в дереве нет файлов, с которыми сверяются снимки:")
        for f in (model_findings if types_seen is None else []) + \
                 (catalog_findings if entries_seen is None else []):
            print(f"  {f}")
        return 2

    print(f"осмотрено: типов vpc_* {types_seen} · записей каталога {entries_seen}")
    findings = model_findings + catalog_findings
    print(f"расхождений: модель {len(model_findings)} · каталог {len(catalog_findings)}")
    for f in findings:
        print(f"  ✗ {f}")
    if not findings:
        print("ВЕРДИКТ: снимки вровень со стволом")
        return 0
    print("ВЕРДИКТ: снимки отстали — числа проработки относятся к ревизии, "
          "а не к сегодняшнему дереву")
    return 1


if __name__ == "__main__":
    sys.exit(main())
