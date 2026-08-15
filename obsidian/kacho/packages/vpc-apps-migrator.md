---
title: vpc-apps-migrator
category: packages
repo: kacho-vpc
layer: migrations
tags:
  - packages
  - kacho-vpc
  - migrations
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога, набор поддерживаемых диалектов по фабрике, число и последний номер миграций; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/apps/migrator

**Каталог**: `services/vpc/internal/apps/migrator/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/apps/migrator/`)
**Imported by**: [[vpc-cmd-migrator]] (bin entrypoint)

Migration runner — вынесен за абстракцию диалекта, но **реализация ровно одна: Postgres**.

## Files

| File | Содержание |
|---|---|
| `runner.go` | core loop: parse SQL files, apply up/down |
| `runner_test.go` | |
| `dialect.go` | интерфейс `Dialect` + `DialectSpec` (имя, goose-имя, driver) + фабрика `NewDialect` |
| `dialect_test.go` | в т.ч. проверка, что `--dialect postgres` резолвится |
| `postgres.go` | единственная реализация: goose + pgx, `pg_advisory_lock` для конкурентного мигратора |

> [!warning] Второго диалекта нет — ни файла, ни поддержки
> Записка объявляла раннер «dialect-aware (Postgres + другая СУБД)» и называла файл под
> вторую реализацию. Файла нет, и поддержки нет: `NewDialect` знает **одно** имя и на
> любом другом возвращает ошибку «unknown dialect … (supported: …)», а `SpecPostgres` —
> единственная объявленная спека. Абстракция при этом настоящая и осмысленная (интерфейс
> + фабрика + спека), просто её ветвь одна.
>
> Различие не academic: «поддерживаются две СУБД» — это обещание переносимости, по
> которому кто-то запланирует стенд, а отказ получит только в рантайме от фабрики.
> Абстракция с одной реализацией — это точка расширения, а не готовая возможность.

## Migration files

Source: `services/vpc/internal/migrations/*.sql` (numbered `0001_...sql`). На сверенной
ревизии их **27**, последняя — `0027_security_group_rules_domain.sql`. (Прежняя редакция
говорила «30+, последняя 0030» — числа были завышены, а «на момент индексации» не называло
момента, поэтому проверить их было нечем. Число живёт ровно до следующей миграции: сверять
пересчётом, а не памятью.)

## See also

[[vpc-cmd-migrator]] [[corelib-db]]

#packages #kacho-vpc #migrations
