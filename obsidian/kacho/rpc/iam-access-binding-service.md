---
title: AccessBindingService
aliases:
  - AccessBindingService (iam)
proto_file: kacho/cloud/iam/v1/access_binding_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-access-binding]]"
methods_count: 7
async_methods: 2
status: done
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-129]]"
  - "[[KAC-131]]"
  - "[[sub-phase-1.2-iam-operations]]"
  - "[[sub-phase-1.3-subject-privileges]]"
tags:
  - rpc
  - kacho-iam
  - iam
---

# AccessBindingService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/access_binding_service.proto`
**Backend**: `kacho-iam:9090` (public gRPC)
**Visibility**: public
**Status**: backend в [[KAC-112]]. E0 хранит binding'и, **не** enforce'ит authz — E3 ([[KAC-108]]) добавит Check-interceptor.

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| Create | CreateAccessBindingRequest | operation.Operation | **async** | UNIQUE → идемпотентный re-create; пишет FGA grant-tuple |
| Delete | DeleteAccessBindingRequest | operation.Operation | **async** | по id; **удаляет FGA grant-tuple** (revoke) |
| Get | GetAccessBindingRequest | AccessBinding | sync | |
| ListByResource | ListAccessBindingsByResourceRequest | ListAccessBindingsResponse | sync | filter (resource_type, resource_id) |
| ListBySubject | ListAccessBindingsBySubjectRequest | ListAccessBindingsResponse | sync | filter (subject_type, subject_id) |
| ListOperations | ListAccessBindingOperationsRequest | ListAccessBindingOperationsResponse | sync | per-resource ops history (sub-phase 1.2; filter `resource_id`, viewer-tier). Был дырой → UI таб «Операции» бил в 404. |
| ListSubjectPrivileges | ListSubjectPrivilegesRequest | ListSubjectPrivilegesResponse | sync | sub-phase 1.3 (+1.3b) — все привилегии субъекта (effective roles); `subject_type ∈ {user, service_account, **group**}` (group добавлен в 1.3b, iam#162; было user\|service_account). `SubjectPrivilege{ subject_type, subject_id, role_id, role_name, resource_type, resource_id, scope, derivation }` + `Derivation` enum. LEFT JOIN roles для `role_name`. Authz self-OR-account-admin (`requireAccountViewAuthority`; для group home-account через `groups.account_id`). |

## REST mapping

| HTTP | Method |
|---|---|
| `POST /iam/v1/accessBindings` | Create |
| `GET /iam/v1/accessBindings/{id}` | Get |
| `DELETE /iam/v1/accessBindings/{id}` | Delete |
| `POST /iam/v1/accessBindings:listByResource` | ListByResource |
| `POST /iam/v1/accessBindings:listBySubject` | ListBySubject |
| `GET /iam/v1/accessBindings/{access_binding_id}/operations` | ListOperations |
| `GET /iam/v1/accessBindings:listSubjectPrivileges` | ListSubjectPrivileges |

## Notes

- UNIQUE (subject_type, subject_id, role_id, resource_type, resource_id) ловит дубликаты; `maperr.go` mapping для этого constraint — `success (no-op)` либо `AlreadyExists` (см. acceptance §6 / §13.4). **KAC-128 BUG-7 fix**: Operation metadata `access_binding_id` теперь содержит СУЩЕСТВУЮЩИЙ id (pre-resolved через `FindExisting` до создания Operation) — не кандидат-id. DB ON CONFLICT остаётся safety-net.
- `subject_id` / `resource_id` хранятся **без FK** (полиморфно, cross-DB) — software-validation отложена в E3 (OpenFGA tuple sync через [[../edges/iam-to-openfga-check]]).
- Удаление Role с активным binding → `FailedPrecondition "Role <id> is in use by access bindings"` (FK RESTRICT).
- **Auth-matrix (KAC-123)** для ListBySubject в handler:
  - explicit `service_account` principal → bypass (admin-tooling).
  - `user` principal → разрешено ТОЛЬКО запрашивать **свои** bindings (`subject_type=user && subject_id=<self>`); иначе 403 `PermissionDenied`.
  - anonymous / system-bootstrap fallback → empty list.
- **Create/Delete authority** (KAC review 2026-05-21 #8/#13): и Create, и Delete авторизуются через общий `requireGrantAuthority` — caller обязан быть owner владеющего Account/Project ИЛИ держать FGA `admin` на scope. Delete больше **не** self-only (`subject_id==principal` убран) — account-owner может отзывать чужие grants.
- **FGA sync (KAC-129 fix #8/#16/#47/#48)**: `Delete.doDelete` после DB-commit удаляет те же tuple'ы, что записал `Create` — через общий `accessBindingTuples(b, relation)` + `OpenFGAClient.DeleteTuples`. Побайтовая идентичность ключей гарантирует, что FGA действительно удаляет (мисматч = silent no-op). До KAC-129 Delete не имел FGA-клиента → туплы оставались, Check → `allowed:true` после Delete. Verified live: 55→53 tuples, Check → `allowed:false`.
- **KAC-131 authz catalog (2026-05-23)**: `Get`, `Delete`, `ListByResource`, `ListBySubject` переведены в `<exempt>` в permission_catalog.json. Причина: (a) account-scoped AB не получал FGA иерархический тупл (только `project`-тип — BUG-6); (b) ListByResource/ListBySubject имели неверный `scope_extractor` → FGA всегда "no path" (BUG-8). Authz теперь — handler-level scope-filter: `Get` — subject/owner check; `Delete` — `requireGrantAuthority`; List* — `RequireAuthenticated`. `Create` остаётся FGA-gated.
- **KAC-131 existence-leak prevention**: `Get` и `Delete` для несуществующего ID возвращают `PermissionDenied` (не `NotFound`) — предотвращает ID-enumeration. `garbage-perresource` authz-deny тест проходит для всех субъектов (403+code 7).

- **KAC-133 partial-UNIQUE scope fix (2026-05-23)**: `FindExisting` добавлен `AND status = 'ACTIVE'` — без этого возвращалась REVOKED-row с другим id, ломая idempotent re-create (IAM-ACB-CR-IDEM-13.4). Соответствует migration 0022 (partial UNIQUE WHERE status='ACTIVE').
- **KAC-133 ListBySubject self-check**: enforced в use-case — `user` principal может запрашивать ТОЛЬКО свои bindings; cross-user → 403 (KAC-123 requirement).
- **KAC-133 ListByResource scope-gate**: use-case добавил `requireGrantAuthority` check — non-member не может перечислить bindings на ресурсе. FGA-wired в main.go. Catalog остаётся `<exempt>`, authz — handler-level.
- **REST HTTP verbs (KAC-133 fix)**: `ListByResource` и `ListBySubject` — `GET` с query params (НЕ POST + body). Тесты ошибочно использовали POST, что давало catalog-miss → 403.
- **Bug A — ListByResource scope-polymorphism (2026-06-14, proto #55 / api-gateway #74)**: catalog для `ListByResource` теперь несёт `object_type_from_request_field=resource_type` — api-gateway берёт FGA object type из request `resource_type` (project|account|cluster), а не статический `project`. До фикса account/cluster-scoped listByResource проверял `project:<id>` → 403 у владельца. Handler-side `requireGrantAuthority` уже умеет cluster (FGA `admin@cluster`), поэтому listByResource(cluster) у bootstrap-admin теперь 200.
- **Bug B — cluster-scope Get readability (2026-06-14, iam #107)**: `GetAccessBindingUseCase` раньше имел только `account`/`project` owner-switch — cluster-scope binding был нечитаем кем-либо кроме своего subject (bootstrap cluster-admin получал 403). Теперь non-subject путь идёт через общий `requireGrantAuthority` (owner ИЛИ FGA-admin, единообразно account/project/cluster). `WithOpenFGA` подключён в composition root. Связанный фикс: `seed.RunBootstrapAdmin` теперь wired как startup-reconciler (KACHO_IAM_BOOTSTRAP_ROOT_EMAIL) → пишет `system_admin@cluster_kacho_root` через fga_outbox-drainer (раньше SQL-seed в обход outbox).
- **ListOperations (sub-phase 1.2, iam #160)** — per-resource ops history для одного AB; `WithListOperations` mirror; AB stays viewer@iam_access_binding (no account-fallback нужен). См. [[sub-phase-1.2-iam-operations]].
- **ListSubjectPrivileges (sub-phase 1.3, iam #159 / api-gateway #84)** — public sync read; возвращает все привилегии субъекта (effective roles) с `role_name` (LEFT JOIN roles) и `derivation`-источником. Authz `requireAccountViewAuthority` (self ИЛИ account-admin). Питает UI вкладку «Привилегии» на User/ServiceAccount. См. [[sub-phase-1.3-subject-privileges]].
- **1.3b group support (iam #162 / ui #82, live fe3455 rev14)** — `subject_type=group` теперь принимается (был вне scope в 1.3). Group connected roles = прямые AccessBinding'и на группе (DIRECT); `resolveSubjectHomeAccount` резолвит home-account группы через `groups.account_id` (within-`kacho_iam`, не новый cross-domain edge). UI: вкладка «Привилегии» добавлена на Group (ui #83 — таб + кнопка в шапке страницы). NB: `kacho-proto` `ListSubjectPrivilegesRequest` doc-comment всё ещё «group — вне scope» (stale, follow-up proto-fix).

## See also

[[../packages/iam-domain]] [[../resources/iam-access-binding]] [[iam-role-service]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]]

#rpc #kacho-iam #iam
