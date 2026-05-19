---
title: AccessReview
aliases:
  - AccessReview (iam)
  - access_review
  - quarterly recertification
category: resource
domain: iam
id_prefix: arv
owner_table: kacho_iam.access_reviews
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

# AccessReview

**Domain**: iam — quarterly recertification campaign по AccessBinding'ам конкретного Account (compliance: SOC 2 CC6.2 + ISO 27001 A.9.2.5). Содержит N [[iam-access-review-item|AccessReviewItem]] детей.
**ID prefix**: `arv_` + `[a-z0-9_]{1,40}` → `^arv_[a-z0-9_]{1,40}$`.
**Owner table**: `kacho_iam.access_reviews` (migration 0014).
**Phase 1**: schema-only. Review-CRUD + cron-generator — Phase 7.

## Fields

| Field | Type | Validation | Note |
|---|---|---|---|
| `id` | TEXT PK | `^arv_[a-z0-9_]{1,40}$` | |
| `account_id` | TEXT | FK → accounts(id) RESTRICT | NOT NULL — review scope |
| `scheduled_at` | TIMESTAMPTZ | NOT NULL | when review must happen |
| `status` | TEXT | CHECK enum | `scheduled` / `in_progress` / `completed` / `cancelled` |
| `reviewer_user_id` | TEXT | FK → users(id) RESTRICT | NOT NULL — assignee |
| `completed_at` | TIMESTAMPTZ NULL | | required ⇔ status=completed |
| `created_at` | TIMESTAMPTZ | server-set | |

## State machine (4-state)

```
scheduled → in_progress → completed (terminal)
                        → cancelled (terminal)
```

DB CHECK `status IN ('scheduled','in_progress','completed','cancelled')` + service-CHECK `completed_at IS NOT NULL ⇔ status='completed'`.

## Constraints / indexes

- `access_reviews_pkey` PRIMARY KEY (id)
- `access_reviews_account_fk` FK → `accounts(id)` ON DELETE RESTRICT
- `access_reviews_reviewer_fk` FK → `users(id)` ON DELETE RESTRICT
- CHECK: id-regex, status-enum

## Lifecycle (Phase 7)

1. **Schedule (cron)**: per Account → INSERT каждый квартал; auto-fill items snapshot всех ACTIVE AccessBindings в Account.
2. **Start**: reviewer → CAS UPDATE (status `scheduled → in_progress`).
3. **Decide per item**: reviewer goes через items, mark `keep | revoke` (см. [[iam-access-review-item]]).
4. **Complete**: все items решены → CAS UPDATE (status `in_progress → completed`, completed_at=now); items с `revoke` → trigger AccessBinding state → `REVOKED` (via outbox + audit + CAEP push).
5. **Cancel**: admin → CAS UPDATE (status → `cancelled`).

## Gotchas

- `account_id` immutable (review всегда per-account).
- Reviewer ≠ subject принципиально не enforced на DB-уровне (logical-conflict пишется в audit).
- Default policy: open items > 30 days после `scheduled_at` → alert PagerDuty (Phase 11 observability).

## See also

[[../packages/iam-domain]] [[../packages/iam-repo-kacho-pg]] [[iam-access-review-item]] [[iam-account]] [[iam-access-binding]] [[../KAC/KAC-127]]

#resource #kacho-iam #iam
