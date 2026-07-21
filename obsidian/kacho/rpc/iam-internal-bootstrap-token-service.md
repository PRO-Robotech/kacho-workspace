---
tags: [rpc, iam, internal, authn, planned]
service: kacho-iam
listener: ":9091 (cluster-internal, mTLS)"
status: acceptance-approved-not-implemented
---

# InternalBootstrapTokenService (planned — #58)

**Status:** acceptance **APPROVED** (`docs/specs/sub-phase-IAM-BOOTSTRAP-TOKEN-acceptance.md`,
2026-07-22), **not yet implemented**. Unblocks non-interactive **production-mode** newman/e2e.

## Problem
Production authN (`api-gateway authn.mode=production-strict`) accepts **RS256 only** (Hydra-signed;
issuer-pin=Hydra; gateway verifies via iam JWKS-proxy :9097; requires `aud=https://{API_DOMAIN}`).
Newman seed (`tests/authz-fixtures/setup-jwt.py`) mints **HS256** dev JWTs → inert (anon+HS256→403).
Kind stand has **zero** Hydra OAuth clients seeded → no non-interactive entry to a first real token
(only human Kratos→Hydra browser login). Blocks ALL production e2e.

## Design (option 1 of #58)
New `InternalBootstrapTokenService.MintBootstrapToken` on **:9091** (mTLS gate = the authz;
`permission="<exempt>"` like the token-hooks). **Sync** request/response (NOT Operation — nothing
durable-async created; justified deviation from mutations→Operation).
- Principal = a **bootstrap ServiceAccount** (cluster `system_admin`), NOT a User — because SAs are
  **acr-exempt** (security.md §4.1.2), so the minted token satisfies acr>=2-gated RPCs
  (`UserTokenService.Issue`/`SAKeyService.Issue`) without acr injection.
- **Reuses existing machinery** (no new crypto): `registrytoken.SignClientAssertionES256` +
  `registrytokenwire.HydraExchange` (client_credentials + private_key_jwt) — the same path the
  registry `/iam/token` shim uses; only the requested **audience** differs (`https://{API_DOMAIN}`
  vs `registry.*`). iam already has `clients.HydraAdminClient` (CreateOAuthClient) + `IssueSAKeyUseCase`.
- Idempotent **provisioning**: first call provisions the bootstrap SA + its OAuth client if absent;
  singleton **DB-invariant** (partial-UNIQUE / well-known id, not TOCTOU) + concurrency test.
- Scope discipline: mints ONLY the bootstrap admin SA — a "mint token for any principal" skeleton-key
  is explicitly rejected.

## ⚠ O-1 dependency (found on acceptance review — REAL gap)
The public **gateway step-up gate** (`gateway/internal/middleware/…` acr-floor, see edge
[[api-gateway-to-iam-acr-floor]]) enforces `acr>=floor` for any verified token and **has no
service_account exemption branch**, while enrichment stamps `kacho_acr="0"` for client_credentials.
So a bootstrap-SA Bearer hitting the gateway for an acr>=2 RPC would be **denied today**. The
acr-exemption comments live in iam's `authzguard`/fgaproxy (the :9091 side), NOT at the edge.
→ Phase B must ALSO add a **narrowly-scoped** SA-exemption to the gateway step-up gate, gated by
`system-design-reviewer`. Acceptance pins the **observable** (bootstrap-SA Bearer → Issue → 200).

## Downstream (Phase C — production-newman)
Rework `tests/authz-fixtures/setup-jwt.py` HS256 minting → RS256 via this bootstrap flow:
bootstrap-SA token → per-subject `UserTokenService.Issue`/`SAKeyService.Issue` → Hydra exchange
(API audience) → per-subject RS256 tokens. Note acr caveat: user-token client_credentials tokens
enrich `kacho_acr="0"` → the StepUp (acr=2) newman variant needs the SA path or acr handling.

## Related
- Acceptance: `docs/specs/sub-phase-IAM-BOOTSTRAP-TOKEN-acceptance.md`
- Reuses: [[iam-sa-key-service]] · [[iam-to-hydra-admin]] · [[registry-to-iam-jwks-fetch]]
- Edge to touch: [[api-gateway-to-iam-acr-floor]]
- GitHub: `PRO-Robotech/kacho#58` (relates #56, #57)
