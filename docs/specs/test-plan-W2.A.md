# Test Plan — W2.A: Gateway permission-catalog unification + Spec-drift remediation (23 findings)

> **Source**: [docs/specs/sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md](sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md) (APPROVED 2026-05-24)
> **Status**: PLAN (no code yet — code lives in feature-impl PR per acceptance doc DoD)
> **Branch (eventual impl)**: `KAC-170-proto-catalog-unify` (kacho-proto) · `KAC-170-gateway-catalog-consumer` (kacho-api-gateway) · `KAC-170-iam-spec-drift` (kacho-iam)
> **Parent KAC**: KAC-170 (subtask of master epic KAC-134)

## 1. Per-GWT mapping

| GWT id | Scenario summary | Integration test (Go) | Newman case | Manual / e2e |
|---|---|---|---|---|
| W2.A-CAT-UNIFIED-01 | Single regen → byte-identical embeds (kacho-proto/gateway/iam) | `kacho-proto/cmd/protoc-gen-kacho-permissions/internal_test.go::Test_Generator_DeterministicOutput` | — (build-time gate) | `make catalog && make sync-permission-catalog && make verify-permission-catalog` triple |
| W2.A-CAT-VALIDATE-02 | Gateway startup validates catalog covers all registered FQNs (positive) | `kacho-api-gateway/internal/middleware/permission_catalog_validate_integration_test.go::Test_ValidateAgainstRegisteredServices_AllCovered` | — | helm install passes liveness gate |
| W2.A-PHASE7-REST-REACHABLE-03 | Phase-7 RPCs reachable via REST (Approve / Activate / Erasure / GetCondition / Exchange) | `kacho-api-gateway/internal/restmux/mux_phase7_integration_test.go::Test_RestMux_Phase7_Reachable` | `iam-access-review.py::REVIEW-RPC-REACHABLE-POST-W2A`, `iam-jit-eligibility.py::JIT-ACTIVATE-RPC-REACHABLE`, `iam-gdpr.py::GDPR-ERASURE-RPC-REACHABLE-POST-W2A`, `iam-conditions.py::CONDITIONS-PROJECT-SCOPED-CRUD`, `iam-federation.py::FED-EXCHANGE-RPC-REACHABLE-POST-W2A` | — |
| W2.A-LIST-PERMISSIONS-04 | InternalIAM.ListPermissions returns catalog-derived perms per subject | `kacho-iam/internal/apps/kacho/api/internal_iam/list_permissions_integration_test.go::Test_InternalIAM_ListPermissions_CatalogDerived` | `iam-internal-only-check.py::INTERNAL-LISTPERMISSIONS-OK` | — |
| W2.A-ROLE-LIST-FILTER-05 | RoleService.List parses `is_system=true`/`account_id=…` mini-language | `kacho-iam/internal/apps/kacho/api/role/list_filter_integration_test.go::Test_RoleService_List_FilterMinilang_SystemOnly` (+ `_AccountScoped` / `_NoFilter`) | `iam-role.py::ROLE-LIST-NO-ACCOUNT-SYSTEM-ONLY`, `ROLE-LIST-WITH-ACCOUNT-SCOPED`, `ROLE-LIST-NO-FOREIGN-CUSTOM` | — |
| W2.A-ACCOUNT-LIST-FGA-06 | Invited admin sees account via FGA-derived list (#4 happy) | `kacho-iam/internal/apps/kacho/api/account/list_fga_integration_test.go::Test_AccountService_List_InvitedAdmin_FGAListObjects` | `iam-account.py::ACCOUNT-LIST-INVITED-ADMIN-SEES` | — |
| W2.A-CAT-DRIFT-DETECT-07 | Catalog drift breaks CI (#45 negative) | `kacho-api-gateway/Makefile.verify_test::Test_VerifyCatalog_DriftRejects` (shell-test) | — | CI runs `make verify-permission-catalog` on every PR |
| W2.A-CAT-MISSING-FQN-08 | Gateway refuses start when catalog missing registered FQN | `kacho-api-gateway/internal/middleware/permission_catalog_validate_integration_test.go::Test_ValidateAgainstRegisteredServices_MissingFQN_FailsStartup` | — | kind smoke: deploy with stale catalog → pod CrashLoopBackOff |
| W2.A-ANON-AFTER-FIX-09 | Anonymous on newly-catalogued RPC → 401 deny | `kacho-api-gateway/internal/middleware/anon_deny_integration_test.go::Test_AnonymousNewRPC_DenyAfterCatalogFix` | `iam-conditions.py::CONDITIONS-EVAL-ANON-DENY`, `iam-jit-eligibility.py::JIT-ACTIVATE-ANON-DENY` | — |
| W2.A-SPOOFED-CATALOG-REJECTED-10 | ConfigMap-override with bad shape → fail startup | `kacho-api-gateway/internal/middleware/permission_catalog_load_integration_test.go::Test_LoadCatalog_BadShape_Rejects` | — | — |
| W2.A-SA-ACCOUNT-SCOPED-REJECTED-11 | Old account_id SA Create → InvalidArgument (#3 negative) | `kacho-iam/internal/apps/kacho/api/service_account/create_integration_test.go::Test_SACreate_NoProjectId_InvalidArgument` | `iam-service-account.py::SA-CREATE-NO-PROJECT-ID-INVALIDARG` | — |
| W2.A-GROUP-OWNER-ONLY-FIXED-12 | Delegated admin can AddMember (#6 negative→positive) | `kacho-iam/internal/apps/kacho/api/group/add_member_grant_authority_integration_test.go::Test_GroupAddMember_DelegatedAdmin_Allows` | `iam-group.py::GROUP-ADDMEMBER-DELEGATED-ADMIN-ALLOW` | — |
| W2.A-REGEN-CONCURRENT-13 | Concurrent `make catalog` ×5 → byte-identical output | `kacho-proto/cmd/protoc-gen-kacho-permissions/internal_test.go::Test_Generator_Concurrent_Deterministic` | — | — |
| W2.A-STALE-EMBED-FAIL-START-14 | Gateway stale embed at startup fails fast (cold-start) | `kacho-api-gateway/internal/middleware/permission_catalog_validate_integration_test.go::Test_StaleEmbed_FailsStartup_NotDegradesOpen` | — | helm rollout assertion in kind |
| W2.A-SCOPE-DBLOOKUP-15 | Conditions Update authz scope resolved via DB-lookup (#34) | `kacho-api-gateway/internal/middleware/scope_extractor_dblookup_integration_test.go::Test_ScopeExtractor_DBLookup_ConditionsUpdate` (uses bufconn + kacho-iam fake `InternalConditionsService.GetScope`) | `iam-conditions.py::CONDITIONS-UPDATE-DBLOOKUP-SCOPE` | — |
| W2.A-PROJ-LIST-PAGING-16 | ProjectService.List paging consistent under filter (#15) | `kacho-iam/internal/apps/kacho/api/project/list_paging_integration_test.go::Test_ProjectService_List_PagingConsistent_UnderFGAFilter` | `iam-project.py::PROJECT-LIST-PAGING-CONSISTENT`, `PROJECT-LIST-INVITED-ADMIN-SEES` | — |
| W2.A-CONDITIONS-PROJECT-SCOPED-17 | Conditions CRUD via project_id (#27 folder→project sweep) | `kacho-iam/internal/apps/kacho/api/conditions/project_scoped_integration_test.go::Test_Conditions_CRUD_ProjectScoped` | `iam-conditions.py::CONDITIONS-PROJECT-SCOPED-CRUD` | — |
| W2.A-ROLE-UNSUPPORTED-PERM-REJECTED-18 | Create role with unknown permission → InvalidArgument (#46) | `kacho-iam/internal/apps/kacho/usecases/role/create_validate_supported_perm_integration_test.go::Test_RoleCreate_UnsupportedPerm_RejectsInvalidArgument` | `iam-role.py::ROLE-CREATE-UNSUPPORTED-PERM-DENY` | — |
| W2.A-CAT-COVERAGE-19 | `coverage.py --min 100 --catalog …` asserts every catalog FQN has ≥1 newman case | (no Go) | `tests/newman/coverage.py` self-test | CI gate |

**Implicit-but-required mapping for findings without explicit GWT id in §6:**

| Finding | Verification surface | Test mapping |
|---|---|---|
| #5 (User membership FGA-based) | `kacho-iam/internal/apps/kacho/usecases/user/list.go` | `Test_UserService_List_FGAMembership` (Go integration) + `iam-user.py::USER-LIST-FGA-MEMBERSHIP`, `USER-LIST-NO-OWNER-ONLY` (newman) |
| #14 (Group.List scope-filter) | `kacho-iam/internal/apps/kacho/usecases/group/list.go` | `Test_GroupService_List_ScopeFiltered_FGAMembership` (Go integration) + `iam-group.py::GROUP-LIST-SCOPED` (newman) |
| #44 (SAKey permission strings) | `kacho-proto/proto/.../sa_key_service.proto` | `iam-sa-key.py::SAKEY-NEW-PERM-STRINGS` newman + protobuf compile-time check |
| #55 (roleNameSystemRe sync with migration 0008) | `kacho-iam/internal/apps/kacho/domain/types.go` | `Test_RoleName_Domain_DBRegex_RoundTrip` (Go integration: insert via SQL + parse via domain.Parse) |
| #6 sub for role/update + role/delete | `kacho-iam/internal/apps/kacho/api/role/{update,delete}.go` | `Test_RoleUpdate_DelegatedAdmin_Allows`, `Test_RoleDelete_DelegatedAdmin_Allows` (Go integration) |
| `iam.serviceAccountKeys.*` rename impact | seed permission-roles | `Test_IAMSeed_ServiceAccountKeysPermStringsCorrect` (Go integration on seed package) |
| Internal-only `InternalBreakGlassService` not on public listener | `kacho-api-gateway/internal/restmux/mux.go` | `w2-a-nm-closeout.py::INTERNAL-BREAKGLASS-NOT-ON-PUBLIC-LISTENER` (newman) |

## 2. Test infrastructure required

- **Testcontainers**: `postgres:16-alpine`, `openfga/openfga:v1.5+` (Postgres-backed), one bufconn gRPC server per integration test
- **Fixtures**:
  - `kacho-iam/internal/repo/.../testdata/permission_catalog_baseline.json` — snapshot of post-W2.A catalog for drift detection
  - `kacho-iam/tests/newman/scripts/setup.sh` — seeds 4 users (`bootstrap`/`alice`/`bob`/`carol`) per W2.D-D3 + 1 invited-admin user (`usr_inv`) + 1 stranger (`usr_outsider`)
  - `kacho-iam/tests/newman/fixtures/access_review/`, `…/gdpr/`, `…/jit/`, `…/conditions/` — minimal seed for cross-cutting newman E2E
- **Newman**: existing `gen.py` + `run.sh`; new suites `iam-access-review.py`, `iam-conditions.py`, `iam-federation.py`, `iam-gdpr.py`, `iam-jit-eligibility.py`, `w2-a-nm-closeout.py` (boundary — also created by W2.D for shared closure)
- **External services**: OpenFGA real (Postgres backend in container); no SAML/CAEP/IdP stubs needed (W2.A only adds restmux registration — RPCs may return 501 / scaffold-shape from B.1/B.2 — those tests live in W2.B)
- **Mocked**: `InternalConditionsService.GetScope` (lean RPC) — for `W2.A-SCOPE-DBLOOKUP-15`, use bufconn fake until kacho-iam impl ships actual handler

## 3. Coverage gates (DoD on impl-PR)

- **Integration coverage ≥80%** on touched files (`kacho-iam/internal/apps/kacho/api/{role,account,user,group,project,conditions,internal_iam,service_account}/`, `kacho-api-gateway/internal/middleware/permission_catalog*.go`, `kacho-api-gateway/internal/middleware/scope_extractor*.go`)
- **Newman per RPC**: minimum 1 happy + 1 negative (workspace §11 / §13). All 23 findings' associated RPCs must have ≥1 GREEN case in the relevant suite
- **Concurrent-race scenarios** for any CAS / partial-UNIQUE / EXCLUDE constraint introduced — N/A in W2.A (drop+recreate `0026` is single-statement; no within-service CAS added; concurrent-regen `W2.A-REGEN-CONCURRENT-13` is generator-side determinism, not DB)
- **Catalog determinism**: 5× repeat `make catalog` produces byte-identical sha256 (covered by `W2.A-REGEN-CONCURRENT-13`)
- **Catalog superset coverage**: `cat.ValidateAgainstRegisteredServices(grpcSrv.GetServiceInfo())` returns nil for every gRPC service registered (covered by `W2.A-CAT-VALIDATE-02` + `W2.A-CAT-MISSING-FQN-08`)

## 4. Test sequencing for TDD (RED-before-GREEN per workspace §12)

1. **RED phase commit (per repo)** — all GWT integration tests + newman cases written BEFORE any production code; CI red, recorded in PR description
   - kacho-proto: Test_Generator_DeterministicOutput / Concurrent_Deterministic
   - kacho-api-gateway: Test_ValidateAgainstRegisteredServices_* / Test_RestMux_Phase7_Reachable / Test_ScopeExtractor_DBLookup_*
   - kacho-iam: Test_RoleService_List_FilterMinilang_* / Test_AccountService_List_InvitedAdmin_FGAListObjects / Test_GroupAddMember_DelegatedAdmin_Allows / etc.
2. **Newman cases RED first** — `iam-access-review.py`, `iam-gdpr.py`, `iam-federation.py` (NEW files) populated; `run.sh` shows FAIL because restmux registrations missing
3. **GREEN phase commits (logical commit per finding, ordered by §6 priority)**:
   - Chunk 3 (kacho-proto): `PermissionsCatalogRoot` proto → generator rewrite → scope_extractor proto fixes → `ActivateJIT` RPC → permission strings fix #44 → regen committed
   - Chunk 3 (kacho-api-gateway): `make sync-permission-catalog` consumed → `permission_catalog.go::Validate()` → `restmux/mux.go` register block → `scope_extractor_dblookup.go` handler
   - Chunk 4 (kacho-iam): handler/usecase fixes per finding (#1, #4, #5, #6, #14, #15, #27, #46, #55, #49) + migration 0026 + service_account project-scope rewrite
4. **CI gate (per-PR)**: `make verify-permission-catalog` must pass in all three repos before merge
5. **Cross-repo merge order**: kacho-proto → kacho-api-gateway → kacho-iam (per workspace §«Кросс-репо зависимости»)
6. **Final RED→GREEN evidence in PR description**: per-finding RED commit hash + GREEN commit hash + log excerpt

## 5. Out-of-scope tests (boundary, not omission)

- **Full SAML XML-DSig verify** — W3.1 #40 (W2.A only adds restmux registration for FederationExchangeService; sig verify is W3.1)
- **CAEP-SET signature ingress verify** — W3.1 #42
- **MFA-fresh CheckRelation context** — W3.1 #23 (Conditions service register only, ABAC plumbing later)
- **Load tests** — W3.2 / k6 (newman cases assertЯт correctness only, не response-time)
- **Chaos tests** — out of scope
- **Live IdP integration tests** (Kratos/Okta) — W3.4 freeze if ever; W2.A relies on stub-shape SCIM/SAML RPCs
- **Signing of catalog ConfigMap (integrity)** — out of scope; only shape-validation gates (W2.A-SPOOFED-CATALOG-REJECTED-10)
- **W1.6 #11 redaction parity** — already covered by W1.6 KAC-164 test plan; not duplicated here

## 6. Coverage gaps observed in acceptance doc

Acceptance §6 does not provide explicit GWT scenarios for the following findings; mapping in §1 above
extrapolates from the implementation-spec sections (§4.8). Recommended that acceptance-author append
a `§6.7 Implicit GWTs` table mapping #5, #14, #55 to explicit Given/When/Then before impl-start. This
is a **doc-update follow-up KAC** (suggested: `KAC-iam-acceptance-update-w2a-implicit-gwt`), NOT a
test-plan TODO.

Other observed gaps requiring acceptance-doc update (NOT test omission):

- **OQ-W2.A-1** resolves to «update acceptance KAC-121 §5:103»; that update is itself a doc-PR
  (suggested `KAC-iam-acceptance-update-roles-list-auth`). Not in test scope.
- **`KACHO_AUDIT_ENABLED` gate** is referenced by W2.A indirectly (W2.B B.9 dependency) but W2.A
  newman suite must NOT require audit-pipeline live — verify suites are unconditional.

## 7. Cross-reference

- Acceptance source: [docs/specs/sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md](sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md)
- Companion plans: [test-plan-W2.B.md](test-plan-W2.B.md) (depends on W2.A catalog), [test-plan-W2.C.md](test-plan-W2.C.md) (api-token cases register through unified catalog), [test-plan-W2.D.md](test-plan-W2.D.md) (newman 100% coverage extends suites enumerated here)
- Workspace rules: `CLAUDE.md` §«Запреты» #1 (acceptance-gate), #11 (no TODO), #12 (test-first), #13 (test-only PR if applicable to sub-PRs)
- Naming conventions: Go integration `Test_<Service>_<Scenario>` (per `kacho-iam/internal/apps/kacho/api/**/*_integration_test.go`); newman `<RESOURCE>-<KIND>-<DESC>` snake-upper (per `kacho-iam/tests/newman/cases/iam-*.py::Case(id=…)`)
