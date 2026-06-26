---
title: "api-gateway → iam: AuthorizeService.Check (per-RPC)"
aliases:
  - apigw to iam authorize
  - apigw fga check
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-api-gateway
  - cross-service
  - authz
  - fga
---

# api-gateway → iam: AuthorizeService.Check (per-RPC)

**Caller**: `kacho-api-gateway` authz middleware ([[../packages/api-gateway-middleware-authz]]).
**Callee**: `kacho-iam` AuthorizeService.Check ([[../rpc/iam-authorize-service]]) — `kacho-iam:9090`.
**Protocol**: gRPC. Cluster-internal — НЕ via api.kacho.cloud (avoids token-loop).
**Sync/Async**: sync per-request.
**Status**: **Phase 3 planned**.

## Flow per-request (Phase 3)

```
1. Client → POST /vpc/v1/networks (api.kacho.cloud)
2. api-gateway TLS-listener:
   - DPoP / JWT verify ([[../packages/api-gateway-middleware-dpop]])
   - Extract subject (user:usr_xxx or service_account:sva_xxx)
   - Extract verb (proto descriptor → "vpc.networks.create")
3. authz middleware ([[../packages/api-gateway-middleware-authz]]):
   - Resolve target object — for Create, project_id from request body
   - Build (subject, relation=verb, object=project:prj_yyy)
4. gRPC call → iam.AuthorizeService.Check
   - Per-RPC: ≤20ms p95 SLO (Phase 3 DoD)
   - Cached 5s (verify-then-cache; LISTEN-invalidate on FGA tuple change)
5. allowed=true → forward request to backend (vpc/compute/lb)
   allowed=false → respond 403 PermissionDenied + audit log
```

## Cache key

`hash(subject || relation || object || condition_params_hash || jwt_aal)` → 5s TTL.

## Cache invalidation

- LISTEN на `kacho_iam_fga_outbox` (PostgreSQL pubsub) → on any tuple change, gateway clears cache subset.
- Tag-based: scan cache keys with prefix `subject=user:usr_xxx` → invalidate (selective; не nuclear).
- TTL fallback: 5s ceiling.

## Fail-closed / fail-open policy

| Operation | iam.Check unavailable | Action |
|---|---|---|
| Mutation (POST/PUT/PATCH/DELETE) | fail-closed | 503 Unavailable + retry-after |
| Read (GET/List) | fail-open behind flag `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN_READS=true` (default false) | proceed without check (audit-logged) |
| List with FGA filtering | fail-closed (can't filter without lookup) | 503 |

## Error handling

| Check result | Gateway action |
|---|---|
| `allowed=true` | forward |
| `allowed=false` | 403 + audit `iam.authz.denied` |
| `Unavailable` | fail-closed for mutations (see above) |
| `Internal` | log + propagate 500 + alert |

## Notes

- Phase 1-2: NO per-RPC Check (auth-interceptor only verifies DPoP/JWT). Phase 3 adds Check.
- Phase 4 — ListObjects integration ([[vpc-to-iam-listobjects]] / [[compute-to-iam-listobjects]]) — backend itself queries ListObjects для List handlers; api-gateway не пред-фильтрует.
- API-gateway side cache shared across requests on same node (sync.Map). Cold cache p95 +5ms.

## History

- Bug A (listByResource scope, 2026-06-14, api-gateway PR #74 / proto PR #55) — для
  **scope-polymorphic** RPC api-gateway теперь берёт FGA `object_type` из request-поля,
  а не из статического `scope_extractor.object_type`. Catalog получил поле
  `object_type_from_request_field`; `AccessBindingService/ListByResource` помечен
  `object_type_from_request_field=resource_type` (→ project|account|cluster). Middleware
  `decide()` извлекает это поле (proto-reflect для gRPC, query/JSON-body для REST) и
  подставляет как FGA object type; статический `object_type` — fallback. До фикса
  account/cluster-scoped listByResource проверял `project:<id>` → 403. Fixed-scope RPC
  не затронуты. Реализация: [[../packages/api-gateway-middleware-authz]].
- Bug C — RequiredRelation drop (2026-06-16, api-gateway PR #77) — адаптер
  `clients.AuthzChecker.Check` (мост `middleware.AuthzCheckInput` →
  `clients.AuthorizeCheckInput`, `iam_authorize_checker.go`) копировал 6 полей, но
  **ронял `RequiredRelation`** (написан в KAC-127 до появления поля; KAC-198 добавил его
  во все хопы, кроме этого промежуточного). Эффект: catalog `required_relation` не доходил
  до IAM → `AuthorizeService.Check` падал в verb-fallback (`resolveActionToRelation`).
  **Priv-esc**: admin-RPC с verb `list`/`get` (`required_relation=system_admin`, напр.
  `InternalAddressPoolService` reads) деривились в `viewer` → `cluster.viewer=user:*` →
  любой аутентифицированный проходил. Не-CRUD verb'ы (`issue`/`grant`/`bind`/…) → `""` →
  fail-closed deny («action does not resolve to a known relation»; 403'ило `SAKeyService.Issue`).
  Не ловилось тестами (middleware-тесты мокают `AuthorizeChecker`, не реальный адаптер).
  Fix: проброс `in.RequiredRelation` + unit-тест pass-through. Это корневой фикс —
  делает verb-fallback IAM избыточным для catalog-RPC и единственный способ гейтить
  system_admin-verb'ы. Сопутствующие band-aid'ы (kacho-iam PR #120: `resolveActionToRelation`
  `issue`/`revoke`→editor; верб-fold M2) теперь defensive-only. Реализация:
  [[../packages/api-gateway-middleware-authz]].
- SEC-E ([[../KAC/SEC-E-gateway-mtls]], 2026-06-11) — backend-dial этого ребра переключён
  с insecure на **mTLS client-cert** идентичности «api-gateway» под
  `KACHO_API_GATEWAY_MTLS_IAM_ENABLE` (per-edge, тот же флаг, что iam-subject + iam-backend;
  one module identity, OQ-SEC-E-3). `enable=false` (default) = insecure (dev backward-compat).
  Check-логика и cache не изменены — mTLS оборачивает только транспорт, principal идёт поверх
  (epic invariant I2). Mismatch (client mTLS vs insecure server) → `Unavailable` (fail-closed).
  Реализация: [[../packages/api-gateway-backend-dial-mtls]].

- Design-B verb-bearing-complete (2026-06-25, api-gateway PR #99 / proto PR #88) — встроенная
  копия каталога (`internal/middleware/embed/permission_catalog.json`, 288 entries) ресинкнута из
  Design-B proto-gen: **148** object-self RPC флипнуты `required_relation` tier→`v_*`
  (`viewer`×70 / `editor`×75 / `admin`×3 → `v_get`×24 / `v_list`×47 / `v_update`×56 / `v_delete`×21).
  Gateway теперь форвардит `v_get`/`v_list`/`v_update`/`v_delete` в `AuthorizeService.Check` для
  get/list/update/delete-self; enforcement резолвит на verb, а не на tier (D-6 see-in-selector-
  without-content). **create-child остаётся `editor`** на parent project/account (F-7); **Internal.***
  admin-RPC остаются `system_admin` (ban #6 — ноль downgrade); exempt-List'ы и scope_extractor/acr
  не тронуты. Authz-интерсептор (`decide()`/`AuthzChecker`) **не менялся** — он уже verbatim-форвардит
  `required_relation`. Conformance-guard: `TestPermissionCatalog_VBC22_VerbBearingFlip` +
  `…AccessBindingUpdate_VerbBearing` (editor→v_update). SUPERSEDES Design-A union (#241).
  Реализация: [[../packages/api-gateway-middleware-authz]].

- BUG-2 hide-existence on read-deny (2026-06-25, api-gateway PR #100 / kacho-iam newman PR #248) —
  для **verb-bearing IAM read** (`account/project/user/service_account/group` `Get`,
  `required_relation=v_get` + concrete scope) gateway-Check бьёт ДО iam: deny → раньше
  **403 PERMISSION_DENIED** с verbose `deny_reasons`, перекрывая hide-existence-контракт
  владельца (iam `read_authz.go` отдаёт `NotFound`, «never PermissionDenied, no enumeration
  leak»). `RoleService/Get` был корректен только потому что `<exempt>` (без gateway-Check →
  доходит до iam → 404). Fix: deny на hide-existence read RPC → **NotFound (gRPC 5 / HTTP 404)
  без deny_reasons** (новый `outcomeNotFound`; три authz-Check-deny сайта идут через
  `denyDecision()`). Резолв: explicit catalog-флаг `HideExistence` ИЛИ эвристика «`/Get` +
  `v_get` + concrete scope». Enforcement не ослаблен (deny блокирует, handler не достигается);
  nonexistent == existing-denied → одинаковый 404 (no enumeration leak); мутации/List/
  catalog-miss/override-deny остаются 403/правильный код. **Scope:** эвристика покрывает 20
  verb-bearing single-resource `Get` на одном gateway-пути — iam(6) + vpc(7) + compute(4) +
  loadbalancer(3), не только iam (единая security-политика hide-existence-on-read). **Refinements:**
  404 только для single-resource `Get` (`…/{id}`, без query) — denied **List** остаётся **403**
  (нет конкретного объекта), anonymous → **401** (authN, не authz-hide); read-after-write на
  свежем `iam_access_binding` → transient 404 (`retry_on=(403,404)`); `get-after-revoke` на
  удалённом ресурсе → tolerant `oneOf([404,403])`. Merged + fe3455-live + TEMP-PIN ревёрнут
  (gw#101/iam#250), BUG-2 ветки удалены — см. [[../KAC/rbac-2026-bug2-hide-existence-read-deny]].
  Реализация: [[../packages/api-gateway-middleware-authz]].

- DIVERGENCE-A — новый public-route `UserService.Update` (2026-06-26, api-gateway PR #102 /
  proto PR #89 / iam PR #249) — `UserService` получил публичный label-write `Update`
  (`PATCH /iam/v1/users/{user_id}`, async→Operation). Зарегистрирован в public allowlist +
  gRPC-director + public REST mux (наравне с `UpdateRole`/`UpdateGroup`/`UpdateServiceAccount`;
  НЕ Internal.* — `InternalUserService.UpsertFromIdentity` остаётся на :9091). `required_relation
  = v_update` на `iam_user:<id>` (verb-bearing, форвардится в `AuthorizeService.Check`); каталог
  расширен новой записью. Прочие iam Create/Update (SA/Group/Role/AccessBinding) с `labels`-полями
  идут через существующий public-mux (новых регистраций нет). Контекст — [[../KAC/DIVERGENCE-A-unify-iam-label-scope]].

- Unify account-scoped List call-gate (2026-06-27, proto#90 / kacho-iam#269 / api-gateway#103) —
  `ProjectService.List` и `GroupService.List` приведены к `<exempt>` паритету с
  `User/ServiceAccount/Role List`: сняты `required_relation=v_list` + `scope_extractor={account,account_id}`
  + `required_acr_min=2`; embedded-catalog ресинкнут (ровно 2 записи из 289). Gateway больше НЕ Check-ает
  `account:<id>#v_list` для этих List — авторитетный gate — in-handler фильтр `viewer ∪ v_list`
  (200+filtered, никогда 403; anon→401; FGA-err→Unavailable). Чинит non-member List 403→200+empty +
  by-label `v_list`-only see-in-selector discovery. Прод-код iam не менялся (фильтр project уже был,
  group доделан #261). Live fe3455 gw `main-cbaa8bc1`. Реализация:
  [[../packages/api-gateway-middleware-authz]], [[../rpc/iam-project-service]], [[../rpc/iam-group-service]].

## See also

[[iam-to-openfga-check]] [[iam-to-opa]] [[vpc-to-iam-listobjects]] [[compute-to-iam-listobjects]] [[../rpc/iam-authorize-service]] [[../packages/api-gateway-middleware-authz]] [[../packages/api-gateway-middleware-dpop]] [[../packages/api-gateway-backend-dial-mtls]] [[../packages/corelib-authz-listobjects]] [[../KAC/KAC-127]] [[../KAC/SEC-E-gateway-mtls]]

#edge #kacho-api-gateway #cross-service #authz #fga
