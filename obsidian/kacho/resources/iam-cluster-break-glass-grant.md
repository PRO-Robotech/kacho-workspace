---
title: ClusterBreakGlassGrant
aliases:
  - ClusterBreakGlassGrant (iam)
  - BreakGlassGrant
  - break_glass_grant
category: resource
domain: iam
id_prefix: bgg
owner_table: kacho_iam.cluster_break_glass_grants
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc:
  - "[[rpc/iam-internal-cluster-service]]"
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
  - internal
---

# ClusterBreakGlassGrant

**Domain**: iam — emergency 2-person approve grant с обязательным TTL.
**ID prefix**: `bgg_` + 17-char crockford → `^bgg_[0-9a-hjkmnp-tv-z]{17}$`.
**Owner table**: `kacho_iam.cluster_break_glass_grants` (migration 0011).
**Visibility**: **internal-only**.
**Phase 1**: schema-only. State machine + 2-person approve flow — Phase 7.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^bgg_[0-9a-hjkmnp-tv-z]{17}$` | |
| `cluster_id` | TEXT | FK → clusters(id) RESTRICT | NOT NULL |
| `subject_type` | TEXT | CHECK `IN ('user','service_account')` | individual identity (NOT group) |
| `subject_id` | TEXT | length 1..64 | |
| `state` | TEXT | CHECK enum (см. ниже) | 6-state machine |
| `requested_by_user_id` | TEXT | FK → users(id) RESTRICT | initiator |
| `requested_at` | TIMESTAMPTZ | server-set | |
| `approver_a_user_id` | TEXT NULL | FK → users(id) RESTRICT | first approver |
| `approver_a_at` | TIMESTAMPTZ NULL | | |
| `approver_b_user_id` | TEXT NULL | FK → users(id) RESTRICT | second approver |
| `approver_b_at` | TIMESTAMPTZ NULL | | |
| `activated_at` | TIMESTAMPTZ NULL | | when state → ACTIVE |
| `revoked_at` | TIMESTAMPTZ NULL | | |
| `revoked_by_user_id` | TEXT NULL | FK → users(id) RESTRICT | |
| `expires_at` | TIMESTAMPTZ | **NOT NULL**, CHECK `> requested_at` | OPA enforces `≤2h` (Phase 3) |
| `rationale` | TEXT | length <=2048 | |

## State machine (6-state)

```
AWAITING_APPROVAL_A → AWAITING_APPROVAL_B → ACTIVE → EXPIRED
                                                   → REVOKED
                                          → DENIED
```

DB CHECK `state IN ('AWAITING_APPROVAL_A','AWAITING_APPROVAL_B','ACTIVE','EXPIRED','DENIED','REVOKED')`.

## Constraints / indexes

- `cluster_break_glass_grants_pkey` PRIMARY KEY (id)
- `cluster_break_glass_grants_cluster_fk` FK → `clusters(id)` RESTRICT
- 4× FK на `users(id)` (requested_by, approver_a, approver_b, revoked_by) — все RESTRICT
- CHECK: id-regex, subject_type-enum, state-enum, `expires_at > requested_at`, rationale-length

## Lifecycle (Phase 7 enforcement)

1. **Request**: user requests → INSERT (state=`AWAITING_APPROVAL_A`, expires_at установлен, rationale required).
2. **Approve A**: separate user → atomic CAS UPDATE (state `AWAITING_APPROVAL_A → AWAITING_APPROVAL_B`, set approver_a_*); CHECK approver_a ≠ requested_by.
3. **Approve B**: third user → CAS UPDATE (state `AWAITING_APPROVAL_B → ACTIVE`, set approver_b_*, activated_at); CHECK approver_b ∉ {requested_by, approver_a}.
4. **Expire**: background worker → state=`EXPIRED` при `now > expires_at` и state=`ACTIVE`.
5. **Revoke**: user → CAS UPDATE (state `ACTIVE → REVOKED`, set revoked_*).
6. **Deny**: approver A/B reject → CAS UPDATE (state → `DENIED`).

## Gotchas

- `expires_at NOT NULL` — намеренно (DB-enforced). OPA-policy Phase 3 enforces ≤2h delta.
- 2-person approve = **2 different users** ≠ requester — Phase 7 service-layer проверит (нет DB-CHECK на это — 3-way row comparison).
- Все state-transitions через atomic CAS-UPDATE (workspace `CLAUDE.md` запрет #10); никаких TOCTOU `SELECT → CHECK → UPDATE`.
- Audit + CAEP push на каждый state-change (acceptance §6.10).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[../rpc/iam-internal-cluster-service]] [[iam-cluster]] [[iam-cluster-admin-grant]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam #internal
