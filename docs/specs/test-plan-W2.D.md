# Test Plan — W2.D: Newman 49→100% coverage (13 new case-files)

> **Source**: [docs/specs/sub-phase-W2.D-stream-d-newman-100pct-coverage-acceptance.md](sub-phase-W2.D-stream-d-newman-100pct-coverage-acceptance.md) (APPROVED 2026-05-24)
> **Status**: PLAN (test-only sub-phase per workspace §13 — NO product code, NO migrations, NO proto)
> **Branch (eventual impl)**: `KAC-XXX-newman-w2d` (kacho-iam only)
> **Parent KAC**: KAC-170 (parent bundle); subtask of master epic KAC-134

## 1. Per-GWT mapping

W2.D is a **test-only** sub-phase per workspace §«Запреты» #13. It produces newman cases, **not**
integration tests. So this plan is structured by `Сценарий` (acceptance §6) → newman case-file →
case-IDs.

### 6.1 Positive — coverage gate passes

| GWT id | Scenario summary | Newman case (gate-level) | Manual / e2e |
|---|---|---|---|
| W2.D-COVERAGE-PASS-01 | `coverage.py --min 100` exit 0 — 113/113 RPC covered | `tests/newman/scripts/coverage.py --min 100 --catalog gateway/embed/permission_catalog.json` | CI gate |

### 6.2 Positive — happy-path cases all GREEN

| Suite (NEW) | RPCs covered | Newman case-IDs (per RPC ≥1 happy + 1 negative) |
|---|---|---|
| `iam-access-review.py` | AccessReviewService 7 RPC | `IAM-ACCESSREVIEW-CAMPAIGN-CREATE-HAPPY/NEG-NOTFOUND/AUTHZ-ANON-DENY/AUTHZ-FOREIGN-DENY`, `…-LIST-OK/AUTHZ-FOREIGN-DENY`, `…-GET-OK/NEG-NOTFOUND/AUTHZ-FOREIGN-DENY`, `…-DECIDE-OK/NEG-ALREADY-DECIDED/AUTHZ-NON-REVIEWER-DENY`, `…-APPROVE-OK/AUTHZ-REVIEWER-FROM-PRINCIPAL` (verifies W1.6 #35), `…-REVOKE-OK/NEG-ALREADY-REVOKED`, `…-ADDREVIEWER-OK/NEG-DUPLICATE` (~30 cases) |
| `iam-authorize.py` | AuthorizeService 5 RPC | `IAM-AUTHORIZE-CHECK-OK/NEG-MISSING-SUBJECT/AUTHZ-ANON-DENY-POST-W13`, `…-BATCHCHECK-OK/NEG-EMPTY`, `…-EXPAND-OK`, `…-LISTOBJECTS-OK/NEG-INVALID-TYPE`, `…-LISTSUBJECTS-OK` (~25 cases) |
| `iam-conditions.py` | ConditionsService 6 RPC | `IAM-COND-CREATE-OK/NEG-INVALID-EXPR/AUTHZ-FOREIGN-DENY`, `…-GET-OK/NEG-NOTFOUND/AUTHZ-FOREIGN-DENY`, `…-LIST-OK/AUTHZ-FOREIGN-DENY`, `…-UPDATE-OK/NEG-INVALID-EXPR/AUTHZ-FOREIGN-DENY`, `…-DELETE-OK/NEG-IN-USE-FAILED-PRECONDITION`, `…-EVALUATE-OK/AUTHZ-ANON-DENY` (~25 cases) |
| `iam-federation-exchange.py` | FederationExchangeService 1 RPC | `IAM-FEDERATION-EXCHANGE-OK/NEG-INVALID-SIG/NEG-EXPIRED-JWT/NEG-WRONG-AUDIENCE/NEG-MISSING-IDP/NEG-MALFORMED-TOKEN` (~6 cases) |
| `iam-gdpr-erasure.py` | GdprErasureService 4 RPC | `IAM-GDPR-REQUEST-OK/NEG-DUPLICATE-ALREADYEXISTS/AUTHZ-ANON-DENY`, `…-LIST-OK/AUTHZ-FOREIGN-DENY`, `…-GET-OK/NEG-NOTFOUND/AUTHZ-FOREIGN-DENY`, `…-CANCEL-OK/NEG-WRONG-TOKEN-PERMDENIED/NEG-EXPIRED-FAILEDPRE/AUTHZ-ANON-DENY` (verifies W1.6 #43 anti-anon allowlist) (~18 cases) |
| `iam-internal-authorize.py` | InternalAuthorizeService 5 RPC | `IAM-INT-AUTHZ-WRITETUPLE-OK/NEG-MALFORMED/AUTHZ-NON-INTERNAL-CALLER-DENY`, `…-DELETETUPLE-OK/NEG-NOTFOUND`, `…-LISTTUPLES-OK`, `…-LISTRELATIONSHIPS-OK`, `…-RESOLVE-OK/NEG-INVALID` (~25 cases) |
| `iam-internal-break-glass.py` | InternalBreakGlassService 6 RPC | `IAM-INT-BG-REQUEST-OK/NEG-MISSING-JUSTIFICATION/AUTHZ-ANON-DENY`, `…-APPROVEA-OK/AUTHZ-SAME-AS-REQUESTER-DENY`, `…-APPROVEB-OK/NEG-OUT-OF-ORDER/NEG-SAME-AS-A-DB-CHECK-VIOLATION`, `…-DENY-OK/NEG-ALREADY-DECIDED`, `…-LISTPENDING-OK`, `…-GETGRANT-OK/NEG-NOTFOUND` (verifies W1.6 #43 + W2.B B.4) (~25 cases) |
| `iam-internal-user.py` | InternalUserService 3 RPC | `IAM-INT-USER-UPSERT-FROM-IDENTITY-OK/NEG-MALFORMED/PRINCIPAL-PROPAGATION-OK` (verifies W1.4), `…-GETBYEXTERNALSUBJECT-OK/NEG-NOTFOUND`, `…-LISTBYEMAIL-OK` (~12 cases) |
| `iam-jit-eligibility.py` | JITEligibilityService 5 RPC | `IAM-JIT-ELIG-CREATE-OK/AUTHZ-SPOOFED-CREATED-BY-DENY` (verifies W1.6 #39), `…-GET-OK/NEG-NOTFOUND/AUTHZ-FOREIGN-DENY`, `…-LIST-OK/AUTHZ-FOREIGN-DENY`, `…-UPDATE-OK/NEG-IMMUTABLE`, `…-DELETE-OK/NEG-NOTFOUND` (~22 cases) |
| `iam-opa-bundle.py` | OpaBundleService 3 RPC | `IAM-OPA-LISTBUNDLES-OK`, `…-GETBUNDLE-OK/NEG-NOTFOUND`, `…-REBUILDBUNDLE-OK/AUTHZ-NON-CLUSTER-ADMIN-DENY` (~12 cases) |
| `iam-sa-key.py` | SAKeyService 3 RPC | `IAM-SAKEY-ISSUE-OK/AUTHZ-SPOOFED-CREATED-BY-DENY` (verifies W1.6 #53), `…-FLOW-REDACT-AFTER-FIRST-GET` (**verifies W1.6 #11 — critical regression**), `…-REVOKE-OK/AUTHZ-FOREIGN-DENY`, `…-LIST-OK/AUTHZ-FOREIGN-DENY` (~15 cases) |
| `iam-trust-policy.py` | TrustPolicyService 5 RPC | `IAM-TRUSTPOLICY-CREATE-OK/AUTHZ-FOREIGN-DENY`, `…-GET-OK/NEG-NOTFOUND`, `…-LIST-OK/AUTHZ-FOREIGN-DENY`, `…-UPDATE-OK/NEG-IMMUTABLE`, `…-DELETE-OK/NEG-NOTFOUND` (~22 cases) |
| `iam-internal-iam-rest.py` | InternalIAMService 6 RPC (sans Check) | `IAM-INT-IAM-INITIALIZE-OK`, `…-SYNCFGA-OK/NEG-INTERNAL-ONLY-EXTERNAL-DENY`, `…-LISTPERMISSIONS-OK` (verifies W2.A #49 closure), `…-GETSUBJECTCHANGE-OK` (W1.2 verify), `…-ACKNOWLEDGESUBJECTCHANGE-OK`, `…-DRAINSUBJECTCHANGES-OK` (~25 cases) |

**Total**: ~262 new newman cases across 13 new case-files.

### 6.3 Negative — anti-anon enforcement

| GWT id | Scenario | Newman case-id (any mutation in 13 suites) |
|---|---|---|
| W2.D-ANON-DENY-MATRIX | Anonymous on `RequestBreakGlass`/`IssueKey`/`Approve*`/`Decide*`/`Cancel*Request`/`RequestErasure`/`Rebuild*`/`WriteTuple`/`DeleteTuple` → 401 Unauthenticated (not 403) | All `*-AUTHZ-ANON-DENY` cases across iam-internal-break-glass, iam-sa-key, iam-access-review, iam-jit-eligibility, iam-gdpr-erasure, iam-opa-bundle, iam-internal-authorize |

### 6.4 Negative — foreign-subject denied

| GWT id | Scenario | Newman case-id |
|---|---|---|
| W2.D-FOREIGN-DENY-MATRIX | Carol (stranger) calls `Get*(id-in-A)` → 404 NotFound (anti-info-leak per KAC-122 §5; NOT 403) | All `*-AUTHZ-FOREIGN-DENY` cases (uses `carol` fixture user) |

### 6.5 Edge — TDD-red against product bug

| GWT id | Scenario | Newman case-id |
|---|---|---|
| W2.D-RED-AGAINST-PROD-BUG | `IAM-SAKEY-IS-FLOW-REDACT-AFTER-FIRST-GET` (W1.6 #11) RED if W1.6 not merged → finding-issue in repo + `# verifies <url>` in case (NO `pm.test.skip`, NO TODO) | `iam-sa-key.py::IAM-SAKEY-IS-FLOW-REDACT-AFTER-FIRST-GET` |

### 6.6 Edge — Internal-listener-only RPC from external → 404

| GWT id | Scenario | Newman case-id |
|---|---|---|
| W2.D-INTERNAL-EXTERNAL-404 | `POST /internal/iam/v1/users:upsertFromIdentity` via TLS api.kacho.local:443 → 404 NotFound (not 401, not 403) | `iam-internal-user.py::IAM-INT-USER-NEG-INTERNAL-ONLY-EXTERNAL-404`, `iam-internal-iam-rest.py::IAM-INT-IAM-SYNCFGA-NEG-INTERNAL-ONLY-EXTERNAL-DENY` (and similar `*-NEG-INTERNAL-ONLY-EXTERNAL-*` in all internal-suites) |

### 6.7 Edge — concurrent case run (suite isolation)

| GWT id | Scenario | Newman case-id |
|---|---|---|
| W2.D-SUITE-ISOLATION | 2+ suites parallel create fixture Account/Project → unique-suffix `acc-${SUITE}-${RANDOM}`; teardown.sh per-suite cleans up | Per-suite `setup.sh` helper + `teardown.sh` — not a specific case, but a fixture-discipline rule |

## 2. Test infrastructure required

- **Helm umbrella**: kind cluster + helm umbrella (per KAC-177 wires) with kacho-iam pod accessible at `BASE_URL_PUBLIC=http://kacho-api-gateway.kacho.svc/iam/v1` and `BASE_URL_INTERNAL=http://kacho-iam.kacho.svc:9091`
- **External services**: OpenFGA (real, Postgres-backed); optionally Kratos IdP stub for `iam-federation-exchange.py` (else hardcoded test JWT signed by test private key)
- **Fixtures**:
  - 4 fixture users `bootstrap`/`alice`/`bob`/`carol` (existing W2.D-D3 per acceptance) seeded by `tests/newman/scripts/setup.sh`
  - `tests/newman/fixtures/opa-bundles/` — bundle archives for `iam-opa-bundle.py::GetBundle`
  - `tests/newman/fixtures/federation/test_idp_jwks.json` + `test_idp_private_key.pem` — for `iam-federation-exchange.py`
  - psql helper for post-step verification: `iam-internal-break-glass.py::IAM-INT-BG-APPROVEB-OK` checks `SELECT * FROM cluster_admin_grants WHERE grant_id=$1` via `kubectl exec`
- **Coverage tooling**: `tests/newman/scripts/coverage.py` (existing); must be extended to read `--catalog .../permission_catalog.json` if not already
- **Auth helpers**: existing `scripts/run.sh <suite>` setup uses 4-user fixtures + helm-mounted bootstrap token

## 3. Coverage gates (DoD on impl-PR)

- **`coverage.py --min 100` exit 0** — every catalog FQN with `scope="public"` has ≥1 newman case in the 13 new suites OR existing 12 baseline suites
- **`coverage.py` for `scope="internal_admin"`**: ≥1 case in respective `iam-internal-*.py` suite OR explicit `# wontfix-newman` annotation (acceptable only for unused legacy internal RPCs — none expected)
- **`run.sh --all` summary**: ≤ 5% known-failing-product-bugs (≤ 13 cases out of ~262); documented in `RESULTS.md` §«Known failing — product bugs» with `# verifies <issue-url>` tag
- **NO TODO/FIXME/skip discipline**: `grep -E '(TODO|FIXME|pm\.test\.skip|XXX|FIXIT)' tests/newman/cases/iam-*.py` returns **empty** (per workspace §11 + §13)
- **No product code changes**: `git diff --stat | grep -E "^\s*(internal/|cmd/|migrations/|.*\.proto)"` returns **empty**
- **RED→GREEN evidence per case-file in PR description** (per acceptance §7.2): pre-W2.D `./run.sh iam-access-review` shows "suite not found"; after population: 30 cases run; after dependencies wired: 30 PASS

## 4. Test sequencing for TDD (RED-before-GREEN per workspace §12)

Per acceptance §5.1 bootstrap + §5.2 case-template + §6 scenarios:

1. For each of 13 case-files:
   1. Copy skeleton from `cases/iam-account.py` (existing example)
   2. Replace `RESOURCE = "account"` → `RESOURCE = "<service>"`
   3. Remove existing cases
   4. For each RPC in service (per proto):
      - Add `IAM-<SVC>-<RPC>-CRUD-OK` (happy)
      - Add `IAM-<SVC>-<RPC>-NEG-NOTFOUND` (or appropriate negative)
      - Add `IAM-<SVC>-<RPC>-AUTHZ-ANON-DENY` (mutations only)
      - Add `IAM-<SVC>-<RPC>-AUTHZ-FOREIGN-DENY` (per-resource RPCs only)
   5. Run `gen.py` → collection json generated
   6. Run `./run.sh iam-<svc>` → confirm cases FAIL (red — expected: setup deps not wired)
   7. Wire fixtures + dependencies → green
   8. `coverage.py` reports service covered
2. Update `run.sh` SUITES_NEW (per acceptance §5.4)
3. `coverage.py --min 100` exit 0
4. **No product code commits** — anywhere in this PR

## 5. Out-of-scope tests (boundary, not omission)

- **Product code changes** — explicitly per workspace §13 (test-only PR); bugs found while writing RED → separate KAC + GitHub Issue
- **ApiTokenService cases** — W2.C scope (`iam-api-token.py` ships with W2.C feature)
- **SAML/SCIM full e2e wire-protocol** — W2.B B.1/B.2 (only smoke `iam-federation-exchange.py` 1-RPC proxy here)
- **Refresh baseline 12 suites** — if W2.A merge breaks any existing case, fix in W2.A PR, NOT W2.D
- **Load tests (k6/ghz)** — separate track (Future-track / KAC-future)
- **Chaos tests** — out of scope
- **Performance assertions (response-time bounds)** — covered by k6 load only; newman cases assert correctness only

## 6. Coverage gaps observed in acceptance doc

- **OQ-W2.D-1** — `InternalIAMService` 6 methods besides Check enumerated only after impl-start (Initialize / SyncFGA / ListPermissions / GetSubjectChange / AcknowledgeSubjectChange / DrainSubjectChanges); verify against `kacho-proto/proto/.../internal_iam_service.proto` at impl-start. Not a gap requiring acceptance update — implementer reads proto.
- **OQ-W2.D-2** — FederationExchangeService 1 RPC fixture requires Kratos IdP OR hardcoded test JWT. Recommended hardcoded test JWT + `test_idp_jwks.json` fixture committed (smaller dependency footprint). Acceptance doesn't mandate either; implementer chooses.
- **OQ-W2.D-3** — OpaBundleService 3 RPC requires bundle storage in test setup. Recommended `tests/newman/fixtures/opa-bundles/` with 2 fixture bundle archives. Acceptance doesn't enumerate sizes/contents — implementer adds.
- **OQ-W2.D-5** — `InternalBreakGlassService` post-step requires `psql` check via `kubectl exec`. Existing pattern in `iam-internal-only-check.py`; implementer reuses.
- **TDD-red against W1.6 #11 regression (`IAM-SAKEY-IS-FLOW-REDACT-AFTER-FIRST-GET`)** — case stays RED until W1.6 PR merges. Acceptance §6.5 + §0 explicitly documents this as **finding** not tech-debt; case in `# verifies` tag form. Per `RESULTS.md` §«Known failing — product bugs» section.

These are **acceptance-recognised** open questions; impl handles per OQ recommendation. No new follow-up KAC.

## 7. Cross-reference

- Acceptance source: [docs/specs/sub-phase-W2.D-stream-d-newman-100pct-coverage-acceptance.md](sub-phase-W2.D-stream-d-newman-100pct-coverage-acceptance.md)
- Test-coverage source-of-truth: `docs/superpowers/plans/2026-05-21-iam-newman-test-coverage-list.md` (495-case full list — W2.D extracts ~262 of these for 13 new services)
- Companion plans: [test-plan-W2.A.md](test-plan-W2.A.md) (catalog unification is prerequisite — W2.A merges first), [test-plan-W2.B.md](test-plan-W2.B.md) (B.4/B.5/B.7 features required end-to-end for full GREEN of internal-break-glass/access-review/gdpr suites), [test-plan-W2.C.md](test-plan-W2.C.md) (api-token cases NOT here — they ship in W2.C feature PR)
- Workspace rules: `CLAUDE.md` §«Запреты» #11 (no TODO), #12 (test-first), #13 (**root** of this sub-phase — test-only PR discipline: no product fix, no skip/TODO/FIXME in any test file)
- Naming conventions: newman case-id `IAM-<SVC>-<RPC>-<CLASS>[-detail]` snake-upper per `2026-05-21-iam-newman-test-coverage-list.md` §0
