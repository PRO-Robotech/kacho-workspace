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
folder_level: false
status: planned
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
  - "[[packages/iam-seed]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
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
- **Idempotent**: 23505 (partial UNIQUE) → graceful WARN — concurrent HA cold-start race (acceptance §6.10.5).
- **Revoke**: Phase 7+ — Update `granted_until` к now() (turns into expired).
- **OpenFGA sync**: атомарно с INSERT через [[../packages/iam-jobs]] FGAOutboxDrainer.

## Gotchas

- `subject_type` намеренно НЕ допускает `group` — break-glass / cluster-admin требует **individual identity** для аудита.
- `granted_until IS NULL` partial-UNIQUE — корректно: один subject может иметь несколько expired grants (history), но только один current permanent.
- `granted_by='bootstrap'` зарезервировано для seed-flow; пользовательские grants пишут реальный user_id grantor'а.

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../packages/iam-seed]] [[../rpc/iam-internal-cluster-service]] [[iam-cluster]] [[iam-cluster-break-glass-grant]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
