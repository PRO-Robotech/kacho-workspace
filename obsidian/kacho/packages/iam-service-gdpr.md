---
title: "iam internal/service/gdpr"
aliases:
  - iam gdpr
  - article 17
  - erasure
category: packages
repo: kacho-iam
layer: service
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - service
  - gdpr
  - compliance
---

# iam `internal/service/gdpr`

Phase 7 — GDPR Article 17 "Right to Erasure" pipeline. 30-day cool-off + hard-delete + cross-domain coordination.

## State machine

```
REQUESTED ─cooloff_complete─▶ APPROVED ─execute─▶ EXECUTED
   │                             │                   │
   │                             └─cancelled─▶ CANCELLED (anywhere)
   │
   └─cancelled (within 30d)─▶ CANCELLED
```

## Use-cases

- `RequestErasureUseCase` — user (or admin on user's behalf) creates erasure request.
  - INSERT `gdpr_erasure_requests` (state=REQUESTED, cooloff_end_at = now()+30d).
  - Soft-disable user.
  - Revoke all sessions (CAEP).
  - Email user "We have received your erasure request. Reversible until 2026-06-19."
- `CancelErasureUseCase` — user changes mind during 30d → state=CANCELLED + re-enable.
- `ExecuteErasureUseCase` — worker invokes after cooloff_end_at:
  - Coordinate cross-domain (kacho-iam, kacho-vpc, kacho-compute) hard-delete.
  - Anonymize audit-pipeline (S3 Object Lock → replace PII with `[erased]`).
  - Hard-delete Kratos identity ([[../edges/iam-to-kratos-admin]]).
  - Hard-delete kacho User row.
  - State=EXECUTED.

## Cool-off worker

```go
type GDPRCoolOffWorker struct {
    Requests   GDPRRepo
    Execute    *ExecuteErasureUseCase
}

// Every hour: SELECT WHERE state=REQUESTED AND cooloff_end_at < now() FOR UPDATE → state=APPROVED.
// Spawn ExecuteErasureUseCase async.
```

## Cross-domain erasure coordination

GDPR erasure NOT same-DB cascade (запрет #4). Each service receives erasure event via CAEP `iam.user.disabled` (Phase 8) + `iam.user.erased` (Phase 7) and is responsible for own data:

| Domain | Action |
|---|---|
| `kacho-iam` | Hard-delete User, AccessBindings, SCIM mappings, JIT eligibilities, all sessions. |
| `kacho-vpc` | Anonymize resources owned by user (replace user_id с `[erased]` in audit rows). Resources themselves NOT deleted (owned by Project; transfer ownership к Account-level if user was sole owner). |
| `kacho-compute` | Same — anonymize user_id. |
| Audit pipeline | S3 lifecycle: re-write rows с PII redacted (`merkle_root` recomputed; `audit_signing_batches` row updated). |

Each domain emits `iam.gdpr.<domain>.erasure.complete` → coordinator marks state=EXECUTED only after all domains acked.

## Verification

After EXECUTED: 7d delayed re-scan all domains for residual `user_id` references → if found, alert + create follow-up bug.

## Imports

- `internal/domain` — GDPRRequest
- `internal/repo/kacho/pg`
- `internal/service/caep` — emit erasure events
- `internal/clients/kratos_admin` — destroy identity
- `internal/notify` — email user

## Imported by

- `internal/handler/grpc/gdpr_handler.go` (Phase 7 follow-up; proto pending)
- `cmd/kacho-iam/main.go` — cooloff worker

## See also

[[iam-service-access-review]] [[../resources/iam-gdpr-erasure-request]] [[../resources/iam-user]] [[../runbooks/README|runbooks/gdpr-erasure-workflow]] [[../edges/iam-to-kratos-admin]] [[../KAC/KAC-127]]

#packages #kacho-iam #service #gdpr #compliance
