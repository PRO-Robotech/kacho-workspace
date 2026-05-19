# Production-Ready Next-Gen IAM — Implementation Plan (KAC-127 vault / YT KAC-123)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Полная production-ready реализация Kachō IAM. **Все компоненты IN scope.** Никаких TODO / deferred / follow-up. DoD = функциональный приклад всех слоёв IAM + zero tech debt + tests на access provisioning + развёрнуто на внешнем контуре `api.kacho.cloud` + все CI/CD зелёные + top-of-market реализация.

**Architecture:** 13 phases поверх KAC-108/125 baseline. Identity hierarchy `cluster → organization (optional) → account → project → resource`. ORY Kratos+Hydra+Jackson AuthN, OpenFGA+OPA AuthZ, SPIFFE/SPIRE+Cilium mesh in-cluster mTLS, full audit pipeline (Kafka+ClickHouse+S3+Glacier+HSM+SIEM+Merkle), CAEP push, JIT/PIM+break-glass, multi-region active-active.

**Tech Stack:** Go 1.22 + sqlc/pgx; PostgreSQL 16 HA + LISTEN/NOTIFY; ORY Kratos v1.4 + Hydra v2.4 + Boxyhq Jackson; OpenFGA v1.6 + OPA v1.0 (Rego); SPIRE v1.10 + Cilium v1.16; Kafka v3.7 (KRaft) + ClickHouse v24 + S3+Glacier + HSM; cosign + SBOM; Argo CD GitOps; Cloudflare WAF+DDoS; cert-manager + Let's Encrypt; OpenTelemetry + Tempo+Mimir+Loki+Grafana; Litmus chaos; go-fuzz continuous fuzzing.

**Reference docs:**
- Design: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md`
- Vision: `docs/superpowers/specs/2026-05-19-iam-revolutionary-architecture-design.md`
- Skill: `.claude/skills/iam-architect/SKILL.md`
- KAC-127 vault: `obsidian/kacho/KAC/KAC-127.md`
- Workspace policy: `CLAUDE.md`

---

## Workflow notes

- Coding-gate per CLAUDE.md запрет #1 — APPROVED acceptance doc per phase прежде кода.
- Test discipline per CLAUDE.md запрет #11 — integration + newman + Rego unit-tests в том же PR. **Tests-followup запрещён** (production edition).
- Branch isolation per CLAUDE.md «Изоляция рабочего пространства» — worktree per branch.
- Per-phase mandatory: integration tests + newman cases + (где applicable) k6 + Playwright + Rego tests.

---

## Phase 0: Ticketing & worktrees

### Task 0.1: Создать 13 subtasks под KAC-123 в YouTrack

**Files:** external (YouTrack).

- [ ] Через REST API создать 13 issues; привязать к KAC-123 через `subtask of`; добавить в текущий sprint:

| # | Summary |
|---|---|
| 1 | [Phase 1] IAM Foundation — DB schema (Org+Cluster+Federation+Conditions+JIT+outboxes+audit+CAEP+SCIM+session_revocations+jwks+gdpr+break_glass+access_reviews); миграции 0011-0014; permission registry from proto |
| 2 | [Phase 2] IAM AuthN — Kratos WebAuthn/Passkey + Hydra DPoP + mTLS-bound + step-up + recovery + JWKS rotation + back-channel logout |
| 3 | [Phase 3] IAM AuthZ — OpenFGA model v2 + Conditions + OPA sidecar + bundle signing + Rego tests |
| 4 | [Phase 4] IAM List filtering — ListObjects integration per List-handler (vpc/compute/lb) + k6 SLA |
| 5 | [Phase 5] IAM Workload Identity Federation — SA-keys Hydra (Class A) + FederationExchangeService (Class B) для GitHub/AWS/GCP/GitLab/Bitbucket/CircleCI/Buildkite |
| 6 | [Phase 6] IAM Enterprise SSO — SCIM 2.0 + SAML bridge (Boxyhq Jackson) + Organization tier + JIT provisioning + domain claim |
| 7 | [Phase 7] IAM JIT/PIM + Break-glass + Access Reviews + GDPR erasure pipeline |
| 8 | [Phase 8] IAM CAEP push pipeline — outbox + drainer + SET signing + subscriber registry + internal receiver |
| 9 | [Phase 9] IAM Audit pipeline (full) — Kafka + ClickHouse + S3+Glacier + HSM + Merkle + SIEM + Detection rules |
| 10 | [Phase 10] IAM in-cluster Workload Identity + Service Mesh — SPIRE + Cilium mesh + AuthorizationPolicy + cosign attestor |
| 11 | [Phase 11] IAM Production deployment + Observability — api.kacho.cloud + Cloudflare + cert-manager + multi-region + Grafana + PagerDuty + GitOps + SBOM/SLSA |
| 12 | [Phase 12] IAM Conformance + Pentest + Chaos + Fuzzing — OWASP ASVS L3 + Litmus + go-fuzz + external pentest + bug bounty |
| 13 | [Phase 13] IAM Vault docs + KAC-127 closeout — 30+ vault files + runbooks + security.txt + disclosure docs |

### Task 0.2: Worktrees в 10 репо

- [ ] Per CLAUDE.md isolation rule, для каждой phase создаём worktree от main в каждом затронутом репо:

```bash
cd project/kacho-iam
git worktree add -b KAC-127-phase1 ../kacho-iam-KAC-127-phase1 main
```

Аналогично для других phases/repos. Удалять worktree после merge.

---

## Phase 1: Foundation (DB schema + bootstrap migration + permission registry)

### Task 1.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.1-iam-foundation-acceptance.md`

- [ ] Dispatch `acceptance-author` agent (на основе design §3 + §4):
  - 25-30 GWT scenarios.
  - Coverage: migration 0011-0014 (split logical — clusters/org, federation/conditions/jit, audit/caep/scim, gdpr/access_reviews), idempotency, CHECK constraints, partial UNIQUE, FK RESTRICT cascades, multi-scope role validation, state machine transitions PENDING→ACTIVE→REVOKED, JWKS rotation table seed, permission registry seed from proto annotations.

- [ ] `acceptance-reviewer` round-trip до APPROVED.

### Task 1.2: kacho-proto — new messages

**Files:** в `kacho-proto/proto/kacho/cloud/iam/v1/`:
- Create: `cluster.proto`, `organization.proto`, `federation_trust_policy.proto`, `access_binding_condition.proto`, `jit_eligibility.proto`, `caep_subscriber.proto`, `gdpr_erasure_request.proto`, `access_review.proto`, `session_revocation.proto`, `jwks_key.proto`, `scim_user.proto`, `scim_group.proto`.
- Modify: `role.proto` (multi-scope: oneof scope { cluster_id, organization_id, account_id, project_id }), `access_binding.proto` (status + condition_id + expires_at).
- New service proto: `internal_cluster_service.proto`, `organization_service.proto`, `federation_service.proto`, `internal_role_service.proto`, `caep_subscriber_service.proto`, `internal_break_glass_service.proto`, `internal_jit_eligibility_service.proto`, `access_review_service.proto`, `gdpr_erasure_service.proto`, `scim_v2_service.proto`.
- Authz annotations: `authz.proto` (extension options для permission/required_relation/scope_extractor/required_acr_min).

- [ ] `proto-sync` agent — envelope metadata/spec/status; buf.validate.
- [ ] `proto-api-reviewer` — buf breaking clean; no yandex; permission catalog generator works.
- [ ] Regenerate stubs (`buf generate`); commit gen/.

### Task 1.3: kacho-iam — migrations 0011-0014

**Files:**
- `internal/migrations/0011_kac127_identity_extension.sql` — clusters/cluster_admin_grants/cluster_break_glass_grants/organizations + roles refactor + access_bindings extension + service_accounts extension.
- `internal/migrations/0012_kac127_federation_jit_conditions.sql` — federation_trust_policies + access_binding_conditions + access_bindings_jit_eligibility.
- `internal/migrations/0013_kac127_audit_caep_pipeline.sql` — audit_outbox + caep_outbox + caep_subscribers + session_revocations + audit_signing_batches.
- `internal/migrations/0014_kac127_scim_gdpr_reviews_jwks.sql` — scim_user_mappings + gdpr_erasure_requests + access_reviews + access_review_items + oidc_jwks_keys.

- [ ] `migration-writer` agent + `db-architect-reviewer`:
  - All FK RESTRICT (no cross-service cascade).
  - All partial UNIQUE syntax correct.
  - CHECK constraints validated (multi-scope exactly_one, status transitions, ipaddr CIDR validation).
  - `pg_advisory_lock` для bootstrap-seed.
  - `statement_timeout` per migration safety.

### Task 1.4: kacho-iam domain + repo

**Files (per entity):** `internal/domain/<entity>.go` + `internal/repo/kacho/pg/<entity>.go` + integration tests.

Entities: Cluster, Organization, ClusterAdminGrant, ClusterBreakGlassGrant, FederationTrustPolicy, AccessBindingCondition, JitEligibility, CaepSubscriber, CaepOutboxEntry, AuditOutboxEntry, SessionRevocation, AuditSigningBatch, ScimUserMapping, GdprErasureRequest, AccessReview, AccessReviewItem, OidcJwksKey + extend existing Role, AccessBinding, ServiceAccount.

- [ ] `rpc-implementer` agent + `go-style-reviewer`:
  - Self-validating newtypes.
  - CQRS Reader/Writer transactor split (per `evgeniy` skill).
  - sentinel-based error mapping.
  - integration tests (testcontainers Postgres) covering CRUD + concurrent races (CAS, partial UNIQUE).

### Task 1.5: permission registry generator

**Files:**
- Create: `kacho-proto/cmd/protoc-gen-kacho-permissions/main.go` — protoc plugin emitting `gen/permission_catalog.json`.
- Modify: `buf.gen.yaml` — register plugin.
- `kacho-iam/internal/apps/kacho/seed/permissions.go` — seeds DB from catalog at startup.

- [ ] Plugin парсит annotations `(kacho.iam.authz.permission)` etc → JSON catalog.
- [ ] kacho-iam seeds on startup (idempotent UPSERT).
- [ ] CI: catalog committed; PR fails if proto added without permission annotation.

### Task 1.6: PR-chain + YT

- [ ] PRs: kacho-proto → kacho-corelib (если нужны новые helper'ы) → kacho-iam.
- [ ] All review rounds (proto-api-reviewer, db-architect-reviewer, go-style-reviewer).
- [ ] Merge → YT subtask → Done. KAC-127 comment с PR URLs.

---

## Phase 2: AuthN core (Kratos Passkey + Hydra DPoP + step-up + recovery)

### Task 2.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`

- [ ] `acceptance-author`: 25-30 GWT. Coverage: WebAuthn registration ceremony, Passkey signin (conditional UI), DPoP token validation (htm/htu/iat/jti), mTLS-bound tokens, step-up flow (acr=2→3), recovery (magic-link + force re-Passkey), refresh token rotation + family-revoke, JWKS rotation (current+previous), back-channel logout (RFC 8254), session_revocations cache invalidation, replay protection (DPoP jti cache), TOTP secondary MFA fallback.

### Task 2.2: Kratos config

**Files:** `kacho-deploy/helm/umbrella/charts/kacho-iam/templates/kratos-config-configmap.yaml`

- [ ] Identity schema v2 (kacho_user_v1.json).
- [ ] WebAuthn enabled (passwordless=true; user_verification=required для step-up).
- [ ] Password fallback (Argon2id m=64MB, t=3, p=4; HIBP-checked).
- [ ] TOTP secondary.
- [ ] Recovery flow magic-link (5min TTL, single-use, IP-bound).
- [ ] Hooks: post-webauthn-registration → kacho-iam.UpsertFromIdentity.
- [ ] Hooks: post-login → require_aal2 (для regular endpoints) / require_aal3 (для admin).

### Task 2.3: Hydra config

**Files:** `kacho-deploy/helm/umbrella/values.dev.yaml` + `values.prod.yaml`

- [ ] DPoP enabled (oauth2.dpop.enabled=true).
- [ ] mTLS-bound tokens enabled (oauth2.mtls.enabled=true).
- [ ] TTL: access 15min / refresh 30d / id 15min / auth_code 1min.
- [ ] Refresh rotation enforced.
- [ ] JWT signing: RS256 + ES256 + EdDSA (alg pinning per kid).
- [ ] JWKS rotation cron (90d).
- [ ] token_hook + refresh_token_hook → kacho-iam (inject ext_claims).
- [ ] Removed grants: Implicit, ROPC.

### Task 2.4: kacho-api-gateway — DPoP/mTLS validation

**Files:**
- Modify: `internal/auth/jwt_validator.go` (extend для DPoP + mTLS-bound).
- Create: `internal/auth/dpop_validator.go`.
- Create: `internal/auth/mtls_validator.go`.
- Create: `internal/auth/session_revocations_cache.go` (LISTEN-invalidated).

- [ ] `rpc-implementer` + `go-style-reviewer`:
  - RFC 9449 strict compliance (cnf.jkt thumbprint match, htm/htu, iat freshness, jti cache 2min).
  - RFC 8705 mTLS sender-constrained.
  - Cache session_revocations 5s + LISTEN 'session_revoked'.
  - Fail-closed on missing required claim.

### Task 2.5: kacho-iam — token_hook handler

**Files:** `kacho-iam/internal/apps/kacho/api/hydra/{token_hook,refresh_hook}.go`

- [ ] Hydra calls на token issue → kacho-iam inject ext_claims (active_account, organization_id, principal_type, device_attestation, mfa_at).

### Task 2.6: kacho-iam — UpsertFromIdentity rewrite

**Files:** `kacho-iam/internal/apps/kacho/api/user/internal_upsert.go`

- [ ] Idempotent identity → User row creation (per-Account).
- [ ] Activate PENDING bindings.
- [ ] On first registration: bootstrap-worker creates default Account + Project + admin-binding (already in KAC-117/125).
- [ ] Emit audit event `authn.signin.success` + `iam.user.created` / `iam.user.activated`.

### Task 2.7: kacho-iam — JWKS rotation cron

**Files:** `kacho-iam/internal/apps/kacho/jobs/jwks_rotator.go`

- [ ] Daily cron checks oidc_jwks_keys; rotates if current key age > 90d.
- [ ] Generates new keypair (RSA/EC/EdDSA configurable); INSERT new key; publishes via Hydra JWKS endpoint.
- [ ] Removes old key after grace window (max access token TTL × 2 = 30min minimum).

### Task 2.8: kacho-ui — Passkey UI

**Files:**
- Modify: `src/pages/auth/SigninPage.tsx` (Conditional UI with Passkey autofill).
- Modify: `src/pages/auth/RegistrationPage.tsx` (Sign up with Passkey CTA primary, password secondary).
- Create: `src/pages/auth/StepUpModal.tsx` (re-Passkey for acr=3).
- Create: `src/pages/auth/RecoveryPage.tsx` (magic-link + force re-Passkey).

- [ ] BFF pattern: refresh token in httpOnly cookie; access in DPoP-bound + IndexedDB key.

### Task 2.9: PR-chain + YT

- [ ] e2c825 + staging smoke: signup Passkey → JWT acr=2 with cnf.jkt → /v1/users/me succeeds.
- [ ] Newman cases for всех auth flows.
- [ ] YT subtask → Done.

---

## Phase 3: AuthZ core (OpenFGA model v2 + Conditions + OPA sidecar)

### Task 3.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`

- [ ] `acceptance-author`: 25-30 GWT. Coverage: model deploy idempotent, Conditions (all 7 предустановленных), Conditional Check (allowed/denied based on runtime context), OPA Deny rules (all 6+ из design §4 Rego), bundle signing + verification, OPA bundle pull (1h TTL), Rego unit-tests in CI, cache invalidation, fail-closed на FGA/OPA unavailable.

### Task 3.2: openfga-bootstrap-job DSL v2

**Files:**
- `kacho-deploy/helm/umbrella/templates/openfga-model-stub-configmap.yaml` (replace stub с full DSL из design §4).
- `kacho-deploy/helm/umbrella/templates/openfga-bootstrap-job.yaml` (idempotency check + model_id record into Secret).

### Task 3.3: corelib/authz — Conditions extension

**Files:** `corelib/authz/check.go`, `listobjects.go`, `conditions_context.go` (новый — builds runtime context from Principal).

- [ ] `rpc-implementer`:
  - Pass principal.AMR/ACR/MFAAt/SourceIP/DeviceAttestation as contextual_tuples.
  - Cache key includes condition-relevant fields (cache invalidation on principal change).
  - All `evgeniy` skill conventions.

### Task 3.4: kacho-iam — AccessBindingService extension

**Files:** `kacho-iam/internal/apps/kacho/api/access_binding/{upsert,activate_jit,revoke_with_caep}.go`

- [ ] Upsert принимает condition_id + expires_at.
- [ ] At outbox-write transmits condition + context payload в FGA tuple.

### Task 3.5: OPA sidecar deploy

**Files:**
- `kacho-deploy/helm/umbrella/templates/opa-sidecar-configmap.yaml`.
- `kacho-deploy/helm/umbrella/charts/kacho-iam/templates/deployment.yaml` (add opa sidecar к kacho-api-gateway pod template).
- `kacho-deploy/helm/umbrella/templates/opa-bundle-server-configmap.yaml` (config — bundle endpoint в kacho-iam).

- [ ] Bundle pull from kacho-iam HTTPS endpoint (signed bundles; 1h TTL).
- [ ] Evaluation AFTER FGA Check passes.
- [ ] Metrics экспонируются (OPA Prometheus exporter).

### Task 3.6: kacho-iam — OPA bundle endpoint

**Files:** `kacho-iam/internal/apps/kacho/api/opa/{bundle,sign_bundle}.go` + Rego files in `kacho-iam/policies/*.rego`.

- [ ] Serves Rego policies + data в signed bundle (cosign or in-band JWS).
- [ ] Rego unit-tests in `kacho-iam/policies/*_test.rego` — CI fails if test fails.

### Task 3.7: PR-chain + YT

- [ ] Smoke: model v2 deployed; Conditional binding (mfa_fresh) → denied without step-up → step-up → allowed; OPA Deny rule blocks billing-project destructive op.
- [ ] YT subtask → Done.

---

## Phase 4: List filtering (ListObjects per List-handler)

### Task 4.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.4-iam-list-filtering-acceptance.md`

- [ ] `acceptance-author`: 15-20 GWT. Coverage: empty/2-id/100-id grants; cluster-admin cascade; cache hit/miss; LISTEN-invalidate; SLA p95 verified; pagination behavior.

### Task 4.2: corelib/authz/listobjects.go

**Files:** `corelib/authz/listobjects.go` + `listobjects_test.go`.

- [ ] `rpc-implementer`:
  - LRU cache 5s TTL.
  - LISTEN `kacho_iam_subjects` → invalidate on AccessBinding change.
  - OpenFGA ListObjects call with Consistency option (default MINIMIZE_LATENCY; HIGHER_CONSISTENCY for sensitive).
  - Pagination: внутренне max_results=10000; больше = follow-up call.

### Task 4.3: per-service List-handler rewrite

**Files:**
- `kacho-vpc/internal/apps/kacho/api/{network,subnet,security_group,route_table,address,gateway,private_endpoint,network_interface,address_pool}/list.go`.
- `kacho-compute/internal/apps/kacho/api/{instance,disk,image,snapshot}/list.go`.
- `kacho-loadbalancer/internal/apps/kacho/api/{network_load_balancer,target_group}/list.go`.

- [ ] Pattern: ListAllowedIDs → SELECT WHERE id IN(...) → return.
- [ ] Empty grant → empty response (not 403).
- [ ] Integration tests per handler.

### Task 4.4: k6 load test

**Files:** `kacho-test/tests/k6/list_filter_kac127_phase4.js`

- [ ] Сценарий: 1000 networks per project; 10/100/1000 users каждый с N bindings (N ∈ {1,10,50,100,500}); 1000 RPS sustained 30min.
- [ ] Assert: p95 ListObjects ≤100ms; p99 ≤250ms; cache hit ratio ≥80%.
- [ ] Results → `kacho-test/tests/k6/results/KAC-127-list-filter.md`.

### Task 4.5: PR-chain + YT

---

## Phase 5: Workload Identity Federation (external CI/CD)

### Task 5.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.5-iam-workload-identity-federation-acceptance.md`

- [ ] `acceptance-author`: 25-30 GWT. Coverage: SA-key Create/Delete/List via Hydra (Class A); Federation Trust Policy CRUD with subject_pattern strict validation (no wildcard `*`); FederationExchange (RFC 8693) flow; verify external OIDC (mock GitHub/AWS/GCP/GitLab JWKS); subject_pattern mismatch → denied; expired policy → denied; conditions evaluation (source_ip, business_hours); per-issuer JWKS cache 24h.

### Task 5.2: kacho-corelib — hydra-admin + kratos-admin clients

**Files:**
- Create: `corelib/clients/hydra_admin.go` + tests (httptest mock).
- Modify: `corelib/clients/kratos_admin.go` — full recovery-link impl (KAC-125 stub → production).

### Task 5.3: kacho-iam — ServiceAccountKeyService

**Files:** `kacho-iam/internal/apps/kacho/api/sa_key/{create,delete,list,rotate}.go`

- [ ] Create: Hydra POST /admin/clients (idempotent on 409); DB INSERT; return secret one-shot.
- [ ] Delete: Hydra DELETE + DB delete + CAEP outbox emit.
- [ ] List: SELECT (без secret).
- [ ] Rotate: special op — issues new key + revokes old after grace period.

### Task 5.4: kacho-iam — FederationExchangeService

**Files:** `kacho-iam/internal/apps/kacho/api/federation/{create_policy,update_policy,delete_policy,list_policy,exchange}.go`

- [ ] CreatePolicy: validates issuer whitelist OR admin-bypass; subject_pattern regex анкорено (no glob).
- [ ] UpdatePolicy: only enabled/expires_at/conditions mutable; subject_pattern immutable.
- [ ] Exchange:
  - Parse subject_token → verify via dynamic JWKS lookup.
  - Match against policies WHERE issuer=$1 AND enabled AND expires_at>now AND subject_pattern matches.
  - Apply additional_claims_filter (exact match).
  - Evaluate conditions (source_ip, business_hours).
  - Issue Kachō JWT (TTL ≤ policy.max_token_ttl).
- [ ] Per-issuer JWKS cache (24h TTL; refresh on kid miss).

### Task 5.5: Integration tests for federation providers

**Files:** `kacho-iam/internal/apps/kacho/api/federation/exchange_integration_test.go`

- [ ] Mock JWKS endpoints for: GitHub Actions, AWS IRSA, GCP WIF, GitLab CI, Azure Workload Identity, Bitbucket, CircleCI, Buildkite.
- [ ] Each provider: happy-path + subject_pattern mismatch + expired policy + tampered signature → denied.

### Task 5.6: kacho-api-gateway — register Exchange + SA-key services

### Task 5.7: kacho-ui — SA-keys page + Federation Trust Policy page

**Files:**
- `kacho-ui/src/pages/iam/sa-keys/{SAKeysPage,IssueKeyModal,RotateKeyModal}.tsx`.
- `kacho-ui/src/pages/iam/federations/{FederationPoliciesPage,CreatePolicyModal}.tsx`.
- Docs snippets для GitHub Actions / GitLab CI / AWS IRSA setup на customer side.

### Task 5.8: PR-chain + YT

- [ ] e2c825 smoke: mock GitHub OIDC token → exchange → Kachō JWT → API call success.

---

## Phase 6: Enterprise SSO (SCIM 2.0 + SAML bridge + Organization tier)

### Task 6.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.6-iam-scim-saml-organization-acceptance.md`

- [ ] `acceptance-author`: 30+ GWT. Coverage: Organization CRUD; domain-claim DNS verification (TXT record); SCIM /Users + /Groups + /Bulk endpoints (RFC 7644 compliance); SAML metadata XML upload + SP-init flow; SAML IdP-init flow; JIT provisioning on first sign-in без pre-SCIM; SCIM filter expressions (eq/ne/co/sw/gt/lt); SCIM pagination; SCIM sort; cross-tenant SCIM isolation; bearer token rotation; lifecycle events (User.DELETE → CAEP cascade).

### Task 6.2: kacho-iam — OrganizationService

**Files:** `kacho-iam/internal/apps/kacho/api/organization/{create,update,delete,get,list,verify_domain}.go`

### Task 6.3: kacho-iam — SCIM 2.0 endpoint

**Files:**
- `kacho-iam/internal/apps/kacho/api/scim/{users,groups,bulk,me,resource_types,schemas,service_provider_config}.go`.
- Full RFC 7644 compliance — tested against Okta + Azure sandboxes.

### Task 6.4: Boxyhq Jackson deploy

**Files:**
- `kacho-deploy/helm/umbrella/templates/jackson-deployment.yaml`.
- `kacho-deploy/helm/umbrella/templates/jackson-service.yaml`.
- `kacho-deploy/helm/umbrella/values.{dev,prod}.yaml` — jackson block.

- [ ] Jackson translates SAML → OIDC; sits behind kacho-api-gateway или поверх Hydra.

### Task 6.5: kacho-iam — SAML JIT provisioning

**Files:** `kacho-iam/internal/apps/kacho/api/user/saml_jit_provision.go`

- [ ] Receive Kratos webhook with SAML-derived identity → resolve organization by domain-claim → create User в default Account → assign initial role (configurable per Org).

### Task 6.6: kacho-ui — Organization admin pages

**Files:** `kacho-ui/src/pages/iam/organizations/{OrgListPage,OrgDetailPage,OrgSSOConfigPage,DomainVerificationPage,SCIMTokenPage}.tsx`

### Task 6.7: PR-chain + YT

- [ ] Smoke: create Organization → assign domain → SAML metadata upload → simulated Okta SAML signin → JIT User created → Account auto-assigned.

---

## Phase 7: JIT/PIM + Break-glass + Access Reviews + GDPR

### Task 7.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.7-iam-jit-breakglass-reviews-gdpr-acceptance.md`

- [ ] `acceptance-author`: 30+ GWT. Coverage: JIT eligibility CRUD; ActivateJIT with required step-up; ActivateJIT with approval workflow; JIT auto-expire; Break-glass request → 2-person approve → grant → auto-expire; PagerDuty + Slack + email alerts triggered; post-incident review enforcement; Access Reviews quarterly automation; SCIM-managed group reviewer reminder; GDPR erasure 30d cool-off + cascade revoke + pseudonymization + audit retention.

### Task 7.2: kacho-iam — JIT handlers

**Files:**
- `kacho-iam/internal/apps/kacho/api/access_binding/activate_jit.go`.
- `kacho-iam/internal/apps/kacho/api/jit_eligibility/{create,update,delete,list,get}.go`.
- `kacho-iam/internal/apps/kacho/jobs/jit_expirer.go` (background revoke).

### Task 7.3: kacho-iam — Break-glass handlers

**Files:**
- `kacho-iam/internal/apps/kacho/api/cluster/{request_break_glass,approve_break_glass,deny_break_glass,list_pending,list_active}.go`.
- `kacho-iam/internal/apps/kacho/jobs/break_glass_expirer.go`.

- [ ] State machine: AWAITING_APPROVAL_A → AWAITING_APPROVAL_B → ACTIVE → EXPIRED/REVOKED/DENIED.
- [ ] OPA Deny rule enforces ≤ 2h.

### Task 7.4: corelib/notify — PagerDuty + Slack + Email

**Files:**
- `corelib/notify/pagerduty.go`.
- `corelib/notify/slack.go`.
- `corelib/notify/email.go` (SMTP or transactional API e.g., AWS SES).

- [ ] kacho-iam wires к break_glass events.

### Task 7.5: kacho-iam — Access Reviews automation

**Files:**
- `kacho-iam/internal/apps/kacho/jobs/access_review_scheduler.go` (quarterly cron).
- `kacho-iam/internal/apps/kacho/api/access_review/{list,get,confirm,revoke,list_items}.go`.

### Task 7.6: kacho-iam — GDPR erasure pipeline

**Files:**
- `kacho-iam/internal/apps/kacho/api/gdpr/{request_erasure,cancel_erasure,list,get}.go`.
- `kacho-iam/internal/apps/kacho/jobs/gdpr_erasure_processor.go` (daily; processes cool-off-expired).

- [ ] Cascade revoke → pseudonymize → hard-delete identity (Kratos admin) → audit retention preserved.

### Task 7.7: kacho-ui — JIT modal + Break-glass approver page + GDPR settings

### Task 7.8: PR-chain + YT

- [ ] Smoke: JIT activate → 1h admin → expire; Break-glass 2-approve → PagerDuty fires → auto-revoke; Access Review quarterly run; GDPR erasure flow end-to-end.

---

## Phase 8: CAEP push pipeline

### Task 8.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.8-iam-caep-push-acceptance.md`

- [ ] `acceptance-author`: 20-25 GWT. Coverage: subscriber CRUD; SET signing/verification; webhook delivery happy/retry/failed_terminal; subscriber-side replay protection (jti cache); internal CAEP receiver in api-gateway; revoke latency ≤10s SLA verified via k6; per-subscriber rate-limit.

### Task 8.2: kacho-iam — CAEP outbox + drainer + SET signing

**Files:**
- `kacho-iam/internal/apps/kacho/jobs/caep_drainer.go`.
- `kacho-iam/internal/apps/kacho/api/caep_subscriber/{create,update,delete,list,test_delivery}.go`.

### Task 8.3: kacho-api-gateway — CAEP internal receiver

**Files:** `kacho-api-gateway/internal/caep/{receiver,handler}.go`

### Task 8.4: kacho-ui — Subscriber registry UI

**Files:** `kacho-ui/src/pages/iam/caep-subscribers/{SubscribersListPage,CreateSubscriberModal,SubscriberDetailPage}.tsx`

### Task 8.5: k6 latency load test

**Files:** `kacho-test/tests/k6/caep_revoke_latency_kac127.js`

### Task 8.6: PR-chain + YT

---

## Phase 9: Audit pipeline (full — Kafka + ClickHouse + S3 + HSM + SIEM + Merkle)

### Task 9.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.9-iam-audit-pipeline-acceptance.md`

- [ ] `acceptance-author`: 30+ GWT. Coverage: audit_outbox write atomic with primary mutation; drainer → Kafka durability; ClickHouse ingest happy/recovery; S3 batch upload with HSM signing; Merkle chain integrity; independent verifier detects tampering; SIEM webhook delivery to Datadog/Splunk/Elastic; detection rules trigger (brute force, impossible travel, mass-delete, out-of-hours-admin, privilege escalation); 90d hot retention; 7y cold retention lifecycle.

### Task 9.2: kacho-corelib/audit — full pipeline

**Files:**
- `corelib/audit/event.go` (CADF schema).
- `corelib/audit/outbox.go` (atomic write helper).
- `corelib/audit/drainer.go` (Kafka producer wrapper).
- `corelib/audit/hsm_signer.go` (PKCS#11 client).
- `corelib/audit/merkle.go`.

### Task 9.3: Kafka cluster deploy

**Files:** `kacho-deploy/helm/umbrella/templates/kafka-strimzi-cluster.yaml`

- [ ] 3 brokers KRaft mode (Strimzi Operator); zstd compression; idempotent producer; topic config (retention 7d, acks=all).

### Task 9.4: ClickHouse cluster deploy

**Files:** `kacho-deploy/helm/umbrella/templates/clickhouse-cluster.yaml`

- [ ] 2 shards × 2 replicas (Altinity Operator); Replicated MergeTree; partitioning by (tenant_id, day).

### Task 9.5: ClickHouse consumer job

**Files:** `kacho-iam/internal/apps/kacho/jobs/clickhouse_ingestor.go`

- [ ] Kafka consumer → batch INSERT в ClickHouse (1000 events / 5s); per-tenant partition.

### Task 9.6: S3 batch writer + HSM signing

**Files:** `kacho-iam/internal/apps/kacho/jobs/s3_audit_writer.go`

- [ ] 5-min batch windows; JSONL.gz; HSM-signed manifest (PKCS#11); Merkle chain (each batch links previous hash).
- [ ] S3 lifecycle policy: hot 30d → IA 1y → Glacier 10y.

### Task 9.7: Independent verifier service

**Files:** `kacho-iam/internal/apps/kacho/jobs/audit_verifier.go`

- [ ] Daily walk S3 Merkle chain; verify all batch signatures; detect: missing batch, tampered batch, broken chain; alert PagerDuty on integrity violation.

### Task 9.8: SIEM webhook forwarders

**Files:** `corelib/audit/siem/{datadog,splunk,elastic,chronicle}.go` + `kacho-iam/internal/apps/kacho/api/siem_subscriber/*.go`

- [ ] Per-tenant subscription; event_types filtering.

### Task 9.9: Detection rules library

**Files:** `kacho-iam/policies/detection/*.rego` (или per-SIEM native rules)

- [ ] All design §9.2 rules implemented.

### Task 9.10: Grafana dashboards для audit

**Files:** `kacho-deploy/dashboards/iam-audit.json`

### Task 9.11: HSM provisioning

**Files:** `kacho-deploy/helm/umbrella/templates/hsm-provisioning-job.yaml`

- [ ] AWS CloudHSM Cluster или GCP Cloud HSM (или SoftHSM для non-prod).
- [ ] Initial key generation + PKCS#11 access policy.

### Task 9.12: PR-chain + YT

- [ ] e2c825 + staging smoke: audit event → ClickHouse query визуализация в Grafana < 60s; daily verifier passes.

---

## Phase 10: In-cluster Workload Identity + Service Mesh (SPIRE + Cilium)

### Task 10.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md`

- [ ] `acceptance-author`: 25-30 GWT. Coverage: SPIRE Server HA deploy; Agent attestation via k8s_psat; SVID issuance per kacho-* pod with cosign image-signature selector; SVID rotation 1h; Cilium mTLS between pods (using SVID); CiliumNetworkPolicy default-deny; AuthorizationPolicy SPIFFE-ID-based; L7 path-based deny; defense-in-depth (compromised pod can't impersonate end-user); Hubble flow visibility; federation bundle publish.

### Task 10.2: SPIRE Server deploy

**Files:** `kacho-deploy/helm/umbrella/templates/spire-server-*.yaml`

- [ ] 3 HA replicas; Postgres-backed; anti-affinity per node.
- [ ] HSM-backed root CA (PKCS#11).
- [ ] Argo CD reads registration entries from `kacho-deploy/spire-registration/*.yaml`.

### Task 10.3: SPIRE Agent DaemonSet

**Files:** `kacho-deploy/helm/umbrella/templates/spire-agent-*.yaml`

### Task 10.4: Cilium service mesh

**Files:**
- `kacho-deploy/helm/umbrella/Chart.yaml` (add cilium dep).
- `kacho-deploy/helm/umbrella/values.{dev,prod}.yaml` — cilium block (eBPF, mesh, WireGuard L3 encryption).
- `kacho-deploy/helm/umbrella/templates/cilium-network-policies.yaml` — per-service allowlists.
- `kacho-deploy/helm/umbrella/templates/cilium-authorization-policies.yaml` — SPIFFE-ID matching.

### Task 10.5: cosign image-signature selector

**Files:** `kacho-deploy/spire-registration/cosign-attestor-config.yaml`

- [ ] SPIRE attestor reads cosign signature → matches against trusted signers (kacho-platform team key) → only signed images get SVID.

### Task 10.6: Federation bundles

**Files:** `kacho-iam/internal/apps/kacho/api/spiffe/federation_bundle.go`

- [ ] Public endpoint `https://spire.kacho.cloud/federation/bundle` serves trust bundle.

### Task 10.7: Re-deploy всех kacho-* services with mesh

- [ ] Each service receives Cilium mesh annotations + SPIFFE Workload API socket mount.

### Task 10.8: Defense-in-depth test

**Files:** `kacho-test/tests/e2e/defense_in_depth_kac127.go`

- [ ] Test: forge end-user principal в gRPC metadata (with valid mesh-mTLS from compromised kacho-vpc) → kacho-iam Check still based on end-user ctx → if forged user has no permission → 403.

### Task 10.9: PR-chain + YT

---

## Phase 11: Production deployment + Observability

### Task 11.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.11-iam-production-deploy-observability-acceptance.md`

- [ ] `acceptance-author`: 30+ GWT. Coverage: api.kacho.cloud reachable via Cloudflare; WAF rules deployed; multi-region active-active failover; Postgres HA failover RTO ≤15min; Kafka cross-region MirrorMaker; ClickHouse cross-region; cert auto-renew (force dry-run); SBOM/SLSA provenance per release; Argo CD GitOps deployment; Grafana dashboards live; Alertmanager rules triggered correctly; PagerDuty integration; runbooks documented and tabletop-tested.

### Task 11.2: Domain + TLS + Cloudflare

**Files:**
- `kacho-deploy/cloudflare-config/{worker.js,dns.tf,waf-rules.tf}` (Terraform or Cloudflare API).
- `kacho-deploy/helm/umbrella/templates/cert-manager-cluster-issuer.yaml`.
- `kacho-deploy/helm/umbrella/templates/api-kacho-cloud-certificate.yaml`.

- [ ] cert-manager with Let's Encrypt ACME DNS-01 (Cloudflare API token).
- [ ] HSTS preload submitted.
- [ ] HTTP/3 enabled at Cloudflare.

### Task 11.3: Multi-region active-active

**Files:**
- `kacho-deploy/clusters/{prod-eu-central,prod-eu-west}/overrides.yaml`.
- `kacho-deploy/postgres-ha/patroni-config.yaml` (или CloudSQL HA / Aurora).
- `kacho-deploy/kafka-mirrormaker-config.yaml`.
- `kacho-deploy/clickhouse-cross-region-replication.yaml`.

### Task 11.4: Argo CD GitOps

**Files:**
- `kacho-deploy/argocd-apps/*.yaml` — Application manifests per env.
- `kacho-deploy/argocd-projects/kacho-iam.yaml`.

### Task 11.5: SBOM + SLSA + cosign

**Files:**
- `.github/workflows/release-iam.yml` — на каждом sibling repo.
- Steps: syft → SBOM (SPDX/CycloneDX); cosign sign --keyless; in-toto/attest-build-provenance.
- Container scan (trivy); vulnerability gate (no HIGH/CRITICAL in new deps).

### Task 11.6: Observability stack

**Files:**
- `kacho-deploy/helm/umbrella/templates/otel-collector-{daemonset,deployment}.yaml`.
- `kacho-deploy/helm/umbrella/templates/{tempo,mimir,loki,grafana}-deployment.yaml`.
- `kacho-deploy/dashboards/*.json` — per-service + IAM-specific.
- `kacho-deploy/alerts/iam-*.yaml` — Alertmanager rules.

### Task 11.7: Runbooks

**Files:** `docs/runbooks/iam/{break-glass,key-rotation,regional-failover,gdpr-erasure,audit-pipeline-incident,caep-backlog,fga-tuple-drift-reconciliation,jwks-rotation-overdue,cert-renewal-failed,kratos-flow-broken,hydra-token-error}.md`

- [ ] Each runbook: problem → diagnosis → mitigation → escalation → post-mortem.
- [ ] Tabletop exercise per runbook (recorded).

### Task 11.8: Renovate / Dependabot config

**Files:** `.github/renovate.json` (or `dependabot.yml`) per sibling repo.

- [ ] Auto-PR weekly; security updates ASAP; group по теме (Go deps / npm deps / Helm charts).

### Task 11.9: PR-chain + YT

- [ ] Smoke: api.kacho.cloud reachable; full E2E from external client; failover test passes (force-failover staging cluster); SLO dashboards green.

---

## Phase 12: Conformance + Pentest + Chaos + Fuzzing

### Task 12.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.12-iam-conformance-pentest-chaos-acceptance.md`

- [ ] `acceptance-author`: 20-25 GWT. Coverage: OWASP ASVS L3 conformance CI test passes; continuous fuzzing (go-fuzz) 7d run без crashes; Litmus chaos game-day quarterly passes; external pentest engagement scheduled + executed + findings remediated; bug bounty launched with security.txt + disclosure policy; OpenID Foundation Self-Certification submitted; FIDO Alliance WebAuthn conformance self-tested.

### Task 12.2: OWASP ASVS L3 conformance test

**Files:**
- `kacho-test/tests/conformance/owasp_asvs_l3/*.py` (or Go).
- CI workflow `.github/workflows/owasp-asvs-l3.yml`.

- [ ] All 280+ requirements mapped to implementation + tested.

### Task 12.3: Continuous fuzzing

**Files:**
- `kacho-iam/internal/apps/kacho/api/*/fuzz_*_test.go` — Go native fuzz (1.18+).
- `.github/workflows/continuous-fuzz.yml` — runs daily; 1h budget per target; results uploaded.

- [ ] Targets: token parsers (JWT, DPoP, SAML assertion, SCIM filter), FGA model parser, Rego policy parser, condition expression evaluator.

### Task 12.4: Litmus chaos engineering

**Files:**
- `kacho-deploy/chaos/chaos-experiments/*.yaml` — pod-kill, network-partition, slow-postgres, dpop-cert-revocation, kafka-broker-down, openfga-replica-down, etc.
- `kacho-deploy/chaos/game-day-schedule.yaml` — quarterly cadence.
- `docs/runbooks/chaos-game-day.md`.

### Task 12.5: External pentest engagement

**Files:** `docs/security/pentest-engagement-2026Q3.md`

- [ ] Engage external firm (e.g., NCC Group / Trail of Bits).
- [ ] Scope: full IAM surface + identity flows + federation + audit + admin operations.
- [ ] Findings tracked в security tracker; remediation SLA per severity (Critical 24h, High 7d, Medium 30d, Low 90d).
- [ ] Re-test after remediation.

### Task 12.6: Bug bounty program + security.txt

**Files:**
- `kacho-deploy/helm/umbrella/templates/security-txt-configmap.yaml` → served at `/.well-known/security.txt`.
- `kacho-ui/public/security/disclosure.html`.
- HackerOne or Bugcrowd account setup; scope + reward table.

### Task 12.7: OpenID Foundation self-certification

**Files:** `docs/security/openid-self-certification-checklist.md`

- [ ] Run OIDC RP conformance test suite (https://www.certification.openid.net).
- [ ] Submit self-certification.

### Task 12.8: FIDO Alliance WebAuthn conformance

**Files:** `docs/security/fido-webauthn-l3-conformance.md`

- [ ] Run FIDO Alliance conformance tools.
- [ ] Document compliance; engage Alliance certification process.

### Task 12.9: PR-chain + YT

---

## Phase 13: Vault docs + KAC-127 final trail

### Task 13.1: Vault updates (30+ files)

**Files:**
- Create: `obsidian/kacho/resources/iam-{cluster,organization,federation-trust-policy,access-binding-condition,jit-eligibility,caep-subscriber,access-review,gdpr-erasure-request,session-revocation,jwks-key,audit-signing-batch,scim-user-mapping,cluster-break-glass-grant,cluster-admin-grant}.md`.
- Modify: `obsidian/kacho/resources/iam-{account,project,user,service-account,group,role,access-binding}.md`.
- Create: `obsidian/kacho/rpc/iam-{internal-cluster-service,organization-service,federation-service,internal-role-service,caep-subscriber-service,internal-break-glass-service,internal-jit-eligibility-service,access-review-service,gdpr-erasure-service,scim-v2-service}.md`.
- Modify: existing iam-*-service.md.
- Create: `obsidian/kacho/edges/iam-to-{hydra-admin,kratos-admin,opa,jackson-saml,scim-okta,scim-azure,scim-google,spire,cilium-mesh,kafka-audit,clickhouse-audit,s3-audit,hsm,siem-datadog,siem-splunk,caep-subscriber-webhook}.md`.
- Create: `obsidian/kacho/packages/{corelib-authz,corelib-audit,corelib-notify,corelib-clients-hydra,corelib-clients-kratos,corelib-clients-jackson,corelib-clients-spire,iam-apps-jit,iam-apps-caep,iam-apps-scim,iam-apps-saml,iam-apps-federation,iam-apps-gdpr,iam-apps-audit,iam-apps-jwks}.md`.

- [ ] `claude` agent — узкие 1-3KB файлы; kepano-style frontmatter; wikilinks.

### Task 13.2: KAC-127 final trail update

**Files:** `obsidian/kacho/KAC/KAC-127.md`

- [ ] status=done, closed=<date>, all 13 subtask PR URLs.
- [ ] Mark all DoD checkboxes.

### Task 13.3: Public documentation

**Files:** `docs.kacho.cloud/`
- `iam/` — user-facing (signup, MFA, SA, Federation, Role mgmt, JIT, Audit query).
- `admin/iam/` — admin-facing (Org SSO, SCIM, Break-glass, Compliance reports).
- `dev/iam/` — developer (Federation OIDC setup для CI/CD).

### Task 13.4: Close YT KAC-123 → Done. Sprint cleanup. Cleanup worktrees.

---

## Estimated effort

| Phase | Tasks | Effort (single eng) |
|---|---|---|
| 0 Ticketing | 2 | 1d |
| 1 Foundation | 6 | 2-3w |
| 2 AuthN core | 9 | 3-4w |
| 3 AuthZ core | 7 | 3-4w |
| 4 List filtering | 5 | 2w |
| 5 Workload Identity Federation | 8 | 3-4w |
| 6 Enterprise SSO | 7 | 4-5w |
| 7 JIT/PIM + Break-glass + Reviews + GDPR | 8 | 3-4w |
| 8 CAEP push pipeline | 6 | 2-3w |
| 9 Audit pipeline (full) | 12 | 4-5w |
| 10 SPIFFE/SPIRE + Cilium mesh | 9 | 4-5w |
| 11 Production deployment + Observability | 9 | 5-6w |
| 12 Conformance + Pentest + Chaos + Fuzzing | 9 | 4-5w |
| 13 Vault + docs closeout | 4 | 1-2w |
| **Total** | **101** | **~40-52 weeks** (single eng); **~5-7 months** parallel (team of 4-5) |

---

## Risk register (production-grade)

| Risk | Mitigation |
|---|---|
| Acceptance docs review cycles затянут timeline | Round-trip budget per phase; parallel write+review where possible |
| External pentest blocked by vendor scheduling | Engage 3 months upfront; reserve calendar slot |
| HSM provisioning latency (cloud vendor) | Begin Phase 9 setup as soon as Phase 0 complete (parallel track) |
| Postgres HA failover real-world testing | Staging environment with realistic load; quarterly DR drills |
| Cilium service mesh deployment edge cases | Staging pre-soak 2 weeks before prod; canary deploy |
| SCIM/SAML interop quirks с Okta/Azure | Use vendor sandboxes; engage support if blocked |
| GitHub Actions OIDC token format changes | Pin issuer config; alert on JWKS unexpected changes |
| Kafka KRaft mode operator immaturity | Use Strimzi (CNCF graduated); test upgrades in staging first |
| ClickHouse Operator stability | Use Altinity (commercial-backed open-source) |
| Cert auto-renew failure | Multiple ACME-providers configured fallback (Let's Encrypt + ZeroSSL) |
| Pentest finds Critical → block GA | Critical SLA 24h remediation; re-test before launch |
| OWASP ASVS L3 non-conformance | Continuous CI test; fix-as-you-go |
| Compliance audit gaps | Engage SOC 2 auditor pre-engagement consultation; align controls before formal audit |

---

**End of plan.** Implementation begins after each phase's acceptance doc is APPROVED (запрет CLAUDE.md #1). Никаких deferred — все 13 phases в scope этого эпика, DoD требует full completion.
