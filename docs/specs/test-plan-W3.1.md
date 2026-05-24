# Test Plan — W3.1: Remediation Chunk 5 — Federation/SSO internals (6 findings)

> **Source**: [docs/specs/sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md](sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md) (APPROVED 2026-05-24)
> **Status**: PLAN (no code yet — code lives in feature-impl PRs)
> **Branch (eventual impl)**: `KAC-XXX-w3-1-federation` (kacho-iam + kacho-proto if scope-allowlist proto change needed)
> **Parent KAC**: KAC-170 (epic-bundle); W3.1 closes Chunk 5 of Remediation plan §1.3

## 1. Per-GWT mapping

### 5.21 / 6.21 — OPA scope-allowlist (#21)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W3.1-21-HAPPY | Allowlisted scope → eval proceeds | `internal/apps/kacho/api/opa/scope_allowlist_integration_test.go::Test_OpaEval_AllowlistedScope_Allows` | `iam-opa-scope.py::OPA-SCOPE-ALLOWLISTED-OK` |
| W3.1-21-UNKNOWN-SCOPE | Non-allowlisted scope → 403 deny + structured log | `internal/apps/kacho/api/opa/scope_allowlist_integration_test.go::Test_OpaEval_UnknownScope_Denies403_LogsEvent` | `iam-opa-scope.py::OPA-SCOPE-UNKNOWN-403` |
| W3.1-21-EMPTY-ALLOWLIST-FAIL-CLOSED | Mis-bootstrap → empty allowlist → deny all | `internal/apps/kacho/api/opa/scope_allowlist_integration_test.go::Test_OpaEval_EmptyAllowlist_FailsClosed` | `iam-opa-scope.py::OPA-SCOPE-EMPTY-ALLOWLIST-FAILCLOSED` (uses fixture that DROPs seed before run) |

### 5.23 / 6.23 — CheckRelation OpenFGA Conditions plumbing (#23)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W3.1-23-HAPPY-MFA | Conditional binding `mfa_fresh_required` with MFA context → allow | `internal/apps/kacho/api/authorize/check_relation_context_integration_test.go::Test_CheckRelation_MFAContext_Allows` | `iam-checkrelation.py::CHECKRELATION-CTX-MFA-ALLOW` |
| W3.1-23-CONTEXT-DENY | Same binding, mfa_fresh=false → deny | `internal/apps/kacho/api/authorize/check_relation_context_integration_test.go::Test_CheckRelation_MFAContextFalse_Denies` | `iam-checkrelation.py::CHECKRELATION-CTX-MFA-DENY` |
| W3.1-23-MALFORMED-OVERSIZE | request_context >32 keys → InvalidArgument | `internal/apps/kacho/api/authorize/check_relation_context_integration_test.go::Test_CheckRelation_ContextOversize_InvalidArgument` | `iam-checkrelation.py::CHECKRELATION-CTX-OVERSIZE-400` |
| W3.1-23-MALFORMED-VALUE | Single value >1KB → InvalidArgument | `internal/apps/kacho/api/authorize/check_relation_context_integration_test.go::Test_CheckRelation_ValueOversize_InvalidArgument` | (combined with OVERSIZE-400) |

### 5.25 / 6.25 — ReloadModel cluster-admin gate (#25)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W3.1-25-HAPPY | cluster-admin ReloadModel → version bump | `internal/apps/kacho/api/internal_iam/reload_model_integration_test.go::Test_ReloadModel_ClusterAdmin_VersionBumps` | `iam-internal-iam.py::INT-IAM-RELOADMODEL-OK` |
| W3.1-25-ANON-DENY | Anonymous ReloadModel → 401 | `internal/apps/kacho/api/internal_iam/reload_model_integration_test.go::Test_ReloadModel_Anon_Rejects401` | `iam-internal-iam.py::INT-IAM-RELOADMODEL-ANON-DENY` |
| W3.1-25-NON-ADMIN-DENY | Authenticated non-admin → 403 | `internal/apps/kacho/api/internal_iam/reload_model_integration_test.go::Test_ReloadModel_NonAdmin_Rejects403` | `iam-internal-iam.py::INT-IAM-RELOADMODEL-NON-ADMIN-DENY` |

### 5.26 / 6.26 — RunRegoTest sandbox (#26)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W3.1-26-HAPPY | Bounded Rego eval → returns result | `internal/apps/kacho/api/internal_iam/rego_test_sandbox_integration_test.go::Test_RunRegoTest_BoundedEval_ReturnsResult` | `iam-internal-iam.py::INT-IAM-REGOTEST-HAPPY` |
| W3.1-26-FORBIDDEN-HTTP | `http.send` builtin → reject at parse-time → 403 | `internal/apps/kacho/api/internal_iam/rego_test_sandbox_integration_test.go::Test_RunRegoTest_HttpSendBuiltin_Rejects403` | `iam-internal-iam.py::INT-IAM-REGOTEST-FORBIDDEN-HTTP` |
| W3.1-26-FORBIDDEN-BUILTINS-TABLE | All forbidden builtins (table-driven) rejected | `internal/apps/kacho/api/internal_iam/rego_test_sandbox_integration_test.go::Test_RunRegoTest_ForbiddenBuiltinsTable` (subtests per builtin) | `iam-internal-iam.py::INT-IAM-REGOTEST-FORBIDDEN-TABLE` (parameterized) |
| W3.1-26-ALLOWED-PURE-BUILTINS | Pure-computation builtins allowed | `internal/apps/kacho/api/internal_iam/rego_test_sandbox_integration_test.go::Test_RunRegoTest_PureBuiltins_Allowed` | `iam-internal-iam.py::INT-IAM-REGOTEST-ALLOWED-PURE` |
| W3.1-26-CPU-TIMEOUT | Infinite loop → DeadlineExceeded → 403 | `internal/apps/kacho/api/internal_iam/rego_test_sandbox_integration_test.go::Test_RunRegoTest_InfiniteLoop_DeadlineExceeded` (CPU bound ≤500ms) | `iam-internal-iam.py::INT-IAM-REGOTEST-CPU-TIMEOUT` |
| W3.1-26-UNKNOWN-IMPORT | Import not in allowlist → 403 | `internal/apps/kacho/api/internal_iam/rego_test_sandbox_integration_test.go::Test_RunRegoTest_UnknownImport_Rejects403` | `iam-internal-iam.py::INT-IAM-REGOTEST-UNKNOWN-IMPORT` |
| W3.1-26-NON-ADMIN-DENY | Non-cluster-admin → 403 (parity #25) | `internal/apps/kacho/api/internal_iam/rego_test_sandbox_integration_test.go::Test_RunRegoTest_NonAdmin_Rejects403` | `iam-internal-iam.py::INT-IAM-REGOTEST-NON-ADMIN-DENY` |

### 5.40 / 6.40 — SAML AuthnResponse verify + replay state (#40)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W3.1-40-HAPPY | Trusted IdP cert + valid sig → JIT user | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_TrustedSig_ProvisionsJITUser` (uses pre-generated test cert + raw XML AuthnResponse fixture) | `iam-saml.py::SAML-ACS-VERIFIED-OK` |
| W3.1-40-TAMPERED-SIGNATURE | Sig mismatch → 401 | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_TamperedSignature_Rejects401` | `iam-saml.py::SAML-ACS-TAMPERED-401` |
| W3.1-40-NO-ASSERTION-SIG | Response signed but Assertion not → 401 | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_NoAssertionSig_Rejects401` | `iam-saml.py::SAML-ACS-NO-ASSERTION-SIG-401` |
| W3.1-40-EXPIRED-NOTONORAFTER | Stale assertion → 401 | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_Expired_Rejects401` | `iam-saml.py::SAML-ACS-EXPIRED-401` |
| W3.1-40-NOTBEFORE-FUTURE | Premature assertion → 401 | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_NotBeforeFuture_Rejects401` | `iam-saml.py::SAML-ACS-NOTBEFORE-FUTURE-401` |
| W3.1-40-REPLAY | Same Response.InResponseTo twice → 401 on second | `internal/apps/kacho/api/saml/acs_replay_integration_test.go::Test_SAML_ACS_Replay_RejectsSecond401` (CAS on saml_request_states table) | `iam-saml.py::SAML-ACS-REPLAY-401` |
| W3.1-40-WEAK-ALG | rsa-sha1 → 401 | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_WeakAlg_Rejects401` | `iam-saml.py::SAML-ACS-WEAK-ALG-401` |
| W3.1-40-WRONG-RECIPIENT | Recipient ≠ our ACS URL → 401 | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_WrongRecipient_Rejects401` | `iam-saml.py::SAML-ACS-WRONG-RECIPIENT-401` |
| W3.1-40-WRONG-AUDIENCE | Audience ≠ our SP entity-ID → 401 | `internal/apps/kacho/api/saml/acs_verify_integration_test.go::Test_SAML_ACS_WrongAudience_Rejects401` | `iam-saml.py::SAML-ACS-WRONG-AUDIENCE-401` |

### 5.42 / 6.42 — CAEP SET ingress verify (#42)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W3.1-42-VERIFY-OK | SET signed by trusted IdP → emit subject_change_outbox row | `internal/apps/kacho/api/caep_ingress/verify_integration_test.go::Test_CAEP_Ingress_Verified_EmitsSubjectChangeOutbox` (uses synthetic IdP stub) | `iam-caep-ingress.py::CAEP-INGRESS-VERIFIED-OK` |
| W3.1-42-VERIFY-BADSIG | Tampered SET → 400 + audit | `internal/apps/kacho/api/caep_ingress/verify_integration_test.go::Test_CAEP_Ingress_BadSig_Rejects400_AuditEmitted` | `iam-caep-ingress.py::CAEP-INGRESS-BADSIG-400` |
| W3.1-42-UNKNOWN-KID | Unregistered kid → refresh-cache once → still unknown → reject | `internal/apps/kacho/api/caep_ingress/verify_integration_test.go::Test_CAEP_Ingress_UnknownKid_RefreshOnceReject` | `iam-caep-ingress.py::CAEP-INGRESS-UNKNOWN-KID-400` |
| W3.1-42-WEAK-ALG | Symmetric alg / `alg: none` → reject | `internal/apps/kacho/api/caep_ingress/verify_integration_test.go::Test_CAEP_Ingress_WeakAlg_Rejects400` | `iam-caep-ingress.py::CAEP-INGRESS-WEAK-ALG-400` |
| W3.1-42-UNKNOWN-ISSUER | Issuer not in trusted_idp_registry → reject | `internal/apps/kacho/api/caep_ingress/verify_integration_test.go::Test_CAEP_Ingress_UnknownIssuer_Rejects400` | `iam-caep-ingress.py::CAEP-INGRESS-UNKNOWN-ISSUER-400` |

## 2. Test infrastructure required

- **Testcontainers**: `postgres:16-alpine` (kacho-iam migrations including new `opa_scope_allowlist` + `iam_trusted_idp_registry` + `iam_trusted_idp_jwks_cache` + `saml_request_states`); `openfga/openfga:v1.5+`
- **Bufconn gRPC server**: kacho-iam with full registration
- **Synthetic IdP stub** (for #42 CAEP ingress): in-process HTTP server serving JWKS endpoint + helper that signs test SETs with paired private key (CGO-free `go-jose`)
- **SAML fixtures**: pre-generated test cert + raw XML AuthnResponse files committed under `tests/newman/fixtures/saml/` (per acceptance §6.40 + §7.2 Option A — uses `crewjam/saml`'s own test pattern; no live IdP needed)
- **CAEP fixtures**: `tests/newman/fixtures/caep/test_idp_jwks.json` + `test_idp_private_key.pem` (test-only, readme warns) + `seed_trusted_idp.sql` seeds `iam_trusted_idp_registry` row for `idp_test_caep_emitter`
- **OPA scope-allowlist seed**: bootstrap-seed for `data.iam.{users,roles,bindings,projects}` present; `iam-opa-scope.py::OPA-SCOPE-EMPTY-ALLOWLIST-FAILCLOSED` uses fixture that DROPs seed before run
- **External services**: no IdP needed (cert-based fixtures); no Kratos / no Okta

## 3. Coverage gates (DoD on impl-PR)

- **Integration coverage ≥80%** in: `internal/apps/kacho/api/{opa,authorize,internal_iam,saml,caep_ingress}/`
- **Newman per RPC**: each of 6 findings has ≥3 newman cases (happy + 1+ negative + 1 edge). Total: ~32 new cases across new suites
- **Concurrent-race scenarios**:
  - **W3.1-40-REPLAY** — CAS on `saml_request_states` (`Test_SAML_ACS_Replay_RejectsSecond401`) — must include concurrent goroutines (2 parallel POSTs with same InResponseTo)
- **Property tests / anti-leak (acceptance §7.4)**:
  - `Test_OpaEval_AllowlistedScope_NeverLeaksDeniedScope_Property` — fuzz allowlist permutations
  - `Test_SAML_ACS_NeverEchoesAssertionPayloadOnFailure_Property` — failure response never includes raw assertion (audit-only)
  - `Test_CAEP_Ingress_NeverLeaksTrustedIdpSigningSecret_Property`
- **Coverage gate `coverage.py --min 100`**: every new RPC/endpoint covered

## 4. Test sequencing for TDD (RED-before-GREEN per workspace §12)

1. **RED phase (per finding, ordered)** — write ALL integration tests + newman cases first
   - #21 OPA scope-allowlist tests: red because handler doesn't enforce allowlist
   - #23 CheckRelation context tests: red because plumbing doesn't pass `Context` to FGA
   - #25 ReloadModel gate tests: red because no admin-check
   - #26 RunRegoTest sandbox tests: red because builtins not restricted
   - #40 SAML verify tests: red because sig verification stub
   - #42 CAEP ingress verify tests: red because parser accepts `alg:none`
2. **GREEN phase per finding** (independent, can be parallelised in sub-PRs):
   - #21: migration `opa_scope_allowlist`; handler enforces in `RunRegoTest.module_imports[]`; empty-allowlist fails-closed → green
   - #23: domain extends `CheckRelationRequest` with size-cap; FGA call passes `Context` → green
   - #25: handler adds cluster-admin check → green
   - #26: parse-time builtin restriction + CPU/memory bounds → green
   - #40: integrate `crewjam/saml` Verify; add `saml_request_states` table + CAS → green
   - #42: replace `parseSETBody` accepting `alg:none` with signed-verify using `iam_trusted_idp_jwks_cache` → green
3. **Cross-finding cross-check**: #26 + #25 share cluster-admin pattern — verify same `requireClusterAdmin` helper used in both
4. **RED→GREEN evidence per finding in PR description** (per acceptance §7.3)

## 5. Out-of-scope tests (boundary, not omission)

- **Live IdP integration tests (Kratos OIDC stub container)** — beyond crewjam/saml fixture-based newman tests; W3.4 freeze if needed
- **CAEP push-egress side** — W2.B B.8 (W3.1 is ingress only)
- **SCIM full e2e wire-protocol** — W2.B B.2
- **JIT-pending approve workflow** — W2.B B.3
- **Break-glass workflow** — W2.B B.4
- **GDPR erasure pipeline** — W2.B B.7
- **ABAC custom predicates (beyond `mfa_fresh_required` sample)** — out of W3.1 (Conditions feature extends in future epic)
- **Bundled Rego module distribution** — separate concern (OPA Bundle service in W2.D `iam-opa-bundle.py`)

## 6. Coverage gaps observed in acceptance doc

- **DEC-W3.1-6** (no backward-compat for unsigned/none-alg SETs) — explicit decision documented; no production-CAEP-subscribers exist yet, so no compat-burden. No test gap.
- **OQ-W3.1-1..-4** (acceptance §4) — implementer chooses fixtures (synthetic IdP vs cert-only, table-driven vs subtest). Acceptance §3 fixes Option A (cert-only); §6.42 fixes synthetic IdP stub. Internally consistent.
- **#40 acceptance §6.40 uses 9 scenarios** (HAPPY + 8 negatives); each maps 1:1 to integration + newman. Complete.
- **`saml_request_states` table** — acceptance §5.40 mentions but doesn't enumerate full schema. Implementer must add migration (e.g. `0027_w3.1_saml_request_states.sql`) with `(request_id PK, created_at, consumed_at)` + cleanup worker. Schema decisions belong to impl, not acceptance. No gap.
- **Property/anti-leak tests (§7.4)** — acceptance enumerates them; implementer adds (fuzz-style on `testing/quick`). Coverage gap-free.

## 7. Cross-reference

- Acceptance source: [docs/specs/sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md](sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md)
- Companion plans: [test-plan-W2.B.md](test-plan-W2.B.md) (B.1 SAML scaffolding + B.8 CAEP egress — predecessors to #40/#42 verify), [test-plan-W3.2.md](test-plan-W3.2.md) (observability gates from W3.1 audit/log emits), [test-plan-W3.3.md](test-plan-W3.3.md) (mTLS for trusted IdP fetch of JWKS — adjacent infra)
- Workspace rules: `CLAUDE.md` §«Запреты» #1/#6/#9/#10/#11/#12; §«Инфра-чувствительные данные» applies — SAML/CAEP test fixtures never expose live IdP secrets
- Naming conventions: Go integration per-feature dir `internal/apps/kacho/api/<feature>/<scenario>_integration_test.go::Test_<Feature>_<Scenario>`; newman `iam-<service>.py::<RESOURCE>-<KIND>-<DESC>` snake-upper
