---
title: AccessReviewItem
aliases:
  - AccessReviewItem (iam)
  - access_review_item
category: resource
domain: iam
id_prefix: ari
owner_table: kacho_iam.access_review_items
owner_db: kacho_iam
folder_level: false
status: planned
related_rpc: []
related_packages:
  - "[[packages/iam-domain]]"
  - "[[packages/iam-repo-kacho-pg]]"
related_tickets:
  - "[[KAC-127]]"
tags:
  - resource
  - kacho-iam
  - iam
---

# AccessReviewItem

**Domain**: iam — composition child of [[iam-access-review|AccessReview]]: одна row на каждый ACTIVE AccessBinding в review-scope. Reviewer marks `keep | revoke | unanswered`.
**ID prefix**: `ari_` + `[a-z0-9_]{1,40}` → `^ari_[a-z0-9_]{1,40}$`.
**Owner table**: `kacho_iam.access_review_items` (migration 0014).
**Phase 1**: schema-only. Item-decision RPC — Phase 7.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^ari_[a-z0-9_]{1,40}$` | |
| `access_review_id` | TEXT | FK → access_reviews(id) CASCADE | NOT NULL |
| `access_binding_id` | TEXT | FK → access_bindings(id) RESTRICT | NOT NULL — snapshot |
| `decision` | TEXT | CHECK enum | `unanswered` (initial) / `keep` / `revoke` |
| `decided_at` | TIMESTAMPTZ NULL | required ⇔ decision != unanswered | |
| `rationale` | TEXT NULL | length <=2048 | optional, обычно для `revoke` |

## State machine

```
unanswered (initial) → keep   (terminal)
                     → revoke (terminal)
```

DB CHECK `decision IN ('unanswered','keep','revoke')` + service-CHECK consistency invariant `decision='unanswered' ⇔ decided_at IS NULL`.

## Constraints / indexes

- `access_review_items_pkey` PRIMARY KEY (id)
- `access_review_items_review_fk` FK → `access_reviews(id)` ON DELETE CASCADE
- `access_review_items_binding_fk` FK → `access_bindings(id)` ON DELETE RESTRICT — нельзя удалить binding пока есть unresolved review item на него
- Index: `(access_review_id, decision)` — для UI progress

## Lifecycle (Phase 7)

1. **Schedule**: review-cron при создании AccessReview → INSERT items для всех ACTIVE bindings в Account (`decision='unanswered'`).
2. **Decide**: reviewer marks → CAS UPDATE (`WHERE id=$id AND decision='unanswered'` → set decision + decided_at + rationale).
3. **Process (on review completion)**: items с `decision='revoke'` → trigger AccessBinding revocation flow (status `ACTIVE → REVOKED`, audit, CAEP push).
4. **Cleanup**: CASCADE на AccessReview-delete; RESTRICT на AccessBinding-delete (нужно сначала resolve item).

## Gotchas

- RESTRICT FK на AccessBinding — намеренно: cannot delete an under-review binding without resolving review-item.
- `rationale` — обычно required для `revoke` (UX-policy, не DB-enforced).
- Snapshot semantics: item привязан к binding-id momentary; если binding изменился между schedule + decision — reviewer видит current state (not snapshot of attrs).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[iam-access-review]] [[iam-access-binding]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
