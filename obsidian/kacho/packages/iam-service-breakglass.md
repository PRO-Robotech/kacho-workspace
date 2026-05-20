---
title: "iam internal/service/breakglass"
aliases:
  - iam break-glass
  - breakglass
  - 2-person approve
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
  - breakglass
---

# iam `internal/service/breakglass`

Phase 7 — Break-Glass workflow: emergency cluster-admin grant с 2-person approval, 2h TTL, mandatory justification, alert на activation.

## State machine (6 states)

```
DRAFT ─request─▶ AWAITING_APPROVE ─approve─▶ ACTIVE ─[expires_at|revoke]─▶ EXPIRED
   │                  │                                              │
   │                  └─reject─▶ REJECTED                            │
   │                                                                 │
   └─cancel─▶ CANCELLED                                              │
                                                                     │
                                          ◀───revoke (admin)─────────┘
```

| State | Transitions | Notes |
|---|---|---|
| `DRAFT` | → AWAITING_APPROVE, CANCELLED | initial — initiator authoring request |
| `AWAITING_APPROVE` | → ACTIVE, REJECTED, CANCELLED | locked — initiator can cancel; **different** admin approves |
| `ACTIVE` | → EXPIRED, REVOKED | activated; cluster:cluster_kacho_root#system_admin granted |
| `EXPIRED` | terminal | TTL reached (worker marks) |
| `REJECTED` | terminal | approver rejected |
| `CANCELLED` | terminal | initiator cancelled |

## Use-cases

- `RequestBreakGlassUseCase` — initiator opens request с justification (length >50 chars; "EMERGENCY" prefix).
- `ApproveBreakGlassUseCase` — different admin signs off; idempotent if pre-approved.
- `RejectBreakGlassUseCase` — abort.
- `CancelBreakGlassUseCase` — initiator cancels.
- `RevokeBreakGlassUseCase` — any admin revokes ACTIVE grant (kill-switch).

## 2-person enforcement (DB invariant)

```sql
ALTER TABLE cluster_break_glass_grants
  ADD CONSTRAINT bgg_different_admins
  CHECK (initiator_id != approver_id OR state IN ('DRAFT','CANCELLED','REJECTED'));
```

→ approver ≠ initiator atomically; any UPDATE setting approver=initiator → 23514 → InvalidArgument.

## TTL enforcement (Phase 7 worker)

```go
type BreakGlassExpiryWorker struct {
    Repo  BreakGlassRepo
    Bindings AccessBindingWriter
    Alerts AlertEmitter
}

// Every minute: SELECT WHERE state=ACTIVE AND expires_at < now() FOR UPDATE → state=EXPIRED.
// Cascade: revoke associated AccessBinding (cluster:cluster_kacho_root#system_admin).
// Emit CAEP iam.break_glass.expired + audit.
```

## Alerts (Phase 7)

- On `ACTIVE` transition → **immediate alerts**:
  - PagerDuty page (high-severity).
  - Slack `#kacho-security` with initiator+approver+justification.
  - Email to security-team@.
  - CAEP `iam.break_glass.activated` to downstream subscribers.
  - Audit-pipeline + SIEM Datadog/Splunk.

## Expiry / revoke flow

- TTL max 2h (DB-CHECK `granted_until - granted_at <= interval '2 hours'`).
- During active window, grant holder can perform cluster-admin RPCs (FGA tuple resolves to system_admin).
- On EXPIRED / REVOKED → tuple deleted, ALL active sessions of grant-holder revoked (CAEP session.revoked).

## Imports

- `internal/domain` — BreakGlassGrant + state newtype
- `internal/repo/kacho/pg`
- `internal/notify` — PagerDuty/Slack adapters
- `internal/service/audit`

## Imported by

- `internal/handler/grpc/break_glass_handler.go` (Phase 7 follow-up; proto-stubs pending — см. KAC-127 "Out of scope")
- `cmd/kacho-iam/main.go`

## See also

[[iam-service-jit]] [[../resources/iam-cluster-break-glass-grant]] [[../resources/iam-cluster]] [[../runbooks/README|runbooks/break-glass-procedure]] [[../KAC/KAC-127]]

#packages #kacho-iam #service #breakglass
