---
title: Condition
aliases:
  - Condition (iam)
  - iam Condition
  - reusable CEL Condition
category: resource
domain: iam
id_prefix: cond
owner_table: kacho_iam.conditions
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc:
  - "[[rpc/iam-conditions-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
  - authz
---

# Condition (iam)

**Domain**: iam — переиспользуемая CEL-like expression, ссылка из `access_binding_conditions` (см. [[iam-access-binding-condition]]) или `federation_trust_policies.condition_id` ([[iam-federation-trust-policy]]).
**ID prefix**: `cond_<crockford-1..40>` (kac127 id generator).
**Owner table**: `kacho_iam.conditions` (Phase 3 migration).
**Visibility**: public — admin / account-owner CRUD через [[../rpc/iam-conditions-service]].

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^cond_[0-9a-z]{1,40}$` | kac127 generator |
| `account_id` | TEXT NULL | FK accounts ON DELETE RESTRICT | NULL = cluster-scope (system-defined) |
| `name` | TEXT | length 1..64 | human label |
| `description` | TEXT | length <=256 | optional |
| `kind` | TEXT | enum {time, ip, mfa, request_attr, resource_attr, composite, custom} | dispatch для CEL stdlib |
| `expression` | TEXT | length 1..4096; CEL parse-validated | sandboxed eval (no I/O) |
| `params_schema` | JSONB | JSON Schema draft-2020-12 | runtime input shape |
| `enabled` | BOOL | default true | soft-disable |
| `created_at` | TIMESTAMPTZ | server-set | |
| `updated_at` | TIMESTAMPTZ | server-set | |

## Constraints / indexes

- `conditions_pkey` PRIMARY KEY (id)
- `conditions_name_check` CHECK (`length(name) BETWEEN 1 AND 64`)
- `conditions_kind_check` CHECK in enum
- `conditions_expression_check` CHECK (`length(expression) <= 4096`)
- INDEX `(account_id)`, `(kind, enabled)`

## FK contract

- (out) `account_id → accounts(id) ON DELETE RESTRICT` — nullable (cluster-scope).
- (in) `access_binding_conditions.condition_id → conditions(id) ON DELETE RESTRICT` — ссылается из [[iam-access-binding-condition]].
- (in) `federation_trust_policies.condition_id → conditions(id) ON DELETE RESTRICT` — Phase 5 federation overlay.

## Lifecycle

CRUD через [[../rpc/iam-conditions-service]]:
- Create — async (Operation). Server parse-validates `expression` через `cel-go` (sandboxed env: deny `net`, `os`, `time.Now()` outside provided context).
- Update — `expression` / `params_schema` / `description` / `enabled` mutable; `kind` immutable (re-create).
- Delete — RESTRICT pending references (binding/trust-policy refs).
- Evaluate — dry-run sandbox: `(condition_id, params_json, request_context_json) → {allowed:bool, trace:[]}`.

## Phase 3 eval flow

Check-path: [[../rpc/iam-authorize-service]] resolves per-binding conditions:
1. binding → `access_binding_conditions.condition_id` lookup
2. `conditions.expression` + supplied params (`access_binding_conditions.params`)
3. Merge `request_context` (caller IP, time, MFA freshness, target resource attributes)
4. CEL eval → boolean → modulates Check result

## Gotchas

- `params_schema` Optional, но REQUIRED если `expression` references `params.*`. Server validates на Create.
- CEL `int` overflows fail-closed (return error → Check returns InvalidArgument).
- Cluster-scope (`account_id IS NULL`) — только admin может создавать (`cluster:cluster_kacho_root#system_admin`).

## See also

[[iam-access-binding-condition]] [[iam-federation-trust-policy]] [[iam-access-binding]] [[../rpc/iam-conditions-service]] [[../rpc/iam-authorize-service]] [[../packages/iam-domain]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #authz
