---
title: "InternalBootstrapTokenService (implemented — #58)"
tags: [rpc, iam, internal, authn, done]
service: kacho-iam
listener: ":9091 (cluster-internal, mTLS)"
status: done
verified_against: "перечень RPC сверен с proto ствола redesign/integration в ОБЕ стороны 2026-08-05 (методы контракта против методов записки); поля запросов и семантика построчно не пересматривались"
category: rpc
---

# InternalBootstrapTokenService (implemented — #58)

**Status:** **IMPLEMENTED** on `redesign/integration` (2026-07-22). Sub-phase B landed:
proto+codegen, migration 0058, repo (BootstrapStore, advisory-lock CAS), mint use-case
(reuses `registrytoken` ES256 assertion + `HydraTokenClient` exchange), handler, :9091
registration, gateway internal-route + permission-catalog, and the O-1 gateway SA
acr-exemption. Full TDD RED→GREEN (unit IBT-08/09/11, integration IBT-01/02/03 +
concurrency, IBT-T5 enrichment, IBT-06/07 internal-only, O-1 mechanism-lock).

## Live-stand verification (2026-07-21)
Migration 0058 applied live (goose v58) → bootstrap SA `svab91854890de887e6d` + cluster
`system_admin` grant (subject_type=service_account) + fga owner-tuple seeded. Mint reachable
via gateway internal REST (:8081 → iam :9091 mТLS). **Provisioning works live** (Hydra OAuth
client `kacho-bootstrap-admin` created + `service_account_oauth_clients` mapping committed);
the ES256 private_key_jwt assertion is **accepted by Hydra** (client auth passes). The token
EXCHANGE then dies because iam's Hydra **token-enrichment hook** (`:9092 /iam/v1/hooks/token`)
returns **401 → Hydra 500** — a pre-existing stand Hydra↔iam **hook-auth misconfig** that
blocks ALL client_credentials issuance (registry SA-keys too), independent of #58. Phase C
(production-newman) is blocked on that hook-auth fix — tracked in **#59**.

## Original problem
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
