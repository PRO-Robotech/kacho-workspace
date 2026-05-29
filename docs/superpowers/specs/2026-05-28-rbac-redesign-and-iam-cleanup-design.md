# RBAC redesign + IAM cleanup (SCIM / SAML / Break-Glass removal)

**Date**: 2026-05-28
**Status**: design — approved by user (carte blanche)
**Scope**: kacho-proto, kacho-iam, kacho-vpc, kacho-compute, kacho-api-gateway, kacho-deploy, kacho-workspace
**Tracking**: YouTrack epic — TBD (`KAC-N`); workspace tracking-issue per wave
**Supersedes**: portions of `2026-05-19-iam-prod-ready-next-gen-design.md` (SCIM/SAML/BG slices); reuses `2026-05-24-kacho-iam-production-cleanup-refactor-design.md` infrastructure

## 1. Problem statement

Two coupled changes:

1. **Remove dead surface** — SCIM (System for Cross-domain Identity Management), SAML (Boxyhq Jackson SP), Break-Glass (emergency_admin / cluster_break_glass_grant). All three predate the simplified Account/Project model (KAC-124) and are not needed for current control-plane targets.
2. **Fine-grained RBAC** — promote the permission grammar from `module.resource.verb` (3 segments) to `module.resource.resourceName.verb` (4 segments). Add an explicit `scope` (cluster/account/project) on AccessBinding. **Guarantee list-side filtering** so a subject never sees the existence of resources they have no access to (the Kubernetes RBAC list-namespace antipattern).

Constraint: public API surface (gRPC method signatures, REST paths) MUST NOT break. Additive proto changes are allowed; permission strings are an *internal* normalization step.

## 2. Goals / non-goals

**Goals.**
- Permission grammar: strict 4 segments `module.resource.resourceName.verb`; each segment is `[a-zA-Z0-9_-]+` or `*` (wildcard); leading/trailing/inner whitespace forbidden.
- AccessBinding gets explicit `scope` enum (`CLUSTER` / `ACCOUNT` / `PROJECT`) — validated against `resource_type`/`resource_id` at create time.
- List-RPCs (`List<Resource>` on vpc, compute, iam-own-resources) filter result rows through `IAM.AuthorizeService.ListObjects` so subjects see only what they're authorized for.
- Wildcard semantics preserved: `compute.instance.*.read` (all instances), `*.*.*.*` (superuser), `iam.project.prj-a.*.read` is **invalid** (verb wildcard at position 4 is allowed, others as written).
- SCIM/SAML/Break-Glass code, proto, FGA-relations, migrations, REST endpoints — removed in a single coordinated drop with data migration.
- Migrations carry existing roles.permissions and access_bindings to the new shape.
- Strict TDD per workspace §12: every change ships with RED→GREEN tests (integration + newman where applicable).

**Non-goals.**
- Public proto messages stay backward-compatible (additive only); no method renames.
- No replacement for SCIM/SAML in this epic. Identity federation now flows exclusively through Zitadel OIDC.
- No change to OpenFGA store / model semantics beyond removing `emergency_admin` and `break_glass_window`. Hierarchy `cluster ▶ account ▶ project ▶ <domain resource>` stays.
- No new policy engine, no Casbin/SpiceDB switch. Reuse FGA + existing `ListObjects`/`Check` plumbing.

## 3. High-level design

### 3.1 Permission grammar (canonical, single form)

```
<module>.<resource>.<resourceName>.<verb>
```

- **module** — service domain identifier. Lowercase. Examples: `compute`, `vpc`, `iam`, `lb`, `*`.
- **resource** — resource type within the module (`instance`, `network`, `project`, `serviceAccount`, …). camelCase allowed where the proto uses camelCase. `*` permitted.
- **resourceName** — concrete resource identifier (typically the resource `id`: `inst-abcdef…`, `prj-…`, `acc-…`) or `*` wildcard. **No abbreviations** (3-segment legacy is migrated up).
- **verb** — action. Lowercase. The known verbs come from `authzmap.verbClass`:
  - read-class: `get`, `list`, `view`, `watch`, `describe`, `read`, plus domain reads (`getTargetStates`, `listOperations`).
  - write-class: `create`, `update`, `delete`, `write`, `patch`, `put`, `start`, `stop`, `move`, etc.
  - admin: `admin`, `manage`, `*`.

**Examples (legal):**

| Permission | Meaning |
|---|---|
| `*.*.*.*` | Superuser; binds to FGA `cluster:cluster_kacho_root#system_admin@<subject>`. |
| `compute.instance.*.read` | Read every compute instance within the binding's scope. |
| `compute.instance.inst-abcd1234567890ab.read` | Read one specific instance. |
| `iam.project.prj-prod0000000000ab.update` | Update one specific project. |
| `vpc.network.*.create` | Create networks within scope. `resourceName=*` is the only valid form for `create` (no id exists yet). |
| `iam.serviceAccount.sva-bot0000000000ab.use` | Use a specific service account (impersonate / mint token). |

**Examples (illegal):**

| Permission | Why illegal |
|---|---|
| `compute.instance.read` | Only 3 segments. Migration script auto-promotes to `compute.instance.*.read`. |
| `*compute*.instance.*.read` | Star can only be a whole segment, not embedded. |
| `compute..*.read` | Empty segment. |
| `Compute.Instance.*.READ` | Module/resource lowercase enforced; verb lowercase enforced. (Validator: case-insensitive at read, normalized at write.) |
| `compute.instance.*.unknownVerb` | Unknown verb. Validator rejects; catalog has the closed verb set. |

The PL/pgSQL `iam_permissions_valid()` function is rewritten to enforce this grammar via regex; the catalog generator pipeline emits 4-segment strings only.

### 3.2 AccessBinding shape

Additive proto change (backward compatible):

```protobuf
message AccessBinding {
  // ... existing fields (id, subject_type, subject_id, role_id,
  //                     resource_type, resource_id, created_at, status,
  //                     condition_id, expires_at, granted_by_user_id,
  //                     revoked_at, revoked_by_user_id, builtin_condition)

  // Explicit scope tier. The binding anchors at this level of the
  // hierarchy (cluster ▶ account ▶ project). Bound concrete-resourceName
  // permissions remain narrower than the scope.
  Scope scope = 15;

  enum Scope {
    SCOPE_UNSPECIFIED = 0;  // legacy backfill state — rejected on new writes
    CLUSTER           = 1;
    ACCOUNT           = 2;
    PROJECT           = 3;
  }
}
```

**Scope validation (CHECK in DB + service-layer):**

| scope     | required resource_type           | required resource_id |
|-----------|----------------------------------|----------------------|
| CLUSTER   | `cluster`                        | `cluster_kacho_root` |
| ACCOUNT   | `account`                        | starts with `acc`    |
| PROJECT   | `project`                        | starts with `prj`    |

**Semantics.** The `scope` controls **which level of the FGA hierarchy the role's wildcard-resourceName permissions anchor on**. Concrete-resourceName permissions emit direct per-object FGA tuples (e.g. `compute_instance:inst-abc#viewer@user:usr-X`); they bypass the scope-level fan-out but still respect the scope as a *validation guard* (binding-create rejects scope=ACCOUNT/acc-A with concrete `compute.instance.inst-XYZ.read` when `inst-XYZ` is provably not under `acc-A`; otherwise fail-soft, since cross-DB lookup is best-effort).

### 3.3 List-filter contract (the K8s antipattern fix)

Every public `List<Resource>` RPC in vpc/compute/iam-own-resources MUST honour this contract:

1. Extract authenticated `subject` from gRPC context (set by api-gateway tenant-interceptor).
2. Compute canonical action `<module>.<resource>.*.read` (or `.list` synonym — see verb-class table).
3. Call `IAM.AuthorizeService.ListObjects(subject, action, resource_type)`. Use the cached corelib `authz.ListObjectsService` adapter for de-duplication and TTL.
4. The response carries either:
   - `wildcard_grant=true` → the subject has unrestricted access in scope; skip filter.
   - `wildcard_grant=false`, `resource_ids=[…]` → filter DB query with `WHERE id = ANY($ids)`.
   - empty list → return empty result. **Do not** return 403/PermissionDenied for List; resource-existence must remain unknowable.
5. Pagination is applied AFTER filtering (`LIMIT/OFFSET` on the filtered set).
6. On ListObjects timeout/unavailable: fail-closed → return `Unavailable` to caller (existing TTL-cache absorbs transient blips).

For `Get<Resource>` / `Update<Resource>` / `Delete<Resource>` RPCs the existing `Check`-on-handler contract is unchanged; per-resource decisions still go through `AuthorizeService.Check`.

`AuthorizeService.ListObjects` proto already returns `resource_ids` and a `wildcard_grant` boolean implicit in "all ids returned" — promote it to an explicit `bool wildcard_grant` field (additive proto change). This makes the wildcard-bypass explicit and avoids a service round-trip ambiguity ("did FGA enumerate every id, or signal 'allowed for all'?").

### 3.4 Inheritance rules (scope cascade)

- `CLUSTER` scope ⇒ binding applies to every Account, Project, and per-domain resource in the cluster.
- `ACCOUNT` scope ⇒ binding applies to every Project under that Account and every per-domain resource ultimately owned by that Account (FGA hierarchy traversal handles this).
- `PROJECT` scope ⇒ binding applies to every per-domain resource owned by that Project (e.g. all Compute/VPC resources tagged with that project_id).
- Per-resourceName binding (the role permission carries a concrete `resourceName`): cascades only via the per-object FGA tuple — it does **not** inherit children. Per-resourceName grants on aggregate resources (`account.acc-A.*.read`) confer view of the account record itself, not its children, unless the binding is also `scope=ACCOUNT`.

These rules are encoded in the existing FGA `fga_model.fga` (`account#viewer from cluster`, `project#viewer from account`, per-domain `viewer from project`). No new FGA syntax is needed; the change is in how AccessBinding writes tuples.

### 3.5 FGA tuple emission (`fga_outbox` emitter)

Reworked logic in `kacho-iam/internal/service/fga_tuple_writer.go` (and the SQL emitter `internal/repo/kacho/pg/fga_outbox/emitter.go`):

For each AccessBinding's effective permission `M.R.N.V`:

| Pattern | FGA tuple emitted |
|---|---|
| `*.*.*.*` + scope=CLUSTER | `cluster:cluster_kacho_root#system_admin@<subject>` |
| `M.R.*.V` + scope=ACCOUNT (acc-X) | `account:acc-X#<tier(V)>@<subject>` (`tier(V)`=`viewer`/`editor`/`admin`) |
| `M.R.*.V` + scope=PROJECT (prj-Y) | `project:prj-Y#<tier(V)>@<subject>` |
| `M.R.*.V` + scope=CLUSTER | `cluster:cluster_kacho_root#<tier(V)>@<subject>` |
| `M.R.N.V` with concrete N | `<fga_type(M,R)>:N#<tier(V)>@<subject>` — single direct tuple. FGA `list-objects` enumerates direct-tuple grants natively, so no extra anchor is needed. |

The fga_type mapping is pre-existing: `compute.instance` → `compute_instance`, `vpc.network` → `vpc_network`, `iam.project` → `project` (the hierarchy type), etc. Table lives in `kacho-iam/internal/authzmap/fga_types.go` (NEW file).

### 3.6 Removal scope (SCIM / SAML / Break-Glass)

Removed in one coordinated drop (single workspace-wide PR-set):

**Proto (`kacho-proto/proto/kacho/cloud/iam/v1/`):**
- DELETE `break_glass_service.proto`, `cluster_break_glass_grant.proto`
- DELETE `scim_user_mapping.proto`
- DELETE FGA-model lines: `emergency_admin: [user with break_glass_window]`, `condition break_glass_window {…}`; update `any_admin` from `system_admin or emergency_admin` to `system_admin`.

**kacho-iam (`project/kacho-iam/`):**
- DELETE directories: `internal/apps/kacho/api/scim/`, `internal/apps/kacho/api/saml/`.
- DELETE files: `internal/repo/kacho/pg/scim_repos.go`, `scim_gdpr_reviews_repos.go`, `organization_sso_repos.go`, `break_glass_repos.go`.
- DELETE files: `internal/service/break_glass_service.go`, `internal/service/break_glass_service_test.go`.
- DELETE files: `internal/domain/scim_user_mapping.go`, `internal/domain/cluster_break_glass_grant.go`, `internal/domain/cluster_break_glass_grant_test.go`.
- DELETE files: `internal/clients/jackson_client.go`, `jackson_client_test.go`.
- DELETE files: `internal/fuzz/fuzz_saml_assertion_test.go`.
- DELETE `cmd/jwks-rotator/` only if it solely served SAML — verify before removing (probably keep, it serves OIDC JWKS too).
- STRIP from `cmd/kacho-iam/serve.go`, `wiring.go`, `governance_wiring.go`, `grpc_register.go`, `listeners.go`: SCIM listener, SAML SP routes, break-glass wiring, jackson client wiring.

**Migrations (kacho-iam):**
- ADD migration `0006_drop_scim_saml_break_glass.sql` — DROP TABLE `scim_user_mappings`, `scim_gdpr_reviews`, `organization_saml_configs`, `cluster_break_glass_grants`. (Existing applied migrations stay per workspace rule #5.)

**kacho-api-gateway:**
- Remove SCIM-callback REST routes (e.g. `/scim/v2/Users`, `/scim/v2/Groups`).
- Remove SAML ACS/SLO routes.
- Remove break-glass REST routes (`/iam/v1/breakGlass:*`).
- Update internal/REST mux + grpc-proxy mapping accordingly. Remove BG/SCIM/SAML methods from public allowlist.

**kacho-deploy:**
- Remove FGA bootstrap-job lines that write `emergency_admin`/`break_glass_window`.
- Remove jackson-saml deployment / configmap if any.
- Update Helm values (drop `breakGlass.enabled`, `scim.enabled` etc).

**Vault:**
- Mark deprecated: `resources/iam-scim-user-mapping.md`, `iam-cluster-break-glass-grant.md`.
- Update `rpc/iam-saml-sp.md`, `iam-scim-v2.md`, `iam-internal-iam-service.md` (Break-Glass methods gone).
- Update `edges/iam-to-jackson-saml.md`, `iam-to-scim-azure.md`, `iam-to-scim-google.md`, `iam-to-scim-okta.md` — mark as removed.

### 3.7 Data migration plan

Single new IAM migration `0005_rbac_v2_grammar_and_scope.sql` (separately from the SCIM/SAML/BG drop) executes in this order:

1. **Backup** `roles.permissions` and `access_bindings` snapshots to `_pre_rbac_v2` audit tables.
2. **Promote permissions to 4-segment**:
   ```sql
   UPDATE kacho_iam.roles
   SET permissions = (
     SELECT jsonb_agg(
       CASE
         WHEN array_length(string_to_array(p, '.'), 1) = 3
           THEN split_part(p,'.',1)||'.'||split_part(p,'.',2)||'.*.'||split_part(p,'.',3)
         WHEN array_length(string_to_array(p, '.'), 1) = 4
           THEN p
         ELSE NULL
       END
     )
     FROM jsonb_array_elements_text(permissions) p
   );
   ```
3. **Add scope column** + backfill from `resource_type`:
   ```sql
   ALTER TABLE kacho_iam.access_bindings ADD COLUMN scope SMALLINT;
   UPDATE kacho_iam.access_bindings SET scope = CASE resource_type
     WHEN 'cluster' THEN 1 WHEN 'organization' THEN 1
     WHEN 'account' THEN 2 WHEN 'cloud' THEN 2
     WHEN 'project' THEN 3 WHEN 'folder' THEN 3
     ELSE 3  -- per-domain resource_types collapse to PROJECT scope
   END;
   ALTER TABLE kacho_iam.access_bindings ALTER COLUMN scope SET NOT NULL;
   ALTER TABLE kacho_iam.access_bindings
     ADD CONSTRAINT access_bindings_scope_ck CHECK (scope IN (1,2,3));
   CREATE INDEX access_bindings_scope_idx ON kacho_iam.access_bindings(scope, resource_type);
   ```
4. **Swap `iam_permissions_valid()`** PL/pgSQL function to enforce strict 4-segment grammar.
5. **Validate**: re-CHECK roles.permissions against the new validator; any row failing → audit-log + abort migration (no silent data loss).
6. **Rebuild fga_outbox**: enqueue re-emit jobs for every active AccessBinding so the FGA store gets the new tuple shape. The drainer is idempotent (UNIQUE on tuple), so re-enqueue is safe.

`0006_drop_scim_saml_break_glass.sql` runs separately to drop the dead tables.

### 3.8 Test strategy

Strict TDD per workspace §12 + memory:

**Unit (kacho-iam):**
- `authzmap.PermissionsToRelations` — full 4-segment grammar; rejects 3-segment; accepts each wildcard position; case-folds verbs.
- New `authzmap.fga_types.go` mapping — `compute.instance` → `compute_instance` and a closed table of pairs.
- AccessBinding validators — scope-vs-resource_type consistency.

**Integration (testcontainers, kacho-iam):**
- `iam_permissions_valid()` — INSERT/UPDATE of role.permissions with invalid 4-segment strings rejects on `23514`.
- AccessBinding scope-backfill migration — pre-existing rows of every resource_type carried to the right scope.
- fga_outbox emitter — for each (permission-pattern × scope) cell from §3.5, the right tuple is emitted; idempotent on re-enqueue.
- AccessBinding INSERT with `scope=CLUSTER` + `resource_type='project'` → CHECK rejects (`23514`).

**Integration (kacho-vpc + kacho-compute):**
- For each `List<Resource>` RPC:
  - Subject with no permissions → empty list, OK status.
  - Subject with `M.R.*.read` + scope=PROJECT → list returns only resources under that project.
  - Subject with `M.R.<id>.read` for two ids → list returns exactly those two.
  - Subject with `*.*.*.*` + scope=CLUSTER → list returns all rows (wildcard_grant short-circuits the filter).
  - ListObjects-call failure → response is Unavailable.

**Newman (kacho-deploy `/tests/newman`):**
- Same matrix end-to-end against the deployed stack. Three new collections per service.
- DELETE existing SCIM/SAML/BG newman cases (entire collections + setup steps).
- Regression: existing passing newman cases must stay green after the 4-segment migration (their role-grants are auto-promoted by the migration).

**No TODO/skip/FIXME in tests** per workspace §13.

## 4. Component map of changes

| Component | Change kind | Notes |
|---|---|---|
| `kacho-proto/proto/kacho/cloud/iam/v1/access_binding.proto` | add `Scope` enum + `scope` field (15) | additive; backward compatible |
| `kacho-proto/proto/kacho/cloud/iam/v1/authorize_service.proto` | add `wildcard_grant` field to ListObjectsResponse | additive |
| `kacho-proto/proto/kacho/cloud/iam/v1/break_glass_service.proto` | DELETE | breaking — coordinated drop |
| `kacho-proto/proto/kacho/cloud/iam/v1/cluster_break_glass_grant.proto` | DELETE | breaking — coordinated drop |
| `kacho-proto/proto/kacho/cloud/iam/v1/scim_user_mapping.proto` | DELETE | breaking — coordinated drop |
| `kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga` | edit: drop `emergency_admin`, `break_glass_window` | breaking |
| `kacho-iam/internal/migrations/0005_rbac_v2_grammar_and_scope.sql` | new | 4-seg promote + scope add |
| `kacho-iam/internal/migrations/0006_drop_scim_saml_break_glass.sql` | new | DROP TABLEs |
| `kacho-iam/internal/authzmap/permissions_to_relations.go` | rewrite | 4-segment grammar |
| `kacho-iam/internal/authzmap/fga_types.go` | new | (module,resource)→fga_type table |
| `kacho-iam/internal/service/fga_tuple_writer.go` | rewrite emit-logic | per §3.5 |
| `kacho-iam/internal/service/break_glass_service.go` | DELETE | + tests |
| `kacho-iam/internal/apps/kacho/api/scim/` | DELETE | entire dir |
| `kacho-iam/internal/apps/kacho/api/saml/` | DELETE | entire dir |
| `kacho-iam/internal/repo/kacho/pg/{scim,saml,break_glass,organization_sso}*.go` | DELETE | |
| `kacho-iam/internal/clients/jackson_client*.go` | DELETE | |
| `kacho-iam/internal/domain/{scim_user_mapping,cluster_break_glass_grant}*.go` | DELETE | |
| `kacho-iam/cmd/kacho-iam/{serve,wiring,governance_wiring,grpc_register,listeners}.go` | strip BG/SCIM/SAML wiring | |
| `kacho-iam/internal/apps/kacho/api/access_binding/` | scope validation + emit | new field plumbing |
| `kacho-iam/internal/apps/kacho/seed/embedded/permission_catalog.json` | regen 4-seg | mirror of api-gateway catalog |
| `kacho-vpc/internal/apps/**/list*.go` | wire `listauthz.Adapter` in every List handler | audit + add tests |
| `kacho-compute/internal/apps/**/list*.go` | same | |
| `kacho-api-gateway/internal/middleware/embed/permission_catalog.json` | regen 4-seg | source-of-truth |
| `kacho-api-gateway/internal/restmux/` | remove SCIM/SAML/BG routes | |
| `kacho-api-gateway/internal/grpcproxy/` | remove SCIM/SAML/BG methods from allowlist | |
| `kacho-deploy/helm/**` | drop break_glass/scim/saml charts + values | |
| `kacho-deploy/tests/newman/cases/iam-{scim,saml,break-glass}-*.py` | DELETE | + regen |
| `kacho-workspace/docs/specs/sub-phase-X.Y-*-acceptance.md` | new per wave | acceptance gates |
| `obsidian/kacho/{resources,rpc,packages,edges,KAC}/*` | update / mark deprecated / add new | vault discipline |

## 5. Cross-repo execution waves

Waves run in topological order (see workspace CLAUDE.md §«Кросс-репо зависимости»). Each wave is a separate KAC subtask with its own acceptance doc + TDD RED→GREEN pair.

1. **W1 — workspace docs**: this design doc + acceptance docs per wave + YouTrack epic + per-wave KAC subtasks. Vault notes.
2. **W2 — kacho-proto**: add `Scope` enum + `wildcard_grant`, DELETE BG/SCIM/SAML protos, edit `fga_model.fga`. Regen go-stubs. `buf breaking` allowed (coordinated).
3. **W3 — kacho-iam migrations**: `0005_rbac_v2_grammar_and_scope.sql`, `0006_drop_scim_saml_break_glass.sql`. Migration integration tests.
4. **W4 — kacho-iam code**: authzmap rewrite, fga_tuple_writer rewrite, AccessBinding scope plumbing, permission-catalog regen, SCIM/SAML/BG package deletion. All wired via integration tests.
5. **W5 — kacho-api-gateway**: route removals, catalog regen, allowlist update.
6. **W6 — kacho-vpc + kacho-compute**: audit + wire `listauthz` in every List handler; tests.
7. **W7 — kacho-deploy**: Helm cleanup; newman collection cleanup + new collections for list-filter; FGA bootstrap-job update.
8. **W8 — vault + workspace docs**: post-merge vault refresh; per-KAC trails; close epic.

## 6. Risks / mitigations

| Risk | Mitigation |
|---|---|
| Existing tests rely on emergency_admin / break_glass FGA path | Delete those tests in the same PR as the removal; re-run newman regression for non-BG paths. |
| Production rows have malformed 3-segment permissions | Migration aborts on first invalid row + audit-table backup; fix data manually then re-run. |
| ListObjects under-coverage misses a List RPC → leaks resource existence | Wave 6 audit script: grep every `List<Resource>(` handler in vpc/compute; CI gate (`make audit-list-filter`) refuses unwired handlers. |
| Subject under-grant after migration (3→4 seg semantics shift) | The 3→4 promotion preserves intent: `compute.instance.read` ⇒ `compute.instance.*.read` — same effective access. No narrowing. |
| FGA tuple drift across re-emit | Drainer is idempotent on (object,relation,user) UNIQUE; safe to re-enqueue every binding. |
| BG/SCIM/SAML data not actually unused → drop breaks an integration | Pre-drop, query each table for non-empty rows on prod-mirror; report counts. Drop only after confirmation. |

## 7. Definition of Done

- [ ] All waves merged; each PR carries integration + newman tests; RED→GREEN pair documented in PR body.
- [ ] `iam_permissions_valid()` enforces strict 4-segment grammar; no 3-segment row exists in `roles.permissions`.
- [ ] `access_bindings.scope` column populated for all rows; constraint enforced.
- [ ] Every `List<Resource>` RPC across vpc/compute/iam returns only authorized rows for a subject; newman tests assert empty/2-of-N/all-N matrices.
- [ ] Zero SCIM/SAML/Break-Glass code, proto, FGA-relation, REST route, Helm chart left in any kacho-* repo.
- [ ] `buf lint` / `buf breaking` (with the coordinated baseline) green across kacho-proto.
- [ ] FGA store catch-up confirmed (no orphan emergency_admin tuples).
- [ ] Vault — every changed resource/rpc/edge/packages file updated; KAC notes carry PR URLs.
- [ ] YouTrack epic + subtasks → Done.

## 8. Open items / explicit non-decisions

- **Permission catalog regeneration ownership**: stays in kacho-proto buf-gen pipeline. The script that emits `permission_catalog.json` (currently producing 3-segment) is updated to emit 4-segment. (Not modified here — separate one-line tweak in the generator.)
- **`granted_by_user_id` vs `system` for migration-time scope-backfill**: backfill leaves the existing `granted_by_user_id` untouched. No new system audit rows generated.
- **Subject lookup for ListObjects under bootstrap**: the existing `auth.PropagateOutgoing` shim (W1.4 fix) already covers this — vpc/compute pass real caller; iam-internal calls use `system:bootstrap`. No change needed.
- **`SCOPE_UNSPECIFIED` after migration**: should never appear; if it does, treat as PROJECT (narrowest scope) at runtime and emit a `slog.Warn`. New writes reject SCOPE_UNSPECIFIED.

## 9. References

- Workspace rules: `kacho-workspace/CLAUDE.md` §«Within-service refs», §«Запреты», §«Кросс-доменные ссылки», §«Obsidian vault»
- IAM rules: `kacho-iam/CLAUDE.md`
- Predecessor design (production-cleanup): `docs/superpowers/specs/2026-05-24-kacho-iam-production-cleanup-refactor-design.md`
- Predecessor design (prod-ready next-gen IAM): `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md`
- FGA model: `kacho-proto/proto/kacho/cloud/iam/v1/fga_model.fga`
- Permission catalog: `kacho-api-gateway/internal/middleware/embed/permission_catalog.json`
- Existing list-filter adapter: `kacho-vpc/internal/clients/iam_listobjects_client.go`, `kacho-corelib/authz/`
