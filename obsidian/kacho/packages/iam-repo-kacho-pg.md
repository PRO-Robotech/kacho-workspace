---
title: "iam internal/repo/kacho/pg"
aliases:
  - iam repo pg
  - iam-repo-kacho-pg
category: packages
repo: kacho-iam
layer: repo
status: done
related_tickets:
  - "[[KAC-105]]"
  - "[[KAC-112]]"
  - "[[KAC-108]]"
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - repo
---

# iam `internal/repo/kacho/pg`

CQRS Repository / Reader / Writer adapter — реализация port-интерфейсов из `internal/repo/kacho/<resource>` через `pgxpool`. Реализует pg-adapter strategy: pgx + dto-mapping без ORM (workspace §запрет #3).

## Layer rules

- Импортирует только `pgxpool`, `pgconn`, `internal/domain`, `internal/errors`, `kacho-corelib/db`.
- НЕ импортирует proto-stubs / grpc — этим занимается handler.
- SQLSTATE → sentinel mapping — централизованно в `maperr.go` (workspace §запрет #10 / §«Within-service refs — DB-уровень»).

## Files (per resource)

### Core (KAC-105/KAC-112)
- `account_repo.go` + `account_integration_test.go`
- `project_repo.go` + `project_integration_test.go`
- `user_repo.go` + `user_integration_test.go` + `user_invite_integration_test.go`
- `service_account_repo.go` + `service_account_integration_test.go`
- `group_repo.go` + `group_integration_test.go`
- `role_repo.go` + `role_integration_test.go`
- `access_binding_repo.go` + `access_binding_integration_test.go`
- `operations_repo.go`

### KAC-127 Phase 1 (4 new repo files + integration tests)
- **`kac127_repos.go`** — Cluster + Organization + ClusterAdminGrant + ClusterBreakGlassGrant + AccessBindingCondition + JITEligibility repos (migration 0011-0012 tables).
- **`kac127_federation_repos.go`** — FederationTrustPolicy + ServiceAccountOAuthClient repos (migration 0012).
- **`kac127_audit_caep_repos.go`** — AuditOutboxEntry + AuditSigningBatch + CAEPSubscriber + CAEPOutboxEntry + SessionRevocation repos (migration 0013).
- **`kac127_scim_gdpr_reviews_repos.go`** — SCIMUserMapping + GDPRErasureRequest + AccessReview + AccessReviewItem + OIDCJwksKey repos (migration 0014).
- **`kac127_repos_integration_test.go`** — concurrent CAS + partial UNIQUE race tests.
- **`migrations_kac127_integration_test.go`** — verifies migrations 0011-0014 apply cleanly + idempotent re-apply.

### Helpers
- `repository.go` — Repository struct + constructor.
- `tx.go` — Writer-TX wrapper (`Repository.RunInTx(ctx, func(WriterCtx) error)`).
- `helpers.go` — shared dto-mapping utilities.
- `maperr.go` — SQLSTATE → sentinel mapping (23503 → FailedPrecondition, 23505 → AlreadyExists/FailedPrecondition по контексту, 23514 → InvalidArgument, 23P01 → FailedPrecondition).
- `stubs.go` — нереализованные методы (returns ErrNotImplemented).
- `dto/` — DTO row-types (1:1 с DB columns).

## DB-уровень enforcement (KAC-127 highlights)

- `cluster_admin_grants_subject_unique` partial UNIQUE WHERE granted_until IS NULL.
- `access_binding_conditions_binding_unique` UNIQUE — 1:1 enforcement.
- `service_account_oauth_clients_sva_unique` UNIQUE — 1:1 SA→client.
- `oidc_jwks_keys_current_per_alg` partial UNIQUE WHERE current=true — JWKS rotation atomic CTE.
- `roles_scope_xor` CHECK + 4 partial UNIQUEs per scope (cluster/organization/account/project).
- `access_bindings_status_ck` + `access_bindings_revoked_consistency_ck` + `access_bindings_expires_ck` — KAC-127 lifecycle invariants.

## Concurrency / atomic CAS patterns

- **JWKS rotate**: single-statement CTE `WITH rotated AS (UPDATE ... WHERE current=true RETURNING) INSERT new`.
- **AccessBinding revoke**: idempotent CAS `UPDATE ... WHERE id=$id AND status IN ('PENDING','ACTIVE')` → REVOKED.
- **Project.Move** (KAC-105): atomic CAS UPDATE с `WHERE account_id=$expected`.
- **BreakGlass state transitions** (Phase 7): atomic CAS UPDATE per state-transition.
- **Bootstrap admin grant** (Phase 1): 23505 → graceful WARN (concurrent HA cold-start, acceptance §6.10.5).

## Imports

- `github.com/jackc/pgx/v5`, `pgxpool`, `pgconn`
- `internal/domain`, `internal/errors`, `internal/dto`
- `kacho-corelib/db` (transactor).

## Imported by

- `cmd/kacho-iam/main.go` — composition root.
- `internal/apps/kacho/api/*` — use-case через port-interfaces (mock via `repomock/`).

## See also

[[iam-domain]] [[iam-seed]] [[iam-jobs]] [[../resources/iam-cluster]] [[../resources/iam-role]] [[../resources/iam-access-binding]] [[../KAC/KAC-127]]

#packages #kacho-iam #repo
