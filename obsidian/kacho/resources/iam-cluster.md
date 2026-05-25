---
title: Cluster
aliases:
  - Cluster (iam)
  - iam Cluster
category: resource
domain: iam
id_prefix: cluster_
owner_table: kacho_iam.clusters
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
  - "[[packages/iam-seed]]"
related_tickets:
  - "[[KAC-127]]"
  - "[[KAC-196]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
---

# Cluster

**Domain**: iam — singleton root of hierarchy `cluster → organization (optional) → account → project → resource`.
**ID prefix**: literal `cluster_kacho_root` (singleton; DB CHECK `clusters_id_singleton_ck`).
**Owner table**: `kacho_iam.clusters` (Phase 1 / migration 0011).
**Visibility**: **internal-only** (admin-tooling / OPA cluster-admin enforcement); никогда на публичной поверхности (workspace `CLAUDE.md` §«Инфра-чувствительные данные» + §Запреты #6).

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | = `cluster_kacho_root` | singleton-CHECK |
| `name` | TEXT | length 1..64 | kebab-style |
| `description` | TEXT | length <=256 | optional |
| `created_at` | TIMESTAMPTZ | server-set | truncate-to-seconds |

## Constraints / indexes

- `clusters_pkey` PRIMARY KEY (id)
- `clusters_id_singleton_ck` CHECK (`id = 'cluster_kacho_root'`)
- `clusters_name_check` CHECK (`length(name) BETWEEN 1 AND 64 AND name ~ '^[a-z][-a-z0-9]*$'`)
- `clusters_description_check` CHECK (`length(description) <= 256`)

## FK contract (in-bound)

- `cluster_admin_grants.cluster_id → clusters(id) ON DELETE RESTRICT` (см. [[iam-cluster-admin-grant]])
- `cluster_break_glass_grants.cluster_id → clusters(id) ON DELETE RESTRICT` (см. [[iam-cluster-break-glass-grant]])
- `organizations.cluster_id → clusters(id) ON DELETE RESTRICT` (см. [[iam-organization]])
- `accounts.cluster_id → clusters(id) ON DELETE RESTRICT` (через миграцию 0011 §«alter accounts»)
- `roles.cluster_id → clusters(id) ON DELETE RESTRICT` (см. [[iam-role]] — system-roles)

→ Удаление Cluster → `FailedPrecondition` (всегда; singleton фактически immortal).

## Lifecycle

Singleton, seed-only через миграцию 0011 (одна row). Immutable после создания.
Phase 2 OpenFGA model: tuple `cluster:cluster_kacho_root#system_admin@user:usr_xxx` —
объект authz-проверки cluster-admin.

**KAC-196**: `Get` RPC доступен через [[../rpc/iam-internal-cluster-service]] (internal mux `/iam/v1/internal/cluster`).

## Gotchas

- `id` хардкод — не используем generator. Попытка INSERT с другим id → `clusters_id_singleton_ck` violation → `InvalidArgument`.
- Cluster — internal resource: никаких публичных RPC / REST endpoint. Любые admin-ops через internal cluster service (см. [[../rpc/iam-internal-cluster-service]]).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../packages/iam-seed]] [[../rpc/iam-internal-cluster-service]] [[iam-cluster-admin-grant]] [[iam-cluster-break-glass-grant]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
