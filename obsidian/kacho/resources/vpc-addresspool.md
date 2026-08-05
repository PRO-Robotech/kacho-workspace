---
title: AddressPool
aliases:
  - AddressPool (vpc)
  - vpc AddressPool
category: resource
domain: vpc
id_prefix: apl
owner_table: kacho_vpc.address_pools
owner_db: kacho_vpc
project_level: false
visibility: internal
status: stable
verified_against: "координаты записки (файл контракта, таблицы-владельцы, миграции схемы) сверены с деревом продукта 1653387b (2026-08-06); поля ресурса построчно не пересматривались"
related_rpc:
  - "[[rpc/vpc-internal-address-pool-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-addresspool]]"
tags:
  - resource
  - kacho-vpc
  - addresspool
  - admin
  - kacho-only
---

# AddressPool

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (`services/vpc/`)
**ID prefix**: `apl` (`ids.PrefixAddressPool`)
**Owner table**: `kacho_vpc.address_pools` (+ `address_pool_cidrs`, `address_pool_free_ips`, `address_pool_network_default`)
**Scope**: **не** project — админский ресурс уровня кластера/зоны
**Видимость**: только `Internal*` (:9091), ban #6

**Контракт**: `proto/kacho/cloud/vpc/v1/internal_address_pool_service.proto` — и сам
`message AddressPool` живёт там же; отдельного файла контракта под этот ресурс нет, и его
гипотетическое имя здесь не приводится координатой (цитата несуществующего файла в
обратных кавычках читается как утверждение, что он есть)
**Схема**: `0001_initial.sql` + 0004 (`address_pool_cidrs`), 0011, 0023

## Поля (`message AddressPool`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `apl<17>` |
| `created_at` | Timestamp | |
| `name`, `description`, `labels` | | |
| `kind` | enum `AddressPoolKind` | см. ниже — **значение сегодня ровно одно** |
| `zone_id` | string | пусто/NULL ⇒ пул не привязан к зоне |
| `is_default` | bool | дефолтный пул своей пары (zone, kind) |
| `selector_labels` | map<string,string> | отбор пула по меткам |
| `selector_priority` | int32 | приоритет отбора |
| `v4_cidr_blocks` | repeated string | |
| `v6_cidr_blocks` | repeated string | |

> [!warning] `kind` — это НЕ «internal_v4 / external_v4 / external_v6»
> ```protobuf
> enum AddressPoolKind {
>   ADDRESS_POOL_KIND_UNSPECIFIED = 0;
>   EXTERNAL_PUBLIC = 1;
>   reserved 2, 100;
>   reserved "EXTERNAL_TEST", "RESERVED_INTERNAL";
> }
> ```
> Живое значение одно — `EXTERNAL_PUBLIC`. Два прежних (`EXTERNAL_TEST`,
> `RESERVED_INTERNAL`) сняты с резервированием номера И имени. Семейство адресов
> различается не видом пула, а тем, какой массив блоков заполнен (`v4_cidr_blocks` /
> `v6_cidr_blocks`).
>
> Там же `reserved 2; reserved "project_id";` — пул **не** принадлежит проекту, и
> `reserved 7; reserved "cidr_blocks";` — единый плоский массив блоков заменён парой
> по семействам.

## Constraints (по DDL)

- `address_pools_pkey` PRIMARY KEY (id)
- `address_pools_zone_kind_default_uniq` — `UNIQUE (COALESCE(zone_id, ''), kind) WHERE is_default = true`:
  один дефолтный пул на пару (зона, вид); пул без зоны попадает в ту же уникальность под ключом `''`
- `address_pools_zone_idx` — обычный индекс по `zone_id`

> [!note] FK на зоны у пула НЕТ — и не может быть
> Прежняя редакция называла `address_pools_zone_id_fkey → zones(id)`. Такого ограничения в
> схеме нет: `zone_id text` объявлен без `REFERENCES`. И иначе быть не может — владелец
> `Zone` это **geo**, отдельный сервис со своей БД, а FK через границу сервиса запрещён
> (ban #4/#8). Существование зоны проверяется peer-вызовом к geo, а не ссылочной
> целостностью.

### Непересечение CIDR — нормализованная дочерняя таблица (миграция 0004)

```sql
address_pool_cidrs (
    pool_id text REFERENCES address_pools(id) ON DELETE CASCADE,
    kind    smallint,
    block   cidr,
    PRIMARY KEY (pool_id, block),
    EXCLUDE USING gist (kind WITH =, block inet_ops WITH &&)
)
```

Ключ исключения — **только `kind`**, зона в него НЕ входит: публичные CIDR глобально
непересекающиеся, поэтому пулы разных зон одного вида пересекаться тоже не вправе.
Без этого IPAM выдал бы один внешний IP дважды — `addresses_external_pool_ip_uniq`
уникален внутри пула и коллизию **между** пулами не ловит. 23P01 →
`FailedPrecondition "address pool CIDRs can not overlap"`. Зеркалит `subnets_no_overlap_v4`.

## Свободные адреса и аллокация

`address_pool_free_ips` — материализованный free-list. Аллокация:
`SELECT … FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING` — конкурентные
аллокации не блокируют друг друга и не дают дедлоков.

Управление блоками:

- `:addCidrBlocks` → материализует free-list **только для новой дельты** (идемпотентно
  через `ON CONFLICT`) и вставляет блоки в `address_pool_cidrs` в той же writer-TX;
- `:removeCidrBlocks` → удаление free-list-строк под row-lock **плюс** подсчёт уже
  выданных адресов в снимаемых диапазонах — в **одной** транзакции, иначе remove и alloc
  разъедутся.

**Возврат lease на каждом пути высвобождения — часть контракта Delete** адреса
(`data-integrity.md` §Lease-recycle-on-delete): иначе пул исчерпывается под параллельным
e2e, аллокация начинает падать, и это выглядит как чужой дефект.

## Привязки

`address_pool_network_default(network_id PK, pool_id FK)` — переопределение дефолтного
пула для конкретной сети.

## Цепочка выбора пула при создании Address

1. `network_default` — строка в `address_pool_network_default`;
2. `zone_default` — дефолтный пул зоны (уникальность по (zone, kind));
3. `global_default` — дефолтный пул без зоны.

> [!note] История: два звена цепочки сняты ([[KAC-266]])
> Таблицы `address_pool_address_override` (переопределение на конкретный Address) и
> `cloud_pool_selector` дропнуты миграцией `0002_drop_override_and_cloud_pool_selector.sql`
> вместе с соответствующими RPC.

## Gotcha

- **Все RPC — на internal-листенере**, отношение `system_admin`, scope-объект `cluster`.
  На публичной поверхности пула нет.
- **Мутации возвращают ресурс синхронно, а не `Operation`** — осознанное отступление от
  ban #9 для админского ресурса; см. [[../rpc/vpc-internal-address-pool-service]].
- Смешивать семейства в одном пуле нельзя.

## См. также

[[vpc-address]] · [[vpc-network]] · [[geo-zone]] · [[../rpc/vpc-internal-address-pool-service]]

#resource #vpc #addresspool #admin #kacho-only
