---
title: NetworkLoadBalancerService
aliases:
  - NetworkLoadBalancerService (nlb)
  - NLB service
proto_file: kacho/cloud/loadbalancer/v1/network_load_balancer_service.proto
category: rpc
backend: kacho-nlb
backend_port: 9090
visibility: public
domain: nlb
related_resource: "[[resources/nlb-load-balancer]]"
methods_count: 8
async_methods: 5
status: stable
tags:
  - rpc
  - kacho-nlb
  - loadbalancer
verified_against: "перечень RPC сверен с proto ствола redesign/integration в ОБЕ стороны 2026-08-05 (методы контракта против методов записки); поля запросов и семантика построчно не пересматривались"
---

# NetworkLoadBalancerService (nlb)

**Proto**: `proto/kacho/cloud/loadbalancer/v1/network_load_balancer_service.proto`
**Backend**: `kacho-nlb:9090` (public gRPC)
**Public/Internal**: public

## Methods — таблица ниже описывает СНЯТУЮ поверхность (12 строк вместо восьми)

> Четыре строки — `Start`, `Stop`, `AttachTargetGroup`, `DetachTargetGroup` — контракту
> ствола не соответствуют; разбор и замена — в §«Сверка со стволом» ниже. Таблица
> оставлена как история решения, а не как перечень доступных вызовов.

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Get | GetNetworkLoadBalancerRequest | NetworkLoadBalancer | sync | NotFound → 404 |
| List | ListNetworkLoadBalancersRequest | ListNetworkLoadBalancersResponse | sync | filter `name=`, page_token, page_size |
| Create | CreateNetworkLoadBalancerRequest | operation.Operation | **async** | metadata: CreateNetworkLoadBalancerMetadata{network_load_balancer_id} |
| Update | UpdateNetworkLoadBalancerRequest | operation.Operation | **async** | UpdateMask; immutable: type/region_id/project_id |
| Delete | DeleteNetworkLoadBalancerRequest | operation.Operation | **async** | sync precheck: deletion_protection, has listeners, has attached TG |
| Start | StartNetworkLoadBalancerRequest | operation.Operation | **async** | precondition: status ∈ {STOPPED, INACTIVE} |
| Stop | StopNetworkLoadBalancerRequest | operation.Operation | **async** | precondition: status ∈ {ACTIVE, INACTIVE} |
| Move | MoveNetworkLoadBalancerRequest | operation.Operation | **async** | cross-project, same-region; blocked if attached TG present |
| AttachTargetGroup | AttachTargetGroupRequest | operation.Operation | **async** | same-region check; M:N pivot ON CONFLICT idempotent |
| DetachTargetGroup | DetachTargetGroupRequest | operation.Operation | **async** | respects `deregistration_delay_seconds` |
| GetTargetStates | GetTargetStatesRequest | GetTargetStatesResponse | sync | computed runtime (deterministic ramp INITIAL→HEALTHY) |
| ListOperations | ListNetworkLoadBalancerOperationsRequest | ListNetworkLoadBalancerOperationsResponse | sync | per-resource history |

## REST mapping

| HTTP | Method |
|---|---|
| `GET /nlb/v1/networkLoadBalancers/{network_load_balancer_id}` | Get |
| `GET /nlb/v1/networkLoadBalancers` | List |
| `POST /nlb/v1/networkLoadBalancers` | Create |
| `PATCH /nlb/v1/networkLoadBalancers/{network_load_balancer_id}` | Update |
| `DELETE /nlb/v1/networkLoadBalancers/{network_load_balancer_id}` | Delete |
| `POST /nlb/v1/networkLoadBalancers/{id}:start` | Start |
| `POST /nlb/v1/networkLoadBalancers/{id}:stop` | Stop |
| `POST /nlb/v1/networkLoadBalancers/{id}:move` | Move |
| `POST /nlb/v1/networkLoadBalancers/{id}:attachTargetGroup` | AttachTargetGroup |
| `POST /nlb/v1/networkLoadBalancers/{id}:detachTargetGroup` | DetachTargetGroup |
| `GET /nlb/v1/networkLoadBalancers/{id}/targetStates` | GetTargetStates |
| `GET /nlb/v1/networkLoadBalancers/{id}/operations` | ListOperations |

## FGA Permissions

- `Get` / `List` → `viewer` on `project:<project_id>` или `nlb_load_balancer:<id>`
- `Create` → `editor` on `project:<project_id>`
- `Update` / `Delete` / `Start` / `Stop` / `AttachTargetGroup` / `DetachTargetGroup` → `editor` on `nlb_load_balancer:<id>`
- `Move` → `editor` on src + dst `project`
- `GetTargetStates` / `ListOperations` → `viewer` on `nlb_load_balancer:<id>`

См. [[../packages/nlb-internal-check]] permission_map + [[../packages/nlb-permissions-catalog]].

## RBAC sub-phase D §11 — per-object filtered List (issue #111)

`List` (NLB / Listener / TargetGroup) теперь отдаёт **только доступные** объекты:
use-case прогоняет id-set через `iam.AuthorizeService.ListObjects(subject,
"loadbalancer.<res>.list", "lb_*")` → repo `WHERE id = ANY` ДО LIMIT
(pagination-after-filter). read==enforce (Get-Check relation viewer, та же
tuple-база), fail-closed (iam down → UNAVAILABLE), no-leak (empty grant → `[]`;
Get вне гранта → 404 via per-RPC Check). Toggle `authz.list-filter.enabled`
(default true). Детали — [[../edges/nlb-to-iam-listobjects]] / [[../KAC/rbac-rules-model-2026-subphase-D-nlb-consumer]].


## Сверка со стволом (2026-08-05)

В контракте `proto/kacho/cloud/loadbalancer/v1/network_load_balancer_service.proto` —
**восемь** RPC: `Get`, `List`, `Create`, `Update`, `Delete`, `Move`, `GetTargetStates`,
`ListOperations`. Мутации возвращают `Operation`; `Move` **жив** (в отличие от домена vpc,
где все `Move` сняты).

**Названы в записке, но в контракте отсутствуют**: `Start`, `Stop`, `AttachTargetGroup`,
`DetachTargetGroup`. Каждое снято осознанно, и proto это фиксирует резервированием:

- **`attached_target_groups`** — слот 13 в `message NetworkLoadBalancer`, зарезервирован
  и номером, и именем. Прежний M:N-снимок на балансировщике снят: авторитетная привязка
  теперь **на `Listener`** (`target_group_id`), а не на балансировщике и не парой глаголов.
  Таблица `kacho_nlb.attached_target_groups` дропнута. Один источник истины вместо снимка
  плюс глаголов, которые могли с ним разъехаться.
- **`Start` / `Stop`** — вместе с ними из `enum Status` вычеркнуты `STARTING(2)`,
  `STOPPING(4)`, `STOPPED(5)` (`reserved 2, 4, 5`). Административное включение/выключение
  выражено полем `admin_state`, то есть **состоянием**, а не парой команд. Отзвук того же
  решения в iam — миграция `0059_nlb_operator_drop_start_stop.sql`, снимающая
  соответствующие права.

Заодно `NetworkLoadBalancer` зарезервировал по **имени** `listeners` (слушатель стал
самостоятельным ресурсом), `allow_zonal_shift`, `disable_zone_statuses`, `network_id`,
`attached_target_groups`, `address_v4`, `address_v6`, `ip_families`, а пер-зональные слоты
15/18 — как несовместимые с anycast. Сеть выводится, VIP описывается `VipSource`.

> [!important] Два поля вернулись под НОВЫМИ номерами — не считать их снятыми
> `cross_zone_enabled` жив полем **42**, `security_group_ids` — полем **43**
> (возврат закреплён миграцией `0020_load_balancer_security_group_ids_revival.sql`).
> Их прежние слоты в диапазоне 19–23 зарезервированы, но **имена** этих двух в списке
> `reserved "…"` не значатся — именно потому, что они переиспользуются. Вывод «имя
> упомянуто в комментарии про снятое ⇒ поля нет» здесь неверен: смотреть надо на
> действующие объявления, а не на прозу рядом с ними.

**`List`: в proto `<exempt>`, в сервисе — `ScopeFiltered`.** Край per-RPC Check по этому
методу не делает; карта прав nlb (`services/nlb/internal/check/permission_map.go`) несёт
для него отношение `viewer` на `project:<project_id>` с флагом `ScopeFiltered: true` — то есть авторизация выполняется на уровне данных, по идентификаторам отданной страницы.

> [!note] Здесь nlb и vpc устроены ПО-РАЗНОМУ, и это не оплошность
> У vpc `NetworkService/List` тоже `<exempt>` в proto, но в карте прав он **намеренно НЕ**
> помечен `ScopeFiltered`: там per-RPC Check обязателен, а фильтр по данным лишь сужает
> поверх него. Значит вывод «exempt в proto ⇒ отбор только по данным» неверен как общее
> правило — сверять надо карту прав **конкретного** сервиса. Следствие для эксплуатации:
> у метода с `ScopeFiltered` production boot-guard отказывается стартовать без рабочего
> фильтра, а пустой субъект обязан отсекаться безусловно — откатываться там не на что.

## See also

[[../packages/nlb-apps-kacho-api-loadbalancer]] [[../resources/nlb-load-balancer]] [[nlb-listener-service]] [[nlb-target-group-service]] [[../edges/nlb-to-iam-listobjects]]

#rpc #kacho-nlb #loadbalancer
