---
title: Gateway
aliases:
  - Gateway (vpc)
  - vpc Gateway
category: resource
domain: vpc
id_prefix: gtw
owner_table: kacho_vpc.gateways
owner_db: kacho_vpc
project_level: true
status: stable
verified_against: "ствол redesign/integration, сверено 2026-08-05"
related_rpc:
  - "[[rpc/vpc-gateway-service]]"
related_packages:
  - "[[packages/vpc-apps-kacho-api-gateway]]"
tags:
  - resource
  - kacho-vpc
  - gateway
---

# Gateway

**Домен**: vpc · **владелец**: сервис `kacho-vpc` (`services/vpc/`)
**ID prefix**: `gtw` (`ids.PrefixGateway`) — **не** `enp`
**Owner table**: `kacho_vpc.gateways`
**Scope**: project

**Контракт**: `proto/kacho/cloud/vpc/v1/gateway.proto`
**Схема**: `services/vpc/internal/migrations/0001_initial.sql`

## Поля (`message Gateway`)

| Поле | Тип | Заметка |
|---|---|---|
| `id` | string | `gtw<17>` |
| `project_id` | string | ссылка → **iam** `Project` |
| `created_at` | Timestamp | |
| `name`, `description`, `labels` | | |
| `gateway` | **oneof** | сейчас ровно одна ветка: `shared_egress_gateway` (`message SharedEgressGateway` — пустой) |

В таблице тип живёт скаляром `gateway_type text NOT NULL DEFAULT 'shared_egress'`; в
контракте это `oneof`, то есть при появлении второго типа шлюза добавляется ветка, а не
флаг. Значение дискриминатора и его конфигурация неразделимы — новый тип нельзя ввести,
не сказав, чем он сконфигурирован.

`SharedEgressGateway` сегодня **пуст** — у общего egress-шлюза настраиваемых полей нет.
Это не заглушка: ветка oneof несёт сам факт выбора типа.

## Ссылки внутри домена

- `route_tables.static_routes[].gateway_id` — ссылка из JSONB-массива [[vpc-routetable]].
  Строгого FK на массив в JSONB нет (Postgres такого не выражает), поэтому существование
  шлюза проверяется на мутации маршрута. Это **не** обход ban #10: within-service
  ссылочная целостность на массив JSONB не выражается FK, и проверка выполняется
  в той же writer-транзакции.

## Gotcha

- `Delete` шлюза, на который смотрит статический маршрут, → `FailedPrecondition`.
- `GatewayService.Move` не существует ([[KAC-266]]); `project_id` неизменяем.
- Зоны/региона шлюз не несёт.

## См. также

[[vpc-routetable]] · [[vpc-network]] · [[../rpc/vpc-gateway-service]]

#resource #vpc #gateway
