---
title: "registry ← iam: anonymous public pull (user:* wildcard, RG-1 D-7)"
aliases:
  - registry anon pull
  - anonymous public read
  - user:* wildcard registry
category: edge
caller_repo: kacho-registry
callee_repo: kacho-iam
sync_async: sync
protocol: http-token + grpc-cluster-internal
status: active
related_tickets:
  - "[[RG-1-registry-repository-overlay]]"
tags:
  - edge
  - kacho-registry
  - kacho-iam
  - cross-service
  - authz
---

# registry ← iam: anonymous public pull (`user:*`, RG-1 D-7)

Anonymous `docker pull` of a PUBLIC repo, brokered by iam and enforced by the registry
data-plane. Two legs (issuance + consumption); no new build edge (runtime only).

## Issuance (iam) — B13/B14

- IAM `/iam/token` **without** Basic creds → `IssueRegistryTokenUseCase.ExecuteAnonymous`
  signs a client_assertion **as** the configured anon Hydra client (`AnonymousClientID`)
  and brokers a short-lived Hydra Bearer with `scope=registry:pull` (**read-only**, never
  a write verb), registry data-plane audience, bounded TTL. No user/SA credential.
  Anon disabled (empty `AnonymousClientID`) → 401 challenge (opt-in, secure-by-default).
- Governance: `user:* v_get registry_repository:<reg>/<repo>` tuple emitted/withdrawn by
  the registry overlay via fga-proxy on the final `visibility` (B01/B06/B12). FGA model
  (kacho-deploy #172): `registry_repository.v_get: [user:*, ...]` — **only** `v_get` gains
  the wildcard, no write relation (read-only floor).

> [!warning] Wire-contract gotcha — `issued_at` MUST be an RFC3339 **string**
> The `/iam/token` JSON body's `issued_at` (Docker Registry v2 token spec) is parsed
> by the docker client via `time.Time.UnmarshalJSON`, which accepts **only** a JSON
> string. Emitting it as a bare int64 **number** breaks `docker login`
> («Time.UnmarshalJSON: input is not a JSON string») → no bearer minted → all
> pull/push 401. `registrytokenhttp` serializes it as `time.Unix(iat,0).UTC().Format(RFC3339)`;
> the use-case `IssueOutput.IssuedAt` stays int64 (unix seconds, source of truth) — only
> the HTTP wire shape is a string. `expires_in` remains an integer.

## Consumption (registry data-plane) — B03/B04/B05/B07/B14

- The Hydra Bearer's `sub` = `AnonymousClientID`. The data-plane
  (`KACHO_REGISTRY_ANONYMOUS_SUBJECT_ID`, MUST match iam's `AnonymousClientID`) resolves
  that `sub` to FGA subject **`user:*`** via `domain.FGASubjectForPrincipalID` +
  `Handler.WithAnonymousSubject` (`fgaSubject` in `ServeHTTP`). Empty → anon disabled.
- Per-request `InternalIAMService.Check(user:*, <verb>, registry_repository:<reg>/<repo>)`:
  - PUBLIC (has `user:* v_get`) → **200** pull (manifest/blob, both `v_get`). `tags/list`
    uses `v_list` (no wildcard) → anon cannot enumerate tags.
  - PRIVATE (no tuple) **or** ABSENT → the **same uniform 404 NAME_UNKNOWN**, byte-identical
    — public-ness is not a probeable existence-oracle. `user:*` never holds a push-grant /
    `v_create` → REG-33 bridges return false for anon (no reveal).
  - no-token → **401** challenge; anon-token push (any repo, incl. pull-able PUBLIC) → **403
    DENIED** (`user:*` carries no write relation → `v_update`/`v_create` deny).

## Error / failure

- Issuer (Hydra) unavailable → iam 503; expired/replayed anon-JWT → data-plane 401
  (inherited Bearer-JWT/JWKS expiry + audience enforcement; RG-1 adds no new mechanism).

## History

- 2026-07-15 — RG-1: iam anon issuance (kacho-iam #325), FGA `user:*` (kacho-deploy #172),
  registry data-plane consumption (kacho-registry #43 slice 3, `be7e1c9`).
- 2026-07-15 — `issued_at` RFC3339-string fix (kacho-iam #326): the Docker-v2 wire fix
  (`c300053`) shipped on the live `KAC-registry-docker-auth` image but was lost from main;
  rolling iam to a `main-<sha>` image without it re-broke `docker login`. Re-applied on main.

#edge #kacho-registry #kacho-iam #cross-service #authz
