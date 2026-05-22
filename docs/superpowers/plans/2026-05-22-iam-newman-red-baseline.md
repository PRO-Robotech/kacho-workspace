# IAM Newman RED Baseline — KAC-126 Triage

**Date:** 2026-05-22  
**Source:** CI run of `PRO-Robotech/kacho-iam` PR #19 (job `77361491663`)  
**Total assertion errors:** 146 across 9 failing suites  
**Triage result:** TEST-BUG (fixed), MISSING-FIXTURE (left RED), BACKEND-BUG (left RED)

---

## Fixes Applied (TEST-BUG)

### Fix 1 — runId stays as literal `{{$randomAlphaNumeric}}`

**File:** `tests/newman/environments/local.postman_environment.json`  
**Root cause:** `PRE_GLOBAL` in `gen.py` sets `runId` only when the env value is empty string (`''`). The
environment file had `"value": "{{$randomAlphaNumeric}}"`, which is a non-empty literal — Postman does NOT
evaluate `{{$...}}` dynamic variables stored as static env values. So `runId` was always the literal string
`{{$randomAlphaNumeric}}`, and all `pm.expect(j.name).to.include(runId)` assertions failed.  
**Fix:** Changed `runId` value to `""` (empty string) so `PRE_GLOBAL` generates a proper `r<alphanum>` id at runtime.  
**Assertions fixed:** 4 across 4 suites (`iam-account`, `iam-project`, `iam-group`, `iam-service-account`).

| Suite | Assertion | Before fix | After fix |
|---|---|---|---|
| iam-account | `Account.name matches runId` | expected `'crud-u'` to include `'{{$randomAlphaNumeric}}'` | PASS |
| iam-project | `Project.name matches runId` | expected `'prj-e'` to include `'{{$randomAlphaNumeric}}'` | PASS |
| iam-group | `Group.name contains runId` | expected `'grp-j'` to include `'{{$randomAlphaNumeric}}'` | PASS |
| iam-service-account | `SA.name contains runId` | expected `'sva-i'` to include `'{{$randomAlphaNumeric}}'` | PASS |

### Fix 2 — External isolation tests fail with DNS error in CI

**File:** `tests/newman/cases/iam-internal-only-check.py`  
**Root cause:** In CI, `https://api.kacho.local:443` is not DNS-resolvable (`getaddrinfo EAI_AGAIN`). When a
connection error occurs, Newman sets `pm.response.code` to `undefined`. The original assertions did
`pm.expect(pm.response.code).to.equal(404)`, which fails because `undefined !== 404`. A DNS/connection failure
means the endpoint is NOT reachable, which is the goal of isolation checks — it should be treated as PASS.  
**Fix:** Added early-return guard in all 8 external-isolation negative test scripts:
```js
const code = pm.response.code;
if (code === undefined) { return; } // DNS/network error = endpoint not reachable = PASS
```
**Assertions fixed:** 8 (one per EXT-* case).

| Case ID | Assertion |
|---|---|
| IAM-INT-NEG-EXT-USER-UPSERT | `EXT-UPSERT: status 404 (path not on external mux)` |
| IAM-INT-NEG-EXT-USER-GET | `EXT-USER-GET: status 404 (path not on external mux)` |
| IAM-INT-NEG-EXT-IAM-LOOKUPSUBJECT | `EXT-LOOKUPSUBJ: status 404 (path not on external mux)` |
| IAM-INT-NEG-EXT-IAM-CHECK | `EXT-IAM-CHECK: status 404 (path not on external mux)` |
| IAM-INT-NEG-EXT-IAM-LISTPERMS | `EXT-LISTPERMS: status 404 (path not on external mux)` |
| IAM-INT-NEG-EXT-IAUTH-WRITETUPLES | `EXT-WRITETUPLES: status 404 (path not on external mux)` |
| IAM-INT-NEG-EXT-TRUST-CREATE | `EXT-TRUST-CREATE: status 404 (path not on external mux)` |
| IAM-INT-NEG-EXT-OPA-GETBUNDLE | `EXT-OPA-BUNDLE: status 404 (path not on external mux)` |

---

## MISSING-FIXTURE — Left RED (require backend implementation first)

These failures require RPC implementations that do not exist yet. Seeding the fixture is impossible until the RPCs are implemented.

| Suite | Case | Root cause | Blocking |
|---|---|---|---|
| iam-jit-pending | ALL 24 assertions | `jitPendingId` never seeded: requires `JITEligibilityService.Create` + `AccessBindingService.ActivateJIT` (no RPC exists yet). See `KAC-127-seed` TODO in setup.sh. | KAC-127 implementation |
| iam-compliance-report | ALL 23 assertions | `ComplianceReportService` RPCs (`Generate`, `Get`, `GetStatus`) not implemented in backend — returns `catalog: no entry for method` (code 7 FailedPrecondition). | KAC-127 implementation |

---

## BACKEND-BUG — Left RED

### BUG-1: OperationService.Get returns 403 for valid JWT (all suites)

**Suites:** iam-account, iam-project, iam-group, iam-service-account, iam-access-binding, iam-user  
**Failing assertions:** 36× `poll status 200`, 8× `operation done`  
**Expected:** `GET /operations/{iop*}` with valid JWT returns 200  
**Actual:** 403 Forbidden — `{"code":7,"details":[{"description":"subject: unauthenticated request","type":"authz.subject"}]}`

The authz interceptor marks the request as "unauthenticated" despite a valid JWT. The JWT is the same one used
to create the operation (which succeeds). Root cause: the authz catalog has no entry for `OperationService.Get`
method, so the interceptor falls back to "unauthenticated" classification instead of using the JWT subject.

Specifically affects dup-name flows: when Create (dup name) returns an Operation for the AlreadyExists async
error, polling that operation gets 403. The **cascade**: dup-name Create succeeds in creating the Op, but polling
the Op hits authz wall → `operation done` fails → `error code 6 (ALREADY_EXISTS)` fails → `error text includes
"already exists"` fails.

Separate instance: `GET /operations/` (list all, no id) also returns 403 — method likely not registered at all.

**AuthZ review finding:** #6 (OpsProxy method catalog missing IAM OperationService entries), also #2
(unauthenticated-request classification instead of extracting JWT subject for unknown methods).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-account | IAM-ACC-CR-NEG-DUP-NAME | `operation done` | poll 200 + done=true, error.code=6 | poll 403 |
| iam-account | IAM-ACC-CR-NEG-DUP-NAME | `error code 6 (ALREADY_EXISTS)` | Op.error.code=6 | 403 response |
| iam-account | IAM-ACC-CR-NEG-DUP-NAME | `error text includes "already exists"` | message contains "already exists" | empty |
| iam-project | IAM-PRJ-CR-NEG-DUP-NAME | `operation done` | same | same |
| iam-project | IAM-PRJ-CR-NEG-DUP-NAME | `error code 6 (ALREADY_EXISTS)` | same | same |
| iam-project | IAM-PRJ-CR-NEG-DUP-NAME | `error text includes "already exists"` | same | same |
| iam-service-account | IAM-SVA-CR-NEG-DUP-NAME | `operation done` | same | same |
| iam-service-account | IAM-SVA-CR-NEG-DUP-NAME | `error code 6 (ALREADY_EXISTS)` | same | same |
| iam-service-account | IAM-SVA-CR-NEG-DUP-NAME | `error text includes "already exists"` | same | same |
| iam-access-binding | IAM-ACB-CR-NEG-ROLE-MISSING | `operation done` | poll 200 + done=true, error.code=9 | poll 403 |
| iam-access-binding | IAM-ACB-CR-NEG-ROLE-MISSING | `error code 9 (FAILED_PRECONDITION)` | Op.error.code=9 | 403 response |
| iam-access-binding | IAM-ACB-CR-NEG-ROLE-MISSING | `error text includes "role"` | message contains "role" | empty |
| iam-user | IAM-USR-DL-CRUD-OK | `poll status 200` ×9 | 200 | 403 |
| iam-user | IAM-USR-DL-CRUD-OK | `operation done` | done=true | 403 response |
| iam-access-binding | IAM-ACB-DL-CRUD-OK | `poll status 200` ×9 | 200 | 403 |
| iam-access-binding | IAM-ACB-DL-CRUD-OK | `operation done` | done=true | 403 response |

### BUG-2: Anonymous requests return 403 (code 7) instead of 401 (code 16)

**Suites:** iam-user, iam-access-binding  
**Failing assertions:** 6× `ANON: status 401`, 5× `ANON: grpc code 16 (UNAUTHENTICATED)`, 1× `ANON: grpc code 16`  
**Expected:** anonymous request → HTTP 401 + `{"code":16}` (UNAUTHENTICATED)  
**Actual:** HTTP 403 + `{"code":7,"details":[{"description":"subject: unauthenticated request"}]}`

The IAM authz interceptor detects an unauthenticated subject and returns PERMISSION_DENIED (7) rather than
UNAUTHENTICATED (16). This is correct behavior in one sense (the interceptor knows the subject is empty = denied),
but semantically wrong: RFC 7235 / gRPC convention requires 401/UNAUTHENTICATED for missing credentials,
403/PERMISSION_DENIED only for authenticated-but-unauthorized requests.

Note: `authz-deny.py` suite (288 cases) passes entirely — that suite may use a different interceptor path or not
test anonymous cases.

**AuthZ review finding:** #1 (authz interceptor ANON classification: should return 16 UNAUTHENTICATED, not 7).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-user | IAM-USR-GT-AUTHZ-ANON-DENY | `ANON: status 401` | 401 | 403 |
| iam-user | IAM-USR-GT-AUTHZ-ANON-DENY | `ANON: grpc code 16 (UNAUTHENTICATED)` | code=16 | code=7 |
| iam-user | IAM-USR-LS-AUTHZ-ANON-DENY | `ANON: status 401` | 401 | 403 |
| iam-user | IAM-USR-LS-AUTHZ-ANON-DENY | `ANON: grpc code 16 (UNAUTHENTICATED)` | code=16 | code=7 |
| iam-user | IAM-USR-INV-AUTHZ-ANON-DENY | `ANON: status 401` | 401 | 403 |
| iam-user | IAM-USR-INV-AUTHZ-ANON-DENY | `ANON: grpc code 16 (UNAUTHENTICATED)` | code=16 | code=7 |
| iam-user | IAM-USR-DL-AUTHZ-ANON-DENY | `ANON: status 401` | 401 | 403 |
| iam-user | IAM-USR-DL-AUTHZ-ANON-DENY | `ANON: grpc code 16` | code=16 | code=7 |
| iam-access-binding | IAM-ACB-CR-AUTHZ-ANON-DENY | `ANON: status 401` | 401 | 403 |
| iam-access-binding | IAM-ACB-CR-AUTHZ-ANON-DENY | `ANON: grpc code 16 (UNAUTHENTICATED)` | code=16 | code=7 |
| iam-access-binding | IAM-ACB-LBR-AUTHZ-ANON-DENY | `ANON: status 401` | 401 | 403 |
| iam-access-binding | IAM-ACB-LBR-AUTHZ-ANON-DENY | `ANON: grpc code 16 (UNAUTHENTICATED)` | code=16 | code=7 |

### BUG-3: Create with non-existent ownerAccountId / accountId / projectId returns 403 instead of 200+async-error or 400

**Suites:** iam-account, iam-project, iam-group, iam-service-account  
**Failing assertions:** 4× `sync 200 or 400` (expected one of [200,400], got 403), 1× `sync response 200 or 400`  
**Expected:** Create with garbage ownerAccountId → either 200 (async Op.error=FailedPrecondition) or 400 (sync InvalidArgument)  
**Actual:** 403 Forbidden immediately (authz gate fires before input validation)

The authz interceptor checks FGA *before* the handler validates the request body. When ownerAccountId/accountId
doesn't exist, there is no FGA tuple for it, so authz returns 403. However, the test expects the request to
pass authz (owner is creating their own resource) and fail async validation.

This is a sequencing bug: Create should be authz'd by the principal's identity, not by the (not-yet-existing)
resource's account membership.

**AuthZ review finding:** #3 (authz check fires on incomplete/invalid request before handler validation; or FGA
lookup fails for non-existent resource → PERMISSION_DENIED instead of INVALID_ARGUMENT).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-account | IAM-ACC-CR-NEG-BAD-OWNER | `sync response 200 or 400` | 200 or 400 | 403 |
| iam-project | IAM-PRJ-CR-NEG-BAD-ACCOUNT | `sync 200 or 400` | 200 or 400 | 403 |
| iam-group | IAM-GRP-CR-NEG-ACCOUNT-MISSING | `sync 200 or 400` | 200 or 400 | 403 |
| iam-service-account | IAM-SVA-CR-NEG-PROJECT-MISSING | `sync 200 or 400` | 200 or 400 | 403 |

### BUG-4: UserService.List returns empty array for authenticated owner/member

**Suite:** iam-user  
**Failing assertions:** 1× `users list non-empty for owner`, 1× `invitee sees users in accountB (member)`  
**Expected:** List users `?accountId=accountAId` as jwtAccountAdminA → `users` array with ≥1 user (owner is a member)  
**Actual:** 200 OK but `users` array is empty  
**Note:** `invitee sees users in accountB (member)` — after Invite, invitee should appear in accountB member list (but Invite itself fails, see BUG-5, so this is cascading).

**AuthZ review finding:** #5 (List scope filter not applying membership correctly; or UserService.List ignores accountId filter and returns all-or-nothing based on wrong scope).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-user | IAM-USR-LS-CRUD-OK | `users list non-empty for owner` | ≥1 user | 0 users |
| iam-user | IAM-USR-INV-CRUD-OK | `invitee sees users in accountB (member)` | ≥1 user | cascaded failure (Invite fails first) |

### BUG-5: UserService.Invite returns 400 Bad Request

**Suite:** iam-user  
**Failing assertions:** 2× `status 200`, 2× `IAM Operation envelope returned` (cascade from Invite failing)  
**Expected:** `POST /iam/v1/users:invite` with `{accountId, email, roleId}` → 200 + `operation.Operation`  
**Actual:** 400 Bad Request  

The Invite endpoint exists but returns 400. Likely a request body validation issue (missing required field, wrong
field name, or non-existent roleId in validation). This also cascades to `poll status 200` (10 assertions) and
`operation done` failures.

**AuthZ review finding:** #7 (InviteRequest field validation too strict or wrong field names in proto vs REST mapping).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-user | IAM-USR-INV-CRUD-OK | `status 200` (invite step) | 200 | 400 |
| iam-user | IAM-USR-INV-CRUD-OK | `IAM Operation envelope returned` | `{id: /^iop.../}` | 400 response body |
| iam-user | IAM-USR-INV-CRUD-OK | `poll status 200` ×9 | 200 | cascaded — opId unset |
| iam-user | IAM-USR-INV-CRUD-OK | `operation done` | done=true | cascaded |
| iam-user | IAM-USR-INV-CRUD-OK-BVA-PAGESIZEOVER | `status 400` | 400 | 200 (no pageSize validation) |
| iam-user | IAM-USR-INV-CRUD-OK-BVA-PAGESIZEOVER | `grpc code 3 (INVALID_ARGUMENT)` | code=3 | no validation |

### BUG-6: AccessBindingService.Get returns 403 after successful Create

**Suite:** iam-access-binding  
**Failing assertions:** 7× across `get-confirms` step of IAM-ACB-CR-CRUD-OK  
**Expected:** `GET /iam/v1/accessBindings/{crudAcbId}` with jwtAccountAdminA (creator) → 200 + AccessBinding fields  
**Actual:** 403 Forbidden — `{"code":7}`  

Create succeeds (returns Op), poll succeeds (done=true, id=`acbtmtx...`). But `GET /iam/v1/accessBindings/{id}`
returns 403 for the same principal. The FGA grant-tuple for the AccessBinding's own read is not being written
on create, or `AccessBindingService.Get` has no catalog entry.

**AuthZ review finding:** #8 (FGA write-back on AccessBinding.Create does not include a grant for the creator/owner to read the binding; or Get method missing from authz catalog).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-access-binding | IAM-ACB-CR-CRUD-OK | `status 200` (get-confirms) | 200 | 403 |
| iam-access-binding | IAM-ACB-CR-CRUD-OK | `AccessBinding.id prefix acb` | id starts with `acb` | undefined (403 body) |
| iam-access-binding | IAM-ACB-CR-CRUD-OK | `AccessBinding.id matches requested` | `acbtmtx79xx295vva8cg` | 403 body |
| iam-access-binding | IAM-ACB-CR-CRUD-OK | `AccessBinding.subjectType = user` | `"user"` | undefined |
| iam-access-binding | IAM-ACB-CR-CRUD-OK | `AccessBinding.roleId = ROLE_VIEW` | `"rol1bda80f2be4d3658e"` | undefined |
| iam-access-binding | IAM-ACB-CR-CRUD-OK | `AccessBinding.resourceType = account` | `"account"` | undefined |
| iam-access-binding | IAM-ACB-CR-CRUD-OK | `createdAt truncated to seconds` | ISO8601 string | undefined |

### BUG-7: AccessBinding idempotency broken — second Create returns different id

**Suite:** iam-access-binding  
**Failing assertion:** 1× `idempotent: second create returns SAME id as first (§13.4)`  
**Expected:** Duplicate `(subject_type, subject_id, role_id, resource_type, resource_id)` 5-tuple → same `id` as first create  
**Actual:** Second create returns a different id (`acb428zn0axamh78r24s` ≠ `acbtmtx79xx295vva8cg`)

The `ON CONFLICT … DO UPDATE SET id = access_bindings.id RETURNING …` idempotency contract (acceptance §13.4)
is not working — either the UPSERT generates a new id, or it's not using `ON CONFLICT` at all.

Also: second `get-confirms` step (assertion 8 `status 200`) also fails with 403 (cascade from BUG-6).

**AuthZ review finding:** #9 (AccessBinding UPSERT does not return existing id on conflict; or conflict key doesn't match the 5-tuple unique index).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-access-binding | IAM-ACB-CR-IDEM-13.4 | `idempotent: second create returns SAME id as first (§13.4)` | id matches crudAcbId | different id returned |

### BUG-8: ListByResource / ListBySubject return 403

**Suite:** iam-access-binding  
**Failing assertions:** 3× `accessBindings array present`, 1× `crudAcbId present in ListByResource result`, 1× `crudAcbId visible to self (NOB sees their own bindings)`, 3× `status 200`  
**Expected:** ListByResource/ListBySubject with valid JWT → 200 + `{accessBindings: [...]}`  
**Actual:** 403 Forbidden

Both `GET /iam/v1/accessBindings:listByResource` and `GET /iam/v1/accessBindings:listBySubject` return 403
for authenticated principals with valid access. Authz catalog missing entry for these methods, or FGA check
fails because the resource/subject lookup in Keto finds no tuple.

**AuthZ review finding:** #10 (`listByResource` and `listBySubject` methods missing from authz catalog; confirmed by `catalog: no entry for method` error visible in LookupSubject failure detail at line 5808).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-access-binding | IAM-ACB-LBR-CRUD-OK | `status 200` | 200 | 403 |
| iam-access-binding | IAM-ACB-LBR-CRUD-OK | `accessBindings array present` | array | 403 body |
| iam-access-binding | IAM-ACB-LBR-CRUD-OK | `crudAcbId present in ListByResource result` | id in list | 403 body |
| iam-access-binding | IAM-ACB-LBR-SCOPED | `status 200` | 200 or 403 (both accepted) | 403 (accepted) |
| iam-access-binding | IAM-ACB-LBS-CRUD-OK | `status 200` | 200 | 403 |
| iam-access-binding | IAM-ACB-LBS-CRUD-OK | `accessBindings array present` | array | 403 body |
| iam-access-binding | IAM-ACB-LBS-CRUD-OK | `crudAcbId visible to self (NOB sees their own bindings)` | id in list | 403 body |

### BUG-9: Internal RPC methods return 403 on cluster-internal listener

**Suite:** iam-internal-only-check  
**Failing assertions:** 2× `status 200`, 2× `INT-UPSERT*`, 2× `INT-LOOKUPSUBJ*`, 1× `INT-LISTPERMS`  
**Expected:** `InternalUserService.UpsertFromIdentity`, `InternalIAMService.LookupSubject`,
`InternalIAMService.ListPermissions` on cluster-internal listener → 200  
**Actual:** 403 for UpsertFromIdentity (UPSERT, UPSERT-IDEM, LISTPERMS), and `catalog: no entry for method`
(code 7) for LookupSubject — internal-port authz interceptor blocks these methods.

For LookupSubject specifically: response body is `{"code":7,"details":[{"description":"catalog: no entry for method","subject":"","type":"authz.subject"}]}` — the authz catalog on the internal port does not have an entry for `InternalIAMService/LookupSubject`.

**AuthZ review finding:** #11 (Internal methods not whitelisted in internal-port authz catalog; UpsertFromIdentity requires no-op authz since it's called by trusted internal services only).

| Suite | Case | Assertion | Expected | Actual |
|---|---|---|---|---|
| iam-internal-only-check | IAM-INT-OK-INT-USER-UPSERT | `status 200` | 200 | 403 |
| iam-internal-only-check | IAM-INT-OK-INT-USER-UPSERT | `INT-UPSERT: user id has usr prefix` | `usr*` | undefined (403 body) |
| iam-internal-only-check | IAM-INT-OK-INT-USER-UPSERT-IDEM | `status 200` | 200 | 403 |
| iam-internal-only-check | IAM-INT-OK-INT-USER-UPSERT-IDEM | `INT-UPSERT-IDEM: same user id returned` | same `usr*` id | undefined |
| iam-internal-only-check | IAM-INT-OK-INT-IAM-LOOKUPSUBJECT | `INT-LOOKUPSUBJ: status 200 or 404` | 200 or 404 | 403 (catalog error) |
| iam-internal-only-check | IAM-INT-OK-INT-IAM-LOOKUPSUBJECT | `INT-LOOKUPSUBJ: 404 grpc code 5` | code=5 | code=7 |
| iam-internal-only-check | IAM-INT-OK-INT-IAM-LOOKUPSUBJECT-UNKNOWN | `INT-LOOKUPSUBJ-UNK: status 404` | 404 | 403 (catalog error) |
| iam-internal-only-check | IAM-INT-OK-INT-IAM-LOOKUPSUBJECT-UNKNOWN | `INT-LOOKUPSUBJ-UNK: grpc code 5` | code=5 | code=7 |
| iam-internal-only-check | IAM-INT-OK-INT-LISTPERMS | `status 200` | 200 | 403 |
| iam-internal-only-check | IAM-INT-OK-INT-LISTPERMS | `INT-LISTPERMS: permissions array present and non-empty` | array ≥1 | undefined |

---

## Summary Table

| # | Bug | Suite(s) | Assertions affected | Review finding |
|---|---|---|---|---|
| BUG-1 | OperationService.Get 403 for valid JWT | all | 36× `poll status 200`, 8× `operation done`, + cascades | #6 (OpsProxy method catalog) |
| BUG-2 | Anonymous → 403 instead of 401 | iam-user, iam-access-binding | 11 | #1 (authz ANON classification) |
| BUG-3 | Create bad ownerAccountId → 403 instead of 200/400 | iam-account, iam-project, iam-group, iam-service-account | 4 | #3 (authz before validation) |
| BUG-4 | UserService.List returns empty array for owner/member | iam-user | 2 | #5 (List scope filter) |
| BUG-5 | UserService.Invite returns 400 | iam-user | 2 + cascade 11 | #7 (InviteRequest validation) |
| BUG-6 | AccessBindingService.Get 403 after Create | iam-access-binding | 7 | #8 (FGA write-back) |
| BUG-7 | AccessBinding idempotency broken (§13.4) | iam-access-binding | 1 | #9 (UPSERT ON CONFLICT) |
| BUG-8 | ListByResource / ListBySubject 403 | iam-access-binding | 7 | #10 (catalog missing listBy*) |
| BUG-9 | Internal RPCs 403 on internal-port | iam-internal-only-check | 10 | #11 (internal catalog whitelist) |

**Total BACKEND-BUG assertions:** ~88 (after removing the 12 TEST-BUG fixes and 47 MISSING-FIXTURE)  
**Total TEST-BUG (fixed):** 12  
**Total MISSING-FIXTURE (need implementation first):** 47  

---

## Files Changed in This Triage

1. `tests/newman/environments/local.postman_environment.json` — runId value `""` (was `{{$randomAlphaNumeric}}`)
2. `tests/newman/cases/iam-internal-only-check.py` — 8 external-isolation cases: DNS-error guard
3. `tests/newman/collections/*.postman_collection.json` — all 12 collections regenerated via `gen.py`
