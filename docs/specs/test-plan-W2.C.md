# Test Plan — W2.C: API tokens (`kat_…`)

> **Source**: [docs/specs/sub-phase-W2.C-stream-c-api-tokens-acceptance.md](sub-phase-W2.C-stream-c-api-tokens-acceptance.md) (APPROVED 2026-05-24)
> **Status**: PLAN (no code yet — code lives in feature-impl PRs per acceptance DoD)
> **Branch (eventual impl)**: `KAC-W2C` (kacho-proto / kacho-iam / kacho-api-gateway)

## 1. Per-GWT mapping

### 6.1 POSITIVE — Create returns plaintext once

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.C-CREATE-HAPPY | Create returns plaintext once; format `kat_<32>` | `internal/apps/kacho/api/api_token/create_integration_test.go::Test_APIToken_Create_HappyReturnsPlaintextOnce` | `iam-api-token.py::CREATE-HAPPY-PLAINTEXT-ONCE` |
| W2.C-CREATE-REDACT | Operation.Get second time → `plaintext=""` (parity W1.6 #11) | `internal/apps/kacho/api/api_token/create_redact_integration_test.go::Test_APIToken_Create_OperationRedactsPlaintextAfterFirstRead` | (combined with CREATE-HAPPY-PLAINTEXT-ONCE) |
| W2.C-AUTHN-HAPPY | Bearer kat_<plaintext> authenticates in-scope RPC | `kacho-api-gateway/internal/middleware/auth_kat_integration_test.go::Test_Auth_BearerKat_InScopeRPC_Allows` | `iam-api-token.py::AUTHN-WITH-KAT-OK` |

### 6.2 POSITIVE — List/Get redact

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.C-LIST-EXCLUDES-REVOKED | List default excludes revoked | `internal/apps/kacho/api/api_token/list_integration_test.go::Test_APIToken_List_DefaultExcludesRevoked` | `iam-api-token.py::LIST-EXCLUDES-REVOKED` |
| W2.C-LIST-INCLUDES-REVOKED | List with `include_revoked=true` returns revoked rows | `internal/apps/kacho/api/api_token/list_integration_test.go::Test_APIToken_List_IncludeRevoked_Returns` | — |
| W2.C-GET-REDACTED | Get returns no hash, plaintext="" | `internal/apps/kacho/api/api_token/get_integration_test.go::Test_APIToken_Get_RedactsHashAndPlaintext` | `iam-api-token.py::GET-REDACTS-HASH-PLAINTEXT` |

### 6.3 POSITIVE — Revoke invalidates cache

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.C-REVOKE-TTL | Revoke → cache invalid within TTL → subsequent authn fails | `internal/apps/kacho/api/api_token/revoke_integration_test.go::Test_APIToken_Revoke_InvalidatesCache_WithinTTL` | `iam-api-token.py::REVOKE-INVALIDATES-CACHE` |
| W2.C-REVOKE-TTL-FALLBACK | Cache miss → DB read confirms revoked | `kacho-api-gateway/internal/middleware/api_token_cache_integration_test.go::Test_APITokenCache_Miss_DBFallback_ReturnsRevoked` | — |

### 6.4 NEGATIVE — Token authn rejects

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.C-AUTHN-OUT-OF-SCOPE | In-scope token used for out-of-scope RPC → 403 | `kacho-api-gateway/internal/middleware/authz_kat_scope_integration_test.go::Test_AuthZ_BearerKat_OutOfScope_Denies` | `iam-api-token.py::AUTHN-OUT-OF-SCOPE-403` |
| W2.C-AUTHN-EXPIRED | Expired ttl_seconds → 401 "token expired" | `kacho-api-gateway/internal/middleware/auth_kat_integration_test.go::Test_Auth_BearerKat_Expired_Rejects401` | `iam-api-token.py::AUTHN-EXPIRED-401` |
| W2.C-AUTHN-REVOKED | Revoked token → 401 "token revoked" | `kacho-api-gateway/internal/middleware/auth_kat_integration_test.go::Test_Auth_BearerKat_Revoked_Rejects401` | (combined with REVOKE-INVALIDATES-CACHE) |
| W2.C-AUTHN-MALFORMED-PREFIX | Bearer without `kat_` prefix → unauthorized | `kacho-api-gateway/internal/middleware/auth_kat_integration_test.go::Test_Auth_Bearer_NoKatPrefix_Skips` | — |
| W2.C-AUTHN-MALFORMED-FORMAT | `Bearer kat_short` → 401 "malformed API token" | `kacho-api-gateway/internal/middleware/auth_kat_integration_test.go::Test_Auth_BearerKat_TooShort_RejectsMalformed401` | `iam-api-token.py::AUTHN-MALFORMED-401` |
| W2.C-AUTHN-WRONG-SECRET | Valid prefix + wrong 17 chars → 401 "token invalid" | `kacho-api-gateway/internal/middleware/auth_kat_integration_test.go::Test_Auth_BearerKat_WrongSecret_RejectsInvalid401` | `iam-api-token.py::AUTHN-WRONG-SECRET-401` |

### 6.5 NEGATIVE — Create/Delete authority + identity-spoofing

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.C-CREATE-SPOOF-DENY | Spoofed subject_id ≠ principal → InvalidArgument (parity W1.6 #53) | `internal/apps/kacho/api/api_token/create_authority_integration_test.go::Test_APIToken_Create_SpoofSubjectId_Denies` | (covered by anti-anon allowlist regressions) |
| W2.C-CREATE-ADMIN-ALLOW | account-admin creates for member-user → allowed | `internal/apps/kacho/api/api_token/create_authority_integration_test.go::Test_APIToken_Create_AdminCreatesForMember_Allows` | — |
| W2.C-CREATE-ANON-DENY | Anonymous → 401 (W1.6 anti-anon) | `internal/apps/kacho/api/api_token/create_anon_integration_test.go::Test_APIToken_Create_Anon_Rejects401` | `iam-api-token.py::CREATE-ANON-DENY` |
| W2.C-CREATE-EMPTY-SCOPE-DENY | Empty scopes_allowed → InvalidArgument | `internal/apps/kacho/api/api_token/create_validate_integration_test.go::Test_APIToken_Create_EmptyScope_InvalidArgument` | — |
| W2.C-CREATE-ALLOW-ZERO-SCOPE | `scopes_allowed=["*"]` allows all (admin/sa subjects only) | `internal/apps/kacho/api/api_token/create_scope_integration_test.go::Test_APIToken_Create_StarScope_AdminOnly` | — |
| W2.C-DELETE-STRANGER-DENY | Stranger deletes someone else's token → 403 (parity W1.6 #13) | `internal/apps/kacho/api/api_token/delete_authority_integration_test.go::Test_APIToken_Delete_Stranger_Denies` | `iam-api-token.py::DELETE-STRANGER-DENY` |
| W2.C-DELETE-ANON-DENY | Anonymous Delete → 401 | `internal/apps/kacho/api/api_token/delete_anon_integration_test.go::Test_APIToken_Delete_Anon_Rejects401` | — |
| W2.C-LIST-FOREIGN-DENY | List `subject_id=otherUser` → 403 (parity W1.6 #12) | `internal/apps/kacho/api/api_token/list_authority_integration_test.go::Test_APIToken_List_ForeignSubject_Denies` | `iam-api-token.py::LIST-FOREIGN-DENY` |
| W2.C-GET-FOREIGN-DENY | Get other user's token → 403/404 | `internal/apps/kacho/api/api_token/get_authority_integration_test.go::Test_APIToken_Get_Foreign_Denies` | — |

### 6.6 EDGE cases

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.C-EDGE-PREFIX-COLLISION | Generation re-rolls on rare prefix collision | `internal/apps/kacho/api/api_token/create_collision_integration_test.go::Test_APIToken_Create_PrefixCollision_Retries` (seeded RNG forcing collision) | — |
| W2.C-EDGE-CONCURRENT-REVOKE | Two concurrent Delete RPCs → first wins, second FailedPrecondition (CAS, §запрет #10) | `internal/repo/kacho/pg/api_token_cas_integration_test.go::Test_APIToken_Revoke_ConcurrentCAS_OneWins` (concurrent goroutines + race-build) | — |
| W2.C-EDGE-SUBJECT-DELETE-CASCADE | Subject (User/SA) deleted → token rows cascade-deleted | `internal/repo/kacho/pg/api_token_cascade_integration_test.go::Test_APIToken_SubjectDeleteCascades_DropRows` | — |
| W2.C-EDGE-DANGLING-SUBJECT-REJECTED | Create with non-existent subject_id → InvalidArgument (FK 23503) | `internal/apps/kacho/api/api_token/create_dangling_subject_integration_test.go::Test_APIToken_Create_DanglingSubject_InvalidArgument` | — |
| W2.C-EDGE-CREATE-ZERO-TTL | `ttl_seconds=0` → no expiry (admin opt-in) | `internal/apps/kacho/api/api_token/create_zero_ttl_integration_test.go::Test_APIToken_Create_ZeroTTL_NoExpiry` | — |
| W2.C-EDGE-CACHE-LRU-EVICTION | Cache bounded LRU size=100; >100 entries still re-look up | `kacho-api-gateway/internal/middleware/api_token_cache_lru_test.go::Test_APITokenCache_LRU_BoundedEvictsCorrectly` (unit, deterministic RNG) | — |

### 6.7 Newman E2E (full CRUD + 6 negative)

| Newman id | Test name | GWT linked |
|---|---|---|
| W2.C-NM-01 | `iam-api-token.py::CREATE-HAPPY-PLAINTEXT-ONCE` | CREATE-HAPPY |
| W2.C-NM-02 | `iam-api-token.py::AUTHN-WITH-KAT-OK` | AUTHN-HAPPY |
| W2.C-NM-03 | `iam-api-token.py::AUTHN-OUT-OF-SCOPE-403` | AUTHN-OUT-OF-SCOPE |
| W2.C-NM-04 | `iam-api-token.py::AUTHN-EXPIRED-401` | AUTHN-EXPIRED |
| W2.C-NM-05 | `iam-api-token.py::AUTHN-MALFORMED-401` | AUTHN-MALFORMED-FORMAT |
| W2.C-NM-06 | `iam-api-token.py::AUTHN-WRONG-SECRET-401` | AUTHN-WRONG-SECRET |
| W2.C-NM-07 | `iam-api-token.py::LIST-EXCLUDES-REVOKED` | LIST-EXCLUDES-REVOKED |
| W2.C-NM-08 | `iam-api-token.py::GET-REDACTS-HASH-PLAINTEXT` | GET-REDACTED |
| W2.C-NM-09 | `iam-api-token.py::DELETE-IDEMPOTENT` | (extra — delete + repeat) |
| W2.C-NM-10 | `iam-api-token.py::DELETE-STRANGER-DENY` | DELETE-STRANGER-DENY |
| W2.C-NM-11 | `iam-api-token.py::LIST-FOREIGN-DENY` | LIST-FOREIGN-DENY |
| W2.C-NM-12 | `iam-api-token.py::CREATE-ANON-DENY` | CREATE-ANON-DENY |
| W2.C-NM-13 | `iam-api-token.py::REVOKE-INVALIDATES-CACHE` | REVOKE-TTL |
| W2.C-NM-14 | `iam-api-token.py::AUDIT-EMIT` (conditional, skipped when B.9 not merged) | — |

## 2. Test infrastructure required

- **Testcontainers**: `postgres:16-alpine` for migration `0026_w2c_api_tokens.sql` (FK trigger + partial UNIQUE + cascade)
- **Bufconn gRPC servers**: `kacho-iam` (full registration) + `kacho-api-gateway` (auth+authz middleware + cache + drainer)
- **Httptest**: not required (kat_-format authn is internal flow)
- **Fixtures**:
  - 4 test subjects: `usr_alice` (account-admin), `usr_bob` (account-member), `usr_carol` (stranger), `sa_payments` (service-account)
  - `tests/newman/fixtures/api_token/setup.sh` — pre-creates accounts/projects + grants admin/member bindings via FGA
- **Helpers**:
  - `internal/clock/testclock.go` — for W2.C-AUTHN-EXPIRED (sleep 2s mock) + W2.C-EDGE-CONCURRENT-REVOKE timing
  - `internal/secret/genkat_test.go` — seeded RNG to deterministically force prefix collision for W2.C-EDGE-PREFIX-COLLISION
- **Drainer**: real W1.2 `subject_change_outbox` drainer runs in goroutine; W2.C-REVOKE-TTL test must wait ≤5s for drain
- **External**: VictoriaLogs (B.9-dependent) — `iam-api-token.py::AUDIT-EMIT` SKIPPED if `KACHO_AUDIT_ENABLED=false`

## 3. Coverage gates (DoD on impl-PR)

- **Integration coverage ≥80%** in: `kacho-iam/internal/apps/kacho/api/api_token/`, `kacho-iam/internal/repo/kacho/pg/api_token_*.go`, `kacho-iam/internal/domain/api_token.go`, `kacho-api-gateway/internal/middleware/{auth.go,authz.go,api_token_cache.go}`
- **Newman per RPC** (4 RPCs in `api_token_service.proto`): Create + Get + List + Delete — each has ≥1 happy + 1 negative. 13 (or 14 with B.9) cases enumerated above
- **Concurrent-race scenarios**:
  - **W2.C-EDGE-CONCURRENT-REVOKE** — concurrent Delete → CAS race (§запрет #10)
  - **W2.C-EDGE-PREFIX-COLLISION** — seeded-RNG collision triggers retry path
- **DB-level invariants**:
  - **Partial UNIQUE** on hash (where revoked_at IS NULL) — `Test_APIToken_DuplicateHash_AlreadyExists` (constraint test)
  - **FK trigger** on subject_id → cascade-delete test (W2.C-EDGE-SUBJECT-DELETE-CASCADE)
- **Cache TTL bound**: W2.C-REVOKE-TTL test asserts subsequent authn FAILS within 5s (TTL=2s + drainer-tick=1s + slack=2s)
- **Coverage gate `coverage.py --min 100`** post-merge: `ApiTokenService` (4 RPCs) covered in newman; baseline 1144 → 1157 (or 1158)

## 4. Test sequencing for TDD (RED-before-GREEN per workspace §12)

1. **RED phase (proto)**: `buf lint` + `buf breaking` checks (vs main). Add `api_token.proto` + `api_token_service.proto` + regen. CI red because handler missing.
2. **RED phase (migration)**: `0026_w2c_api_tokens.sql` written; `Test_APIToken_DuplicateHash_AlreadyExists` red (table doesn't exist).
3. **RED phase (integration)**: all §1 integration tests + newman §6.7 cases committed first → CI fully red.
4. **GREEN phase ordered**:
   1. Migration applied → DB-level constraints integration tests GREEN
   2. Domain (newtypes + Validate) + Repo (Reader/Writer + pg) → repo integration tests GREEN
   3. Use-case Create + redaction → CREATE-HAPPY → CREATE-REDACT GREEN
   4. Use-case Delete (CAS) + drainer → REVOKE-TTL + EDGE-CONCURRENT-REVOKE GREEN
   5. Use-case List + Get + authority → LIST/GET cases GREEN
   6. Gateway middleware auth.go `Bearer kat_` branch + cache → AUTHN-HAPPY/EXPIRED/REVOKED/MALFORMED GREEN
   7. Gateway authz.go scope-gate → AUTHN-OUT-OF-SCOPE GREEN
   8. Drainer integration → subject_change_outbox `api_token_revoke` event handling GREEN
   9. AuditLogger port (no-op default) + AUDIT-EMIT conditional case
5. **Cross-repo merge order**: kacho-proto → kacho-iam → kacho-api-gateway (per workspace §«Кросс-репо зависимости»)
6. **RED→GREEN evidence in PR description**: per-fragment commit hash pair

## 5. Out-of-scope tests (boundary, not omission)

- **OAuth-style refresh-token flow** — out of scope; `kat_` tokens are single-use bearer tokens
- **Per-token rate-limit** — separate concern (gateway edge rate-limit)
- **Multi-region token replication** — out of W2 scope
- **Token impersonation / OnBehalfOf** — out of scope
- **Penetration test of brute-force on 17-char secret** — mitigated by rate-limit + lockout (separate; not in W2.C)
- **`AUDIT-EMIT` newman test** — conditional on B.9 (§W2.B); SKIP allowed; explicit `pytest.skip("B.9 audit pipeline not yet merged")` — this is a **conditional skip**, NOT a `# TODO` (per workspace §13)

## 6. Coverage gaps observed in acceptance doc

- **Acceptance §6.6 EDGE cases** mention `W2.C-EDGE-PREFIX-COLLISION` and reference «seeded RNG forcing collision» but don't enumerate the helper. Implementer must add `internal/secret/testgen.go` exposing `SeededRNG(seed int64) io.Reader` — small fixture-detail, not a gap.
- **`AUDIT-EMIT` conditional skip** is the ONE allowed exception to the «no skip» rule (per acceptance §6.7 NM-14). It's documented and explicit; not technical debt.
- **OQ-W2.C-3** (cache invalidation latency target) — acceptance defaults to 5s end-to-end; if reviewer mandates tighter (e.g. 2s), tighten W2.C-REVOKE-TTL assertion. No test impact today.

No new follow-up KAC needed; impl handles fixture-helper additions as part of regular work.

## 7. Cross-reference

- Acceptance source: [docs/specs/sub-phase-W2.C-stream-c-api-tokens-acceptance.md](sub-phase-W2.C-stream-c-api-tokens-acceptance.md)
- Companion plans: [test-plan-W2.A.md](test-plan-W2.A.md) (api-token RPCs require catalog entry; W2.A unified catalog includes ApiTokenService), [test-plan-W2.D.md](test-plan-W2.D.md) (does NOT cover api-tokens — W2.D 13 new suites exclude `iam-api-token.py` because the latter ships within W2.C own scope), [test-plan-W2.B.md](test-plan-W2.B.md) (B.9 audit pipeline gates `AUDIT-EMIT` newman case)
- Workspace rules: `CLAUDE.md` §«Запреты» #10 (CAS for Revoke), #11 (no TODO; `AUDIT-EMIT` skip is conditional, not TODO), #12 (test-first RED→GREEN per fragment); §«Within-service refs DB-уровень обязателен» for partial UNIQUE on hash + FK trigger on subject_id
- Naming conventions: Go integration `Test_APIToken_<Scenario>` in `internal/apps/kacho/api/api_token/`; newman `iam-api-token.py::Case(id="<KIND>-<DESCRIPTION>")` snake-upper
