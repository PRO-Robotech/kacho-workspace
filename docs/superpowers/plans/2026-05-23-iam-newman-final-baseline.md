# IAM Newman Final Baseline — 2026-05-23

**Branch under test**: `KAC-133` (off `KAC-130-integration`, merges KAC-131 + KAC-132)
**api-gateway**: `KAC-131` commit `1914192`
**Fixture refresh**: `tests/authz-fixtures/setup.sh` (internal port-forward 19091:9091)
**Run command**: `cd tests/newman && bash scripts/run.sh`
**v2 baseline reference**: `docs/superpowers/plans/2026-05-23-iam-newman-red-baseline-v2.md`

---

## Summary Table

| Suite | Passed / Total | v2 Baseline | Delta | Status |
|---|---|---|---|---|
| authz-deny | 731 / 731 | 705/731 | **+26** | GREEN |
| authz-sa-apitoken | 72 / 74 | 72/74 | 0 | 2 BACKEND-BUG |
| iam-access-binding | 69 / 73 | 62/73 | **+7** | 4 BACKEND-BUG |
| iam-account | 18 / 20 | 18/20 | 0 | 2 BACKEND-BUG |
| iam-compliance-report | 0 / 23 | 0/23 | 0 | 23 BACKEND-BUG (catalog missing) |
| iam-group | 12 / 13 | 12/13 | 0 | 1 BACKEND-BUG |
| iam-internal-only-check | 10 / 23 | 10/23 | 0 | 13 failures (5 TEST-ENV + 8 BACKEND-BUG) |
| iam-jit-pending | 10 / 34 | 10/34 | 0 | 24 BACKEND-BUG (catalog missing) |
| iam-project | 17 / 18 | 17/18 | 0 | 1 BACKEND-BUG |
| iam-role | 15 / 15 | 15/15 | 0 | GREEN |
| iam-service-account | 17 / 18 | 17/18 | 0 | 1 BACKEND-BUG |
| iam-user | 57 / 60 | 57/60 | 0 | 3 BACKEND-BUG |
| **TOTAL** | **1028 / 1102** | **995/1102** | **+33** | |

**Net improvement vs v2**: +33 assertions fixed (KAC-132 authz-deny +26, KAC-133 LBR/LBS +7).

---

## Remaining Failures — Per Suite

### authz-sa-apitoken (2 failures)

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `AUTHZ-SA-NET-GT-A1` | ALLOW: not 403 | SA with `vpc-editor` grant on network-A1 gets 403 from FGA — tuple not propagated for per-resource scoped grants | BACKEND-BUG |
| `AUTHZ-APITOK-NET-GT-A1` | ALLOW: not 403 | Same as above for API token identity | BACKEND-BUG |

Root cause: FGA grant tuples for per-resource (non-scope-level) access not wired — when an SA/apitoken is granted `vpc.network.editor` on a specific network via `AccessBinding`, the FGA check in `kacho-vpc` does not find the path.

---

### iam-access-binding (4 failures)

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-ACB-CR-IDEM` (assert 13.4) | second-create | Second `Create` with same (scope+subject+role) returns a new operation id instead of the same binding id — ON CONFLICT idempotency not implemented | BACKEND-BUG |
| `IAM-ACB-LBR-AUTHZ-SCOPED` | NONMEMBER: empty list if 200 | NOB (non-member) receives 200 with non-empty list from `ListByResource` — scope filter not enforced for GET | BACKEND-BUG |
| `IAM-ACB-LBS-AUTHZ-FOREIGN-DENY` (2 asserts) | FOREIGN: status 403 + grpc code 7 | NOB can list account-A's bindings via `ListBySubject` — cross-account isolation not enforced for GET | BACKEND-BUG |

Note: 7 assertions were fixed in this run (+7 from v2) by changing 6 LBR/LBS steps from POST to GET with query params in URL (proto binding is `get:`).

---

### iam-account (2 failures)

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-ACC-CR-DUP-NAME` | error code 6 + text | Second `Create` with same name/owner returns 200 success (first op response) instead of ALREADY_EXISTS (6) | BACKEND-BUG |
| `IAM-ACC-CR-NEG-OWNER-MISSING` | error text includes "already exists" | Part of same cascade — wrong assertion fires on wrong response | BACKEND-BUG |

Root cause: Account `Create` has no dup-name detection; ON CONFLICT not returning ALREADY_EXISTS.

---

### iam-compliance-report (23 / 23 failures)

All 23 assertions fail. Every request returns `403 permission denied: catalog: no entry for method`.

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-CMPL-GEN-OK` (all steps) | generate, poll-op, get-report-completed | `ComplianceReportService` FQNs absent from `permission_catalog.json` in kacho-api-gateway | BACKEND-BUG |
| `IAM-CMPL-GEN-NEG-BAD-SCOPE` | generate-bad-scope | Same — catalog missing | BACKEND-BUG |
| `IAM-CMPL-GEN-NEG-SCOPE-NOTFOUND` | generate-missing-scope | Same — catalog missing | BACKEND-BUG |

Root cause: `kacho.cloud.iam.v1.ComplianceReportService/*` entries not present in `permission_catalog.json`. Fix: add entries to catalog in kacho-api-gateway (KAC-131 scope or new KAC).

---

### iam-group (1 failure)

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-GRP-CR-NEG-ACCOUNT-MISSING` | create-bad-account: sync 200 or 400 | Returns 403 (authz gate fires before account validation) instead of 400/409 | BACKEND-BUG |

Root cause: `RequireAuthenticated` + FGA check fires before the `accountId` existence check in the use-case.

---

### iam-internal-only-check (13 failures)

Two distinct failure modes:

**TEST-ENV (5 errors + 5 cascading asserts = 10 failures)** — `api.kacho.local` not resolvable in test environment (`/etc/hosts` entry missing):

| Case ID | Failure | Classification |
|---|---|---|
| `IAM-INT-NEG-EXT-USER-UPSERT` | ENOTFOUND api.kacho.local + cascading "no user.id leak" false positive | TEST-ENV |
| `IAM-INT-NEG-EXT-USER-GET` | ENOTFOUND + "no user id leak" false positive | TEST-ENV |
| `IAM-INT-NEG-EXT-IAM-LOOKUPSUBJECT` | ENOTFOUND + "no subjectId leak" false positive | TEST-ENV |
| `IAM-INT-NEG-EXT-IAM-CHECK` | ENOTFOUND | TEST-ENV |
| `IAM-INT-NEG-EXT-IAM-LISTPERMS` | ENOTFOUND | TEST-ENV |
| `IAM-INT-NEG-EXT-IAUTH-WRITETUPLES` | ENOTFOUND | TEST-ENV |
| `IAM-INT-NEG-EXT-TRUST-CREATE` | ENOTFOUND | TEST-ENV |
| `IAM-INT-NEG-EXT-OPA-GETBUNDLE` | ENOTFOUND | TEST-ENV |

**BACKEND-BUG (3 failures)** — internal-listener paths also hit permission_catalog authz gate via the public port-forward:

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-INT-OK-INT-USER-UPSERT` (2 asserts) | upsert-from-identity-on-internal | 403 "catalog: no entry for method" for `/iam/v1/internal/users:upsertFromIdentity` via 18080 — internal paths need catalog `<exempt>` entries or the test must target the internal port (9091) | BACKEND-BUG / TEST-ENV |
| `IAM-INT-OK-INT-IAM-LOOKUPSUBJECT` (2 asserts) | lookup-subject-on-internal | 403 for `//iam/v1/internal/iam:lookupSubject` via 18080 | BACKEND-BUG / TEST-ENV |
| `IAM-INT-OK-INT-IAM-LOOKUPSUBJECT-UNKNOWN` (2 asserts) | lookup-unknown-on-internal | Same | BACKEND-BUG / TEST-ENV |
| `IAM-INT-OK-INT-LISTPERMS` (2 asserts) | list-perms-on-internal | 403 for `/iam/v1/internal/iam/permissions` via 18080 | BACKEND-BUG / TEST-ENV |

Note: The test suite sends "internal" requests to the same `{{baseUrl}}` (18080 public port). Internal endpoints either need `<exempt>` catalog entries or the suite needs a separate `{{internalBaseUrl}}` variable pointing at port 9091.

---

### iam-jit-pending (24 failures)

All non-passing assertions return `403 permission denied: catalog: no entry for method`.

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-JITPEND-AP-OK` | approve | `JitPendingService/ApproveJITActivation` absent from catalog → 403 | BACKEND-BUG |
| `IAM-JITPEND-DN-OK` | deny, poll-op (×10), get-denied | `JitPendingService/DenyJITActivation` absent from catalog → 403; poll fails because `opId` never set | BACKEND-BUG |
| `IAM-JITPEND-GT-OK` | get-pending | `JitPendingService/GetJitPending` absent from catalog → 403 | BACKEND-BUG |
| `IAM-JITPEND-LS-OK` | list | `JitPendingService/ListJitPending` absent from catalog → 403 | BACKEND-BUG |
| `IAM-JITPEND-LS-AUTHZ-SCOPED` | list-scoped | Same | BACKEND-BUG |
| `IAM-JITPEND-LS-AUTHZ-ANON-DENY` | list-anon | Catalog missing → 403 instead of 401 (UNAUTHENTICATED) | BACKEND-BUG |

Root cause: `kacho.cloud.iam.v1.JitPendingService/*` entries not present in `permission_catalog.json`.

---

### iam-project (1 failure)

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-PRJ-CR-NEG-ACCOUNT-MISSING` | create-bad-account: sync 200 or 400 | Returns 403 instead of 400/404 — authz gate fires before accountId validation | BACKEND-BUG |

Same root cause as iam-group bad-account failure.

---

### iam-service-account (1 failure)

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-SVA-CR-NEG-PROJECT-MISSING` | create-bad-account: sync 200 or 400 | Returns 403 instead of 400/404 — authz gate fires before accountId/projectId validation | BACKEND-BUG |

Same root cause as iam-group/iam-project bad-account failures.

---

### iam-user (3 failures)

| Case ID | Step | Reason | Classification |
|---|---|---|---|
| `IAM-USR-LS-AUTHZ-MEMBER-SEES` | invitee sees users in accountB (member) | Invitee user gets empty list for `accountBId` despite having a viewer binding (invited to accountB) — ListUsers scope-filter not passing members through | BACKEND-BUG |
| `IAM-USR-INV-NEG-ROLE-MISSING` (2 asserts) | status 400 + grpc code 3 (INVALID_ARGUMENT) | Returns 200+async instead of sync 400 InvalidArgument when roleId is non-existent — validation is deferred to worker instead of sync pre-check | BACKEND-BUG |

---

## Fixes Applied in This Session (KAC-133)

### test(newman): LBR/LBS POST → GET fix (commit `70e3277`)

`ListByResource` and `ListBySubject` have `get:` HTTP bindings in proto; the
`rest_route_table_gen.go` maps them as GET, and the permission catalog has them as
`<exempt>` GET entries. The test cases were sending `POST` with a JSON body, hitting
`"catalog: no entry for method"` (no POST route exists).

Fixed: 6 `Step` definitions in `tests/newman/cases/iam-access-binding.py` changed from
`method="POST", body={...}` to `method="GET", path="...?resourceType=...&resourceId=..."`.
All 12 collections regenerated via `python3 scripts/gen.py`.

Result: iam-access-binding improved from 62/73 to 69/73 (+7 assertions).

---

## Classified Backend Bugs (not fixed in this session)

| Bug | Suite(s) | Fix owner |
|---|---|---|
| `JitPendingService/*` absent from permission_catalog.json | iam-jit-pending (24) | kacho-api-gateway |
| `ComplianceReportService/*` absent from permission_catalog.json | iam-compliance-report (23) | kacho-api-gateway |
| Internal endpoint paths not in permission catalog (or test uses wrong port) | iam-internal-only-check (4 BE failures) | kacho-api-gateway + test env |
| `ListByResource` / `ListBySubject` scope isolation not enforced for GET | iam-access-binding (2) | kacho-iam |
| AccessBinding `Create` idempotency (ON CONFLICT) broken | iam-access-binding (1) | kacho-iam |
| Account `Create` dup-name not returning ALREADY_EXISTS | iam-account (2) | kacho-iam |
| authz gate fires before accountId/projectId validation in Create | iam-project, iam-group, iam-service-account (3) | kacho-iam |
| `ListUsers` scope-filter not passing members through for cross-account invited user | iam-user (1) | kacho-iam |
| `InviteUser` roleId validation deferred to async instead of sync 400 | iam-user (2) | kacho-iam |
| FGA tuple not propagated for per-resource SA/apitoken grants on vpc resources | authz-sa-apitoken (2) | kacho-iam + kacho-vpc |

## Test-Environment Gaps (not backend bugs)

| Gap | Suite | Fix |
|---|---|---|
| `api.kacho.local:443` not in /etc/hosts → ENOTFOUND (8 ENOTFOUND errors) | iam-internal-only-check | Add `127.0.0.1 api.kacho.local` to /etc/hosts or mock the external URL in local env |
| "no-leak" assertions use `expected false to be undefined` — when ENOTFOUND response body is empty `{}`/error, `response.json().id` returns `false` (not `undefined`) because JS coercion | iam-internal-only-check | Fix test assertions to check `!response.json().id` or skip when ENOTFOUND |
| Internal paths tested via public port (18080) — catalog gate blocks them | iam-internal-only-check | Add second env var `internalBaseUrl` pointing to 9091, update suite to use it |
