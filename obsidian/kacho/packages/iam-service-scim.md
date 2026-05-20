---
title: "iam internal/service/scim"
aliases:
  - iam scim
  - scim provisioning
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
  - scim
  - sso
---

# iam `internal/service/scim`

Phase 6 — SCIM 2.0 user/group provisioning (RFC 7644). Inbound only — kacho-iam is **Service Provider**, external IdPs (Okta / Entra / Google) — clients.

## Use-cases

- `ProvisionUserUseCase` — JIT-create / update existing kacho User from SCIM `POST /Users`.
- `DeactivateUserUseCase` — `PATCH active=false` → soft-disable + session revoke + GDPR cool-off start.
- `SyncGroupUseCase` — push group membership changes.
- `LookupByExternalIDUseCase` — `(org_id, scim_external_id) → user_id`.
- `BootstrapOrganizationSCIMUseCase` — generate bearer secret for new Organization.

## Mapping logic

```go
// internal/service/scim/provision_user.go
type ProvisionUserUseCase struct {
    Users           UserRepo            // kacho_iam.users
    Mappings        SCIMMappingRepo     // kacho_iam.scim_user_mappings
    KratosClient    KratosAdminClient   // [[../edges/iam-to-kratos-admin]]
    AuditEmitter    AuditEmitter
}

func (uc *ProvisionUserUseCase) Execute(ctx, req SCIMUser) (User, error) {
    return uc.Users.WithTx(ctx, func(tx Tx) (User, error) {
        // 1. Lookup by mapping
        if uid, found := uc.Mappings.LookupByExternal(ctx, req.OrgID, req.ExternalID); found {
            u := uc.Users.Get(ctx, uid)
            uc.Users.Update(ctx, u, scimUpdate(req))  // idempotent
            return u, nil
        }
        // 2. Create new kacho User + map
        user := domain.NewUser(req.UserName, req.Emails[0].Value, ...)
        uc.Users.Create(ctx, user)
        uc.Mappings.Create(ctx, SCIMMapping{OrgID: req.OrgID, ExternalID: req.ExternalID, UserID: user.ID})
        uc.KratosClient.CreateIdentity(ctx, kratosIdentity(user))
        uc.AuditEmitter.Emit(ctx, "iam.scim.user.provisioned", user)
        return user, nil
    })
}
```

## Authentication helper

```go
type SCIMAuthValidator struct {
    Organizations OrganizationReader
}

func (a *SCIMAuthValidator) Verify(ctx, orgID, bearer) error {
    org := a.Organizations.Get(ctx, orgID)
    if subtle.ConstantTimeCompare(org.SCIMSecretHash, hashSecret(bearer)) != 1 {
        return ErrUnauthenticated
    }
    return nil
}
```

## Rate limiting

Token-bucket per-org (`internal/middleware/scim_rate_limiter.go`, default 100 req/s, configurable per-org).

## Imports

- `internal/domain` — User, SCIMMapping
- `internal/repo/kacho/pg` — UserRepo + SCIMMappingRepo
- `internal/clients/kratos_admin`

## Imported by

- `internal/handler/scim/{users,groups,config}_handler.go` — REST handler (port 9093)
- `cmd/kacho-iam/main.go`

## Tests

- Unit: table-driven SCIM operations (8 ops × 3 IdP-quirks variants).
- Integration: full RFC 7644 conformance suite (third-party SCIM compliance tool).
- E2E: Okta sandbox → real provisioning round-trip (Phase 6 DoD).

## See also

[[../rpc/iam-scim-v2]] [[../resources/iam-scim-user-mapping]] [[../resources/iam-organization]] [[../resources/iam-user]] [[../edges/iam-to-scim-okta]] [[../edges/iam-to-scim-azure]] [[../edges/iam-to-scim-google]] [[../edges/iam-to-kratos-admin]] [[../KAC/KAC-127]]

#packages #kacho-iam #service #scim #sso
