---
title: "tests/newman/scripts (kacho-iam)"
category: packages
repo: kacho-iam
layer: tests
tags:
  - packages
  - kacho-iam
  - test
---

# tests/newman/scripts

Генератор + раннер + coverage-gate для newman-сюит kacho-iam.

## Exported (CLI-utilities)

| Script | Назначение |
|---|---|
| `gen.py` | Парсит `cases/<svc>.py` (CASES list of Case → Step) → `collections/<svc>.postman_collection.json`. Source of truth — модули в `cases/`. |
| `run.sh` | Гоняет ВСЕ generated collections под `newman`, агрегирует `out/<svc>.json` + `summary.txt`. После KAC-135 W0.2 — печатает coverage-сводку в конце (env `COVERAGE_MIN` — floor, default 0). |
| `coverage.py` | KAC-135 W0.1. Парсит `../kacho-proto/proto/kacho/cloud/iam/v1/*.proto` (`service/rpc` + `google.api.http` блоки) + `collections/*.json` (URL paths), мапит RPC → URL-templates (`{param}` → `[^/]+` regex), exit 1 если covered% < `--min`. Stdlib-only. 5 unit-тестов (`coverage_test.py`). |

## Tests

- `coverage_test.py` — 5 pytest-кейсов: full-cov happy / partial fail / `google.api.http` override / path-param template / **commented-out RPC defended** (regression на quality-review finding).

## Imports

stdlib only (`argparse`, `glob`, `json`, `re`, `pathlib`, `sys`, `subprocess` в тестах).

## Imported by

CI workflows: `.github/workflows/newman-e2e.yml` (kacho-iam + kacho-deploy) — gate `COVERAGE_MIN=30` (W0 baseline ≈ 49%, W2 Stream D драйвит к 100).

## Baseline (W0, 2026-05-23)

`Coverage: 57 of 117 RPCs (49%)` — `tests/newman/out/coverage-baseline.txt` (gitignored).

## Связано

- [[../KAC/KAC-134]] — epic
- [[../KAC/KAC-135]] — W0
- [[../KAC/KAC-133]] — baseline newman 1144/1148 до W0

#packages #kacho-iam #test
