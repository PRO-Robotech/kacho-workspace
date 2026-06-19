---
title: ResourceMirror
aliases:
  - resource_mirror
  - iam resource mirror
category: resource
domain: iam
id_prefix: "(none — PK object_type+object_id)"
owner_table: kacho_iam.resource_mirror
owner_db: kacho_iam
folder_level: false
status: done
related_rpc:
  - "[[rpc/iam-internal-iam-service]]"
related_packages:
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[epic-100-resource-scoped-access-binding]]"
tags:
  - resource
  - kacho-iam
  - iam
  - cross-service
---

# ResourceMirror (kacho_iam.resource_mirror)

**Domain**: iam — **output-only зеркало** labels+parent чужих ресурсов (compute/vpc),
синканное через расширенное ребро `compute→iam` (`RegisterResource`, sub-phase β
epic-rsab). Source of truth = owner-сервис (`data-integrity.md` §cross-domain п.3);
mirror НЕ источник истины, переживает dangling. Питает **γ**: `bySelector`
(`matchLabels`) membership + containment («объект под scope») SAME-DB, **без ребра
iam→owner** (цикл запрещён).

**Owner table**: `kacho_iam.resource_mirror` (migration 0019). НЕ tenant-CRUD —
наполняется только Internal `RegisterResource`/`UnregisterResource`.

## Fields (migration 0019)

| Field | Type | Note |
|---|---|---|
| `object_type` | TEXT | часть PK; closed `<module>.<resource>` (`compute.instance`) |
| `object_id` | TEXT | часть PK; opaque cross-DB soft-ref (без FK, ban #8) |
| `parent_project_id` | TEXT | scope-parent (`prj-…`); для γ-containment на project-scope |
| `parent_account_id` | TEXT | scope-parent (`acc-…`); пусто, если compute не резолвит (γ дополнит из `projects.account_id` same-DB) |
| `labels` | JSONB NOT NULL DEFAULT '{}' | CHECK `jsonb_typeof='object'`; GIN-индекс (γ `@>` selector probe) |
| `source_version` | TIMESTAMPTZ NOT NULL DEFAULT '-infinity' | монотонный маркер (compute `now()@emit`) |
| `updated_at` | TIMESTAMPTZ | время применения |

- **PK (object_type, object_id)** — одна строка на объект; основа UPSERT-идемпотентности.
- **GIN на labels** — `jsonb_ops` (γ может потребовать key-exists; для чистого `@>` рассмотреть `jsonb_path_ops`).

## Lifecycle / инварианты

- **RegisterResource** (compute-drainer, mTLS :9091): UPSERT mirror **co-commit** с
  owner-tuple emit в ОДНОЙ writer-tx (ban #10, атомарно — не dual-write).
  Эмитится на Instance **Create** И **Update(labels в mask)** (β-04; non-labels Update
  → no-op, β-04b). Disk/Image/Snapshot — labels несут тем же payload.
- **Monotonic ordering (β-hardening, last-source-state-wins):** UPSERT condition
  `… WHERE resource_mirror.source_version < EXCLUDED.source_version` — stale intent
  (reorder под HA-drainer) → no-op. Закрывает lost-update (system-design finding).
  Unregister — tombstone `DELETE … WHERE source_version <= $tombstone`.
- **Unregister** (Delete ресурса): DELETE mirror + owner-tuple в одной tx (β-07).
- **Idempotency**: at-least-once drainer retry → ON CONFLICT DO UPDATE no-op.
- **Validation**: labels — `corevalidate.Labels` sanity (невалидные → InvalidArgument,
  β-15) + DB CHECK jsonb-object (defense-in-depth).
- **Граница β:** mirror **НЕ читается для authz** в β — только наполняется. Чтение
  (selector-матч + containment-гейт) — **γ**.

## Gotchas

- **Delete-после-Update reorder residual edge:** stale `register` ПОСЛЕ `unregister`
  (строки нет → INSERT воскрешает) — оставлен **γ reconcile-sweep** (benign в β,
  mirror не authz; by-design `kacho-iam/docs/architecture/resource-mirror-source-version.md`).
- `parent_account_id` пуст от compute → γ дополняет IAM same-DB lookup `projects.account_id`.
- Dangling (объект исчез без Unregister) — строка переживает, не паника, не каскад.

## See also

[[iam-access-binding]] [[../rpc/iam-internal-iam-service]] [[../edges/compute-to-iam-fgaproxy]] [[../KAC/epic-100-resource-scoped-access-binding]]

#resource #kacho-iam #iam #cross-service
