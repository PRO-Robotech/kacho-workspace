---
title: Address
aliases:
  - Address (vpc)
  - vpc Address
category: resource
domain: vpc
id_prefix: adr
owner_table: kacho_vpc.addresses
owner_db: kacho_vpc
project_level: true
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/vpc-address-service]]"
  - "[[rpc/vpc-internal-address-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-address]]"
  - "[[packages/vpc-apps-kacho-services-addressref]]"
tags:
  - resource
  - kacho-vpc
  - address
  - ipam
---

# Address

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (`services/vpc/`)
**ID prefix**: `adr` (`ids.PrefixAddress`, `pkg/ids/ids.go`)
**Owner table**: `kacho_vpc.addresses` (+ `kacho_vpc.address_references`)
**Scope**: project

**Контракт**: `proto/kacho/cloud/vpc/v1/address.proto`
**Схема**: `services/vpc/internal/migrations/0001_initial.sql` + 0013, 0023, 0025, 0026

> [!note] ID prefix здесь стоял неверный
> Прежняя редакция объявляла `e9b` «общим с Subnet». Общего prefix у vpc-ресурсов нет:
> `pkg/ids/ids.go` даёт каждому свой (`net`/`sub`/`adr`/`rtb`/`sgr`/`gtw`/`nic`/`apl`).
> `e9b` числится в общем каталоге `KnownPrefixes` как legacy-значение, а `enp` — это
> **op-root vpc** (`PrefixOperationVPC`), то есть prefix идентификатора `Operation`,
> а не ресурса. Комментарий в самом `ids.go` про «Subnet/Address делят `e9b`» тоже
> пережил свои константы — при сверке смотреть на константы, а не на комментарий рядом.

## Поля публичной проекции (`message Address`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `adr<17>`; immutable |
| `project_id` | string | ссылка → **iam** `Project` |
| `created_at` | Timestamp | truncate до секунд |
| `name`, `description`, `labels` | | `UNIQUE (project_id, name)` partial |
| `address` | **oneof**, `exactly_one` | ровно одна из четырёх веток (ниже) |
| `reserved` | bool | тенантский флаг |
| `used` | bool | output-only признак занятости |
| `type` | enum `Type` | `INTERNAL` \| `EXTERNAL` |
| `ip_version` | enum `IpVersion` | `IPV4` \| `IPV6` |
| `deletion_protection` | bool | |
| `used_by` | repeated `reference.Reference` | output-only зеркало, кто ссылается |

Ветки `oneof address` (номера полей 7, 8, 22, 23):
`external_ipv4_address`, `internal_ipv4_address`, `internal_ipv6_address`,
`external_ipv6_address`. Опция `exactly_one` делает выбор обязательным на уровне контракта.

> [!warning] `dns_records` снят с контракта
> `reserved 20; reserved "dns_records";` — домена DNS в сервисе нет вовсе, поэтому поле
> удалено, а не оставлено «на будущее». Прецедент из `api-conventions.md`
> §«Принято-и-проигнорировано»: молча принять и выбросить — не исход.
> Также `reserved 9 to 14`.

## Таблица: JSONB-ветки + generated FK

Колонки `external_ipv4`, `internal_ipv4`, `external_ipv6`, `internal_ipv6` — `jsonb`
(каждая несёт свой `{address, subnet_id|address_pool_id}`); плюс скаляры `addr_type`,
`ip_version`, `reserved`, `used`, `deletion_protection`.

Ключевой приём — **generated-колонка как якорь FK**:

```sql
internal_subnet_id text GENERATED ALWAYS AS (
    CASE WHEN internal_ipv4 ? 'subnet_id' AND length(internal_ipv4->>'subnet_id') > 0
         THEN internal_ipv4->>'subnet_id'
         WHEN internal_ipv6 ? 'subnet_id' AND length(internal_ipv6->>'subnet_id') > 0
         THEN internal_ipv6->>'subnet_id'
         ELSE NULL END
) STORED REFERENCES kacho_vpc.subnets(id) ON DELETE RESTRICT
```

То есть внутренний адрес (v4 или v6) **блокирует свою подсеть** обычным FK, хотя сам
живёт в JSONB. `0025_addresses_read_path.sql` добавила CHECK
`addresses_single_internal_family` (одновременно v4 и v6 internal — запрещено) и индекс
по `internal_ipv4->>'address'` для read-path.

## Уникальность (partial UNIQUE — по DDL)

- `addresses_project_id_name_key` — (project_id, name)
- `addresses_external_ip_uniq` — глобальная уникальность внешнего v4
- `addresses_external_pool_ip_uniq` — (pool_id, ip) для внешнего v4
- `addresses_internal_subnet_ip_uniq` — (subnet_id, ip) для внутреннего v4
- `addresses_internal_subnet_ipv6_uniq` — то же для v6
- `addresses_external_v6_pool_ip_uniq` — (pool_id, ip) для внешнего v6
- `addresses_external_v6_ip_uniq` (0026) — глобальная уникальность внешнего v6

## Referrer-трекинг — отдельная таблица, а не колонка

```sql
CREATE TABLE kacho_vpc.address_references (
    address_id    text PRIMARY KEY REFERENCES kacho_vpc.addresses(id) ON DELETE CASCADE,
    referrer_type text NOT NULL,
    referrer_id   text NOT NULL,
    referrer_name text NOT NULL DEFAULT '',
    attached_at   timestamptz NOT NULL DEFAULT now(),
    owned         boolean NOT NULL DEFAULT false   -- миграция 0013
);
```

`owned` — **несущее различие**, а не флажок удобства:

- `owned = true` — адрес заказан ссылающимся неявно, его жизненный цикл привязан к
  ссылающемуся; освобождение = `ClearReference` **и** удаление адреса;
- `owned = false` (умолчание) — тенант создал адрес заранее и лишь залинковал;
  освобождение = только `ClearReference`, адрес остаётся за тенантом.

Прежняя редакция описывала это булевой колонкой `is_ephemeral` на самом адресе —
такой колонки в схеме нет; семантика живёт на строке ссылки.

## IPAM: путь адреса

1. Тенант создаёт Address → внешний IP берётся из [[vpc-addresspool]] через
   CAS-аллокацию из free-list (`FOR UPDATE SKIP LOCKED LIMIT 1` + `DELETE … RETURNING`).
2. Потребитель (NIC/инстанс) ставит ссылку — `InternalAddressService.SetAddressReference`
   с `owned`; CAS «свободно ИЛИ уже наш» ⇒ идемпотентно.
3. Отцепление — `ClearAddressReference`; при `owned=true` инициатор доудаляет адрес.
4. Эфемерный путь — `MarkAddressEphemeralInUse` (internal), когда адрес выдан «под задачу».
5. `Delete` адреса под живой ссылкой → `FailedPrecondition`.

Возврат lease в free-list на **каждом** пути высвобождения — часть контракта Delete
(`data-integrity.md` §Lease-recycle-on-delete), иначе пул исчерпывается под параллельным
e2e и рождает фантомные ресурсы.

## Gotcha

- **`used_by` — не software check-then-act.** Смена владения только атомарным CAS в одном
  UPDATE (ban #10).
- **Зону адрес не несёт** — наследует через `subnet_id`. У REGIONAL-подсети зоны нет,
  адреса region-scoped (anycast).
- **`GetByValue`** — отдельный RPC (`GetAddressByValue`), потому что искать по значению IP
  через `Get(id)` нельзя: адресация ресурса — по `id` (ban #15).

> [!note] История: миграции до baseline
> Номера ниже `0001_initial.sql` — археология. Живые номера — 0002 и выше.

## См. также

[[vpc-subnet]] · [[vpc-addresspool]] · [[vpc-networkinterface]] · [[../rpc/vpc-address-service]] · [[../rpc/vpc-internal-address-service]]

#resource #vpc #address #ipam
