---
title: vpc-repo-kacho-kachomock
category: packages
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - mock
  - testing
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога против перечня портов пакета-владельца; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/repo/kacho/kachomock

**Каталог**: `services/vpc/internal/repo/kacho/kachomock/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/repo/kacho/kachomock/`)
**Imported by**: service-layer unit-тесты (`internal/apps/kacho/api/<resource>/usecase_test.go`)

Mock-реализации port-интерфейсов из [[vpc-repo-kacho]] — для unit-тестов service-layer без БД (skill `evgeniy` rule).

## Files

Per-entity mock structs:
- `repository.go` — aggregator mock implementing full `Repository`.
- `network.go`, `subnet.go`, `address.go`, `route_table.go`, `security_group.go`,
  `gateway.go`, `network_interface.go`, `address_pool.go`, `address_pool_binding.go`.
- `pagination.go` — общий помощник постраничного обхода для моков.

Итого **одиннадцать** файлов: агрегатор + девять per-entity + помощник пагинации.

> [!note] Двух моков из прежней редакции нет, потому что нет и портов под них
> Записка перечисляла моки приватной конечной точки и выбора пула. Их нет — и не может
> быть: мок реализует **порт**, а обоих портов в [[vpc-repo-kacho]] тоже нет (там же
> разобрано, почему: одно снято миграцией вместе с таблицей, второго нет в дереве вовсе).
> Снятые имена здесь не воспроизводятся в обратных кавычках, иначе разбор находки сам
> стал бы её повторением.
>
> Полезное свойство этого пакета: он **не может** молча отстать от портов — мок, потерявший
> свой интерфейс, не собирается. Отстала именно записка, и ровно потому, что перечисляла
> набор по памяти, а не выводила его из каталога.

## Pattern

Не gomock-generated — handwritten для лучшего test-DSL (записываем какие вызовы ожидаются + что вернуть). Каждый mock содержит `On<Method>`-helpers.

## See also

[[vpc-repo-kacho]] [[vpc-repo-repomock]] [[vpc-repo-cqrsadapter]]

#packages #kacho-vpc #repo #mock #testing
