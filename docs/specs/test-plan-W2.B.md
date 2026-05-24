# Test Plan — W2.B: Enterprise block B.1–B.10 (SAML/SCIM/JIT/BreakGlass/Review/Compliance/GDPR/CAEP/Audit/mTLS)

> **Source**: [docs/specs/sub-phase-W2.B-stream-b-enterprise-block-acceptance.md](sub-phase-W2.B-stream-b-enterprise-block-acceptance.md) (APPROVED 2026-05-24)
> **Status**: PLAN (no code yet — code lives in per-feature impl PRs)
> **Branch (eventual impl)**: per-feature `KAC-XXX-w2b-B<n>-…` (e.g. `KAC-XXX-w2b-B2-scim`); one tracker KAC per B-feature recommended
> **Parent KAC**: KAC-170 epic-bundle; W2.B is parent for 10 per-feature subtasks

## 1. Per-GWT mapping

Acceptance doc §6 already supplies an `IT-XX` (integration) + `NM-XX` (newman) table per feature with
exact Go test names. This plan preserves that mapping verbatim and adds the missing «file path»
column inferring it from Clean-Architecture layout (`internal/apps/kacho/api/<feature>/…_integration_test.go`).

### B.1 — SAML 2.0 SSO scaffolding (W2.B scope: stub-only)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B1-01 | ACS reachable, parses XML, audit emitted, returns 501 | `internal/apps/kacho/api/saml/acs_integration_test.go::Test_SAML_ACS_Reachable_Returns501_AuditEmitted` | `iam-saml.py::SAML-ACS-RETURNS-501-W2B-SCAFFOLDING` |
| W2.B-B1-02 | Raw assertion-id captured in audit (forensics) | `internal/apps/kacho/api/saml/acs_integration_test.go::Test_SAML_ACS_AssertionIdCapturedInAudit` | — (covered by B1-01 audit row inspection) |
| W2.B-B1-03 | Malformed XML → 400 | `internal/apps/kacho/api/saml/acs_integration_test.go::Test_SAML_ACS_MalformedXml_Rejects400` | `iam-saml.py::SAML-ACS-MALFORMED-REJECTS-400` |
| W2.B-B1-04 | Missing SAMLResponse field → 400 | `internal/apps/kacho/api/saml/acs_integration_test.go::Test_SAML_ACS_MissingField_Rejects400` | — |
| W2.B-B1-05 | Non-existent org → 404 | `internal/apps/kacho/api/saml/acs_integration_test.go::Test_SAML_ACS_OrgNotFound_Returns404` | — |
| W2.B-B1-06 | SP-init `/saml/sp/init` → 501 | `internal/apps/kacho/api/saml/init_integration_test.go::Test_SAML_Init_NotImplemented` | — |

### B.2 — SCIM 2.0 inbound provisioning (FULL incl. #41 per-org Basic-auth)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B2-01 | POST new user → provisioned (201) | `internal/apps/kacho/api/scim/users_integration_test.go::Test_SCIM_PostUser_HappyProvisions` | `iam-scim.py::SCIM-USER-PROVISION-HAPPY` |
| W2.B-B2-02 | Repeat POST same externalId → 200 idempotent | `internal/apps/kacho/api/scim/users_integration_test.go::Test_SCIM_PostUser_Idempotent` | `iam-scim.py::SCIM-USER-PROVISION-IDEMPOTENT` |
| W2.B-B2-03 | Wrong Basic-auth → 401 | `internal/apps/kacho/api/scim/auth_integration_test.go::Test_SCIM_BasicAuth_WrongSecret_Rejects` | `iam-scim.py::SCIM-AUTH-WRONG-SECRET-DENY` |
| W2.B-B2-04 | Anonymous POST → 401 | `internal/apps/kacho/api/scim/auth_integration_test.go::Test_SCIM_NoAuth_Rejects` | — |
| W2.B-B2-05 | DELETE `/Users/{id}` → soft-delete | `internal/apps/kacho/api/scim/users_integration_test.go::Test_SCIM_DeleteUser_SoftDeletes` | — |
| W2.B-B2-06 | RotateScimBasicAuth on external listener → Unimplemented (§Запрет #6) | `internal/apps/kacho/api/internal_organization/rotate_external_listener_integration_test.go::Test_RotateScimBasicAuth_ExternalListener_Unimplemented` (two-listener bufconn) | — (covered by `w2-a-nm-closeout.py::INTERNAL-BREAKGLASS-NOT-ON-PUBLIC-LISTENER` style; analogous suite or extend `iam-internal-only-check.py`) |
| W2.B-B2-07 | Operation.Get returns redacted secret after first read (parity W1.6 #11) | `internal/apps/kacho/api/internal_organization/rotate_redact_integration_test.go::Test_RotateScimBasicAuth_Operation_Redacted_SecondRead` | `iam-scim.py::SCIM-ROTATE-SECRET-REDACTED-2ND-READ` |

### B.3 — JIT-activate (approval workflow E2E)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B3-01 | Approve → grant lands in FGA | `internal/apps/kacho/api/jit_pending/approve_integration_test.go::Test_JitApprove_GrantsAndDrainsToFGA` | `iam-jit-pending.py::JIT-APPROVE-ENFORCED-FGA` |
| W2.B-B3-02 | Deny → no grant, audit only | `internal/apps/kacho/api/jit_pending/deny_integration_test.go::Test_JitDeny_NoGrant` | `iam-jit-pending.py::JIT-DENY-NO-GRANT` |
| W2.B-B3-03 | Non-approver Approve → PermissionDenied | `internal/apps/kacho/api/jit_pending/approve_integration_test.go::Test_JitApprove_NonApprover_Denied` | `iam-jit-pending.py::JIT-APPROVE-NON-APPROVER-DENY` |
| W2.B-B3-04 | Already-decided pending → FailedPrecondition | `internal/apps/kacho/api/jit_pending/approve_integration_test.go::Test_JitApprove_AlreadyDecided_FailedPrecondition` | — |
| W2.B-B3-05 | Concurrent Approve+Deny → exactly one wins (CAS race) | `internal/apps/kacho/api/jit_pending/approve_concurrent_integration_test.go::Test_JitApprove_ConcurrentRace_OneWins` (concurrent goroutines, race-build) | — |
| W2.B-B3-06 | Expiry worker revokes grant + emits CAEP | `internal/worker/jit_expiry_integration_test.go::Test_JitExpiryWorker_RevokesAndEmitsCAEP` | `iam-jit-pending.py::JIT-EXPIRY-REVOKES` |

### B.4 — Break-glass full workflow (2-person + auto-revoke + DB-CHECK distinctness)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B4-01 | Full happy path Request→A→B→ACTIVE→auto-revoke | `internal/apps/kacho/api/internal_break_glass/full_flow_integration_test.go::Test_BreakGlass_FullFlowHappy` | `iam-internal-break-glass.py::BREAKGLASS-HAPPY-FLOW` |
| W2.B-B4-02 | DenyBreakGlass at A | `internal/apps/kacho/api/internal_break_glass/deny_a_integration_test.go::Test_BreakGlass_DenyAtA` | — |
| W2.B-B4-03 | Same approver A==B → DB CHECK violation → FailedPrecondition | `internal/repo/kacho/pg/cluster_admin_grants_check_integration_test.go::Test_BreakGlass_SameApproverRejected_DBCheckViolation` | `iam-internal-break-glass.py::BREAKGLASS-SAME-APPROVER-DENY` |
| W2.B-B4-04 | Approve B before A → FailedPrecondition | `internal/apps/kacho/api/internal_break_glass/order_integration_test.go::Test_BreakGlass_OutOfOrderApprove_FailedPrecondition` | — |
| W2.B-B4-05 | Concurrent ApproveA + DenyBreakGlass → one wins | `internal/apps/kacho/api/internal_break_glass/concurrent_integration_test.go::Test_BreakGlass_ConcurrentApproveDeny_OneWins` | — |
| W2.B-B4-06 | Expiry worker auto-revokes + post-incident-review alert | `internal/worker/break_glass_expiry_integration_test.go::Test_BreakGlass_ExpiryWorker_AutoRevokes` | `iam-internal-break-glass.py::BREAKGLASS-EXPIRY-REVOKES` |

### B.5 — AccessReview campaign engine

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B5-01 | Schedule → enumerate → review-Approve happy | `internal/apps/kacho/api/access_review/campaign_integration_test.go::Test_AccessReview_ScheduleEnumApprove_HappyPath` | `iam-access-review.py::REVIEW-SCHEDULE-AND-DECIDE-HAPPY` |
| W2.B-B5-02 | Deadline → REVOKE strategy auto-revokes OPEN items | `internal/apps/kacho/api/access_review/deadline_integration_test.go::Test_AccessReview_DeadlineAutoRevokes` (advance-clock) | `iam-access-review.py::REVIEW-DEADLINE-AUTO-REVOKE` |
| W2.B-B5-03 | Non-reviewer Approve → PermissionDenied | `internal/apps/kacho/api/access_review/approve_authority_integration_test.go::Test_AccessReview_NonReviewer_Denied` | — |
| W2.B-B5-04 | Approve already-decided → FailedPrecondition | `internal/apps/kacho/api/access_review/approve_authority_integration_test.go::Test_AccessReview_DoubleDecide_FailedPrecondition` | — |
| W2.B-B5-05 | Cancel mid-flight drops OPEN items | `internal/apps/kacho/api/access_review/cancel_integration_test.go::Test_AccessReview_Cancel_DropsOpenItems` | `iam-access-review.py::REVIEW-CANCEL-MID-FLIGHT` |

### B.6 — ComplianceReport engine

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B6-01 | Generate Markdown report happy | `internal/apps/kacho/api/compliance_report/generate_integration_test.go::Test_Compliance_Generate_MarkdownHappy` | `iam-compliance-report.py::COMPLIANCE-GENERATE-MD-HAPPY` |
| W2.B-B6-02 | GetReportDownloadUrl + fetch (signed URL expiry) | `internal/apps/kacho/api/compliance_report/download_integration_test.go::Test_Compliance_DownloadUrl_HappyAndExpiry` (advance-clock) | `iam-compliance-report.py::COMPLIANCE-DOWNLOAD-URL-EXPIRES` |
| W2.B-B6-03 | Invisible-scope principal → NotFound (parity W1.6 #37) | `internal/apps/kacho/api/compliance_report/scope_authority_integration_test.go::Test_Compliance_InvisibleScope_NotFound` | `iam-compliance-report.py::COMPLIANCE-INVISIBLE-SCOPE-DENY` |
| W2.B-B6-04 | Tampered download token → 401 | `internal/apps/kacho/api/compliance_report/download_integration_test.go::Test_Compliance_DownloadToken_TamperRejected` | — |
| W2.B-B6-05 | Concurrent Generate same scope → 2 distinct reports | `internal/apps/kacho/api/compliance_report/concurrent_integration_test.go::Test_Compliance_ConcurrentGenerate_DistinctRows` | — |

### B.7 — GDPR erasure pipeline

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B7-01 | Request → wait 30d → erasure executed | `internal/apps/kacho/api/gdpr_erasure/request_integration_test.go::Test_GDPR_RequestAndExecute_HappyPath` (advance-clock) | — |
| W2.B-B7-02 | Cancel within 30d window | `internal/apps/kacho/api/gdpr_erasure/cancel_integration_test.go::Test_GDPR_CancelWithinGrace_Cancels` | `iam-gdpr-erasure.py::GDPR-REQUEST-AND-CANCEL` |
| W2.B-B7-03 | Cancel wrong token → PermissionDenied | `internal/apps/kacho/api/gdpr_erasure/cancel_authority_integration_test.go::Test_GDPR_CancelWrongToken_PermDenied` | `iam-gdpr-erasure.py::GDPR-CANCEL-WRONG-TOKEN-DENY` |
| W2.B-B7-04 | Cancel after expiry → FailedPrecondition | `internal/apps/kacho/api/gdpr_erasure/cancel_authority_integration_test.go::Test_GDPR_CancelAfterExpiry_FailedPrecondition` | — |
| W2.B-B7-05 | Duplicate Request same subject → AlreadyExists (partial-UNIQUE) | `internal/repo/kacho/pg/gdpr_erasure_request_partial_unique_integration_test.go::Test_GDPR_DuplicateRequest_AlreadyExists` | `iam-gdpr-erasure.py::GDPR-DUPLICATE-REQUEST-DENY` |
| W2.B-B7-06 | Erasure during active break-glass → still executes (OQ-W2.B-15 resolution) | `internal/apps/kacho/api/gdpr_erasure/breakglass_concurrent_integration_test.go::Test_GDPR_Execute_DuringActiveBreakGlass_StillExecutes` | `iam-gdpr-erasure.py::GDPR-ERASURE-OVERRIDES-BREAKGLASS` |
| (W2.B-B7-06 side effect) | Execute emits CAEP + subject_change_outbox | `internal/worker/gdpr_erasure_emit_integration_test.go::Test_GDPR_ExecuteEmitsCAEPAndSubjectChange` | — |

### B.8 — CAEP push egress sign (FULL; ingress verify deferred W3.1 #42)

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W2.B-B8-01 | Register + event → SET delivered + JWS verifiable | `internal/apps/kacho/api/internal_caep_subscriber/register_event_integration_test.go::Test_CAEP_SignAndDeliver_Happy` (httptest as subscriber) | `iam-caep.py::CAEP-REGISTER-AND-EVENT-DELIVERS` |
| W2.B-B8-02 | Update subscriber endpoint → next event delivers new | `internal/apps/kacho/api/internal_caep_subscriber/update_integration_test.go::Test_CAEP_UpdateEndpoint_DeliversToNew` | — |
| W2.B-B8-03 | Subscriber 5xx → retries with backoff | `internal/worker/caep_delivery_integration_test.go::Test_CAEP_RetryBackoffOn5xx` (httptest 503→200) | `iam-caep.py::CAEP-RETRY-ON-5XX` |
| W2.B-B8-04 | Permanently-down → failed_permanent + alert | `internal/worker/caep_delivery_integration_test.go::Test_CAEP_FailedPermanent_AfterMaxRetries` | — |
| W2.B-B8-05 | Disabled subscriber → no delivery, no error | `internal/worker/caep_delivery_integration_test.go::Test_CAEP_DisabledSubscriber_NoDelivery` | — |
| W2.B-B8-06 | Duplicate Register same (account,endpoint) → AlreadyExists | `internal/repo/kacho/pg/caep_subscribers_unique_integration_test.go::Test_CAEP_DuplicateRegister_AlreadyExists` | `iam-caep.py::CAEP-DUPLICATE-REGISTER-DENY` |
| W2.B-B8-07 | `/jwks.json` exposes ONLY `purpose='caep_sign'` keys | `internal/apps/kacho/api/jwks/handler_integration_test.go::Test_CAEP_JWKS_ExposesOnlyCAEPSignKeys` | `iam-caep.py::CAEP-JWKS-PUBLIC-FETCH` |
| (W2.B-B8-01 sig side) | SET signed verifies against JWKS | `internal/apps/kacho/api/jwks/handler_integration_test.go::Test_CAEP_SignedSET_VerifiesAgainstJWKS` | — |

### B.9 — Audit pipeline (VictoriaLogs via vector.dev)

| GWT id | Scenario summary | Integration test (Go) | Newman case | Cluster-blocked |
|---|---|---|---|---|
| W2.B-B9-01 | Every B-feature emit parsable JSON on stdout | `internal/audit/json_emit_test.go::Test_Audit_JSONEmitter_HappyParse` (unit) | — | NO |
| W2.B-B9-02 | Vector sidecar ships event to VL | `internal/audit/vector_sidecar_integration_test.go::Test_Audit_VectorSidecarShipsToVL` (kind e2e, requires VictoriaLogs) | `iam-audit.py::AUDIT-EVENT-SHIPS-TO-VL` (newman e2e) | **YES** |
| W2.B-B9-03 | Vector down → events still emit to stdout (graceful) | `internal/audit/vector_sidecar_integration_test.go::Test_Audit_VectorDown_GracefulDegradation` | — | NO |
| W2.B-B9-04 | Malformed payload sanitized at emit | `internal/audit/sanitize_test.go::Test_Audit_BinaryPayload_Sanitized` (unit) | — | NO |
| W2.B-B9-05 | Burst 1000/s → no drops | `tests/load/audit_burst_test.go::Test_Audit_BurstNoLoss` (load on kind) | — | **YES** |

### B.10 — SPIRE + Cilium mesh mTLS (handshake + policy)

| GWT id | Scenario summary | Integration test (Go) | Newman case | Cluster-blocked |
|---|---|---|---|---|
| W2.B-B10-01 | Pod fetches SVID + serves internal listener | `internal/spiffe/workload_api_client_test.go::Test_SPIFFE_WorkloadAPIClient_FetchSVID` (mock workload API, unit) + `internal/spiffe/tls_config_test.go::Test_SPIFFE_TLSConfig_FromSVID` (unit) | — | NO (unit) — kind smoke documented in W3.3 |
| W2.B-B10-02 | Allowed peer (gateway) connects + RPC succeeds | (full integration deferred to W3.3 §6.1 W3.3-POS-02) | — | NO (deferred to W3.3) |
| W2.B-B10-03 | Unknown peer SPIFFE-ID → refused | (deferred W3.3 §6.2 W3.3-NEG-01) | — | — |
| W2.B-B10-04 | Plain HTTP → TLS handshake reject | (deferred W3.3) | — | — |
| W2.B-B10-05 | SVID rotation mid-flight → existing connections survive | `internal/spiffe/rotation_test.go::Test_SPIFFE_RotationReloadsTLS` (unit) | — | NO (unit) |

## 2. Test infrastructure required

- **Testcontainers**: `postgres:16-alpine`, `openfga/openfga:v1.5+`, optionally MinIO (for B.6 download URLs if using S3 backend)
- **Httptest servers**: B.8 (subscriber endpoint), B.8 (JWKS), B.2 (synthetic Okta poster), B.1 (SAML ACS poster — XML fixture only, no live IdP)
- **Fixtures**:
  - `kacho-iam/tests/newman/fixtures/saml/` — raw XML AuthnResponse files (scaffolding-shape, no sig)
  - `kacho-iam/tests/newman/fixtures/scim/` — SCIM POST bodies (User/Group/PatchOp)
  - `kacho-iam/tests/newman/fixtures/caep/` — synthetic IdP private key (test-only) + JWKS pub
  - `kacho-iam/tests/newman/fixtures/jit/` — pre-created eligibility rows
- **External services**: VictoriaLogs (kind e2e for B9-02/B9-05) — **BLOCKED** without `kacho-deploy` umbrella; mark those tests `t.Skip` until B.9 cluster-side wired
- **Advance-clock helper**: `internal/clock/testclock.go` (NEW) — required by B.5-02, B.6-02, B.7-01

## 3. Coverage gates (DoD on impl-PR)

- **Integration coverage ≥80%** per touched package
- **Newman per-feature**: minimum scenario-table NM-XX from §1; total +25–35 cases across W2.B
- **Concurrent-race scenarios** for DB-level CAS / partial-UNIQUE / EXCLUDE: B.3-05 (JIT race), B.4-05 (BG race), B.5 (decide race), B.7-05 (partial UNIQUE), B.8-06 (UNIQUE). Each requires its own integration test with concurrent goroutines + race-build (`go test -race`).
- **DB-CHECK distinctness for B.4-03**: explicit constraint test (insert two rows with same approver_a/approver_b → 23514 expected)
- **§Запрет #6 regression**: B.2-06 + B.10-* (internal-only services not on external listener) — must have integration test verifying registration absence on external mux
- **§Запрет #11 redaction parity (W1.6 #11) for B.2-07**: integration test verifying second Operation.Get returns `"<redacted>"` literal
- **Coverage gate `coverage.py --min 100`** still passes — every new RPC (B.2 SCIM, B.3 JIT-activate, B.4 BG approve, B.5 review-CRUD, B.6 compliance-CRUD, B.7 GDPR-CRUD, B.8 CAEP subscriber-CRUD + JWKS) has ≥1 newman case

## 4. Test sequencing for TDD (RED-before-GREEN per workspace §12)

**Per-feature isolated PR** (recommended ordering, see acceptance §7):

1. **B.10 SPIRE/Cilium mTLS** — infrastructure-first (unit-only in W2.B; cluster smoke deferred W3.3)
2. **B.9 Audit pipeline** — emit-side first (B.9-01/B.9-03/B.9-04 unit) → vector wire (B.9-02/B.9-05 kind e2e)
3. **B.8 CAEP egress** — sign + deliver (B8-01 happy → B8-03 retry → B8-04 permanent fail)
4. **B.2 SCIM** — POST/PUT/DELETE + Basic-auth (B2-01/02 → B2-03/04 → B2-05 → B2-06/07 listener separation)
5. **B.1 SAML scaffolding** — ACS endpoint (501-shape) + audit emit (B1-01..B1-06)
6. **B.3 JIT-activate** + **B.4 Break-glass** — both depend on FGA atomic grant (W1.5); shared expiry-worker pattern
7. **B.5 AccessReview** — depends on B.7 outbox cascade for decide→FGA write
8. **B.6 ComplianceReport** — depends on B.5 access-review-decision audit-row source
9. **B.7 GDPR erasure** — depends on B.4 (concurrent break-glass case W2.B-B7-06)

**RED-first per feature**:
1. Write ALL §1 integration tests + newman cases for the feature → CI red
2. Migration → integration tests pass row-by-row
3. Repo (pgx + sqlc) → Reader/Writer integration tests pass
4. Service/use-case → handler tests pass
5. Wire into restmux/cmd `main.go` → newman tests pass
6. Commit RED → GREEN evidence pair in PR description

## 5. Out-of-scope tests (boundary, not omission)

- **Full SAML signature verify / replay state CAS** — W3.1 #40 (B.1 here is scaffolding-only per scope-split Option Y)
- **CAEP SET ingress verify** — W3.1 #42 (B.8 here is egress sign only)
- **MFA-fresh ABAC plumbing** — W3.1 #23
- **OPA scope-allowlist, ReloadModel admin gate, RunRegoTest sandbox** — W3.1 #21/#25/#26
- **API tokens (`kat_*`)** — W2.C separate stream
- **Multi-region failover / chaos** — out of W2 scope
- **Production CAEP subscriber integration** — only in-cluster test-stubs; real Okta/Azure subscribers belong to W3.4+ freeze
- **Penetration test of SCIM Basic-auth brute-force** — out of scope; mitigated by rate-limit at gateway-edge (separate concern)

## 6. Coverage gaps observed in acceptance doc

- **B.9-02 / B.9-05 require live VictoriaLogs on kind** — without `kacho-deploy` umbrella deploying VL, these tests must be `t.Skip` in W2.B. Recommended: `kacho-deploy` PR enabling VL precedes B.9 impl (already tracked in W3.2 KAC tickets). **Not** a doc-gap — acceptance §B.9 already calls out blocking.
- **B.10 full peer-acceptance tests** are deferred to W3.3 by W2.B acceptance §B.10 itself — verify W3.3 acceptance covers all 5 B10-XX scenarios (W3.3 §6.1/6.2 already provides POS-01..03 + NEG-01..03 + EDGE-01..06 — adequate coverage). No gap.
- **B.7-06 implicit dependency on B.4 active grant state**: cross-feature integration test `Test_GDPR_Execute_DuringActiveBreakGlass_StillExecutes` is correctly enumerated; ensure test sets up complete B.4 ACTIVE grant in arrange phase (acceptance §B.7 §6 enumerates this but doesn't show fixture detail — implementer should add fixture helper `setupBreakGlassActive(t, subject_id)`).
- **B.6 `tests/newman/fixtures/access_review/`** seed for review-Approve audit events the report queries — acceptance doesn't enumerate; implementer must add as part of B.6 fixture work.

These are **fixture-detail gaps**, not GWT-scenario omissions. No follow-up KAC needed; impl handles in regular work.

## 7. Cross-reference

- Acceptance source: [docs/specs/sub-phase-W2.B-stream-b-enterprise-block-acceptance.md](sub-phase-W2.B-stream-b-enterprise-block-acceptance.md)
- Companion plans: [test-plan-W2.A.md](test-plan-W2.A.md) (catalog → required for B.1/B.2/B.5/B.7/B.8 REST registration), [test-plan-W3.1.md](test-plan-W3.1.md) (SAML sig + CAEP ingress sequels), [test-plan-W3.3.md](test-plan-W3.3.md) (B.10 cluster-side proof)
- Workspace rules: `CLAUDE.md` §«Запреты» #1/#6/#9/#10/#11/#12; §«Within-service refs DB-уровень обязателен» for B.3/B.4/B.5/B.7/B.8 CAS+UNIQUE patterns
- Naming conventions: per-feature subdirectory mirrors `internal/apps/kacho/api/<feature>/` Clean-Architecture layout (each feature its own handler/usecase/repo trio); per-feature newman case-file `iam-<feature>.py`
