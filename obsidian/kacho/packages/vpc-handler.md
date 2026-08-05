---
title: vpc-handler
category: packages
repo: kacho-vpc
layer: handler
tags:
  - packages
  - kacho-vpc
  - handler
  - internal
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): перечень файлов каталога и место, где реально лежат три названные прежде единицы; текст записки построчно не пересматривался"
---

# kacho-vpc/internal/handler

**Каталог**: `services/vpc/internal/handler/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/handler/`)

Internal admin handlers (внутренний listener 9091) + общие gRPC-side компоненты (interceptors, error mapping, operation-handler).

## Files

| File | Содержание |
|---|---|
| `internal_address_allocate_handler.go` | gRPC adapter для [[../rpc/vpc-internal-address-service]] (Allocate* RPCs) — пробрасывает в [[vpc-apps-kacho-services-addressref]] |
| `internal_network_handler.go` | adapter для [[../rpc/vpc-internal-network-service]] (SetDefaultSecurityGroupId) → [[vpc-apps-kacho-services-networkinternal]] |
| `internal_network_interface_handler.go` | adapter внутренних RPC интерфейса |
| `internal_maperr.go` | internal-side error mapping |
| `operation_handler.go` | [[../rpc/operation-service]] adapter — `Get` / `Cancel` |
| `authn_interceptor.go` | gRPC unary-interceptor: извлечение личности вызывающего из метаданных, trust-aware |
| `deadline_interceptor.go` | per-call deadline на входящих вызовах |
| `recovery_interceptor.go` | recovery; наружу — фиксированный opaque-текст, без утечки внутренней ошибки |
| `*_test.go` | `handler_test.go`, `mock_test.go`, тесты каждого интерсептора, `forged_system_principal_test.go`, `internal_listener_authorization_test.go` |
| `SECURITY.md` | заметки про изоляцию арендаторов |

> [!warning] Три единицы из прежней редакции здесь не лежат — и две из них вообще не vpc
> - Адаптер внутреннего «облачного» сервиса **снят вместе со своим предметом**: RPC
>   выбора пула убраны из proto и реализации, а обе их таблицы дропнуты миграцией
>   `services/vpc/internal/migrations/0002_drop_override_and_cloud_pool_selector.sql`.
>   Снятый адрес здесь намеренно не цитируется в обратных кавычках — цитата мёртвого
>   имени читается как живое утверждение о дереве.
> - Интерсептор арендатора и его тест, а также заглушка снятого стримингового RPC —
>   **существуют, но в другом сервисе**: `services/compute/internal/handler/`. У vpc
>   соответствующую роль играет `authn_interceptor.go`. Это худший вид расхождения из
>   трёх: имя в дереве **резолвится**, поэтому автоматическая проверка на нём молчит, а
>   неверен — адрес владельца. Ловится только переписью по каталогу, чем и был получен
>   этот перечень.
> - Отдельного теста адресного адаптера в каталоге нет; покрытие лежит в общих
>   `handler_test.go` / `internal_address_allocate_handler_test.go`.

## Position

В [[vpc-cmd-vpc]] wiring'е:
- Public listener (9090): handlers из `apps/kacho/api/<resource>/handler.go`.
- Internal listener (9091): handlers из этого пакета + [[vpc-apps-kacho-api-addresspool]] (тоже internal-only).

## See also

[[vpc-apps-kacho-services-addressref]] [[vpc-apps-kacho-services-networkinternal]] [[../rpc/operation-service]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-vpc #handler #internal
