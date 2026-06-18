---
title: InternalOperationsService
aliases:
  - InternalOperationsService (iam)
proto_file: kacho/cloud/iam/v1/internal_operations_service.proto
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-account]]"
methods_count: 1
async_methods: 0
status: done
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
---

# InternalOperationsService (iam)

**Proto**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_operations_service.proto`
**Backend**: `kacho-iam:9091` (internal-only gRPC — **ban #6**, never external).
**Visibility**: internal — cluster-wide admin operations feed for the admin UI.
**Status**: ✅ done — sub-phase 1.2 (IAM operations visibility, §B / D-4b / D-10); merged + live `fe3455` helm rev13. См. [[sub-phase-1.2-iam-operations]].

## Methods

| Method | Request | Response | Sync/Async | Note |
|---|---|---|---|---|
| ListIamOperations | ListIamOperationsRequest | ListIamOperationsResponse | sync | cluster-wide: ALL IAM ops of the cluster, optional `account_id` filter (empty → no filter). cursor `(created_at,id)` ASC, page_size clamp ≤1000. |

## REST mapping (internal mux only)

| HTTP | Method |
|---|---|
| `GET /iam/v1/internal/operations` | ListIamOperations |

> Registered ONLY in the api-gateway **internal** restmux block (`iamInternalAddr`),
> never on the external listener. `external_isolation_test.go` `internalRESTPaths`
> must include `/iam/v1/internal/operations` (api-gateway-registrar, P0 ban #6).

## Authz (admin-tier, defense-in-depth)

- **Gateway permission-catalog**: `required_relation=system_admin`,
  `scope_extractor.object_type=cluster` (→ singleton `cluster_kacho_root`),
  `required_acr_min=2` — parity with `InternalClusterService/*` (D-10).
- **iam internal-listener interceptor chain** also enforces it: the RPC FQN
  `/kacho.cloud.iam.v1.InternalOperationsService/ListIamOperations` is in
  `authzguard.GatewayFrontedInternalRPCs()` → caller-policy gateway-only +
  acr-floor. (security.md "AuthN+AuthZ ВЕЗДЕ" — internal NOT exempt.)
- **In-handler ReBAC Check**: the use-case `requireClusterSystemAdmin` runs a
  per-user `Check(user:<p>, system_admin, cluster:<singleton>)` (mirrors
  `cluster.requireClusterSystemAdmin`). A caller bypassing the gateway and
  dialing :9091 directly is rejected without `system_admin` (1.2-15a). nil
  checker / backend error / explicit deny → `PermissionDenied` (fail-closed).

## Notes

- Filters on the denormalized `operations.account_id` column (corelib
  `ListFilter.AccountID`); IAM migration `0016_operations_account_id.sql` adds it
  + the partial cursor index.
- Cluster-wide list is the ONLY surface aggregating category-(II) + Internal-only
  op-producers (Role, project-scoped AccessBinding, SAKey/Condition,
  GrantClusterAdmin/ForceLogout/WriteTuples/Upsert) — none of which appear in any
  account-scoped public list (their `account_id` stays NULL).

## See also

[[iam-account-service]] [[iam-internal-cluster-service]] [[../resources/iam-account]] [[../packages/corelib-operations]] [[sub-phase-1.2-iam-operations]]

#rpc #kacho-iam #iam #internal
