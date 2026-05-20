---
title: "iam internal/service/jit"
aliases:
  - iam jit
  - jit pim
  - eligibility
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
  - jit
  - pim
---

# iam `internal/service/jit`

Phase 7 — Just-In-Time / Privileged Identity Management (Microsoft Entra-style). Eligibility + activate (time-bound, justification, MFA-fresh).

## Use-cases

- `CreateEligibilityUseCase` — admin grants user JIT eligibility for role (max_duration configurable, default 8h cap).
- `ActivateJITUseCase` — user requests activation: justification text, requested_duration, MFA-fresh check.
- `RenewActivationUseCase` — within active window, extend up to max_duration.
- `RevokeEligibilityUseCase` — admin revokes upcoming eligibility.
- `ListPendingActivationsUseCase` — for admin approval (if eligibility requires approve).
- `ApproveActivationUseCase` — admin (or second admin if 2-approve) sign-off (Phase 7 mode).

## Eligibility vs activation

```
Eligibility (long-term)             Activation (short-term)
─────────────────────────           ─────────────────────────
INSERT access_binding_jit_eligibility    INSERT access_binding с status=ACTIVE
  user_id, role_id, scope, max_dur          + expires_at = now() + duration
                                            + condition_id (mfa_required=true, etc.)
status=ELIGIBLE (always)                  status=ACTIVE during window
                                            → REVOKED when expires_at reached (worker)
```

## Activation flow

```go
type ActivateJITUseCase struct {
    Eligibilities    JITEligibilityRepo
    Bindings         AccessBindingWriter
    Conditions       ConditionReader
    AuditEmitter     AuditEmitter
}

func (uc *ActivateJITUseCase) Execute(ctx, req ActivateJITRequest) (AccessBinding, error) {
    elig := uc.Eligibilities.Get(ctx, req.EligibilityID)
    if elig.UserID != req.CallerID { return nil, ErrPermissionDenied }
    if elig.RequiresApproval && req.ApproverID == "" { return nil, ErrFailedPrecondition("approver required") }
    if !mfaFresh(ctx, 5*time.Minute) { return nil, ErrFailedPrecondition("MFA stale") }
    
    duration := min(req.Duration, elig.MaxDuration)
    if duration > 8*time.Hour { return nil, ErrInvalidArgument("max 8h") }
    
    binding := AccessBinding{
        Subject:    "user:" + req.CallerID,
        RoleID:     elig.RoleID,
        Scope:      elig.Scope,
        Status:     ACTIVE,
        GrantedBy:  "jit:" + elig.ID,
        ExpiresAt:  time.Now().Add(duration),
        ConditionID: &elig.ConditionID,
    }
    uc.Bindings.Create(ctx, binding)
    uc.AuditEmitter.Emit(ctx, "iam.jit.activated", binding)
    return binding, nil
}
```

## Auto-revocation worker

```go
type JITExpiryWorker struct {
    Bindings   AccessBindingWriter
    Notify     CAEPEmitter
}

// Every minute: SELECT WHERE expires_at < now() AND status = ACTIVE FOR UPDATE → mark REVOKED.
// Emit CAEP session.revoked.
```

## Imports

- `internal/domain` — JITEligibility, AccessBinding
- `internal/repo/kacho/pg` — repo adapters

## Imported by

- `internal/handler/grpc/jit_eligibility_handler.go` (Phase 7 follow-up — handler depends on proto-stub which not yet in kacho-proto, see KAC-127 "Out of scope" note)
- `cmd/kacho-iam/main.go`

## Tests (Phase 7 implemented в commit `a6caf51`)

- Unit: 100% use-case coverage table-driven.
- Integration: testcontainers Postgres + concurrent activation race (idempotent).
- 86 tests total в Phase 7 (per KAC-127 trail).

## See also

[[iam-service-breakglass]] [[iam-service-access-review]] [[../resources/iam-jit-eligibility]] [[../resources/iam-access-binding]] [[../resources/iam-condition]] [[../KAC/KAC-127]]

#packages #kacho-iam #service #jit #pim
