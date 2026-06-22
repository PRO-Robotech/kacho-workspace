---
title: PermissionCatalogService
aliases:
  - PermissionCatalogService (iam)
  - ListPermissionCatalog
  - backend-driven role-rule catalog
proto_file: kacho/cloud/iam/v1/permission_catalog_service.proto
category: rpc
backend: kacho-iam
backend_port: 9090
visibility: public
domain: iam
related_resource: "[[resources/iam-role]]"
methods_count: 1
async_methods: 0
status: test
related_tickets:
  - "[[rbac-rules-model-2026-subphase-G-iam]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - authz
  - usecase
  - handler
---

# PermissionCatalogService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/permission_catalog_service.proto` (RBAC rules-model G).
**Backend**: `kacho-iam:9090` (**public** listener; `registerPublicServices` in `cmd/kacho-iam/grpc_register.go`).
**Visibility**: **public** — grantable-token platform metadata, NOT infra-sensitive (`security.md` §infra-sensitive; G-D3). Authenticated-floor; anonymous fail-closed.
**Status**: test (branch `rbac-docs-site`).

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| ListPermissionCatalog | ListPermissionCatalogRequest (empty) | ListPermissionCatalogResponse | **sync** read | grantable role-rule taxonomy: `modules[]`→`resources[]` + `closedVerbs[]` + `wildcardPolicy`. No payload (no id/filter/pagination in v1). |

## REST mapping (public mux)

| HTTP | Method |
|---|---|
| `GET /iam/v1/permissionCatalog` | ListPermissionCatalog |

## Response shape (camelCase on the wire)

- `modules[]` — `{module, resources[]}`; ordered, derived from `authzmap.objectTypes` keys.
- `resources[]` — `{resource, hasVerbRelations, hasListEndpoint}` (camelCase).
- `closedVerbs[]` — `["get","list","create","update","delete"]` (mirror `domain.ClosedVerbs`, fixed order).
- `wildcardPolicy` — `{verbWildcardAllowedCustom=true, moduleResourceWildcardSystemOnly=true}` (R-3/§2.2 parity; one combined flag for module+resource wildcards).

## Backend projection (NO DB, NO migration, NO repo)

Catalog is a **projection from code** — `internal/apps/kacho/api/permission_catalog/`:
- source = `authzmap.Catalog()` (the exported lister over the closed `objectTypes` table) + `authzmap.TypeHasVerbRelations` (→ `hasVerbRelations`) + `domain.ClosedVerbs` (→ `closedVerbs`).
- `hasListEndpoint` = curated closed DENY-set table `noPublicListEndpoint` (`has_list_endpoint.go`): `true` for every objectTypes pair EXCEPT `vpc.addressPool` (Internal-only :9091 List) and `iam.condition` (`ConditionsService.List` NOT registered on external gateway mux). **MUST stay in lockstep with kacho-api-gateway public-mux registration.**
- Use-case `ListPermissionCatalogUseCase.Execute(ctx)` — first statement `authzguard.RequireAuthenticated(ctx)` (anonymous fail-closed, G-02). Thin handler projects DTO → proto. Stateless.

## Notes

- **Two-way set-equality (G-04)**: catalog `(module,resource)` set == `authzmap.Catalog()` keys exactly (integration/unit parity test — a future `objectTypes` addition appears automatically, no catalog-code change; closes the manual 3-place sync debt).
- **NOT** the internal `InternalIAMService.ListPermissions` stub (that was a :9091 false-assurance stub returning `module.resource.verb` RPC-enforcement strings — **DELETED** in sub-phase G; see [[iam-internal-iam-service]]). Different taxonomy (rule-tokens vs permission-strings), different listener, different RPC.
- Catalog carries NO compiled `permissions[]` / FGA-relation-names (`v_*`/`scope_grant`/`sg_*`) — only tenant-facing grantable tokens + editor/policy flags (G-D9, `security.md` §infra-sensitive parity).
- No new cross-service edge: in-process projection, IAM calls no peer for the catalog. gateway catalog marks the RPC `<exempt>` (authenticated-floor only, no FGA Check).

## See also

- [[iam-role-service]] — role-rule authoring consumes this catalog (UI dropdowns).
- [[iam-internal-iam-service]] — the deleted `ListPermissions` stub (NOT this).
- [[rbac-rules-model-2026-subphase-G-iam]] — KAC-trail.

#rpc #kacho-iam #iam #authz #usecase #handler
