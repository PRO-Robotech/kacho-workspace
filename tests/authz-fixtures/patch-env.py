#!/usr/bin/env python3
"""Merges authz-fixtures.json into newman *.postman_environment.json files.

Usage:
    patch-env.py <fixtures.json> <env1.json> [<env2.json> ...]

Сохраняет старые ключи; добавляет / обновляет ключи из fixtures.
"""
from __future__ import annotations

import json
import pathlib
import sys


# Newman-env ключи, которых нет verbatim в fixtures.json, но которые ОБЯЗАНЫ
# зеркалить canonical fixture-ключ. KAC-263: иначе newman гоняет CRUD по stale
# `existingProjectId`, где у тест-юзера (PA1) нет editor-binding → 403, и
# приходится доделывать вручную. projectA1 — home-проект CRUD-юзера PA1
# (там setup.sh выдал editor); projectA2 — cross-проект для Move/cross-сценариев.
ENV_ALIASES = {
    "existingProjectId": "projectA1Id",
    "existingProjectCrossId": "projectA2Id",
    "_suiteFolderId": "projectA1Id",
    "_suiteFolderCrossId": "projectA2Id",
}


def patch_env(env_path: pathlib.Path, fixtures: dict) -> int:
    """Return number of keys added/updated."""
    data = json.loads(env_path.read_text())
    values = data.setdefault("values", [])
    existing = {v["key"]: v for v in values}
    # Прямые ключи fixtures + newman-env алиасы (existingProjectId ← projectA1Id …).
    merged = dict(fixtures)
    for env_key, fx_key in ENV_ALIASES.items():
        if fixtures.get(fx_key):
            merged[env_key] = fixtures[fx_key]
    changes = 0
    for key, val in merged.items():
        sval = "" if val is None else str(val)
        if key in existing:
            if existing[key].get("value") != sval:
                existing[key]["value"] = sval
                existing[key]["enabled"] = True
                changes += 1
        else:
            values.append({"key": key, "value": sval, "type": "default", "enabled": True})
            changes += 1
    env_path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    return changes


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: patch-env.py <fixtures.json> <env1.json> [<env2.json> ...]", file=sys.stderr)
        return 2
    fixtures_path = pathlib.Path(sys.argv[1])
    fixtures = json.loads(fixtures_path.read_text())
    for env_arg in sys.argv[2:]:
        env_path = pathlib.Path(env_arg)
        if not env_path.exists():
            print(f"[patch-env] SKIP (missing): {env_path}", file=sys.stderr)
            continue
        n = patch_env(env_path, fixtures)
        # display friendly path without crashing on /tmp/ paths outside cwd
        try:
            disp = env_path.relative_to(env_path.cwd()) if env_path.is_absolute() else env_path
        except ValueError:
            disp = env_path
        print(f"[patch-env] {disp}: {n} keys", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
