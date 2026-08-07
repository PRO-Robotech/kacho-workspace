---
title: ServiceAccountService
aliases:
  - ServiceAccountService (iam)
proto_file: kacho/cloud/iam/v1/service_account_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-service-account]]"
methods_count: 8
async_methods: 5
status: planned
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
tags:
  - rpc
  - kacho-iam
  - iam
verified_against: "перечень RPC сверен с proto ствола redesign/integration в ОБЕ стороны 2026-08-05 (методы контракта против методов записки); поля запросов и семантика построчно не пересматривались"
---

# ServiceAccountService (iam)

**Proto**: `proto/kacho/cloud/iam/v1/service_account_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public
**Status**: backend в [[KAC-112]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetServiceAccountRequest | ServiceAccount | sync | |
| List | ListServiceAccountsRequest | ListServiceAccountsResponse | sync | filter account_id. **`viewer ∪ v_list`** (эталон role.List; DIVERGENCE-A): anonymous→empty, FGA error→`Unavailable`, self-floor, admin/owner/cluster-admin через viewer-tier; **membership-over-show устранён** (член аккаунта не видит все SA). `Get == List` resolver. |
| Create | CreateServiceAccountRequest | operation.Operation | **async** | account_id required; принимает own-resource `labels` (DIVERGENCE-A; полный annotation-set, паритет account/project — раньше SA request-`labels` были без аннотаций). |
| Update | UpdateServiceAccountRequest | operation.Operation | **async** | UpdateMask `{name, description, labels}`; account_id immutable; `labels` mutable через `update_mask` (DIVERGENCE-A) — label-change co-commit'ит reconcile-event `iam.serviceAccount`. **`enabled` в маску НЕ входит** — см. Disable/Enable ниже. |
| Disable | DisableServiceAccountRequest | operation.Operation | **async** | `:disable`. Учётка перестаёт аутентифицироваться. Идемпотентно (предмет — состояние, не переход). `v_update` @ `iam_service_account` (то же отношение и объект, что у Update) + **`required_acr_min=2`** — порог ИНТЕРАКТИВНЫЙ, машинный принципал от него освобождён платформенным правилом. Аудит `iam.service_account.disabled`. |
| Enable | EnableServiceAccountRequest | operation.Operation | **async** | `:enable`. Обратное действие, та же форма и тот же ярус. Аудит `iam.service_account.enabled`. |
| Delete | DeleteServiceAccountRequest | operation.Operation | **async** | |
| ListOperations | ListServiceAccountOperationsRequest | ListServiceAccountOperationsResponse | sync | |

> **НЕТ key-credentials RPC на E0**. CreateKey/ListKeys/DeleteKey появятся в E2 через Zitadel `client_credentials` grant.

## REST mapping

| HTTP | Method |
|---|---|
| `GET /iam/v1/serviceAccounts/{id}` | Get |
| `GET /iam/v1/serviceAccounts` | List |
| `POST /iam/v1/serviceAccounts` | Create |
| `PATCH /iam/v1/serviceAccounts/{id}` | Update |
| `POST /iam/v1/serviceAccounts/{id}:disable` | Disable |
| `POST /iam/v1/serviceAccounts/{id}:enable` | Enable |
| `DELETE /iam/v1/serviceAccounts/{id}` | Delete |
| `GET /iam/v1/serviceAccounts/{id}/operations` | ListOperations |

## Notes

- **Почему Disable/Enable — действия, а не поле маски.** У `Update` пустая маска по конвенции
  означает полную замену объекта, а `bool` в proto3 неотличим от неприсланного: клиент, не
  заполнивший поле, отключил бы учётку молча. Плюс отключение — событие, а не правка атрибута,
  и в журнале обязано читаться событием. Плюс это смена security-posture — полоса, где действует
  порог повышенной аутентификации, а обычный CRUD её не несёт. Порог — про
  СТОИМОСТЬ для человека, не второй гейт: машина им не ограничена, весь «кто
  вправе» решает модель через `v_update`.
- **Порядок между двумя одновременными запросами не гарантирован** — мутации
  асинхронные, поэтому `Enable`, отправленный раньше, может закоммититься позже
  `Disable`. Состояние перечитывать через `Get`, не выводить из порядка отправки.
- Оба типа метаданных разбираются `operationresolver` (иначе осиротевшая операция
  никогда не станет терминальной); дрейф закрыт гейтом
  `metadata_coverage_test.go`, который сверяет объявленные типы с ветками
  переключателя по AST — на момент посадки непокрытыми остаются 18 типов, все
  запинены реестром.
- Без E2 SA остаётся identity-stub: не может «логиниться» (нет credentials).
- Delete SA с активной GroupMember/AccessBinding — на E0 sentinel `FailedPrecondition` от service-слоя.


## Сверка со стволом (2026-08-05)

В контракте **восемь** RPC. **Не были названы в записке**: `Disable`
(`POST /iam/v1/serviceAccounts/{service_account_id}:disable` → `Operation`) и `Enable`
(`…:enable` → `Operation`), с парными метаданными `DisableServiceAccountMetadata` /
`EnableServiceAccountMetadata`.

Отключение — **действие**, а не поле в `Update`: у него свой глагол, своя операция и свои
метаданные, поэтому «выключить учётку» нельзя выполнить незаметно через частичное
обновление, и в истории операций оно видно отдельной записью.

## See also

[[../packages/iam-domain]] [[../resources/iam-service-account]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
