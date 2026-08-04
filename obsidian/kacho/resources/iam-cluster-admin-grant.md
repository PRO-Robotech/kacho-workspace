---
title: ClusterAdminGrant
aliases:
  - ClusterAdminGrant (iam)
  - iam ClusterAdminGrant
  - cluster_admin_grant
category: resource
domain: iam
id_prefix: cag
owner_table: kacho_iam.cluster_admin_grants
owner_db: kacho_iam
project_level: false
status: done
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
  - "[[packages/iam-seed]]"
  - "[[packages/iam-handler-internal-cluster]]"
  - "[[packages/iam-apps-cluster-usecases]]"
related_tickets:
  - "[[KAC-127]]"
  - "[[KAC-196]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
verified_against: "таблица-владелец подтверждена живой переписью миграций сервиса (ствол redesign/integration, 2026-08-05); поля построчно не пересматривались"
---

# ClusterAdminGrant

**Domain**: iam — permanent root-grant на singleton Cluster. Источник истины для OpenFGA tuple `cluster:cluster_kacho_root#system_admin@user:usr_xxx`.
**ID prefix**: `cag_` + 17-char crockford → `^cag_[0-9a-hjkmnp-tv-z]{17}$`.
**Owner table**: `kacho_iam.cluster_admin_grants` (migration 0011).
**Visibility**: **internal-only** (cluster-admin enforcement).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^cag_[0-9a-hjkmnp-tv-z]{17}$` | |
| `cluster_id` | TEXT | FK → clusters(id) RESTRICT | NOT NULL |
| `subject_type` | TEXT | CHECK `IN ('user','service_account')` | **NOT group** — strictly individual identity |
| `subject_id` | TEXT | length 1..64 | soft-ref (полиморфно user/sva) |
| `granted_by` | TEXT | length 1..64 | `'bootstrap'` либо user_id verbatim |
| `granted_at` | TIMESTAMPTZ | server-set | |
| `granted_until` | TIMESTAMPTZ NULL | CHECK `IS NULL OR > granted_at` | **NULL = permanent**; временные → [[iam-cluster-break-glass-grant]] |

## Constraints / indexes

- `cluster_admin_grants_pkey` PRIMARY KEY (id)
- `cluster_admin_grants_cluster_fk` FK → `clusters(id)` RESTRICT
- `cluster_admin_grants_subject_unique` **partial UNIQUE** (subject_type, subject_id) **WHERE `granted_until IS NULL`** — гарантирует **один permanent grant** на subject (acceptance §6.10.5).
- CHECK: id-regex, subject_type-enum, length, granted_until > granted_at.

## Lifecycle

- **Bootstrap** ([[iam-seed]] `bootstrap_admin.go`): startup-time `KACHO_IAM_BOOTSTRAP_ROOT_EMAIL` → lookup user → atomic TX: INSERT cluster_admin_grant + INSERT fga_outbox (`fga.tuple.write`) + INSERT audit_outbox.
- **Grant** (KAC-196, [[../KAC/KAC-196]]) — `GrantAdminUseCase`: ON CONFLICT ON CONSTRAINT cluster_admin_grants_cluster_subject_uniq DO NOTHING → если revoked-row → Reactivate (UPDATE granted_until=NULL, granted_by=$principal, granted_at=now) → emit fga_outbox + audit_outbox (D-4 idempotent retry-safe).
- **Revoke** (KAC-196) — `RevokeAdminUseCase`: атомарный CAS UPDATE granted_until=now() с тремя WHERE условиями: `granted_until IS NULL` (D-12 NOT idempotent), `subject_id != $principal` (D-5 self), `(SELECT count(*) WHERE granted_until IS NULL) > 1` (D-6 last). 0 rows → diagnostic SELECTs → sentinel (`ErrSelfRevoke`/`ErrLastAdmin`/`ErrNotFound`).
- **Idempotent**: 23505 (partial UNIQUE) → graceful WARN — concurrent HA cold-start race (acceptance §6.10.5).
- **OpenFGA sync**: атомарно с INSERT через [[../packages/iam-jobs]] FGAOutboxDrainer.

## RPC operations (KAC-196)

- `Get` / `ListAdmins` — sync, см. [[../rpc/iam-internal-cluster-service]].
- `GrantAdmin` / `RevokeAdmin` — async (Operation), single TX insert/update + fga_outbox + audit_outbox.
- Atomic guards: idempotent ON CONFLICT (D-4), CAS WHERE `count(*) WHERE granted_until IS NULL > 1` last-admin (D-6), CAS WHERE `subject_id != $principal` self-revoke (D-5), CAS WHERE `granted_until IS NULL` revoke-only-active (D-12).

## Gotchas

- `subject_type` намеренно НЕ допускает `group` — break-glass / cluster-admin требует **individual identity** для аудита.
- `granted_until IS NULL` partial-UNIQUE — корректно: один subject может иметь несколько expired grants (history), но только один current permanent.
- `granted_by='bootstrap'` зарезервировано для seed-flow; пользовательские grants пишут реальный user_id grantor'а.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../packages/iam-seed]] [[../rpc/iam-internal-cluster-service]] [[iam-cluster]] [[iam-cluster-break-glass-grant]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
