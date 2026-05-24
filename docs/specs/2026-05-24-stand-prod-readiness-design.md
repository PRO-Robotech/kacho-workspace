# Stand prod-readiness — закрыть 5 backend gaps после KAC-171/175

**KAC**: [KAC-178](https://prorobotech.youtrack.cloud/issue/KAC-178)
**Дата**: 2026-05-24
**Stand state at writing**: live kind cluster `kacho`, UI deployed `kacho-ui:KAC-171d`, api-gateway `KAC-zones2`, iam `KAC-zones3`, vpc/compute/nlb на `docker.io/prorobotech/*` master tags.

## Контекст

После KAC-171 (UI NLB integration + DashboardPage fix) и KAC-175 (port-portable Kratos/Hydra) полностью **починен UI**. Login flow работает на любом порту, cascader рендерится, 4 tiles (VPC/Compute/NLB/IAM) видны, navigation корректна, 58 system roles в access-bindings dropdown.

Однако downstream **backend endpoints** падают на **5 разных уровнях AuthZ / catalog / proto**. Этот документ — план для каждого с конкретными action items.

---

## §1. kacho-vpc#112 — list-filter PermissionDenied → Unavailable (code 14) + FGA relation mismatch

### Симптом
```
GET /vpc/v1/networks?project_id=prjXXX
→ 503 {"code":14, "message":"list-filter unavailable: authz: check service unavailable: rpc error: code = PermissionDenied desc = permission denied"}
```

User имеет admin tuple в openfga для project, но VPC list-filter returns PermissionDenied → wrapped как Unavailable.

### Root cause
1. **Code wrapping**: `kacho-vpc/internal/apps/kacho/services/listauthz/adapter.go` оборачивает `PermissionDenied` (code 7) в `Unavailable` (code 14). Semantically wrong — должен оставаться PermissionDenied.
2. **FGA relation mismatch**: VPC list-filter отправляет `iam.ListObjects(action="vpc.networks.list")`. IAM проверяет permission catalog → находит `required_relation: "viewer"`. Но в openfga schema relation `viewer@project` нет path от admin role.

### Action items
- **kacho-vpc** `internal/apps/kacho/services/listauthz/adapter.go`: replace `Unavailable(err)` wrap → `if codes.PermissionDenied → return as-is`.
- **kacho-iam openfga model** (`config/openfga_model.fga` или embedded): добавить `define viewer: [user] or admin` на `type project` (admin grants viewer transitively).
- **alternatively** — patch permission catalog `required_relation: "admin"` для list actions (но это меняет semantics).

### Live workaround на стенде
`vpc-config` ConfigMap patched `list-filter.enabled=false` — list работает без FGA. Не persist через Helm.

### Persistence
- Add `KACHO_VPC_LIST_FILTER_ENABLED` override в `kacho-deploy/helm/umbrella/charts/vpc/templates/deployment.yaml` env block + `values.dev.yaml` (default false для dev).

---

## §2. kacho-vpc#114 — Operation.created_by=anonymous (W1.4 principal propagation)

### Симптом
```json
{
  "id": "enp1szdnhmkkbqye2mdb",
  "description": "Create network ...",
  "createdBy": "anonymous",
  "principalType": "",
  "principalId": ""
}
```

api-gateway корректно injectит `x-kacho-principal-*` headers (log: `"Principal injected (Kratos)"`), но VPC server видит anonymous.

### Root cause
Per W1.4 DRAFT acceptance (`docs/specs/sub-phase-W1.4-principal-propagation-acceptance.md`):
- `cmd/vpc/main.go` НЕ mountит `corelib/grpcsrv.UnaryPrincipalExtract` interceptor.
- `operations.PrincipalFromContext(ctx)` возвращает `SystemPrincipal{system, bootstrap}`.
- Operation handler пишет `created_by = "anonymous"` как fallback.

### Action items
1. **kacho-corelib** — new package `auth/propagate.go`:
   ```go
   func PropagateOutgoing(ctx context.Context) context.Context // wrap outgoing gRPC MD
   ```
   Extract из существующих `kacho-vpc/internal/clients/iam_client.go::withPrincipalMD` + `kacho-compute/internal/clients/iam_client.go::withPrincipalMD` (byte-identical).
2. **kacho-vpc** `cmd/vpc/main.go`:
   ```go
   serverOpts := append(serverOpts, grpc.ChainUnaryInterceptor(
       grpcsrv.UnaryPrincipalExtract(...), // <- add
       ...existing
   ))
   ```
3. **kacho-vpc** `internal/apps/kacho/check/check_client.go::IAMCheckClient.Check` — wrap outgoing ctx:
   ```go
   ctx = auth.PropagateOutgoing(ctx)
   out, err := c.cli.Check(ctx, ...)
   ```
4. **kacho-compute** symmetric: cmd/compute/main.go + internal/check/check_client.go.

### Verification
e2e тест из W1.4 acceptance §3 — login → Create Network → verify Operation.principal_id == user_id.

---

## §3. kacho-compute#29 — catalog gap + FGA cluster wildcard model

### Симптом
```
GET /compute/v1/zones?pageSize=200 → 403 catalog: no entry for method
GET /compute/v1/instances?... → 403 authorization service unavailable
```

### Root cause
1. **api-gateway catalog** не имел entries для `compute.v1.ZoneService` / `RegionService`. Live patched в [PR #36](https://github.com/PRO-Robotech/kacho-api-gateway/pull/36) — closed.
2. **FGA model gap**: catalog entry для Zone/Region scope_extractor использует `object_type: cluster, from_request_field: '*'` → AuthZ subject becomes `cluster:*` (literal asterisk). FGA schema не имеет path для wildcard на cluster type.
3. **Compute** другие RPC падают с `authorization service unavailable` — отдельная catalog gap (нужны все compute service entries populated).

### Action items
1. **kacho-iam openfga model** — добавить tuple bootstrap для всех authenticated users:
   ```
   user:* viewer cluster:cluster_kacho_root
   ```
   ИЛИ schema rule: `define cluster_viewer: [user, user:*] or system_viewer`.
2. **kacho-api-gateway** permission_catalog.json — populate **все** compute service entries (current Phase 1 empty):
   ```json
   {"fqn":"...InstanceService/List","permission":"compute.instances.list","required_relation":"viewer","scope_extractor":{"object_type":"project","from_request_field":"project_id"}}
   ```
   (Phase 3 catalog rollout per kacho-iam acceptance §6.9.3 — generated by proto-pipeline.)
3. **kacho-compute** — `KACHO_COMPUTE_LIST_FILTER_ENABLED=false` env override в `values.dev.yaml` пока catalog не populated. Live applied на стенде.

---

## §4. kacho-api-gateway#33 — NLB proto-annotations + ListenerService catalog

### Симптом
```
GET /nlb/v1/loadBalancers → 403 catalog: no entry  (fqn="//nlb/v1/loadBalancers" — HTTP path fallback)
GET /nlb/v1/listeners → 403 catalog: no entry (ListenerService entirely missing)
GET /nlb/v1/targetGroups → 200 OK  (works)
```

### Root cause
1. **proto-annotation broken**: `NetworkLoadBalancerService.List` РПЦ в kacho-proto имеет `google.api.http` annotation НЕ соответствующую `/nlb/v1/loadBalancers` path → grpc-gateway не может resolve REST→gRPC → api-gateway authz получает HTTP path `"//nlb/v1/loadBalancers"` как fqn → catalog miss → deny.
2. **ListenerService полностью отсутствует** в catalog (0 entries в permission_catalog.json).

### Action items
1. **kacho-proto** `proto/kacho/cloud/loadbalancer/v1/network_load_balancer_service.proto` — verify annotation:
   ```proto
   rpc List(ListNetworkLoadBalancersRequest) returns (ListNetworkLoadBalancersResponse) {
     option (google.api.http) = { get: "/nlb/v1/loadBalancers" };
   }
   ```
   Если annotation на `/loadbalancer/v1/...` (legacy) — fix на `/nlb/v1/...`.
   Regen `kacho-proto/gen/go/...`.
2. **kacho-api-gateway permission_catalog.json** — добавить все ListenerService entries (Create/Get/List/Update/Delete/Move/ListOperations). Берём pattern от TargetGroupService.
3. Rebuild kacho-api-gateway + kacho-nlb с regen'нутыми proto stubs.

---

## §5. NEW — Catalog source-of-truth clarification

### Confusion
- `kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json` — **существует**, но `LoadPermissionRegistry` вызывается ТОЛЬКО из integration tests. **НЕ читается в runtime**.
- `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` — **runtime catalog source**. Error `"catalog: no entry for method"` идёт от api-gateway middleware.

### Action items
1. **Documentation** — добавить раздел в `docs/architecture/` workspace:
   - Catalog source-of-truth = `kacho-api-gateway/internal/middleware/embed/permission_catalog.json`.
   - Sync rule: `cp kacho-proto/gen/permission_catalog.json kacho-api-gateway/internal/middleware/embed/`. Makefile target в kacho-api-gateway.
   - `kacho-iam/seed/embedded/permission_catalog.json` — **mirror** для integration test bootstrap, **не runtime**. Либо удалить (если не используется), либо ясно пометить «not for runtime» в file header.
2. **kacho-proto/gen** — confirm `permission_catalog.json` is single source-of-truth, generated from proto annotations. Все consumers (api-gateway, iam-test, kacho-iam-seed-mirror) импортируют отсюда.
3. **Makefile rule**: при изменении proto annotations — auto-sync во все consumers (sync-permission-catalog target в каждом).

---

## §6. Definition of Done

- [ ] §1 — VPC list работает с list-filter включённым (после FGA model fix или relation override).
- [ ] §2 — Operation.created_by показывает реального subject_id user'а после login.
- [ ] §3 — Compute list endpoints возвращают данные; Zone/Region public access работает.
- [ ] §4 — `/nlb/v1/loadBalancers` и `/nlb/v1/listeners` возвращают 200 (после proto regen + catalog populate).
- [ ] §5 — Catalog source-of-truth задокументирован, sync-pipeline установлен.

## §7. Roadmap

| Этап | Repos | Effort |
|---|---|---|
| §5 (docs) | kacho-workspace | 1 day |
| §4 (proto + catalog) | kacho-proto, kacho-api-gateway, kacho-nlb | 2 days |
| §3 (catalog populate + FGA model) | kacho-iam, kacho-api-gateway | 3 days |
| §2 (W1.4 principal) | kacho-corelib, kacho-vpc, kacho-compute | 3 days |
| §1 (list-filter + relation) | kacho-vpc, kacho-compute, kacho-iam-model | 2 days |
| **Total** | 6 repos | **~11 days** |

---

## §8. Live workarounds на стенде (need removal после full fix)

| Patch | Location | Reason |
|---|---|---|
| `list-filter.enabled=false` | `vpc-config` ConfigMap | §1 — closes for now |
| `KACHO_COMPUTE_LIST_FILTER_ENABLED=false` | `compute` deploy env | §3 |
| `KACHO_COMPUTE_AUTHZ_FAIL_OPEN=true` | `compute` deploy env | §3 (partial — не помог) |
| `kacho-iam:KAC-zones3` image | local kind only | §3 partial (catalog patch не embed'ится) |
| `kacho-api-gateway:KAC-zones2` image | local kind only | §3/§4 catalog entries |

Все patches **temporary** — должны быть removed после real fixes per §1-§5.
