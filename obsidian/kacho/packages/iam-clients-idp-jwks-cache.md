---
title: "iam internal/clients/idp_jwks_cache"
aliases:
  - idp jwks cache
  - jwks cache
category: packages
repo: kacho-iam
layer: clients
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - clients
  - federation
---

# iam `internal/clients/idp_jwks_cache`

Phase 5 — TTL + LRU cache external IdP JWKS endpoints. Reduces latency federation Exchange + survives transient IdP outages.

## Exported API

```go
type JWKSCache interface {
    Get(ctx context.Context, issuer string, kid string) (*jose.JSONWebKey, error)
    Refresh(ctx context.Context, issuer string) error  // force re-fetch
    HealthCheck(ctx context.Context) error
}
```

## Architecture

```
Exchange RPC arrives →
  cache.Get(issuer, kid):
    1. Check in-memory LRU (1MB, configurable)
    2. Miss → HTTP GET jwks_uri (resolved from issuer/.well-known/openid-configuration)
    3. Parse JWK set, filter by kid
    4. Cache TTL = min(Cache-Control max-age, KACHO_IAM_JWKS_CACHE_TTL_MAX=3600s)
    5. Return key
```

## Configuration

| ENV | Default | Description |
|---|---|---|
| `KACHO_IAM_JWKS_CACHE_TTL_DEFAULT_S` | 600 | TTL if no Cache-Control |
| `KACHO_IAM_JWKS_CACHE_TTL_MAX_S` | 3600 | upper bound |
| `KACHO_IAM_JWKS_CACHE_SIZE_MB` | 16 | LRU max size |
| `KACHO_IAM_JWKS_TIMEOUT_MS` | 3000 | per-fetch HTTP timeout |
| `KACHO_IAM_JWKS_STALE_TOLERATE_S` | 86400 | serve stale during IdP outage |

## Stale-while-revalidate

```
fetch fail + cached entry exists + (now - fetched_at) < stale_tolerate:
  → return stale entry (Phase 5 acceptance §"resilient federation")
  → emit metric kacho_iam_jwks_stale_serve_total{issuer}
  → continue async re-fetch attempt
```

→ IdP downtime ≤24h doesn't fail federation Exchange.

## Pre-warming

Composition root invokes `Refresh` for known trust-policy issuers at boot — populates cache before first request.

## Known IdP JWKS endpoints (Phase 5)

| Issuer | jwks_uri |
|---|---|
| https://token.actions.githubusercontent.com | `/.well-known/jwks` |
| https://sts.amazonaws.com | `/.well-known/jwks_uri` (custom OIDC) |
| https://accounts.google.com | `/o/oauth2/v3/certs` |
| https://gitlab.com | `/oauth/discovery/keys` |
| https://oidc.circleci.com | per-org JWKS |
| https://agent.buildkite.com | static via OIDC discovery |
| https://api.bitbucket.org/2.0/workspaces/{ws}/.../pipelines-config/identity/oidc | per-workspace |

## Metrics

- `kacho_iam_jwks_cache_hits_total{issuer}`
- `kacho_iam_jwks_cache_misses_total{issuer}`
- `kacho_iam_jwks_fetch_seconds{issuer}` — histogram
- `kacho_iam_jwks_stale_serve_total{issuer}`

## Imports

- `gopkg.in/go-jose/go-jose.v3` — JWK parse
- `github.com/hashicorp/golang-lru/v2` — LRU
- `net/http`

## Imported by

- `internal/service/federation/tokenexchange` — JWT verify
- `cmd/kacho-iam/main.go` — composition root + pre-warm

## See also

[[iam-service-federation]] [[../rpc/iam-federation-exchange-service]] [[../resources/iam-federation-trust-policy]] [[../resources/iam-jwks-key]] [[../KAC/KAC-127]]

#packages #kacho-iam #clients #federation
