---
title: Subnet
aliases:
  - Subnet (vpc)
  - vpc Subnet
category: resource
domain: vpc
id_prefix: sub
owner_table: kacho_vpc.subnets
owner_db: kacho_vpc
project_level: true
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/vpc-subnet-service]]"
related_packages:
  - "[[packages/vpc-domain]]"
  - "[[packages/vpc-repo-kacho-pg]]"
tags:
  - resource
  - kacho-vpc
  - subnet
  - cidr
---

# Subnet

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (`services/vpc/`)
**ID prefix**: `sub` (`ids.PrefixSubnet`, `pkg/ids/ids.go`)
**Owner table**: `kacho_vpc.subnets`
**Scope**: project (`project_id`), сеть — через `network_id`

**Контракт**: `proto/kacho/cloud/vpc/v1/subnet.proto`
**Схема**: `services/vpc/internal/migrations/0001_initial.sql` + 0010 (`subnet_cidr_blocks`), 0012 (placement)

Subnet — **канонический якорь размещения** всего домена: NIC и Address зону не несут, а
наследуют её через `subnet_id` (`data-integrity.md` §Placement-coherence).

## Поля публичной проекции (`message Subnet`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `sub<17>`; immutable |
| `project_id` | string | cross-service ссылка → **iam** `Project` |
| `created_at` | Timestamp | truncate до секунд |
| `name`, `description`, `labels` | | `UNIQUE (project_id, name) WHERE name <> ''` |
| `network_id` | string | within-service FK → `networks(id)` |
| `placement_type` | enum `SubnetPlacementType` | **ZONAL** \| **REGIONAL**; required, immutable |
| `zone_id` | string | задан ⟺ `placement_type == ZONAL`; ссылка → **geo** `Zone` |
| `region_id` | string | задан ⟺ `placement_type == REGIONAL`; ссылка → **geo** `Region` |
| `route_table_id` | string | within-service ссылка → `route_tables(id) ON DELETE SET NULL` |
| `ipv4_cidr_primary` | string | **immutable**, задаётся на Create; подмножество супернет-блока сети; мин /28, макс /16; пусто у v6-only |
| `ipv4_cidr_blocks` | repeated string | дополнительные диапазоны сверх primary; мутируются **только** `:add-cidr-blocks` / `:remove-cidr-blocks` |
| `ipv6_cidr_primary` | string | immutable; пусто у v4-only |
| `ipv6_cidr_blocks` | repeated string | зеркало v4 |

> [!warning] Имена CIDR-полей сменились — прежние СНЯТЫ с контракта
> В `message Subnet` объявлено `reserved 9, 10, 11, 13` и `reserved "dhcp_options"`.
> Слоты 10/11 — прежние `v4_cidr_blocks` / `v6_cidr_blocks`: плоский массив «все блоки»
> разбит на явный immutable-якорь плюс дополнительные диапазоны (VPC-1 F7). Слот 9 —
> прежний `route_table` oneof, слот 13 — `dhcp_options` (DHCP/DNS-ручки уровня сети сняты
> по дизайну, VPC-1 F9). Записка, называющая `v4_cidr_blocks` полем **контракта**, описывает
> состояние до этой правки.
>
> Отдельно и важно: **в БД имена другие, и другими остались.** Таблица `subnets`
> по-прежнему несёт `v4_cidr_blocks text[]` / `v6_cidr_blocks text[]` и **generated**
> колонки `v4_cidr_primary` / `v6_cidr_primary` (`GENERATED ALWAYS AS … STORED`, берут
> первый элемент массива). Механическая замена имени по всему тексту сделала бы описание
> схемы уверенно неверным: wire-имя и имя колонки здесь разошлись намеренно.

## Placement — дискриминатор, а не пара ad-hoc полей

`0012_subnet_placement.sql` добавила `placement_type text NOT NULL DEFAULT 'ZONAL'` и
`region_id text NOT NULL DEFAULT ''` и закрепила взаимоисключение DB-CHECK'ом:
ZONAL ⇒ `zone_id <> '' AND region_id = ''`; REGIONAL ⇒ `zone_id = '' AND region_id <> ''`.

REGIONAL-подсеть — **anycast**: зоны у неё нет by construction, поэтому из зональной
проверки когерентности она исключена, а региональная остаётся. Это и есть «исключение
эникаст» из `data-integrity.md`.

## Constraints (по DDL)

- `subnets_pkey` PRIMARY KEY (id)
- `subnets_project_id_name_key` — UNIQUE (project_id, name) partial `WHERE name <> ''`
- `subnets_no_overlap_v4` — `EXCLUDE USING gist (network_id WITH =, v4_cidr_primary inet_ops WITH &&) WHERE (v4_cidr_primary IS NOT NULL)`
- `subnets_no_overlap_v6` — то же для v6
- `subnets_name_check`, `subnets_description_check`, `subnets_labels_valid`
- FK: `network_id → networks(id)` (без CASCADE); `route_table_id → route_tables(id) ON DELETE SET NULL`

### Почему одного EXCLUDE на таблице не хватило (миграция 0010)

Оба baseline-EXCLUDE смотрят только на **primary**-блок семейства — generated-колонку из
первого элемента массива. Вторичные блоки, добавляемые `:add-cidr-blocks`, под них не
попадали: пересечение вторичных диапазонов двух подсетей ОДНОЙ сети проходило, и IPAM мог
выдать один internal-IP дважды.

Решение — нормализованная дочерняя таблица:

```sql
CREATE TABLE kacho_vpc.subnet_cidr_blocks (
    subnet_id  text NOT NULL REFERENCES kacho_vpc.subnets(id) ON DELETE CASCADE,
    network_id text NOT NULL,
    block      cidr NOT NULL,
    PRIMARY KEY (subnet_id, block),
    CONSTRAINT subnet_cidr_blocks_no_overlap
        EXCLUDE USING gist (network_id WITH =, block inet_ops WITH &&)
);
```

Ключ исключения — `network_id`: подсети **разных** сетей пересекаться вправе (изоляция
per-network), поэтому network денормализуется в дочернюю строку ради scope-ключа. v4 и v6
в одной колонке ложных пересечений не дают (`inet &&` между семействами — false). Строки
поддерживаются репозиторием в **той же writer-транзакции**, что и DML подсети; удаление
подсети снимает их FK-каскадом внутри одной БД.

## FK-контракт (кто ссылается на Subnet)

- `addresses.internal_subnet_id → subnets(id) ON DELETE RESTRICT` — причём сам
  `internal_subnet_id` **generated** из JSONB `internal_ipv4`/`internal_ipv6`
- `network_interfaces.subnet_id → subnets(id) ON DELETE RESTRICT`
- `subnet_cidr_blocks.subnet_id → subnets(id) ON DELETE CASCADE`

Следствие: `Delete` подсети, на которой висит адрес или NIC → `FailedPrecondition`.

## Жизненный цикл

Одно состояние, `status` отсутствует. Мутации async через `Operation`.

## Gotcha

- **Зону валидирует geo, а не compute.** `zone_id` резолвится peer-вызовом
  `geo.v1.ZoneService.Get`; ребро `vpc → geo`. Прежняя редакция называла владельцем
  `compute.Zone`: таблицы `zones`/`regions` в compute действительно были — и **дропнуты**,
  а message `Zone` в compute-контракте нет ни одного.
- **Регион зоны НИКОГДА не выводится из имени** — только резолв у владельца либо
  авторитетное поле `Subnet.region_id`. Разбор запрета — `data-integrity.md`.
- **Пересечение ловит EXCLUDE (SQLSTATE 23P01)** → `FailedPrecondition`; software-проверка
  «сначала посмотреть, потом вставить» запрещена (ban #10).
- **Подсеть бывает v6-only и v4-only**; пустыми оба семейства быть не могут.
- **REST-глаголы в kebab-case**: `POST /vpc/v1/subnets/{subnet_id}:add-cidr-blocks`
  (не `:addCidrBlocks`) — сверено по `google.api.http` в `subnet_service.proto`.

> [!note] История: миграции до baseline
> Номера ниже `0001_initial.sql` — археология; физически их нет. Номера **0002 и выше** в
> `services/vpc/internal/migrations/` — живые, применяются поверх baseline.

## См. также

[[vpc-network]] · [[vpc-address]] · [[vpc-networkinterface]] · [[geo-zone]] · [[../rpc/vpc-subnet-service]]

#resource #vpc #subnet #cidr
