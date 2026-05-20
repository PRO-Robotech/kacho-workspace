---
title: "iam internal/handler/iamhooks"
aliases:
  - iam iamhooks
  - token hook
  - refresh hook
  - caep ingress
category: packages
repo: kacho-iam
layer: handler
status: done
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - handler
  - oauth
---

# iam `internal/handler/iamhooks`

HTTP listener `0.0.0.0:9092` для **Hydra OAuth lifecycle hooks** + **CAEP ingress** (incoming events from upstream IdPs). НЕ gRPC — Hydra-spec REST callbacks.

**Phase 2 implemented (KAC-127 `da2d627e` kacho-iam)** + **Phase 8 ingress planned**.

## Endpoints

| HTTP | Description | Status |
|---|---|---|
| `POST /token_hook` | Hydra OAuth2 token-issuance hook — invoked при каждой ::token:: issuance из Hydra. | Phase 2 done |
| `POST /refresh_hook` | Hydra refresh-token-rotation hook — invoked при refresh-token grant. | Phase 2 done |
| `POST /caep/ingress` | Receives CAEP SET (RFC 8417) from upstream IdPs (Phase 8). | Phase 8 planned |
| `POST /dpop_replay` | (Internal) DPoP jti replay cache HTTP API (api-gateway co-reads). | Phase 2 done |

## token_hook (Phase 2)

Hydra POSTs JSON; kacho-iam adds claims:
```json
{
  "request": {
    "client_id": "kacho-ui",
    "granted_scopes": ["openid", "profile", "kacho.vpc.read"],
    "session": {
      "id_token": { "id_token_claims": { "sub": "usr_xxx" } }
    }
  },
  "session": {
    "kacho": {
      "account_id": "acc_yyy",
      "project_id": "prj_zzz",
      "principal_id": "usr_xxx",
      "groups": ["grp_aaa"],
      "mfa_fresh": true,
      "acr": "aal2",
      "dpop_cnf": { "jkt": "<jwk-thumbprint>" }
    }
  }
}
```

Hydra includes these claims в issued JWT. api-gateway middleware ([[api-gateway-middleware-authz]]) consumes `kacho.account_id` / `kacho.acr` для downstream authz.

## refresh_hook

Re-checks user/SA status:
- User soft-disabled → deny refresh.
- Session revoked (`session_revocations` row) → deny.
- Rotate detected → emit CAEP event (Phase 8).

## DPoP replay cache (Phase 2)

In-memory sharded LRU 64-shard (lock-free per-shard). Persisted на restart через Postgres `dpop_replay_jti` table.
- Insert `jti` + `cnf.jkt` → если duplicate → reject (replay attack).
- TTL 5min (configurable `KACHO_IAM_DPOP_REPLAY_TTL`).
- Sharded by hash(jti) → 64 shards → linear scaling в high-throughput.

## CAEP ingress (Phase 8)

Verify signed SET → process event:
- `session.revoked` from upstream → mark `session_revocations` row → propagate downstream subscribers.
- `iam.user.disabled` upstream → soft-disable user mirror.

## Auth

- Hydra → kacho-iam: shared secret (`KACHO_IAM_HYDRA_HOOK_SECRET`); verified `subtle.ConstantTimeCompare` fail-closed.
- CAEP ingress: SET signature verified против issuer JWKS.

## Imports

- `net/http`, `encoding/json`, `crypto/subtle` — stdlib
- `internal/service/session_revocations` — port
- `internal/clients/openfga` (Phase 3 — `model.changed` propagation)

## Imported by

- `cmd/kacho-iam/main.go` — wired as 5th parallel task (HTTP server on 9092)

## See also

[[iam-domain]] [[iam-jobs]] [[../edges/iam-to-hydra-admin]] [[../edges/iam-caep-to-subscriber]] [[../rpc/iam-caep-subscriber-service]] [[../KAC/KAC-127]]

#packages #kacho-iam #handler #oauth
