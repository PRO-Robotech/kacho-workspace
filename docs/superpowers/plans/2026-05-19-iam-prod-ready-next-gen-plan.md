# Production-ready Next-Gen IAM — Implementation Plan (vault-label KAC-127 / YT KAC-123)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Полная перестройка Kachō IAM в production-ready состоянии — ORY Kratos+Hydra (WebAuthn/Passkey + DPoP), OpenFGA v2 + Conditions + OPA guardrails, Workload Identity Federation (GitHub/AWS/GCP) для external M2M, SCIM 2.0 + SAML bridge, PIM/JIT elevation + break-glass, CAEP push pipeline.

**Architecture:** 8 phases поверх KAC-108/125 baseline. Identity hierarchy `cluster → organization (optional) → account → project → resource`. Custom Role multi-scope.

**Out of scope (отдельные future эпики, не в этом плане):**
- Audit-infra (Kafka/ClickHouse/S3/HSM/SIEM/Merkle).
- **In-cluster workload identity + service mesh mTLS** (SPIFFE/SPIRE + Cilium/Linkerd) — на MVP service-to-service auth = K8s NetworkPolicy + Internal listener + end-user principal forwarding в gRPC metadata.

**Tech Stack:** Go 1.22 + sqlc/pgx; PostgreSQL 16 + LISTEN/NOTIFY; ORY Kratos v1.4 (WebAuthn) + Hydra v2.4 (OIDC + DPoP); OpenFGA v1.6 (Conditions + ListObjects); OPA v1.0 (Rego); Jackson (SAML bridge); SCIM 2.0 endpoint; CAEP/SSF SET signing.

**Reference docs:**
- Design: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md`
- Vision: `docs/superpowers/specs/2026-05-19-iam-revolutionary-architecture-design.md`
- Skill: `.claude/skills/iam-architect/SKILL.md`
- KAC-127 vault: `obsidian/kacho/KAC/KAC-127.md` (YT: KAC-123)
- Workspace policy: `CLAUDE.md` (новый раздел «Изоляция рабочего пространства между агентами»)

---

## Workflow notes

- Coding-gate per CLAUDE.md запрет #1 — APPROVED acceptance doc per phase прежде кода.
- Test discipline per CLAUDE.md запрет #11 — integration + newman в том же PR.
- **Branch isolation** per новое правило CLAUDE.md — каждая работа в git worktree per branch.
- Per-PR mandatory: integration tests (testcontainers Postgres) + newman cases (gen.py → Postman). "tests-followup" — только с trakable KAC-tickets.

---

## Phase 0: Ticketing & worktrees

### Task 0.1: Создать 8 subtasks под KAC-123

**Files**: external (YouTrack).

- [ ] **Step 1:** Через REST API create 8 issues в проекте KAC, привязать к KAC-123 через `subtask of`, добавить в текущий спринт:

```bash
YT="https://prorobotech.youtrack.cloud/api"
TOKEN="<perm-token>"   # из memory youtrack-credentials

for phase in \
  "Phase1-Foundation:[Phase 1] IAM Foundation — DB schema (Org, Cluster, Federation, Conditions, JIT, outboxes) + bootstrap migration" \
  "Phase2-AuthN-core:[Phase 2] IAM AuthN — Kratos WebAuthn/Passkey + Hydra DPoP + step-up + recovery" \
  "Phase3-AuthZ-core:[Phase 3] IAM AuthZ — OpenFGA model v2 + Conditions + OPA sidecar" \
  "Phase4-List-filtering:[Phase 4] IAM ListObjects per List-handler (vpc/compute/lb)" \
  "Phase5-Workload-Identity:[Phase 5] IAM SA-keys (Hydra Class A) + Federation Trust (Class B GitHub/AWS/GCP)" \
  "Phase6-Enterprise-SSO:[Phase 6] IAM SCIM 2.0 + SAML bridge (Jackson) + Organization tier" \
  "Phase7-JIT-PIM-Breakglass:[Phase 7] IAM JIT/PIM elevation + Break-glass 2-person approve" \
  "Phase8-CAEP:[Phase 8] IAM CAEP push pipeline (real-time revoke ≤10s; webhook subscribers)"; do
  SUMMARY="${phase#*:}"
  curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -X POST \
    "$YT/issues?fields=id,idReadable" \
    -d "{\"project\":{\"id\":\"0-5\"},\"summary\":\"$SUMMARY\",\"description\":\"Подэпик KAC-123. См. spec docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md\"}"
done
```

- [ ] **Step 2:** Привязать как subtasks через `/commands`:

```bash
for sub in KAC-124 KAC-125 KAC-126 KAC-127 KAC-128 KAC-129 KAC-130 KAC-131; do   # фактические номера после Step 1
  curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -X POST \
    "$YT/commands" \
    -d "{\"query\":\"subtask of KAC-123\",\"issues\":[{\"idReadable\":\"$sub\"}]}"
done
```

- [ ] **Step 3:** Добавить все 8 в текущий спринт:

```bash
curl -sS -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -X POST \
  "$YT/commands" \
  -d "{\"query\":\"Board kacho <текущий-спринт-name>\",\"issues\":[{\"idReadable\":\"KAC-124\"},{\"idReadable\":\"KAC-125\"},{\"idReadable\":\"KAC-126\"},{\"idReadable\":\"KAC-127\"},{\"idReadable\":\"KAC-128\"},{\"idReadable\":\"KAC-129\"},{\"idReadable\":\"KAC-130\"},{\"idReadable\":\"KAC-131\"}]}"
```

### Task 0.2: Worktrees в 10 репо (изоляция per phase)

Per new CLAUDE.md rule «Изоляция рабочего пространства»:

- [ ] **Step 1:** Для каждой Phase N создаём worktree от main в каждом затронутом репо:

```bash
# Пример для Phase 1 (Foundation) в kacho-iam:
cd project/kacho-iam
git worktree add -b KAC-124 ../kacho-iam-KAC-124 main
cd ../kacho-iam-KAC-124
# работаем здесь
```

Аналогично для других репо/phases. После merge — `git worktree remove`.

---

## Phase 1: Foundation (DB schema + bootstrap migration)

### Task 1.1: Acceptance doc (red phase)

**Files:**
- Create: `docs/specs/sub-phase-3.1-iam-foundation-acceptance.md`

- [ ] Dispatch `acceptance-author` agent:
  > На основе `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` §3 (Identity Model) + §4 (OpenFGA model — только schema, без deploy) напиши Given-When-Then acceptance (15-20 GWT): миграция 0011 (clusters/organizations/cluster_admin_grants/cluster_break_glass_grants/service_account_oauth_clients/federation_trust_policies/access_binding_conditions/access_bindings_jit_eligibility/audit_outbox/caep_outbox/caep_subscribers/gdpr_erasure_requests skeleton); roles refactor (multi-scope: cluster/org/account/project — exactly one non-NULL); access_bindings status + condition_id; service_accounts project_id + enabled. Acceptance включает: migration idempotency (re-run), CHECK constraints, partial UNIQUE indexes, FK RESTRICT cascades, multi-scope role validation, status PENDING-ACTIVE-REVOKED state machine.

- [ ] `acceptance-reviewer` round-trip до APPROVED.

### Task 1.2: kacho-proto — message types для новых entity

**Files:** в `kacho-proto/proto/kacho/cloud/iam/v1/`:
- Modify: `role.proto` (multi-scope: oneof scope { cluster_id, organization_id, account_id, project_id })
- Modify: `access_binding.proto` (status enum + condition_id)
- Create: `organization.proto`
- Create: `cluster.proto`
- Create: `federation_trust_policy.proto`
- Create: `access_binding_condition.proto`
- Create: `jit_eligibility.proto`

- [ ] `proto-sync` agent — envelope-style metadata/spec/status; buf.validate annotations.
- [ ] `proto-api-reviewer` — `buf breaking` clean; никаких yandex.

### Task 1.3: kacho-iam — миграция 0011

**Files:** `kacho-iam/internal/migrations/0011_kac123_foundation.sql`

- [ ] `migration-writer` agent (см. design §3.1):
  - CREATE clusters + singleton row.
  - CREATE organizations.
  - CREATE cluster_admin_grants, cluster_break_glass_grants.
  - CREATE service_account_oauth_clients, federation_trust_policies.
  - CREATE access_binding_conditions, access_bindings_jit_eligibility.
  - CREATE audit_outbox, caep_outbox, caep_subscribers.
  - CREATE gdpr_erasure_requests (skeleton only; not yet wired).
  - ALTER roles: DROP COLUMN account_id, ADD cluster_id/organization_id/project_id, CHECK exactly_one_scope.
  - ALTER access_bindings: ADD status, condition_id (FK→access_binding_conditions(id) ON DELETE RESTRICT), expires_at.
  - ALTER service_accounts: ADD project_id (FK→projects(id) ON DELETE RESTRICT), enabled.
  - INSERT seed system-roles: kacho-system.admin, kacho-system.viewer (cluster-scoped).
  - INSERT outbox-tuple-write seed для cluster_admin (env KACHO_IAM_BOOTSTRAP_ROOT_EMAIL).

- [ ] `db-architect-reviewer` — partial UNIQUE syntax, FK RESTRICT, multi-scope CHECK.

### Task 1.4: kacho-iam domain + repo

**Files:** в `kacho-iam/internal/`:
- Create: `domain/cluster.go`, `domain/organization.go`, `domain/federation_trust_policy.go`, `domain/access_binding_condition.go`, `domain/jit_eligibility.go`.
- Modify: `domain/role.go` (multi-scope newtype), `domain/access_binding.go` (status enum + condition_id).
- Create: `repo/kacho/pg/cluster.go`, `organization.go`, `federation_trust_policy.go`, `access_binding_condition.go`, `jit_eligibility.go`.
- Modify: `repo/kacho/pg/role.go`, `access_binding.go`.
- Tests: integration tests с testcontainers Postgres.

- [ ] `rpc-implementer` — реализация всех CRUD + integration tests (см. acceptance GWT).

### Task 1.5: Commit + PR + YT

- [ ] PR `kacho-iam/KAC-124` (Phase 1).
- [ ] `go-style-reviewer` + `db-architect-reviewer` round-trip.
- [ ] Merge → YT KAC-124 → Done; KAC-123 comment with PR URL.

---

## Phase 2: AuthN core (Kratos WebAuthn + Hydra DPoP + step-up)

### Task 2.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`

- [ ] `acceptance-author` (§5 + §11 + skill `references/oidc-oauth2.md` §3-9): 15-20 GWT — WebAuthn registration, Passkey signin, DPoP token validation, step-up, recovery via Kratos `/recovery`, token rotation, replay-protect (jti cache), JWKS rotation, ACR/AMR enforcement.

### Task 2.2: Kratos config (WebAuthn enabled)

**Files:** `kacho-deploy/helm/umbrella/charts/kacho-iam/templates/kratos-config-configmap.yaml`

- [ ] Включить WebAuthn в Kratos identity schema; configure `selfservice.methods.webauthn.config.passwordless=true`; rp.id=kacho.cloud.
- [ ] Recovery flow с magic-link.
- [ ] Hooks: registration after webauthn → POST kacho-iam UpsertFromIdentity.

### Task 2.3: Hydra config (DPoP enabled)

**Files:** `kacho-deploy/helm/umbrella/values.dev.yaml` (hydra block)

- [ ] `oauth2.dpop.enabled=true`.
- [ ] TTL: access 15min, refresh 30d (rotation), id 15min.
- [ ] token_hook + refresh_token_hook → kacho-iam endpoints (для injecting ext_claims).

### Task 2.4: kacho-api-gateway — DPoP validation

**Files:** в `kacho-api-gateway/internal/`:
- Modify: `auth/jwt_validator.go` — добавить DPoP path.
- Create: `auth/dpop_validator.go` — RFC 9449 implementation (htm/htu/iat/jti cache).
- Create: `auth/dpop_test.go` — replay protection scenarios.

- [ ] `rpc-implementer` + `go-style-reviewer`.

### Task 2.5: kacho-iam — token_hook handler

**Files:** `kacho-iam/internal/apps/kacho/api/hydra/token_hook.go`

- [ ] Hydra calls this on each token issue → kacho-iam injects ext_claims (active_account, organization_id, principal_type).

### Task 2.6: kacho-ui — Passkey signin/registration

**Files:** в `kacho-ui/src/pages/auth/`:
- Modify: SigninPage с conditional UI (Passkey autofill).
- Modify: RegistrationPage с "Sign up with Passkey" CTA.
- Create: StepUpModal для acr=3 requirements.

### Task 2.7: PR-chain + YT

- [ ] PR'ы в kacho-deploy, kacho-api-gateway, kacho-iam, kacho-ui (porder).
- [ ] e2c825 smoke: signup → Passkey → JWT с acr=2 и DPoP claim → API call validates.
- [ ] YT KAC-125 → Done.

---

## Phase 3: AuthZ core (OpenFGA model v2 + Conditions + OPA)

### Task 3.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`

- [ ] `acceptance-author` (§4 design + skill `references/zanzibar-rebac.md`): 20-25 GWT — model deploy idempotent, Conditions (mfa_fresh/non_expired/source_ip/jit_window/break_glass_window), per-condition tuple write, Conditional Check (allowed/denied based on context), OPA deny rules (billing-project, SA-grant-user, org-region), Check fail-closed, cache invalidation.

### Task 3.2: openfga-bootstrap-job DSL v2

**Files:** `kacho-deploy/helm/umbrella/templates/openfga-model-stub-configmap.yaml` (replace) + `openfga-bootstrap-job.yaml`

- [ ] DSL из design §4 (cluster/org/account/project/resource + Conditions block).
- [ ] Idempotency: helm upgrade with same DSL → skip if model_id matches.

### Task 3.3: corelib/authz — Conditions support

**Files:** `corelib/authz/check.go` (extend для contextual_tuples передачи), `corelib/authz/listobjects.go` (Phase 4 prepwork).

- [ ] `rpc-implementer` — KAC-108 extension: pass principal context (amr/acr/source_ip/mfa_at) в Check call.

### Task 3.4: kacho-iam — Conditions repo + handlers

**Files:** в `kacho-iam/internal/`:
- Create: `repo/kacho/pg/access_binding_condition.go`.
- Modify: `apps/kacho/api/access_binding/upsert.go` — поддержка condition_id; при tuple-write передавать condition + context в OpenFGA.

### Task 3.5: OPA sidecar deploy

**Files:** `kacho-deploy/helm/umbrella/templates/opa-sidecar-configmap.yaml`

- [ ] Bundle pull mode: OPA pulls Rego policies from kacho-iam-served HTTPS endpoint (cached 1h).
- [ ] Sidecar attached к kacho-api-gateway pod.
- [ ] Sidecar evaluates AFTER OpenFGA Check passes.

### Task 3.6: kacho-iam — OPA policy bundle endpoint

**Files:** `kacho-iam/internal/apps/kacho/api/opa/bundle.go`

- [ ] Serves Rego policies + data; signed bundle для OPA verification.

### Task 3.7: PR-chain + YT

- [ ] e2c825 smoke: deploy model v2 → Check on conditional binding (mfa_fresh) → fails without acr=3 → step-up → succeeds. OPA deny on billing-project verified.
- [ ] YT KAC-126 → Done.

---

## Phase 4: List filtering (ListObjects integration)

### Task 4.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.4-iam-list-filtering-acceptance.md`

- [ ] `acceptance-author` (§7 design): 10-15 GWT — empty grants → {}; 2-id grants → 2 resources; cluster-admin → all; cache hit/miss; LISTEN-invalidate; SLA p95 ≤ 100ms.

### Task 4.2: corelib/authz/listobjects.go

**Files:** `corelib/authz/listobjects.go` + `listobjects_test.go`

- [ ] `rpc-implementer`:
  - `ListAllowedIDs(ctx, principal, objectType, relation, opts) → ([]string, consistency_token, error)`.
  - In-memory LRU cache, 5s TTL.
  - LISTEN `kacho_iam_subjects` → invalidate on NOTIFY.
  - OpenFGA `ListObjects` API call with `Consistency` parameter.
  - Fail-closed on OpenFGA unavailable.

### Task 4.3: vpc/compute/lb — List-handler rewrite

**Files:** in each of:
- `kacho-vpc/internal/apps/kacho/api/{network,subnet,security_group,route_table,address,gateway,private_endpoint,network_interface,address_pool}/list.go`
- `kacho-compute/internal/apps/kacho/api/{instance,disk,image,snapshot}/list.go`
- `kacho-loadbalancer/internal/apps/kacho/api/{network_load_balancer,target_group}/list.go`

- [ ] Replace existing "Check parent then return all" with `ListAllowedIDs` + `SELECT WHERE id IN(...)`.
- [ ] Integration tests: empty / 2-id / cluster-admin / SA-with-binding.

### Task 4.4: k6 load test

**Files:** `kacho-test/tests/k6/list_filter_kac123.js`

- [ ] 100 networks per project, 10 users with N bindings (N=1, 10, 50, 100); 100 RPS sustained 5min.
- [ ] Assert p95 ≤ 100ms, p99 ≤ 250ms.
- [ ] Results → `kacho-test/tests/k6/results/KAC-127-list-filter.md`.

### Task 4.5: PR-chain + YT

- [ ] 3 PRs (vpc/compute/lb) + corelib PR + test PR.
- [ ] Newman cases для list-filter scenarios.
- [ ] YT KAC-127 → Done.

---

## Phase 5: Workload Identity (SA tokens + Federation)

### Task 5.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.5-iam-workload-identity-federation-acceptance.md`

- [ ] `acceptance-author` (§6 design + skill `references/workload-identity.md`): 20-25 GWT — SA-key Create (Hydra), Delete (revoke), List; Federation policy Create with subject_pattern validation (no wildcard `*`); Federation Exchange (Token Exchange RFC 8693); GitHub OIDC verification (mock JWKS); AWS IRSA / GCP WIF (mocked); subject_pattern mismatch → denied; expired policy → denied.

### Task 5.2: kacho-corelib — hydra-admin client + kratos-admin recovery

**Files:**
- Create: `corelib/clients/hydra_admin.go` + tests.
- Modify (KAC-125 stub): `corelib/clients/kratos_admin.go` — full recovery-link generation.

### Task 5.3: kacho-iam — ServiceAccountKeyService

**Files:** `kacho-iam/internal/apps/kacho/api/sa_key/{create,delete,list}.go`

- [ ] Create: Hydra admin POST /admin/clients; INSERT service_account_oauth_clients; return secret one-shot in Operation.response.
- [ ] Delete: Hydra DELETE; row delete; CAEP outbox emit.
- [ ] List: SELECT (без secret); response has hydra_client_id only.

### Task 5.4: kacho-iam — FederationExchangeService

**Files:** `kacho-iam/internal/apps/kacho/api/federation/{create_policy,exchange}.go`

- [ ] `CreatePolicy`: validate issuer in whitelist (or admin-override); subject_pattern can't contain `*` (or limited paths only).
- [ ] `Exchange`: parse subject_token (JWT) → verify via dynamic JWKS lookup (cached 24h per issuer) → match against policies → issue Kachō JWT (TTL ≤15min, sub=sva-id).
- [ ] Apply Conditions in trust policy at exchange time (source_ip, time-of-day).

### Task 5.5: kacho-api-gateway — /federations:exchange endpoint

**Files:** register на public mux.

### Task 5.6: kacho-ui — SA-keys page + Trust Policy page

**Files:** in `kacho-ui/src/pages/iam/sa-keys/` and `kacho-ui/src/pages/iam/federations/`.

- [ ] Issue Key modal с warning "save secret now".
- [ ] Trust Policy create form (issuer dropdown, subject_pattern field with validation).
- [ ] Federation Exchange docs page (snippets для GitHub Actions / GitLab CI / AWS IRSA).

### Task 5.7: PR-chain + YT

- [ ] Smoke e2c825: mock GitHub OIDC token → exchange → Kachō JWT → API call success.
- [ ] YT KAC-128 → Done.

---

## Phase 6: Enterprise SSO (SCIM 2.0 + SAML + Organization tier)

### Task 6.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.6-iam-scim-saml-organization-acceptance.md`

- [ ] `acceptance-author` (skill `references/oidc-oauth2.md` §10-11 + design §5.1 Federation): 25-30 GWT — Organization create; SCIM /Users CRUD; SCIM /Groups CRUD; SAML metadata-exchange; SAML SP-init flow; JIT provisioning on first SAML; domain-claim assignment.

### Task 6.2: kacho-proto — Organization + SCIM proto

**Files:** create `proto/iam/v1/organization.proto`, `proto/iam/v1/scim_service.proto` (REST-only — SCIM is HTTP/JSON, but we proxy through gRPC-gateway).

### Task 6.3: kacho-iam — OrganizationService + SCIM endpoints

**Files:** in `kacho-iam/internal/apps/kacho/api/`:
- Create: `organization/{create,update,delete,get,list}.go`.
- Create: `scim/{users,groups,bulk}.go` — full SCIM 2.0 spec compliance (RFC 7644).

### Task 6.4: SAML bridge deploy

**Files:** `kacho-deploy/helm/umbrella/templates/jackson-saml-bridge-deployment.yaml`

- [ ] Deploy [Jackson](https://github.com/boxyhq/jackson) — translates SAML → OIDC; mounted под `https://hydra.kacho.cloud/saml`.
- [ ] Per-organization SAML metadata XML upload UI.

### Task 6.5: kacho-ui — Organization admin pages

**Files:** in `kacho-ui/src/pages/iam/organizations/`:
- Org create / details / SSO config / SCIM-token issue / domain-claim verification.

### Task 6.6: PR-chain + YT

- [ ] Smoke: create Organization → assign domain → SAML metadata upload → simulated Okta SAML signin → JIT-provisioned User → Account auto-assigned in org.
- [ ] YT KAC-129 → Done.

---

## Phase 7: JIT/PIM + Break-glass

### Task 7.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.7-iam-jit-breakglass-acceptance.md`

- [ ] `acceptance-author` (design §13.4 J35 + skill `references/security-2026.md`): 15-20 GWT — JIT eligibility CRUD, ActivateJIT (with step-up acr=3), JIT expiry, Break-glass request (single approval = denied), Break-glass 2-approve (granted), PagerDuty webhook, 2h auto-expire, post-incident audit retention.

### Task 7.2: kacho-iam — JIT + Break-glass handlers

**Files:**
- Create: `apps/kacho/api/access_binding/activate_jit.go`.
- Create: `apps/kacho/api/cluster/{request_break_glass,approve_break_glass,list_pending}.go`.

- [ ] ActivateJIT: validate eligibility row exists; require step-up; INSERT access_bindings with jit_window condition + activated_at; outbox tuple.
- [ ] Break-glass: state machine AWAITING_APPROVAL_A → AWAITING_APPROVAL_B → ACTIVE → EXPIRED.
- [ ] Background job: scan break_glass_grants WHERE status=ACTIVE AND expires_at < now → emit revoke tuple; status=EXPIRED.

### Task 7.3: Alerting integrations

**Files:**
- `corelib/notify/pagerduty.go`, `corelib/notify/slack.go`.
- kacho-iam wires both to break_glass grant event.

### Task 7.4: kacho-ui — JIT activation modal + Break-glass approver UI

### Task 7.5: PR-chain + YT

- [ ] e2c825 smoke: JIT activate (eligible user) → 1h admin → expires; Break-glass 2-approve → PagerDuty alert verified → 2h cookoff.
- [ ] YT KAC-130 → Done.

---

## Phase 8: CAEP push pipeline

> **SPIFFE/SPIRE + service mesh mTLS — OUT OF SCOPE этого эпика** (см. §0 "Out of scope" в Goal). Будущий отдельный эпик. На MVP service-to-service auth = K8s NetworkPolicy + Internal listener + end-user principal forwarding в gRPC metadata (как сейчас в KAC-108).

### Task 8.1: Acceptance doc

**Files:** `docs/specs/sub-phase-3.8-iam-caep-push-acceptance.md`

- [ ] `acceptance-author` (design §10 + skill `references/security-2026.md` §2): 15-20 GWT — CAEP subscriber CRUD, SET signing/verification, webhook delivery happy/retry/failed_terminal, signature verification by subscriber, internal CAEP receiver in api-gateway (session_revocations + cache invalidation), revoke latency ≤10s SLA, subscriber-side replay protection (jti cache).

### Task 8.2: kacho-iam — CAEP outbox + drainer + SET signing

**Files:**
- `apps/kacho/jobs/caep_drainer.go` — pulls caep_outbox, signs SET, POSTs to subscribers.
- `apps/kacho/api/caep_subscriber/{create,update,delete,list}.go`.
- `apps/kacho/api/caep_subscriber/test_delivery.go` — admin tool для verification subscriber.

- [ ] SET = signed JWT (kacho-iam's signing key share или dedicated key); aud per-subscriber.
- [ ] Retry exponential: 1s, 5s, 30s, 5min, 1h, 6h, 24h; max 8 attempts; status=failed_terminal after.
- [ ] Per-subscriber rate-limit (max 100 events/min) — защита от cascade attack.

### Task 8.3: kacho-api-gateway — CAEP internal receiver

**Files:** `kacho-api-gateway/internal/caep/receiver.go`

- [ ] On internal CAEP event (kacho-iam direct call, not webhook): INSERT session_revocations + invalidate principal cache + emit metric.

### Task 8.4: Subscriber registry UI

**Files:** `kacho-ui/src/pages/iam/caep-subscribers/`

- [ ] Admin UI: list/create/delete subscriber endpoints; per-subscriber test-delivery button.
- [ ] Display per-subscriber: success rate, last delivery, current backoff status.

### Task 8.5: K6 load test (revoke latency SLA)

**Files:** `kacho-test/tests/k6/caep_revoke_latency_kac127.js`

- [ ] Сценарий: 10 subscribers, 100 revoke events/min, sustained 10 min.
- [ ] Assert: p95 webhook delivery ≤ 2s; p99 ≤ 5s; total revoke→effect ≤ 10s.

### Task 8.6: PR-chain + YT

- [ ] e2c825 smoke: revoke binding → внутренний receiver invalidates ≤ 1s; webhook delivered to test-SP within 10s; subscriber rejects replay (same jti) → 409.
- [ ] YT subtask → Done.

---

## NOT in this epic: Workload Identity (SPIFFE/SPIRE) + Service Mesh mTLS

> **OUT OF SCOPE** — отдельный future эпик. Why deferred:
> - SPIRE deploy + selectors per kacho-* service + integration с каждым pod = недели работы.
> - Service mesh (Linkerd / Cilium) добавляет cluster-wide infra (control plane, sidecars/eBPF) — operational complexity без явной выгоды на MVP-стенде.
> - Текущий defense-in-depth от KAC-108 (end-user principal в gRPC metadata + K8s NetworkPolicy на internal listener) — **уже достаточен** для production-MVP single-tenant и small-tenant deployments.
> - Когда трафик и compliance требования вырастут — SPIFFE+mesh добавляется как extra layer, не меняя текущую модель.

---

## Phase 9: Audit infra (OUT OF SCOPE — future epic)

Not in this plan. Skeleton (`audit_outbox`, `slog` drainer) сделан в Phase 1. Future epic ~KAC-200+ накатит: Kafka, ClickHouse, S3+Glacier, HSM signing, SIEM webhook subscribers, Merkle chain.

---

## Phase 10: Vault docs + KAC-127 final trail

### Task 10.1: Vault updates (15+ files)

See KAC-127 vault stub «Затронутые сущности vault» (8 категорий, 20+ files).

- [ ] `claude` agent — узкие 1-3KB файлы; kepano-style frontmatter; wikilinks.

### Task 10.2: KAC-127 final commit + close

- [ ] Update `obsidian/kacho/KAC/KAC-127.md` — status=done, closed=<date>, all 8 subtask PR URLs.
- [ ] YT KAC-123 → Done.
- [ ] Sprint cleanup.

---

## Estimated effort

| Phase | Tasks | Effort (single eng) |
|---|---|---|
| 0 Ticketing | 2 | 0.5d |
| 1 Foundation | 5 | 1.5w |
| 2 AuthN core | 7 | 2-3w |
| 3 AuthZ core | 7 | 2-3w |
| 4 List filtering | 5 | 1.5w |
| 5 Workload Identity | 7 | 2-3w |
| 6 Enterprise SSO | 6 | 3-4w |
| 7 JIT/PIM | 5 | 1.5-2w |
| 8 CAEP push | 6 | 2w |
| 10 Vault closeout | 2 | 0.5w |
| **Total** | **53** | **~18-23 weeks** (4.5-5.5 months single eng); ~3-4 months 2 eng parallel |

---

## Risk register

| Risk | Mitigation |
|---|---|
| KAC-108/125 not fully merged | Pre-check; block work until baseline ready |
| OpenFGA Conditions immature in 1.6 | Pin specific OpenFGA version; integration tests cover edge cases |
| Hydra DPoP edge cases (Safari) | Bearer fallback behind feature flag; gradual rollout |
| SCIM 2.0 spec interpretation | RFC 7644 compliance tests; Okta/Azure sandbox testing |
| SAML bridge (Jackson) operational | Monitor + fallback to manual SAML setup option |
| Workload Identity Federation auth bypass | Strict subject_pattern validation; deny `*`; integration tests with malicious tokens |
| ~~SPIFFE/SPIRE complexity~~ | OUT OF SCOPE этого эпика — future epic |
| CAEP delivery failures | Retry exponential + dead-letter queue; admin UI to retry manually |
| Break-glass abuse | 2-person mandatory; PagerDuty alert; quarterly review of usage |
| Audit gap (Phase 9 not done) | slog-stdout sufficient for non-prod; document path to full pipeline |

---

**End of plan.** Implementation begins after each Phase's acceptance doc is APPROVED (запрет CLAUDE.md #1).
