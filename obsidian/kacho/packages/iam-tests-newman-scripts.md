---
title: "tests/newman/scripts (kacho-iam)"
category: packages
path: services/iam/tests/newman/scripts
repo: kacho-iam
layer: tests
tags:
  - packages
  - kacho-iam
  - test
status: stable
verified_against: "координаты записки (workflow CI, дерево proto, артефакты прогона) сверены с деревом продукта 1653387b (2026-08-06); числа покрытия и состав кейсов построчно не пересматривались"
---

# tests/newman/scripts

Генератор + раннер + coverage-gate для newman-сюит kacho-iam.

## Exported (CLI-utilities)

| Script | Назначение |
|---|---|
| `gen.py` | Парсит `cases/<svc>.py` (CASES list of Case → Step) → `collections/<svc>.postman_collection.json`. Source of truth — модули в `cases/`. |
| `run.sh` | Гоняет ВСЕ generated collections под `newman`, складывает отчёт, cli-вывод, код возврата и итоговую сводку в каталог `out` рядом со скриптами. После KAC-135 W0.2 — печатает coverage-сводку в конце (env `COVERAGE_MIN` — floor, default 0). |
| `coverage.py` | KAC-135 W0.1. Парсит `.proto` (`service/rpc` + `google.api.http` блоки) + `collections/*.json` (URL paths), мапит RPC → URL-templates (`{param}` → `[^/]+` regex), exit 1 если covered% < `--min`. Stdlib-only. 5 unit-тестов (`coverage_test.py`). Дерево proto **не зашито**: путь приходит обязательным аргументом `--proto-glob`, и сегодня это `proto/kacho/cloud/iam/v1/*.proto` монорепо (пример в собственной справке скрипта до сих пор написан по раскладке времён полирепо). |

> [!note] Артефакты прогона отслеживаемыми файлами не являются — координаты сняты (1653387b, 2026-08-06)
> Прежняя редакция называла сводку прогона и файл базового покрытия так, будто это файлы
> дерева. Каталог, куда они пишутся, закрыт от учёта
> (`services/iam/tests/newman/.gitignore`), поэтому такая координата не резолвится **по
> построению** и не станет резолвиться никогда. Причина запрета названа там же: устаревший
> отчёт от прошлого локального прогона подхватывался гейтом и всплывал фантомной суитой.
> Имена артефактов здесь намеренно не воспроизводятся в обратных кавычках — постоянный
> адрес у них один, и это **производящий** скрипт, чьи выходы перечислены в его шапке.

## Tests

- `coverage_test.py` — 5 pytest-кейсов: full-cov happy / partial fail / `google.api.http` override / path-param template / **commented-out RPC defended** (regression на quality-review finding).

## Imports

stdlib only (`argparse`, `glob`, `json`, `re`, `pathlib`, `sys`, `subprocess` в тестах).

## Imported by

CI workflow — `.github/workflows/e2e-newman.yml` (единственный корневой `.github/`
монорепо; прежняя редакция называла его переставленными словами, такого файла в дереве
нет) — gate `COVERAGE_MIN=30` (W0 baseline ≈ 49%, W2 Stream D драйвит к 100).

## Baseline (W0, 2026-05-23)

`Coverage: 57 of 117 RPCs (49%)` — замер того дня, снятый в неотслеживаемый каталог
прогона (см. примечание выше). Число приведено **как история**: подтвердить его по
дереву нельзя ни сегодня, ни впредь — файла с ним не существует, а знаменатель с тех пор
изменился вместе с контрактом.

## Связано

- [[../KAC/KAC-134]] — epic
- [[../KAC/KAC-135]] — W0
- [[../KAC/KAC-133]] — baseline newman 1144/1148 до W0

#packages #kacho-iam #test
