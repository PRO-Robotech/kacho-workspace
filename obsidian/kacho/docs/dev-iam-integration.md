---
title: Developer IAM integration
aliases:
  - Developer guide
  - DPoP integration
  - Workload Identity
category: docs
audience: developer
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - docs
  - kacho-iam
  - developer
  - oauth
  - dpop
---

# Developer IAM integration

> [!info] Audience
> Developers integrating with Kachō API. Public URL `https://docs.kacho.cloud/dev/iam/`. This page = vault catalog.

## OAuth 2.1 + DPoP

Kachō issues DPoP-bound access tokens (RFC 9449). Tokens cannot be replayed without your private key.

### Quickstart

```bash
# 1. Get a token (user — interactive)
kacho-cli auth login                     # opens browser → Passkey

# 2. Get a token (service account — Class A static)
curl -X POST https://api.kacho.cloud/oauth2/token \
  -d "grant_type=client_credentials" \
  -d "client_id=$SA_CLIENT_ID" \
  -d "client_secret=$SA_CLIENT_SECRET" \
  -d "scope=kacho.vpc.read kacho.vpc.write" \
  -H "DPoP: $(generate-dpop-proof.sh POST /oauth2/token)"

# Response: { "access_token": "...", "token_type": "DPoP", "expires_in": 900 }

# 3. Use it
curl https://api.kacho.cloud/vpc/v1/networks?folderId=prj_xxx \
  -H "Authorization: DPoP $ACCESS_TOKEN" \
  -H "DPoP: $(generate-dpop-proof.sh GET /vpc/v1/networks)"
```

### DPoP proof generation (JS example)

```js
import { generateKeyPair, exportJWK } from 'jose';
const { publicKey, privateKey } = await generateKeyPair('ES256');
const jwk = await exportJWK(publicKey);

const proof = await new SignJWT({
  htm: 'POST',
  htu: 'https://api.kacho.cloud/oauth2/token',
  iat: Math.floor(Date.now() / 1000),
  jti: crypto.randomUUID(),
})
  .setProtectedHeader({ alg: 'ES256', typ: 'dpop+jwt', jwk })
  .sign(privateKey);
```

Full spec: RFC 9449. UI does this transparently — see `kacho-ui/src/lib/dpop.ts`.

## Workload Identity Federation (CI/CD)

For GitHub Actions / AWS / GCP / GitLab CI — no static secrets!

### GitHub Actions (Phase 5)

`.github/workflows/deploy.yml`:
```yaml
permissions:
  id-token: write  # GitHub OIDC

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Get kacho token
        run: |
          GITHUB_OIDC_TOKEN=$(curl -sLS -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=https://api.kacho.cloud" | jq -r .value)
          
          KACHO_TOKEN=$(curl -X POST https://api.kacho.cloud/iam/v1/federation/exchange \
            -d "grant_type=urn:ietf:params:oauth:grant-type:token-exchange" \
            -d "subject_token=$GITHUB_OIDC_TOKEN" \
            -d "subject_token_type=urn:ietf:params:oauth:token-type:jwt" \
            -d "audience=https://api.kacho.cloud" \
            -H "DPoP: $(make-dpop)" | jq -r .access_token)
          
          # Now use $KACHO_TOKEN to call kacho APIs
```

Setup steps:
1. In kacho admin UI → **Service Accounts** → create SA `github-actions-deploy`.
2. **Federation Trust Policy** → create:
   - Issuer: `https://token.actions.githubusercontent.com`
   - Subject pattern: `^repo:myorg/myrepo:ref:refs/heads/main$`
   - Audience: `https://api.kacho.cloud`
   - Max TTL: 15min
3. Grant `github-actions-deploy` SA the AccessBinding needed (e.g., editor on project prj_xxx).
4. Done — workflow gets short-lived kacho tokens without storing secrets.

See [[../rpc/iam-federation-exchange-service]], [[../resources/iam-federation-trust-policy]].

### Other providers — same pattern, different issuer

AWS STS, GCP, GitLab CI, CircleCI, Buildkite, Bitbucket — see [[../packages/iam-service-federation]].

## ListObjects pagination (efficient List with FGA)

For lists with FGA filtering:
```
GET /vpc/v1/networks?folderId=prj_xxx&pageSize=100&pageToken=<opaque>
```

Server-side flow:
1. Call iam.ListObjects(user, "vpc.network.read", project:prj_xxx).
2. Returns visible network IDs.
3. SQL filter `WHERE id = ANY(...)`.
4. Return + opaque next page token.

Don't try to decode the pageToken — it's signed (HMAC). Just pass it through.

See [[../edges/vpc-to-iam-listobjects]].

## Custom Conditions (CEL)

Phase 3 — embed dynamic constraints in AccessBindings:

```python
# Example condition: only on weekdays UTC
expression = "request.time.getDayOfWeek() in [1,2,3,4,5]"
```

API:
```bash
curl -X POST https://api.kacho.cloud/iam/v1/conditions \
  -H "Authorization: DPoP $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "weekdays-only",
    "kind": "time",
    "expression": "request.time.getDayOfWeek() in [1,2,3,4,5]",
    "params_schema": {}
  }'

# Attach to AccessBinding via condition_id field
```

See [[../rpc/iam-conditions-service]], [[../resources/iam-condition]].

## Subscribing to CAEP events

If your app needs real-time IAM state changes (session revoke, role change):

1. Admin endpoint → register subscriber endpoint (URL + auth).
2. Listen on your endpoint for signed JWT events (RFC 8417 SET format).
3. Verify signature against kacho JWKS.
4. Process event types: `session.revoked`, `iam.role.changed`, etc.

See [[../rpc/iam-caep-subscriber-service]], [[../edges/iam-caep-to-subscriber]].

## SPIFFE / SPIRE (in-cluster workloads, Phase 10)

For workloads inside same Kubernetes cluster as Kachō control plane:
- SPIRE Agent provides X.509 SVID per pod.
- mTLS to kacho APIs no token needed.
- Cilium mesh enforces SPIFFE-based policies.

See [[../edges/iam-to-spire]], [[../edges/iam-to-cilium-mesh]].

## See also

- [[user-iam-guide]] — end-user docs.
- [[admin-iam-guide]] — organization admin docs.
- [[../KAC/KAC-127]] — implementation milestone.

#docs #kacho-iam #developer #oauth #dpop
