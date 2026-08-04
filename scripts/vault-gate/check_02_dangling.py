#!/usr/bin/env python3
"""Тело проверки 02 — висячие wikilink'и. Комментарий предмета — в .sh-обёртке.

Основание храповика — не число, а ПЕРЕЧЕНЬ целей с числом ссылок на каждую.
Одно суммарное число сходится случайно: завели новую висячую ссылку, починили
старую — итог тот же, гейт зелен. Перечень же называет, что именно прибавилось
и что исчезло, поэтому и находка, и устаревание основания получают координату.
"""

from __future__ import annotations

import collections
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import vaultlib as V  # noqa: E402

CHECK = "ссылка между записками ведёт в существующий файл"
DEFAULT_BASELINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dangling-baseline.txt")


def baseline_path() -> str:
    return os.environ.get("VAULT_GATE_BASELINE") or DEFAULT_BASELINE


def read_baseline(path: str) -> dict[str, int] | None:
    try:
        out: dict[str, int] = {}
        for line in open(path, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            count, _, target = line.partition("\t")
            out[target.strip()] = int(count.strip())
        return out or None
    except (OSError, ValueError):
        return None


def collect(root: str) -> tuple[collections.Counter, dict[str, str], int, int]:
    files = V.vault_files(root)
    notes = V.notes(files)
    resolver = V.Resolver(files)
    dangling: collections.Counter[str] = collections.Counter()
    where: dict[str, str] = {}
    total = 0
    for rel in notes:
        try:
            text = open(os.path.join(root, V.VAULT, rel), encoding="utf-8").read()
        except OSError:
            continue
        for m in V.LINK_RE.finditer(text):
            total += 1
            target = m.group(1).strip().rstrip("\\")
            if resolver.resolve(target, rel) is None:
                dangling[target] += 1
                where.setdefault(target, rel)
    return dangling, where, total, len(notes)


def main() -> int:
    root = os.environ.get("VAULT_GATE_ROOT") or V.workspace_root(__file__)
    dangling, where, total, n_notes = collect(root)

    if n_notes == 0:
        print(f"[VOID] {CHECK} — в индексе git нет ни одной записки хранилища", file=sys.stderr)
        return 2
    if total == 0:
        print(f"[VOID] {CHECK} — прочитано записок {n_notes}, ссылок в них ноль: читать нечего", file=sys.stderr)
        return 2

    if "--list" in sys.argv:
        for target, count in dangling.most_common():
            print(f"{V.link_kind(target):>4} {count:4d}  {target}   <- {where[target]}")
        return 0

    if "--write-baseline" in sys.argv:
        path = baseline_path()
        head = open(path, encoding="utf-8").read().split("\n") if os.path.exists(path) else []
        comment = [l for l in head if l.lstrip().startswith("#")]
        with open(path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(comment) + ("\n" if comment else ""))
            for target, count in sorted(dangling.items()):
                fh.write(f"{count}\t{target}\n")
        print(f"основание переписано: целей {len(dangling)}, ссылок {sum(dangling.values())}")
        return 0

    by_kind: collections.Counter[str] = collections.Counter()
    for t, c in dangling.items():
        by_kind[V.link_kind(t)] += c
    scope = (
        f"осмотрено записок {n_notes}, ссылок {total}; висячих {sum(dangling.values())} "
        f"на {len(dangling)} целей (категорийных {by_kind['cat']}, коротких {by_kind['bare']}, KAC {by_kind['KAC']})"
    )

    base = read_baseline(baseline_path())
    if base is None:
        print(f"[VOID] {CHECK} — основание не прочитано ({baseline_path()}); сравнивать не с чем", file=sys.stderr)
        return 2

    grew = [(t, c, base.get(t, 0)) for t, c in sorted(dangling.items()) if c > base.get(t, 0)]
    gone = [(t, base[t]) for t in sorted(base) if base[t] > dangling.get(t, 0)]

    if grew:
        print(f"[FAIL] {CHECK} — {scope}; новых висячих целей/ссылок: {len(grew)}", file=sys.stderr)
        for t, c, b in grew[:20]:
            print(f"        {t}   ссылок {b} → {c}   <- {where.get(t, '?')}", file=sys.stderr)
        print("        починка — завести записку под этим именем ЛИБО исправить имя ссылки", file=sys.stderr)
        return 1

    if gone:
        rel = os.path.relpath(baseline_path(), root)
        print(
            f"[FAIL] {CHECK} — {scope}; основание УСТАРЕЛО: {len(gone)} целей больше не висят. "
            f"Перепишите основание тем же коммитом (`{rel}`, `--write-baseline`): "
            "послабление, которому нечего прощать, обязано истечь",
            file=sys.stderr,
        )
        for t, b in gone[:20]:
            print(f"        {t}   было ссылок {b}, стало {dangling.get(t, 0)}", file=sys.stderr)
        return 1

    print(f"[PASS] {CHECK} — {scope}; сходится с основанием ({len(base)} целей)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
