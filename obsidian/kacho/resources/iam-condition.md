---
title: Condition
aliases:
  - Condition (iam)
  - iam Condition
  - reusable CEL Condition
category: resource
domain: iam
id_prefix: cnd
owner_table: kacho_iam.conditions
owner_db: kacho_iam
folder_level: false
status: experimental
related_rpc:
  - "[[rpc/iam-conditions-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
tags:
  - resource
  - kacho-iam
  - iam
  - authz
---

# Condition (iam)

**Domain**: iam — project-scoped reusable expression, referenced by `AccessBinding.condition_ref.condition_id`.
**ID prefix**: `cnd` (legacy joined form, `ids.NewID("cnd")`). Registered in `ids.KnownPrefixes()` — before that the gateway rejected every well-formed condition id as malformed.
**Owner table**: `kacho_iam.conditions`.
**Visibility**: public — CRUD + `Evaluate` via [[../rpc/iam-conditions-service]].

> [!warning] The connective tissue does not exist
> The CRUD is real and tested, but nothing consumes a Condition. `AccessBindingService.Create` never reads `condition_id`; `access_binding_conditions` has no production writer; no code maps a `cnd…` id to an FGA condition name; `Evaluate` is a substring matcher, not CEL. Read [[../rpc/iam-conditions-service]] §Reality before designing against this resource.

## Fields (as implemented)

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | CHECK `^cnd[a-z0-9]{1,17}$` |
| `project_id` | TEXT NOT NULL | the scope. Renamed from `folder_id` (migration `0070`) |
| `created_at` | TIMESTAMPTZ | truncated to seconds on the wire |
| `name` | TEXT | `UNIQUE(project_id, name) WHERE status <> 'DELETING'` |
| `description` | TEXT | ≤256 |
| `labels` | JSONB | |
| `expression` | TEXT | 1..2048 |
| `parameters_schema` | JSONB | |
| `status` | TEXT | `CREATING` / `ACTIVE` / `DELETING` / `ERROR` |
| `resource_version` | BIGINT | **internal OCC token, never on the wire** — `UPDATE … WHERE id=$1 AND resource_version=$2`. Not the forbidden K8s envelope field; the proto message has no such field |

## Constraints / indexes

- `conditions_pkey` (id) · `conditions_project_name_uniq` · `idx_conditions_project_status`
- `conditions_project_id_not_empty`, `conditions_id_check`, `conditions_name_pattern`, `conditions_status_whitelist`
- (in) `access_binding_conditions.condition_id → conditions(id) ON DELETE RESTRICT` (migration `0048`, trigger-derived column) — the table it guards has no writer.

## Authorization

`type iam_condition` carries a `project` parent pointer; `super_admin: super_admin from project` gives the three super-access tiers.
**`ConditionsService.Create` emits `iam_condition:<id> # project @ project:<projectId>` into `fga_outbox` in the same writer-tx as the row, and retracts it on Delete.** Before that no writer existed, the cascade was dead, and the cloud administrator could not reach a Condition.
In-service gate: read needs `viewer`, mutation needs `editor` on `project:<projectId>`; cluster-admin short-circuits.

> [!note] Not registered for per-object materialisation
> `iam.condition` is absent from `labelSelectableTypes` / `materializableTypes` (`internal/domain/feed_registry.go`), from `iamDirectScanSpecs` (`repo/kacho/pg/reconcile_adapter.go`) and from every seeded `role_rule_selectors.object_types`. A `*.*` owner binding therefore materialises no per-object verb tuple on a Condition — only the super-admin cascade and a direct grant reach it.

## See also

[[iam-access-binding-condition]] [[iam-access-binding]] [[../rpc/iam-conditions-service]] [[../rpc/iam-authorize-service]] [[../packages/iam-domain]]

#resource #kacho-iam #iam #authz
