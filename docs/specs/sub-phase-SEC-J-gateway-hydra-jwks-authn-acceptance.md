# Sub-phase SEC-J — api-gateway: validate real Hydra RS256 access JWTs in the principal-setting AuthInterceptor

**Status:** DRAFT (awaiting `acceptance-reviewer` APPROVED gate — ban #1)
**Type:** bugfix + config (authN wiring, not a new resource/RPC)
**Repos:** `kacho-api-gateway` (code), `kacho-deploy` (helm env)
**Owner agent:** acceptance-author → acceptance-reviewer
**Format:** Given-When-Then (markdown only — no code)

---

## 1. Problem statement (ground truth)

After a real Ory-Hydra login (register + login through Kratos/Hydra), the SPA holds a
**Hydra-issued RS256 access JWT**. Calling
`kacho.cloud.iam.v1.AuthorizeService/WhoAmI` (and `AccountService` / `ProjectService`)
returns **gRPC code 16 `AUTHN_REQUIRED` "subject: unauthenticated request"**.

**Root cause.** The api-gateway principal-setting `AuthInterceptor`
(`internal/middleware/auth.go`) — the middleware responsible for turning a Bearer
token into the Kachō `Principal` and injecting `x-kacho-principal-*` metadata for
backends — validates **only the HMAC-dev JWT path**. Its `validateJWT` keyfunc
(~L244-267) accepts a token **only** when `t.Method` is `*jwt.SigningMethodHMAC`,
signed with `devSecret`; when `devSecret` is empty it returns an error outright
(L245-249). The TODO at ~L246 (`"Zitadel JWKS deferred"`, legacy naming) is exactly
the missing wire. A real Hydra RS256 token therefore **fails `validateJWT`** → in
`dev` mode the request degrades to anonymous (or, when the dev path is taken in
`auth.HTTP`, never even reaches the RS256 branch because `len(a.devSecret) > 0` gates
it) → the request reaches kacho-iam principal-less → iam's authz gate rejects it as
`AUTHN_REQUIRED`.

**The verifier already exists — this is a WIRE, not a build.** A complete,
RFC 8725-hardened Hydra JWKS verifier lives in
`internal/middleware/jwt_verifier.go` + `jwk.go` (`NewJWTVerifier`,
`{JWKSURL, JWKSCacheTTL, JWKSFetchTimeout}`, RS256, alg whitelist, kid pinning,
iss/aud/exp/nbf checks, TTL cache with force-refresh on unknown kid). It is **already
constructed** in `cmd/api-gateway/main.go` (~L132) but is wired **only into the DPoP
middleware** (~L169-170), **not into `NewAuthInterceptor`** (~L94). The principal
path never calls it.

**The validated Hydra token already carries the Kachō principal.** Hydra runs
`strategies.access_token=jwt` and the kacho-iam token_hook
(`internal/service/token_enrichment_service.go`, `iamhooks/token_hook_handler.go`)
emits these claims: `kacho_principal_type`, `kacho_principal_id`, `kacho_account_id`,
`kacho_active_account`, `kacho_project_id`, `kacho_user_id`, `kacho_sa_key_id`.
So once the token is JWKS-verified, the principal can be derived **directly from the
verified claims** — no extra round-trip to kacho-iam needed (fall back to
`SubjectLookuper` only when the claims are absent).

> **Claim-placement nuance (load-bearing).** The token_hook returns the kacho claims
> under `session.access_token.ext_claims` (`token_hook_handler.go` L157-160) → in the
> issued JWT they land **nested under an `ext_claims` map**, which the verifier already
> surfaces as `VerifiedToken.ExtClaims`. Hydra `allowed_top_level_claims` additionally
> promotes the same names to the **top level** of the JWT. The fix MUST read the
> principal claims **robustly from either placement** — prefer top-level
> (`claims["kacho_principal_type"]`), else `ext_claims.kacho_principal_type`. An
> integration test pins both placements so a future Hydra config change to either form
> does not silently regress to anonymous.

---

## 2. Scope

### In scope
1. Wire the existing `JWTVerifier` into `NewAuthInterceptor` so the principal path can
   validate Hydra-issued RS256 access JWTs (a **second** validation strategy alongside,
   not replacing, the HMAC-dev path).
2. On a JWKS-verified Hydra token, derive the `Principal` from the verified claims
   (`kacho_principal_type` + `kacho_principal_id`, plus a display value when present),
   robust to top-level **or** `ext_claims` placement; fall back to `SubjectLookuper`
   only when those claims are absent.
3. Preserve the HMAC-dev path verbatim (dev/e2e tokens) — **zero regression**.
4. Preserve the no-Bearer behaviour per mode (anonymous in dev/production, 401 in
   production-strict) verbatim.
5. Ensure a present-but-invalid token is **always rejected**, never silently
   downgraded to anonymous (carry forward the KAC-127 api-token authN pre-gate).
6. Fail-closed when the JWKS endpoint is unreachable: a Hydra token presented while
   JWKS cannot be fetched is **rejected (Unauthenticated)**, logged — not anonymous.
7. Config: the live gateway must resolve a **reachable cluster-internal Hydra JWKS
   URL** (helm env in `kacho-deploy`), instead of the unreachable derived default
   `https://hydra.{APIDomain}/.well-known/jwks.json`.
8. Parity between the two principal-setting code paths — the gRPC unary/stream
   interceptor (`authorize`) **and** the REST path (`auth.HTTP`).

### Non-goals
- **No new crypto / no new verifier** — reuse `jwt_verifier.go` / `jwk.go` exactly.
- **No DPoP / sender-constrained change** — the DPoP middleware and its existing
  verifier wiring are untouched; this adds a verifier reference to the principal path
  only. (The verifier instance MAY be shared, but DPoP enforcement semantics do not
  change.)
- **No opaque-token introspection** — only self-contained JWT (`access_token=jwt`).
  Introspection cache stays as-is.
- **No proto / no contract change** — no RPC added/removed; `WhoAmI` request/response
  and all error texts are unchanged. The fix is behind the gateway; backends see the
  same `x-kacho-principal-*` metadata they always have.
- **No change to backend authZ** (`InternalIAMService.Check`, listauthz) — once the
  principal is set, downstream is identical.
- **No lazy-mirror / UpsertFromIdentity** behaviour change (out of scope; existing
  Kratos path unchanged).

---

## 3. Acceptance scenarios (Given-When-Then)

Each scenario applies to **both** the gRPC interceptor path (`authorize`) and the REST
path (`auth.HTTP`) unless a path is named explicitly.

### Scenario A — valid Hydra RS256 access JWT → principal from claims → WhoAmI returns the subject

```
Given  the api-gateway AuthInterceptor is wired with the existing JWKS verifier
  And  the verifier's JWKS URL points at a reachable Hydra public JWKS endpoint
  And  a user has registered and logged in via Hydra, holding an RS256 access JWT
       whose header alg=RS256 and whose claims include
       kacho_principal_type="user" and kacho_principal_id=<userId>
       (at top level and/or under ext_claims), iss=<expected Hydra issuer>,
       a valid signature against a JWKS key, and exp in the future
When   the client calls kacho.cloud.iam.v1.AuthorizeService/WhoAmI
       with Authorization: Bearer <that JWT>
Then   the token is JWKS-verified (RS256, kid resolved, iss/exp/nbf valid)
  And  the Principal is built from the verified claims:
       type="user", id=<userId>, displayName from a present display claim
       (else id) — WITHOUT a SubjectLookuper round-trip
  And  x-kacho-principal-type / x-kacho-principal-id / x-kacho-principal-display-name
       metadata are injected toward the backend
  And  WhoAmI returns 200 / OK identifying that subject
  And  the response is NOT code 16 AUTHN_REQUIRED
```

Variant **A2 (service-account token, parity with KAC-127 models 5-6):** a Hydra
`client_credentials` / API token carrying `kacho_principal_type="service_account"` and
`kacho_principal_id=<svaId>` is JWKS-verified and yields
`type="service_account", id=<svaId>` — never anonymous, never a User lookup miss.

Variant **A3 (claims placement):** the same token is accepted whether the kacho
claims are top-level **or** nested under `ext_claims` — both placements resolve to the
identical Principal.

Variant **A4 (claims absent → fallback):** a verified Hydra token that lacks the
`kacho_principal_*` claims falls back to `SubjectLookuper.LookupByExternalID(sub)`
exactly as the legacy path does (no behaviour change for that branch).

### Scenario B — HMAC-dev token still validates (dev / e2e unchanged, ZERO regression)

```
Given  the gateway runs in mode=dev with a non-empty devSecret
       (KACHO_API_GATEWAY_AUTHN_DEV_SECRET) — the kind dev stand / authz-fixtures minter
When   a client presents a Bearer HS256 JWT signed with that devSecret
       (the existing dev/e2e token shape, sub=<external_id>)
Then   the token validates via the HMAC path EXACTLY as before
  And  subject resolution (SubjectLookuper or SA-claims short-circuit) is unchanged
  And  the Principal and x-kacho-principal-* metadata are identical to pre-fix behaviour
  And  every existing dev/e2e newman case that authenticates with an HS256 token
       still passes with no edit
```

Variant **B2:** with `devSecret` set **and** the JWKS verifier wired, an HS256 token
still takes the HMAC branch (it is not RS256, so the RS256/JWKS branch is not the one
that validates it) — the two strategies coexist; neither steals the other's tokens.

### Scenario C — missing Bearer → anonymous (unchanged per mode)

```
Given  the gateway runs in mode=dev (or production)
When   a request arrives with NO Authorization Bearer header (and no Kratos session)
Then   the request is injected as Principal{system, anonymous} (pass-through)
  And  behaviour is byte-for-byte the pre-fix no-Bearer path
And given mode=production-strict
When   a request arrives with no Bearer
Then   it is rejected Unauthenticated "missing Bearer token" (unchanged)
```

### Scenario D — forged / expired / bad-signature / disallowed-alg token → REJECTED (never silent-anonymous)

```
Given  the AuthInterceptor with both HMAC-dev and JWKS strategies wired
When   a client presents a Bearer token that is present but INVALID, for each of:
        (d1) RS256 token with a signature that does not verify against the JWKS
        (d2) RS256 token whose kid is unknown even after a JWKS force-refresh
        (d3) expired RS256 token (exp in the past, beyond clock-skew leeway)
        (d4) token whose iss does not match the expected Hydra issuer
        (d5) alg=none, or an HS256 token NOT signed with the dev secret,
             or any alg outside the RS256/ES256/EdDSA whitelist
        (d6) structurally malformed JWT (not three base64url segments)
        (d7) a Hydra-shaped token missing the sub claim
Then   the request is REJECTED with codes.Unauthenticated (REST: HTTP 401 with a
       gRPC-shaped body code 16 + WWW-Authenticate challenge)
  And  it is NEVER downgraded to Principal{system, anonymous}
  And  it is NEVER passed through to the backend principal-less
  And  the failure is logged at WARN with the method and a non-leaking reason
  And  this holds in EVERY mode (dev / production / production-strict)
```

> Rationale: authN failures precede authZ. A bad token granting anonymous would let an
> attacker probe the anonymous surface and would mask a 401 as a 403 — both forbidden.
> This carries forward the existing KAC-127 api-token authN pre-gate to the RS256 path.

### Scenario E — JWKS endpoint unreachable → token rejected FAIL-CLOSED (not anonymous)

```
Given  the AuthInterceptor JWKS verifier is configured but its JWKS endpoint is
       temporarily unreachable (network error / non-200 / empty key set / timeout)
       and no usable key is in the TTL cache for the token's kid
When   a client presents an otherwise well-formed Hydra RS256 Bearer token
Then   verification fails (the verifier returns a JWKS-fetch/unreachable error)
  And  the request is REJECTED with codes.Unauthenticated (REST: 401) — fail-closed
  And  it is NOT downgraded to anonymous and NOT passed through principal-less
  And  the failure is logged at WARN/ERROR distinguishing "JWKS unreachable" from
       "token invalid" (operability — points at infra, not at the client)
And given a previously-fetched JWKS key for the token's kid is still within cache TTL
When   the same token is presented while the endpoint is briefly down
Then   verification succeeds from cache (the existing cache behaviour is preserved;
       fail-closed applies only when no usable key is available)
```

### Scenario F — config: gateway resolves a REACHABLE cluster-internal Hydra JWKS URL (helm)

```
Given  the live gateway pod currently emits NO KACHO_HYDRA_* / KACHO_API_DOMAIN /
       KACHO_HYDRA_JWKS_URL env (deploy/templates/deployment.yaml emits only
       AUTHN_MODE / AUTHN_DEV_SECRET / AUTHZ_* / MTLS_*)
  And  with those unset, ResolvedHydraJWKSURL() derives
       https://hydra.{APIDomain}/.well-known/jwks.json (default APIDomain
       api.kacho.cloud) — which is NOT reachable from inside the cluster
  And  the in-cluster Hydra public JWKS is served by the hydra-public Service at
       http://kacho-umbrella-hydra-public:4444/.well-known/jwks.json
       (VERIFY the exact Service name/port in the deploy helm before pinning)
  And  Hydra's self.issuer is http://kacho-umbrella-hydra-public:4444 in-cluster
       (dev override: http://localhost:28080/.ory/hydra/public/)
When   the kacho-deploy api-gateway subchart renders the gateway Deployment
Then   the gateway is configured (via helm env — e.g. KACHO_HYDRA_JWKS_URL and/or
       KACHO_HYDRA_ISSUER) so that:
         * ResolvedHydraJWKSURL() returns a cluster-REACHABLE JWKS URL
           (the hydra-public Service, NOT https://hydra.api.kacho.cloud)
         * ResolvedHydraIssuer() matches the value Hydra actually stamps into the
           token `iss` claim, so Scenario A passes the iss check and Scenario D(d4)
           still rejects a wrong issuer
  And  the rendered env is asserted by a helm-template test (the JWKS URL is the
       reachable Service URL; the issuer matches Hydra's self.issuer)
  And  the verifier construction in cmd/main.go (which already reads
       ResolvedHydraJWKSURL/ResolvedHydraIssuer) now feeds the AuthInterceptor too
```

> Note: issuer/JWKS must be **consistent** — a JWKS URL that does not correspond to the
> issuer Hydra signs with would make every real token fail the iss check. The acceptance
> is "real login → WhoAmI works end-to-end against the dev stand", which forces both to
> be correct together.

### Scenario G — requirement #7: JWT authN preserved, no contract change

```
Given  the SEC/AuthN epic requirement #7 — JWT-based authN is preserved end-to-end
When   the fix is applied
Then   the public/REST contract is UNCHANGED: no RPC added/removed, WhoAmI request and
       response shapes unchanged, all error texts/codes unchanged
  And  the only observable change is: a real Hydra RS256 login token now authenticates
       (Scenario A) where it previously failed AUTHN_REQUIRED
  And  the HMAC-dev path, the no-Bearer anonymous path, and the Kratos-session path are
       all behaviourally unchanged
  And  Internal-vs-external (ban #6) is unaffected — this is edge authN, not a method
       publication change
```

---

## 4. Invariants (MUST hold — restated for the reviewer)

| # | Invariant |
|---|---|
| I1 | HMAC-dev path keeps working byte-for-byte (dev/e2e) — zero regression (Scenario B). |
| I2 | Missing Bearer → anonymous in dev/production, 401 in strict — unchanged (Scenario C). |
| I3 | A present-but-bad token is **always** rejected Unauthenticated, **never** silent-anonymous, in every mode (Scenario D). |
| I4 | JWKS unreachable + no usable cached key → **fail-closed reject**, never anonymous (Scenario E). |
| I5 | The two strategies coexist: RS256 validates via JWKS, HS256-dev via HMAC; neither path steals the other's tokens (Scenario B2). |
| I6 | Principal from verified claims is preferred; SubjectLookuper is fallback only (Scenario A4). |
| I7 | gRPC interceptor path and REST `auth.HTTP` path behave identically across A-E (parity). |
| I8 | No new crypto, no DPoP semantics change, no introspection, no proto/contract change. |
| I9 | The live gateway resolves a reachable in-cluster JWKS URL whose issuer matches Hydra's `iss` (Scenario F). |

---

## 5. Test plan (TDD — RED before GREEN, ban #12)

All tests authored and run RED **before** the fix; pair RED→GREEN shown in the PR.

### 5.1 Unit / middleware (`internal/middleware/*_test.go`)
- **RS256 happy** (A): table-driven, an RS256 token signed by a test JWK served by an
  httptest JWKS server → AuthInterceptor builds Principal{user,id} from claims; assert
  injected `x-kacho-principal-*` metadata; assert **no** SubjectLookuper call when claims
  present.
- **A2 SA token**: `kacho_principal_type=service_account` → `service_account`/svaId,
  no User lookup.
- **A3 placement**: same token with claims top-level vs nested `ext_claims` → identical Principal.
- **A4 fallback**: verified RS256 token without kacho claims → SubjectLookuper invoked.
- **B / B2 HMAC coexistence**: HS256-dev token still validates with verifier wired;
  RS256 token does not validate via the HMAC branch and vice-versa.
- **C** no-Bearer per mode (reuse/extend existing cases).
- **D d1-d7**: each invalid-token class → `codes.Unauthenticated`; assert **not**
  anonymous (Principal not system/anonymous; backend not reached principal-less);
  assert WARN log. Mirror for REST `auth.HTTP` → 401 + WWW-Authenticate.
- **E**: httptest JWKS server returning 500 / network-closed / empty keys → token
  rejected fail-closed; plus the cache-hit-during-outage sub-case → success from cache.
- **Parity**: every A-E unit assertion is run against both `authorize()` and `auth.HTTP`.

### 5.2 Config (`internal/config/config_test.go`)
- `ResolvedHydraJWKSURL()` returns the explicit cluster URL when `KACHO_HYDRA_JWKS_URL`
  is set; derives correctly from issuer otherwise; issuer/JWKS consistency asserted.

### 5.3 Helm (`kacho-deploy` helm-template test)
- Rendered api-gateway Deployment emits a JWKS/issuer env that resolves to the
  reachable hydra-public Service URL (NOT `https://hydra.api.kacho.cloud`); issuer
  matches Hydra `self.issuer`. (Scenario F.)

### 5.4 e2e / newman (`tests/newman/`)
- **Happy (A)**: obtain a real Hydra access JWT against the dev stand (login flow),
  call `WhoAmI` over REST → 200 identifying the subject; ≥1 happy.
- **Negative (D)**: forged/expired/wrong-iss Bearer → 401 (code 16), never an
  anonymous 200; ≥1 negative.
- **Regression (B)**: an existing HS256-dev-authenticated case still passes unedited.

> Final verification before merge (ai-tooling §7): `go test ./... -race` +
> `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman green; and a
> manual end-to-end "register+login → WhoAmI 200" on the kind dev stand confirming the
> original bug is fixed.

---

## 6. Traceability

| Requirement | Source | Scenario / Test |
|---|---|---|
| Wire existing JWKS verifier into principal path | `auth.go` L244-267 TODO; verifier in `jwt_verifier.go`, constructed `main.go` L132, wired only to DPoP L169 | A, §5.1 |
| Principal from `kacho_principal_*` claims (no lookup) | token_hook `token_enrichment_service.go` L182-287; verifier `ExtClaims` extraction `jwt_verifier.go` L342-344 | A, A2, A3, A4 |
| HMAC-dev zero regression | `auth.go` `validateJWT` HMAC branch L250-255; dev `values.dev.yaml` authn.devSecret | B, B2, I1, §5.1/§5.4 |
| Missing Bearer per mode unchanged | `auth.go` L159-166 | C, I2 |
| Bad token never silent-anonymous | `auth.go` L168-182, L377-393 (KAC-127 pre-gate) | D, I3 |
| JWKS unreachable fail-closed | `jwt_verifier.go` `refresh` sentinels `ErrJWKSUnreachable`/`ErrJWKSFetchFailed` L188-227; cache `Resolve` L163-186 | E, I4 |
| Reachable in-cluster JWKS URL | `config.go` `ResolvedHydraJWKSURL`/`ResolvedHydraIssuer` L240-260; `deploy/templates/deployment.yaml` emits NO HYDRA env L95-120; in-cluster `kacho-umbrella-hydra-public:4444` + Hydra `self.issuer` (overrides.yaml L33, values.dev.yaml L572-573) | F, I9, §5.2/§5.3 |
| JWT authN preserved, no contract change | epic requirement #7; ban #6 | G, I8 |

### Cross-repo order (polyrepo §topo)
No proto / corelib change. Order: **kacho-api-gateway** (code) → **kacho-deploy**
(helm env) → docs/vault trail. CI of the gateway is self-contained; the helm change is
verified by a render test and the kind stand.

### Affected vault entities (KAC-trail to update post-merge)
- `edges/api-gateway-to-iam-*` (principal/authN edge) — note RS256 path now active.
- `packages/kacho-api-gateway-middleware` (or equivalent) — AuthInterceptor now holds a
  JWKS verifier strategy.
- `KAC/KAC-<N>.md` — Status, PRs, "Что и зачем", DoD.

---

## 7. Definition of Done

- [ ] APPROVED by `acceptance-reviewer` (this doc) before any code (ban #1).
- [ ] KAC ticket + branch `KAC-<N>` in kacho-api-gateway and kacho-deploy; KAC-trail in vault.
- [ ] RED tests authored & run first for A-G (unit/middleware, config, helm, newman) — pair shown.
- [ ] `JWTVerifier` wired into `NewAuthInterceptor`; principal derived from verified
      `kacho_principal_*` claims (top-level or `ext_claims`); SubjectLookuper fallback retained.
- [ ] HMAC-dev path unchanged (Scenario B green; existing dev/e2e newman unedited).
- [ ] Bad token → reject (D); JWKS-unreachable → fail-closed reject (E); never anonymous.
- [ ] gRPC and REST principal paths at parity (I7).
- [ ] kacho-deploy helm emits a reachable in-cluster JWKS URL + consistent issuer (F);
      render test green.
- [ ] No proto/contract change; ban #6 unaffected (G).
- [ ] `go test ./... -race` + `golangci-lint run` + `govulncheck` + `make audit-list-filter` + newman green.
- [ ] Manual dev-stand check: register + login → WhoAmI returns 200 (original bug gone).
- [ ] Ticket → Test → Done with artifacts (PR URLs, test logs); vault trail updated.
