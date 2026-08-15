#!/usr/bin/env python3
"""Тело проверки 03 — оболочка записки. Комментарий предмета — в .sh-обёртке."""

from __future__ import annotations

import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vaultlib as V  # noqa: E402

CHECK = "у записки есть оболочка: назначение, категория, состояние"

# Каталог → категория, которую записка обязана объявить. Выведено из раскладки
# хранилища: категория — это и есть каталог верхнего уровня.
DIR_CATEGORY = {
    "resources": "resource",
    "rpc": "rpc",
    "packages": "packages",
    "edges": "edge",
    "KAC": "kac",
    "lessons": "lesson",
    "runbooks": "runbook",
    "docs": "docs",
    "legacy": "legacy",
}

# Категории, где записка описывает СУЩНОСТЬ ПРОДУКТА и потому обязана объявить
# состояние. Журнал, уроки и процедуры от этого требования свободны: их предмет
# не «живёт» и не «снимается» вместе с деревом.
STATUS_REQUIRED = {"resources", "rpc", "packages", "edges"}


def vocabulary(root: str) -> set[str]:
    """Словарь состояний — из таблицы трёх вёдер в CLAUDE.md хранилища."""
    path = os.path.join(root, V.VAULT, "CLAUDE.md")
    try:
        text = open(path, encoding="utf-8").read()
    except OSError:
        return set()
    m = re.search(r"^\|\s*Ведро\s*\|.*?(?=\n\n)", text, re.S | re.M)
    if not m:
        return set()
    return set(re.findall(r"`([a-z\-]+)`", m.group(0)))


def is_showcase(rel: str) -> bool:
    base = os.path.basename(rel)
    return base == "README.md" or base.startswith("all-") or base == "_TEMPLATE.md"


def main() -> int:
    root = os.environ.get("VAULT_GATE_ROOT") or V.workspace_root(__file__)
    files = V.vault_files(root)
    notes = V.notes(files)
    if not notes:
        print(f"[VOID] {CHECK} — в индексе git нет ни одной записки хранилища", file=sys.stderr)
        return 2

    vocab = vocabulary(root)
    if not vocab:
        print(
            f"[VOID] {CHECK} — в {V.VAULT}/CLAUDE.md не нашлась таблица вёдер состояния; "
            "словарь выводить неоткуда, а рукописный разошёлся бы с контрактом молча",
            file=sys.stderr,
        )
        return 2

    findings: list[str] = []
    examined = 0
    for rel in notes:
        top = rel.split("/")[0] if "/" in rel else "(корень)"
        if top not in DIR_CATEGORY:
            continue
        examined += 1
        fm = V.frontmatter(os.path.join(root, V.VAULT, rel))
        if not fm:
            findings.append(f"{rel}: нет frontmatter вовсе")
            continue
        if not fm.get("title"):
            findings.append(f"{rel}: нет `title`")
        expected = DIR_CATEGORY[top]
        actual = fm.get("category", "")
        if not actual:
            findings.append(f"{rel}: нет `category` (ожидается `{expected}` либо `hub` у витрины)")
        elif actual not in (expected, "hub"):
            findings.append(f"{rel}: `category: {actual}`, а каталог требует `{expected}` (или `hub` у витрины)")
        status = fm.get("status", "")
        if status and status not in vocab:
            findings.append(f"{rel}: `status: {status}` вне словаря {sorted(vocab)}")
        elif not status and top in STATUS_REQUIRED and not is_showcase(rel):
            findings.append(f"{rel}: нет `status` — записка не попадёт ни в один срез по состоянию")

    scope = f"осмотрено записок {examined} из {len(notes)}; словарь состояний из CLAUDE.md — {len(vocab)} значений"
    if findings:
        print(f"[FAIL] {CHECK} — {scope}; находок {len(findings)}", file=sys.stderr)
        for f in findings[:40]:
            print(f"        {f}", file=sys.stderr)
        if len(findings) > 40:
            print(f"        … и ещё {len(findings) - 40}", file=sys.stderr)
        return 1

    print(f"[PASS] {CHECK} — {scope}; находок 0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
