---
title: AuthorizeService
aliases:
  - AuthorizeService (iam)
  - FGA Check
proto_file: kacho/cloud/iam/v1/authorize_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-access-binding]]"
methods_count: 6
async_methods: 0
status: active
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - fga
  - authz
verified_against: "ствол redesign/integration, сверено 2026-08-05"
---

> [!note] Сверка со стволом (2026-08-05)
> Сервис жив: `proto/kacho/cloud/iam/v1/authorize_service.proto`, шесть RPC —
> `Check`, `BatchCheck`, `ListObjects`, `ListSubjects`, `ExpandRelations`, `WhoAmI`
> (имена сверены по контракту). Там же живут `message ResourceRef` (закрытая таблица
> целей авторизации, **без** поля имени — least-info) и `AccountMembership`.
>
> **Две ссылки в подвале ведут к снятым предметам**: `iam-conditions-service` и
> `iam-access-binding-condition` — тенант-facing Condition-поверхность снята миграцией
> `0075_retire_tenant_condition_surface.sql`. Ссылки оставлены намеренно (обе записки
> живы как история и несут предикат переписи), но принимать их за действующие соседние
> сервисы нельзя. Условия **на кортеже** — другой предмет, они живы и лежат на внутреннем
> листенере (`TupleCondition` в `internal_authorize_service.proto`).
>
> Ссылка `edges/iam-to-opa` описывает подкладку, которой в дереве нет: решение о доступе
> принимает модель отношений, а не политика в сайдкаре
> (`security.md` §«Авторизация живёт в МОДЕЛИ»); одноимённый бандл-сервис снят —
> см. [[iam-opa-bundle-service]].

# AuthorizeService (iam)

**Proto**: `proto/kacho/cloud/iam/v1/authorize_service.proto`.
**Backend**: `kacho-iam:9090` (public mux + cluster-internal listener для api-gateway).
**Visibility**: **public** — per-RPC authorization-gate. Потребители: интерсептор
api-gateway, фильтры видимости списков vpc / compute / nlb / storage / registry / geo, kacho-ui.

> [!important] Сужение списка у потребителя — это `BatchCheck`, а НЕ `ListObjects`
> `ListObjects` сервисом по-прежнему **обслуживается** (см. таблицу), но
> потребителю **запрещено** сужать им список: у перечисления жёсткий серверный
> предел и нет продолжения, поэтому ответ — произвольный префикс, а предел общий
> на тип для всего кластера. Потребитель читает страницу курсором из своей БД и
> спрашивает `BatchCheck` про id **этой страницы**. Запрет исполняем: имена
> `ListObjects`/`ListAllowedIDs` внесены в запрещённые у анализатора сужения
> **каждого** сервиса-потребителя. Рёбра: [[../edges/vpc-to-iam-listobjects]],
> [[../edges/compute-to-iam-listobjects]], [[../edges/nlb-to-iam-listobjects]].

> [!warning] Условного доступа на этой поверхности больше нет
> Прежняя редакция описывала сервис как обёртку над хранилищем прав «с
> Conditions-overlay». Тенантская поверхность условного доступа **снята с
> контракта** (одним изменением на 101 файл). Осталась модель без условий на
> тенантских отношениях.

## Methods (sync)

| Method | Description |
|---|---|
| Check | single-tuple boolean: `(user, relation, object) → allowed=bool`. SLO p95 ≤20ms (Phase 3 DoD). |
| BatchCheck | до 100 tuples в одном RPC (api-gateway batches per-request). Returns `[]CheckResult`. |
| ListObjects | «какие объекты типа доступны субъекту». Объединяет `viewer ∪ v_list`. **Потребителю для сужения списка запрещён** — см. предупреждение выше; остаётся для админских/диагностических путей, где усечение приемлемо и заявлено. |
| ListSubjects | «у кого есть отношение к объекту» — админский разбор выдач. |
| ExpandRelations | разворот дерева отношений для отладки. |
| WhoAmI | опознание вызывающего по предъявленным учётным данным. |

## Request flow (Check)

1. Extract caller identity (`user:usr_xxx` или `service_account:sva_xxx`) из DPoP-bound JWT claims.
2. Resolve relevant `AccessBindingCondition` (CEL params) + `JITEligibility` activation state.
3. Forward to OpenFGA `Check` API ([[../edges/iam-to-openfga-check]]).
4. OPA cluster-deny gate ([[../edges/iam-to-opa]]) — fail-closed override (org-wide policy / break-glass override).
5. Cache result (5s TTL) keyed on `(user, relation, object, condition_hash)`.

## REST mapping (public mux, Phase 3)

| HTTP | Method |
|---|---|
| `POST /iam/v1/authorize:check` | Check |
| `POST /iam/v1/authorize:batchCheck` | BatchCheck |
| `POST /iam/v1/authorize:listObjects` | ListObjects |
| `POST /iam/v1/authorize:listSubjects` | ListSubjects |
| `POST /iam/v1/authorize:expand` | ExpandRelations |

## Errors

- `PermissionDenied` — `allowed=false` (NB: Check returns boolean; PD only for caller-not-allowed-to-Check).
- `Unavailable` — OpenFGA / OPA недоступен → fail-closed для мутаций, fail-open behind flag для read.
- `InvalidArgument` — malformed tuple.

## Notes

- DPoP / mTLS-bound JWT verify происходит на api-gateway middleware ([[../packages/api-gateway-middleware-dpop]] + [[../packages/api-gateway-middleware-authz]]) до этого RPC.
- Write-path (tuple sync) — НЕ здесь, а через `InternalAuthorizeService.WriteTuples` ([[iam-internal-authorize-service]]).
- ListObjects pagination cursor opaque, signed → защита от tuple-store enumeration.

## See also

[[iam-internal-authorize-service]] [[iam-conditions-service]] [[../resources/iam-access-binding]] [[../resources/iam-access-binding-condition]] [[../edges/api-gateway-to-iam-authorize]] [[../edges/iam-to-openfga-check]] [[../edges/iam-to-opa]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #fga #authz
