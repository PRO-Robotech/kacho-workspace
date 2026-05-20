---
title: "iam internal/service/federation"
aliases:
  - iam federation
  - sa key
  - rfc8693
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
  - federation
  - oauth
---

# iam `internal/service/federation`

Phase 5 — Workload Identity Federation: SA Class A static OAuth + RFC 8693 Token Exchange для 8 external IdPs.

## Sub-packages

- `tokenexchange/` — RFC 8693 Exchange use-case ([[../rpc/iam-federation-exchange-service]]).
- `trustpolicy/` — CRUD federation_trust_policies ([[../rpc/iam-trust-policy-service]]).
- `sakey/` — SA OAuth client CRUD ([[../rpc/iam-sa-key-service]]).

## 8 providers (Phase 5)

| Provider | OIDC Issuer | Subject claim |
|---|---|---|
| GitHub Actions | `https://token.actions.githubusercontent.com` | `repo:OWNER/REPO:ref:refs/heads/BRANCH` |
| AWS STS | `https://sts.amazonaws.com` | aws-arn |
| GCP | `https://accounts.google.com` | service-account email |
| GitLab CI | `https://gitlab.com` | project_path/job env |
| CircleCI | `https://oidc.circleci.com/org/{org_id}` | org-context |
| Buildkite | `https://agent.buildkite.com` | agent-name+job-id |
| Bitbucket Pipelines | `https://api.bitbucket.org/2.0/workspaces/{ws}/pipelines-config/identity/oidc` | repo-id |
| Generic OIDC | (configurable) | per-policy regex |

## Use-cases (Phase 5)

```go
// internal/service/federation/tokenexchange/exchange.go
type ExchangeUseCase struct {
    JWKSCache         JWKSCacheClient   // → IdP JWKS fetcher [[iam-clients-idp-jwks-cache]]
    TrustPolicyRepo   TrustPolicyReader
    JWTSigner         JWTSigner          // → HSM-backed (Phase 9) или software fallback
    AuditEmitter      AuditEmitter
}

func (uc *ExchangeUseCase) Execute(ctx, req) (Token, error) {
    extJWT, _ := jose.Parse(req.SubjectToken)
    jwks := uc.JWKSCache.Get(ctx, extJWT.Header.Kid, extJWT.Claims.Issuer)
    if err := extJWT.VerifySignature(jwks); err != nil { return nil, ErrUnauthenticated }
    
    policies := uc.TrustPolicyRepo.ListByIssuer(ctx, extJWT.Claims.Issuer)
    for _, p := range policies {
        if !p.SubjectPattern.Match(extJWT.Claims.Sub) { continue }
        if !p.AudienceMatch(req.Audience) { continue }
        if !uc.evaluateCondition(p.ConditionID, extJWT, ctx) { continue }
        
        kachoTok := uc.JWTSigner.Sign(jwt.NewClaims(
            "sub": p.ServiceAccountID,
            "aud": req.Audience,
            "exp": time.Now().Add(p.MaxTokenTTL),
            "cnf": req.DPoPCnf,
        ))
        uc.AuditEmitter.Emit(ctx, "iam.federation.token.issued", ...)
        return kachoTok, nil
    }
    return nil, ErrPermissionDenied
}
```

## Imports

- `internal/domain` — TrustPolicy, FederationToken newtypes
- `gopkg.in/go-jose/go-jose.v3` — JWT parse/verify/sign
- `internal/clients/idp_jwks_cache` — TTL+LRU cache adapter
- `internal/clients/hydra_admin` — для SA OAuth client CRUD

## Imported by

- `internal/handler/grpc/federation_handler.go`
- `internal/handler/grpc/trust_policy_handler.go`
- `internal/handler/grpc/sa_key_handler.go`
- `cmd/kacho-iam/main.go` — composition root

## Tests

- Unit: mocked JWKS + TrustPolicyRepo (table-driven 8 providers × 5 scenarios each).
- Integration: testcontainers Postgres + httptest mock JWKS endpoint.
- E2E: real GitHub OIDC against staging cluster (Phase 5 acceptance §"GitHub Actions sample workflow").

## See also

[[iam-clients-idp-jwks-cache]] [[../rpc/iam-federation-exchange-service]] [[../rpc/iam-trust-policy-service]] [[../rpc/iam-sa-key-service]] [[../resources/iam-federation-trust-policy]] [[../resources/iam-service-account-oauth-client]] [[../edges/iam-to-hydra-admin]] [[../KAC/KAC-127]]

#packages #kacho-iam #service #federation #oauth
