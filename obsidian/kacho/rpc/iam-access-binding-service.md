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
methods_count: 14
async_methods: 5
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
| Create | CreateAccessBindingRequest | operation.Operation | **async** | UNIQUE → идемпотентный re-create; пишет FGA grant-tuple. **sub-phase 1.5 scope-enforcement (D-2)**: `doCreate` читает роль ДО INSERT и энфорсит `domain.IsRoleAssignable` → mis-scoped роль → `Operation.error` **FAILED_PRECONDITION** «not assignable» (binding не создаётся). **Missing роль тоже FAILED_PRECONDITION** (ранний read мапит role-not-found→FP, сохраняя pre-1.5 FK RESTRICT-контракт 23503→9; иначе регрессия 9→5). Forward-only (D-11): гейтит только новые Create. |
| Delete | DeleteAccessBindingRequest | operation.Operation | **async** | по id; **удаляет FGA grant-tuple** (revoke) |
| Get | GetAccessBindingRequest | AccessBinding | sync | self ∪ grant-authority ∪ `viewer/v_list` (label-грант, T3.3 D-6 additive путь, паритет gateway v_get Check) |
| Update | UpdateAccessBindingRequest | operation.Operation | **async** | mutable set `{deletion_protection, labels}` (T3.3-IMM-01). `deletion_protection` (C-03 снятие) + own-resource `labels` (T3.3, label-selectability) в одной writer-tx; иной mask путь (`role_id`/subject/scope/`resource_*`) → `INVALID_ARGUMENT "<field> is immutable after AccessBinding.Create"`. labels-change co-commit'ит reconcile-event `iam.accessBinding`. REST `PATCH …/{id}` |
| **ListByScope** | ListAccessBindingsByScopeRequest | ListAccessBindingsResponse | sync | filter (resource_type, resource_id) — scope-якорь project\|account\|cluster. **Переименован из `ListByResource`, старое wire-имя СНЯТО** (не роутится → 403 catalog-miss, залочено кейсом `IAM-ACB-F50-ROUTES-REMOVED`). REST — **GET** `…:listByScope`. |
| ListBySubject | ListAccessBindingsBySubjectRequest | ListAccessBindingsResponse | sync | filter (subject_type, subject_id) |
| ListOperations | ListAccessBindingOperationsRequest | ListAccessBindingOperationsResponse | sync | per-resource ops history (sub-phase 1.2; filter `resource_id`, viewer-tier). Был дырой → UI таб «Операции» бил в 404. |
| ListSubjectPrivileges | ListSubjectPrivilegesRequest | ListSubjectPrivilegesResponse | sync | sub-phase 1.3 (+1.3b) — все привилегии субъекта (effective roles); `subject_type ∈ {user, service_account, **group**}` (group добавлен в 1.3b, iam#162; было user\|service_account). `SubjectPrivilege{ subject_type, subject_id, role_id, role_name, resource_type, resource_id, scope, derivation }` + `Derivation` enum. LEFT JOIN roles для `role_name`. Authz self-OR-account-admin (`requireAccountViewAuthority`; для group home-account через `groups.account_id`). |
| AddTargetResources | AddTargetResourcesRequest | operation.Operation | **async** | **epic-100 α** — добавить concrete refs в `target.resources[]` существующего binding'а. Idempotent (`ON CONFLICT DO NOTHING`); role-coverage re-check (D-13); add к `all_in_scope`-binding → `Operation.error` FAILED_PRECONDITION. exempt-perm (handler `requireGrantAuthority`). REST `POST …/{id}:addTargetResources`. |
| RemoveTargetResources | RemoveTargetResourcesRequest | operation.Operation | **async** | **epic-100 α** — убрать refs из `target.resources[]`. Idempotent (DELETE no-op); **last-element guard** (D-10): снятие последнего → `Operation.error` FAILED_PRECONDITION «use Delete to revoke» (НЕ авто-`all_in_scope`, НЕ пустой target). Сериализация concurrent через `CountTargetsForUpdate` (`SELECT … FOR UPDATE` на parent). REST `POST …/{id}:removeTargetResources`. |
| ReplaceTargetSelector | ReplaceTargetSelectorRequest | operation.Operation | **async** | **epic-100 γ (D2/D11/γ-18/γ-19)** — атомарная **полная замена** selector'а bySelector-binding'а (НЕ merge). Только `selector` mutable; subject/role/scope immutable (смена ветки oneof = Delete+Create). **CAS на `resource_version` = `xmin::text`** access_bindings-row (НЕТ version-колонки; OCC через системный xmin, ban #10): `UPDATE … SET status=status WHERE id AND status='ACTIVE' AND xmin::text=$rv` — no-op SET бампит xmin, конкурентный replace с тем же rv → 0 rows → `Operation.error` FAILED_PRECONDITION «access binding was modified concurrently, retry» (γ-19). Гейты (Operation.error FAILED_PRECONDITION): non-selector binding (D2); role-coverage новых `selector.types` (α D-13). После CAS+selector-UPSERT (одна writer-tx + subject_change outbox) → `reconciler.ReconcileBinding` пересчитывает membership (выпавшие → eager-revoke tuple, новые matched → emit). `resource_version` клиент читает из `Get` (репо `GetWithVersion`). exempt-perm (handler `requireGrantAuthority`). REST `POST …/{id}:replaceTargetSelector`. |
| ListGrantableResources | ListGrantableResourcesRequest | ListGrantableResourcesResponse | sync | **epic-100 α** — объекты типа `object_type` под scope для object-picker'а. `GrantableResource{type,id,name}`. **iam-owned типы** (`iam.project`/`account`/…) — реальные строки same-DB; **не-iam** (`compute.*`/`vpc.*`) → **пустой list** (нет mirror, нет ребра iam→owner — D-14; UI резолвит client-side). Authz `requireGrantAuthority` на scope (scope-полиморфный extractor `scope_type`/`scope_id`). НЕ строгий read==accept parity (containment не энфорсится в α). REST `GET …:listGrantableResources`. |
| ListAssignableRoles | ListAssignableRolesRequest | ListAssignableRolesResponse | sync | **sub-phase 1.5** — роли, ВАЛИДНЫЕ для привязки на `(resource_type, resource_id)`; каждая с серверно-вычисленным `scope_group` (SYSTEM/ACCOUNT/PROJECT). `AssignableRole{ role_id, name, description, is_system, scope_group, created_at }` (БЕЗ permissions — lean picker, Q#2). Authz `requireGrantAuthority` (как `ListByResource`/Create на ресурсе; scope-полиморфный extractor). Фильтр — единый предикат `domain.IsRoleAssignable` (D-2), SQL-mirror в `Reader.ListAssignable`, keyset `(created_at,id)`. resource_type ∈ {account,project,cluster}; malformed→InvalidArgument (sync, first stmt — **use-case контракт**), missing→NotFound. **E2e через gateway**: malformed `resource_id` → **403 PERMISSION_DENIED** (authz-интерцептор fail-closed pre-empt'ит формат-валидацию на malformed scope-объекте — defense-in-depth); строгий 400 держится на use-case/direct-gRPC уровне (newman принимает 400\|403, как `Get-malformed` 400\|404). |

## REST mapping

| HTTP | Method |
|---|---|
| `POST /iam/v1/accessBindings` | Create |
| `GET /iam/v1/accessBindings/{id}` | Get |
| `DELETE /iam/v1/accessBindings/{id}` | Delete |
| `GET /iam/v1/accessBindings:listByScope` | **ListByScope** (ex-`ListByResource`; старый путь СНЯТ → 403 catalog-miss) |
| `GET /iam/v1/accessBindings:listBySubject` | ListBySubject |
| `GET /iam/v1/accessBindings/{access_binding_id}/operations` | ListOperations |
| `GET /iam/v1/accessBindings:listSubjectPrivileges` | ListSubjectPrivileges |
| `GET /iam/v1/accessBindings:listAssignableRoles` | ListAssignableRoles |
| `POST /iam/v1/accessBindings/{id}:addTargetResources` | AddTargetResources |
| `POST /iam/v1/accessBindings/{id}:removeTargetResources` | RemoveTargetResources |
| `POST /iam/v1/accessBindings/{id}:replaceTargetSelector` | ReplaceTargetSelector |
| `GET /iam/v1/accessBindings:listGrantableResources` | ListGrantableResources |

## Notes

> [!warning] `ListByResource` → `ListByScope`: старое wire-имя СНЯТО, роут не отвечает
> REST — **GET** `/iam/v1/accessBindings:listByScope`. Legacy `:listByResource` не
> мапится в gRPC-метод: fqn вырождается в путь (`//iam/v1/accessBindings:listByResource`),
> записи в permission-каталоге нет → **403 catalog-miss** (fail-closed, `security.md` §4).
> Залочено кейсом `IAM-ACB-F50-ROUTES-REMOVED`. Записи ниже про `ListByResource` —
> история; действующий метод — `ListByScope`.
>
> **Гоча (стоила отладки, 2026-07-16):** 403 приходит **валидным JSON'ом**
> (`google.rpc.Status` + details). Клиент, делающий `json.load(resp).get('accessBindings', [])`,
> получает **пустой список**, а не исключение — отказ исчезает бесследно и выглядит как
> «binding'ов нет». Так `tests/authz-fixtures/setup.sh` ломался молча: «очистка»
> stale-binding'ов не удаляла НИЧЕГО и рапортовала успех (мусор копился и ронял кейсы,
> ждущие чистое состояние), а проба готовности bootstrap cluster-admin получала 403
> независимо от готовности и выжигала 180с на каждом прогоне. **Проверяй HTTP-код, а не
> только парсинг тела.** См. [[../packages/kacho-ci-runners]].

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
- **ListAssignableRoles + Create scope-enforcement (sub-phase 1.5)** — НОВЫЙ public sync RPC (форма выше) + **`AccessBinding.Create` стал scope-авторитетным** (D-2): был пермиссивен по role-vs-resource scope (только FK existence), теперь энфорсит единый предикат `domain.IsRoleAssignable` (см. [[../resources/iam-role]] §isRoleAssignable). Mis-scoped роль → **`Operation.error.code = FAILED_PRECONDITION`** «role <id> is not assignable on <type>:<id>» (async-контракт сохранён, ban #9 / Q#3; проверка в `doCreate` ДО INSERT, в той же writer-tx; binding не создаётся). list⇔create parity: набор `ListAssignableRoles` == набор, который принимает Create. **Forward-only (D-11):** гейтит ТОЛЬКО новые Create — pre-1.5 mis-scoped bindings НЕ трогаются (нет migration-revoke / read-hide; `ListByResource`/`ListSubjectPrivileges` показывают как раньше; `Delete` отзывает беспрепятственно). Predicate детерминирован per role-row+resource (нет TOCTOU; concurrent integration-тест 1.5-12b подтверждает). impl: `roleCols` расширен на `cluster_id`/`project_id` (scope read). by-design: `docs/architecture/assignable-roles-scope-enforcement.md`. См. [[sub-phase-1.5-assignable-roles]].

- **Resource-scoped AccessBinding (epic-100 α, proto#65 / iam#165 / gateway#88)** — `AccessBinding.target` oneof (`AllInScope` | `TargetResourceRefList` | `ResourceSelector`-forward-γ) + `CreateAccessBindingRequest.target`; Role → чистый verb-bundle (`resourceName` уходит из роли в target). Create получил **третий** независимый детерминированный гейт — **role-coverage** (D-13, `domain.RoleCoversType`: `target.type ⊆ типов в role.permissions`; mis → `Operation.error` FAILED_PRECONDITION «role <id> does not grant any verb on <type>») — ортогонален 1.5 IsRoleAssignable (scope-tier). FGA per-object tuple: источник `resourceName` = `binding.target`, НЕ `role.permissions`; ref прошедший D-13 но давший 0 tuples → INTERNAL fail-closed (нет target-без-tuple). target unset → backfill `all_in_scope` (D-8, read-time). `target.id` opaque soft-ref без existence/containment (НЕТ ребра iam→compute/vpc — цикл; containment → γ). +3 RPC (выше). by-design: `kacho-iam/docs/architecture/resource-scoped-access-binding-alpha.md`. См. [[../KAC/epic-100-resource-scoped-access-binding]].

- **UI consumer (kacho-ui, ui#95)** — grant-форма (`AccessBindingCreateForm`)
  кладёт `target` в Create-body: дефолт `{"target":{"allInScope":{}}}` (α-20
  back-compat), режим resources → `{"target":{"resources":{"resources":[{type,id}]}}}`.
  `allInScope` — **пустой объект `{}`** (message-sentinel), НЕ bool. Object-picker
  зовёт `…:listGrantableResources?scopeType=&scopeId=&objectType=` (camelCase
  proto-полей); для iam-типов рисует dropdown из ответа, для non-iam (пустой list,
  D-14) — ручной ввод id (tags-input). Display устойчив к legacy (parseTarget:
  отсутствие target → all_in_scope). Detail-страница resources-binding'а — панель
  add/remove через `:addTargetResources`/`:removeTargetResources`.

- **subjects[] + ExpandAccess + ListByRole (RBAC rules-model 2026 sub-phase E; proto rbac-rules-e-proto / iam rbac-rules-e-iam / gateway rbac-rules-e-gateway)** — три добавления к `AccessBindingService`:
  - **`AccessBinding.subjects=19` (`repeated Subject{type,id}`, 1..32, R-5)** — multi-subject binding. Одна `access_bindings`-строка несёт N субъектов в child-таблице `access_binding_subjects (binding_id FK CASCADE, subject_type, subject_id, ordinal) UNIQUE` (migration **0028**, backfill 1 строка/legacy-binding). **Per-subject independence (E-30):** Create эмитит НЕЗАВИСИМЫЙ tuple-set на каждого субъекта (`buildBindingTuples` в цикле по subjects; FGA `User` различается: `user:` / `group:…#member` / `service_account:`); emitted-ledger #178 различает субъекта по `fga_user` → per-subject revoke удаляет только его tuple'ы. subject_change + audit эмитятся per-subject; hierarchy parent-pointer subject-независим (dedupe).
  - **Нормализация (E-34 двусторонняя проекция, `domain.NormalizeSubjects`):** `subjects[]` каноничен; legacy single `subject_type`/`subject_id` = `subjects[0]`. Конфликт single≠subjects[0] → sync `INVALID_ARGUMENT`. Пусто/`>32` → `INVALID_ARGUMENT "Illegal argument subjects (must be 1..32)"`. На чтении Get/List/ListByResource/ListByAccount/**ListByRole** заполняют ОБА: `subjects[]` (из child-table, `ListSubjectsForBindings` batch) + legacy single (= subjects[0]); пустой child ⇒ fallback legacy single как один элемент (`toPb domainSubjectsToProto`). Окно до Phase 6.
  - **`ExpandAccess(ExpandAccessRequest{object_type,object_id,relation,max_results}) → ExpandAccessResponse{principals[],truncated}` (sync read, **per-object grant-authority**, E-31/R-6)** — разворот в concrete principals (USER/SERVICE_ACCOUNT). **Механизм: OpenFGA `POST /list-users` (graph-traversing), НЕ плоский Read** (fix `rbac-rules-e-iam`, поверх 6ca2c71). Плоский filtered-Read `ListSubjects` видел только литеральные tuple'ы на `<object>#<relation>` и НЕ обходил граф → rules-model гранты через индирекцию (computed-userset каскад `admin⇒editor⇒viewer`, `scope_grant`-pull-up `g_*_<type>`, group#member) резолвились в ПУСТО (`RBACSUBJ-EXPAND-GROUP-OK` red). `OpenFGAHTTPClient.ListUsers(objectType,objectID,relation,[user,service_account])` нативно обходит ВЕСЬ граф (группы разворачивает сервер, server-side limits — нет client cycle-guard/depth/paging); dedup (E-30), truncation-flag, fail-closed (FGA-ошибка → фикс. INTERNAL). OpenFGA v1.8.4: `user_filters` ровно 1 элемент → 1 запрос на тип, merge. (`ListSubjects` сохранён для `AuthorizeService.ListSubjects` — там нужны direct-subjects.) **Authz (security review E, В3, fix `rbac-rules-e-iam`):** read==enforce — caller ОБЯЗАН иметь grant-authority/admin на target object/scope (тот же `requireGrantAuthority`, что `ListByResource`/`ListByRole`) ДО разворота; чужой объект → `PERMISSION_DENIED` (НЕ только anti-anon floor — иначе любой authenticated раскрывал authz-топологию/членство на ЛЮБОМ объекте). **relation closed-set (В2):** валидируется против `authzmap.IsExpandableRelation` (per-verb `v_*` + tier viewer/editor/admin + member); unknown → `INVALID_ARGUMENT` (нет probe произвольных FGA-relation строк). REST `GET /iam/v1/accessBindings:expandAccess`; perm `iam.access_bindings_by_resources.expandAccess`.
  - **`ListByRole(ListAccessBindingsByRoleRequest{role_id,page,include_revoked}) → ListAccessBindingsResponse` (sync read, E-33)** — audit «кто несёт роль R». repo keyset `(created_at,id) ASC`; authz: authenticated floor + per-row scope-filter через `requireGrantAuthority`. REST `GET /iam/v1/accessBindings:listByRole`; perm `iam.access_bindings_by_roles.listByRole`.
  - **group-amplification guard (E-32/Q#4)** — admin/editor + GROUP требует `requireGrantAuthority` на scopeRef (Create вызывает его для ЛЮБОГО create → guard by construction). Оба новых RPC — **public** (external endpoint, gateway public mux); НЕ Internal. См. [[../KAC/rbac-rules-model-2026-subphase-E-iam]].

## See also

[[../packages/iam-domain]] [[../resources/iam-access-binding]] [[iam-role-service]] [[../edges/iam-to-openfga-check]] [[../KAC/KAC-105]] [[../KAC/epic-100-resource-scoped-access-binding]] [[../KAC/rbac-rules-model-2026-subphase-E-iam]]

#rpc #kacho-iam #iam
