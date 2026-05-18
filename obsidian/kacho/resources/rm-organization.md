---
title: Organization
aliases:
  - Organization (organizationmanager)
  - om Organization
category: resource
domain: organizationmanager
id_prefix: bpf
owner_table: kacho_rm.organizations
owner_db: kacho_rm
folder_level: false
hierarchy: root
status: stable
related_rpc:
  - "[[rpc/rm-organization-service]]"
  - "[[rpc/om-organization-service]]"
related_packages:
  - "[[packages/proto-organizationmanager]]"
tags:
  - resource
  - kacho-rm
  - organization
  - root
---

# Organization

**Domain**: organizationmanager (обслуживается `kacho-resource-manager`)
**ID prefix**: `bpf`
**Owner table**: `kacho_rm.organizations`
**Hierarchy**: root уровня — родительский для Cloud.

## Fields

| Field | Type | Note |
|---|---|---|
| `id` | TEXT PK | `bpf<…>` |
| `name` | TEXT | uniqueness — global per platform |
| `description` | TEXT | |
| `labels` | JSONB | |
| `created_at` | TIMESTAMP | |

## FK (out-bound)

- `clouds.organization_id → organizations(id)` — RESTRICT (в same DB `kacho_rm`).

## Lifecycle

ACTIVE. Delete → FailedPrecondition если есть Cloud.

## IAM placeholders

В proto есть `SetAccessBindings`/`BindAccessPolicy`/... — это placeholders для `kacho-iam` (blocked). Сейчас RPC возвращают `Unimplemented` (или скелетная реализация без enforcement).

## See also

[[../packages/proto-organizationmanager]] [[../rpc/rm-organization-service]]

#resource #kacho-rm #organization #root
