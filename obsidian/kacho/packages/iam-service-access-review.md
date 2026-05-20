---
title: "iam internal/service/access_review"
aliases:
  - iam access review
  - recertification
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
  - access-review
---

# iam `internal/service/access_review`

Phase 7 — Microsoft Entra ID-style **Access Reviews** (recertification). Periodic (quarterly default) admin re-validation of who has access to what.

## Concepts

- **Review** — `access_reviews` row: scope (account / project / role), schedule (quarterly cadence), reviewer_id, start/end window.
- **Review Item** — `access_review_items` row per (review_id, binding_id): decision (approve / revoke / abstain) + justification.

## Use-cases

- `ScheduleReviewUseCase` — admin creates review schedule (cadence + scope + reviewer).
- `OpenReviewUseCase` — worker materializes review items для текущего window (snapshots active bindings).
- `ReviewBindingUseCase` — reviewer marks item approve/revoke/abstain + optional comment.
- `CloseReviewUseCase` — apply decisions: for `revoke` → AccessBinding.status=REVOKED + CAEP push.
- `BulkApproveUseCase` — reviewer bulk-approves (e.g., "approve all" for routine bindings).
- `GenerateReportUseCase` — PDF/CSV report для compliance (SOC 2, ISO 27001).

## Schedule worker

```go
type AccessReviewScheduler struct {
    Reviews   AccessReviewRepo
    Items     AccessReviewItemRepo
    Bindings  AccessBindingReader
    Notify    Notifier
}

// Cron daily check:
// - For each Review with state=SCHEDULED AND next_open_at <= now():
//     Materialize Items from current bindings in scope.
//     Set state=OPEN, end_at=now() + window (default 14d).
//     Notify reviewer (Slack DM + email).
// - For OPEN with end_at < now():
//     Auto-decide unresponded items (default: abstain → keep binding; configurable to revoke).
//     state=CLOSED.
```

## Bulk apply

Closing review:
```go
func (uc *CloseReviewUseCase) Execute(ctx, reviewID) error {
    items := uc.Items.ListByReview(ctx, reviewID)
    return uc.Bindings.WithTx(ctx, func(tx Tx) error {
        for _, item := range items {
            if item.Decision == "revoke" {
                uc.Bindings.SetStatus(ctx, item.BindingID, REVOKED, revokedAt: time.Now())
                uc.CAEP.Emit(ctx, item.Subject, "session.revoked")
            }
        }
        uc.Reviews.SetState(ctx, reviewID, CLOSED)
        return nil
    })
}
```

## Audit + Notify

- `iam.access_review.opened` event audit.
- `iam.access_review.binding.revoked` per-revocation event.
- `iam.access_review.closed` + summary (count approved/revoked/abstained).

## Imports

- `internal/domain` — AccessReview, AccessReviewItem newtypes
- `internal/repo/kacho/pg`
- `internal/service/caep` — emit revocation events
- `internal/notify` — Slack DM / email

## Imported by

- `internal/handler/grpc/access_review_handler.go` (Phase 7 follow-up; proto pending)
- `cmd/kacho-iam/main.go` — scheduler worker

## Reports format

PDF + CSV downloadable via signed-URL.
Schema: review_id, scope, reviewer, start, end, items_count, approved_count, revoked_count, abstained_count, items[].

## See also

[[iam-service-jit]] [[iam-service-gdpr]] [[../resources/iam-access-review]] [[../resources/iam-access-review-item]] [[../KAC/KAC-127]]

#packages #kacho-iam #service #access-review
