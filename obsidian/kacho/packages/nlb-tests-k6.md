---
title: nlb-tests-k6
aliases:
  - nlb k6 load
category: packages
repo: kacho-nlb
layer: tests
tags:
  - packages
  - kacho-nlb
  - tests
  - k6
  - load
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): цели Makefile каталога, перечень файлов сценариев, наличие k6 в рабочих процессах CI; пороги SLO против дерева НЕ сверялись — их источник вне кода"
---

# kacho-nlb/tests/k6

**Каталог**: `services/nlb/tests/k6/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/tests/k6/`)
**Tooling**: k6 (HTTP/gRPC scripts) + ghz (gRPC-specific). Run against deployed kacho-nlb (real Postgres + peer-services).

## Files

| File | Содержание |
|---|---|
| `scripts/` | k6 entry-point scripts |
| `scenarios/` | declarative scenario configs (RPS, VUs, duration) |
| `lib/` | shared utilities (auth bootstrap, project seed, helpers) |
| `data/` | test data fixtures (sample LBs/TGs/Targets) |
| `ghz/` | ghz configs для gRPC load |
| `Makefile` | цели с префиксом `k6-`: `make k6-smoke`, `make k6-baseline`, `make k6-stress`, `make k6-soak`, `make k6-spike`, плюс `make k6-dry-run` и `make clean`. Префикс — часть имени, не украшение: без него цели в дереве нет |
| `results/` | output dir (gitignored) |
| `README.md` | scenario catalog + SLO targets |

## Scenarios (5 файлов в `services/nlb/tests/k6/scenarios/`)

`smoke.js` · `baseline.js` · `stress.js` · `soak.js` · `spike.js` — по одному на цель
Makefile. Смысл каждого:

1. **smoke** — минимальный прогон, проверка что стенд и авторизация живы (не нагрузка).
2. **baseline** — установившаяся смешанная нагрузка read/write, основная точка отсчёта.
3. **stress** — ramp вверх до точки насыщения, отчёт кривой.
4. **soak** — долгий ровный прогон: утечки памяти, исчерпание соединений, дрейф ошибок.
5. **spike** — резкий всплеск и возврат, поведение на восстановлении.

> [!note] Прежняя редакция называла два сценария, которых в каталоге нет
> Вместо `smoke` и `spike` перечислялись «read-heavy» и «write-heavy» с точными цифрами
> RPS и порогами. Файлов под этими именами нет; числа рядом с ними, соответственно, тоже
> ничем не обеспечены. Профили нагрузки (VU, ramp, длительность) заданы **внутри**
> сценарных файлов и в `services/nlb/tests/k6/lib/mix.js` — источник истины там, а не здесь,
> поэтому дублировать их в записку значило бы завести второе место об одном предмете.

## SLO targets (KAC-141 DoD) — заявлены, автоматически не энфорсятся

- p95 latency ≤ 100ms @ 500 RPS (baseline) — **MUST pass для DoD**
- p99 latency ≤ 300ms @ 500 RPS
- Error rate < 0.01% (excluding intentional 4xx)
- pgx pool utilization < 80%

Пороги взяты из DoD тикета, а не из дерева, и на сверенной ревизии в дереве нет ничего,
что их проверяло бы (см. следующий раздел). Держать их тут можно — но как **цель**, а не
как действующий гейт.

## CI integration — её НЕТ, и это открытый долг, а не деталь оформления

Прежняя редакция описывала ночной рабочий процесс, гоняющий baseline, с выгрузкой
результатов и дашбордом. **Ни такого файла, ни любого другого упоминания k6 в
`.github/workflows/` нет**: перепись по каталогу даёт девять рабочих процессов, и k6 не
называет ни один из них (`git grep -l k6 -- .github/workflows/` — пусто).

Значит нагрузка гоняется **только руками**, целями Makefile выше. Следствие, которое
важно назвать числом, а не тоном: пороги SLO в разделе ниже **не проверяются ничем** —
ни один прогон не может их нарушить, потому что ни один прогон не происходит сам.
Это ровно та форма, которую правила зовут «проверка без предмета»: цель есть,
исполнителя нет. Запись держится как **открытый долг с числом** (ноль автоматических
прогонов), а не выдаётся за работающую интеграцию.

## SLO targets — заявлены, но не энфорсятся

## See also

[[nlb-tests-newman]] [[../KAC/KAC-141]]

#packages #kacho-nlb #tests #k6 #load
