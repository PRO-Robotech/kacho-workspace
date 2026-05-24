# Sub-phase W2.B — Stream B: Enterprise Block (B.1–B.10) — Acceptance

> **Status**: DRAFT — v2 revised per KAC-172 (acceptance-reviewer CHANGES REQUESTED on v1, see `docs/specs/KAC-170-acceptance-review-report.md`). Awaiting re-review by `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1.
> **Date**: 2026-05-24 (v2 — revised per KAC-172; scope split Option Y ratified)
> **YouTrack**: KAC-W2.B (TBD — create epic per parent KAC-134 "kacho-iam → production-ready"; subtasks B.1…B.10).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` (handler + service + usecase + repo + cmd wiring; new migration files only where DB schema does not yet exist — see §3 per-feature column).
>   - `PRO-Robotech/kacho-proto` — touched only where new RPC / new field is required (B.4 break-glass workflow extensions; B.7 GDPR cancel-token; B.8 CAEP subscriber-management RPCs on internal listener; B.5 review-campaign workflow RPCs — see per-feature §«gRPC API surface»).
>   - `PRO-Robotech/kacho-deploy` — helm chart values for B.9 vector.dev sidecar; B.10 SPIFFE-ID labels + Cilium AuthorizationPolicy for internal-listener mTLS.
>   - **NOT touched (verified by §3 checks)**: `kacho-corelib` (no new horizontal helper required — B.9 emit uses existing `observability/slog` + new thin `audit/JSONEmitter` lives in kacho-iam since only this service emits audit); `kacho-api-gateway` (Stream A registers gateway routes for B.4/B.5/B.6/B.7 — out of scope here, see §0.1); `kacho-vpc` / `kacho-compute` (no cross-service touch — B.8 webhook delivery + B.10 SPIRE wiring are iam-internal).
> **Branch (kacho-iam)**: per-feature `KAC-W2.B-<feature-id>` (e.g. `KAC-W2.B-1-saml-acs`, `KAC-W2.B-9-vector-pipeline`) off `main`.
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 2, Stream B (enterprise).
> **Predecessor remediation plan**: `docs/superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` — findings #40 (full SAML XML-DSig verify — **DEFERRED to W3.1**), #41 (SCIM per-org Basic-auth — **STAYS in W2.B B.2**, master plan §W3 row does NOT list #41), #42 (CAEP ingress SET verify — **DEFERRED to W3.1**; W2.B B.8 is egress sign, different code path); #35/#37/#43 (closed in W1.6) gate the spoof-safe layer underneath B.5/B.6/B.4/B.7.
> **Production-launch plan**: `docs/superpowers/plans/2026-05-21-production-launch-plan.md` — WS-3.3 audit-pipeline = vector.dev → VictoriaLogs (B.9); WS-3.x SPIRE/Cilium wiring (B.10).
> **Predecessors (must be `main`-merged before any B.x impl starts)**:
> - **W1.4** — principal propagation cross-service (KAC-140) — **MERGED**. Required so iam handlers + audit emit (B.9) record the *true* caller (not `user:bootstrap`) on cross-service-triggered events (e.g. JIT-activate caused by upstream vpc call).
> - **W1.5** — Remediation Chunk 1 (KAC-163) — **PR open / merging**. Required so grant-write path (`fga_outbox` drainer + atomic emit) is GREEN; B.3 JIT-activate + B.4 break-glass-activate + B.5 access-review-approve are **all grant-writers** and would silently leak grants without W1.5. **Hard-blocker for B.3 / B.4 / B.5** (per §0.2). Other features (B.1 / B.2 / B.6 / B.7 / B.8 / B.9 / B.10) do not depend on W1.5 grant-write atomicity and can start once W2.B doc APPROVED.
> - **W1.6** — Remediation Chunk 2 (KAC-164) — **DRAFT acceptance** (peer document, in-flight). Required so anti-anon allowlist gate is in place on `Approve*` / `Deny*` / `Issue` / `Revoke` / `Generate*` / `Cancel*` / `ActivateJIT` (this is finding #43); B.4 (Approve A/B), B.7 (CancelErasureRequest), B.5 (ApproveReviewItem / RevokeReviewItem), B.6 (GenerateAccessReport) all depend on that interceptor change to refuse anonymous callers. Also W1.6 #35 (reviewer-from-principal) gates B.5 audit-shape; W1.6 #37 (compliance scope-filter) gates B.6 read paths; W1.6 #43 gates the entire mutating surface of B.3/B.4/B.5/B.7.
>
> **Why W2.B unlocks Enterprise tier**: Production-launch plan §WS-3.1 (`2026-05-21-production-launch-plan.md`) explicitly **descopes** SAML / SCIM / JIT-activate / AccessReview / ComplianceReport / GdprErasure / BreakGlass / CAEP from "lean v1" because they were *stubs / disabled / undelivered*. Master plan (`2026-05-23-iam-prod-ready-master.md`) brings them back into scope **conditioned on** W1 closing the authz holes underneath (W1.5 grant-write, W1.6 spoof-safe & anti-anon). W2.B finishes the job: **scaffolding+501-guard** (SAML wire — full verify in W3.1), real provisioning (SCIM full incl. Basic-auth), real activate (JIT pending → grant), real workflow (break-glass A+B, access-review campaign), real reporting (compliance), real erasure (GDPR right-to-be-forgotten), real notify (CAEP signed SET **egress** push — ingress verify in W3.1), real audit (vector.dev → VictoriaLogs), real identity (SPIFFE SVID for cluster-internal mTLS). Together these convert iam from "control-plane skeleton" to "enterprise-grade IAM" per master DoD line «Все Enterprise-фичи (Блок B): подключены к gateway, работают, имеют newman».

---

## 0. Преамбула — что эта sub-итерация (précis)

W2.B доставляет 10 enterprise-фич Wave 2 Stream B параллельно (внутри потока — последовательно по
§6 рекомендации). Каждая фича — отдельный subtask с собственным acceptance-id, GWT-сценариями,
DB-импактом, тестами; общий acceptance-doc даёт горизонтальный взгляд (cross-feature interactions,
implementation order, global DoD).

| # | Feature | Цель (1 предложение) | Сложность |
|---|---|---|---|
| **B.1** | SAML 2.0 SSO — **scaffolding only** | принять IdP-initiated SAML AuthnResponse на `/saml/sp/acs`, распарсить body, **501-guard до wired verify-callback**; full XML-DSig verify + JIT-provision — **W3.1 #40** | **S** (wire endpoint + 501-guard; verify-callback hook без impl) |
| **B.2** | SCIM 2.0 inbound provisioning — **FULL** | принять `/scim/v2/Users` / `/scim/v2/Groups` CRUD от IdP (Okta/Azure AD/Google Workspace), Basic-auth с per-org secret (**#41 lives here**), идемпотентный provisioning в kacho_iam.users | **L** (RFC 7644 субсет + auth wiring) |
| **B.3** | JIT-activate (approval workflow) | end-to-end: JIT-eligibility row → user-requests-activation → pending-row → approver-approves → grant-emitted → time-bounded → auto-expiry → audit | **M** (uses W1.5 fga_outbox + W1.6 caller-scope; новых таблиц нет) |
| **B.4** | Break-glass full workflow | request → A-approve → B-approve → activate → time-bounded grant → auto-revoke + audit + alert. (W1.6 #43 only закрыл anti-anon на Approve*; W1.5 closed grant-write atomicity — B.4 строит state-machine + auto-revoke worker + DB-level CHECK approver_a ≠ approver_b.) | **M** (state-machine + worker; tables существуют + 1 NEW CHECK migration) |
| **B.5** | AccessReview campaign engine | create campaign over scope → enumerate (subject,resource) review-items → assign reviewers → reviewer Approve/Revoke per item → close campaign → audit | **L** (campaign engine; reviewer pool model; per-item state-machine) |
| **B.6** | ComplianceReport engine | generate report per scope (project/account/org) → query data → render Markdown/JSON → store row → presigned download URL | **M** (report-builder workers + storage; tables существуют) |
| **B.7** | GDPR erasure pipeline | RequestErasure → 30-day grace → CancelErasureRequest possible → if not cancelled → execute erasure (tombstone PII) → audit-emit → CAEP push to subscribers | **M** (state-machine + worker + cancel-token + audit) |
| **B.8** | CAEP push — **egress sign FULL** | подписанные RFC 8417 Security Event Tokens (JWS, RS256) на `caep_subscriber.endpoint_url` по событиям revoke/disable/session-revoke / GDPR-erase; retries + dead-letter; **expose `/jwks.json` для subscriber verify** | **M** (signed JWS + retry-worker + subscriber CRUD via internal listener + public JWKS endpoint) |
| **B.9** | Audit pipeline (VictoriaLogs via vector.dev) | заменить no-op `audit.AuditLogger` стаб на: handler emit → JSON-line stdout → vector.dev sidecar → VictoriaLogs cluster; correlation-id; structured fields; sample queries | **S** (per master plan decision: no Kafka/ClickHouse/HSM/Merkle) |
| **B.10** | SPIRE + Cilium mesh mTLS (handshake & policy) | wire kacho-iam pod as SPIFFE workload (SVID via SPIRE Workload API), Cilium AuthorizationPolicy gates port 9091 to known cluster-internal SVIDs (gateway, vpc, compute, ui-admin) | **S–M** (charts уже есть; W2.B доставляет identity, AP-policy yaml, cert-rotation handler — full SPIRE infra wiring остаётся в W3.3) |

### 0.1 W2.B НЕ включает

- **B.1 НЕ доставляет XML-DSig signature verify** (это **W3.1 #40**). B.1 = endpoint wiring (`/saml/sp/acs` reachable, body parsed, `OnSAMLAssertion` hook-callback registered) + **501-guard** на любую попытку trust unverified assertion. До wired W3.1 verify-callback в production handler **возвращает HTTP 501 Not Implemented** с body `{"error":"saml_verify_not_wired"}`. JIT-provisioning logic (создание user'а из NameID + attributes) — тоже **W3.1**, потому что без verify нельзя trust'ить NameID. B.1 audit emits `iam.saml.acs_received` (без user-creation).
- **B.1 НЕ доставляет `saml_request_state` migration** — она перенесена в **W3.1**, потому что request-state CAS (replay-protection) имеет смысл только когда есть verify; без verify replay-protection даёт ложную уверенность. Migration `0036_saml_request_state.sql` (примерный номер) живёт в W3.1, не в W2.B.
- **B.8 НЕ доставляет ingress-side SET verify** (это **W3.1 #42** — `caep_ingress_handler.go::parseSETBody` сейчас base64-декодит JWT без проверки подписи; fix = fetch external IdP JWKS + verify). B.8 = **egress sign**: наш drainer подписывает наши SETs нашим ключом (`oidc_jwks_keys[purpose='caep_sign']`), POST'им subscriber'у; subscriber verifies через наш `/jwks.json`. **Два разных code path**, без перекрытия.
- **Stream A — gateway / catalog / spec-drift**: B-features registers gRPC handlers; *регистрация в api-gateway REST mux* (REST routes для break-glass / access-review / compliance / gdpr / jit-pending) — задача Stream A (W2.A `sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md`). W2.B оставляет в gen-каталоге proto-stubs и регистрирует на gRPC; REST surface приходит из W2.A.
- **Stream C — API tokens (Блок F)**: ApiTokenService + per-token-scope + JIT-revoke-on-rotation — отдельный subtask (W2.C). W2.B B.3 НЕ путать с API-token-based JIT.
- **Stream D — newman 100% coverage**: добор 13 новых suite (W2.D). W2.B доставляет newman-кейсы per-feature (см. §6.5 каждой), но не trogает other-domain coverage.
- **W3 federation internals — #21 (`/internal/check_relation`), #23 (mfa-fresh enforcement), #25 (session-IP rebind), #26 (CheckRelation context propagation), #40 (SAML verify), #42 (CAEP ingress verify)** — это **не** B.1/B.2/B.8. См. above для #40/#42 разделения. Master plan §W3 row source-of-truth: «#21/#23/#25/#26/#40/#42» — note: #41 NOT in W3 row (lives in W2.B B.2).
- **W3.3 — full SPIRE infrastructure wiring** (spire-server bootstrap, trust-bundle distribution, agent DaemonSet rollout). B.10 здесь = **только** kacho-iam side handshake (Workload API client, SVID rotation policy in app, AuthorizationPolicy yaml). SPIRE control-plane bring-up — W3.3 (`docs/specs/sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md` уже есть).
- **VictoriaLogs cluster bring-up** — assumed already deployed via `kacho-deploy` umbrella (see WS-6.2 in production-launch-plan). B.9 wires *iam* как producer, не stands up logs cluster. **Hard pre-condition: см. §B.9 «Pre-conditions».**
- **PDF report rendering for B.6** — out of scope; B.6 stores Markdown + JSON only. PDF — отдельный ticket пост-v1 (lean MVP per master DoD).
- **MFA-step-up на break-glass request / approve** — gates остаются standard authz (W1.6 anti-anon + per-RPC FGA Check). Step-up-MFA — W3 (#23 mfa-fresh). B.4 здесь — workflow + grant + audit; step-up — отдельный layer.
- **HSM-backed signing для CAEP / audit batches** — out of scope per WS-8.6 (lean-v1 нет HSM). B.8 подписывает SET через soft-keys из `oidc_jwks_keys` (existing table; KAC-127).
- **Bring-your-own-IdP UI** для SAML/SCIM config (TenantOrg admins, метаданные XML upload) — UI работа отдельным KAC; B.1/B.2 принимают config через existing `organizations` table (KAC-127 KAC-119) + per-org config rows (already in `0019_kac127_phase6_org_scim_saml.sql`).

### 0.2 Зависимости (явно, упорядочены)

| Pred | Why W2.B depends | Which B-features hard-blocked |
|---|---|---|
| **W1.4** (MERGED) | B.9 audit + B.7 GDPR erasure + B.4 break-glass + B.5 access-review must record *true* caller in audit (`actor_user_id`), not `user:bootstrap`. Cross-service callers (vpc-triggered erasure of GDPR-affected user) must propagate user. | B.4, B.5, B.7, B.9 |
| **W1.5** (merging) | B.3 ActivateJIT writes grant → `fga_outbox` must drain idempotently to FGA. B.4 Approve B writes break-glass grant → same. B.5 review-Approve may grant (rare) — same. **Без W1.5: grants writes silently lost.** | **HARD-BLOCKER**: B.3, B.4, B.5. Other features (B.1, B.2, B.6, B.7, B.8, B.9, B.10) NOT blocked. |
| **W1.6 #43** | B.3 `ActivateJIT`, B.4 `ApproveBreakGlassA/B` + `DenyBreakGlass`, B.5 `ApproveReviewItem`/`RevokeReviewItem`, B.6 `GenerateAccessReport`, B.7 `CancelErasureRequest` — все попадают в anti-anon allowlist gate. Без W1.6: anonymous может trigger break-glass activate. | B.3, B.4, B.5, B.6, B.7 |
| **W1.6 #35** | B.5 reviewer = principal — already enforced in W1.6; B.5 здесь строит engine *вокруг* этой гарантии. | B.5 |
| **W1.6 #37** | B.6 scope-visibility provider — wired в W1.6 для существующего `GetReport`; B.6 здесь строит **generation** path (тоже scope-gated). | B.6 |
| **W2.A** | B-features register gRPC handlers; *REST* routes appear via W2.A. **W2.B B.4/B.5/B.6/B.7 functional acceptance — через gRPC** (`grpcurl`); REST E2E newman — после W2.A merge. Acceptance §6.5 newman cases на B-features используют gRPC client wrapper (`tests/newman/lib/grpc_client.py`, см. KAC-127 newman infra) если REST route ещё не зарегистрирован к моменту merge. | All B (REST E2E only) |
| **W0.1** | newman matrix gate должен оставаться зелёным; W2.B новые suite добавляются в `tests/newman/run.sh`. | All B |

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** | acceptance gate; impl стартует только после APPROVED. Per-feature subtask проверяет «своё» §6 GWT прошло APPROVED — не весь doc глобально (см. §6 импл-порядок). |
| **Запрет #2** | в коде/комментариях/тестах не упоминается. SAML library reference — **deferred to W3.1** (vendor decision DEC-W3.1-3: `crewjam/saml`); B.1 W2.B scaffolding does not import any SAML library yet, only parses raw XML body. |
| **Запрет #3** | handwritten pgx — для **всех** новых repo-методов (B.3/B.4/B.5/B.6/B.7/B.8); никакого ORM. |
| **Запрет #4** | within-iam-DB only. Cross-service `subject_change_outbox` invalidation на B.7 erasure — через existing pattern (W1.2), не cross-DB FK. |
| **Запрет #5** | applied migrations не редактируем. W2.B вводит **только NEW** migration files: `scim_per_org_auth` (B.2), `compliance_report_download_token` (B.6 — index-only, optional), `breakglass_approver_distinct_check` (B.4 — NEW CHECK constraint), `erasure_cancel_token + erasure_pii_tombstone` (B.7), `subject_change_outbox CHECK extend +'erasure'` (B.7), `caep_subscribers + caep_event_log` (B.8 egress), `caep_jwks_purpose_extend` (B.8 — additively extend existing `oidc_jwks_keys`). **NO** edits to applied migrations 0001–0025. Verify via `git log -- '*migrations/*.sql'` shows only NEW files added (DoD §5 gate). |
| **Запрет #6** | `Internal.*` separation сохраняется: **B.8 CAEP subscriber CRUD** (`RegisterSubscriber`/`UpdateSubscriber`/`DeleteSubscriber`/`ListSubscribers`) — admin-only → internal listener (9091). **B.2 SCIM** — `/scim/v2/...` — vendor-callable (Okta/Azure → external internet) → external TLS listener (443). **B.2 RotateScimBasicAuth** (Internal admin RPC) — internal listener only; **negative test B2-06** verifies invocation on external listener returns `Unimplemented`. **B.1 SAML ACS** — IdP-callable → external TLS listener. **B.8 `/jwks.json`** — public read-only (subscribers verify our SETs) → **external** but **read-only public keys, no secrets**. **B.9 audit-pipeline** — internal (stdout → vector → VL), no API surface. **B.10 mTLS** — gates internal listener only. |
| **Запрет #7** | broker отсутствует. B.8 dead-letter — DB-only (`caep_event_delivery.status='failed'` + `attempts>=N`); B.9 audit — vector.dev → VL, not Kafka. |
| **Запрет #8** | DB-per-service. B-features all in `kacho_iam` schema. |
| **Запрет #9** | мутации остаются async via Operation **с явными исключениями для wire-level protocols**: <br>• **ALL gRPC mutations** (`ActivateJIT`, `ApproveBreakGlassA/B`, `DenyBreakGlass`, `ScheduleAccessReview`, `ApproveReviewItem`, `RevokeReviewItem`, `GenerateAccessReport`, `RequestErasure`, `CancelErasureRequest`, `SubmitBreakGlassReview`, `RotateScimBasicAuth`, B.8 `RegisterSubscriber`/`UpdateSubscriber`/`DeleteSubscriber`) return `*operation.Operation`.<br>• **EXCEPTION 1 — B.1 SAML**: REST endpoint `/saml/sp/acs` returns wire-level HTTP 302 redirect (after verify-callback wired in W3.1) — this is the **SAML protocol contract** (IdP-callable, browser-redirected), Operation envelope не применим.<br>• **EXCEPTION 2 — B.2 SCIM**: REST endpoints `/scim/v2/Users` etc. return RFC 7644 sync HTTP responses (200/201/204 + SCIM resource body) — this is the **SCIM protocol contract** (vendor-callable from Okta/Azure/etc.), Operation envelope не применим. RFC 7644 requires sync semantics.<br>• **EXCEPTION 3 — B.8 CAEP `/jwks.json`**: REST endpoint, GET, returns RFC 7517 JWKS document sync — no mutation, Operation N/A.<br>• **EXCEPTION 4 — B.6 compliance download URL**: REST GET `/iam/v1/compliance_report_download/{token}` returns content bytes sync — no mutation, Operation N/A. |
| **Запрет #10** (within-service refs DB-level) | per §3 per-feature: FK + UNIQUE + CHECK + EXCLUDE + CAS на: B.4 state-machine transitions (CAS `WHERE state = $expected_state`) + **NEW CHECK** `approver_a_user_id != approver_b_user_id` (NEW migration); B.5 review-item decided_by uniqueness (partial UNIQUE on `(campaign_id, item_id) WHERE state='OPEN'`); B.7 erasure idempotency-token UNIQUE; B.8 subscriber dedup UNIQUE on `(account_id, endpoint_url) WHERE enabled = true`. |
| **Запрет #11** (no TODO / no tech-debt) | каждая фича доставляется **полностью** в своём PR — никаких stubs «secret-key rotation = follow-up» / `TODO: validate SCIM filter spec`. Reviewer reject'нёт. Explicit grep gate в DoD: `! git diff main -- '*.go' '*.sql' '*.proto' | grep -E '(TODO|FIXME|XXX)\\(.*KAC'`. **EXCEPTION explicit**: B.1 501-guard на unwired verify-callback — это **boundary** (out-of-scope feature, not tech debt — see §0.1), документировано как «awaiting W3.1 #40»; reviewer accepts boundary marker, NOT TODO stub. |
| **Запрет #12** (test-first STRICT + RED→GREEN) | каждая B.x доставляется как: (a) RED commit (failing integration test + newman case) → (b) GREEN impl commit. PR description shows RED before / GREEN after evidence per feature. |
| **Запрет #13** (test-only PRs не трогают приклад) | not applicable here — W2.B = feature delivery. Но: если B.6 compliance integration выявит баг в W1.6-#37 visibility provider — отдельный fix-PR + KAC, не подшивать в B.6. |
| **«Инфра-чувствительные данные»** | **B.10 SPIRE workload selectors / SVID details / cluster-internal SPIFFE-IDs — НЕ на публичной surface.** SPIFFE-ID живёт в Cilium AuthorizationPolicy yaml + iam config-map (internal); НЕ в gRPC reflection / public API. **B.9 audit events** — full payload в VictoriaLogs (internal observability stack); public exposure только через tenant-scoped query API (B.9.4) с scope-filter (parity с #37 visibility). **B.4 break-glass post-incident-review** — full text в `break_glass_post_incident_reviews` (already in 0024); exposed только cluster-admin role. **B.8 `/jwks.json` exposes ONLY public keys, not private** (per RFC 7517). |
| **CLAUDE.md §«YC-стилистика»** | error-text форма: `"<Resource> %s not found"`, `"Illegal argument <field>"`, `"<field> is immutable after Create"`. B.1 SAML errors: `"SAML verify-callback not wired"` (501) — W2.B; full verify-error texts come in W3.1. B.2 SCIM errors per RFC 7644 (detail.scimType — externally specified, follow RFC not YC). B.8 CAEP per RFC 8417. |
| **Vault discipline** | per-feature §«Vault entries to update» — minimum 1 resource + 1 rpc + 1 edge per feature. KAC-W2.B-N.md trail per subtask. |

---

## 2. Глоссарий

- **SAML** — Security Assertion Markup Language 2.0 (OASIS). XML-based SSO protocol. **AuthnRequest** = SP → IdP login request. **AuthnResponse** = IdP → SP signed assertion. **ACS** = Assertion Consumer Service (SP HTTPS endpoint receiving AuthnResponse). **XML-DSig** = XML Digital Signatures (W3C) — wraps Assertion or whole Response. **W2.B scope**: endpoint wiring + body parse + 501-guard на unverified path. **W3.1 #40 scope**: XML-DSig verify + JIT-provision + request-state CAS.
- **SCIM** — System for Cross-domain Identity Management 2.0 (RFC 7643/7644). REST-based provisioning protocol. **Resource types**: User, Group, Schemas, ResourceTypes, ServiceProviderConfig. **PATCH operations**: `op` = add/replace/remove; `path` per RFC 6902-like.
- **CAEP** — Continuous Access Evaluation Profile (OpenID). Push-based session-state propagation. **SET** = Security Event Token (RFC 8417) — signed JWT carrying one event (e.g. `iam.session.revoked`, `iam.subject.erased`, `iam.credential.revoked`). **Egress (B.8)**: our drainer signs and POSTs SETs to subscribers. **Ingress (W3.1 #42)**: external IdP POSTs SETs to us, we verify their signature.
- **JIT (Just-in-Time)** — eligibility = «user X *may* request role Y on resource Z when needed»; pending = «user requested, awaiting approver»; activated = «approver approved → time-bounded grant exists». Different from JIT-provisioning (B.1/B.2: auto-create user on first SSO/SCIM event — B.1 part в W3.1 #40).
- **Break-glass** — emergency access flow. Two-person approval: requester → approver A → approver B → ACTIVE (time-bounded cluster-admin grant) → auto-revoke at `expires_at` → mandatory post-incident review. **DB invariant** (Запрет #10): approver_a_user_id != approver_b_user_id enforced via CHECK constraint (NEW migration).
- **AccessReview campaign** — periodic governance task. Campaign created over scope (e.g. «review all admins of project:prj_X»). Engine enumerates (subject, role, resource) tuples → review-items, each assigned to reviewer(s). Reviewer Approve = keep binding; Revoke = delete binding (writes to fga_outbox + emits CAEP). Campaign closes at deadline.
- **ComplianceReport** — point-in-time snapshot of access-bindings + roles + grants in a scope, rendered as Markdown/JSON for auditor download. Different from AccessReview (continuous review process vs static snapshot).
- **GDPR erasure** — RFC-equivalent: right-to-be-forgotten flow. Subject (or admin) requests erasure → 30-day grace (per GDPR Art.17) → can cancel within grace → if not cancelled → tombstone PII (set `deleted_at`, null email/name) → audit retained but pseudonymised.
- **JWS (RFC 7515)** — JSON Web Signature. SET (RFC 8417) is a JWS with specific claim set (`events`, `iat`, `iss`, `aud`, `jti`).
- **JWKS (RFC 7517)** — JSON Web Key Set. B.8 exposes our public keys at `/jwks.json` so subscribers can verify our signed SETs.
- **SPIFFE / SPIRE** — SPIFFE = identity standard (URI `spiffe://<trust-domain>/<workload-path>`). SPIRE = reference impl. **Workload API** = SPIRE agent → app socket (`/run/spire/sockets/agent.sock`); app fetches SVID (X.509-SVID for mTLS, JWT-SVID for token-based authn). **SVID rotation** = SPIRE rotates SVID every <ttl/2>; app must re-fetch.
- **Cilium AuthorizationPolicy** — k8s CRD; gates source → destination traffic by SPIFFE-ID. Replaces L4 NetworkPolicy with L7 identity-aware policy.
- **vector.dev** — Rust-based log/event-shipping agent; sidecar pattern reads stdout/file → transforms (parse JSON, enrich) → ships to VL/VM/S3.
- **VictoriaLogs (VL)** — log storage system; LogsQL query language; column-store; aligned with VictoriaMetrics for observability stack uniformity.

---

## 3. Data model — overview (per-feature detail в §6.X)

**Migration numbers — NOT hard-coded**. Per `docs/specs/KAC-170-acceptance-review-report.md` §«Migration number coordination»: last applied = `0025_nlb_operator_target_manager_roles.sql`; real numbers assigned at impl-start (PR merge order determines actual sequence). Acceptance docs refer to migrations by **symbolic filename** (`00XX_w2b_<topic>.sql`); reviewer + reviewer-coordinator update to concrete `00NN_` at impl-start commit.

**Sketch sequence** (non-binding, per KAC-170 report §«Migration number coordination»):

```
W2.A merges first: 0026 (service_accounts project_scoped)
W2.C: 0027 (subject_change_outbox CHECK extend +api_token_revoke), 0028 (api_tokens)
W2.B (this doc — Option Y; saml_request_state moved to W3.1):
  0029 (scim_per_org_auth — B.2 #41)
  0030 (compliance_report_download_token — B.6 — optional index-only; may collapse)
  0031 (cluster_break_glass_grants approver_a != approver_b CHECK — B.4)
  0032 (erasure_cancel_token + users.pii_tombstoned_at — B.7)
  0033 (subject_change_outbox CHECK extend +'erasure' — B.7)
  0034 (caep_subscribers extend — B.8 egress)
  0035 (caep_event_log retention metadata — B.8)
  0036 (caep_jwks_purpose_extend — B.8 — additive on oidc_jwks_keys)
W3.1:
  0037 (saml_request_state — moved from W2.B per scope split Option Y)
  0038 (iam_trusted_idp_jwks_cache — #42 ingress JWKS cache)
W3.3: no migrations (cilium policies = YAML)
```

| Feature | Migration impact (W2.B scope) | Existing tables used |
|---|---|---|
| **B.1 SAML (scaffolding)** | **NO new migration in W2.B**. `saml_request_state` migration deferred to W3.1 (meaningful only with verify). | `organizations` (idp_metadata_xml, sp_entity_id — read-only); `saml_sessions` (already in `0019`) — read-only at this stage. |
| **B.2 SCIM** | NEW: `00XX_w2b_scim_per_org_auth.sql` — adds `scim_basic_auth_secret_hash` (bcrypt hashed) + `scim_basic_auth_generated_at timestamptz` on existing `organizations` table. | `scim_user_mappings`, `scim_groups`, `scim_group_members` (all in `0019`). |
| **B.3 JIT-activate** | **No new migration**. Uses `access_bindings_jit_eligibility` (0012) + `access_bindings_jit_pending` (0022) + `fga_outbox` (0002). | `access_bindings_jit_eligibility`, `access_bindings_jit_pending`, `access_bindings`, `fga_outbox`, `audit_outbox`. |
| **B.4 Break-glass workflow** | NEW: `00XX_w2b_breakglass_approver_distinct_check.sql` — **adds CHECK constraint** `CHECK (approver_a_user_id IS NULL OR approver_b_user_id IS NULL OR approver_a_user_id != approver_b_user_id)` on `cluster_break_glass_grants`. Per Запрет #10 (DB-level enforcement of invariants — not software). | `cluster_break_glass_grants`, `cluster_admin_grants`, `break_glass_post_incident_reviews`, `fga_outbox`, `audit_outbox`. |
| **B.5 AccessReview campaign** | **No new migration**. Engine on existing `access_review_campaigns` (0024) + `access_reviews` + `access_review_items` (0014). Workers + reviewer-pool logic in Go. | `access_review_campaigns`, `access_reviews`, `access_review_items`, `access_bindings`, `fga_outbox` (for Revoke→deletion). |
| **B.6 ComplianceReport engine** | **No new migration** (download URL HMAC reuses existing `oidc_jwks_keys`). | `compliance_reports`, `access_bindings`, `roles`, `cluster_admin_grants`, `oidc_jwks_keys`. |
| **B.7 GDPR erasure pipeline** | NEW: `00XX_w2b_gdpr_cancel_token.sql` — adds `cancel_token_hash text` column on `gdpr_erasure_requests` + partial UNIQUE for active pending requests per subject + adds `pii_tombstoned_at timestamptz` column on `users`. NEW: `00XX_w2b_subject_change_outbox_check_extend.sql` — ALTER existing CHECK to allow `change_type='erasure'`. | `gdpr_erasure_requests` (0020), `gdpr_erasure_audit` (0020), `users`, `audit_outbox`, `subject_change_outbox` (W1.2 — for cache invalidation), `caep_outbox` (for B.8 push). |
| **B.8 CAEP push (egress)** | NEW: `00XX_w2b_caep_jwks_purpose_extend.sql` — **additively** extends existing `oidc_jwks_keys` with `purpose text NOT NULL DEFAULT 'oidc_id_token'` + index; existing rows backfilled to default; new B.8 signing keys inserted with `purpose='caep_sign'`. NEW: `00XX_w2b_caep_subscribers_extend.sql` — adds `signing_jwk_kid text` FK referencing `oidc_jwks_keys(kid)` (per-subscriber overlay; NULL → cluster-default) + partial UNIQUE on `(account_id, endpoint_url) WHERE enabled=true`. | `caep_subscribers` (0013), `caep_outbox` (0013), `caep_event_delivery` (0014), `oidc_jwks_keys` (0014 — extended additively). |
| **B.9 Audit pipeline** | **No new migration**. Emits JSON lines to stdout — read by vector sidecar — shipped to VL. `audit_outbox` (0013) remains for durable in-DB audit + optional replay. | `audit_outbox` for durable backup only. |
| **B.10 SPIRE+Cilium** | **No new migration**. App-side SVID handling. Helm value changes in kacho-deploy. | none. |

**Total NEW migration files in W2.B**: 6 (B.2: 1; B.4: 1; B.7: 2; B.8: 2). Each ≤80 lines, scoped, FK/UNIQUE/CHECK at DB level. **Numbers assigned at impl-start** per coordination meta-doc.

---

## 4. Cross-feature interactions (critical)

| Producer | Consumer | Interaction | Where wired |
|---|---|---|---|
| **B.3 ActivateJIT** | **B.9 audit** | emits `iam.jit.activated` event (subject_id, role_id, resource_id, expires_at, actor=approver) | usecase `jit_pending_service.go::Activate` → `audit.Emit(...)` |
| **B.3 expiry worker** | **B.8 CAEP** | on expiry → `caep_outbox` row `iam.credential.revoked` (per RFC 8417 standard event) → drainer → subscribers | `phase7_workers.go` (existing — extend per W1.5 §1.5 finding #51 already fixed) |
| **B.4 ApproveBreakGlassB → ACTIVE** | **B.9 audit** | `iam.breakglass.activated` (subject, approvers[2], cluster_id, expires_at, request_justification) | usecase `phase7_break_glass_service.go::ApproveB` → `audit.Emit(...)` |
| **B.4 auto-revoke worker** | **B.8 CAEP** | on `expires_at` reached → revoke grant + `caep_outbox` `iam.credential.revoked` | **NEW** `breakglass_expiry_worker.go` (registered in `cmd/kacho-iam/main.go` alongside existing JIT `phase7_workers.go` JIT-expiry worker — both workers coexist, separate goroutines) |
| **B.4 ACTIVE / auto-revoke** | **B.9 audit + alert** | structured event + AlertManager firing (`breakglass_active{}`) | vector.dev parse → VL → AM rule (B.9 + observability) |
| **B.5 RevokeReviewItem** | **fga_outbox** | binding deletion → fga_outbox revoke row → drainer applies | usecase `phase7_access_review_service.go::RevokeItem` (W1.5-style emit) |
| **B.5 RevokeReviewItem** | **B.8 CAEP** | `iam.session.revoked` per subject (after fga revoke confirmed) | shared `phase7_workers.go::onRevoke` hook |
| **B.6 GenerateAccessReport** | **B.9 audit** | `iam.report.generated` event (scope, principal, report_id) | usecase `compliance_report_service.go::Generate` |
| **B.7 erasure execute** | **B.8 CAEP** | `iam.subject.erased` (RFC 8417) → all subscribers for that subject's account | erasure worker → caep_outbox |
| **B.7 erasure execute** | **subject_change_outbox** (W1.2) | gateway cache invalidation per principal (`change_type='erasure'` — extended via NEW migration) | erasure worker (parity with existing JIT-erasure path, finding #51 reuse) |
| **B.7 erasure execute** | **B.9 audit** | `iam.subject.erasure_completed` — pseudonymised actor (per GDPR: don't audit subject themselves identifying) | erasure worker |
| **B.7 erasure during active B.4 break-glass** | **B.4 grant** | erasure executes **regardless** of active break-glass for that subject — legal compliance trumps active emergency access (OQ-W2.B-15 resolution). Break-glass grant auto-revokes as side-effect: subject_change_outbox + caep cascade trigger grant cleanup downstream. New GWT: **W2.B-B7-06**. | erasure worker continues without checking break-glass state |
| **B.8 SET signing** | **oidc_jwks_keys** | per-subscriber signing-kid OR cluster-default (`purpose='caep_sign'`); verify JWKS endpoint exposes pub-key | `caep_drainer.go::signSET` |
| **B.8 `/jwks.json`** | **external subscribers** | public read-only RFC 7517 JWKS document; subscribers verify our SETs against keys here. Exposes ONLY `purpose='caep_sign'` keys (not oidc_id_token signing keys — separation). | NEW REST handler `internal/apps/kacho/api/caep/jwks_handler.go` on external listener (read-only public) |
| **B.10 SPIFFE-ID** | **B.8 outbound webhook** | NO — B.8 webhooks are external (vendor-callable inbound to subscribers, our egress); SPIFFE — internal-only listener gating. Document explicitly **no overlap**. | — |
| **B.10 Cilium AP** | **all internal listeners** | gate port 9091 by allowed SPIFFE-IDs: gateway, vpc, compute, ui-admin, audit-reader | `kacho-deploy` helm value `cilium.authorizationPolicies.iam.allowedSpiffeIds` |
| **B.1 SAML scaffolding** | **B.9 audit** | `iam.saml.acs_received` event (org_id, body_size_bytes) — **without** subject_user_id since verify not wired (W3.1) | `saml/sp_handler.go::ServeHTTP` → `audit.Emit` |
| **B.2 SCIM provision** | **B.9 audit** | `iam.user.provisioned_scim` (user_id, account_id, idp_id, provision_source) | `scim/handlers.go::createUser` |

> **Implication for impl-order** (§6): B.9 audit pipeline лучше идти **first** (или хотя бы вместе с B.3) — иначе все остальные B-features emit'ят в no-op и acceptance audit-shape checks падают. См. §6.

---

## 5. Test discipline (запрет #12) — RED first + Запреты cross-check

Per-feature PR обязан содержать **в указанном порядке**:

1. **RED phase commit** (testing-only): per-feature integration test + newman case written, committed. CI red (compile-fail OR assertion-fail).
2. **GREEN phase commits**: per-feature impl driving each RED test → GREEN. PR description shows RED before / GREEN after evidence (test name + before-output + after-output).
3. **Integration tests** use testcontainers Postgres + migrations 0001–latest applied + fake/real OpenFGAClient (existing repo helpers) + bufconn gRPC server.
4. **Newman cases** added to per-domain `tests/newman/cases/iam-<feature>.py`:
    - `iam-saml.py` (B.1; NEW — limited scope per scaffolding only)
    - `iam-scim.py` (B.2; NEW)
    - `iam-jit-activate.py` (B.3; existing `iam-jit-pending.py` extended)
    - `iam-breakglass.py` (B.4; NEW)
    - `iam-access-review-campaign.py` (B.5; NEW)
    - `iam-compliance-report.py` (B.6; existing extended)
    - `iam-gdpr.py` (B.7; existing extended)
    - `iam-caep.py` (B.8; NEW)
    - `iam-audit.py` (B.9; NEW — read-side assertion against VL)
    - B.10 — newman not appropriate (mTLS infra); covered by `make e2e` smoke instead
5. **Each feature**: minimum 2 positive + 2 negative + 1 edge GWT scenario (per §6.X).
6. **No TODO/FIXME/skip in diff** (workspace §11/§13).
7. **No yandex** (§2).

### §5.1 Запреты cross-check table (Запрет → where honored)

Per acceptance-reviewer Minor #7 (explicit Запреты mapping, не повтор §1):

| Запрет | Where honored in W2.B | Verification gate |
|---|---|---|
| **#1** acceptance before code | This doc APPROVED → per-feature subtask APPROVED in §6.X → branch created | `acceptance-reviewer` two-stage approval |
| **#2** no "yandex" | All B.x code, comments, tests, env-names, docs | `grep -ri yandex project/kacho-iam/` returns 0 in W2.B diff |
| **#3** no ORM | All new repos handwritten pgx + sqlc | `grep -ri "gorm\|ent\|bun" project/kacho-iam/` returns 0 |
| **#4** no cross-service cascade | B.7 cross-service invalidation via subject_change_outbox (W1.2 pattern), NOT cross-DB FK | code review |
| **#5** no applied migration edits | Only NEW migration files (see §3 table) | `git log -- 'project/kacho-iam/internal/migrations/0001*.sql' ... '0025*.sql'` shows NO new commits in W2.B PRs |
| **#6** Internal vs external | B.2 RotateScimBasicAuth, B.8 RegisterSubscriber etc. → internal listener (9091); SCIM REST + SAML ACS + `/jwks.json` → external (443) | Negative test B2-06 (RotateScimBasicAuth on external → Unimplemented); explicit listener-routing in `cmd/kacho-iam/main.go` |
| **#7** no broker | B.8 dead-letter = DB; B.9 audit = vector→VL (not Kafka) | code review |
| **#8** DB-per-service | All B.x in `kacho_iam` schema | migrations |
| **#9** Operation envelope w/ explicit REST exceptions | All gRPC mutations → Operation; B.1 SAML / B.2 SCIM / B.8 JWKS / B.6 download — REST sync per protocol (see §1 Запрет #9 row) | proto file inspection |
| **#10** DB-level invariants | B.4 CHECK approver_a ≠ approver_b (NEW migration); state-CAS on B.3/B.4/B.5/B.7; partial UNIQUE on B.7/B.8 | integration tests with concurrent goroutines |
| **#11** no TODO/FIXME | Explicit DoD grep: `! git diff main -- '*.go' '*.sql' '*.proto' \| grep -E '(TODO\|FIXME\|XXX)\(.*KAC'`; B.1 501-guard is **boundary** not TODO | per-feature DoD gate |
| **#12** test-first RED→GREEN | Per-feature PR description shows RED commit hash + GREEN commit hash with output diffs | PR review |
| **#13** test-only PRs не трогают приклад | If bug found mid-impl → separate fix-PR + KAC | code review |

---

## 6. Per-feature acceptance (B.1 → B.10)

Format per feature:
- **Scope** (IN / OUT)
- **Pre-conditions / dependencies**
- **Repos touched**
- **DB migrations**
- **gRPC API surface** (extended vs new RPC; proto paths)
- **GWT scenarios** (≥2 positive + ≥2 negative + ≥1 edge)
- **B.X.5 Integration tests + Newman cases** (unique subsection name per feature)
- **Vault entries to update**
- **DoD checklist**

---

### B.1 — SAML 2.0 SSO — **scaffolding only** (W2.B); full verify в W3.1 #40

#### Scope (IN / OUT)

- **IN (W2.B)**:
  - REST endpoint `/saml/sp/acs` registered, listens on external TLS listener (443).
  - Body parsing: accept `application/x-www-form-urlencoded` with `SAMLResponse` field, base64-decode + XML-parse syntactic validity (raw `xml.Decoder` check; reject malformed XML with 400).
  - `OnSAMLAssertion` callback hook interface defined; **production handler returns HTTP 501** `{"error":"saml_verify_not_wired","wave":"W3.1"}` until W3.1 wires the verify-callback impl.
  - `/saml/sp/metadata?org=<orgId>` already exists (KAC-127); B.1 verifies SP-entityID + ACS URL correctness per `organizations.sp_entity_id`. **No changes** to this endpoint in W2.B.
  - `/saml/sp/init?org=<orgId>` — **W2.B does NOT implement**; returns 501. Belongs in W3.1 (SP-initiated flow needs request-state CAS which depends on `saml_request_state` table — also moved to W3.1).
  - Audit emit: every ACS POST emits `iam.saml.acs_received` (org_id, body_size_bytes, peer_ip) — **without** subject_user_id since verify не wired.
- **OUT (deferred to W3.1)**:
  - XML-DSig signature verification against `organizations.idp_metadata_xml` IdP cert.
  - JIT-provision user from `subject.NameID` + `AttributeStatement`.
  - Kratos session minting.
  - 302 redirect to UI dashboard.
  - Request-state CAS for InResponseTo replay-protection (`saml_request_state` table — W3.1 migration).
  - SP-initiated `/saml/sp/init` flow.
  - SAML library decision (`crewjam/saml`) — referenced in W3.1 DEC-W3.1-3; W2.B doesn't import any SAML lib (only raw XML body parse).
- **OUT (post-v1)**:
  - SLO (single-logout) — existing `back_channel_logout_service.proto` handles non-SAML logout. SLO endpoint stays `Unimplemented`.
  - per-IdP custom NameID format mapping UI — IdP metadata uploaded once via admin (existing manual flow).
  - SAML-initiated logout request (`<LogoutRequest>` from IdP).

#### Pre-conditions / dependencies

- W1.6 #43 anti-anon allowlist: `/saml/sp/acs` is REST not gRPC; explicitly added to **whitelistRESTPath** (anonymous OK on ACS since wire-protocol is IdP-callable; full verify in W3.1 will validate before any trust granted).
- KAC-127 phase6 `0019_kac127_phase6_org_scim_saml.sql` — `organizations` + `saml_sessions` tables exist (read-only in W2.B).

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/apps/kacho/api/saml/sp_handler.go` (extend — body parse + 501-guard + audit emit), `internal/apps/kacho/api/saml/verify_callback.go` (NEW — interface definition; production returns 501) |
| `kacho-proto` | NONE (REST only) |
| `kacho-deploy` | helm value `iam.saml.acs_enabled=true` (default false; flip per-env). Note: `iam.saml.verify_enabled=false` always in W2.B (becomes true in W3.1). |

#### DB migrations

- **NONE in W2.B**. (`saml_request_state` deferred to W3.1 per scope split Option Y.)

#### gRPC API surface

- **No new gRPC**. SAML is REST: `/saml/sp/acs` (extended in W2.B), `/saml/sp/init` (501 in W2.B), `/saml/sp/metadata` (unchanged).

#### GWT scenarios (W2.B scope — scaffolding only)

##### W2.B-B1-01 (positive) — endpoint reachable, body parsed, audit emitted, returns 501

**Given** Organization `org_acme` configured; helm `iam.saml.acs_enabled=true`
**And** Test IdP sends well-formed (syntactically valid XML) SAML AuthnResponse body via POST

**When** POST `/saml/sp/acs?org=org_acme` with `SAMLResponse=<base64-encoded-valid-XML>` form field

**Then** HTTP 501 Not Implemented
**And** Response body JSON `{"error":"saml_verify_not_wired","wave":"W3.1"}`
**And** **NO** user created, **NO** session minted, **NO** redirect issued
**And** `audit_outbox` row `iam.saml.acs_received` with fields: `org_id=org_acme`, `body_size_bytes=<size>`, `peer_ip=<src>` — **no** `subject_user_id` (verify not wired)

##### W2.B-B1-02 (positive) — raw assertion-id captured in audit for forensics

**Given** SAML body contains `<saml2:Assertion ID="_abc123def...">` element (Assertion ID is in plaintext XML, no verify needed to extract)

**When** POST to ACS

**Then** HTTP 501 (as B1-01)
**And** `audit_outbox` row `iam.saml.acs_received` additionally contains `assertion_id="_abc123def..."` (parsed from raw XML, capability tested even without signature verify — useful for forensic correlation in W3.1)

##### W2.B-B1-03 (negative) — malformed XML body → 400

**Given** SAML body = `SAMLResponse=not-valid-xml-just-garbage`

**When** POST to ACS

**Then** HTTP 400 Bad Request with `{"error":"saml_response_parse_failed"}`
**And** `audit_outbox` row `iam.saml.parse_failed` (org_id, peer_ip, reason)

##### W2.B-B1-04 (negative) — missing `SAMLResponse` form field → 400

**When** POST to ACS without `SAMLResponse` field

**Then** HTTP 400 with `{"error":"saml_response_missing"}`
**And** audit row emitted

##### W2.B-B1-05 (edge) — non-existent org → 404

**When** POST `/saml/sp/acs?org=nonexistent_org_id` with valid SAML body

**Then** HTTP 404 with `{"error":"organization_not_found"}`
**And** audit row `iam.saml.acs_received` with `org_id=nonexistent_org_id` and `org_resolve_failed=true`

##### W2.B-B1-06 (edge) — SP-initiated `/saml/sp/init` returns 501

**When** GET `/saml/sp/init?org=org_acme`

**Then** HTTP 501 `{"error":"sp_init_not_wired","wave":"W3.1"}` (request-state CAS belongs to W3.1)

> **NOTE**: GWT scenarios B1-03 (BadSignature), B1-04 (ExpiredAssertion), B1-05 (Replay) from v1 are **DROPPED** in v2 per scope split Option Y — these test actual signature verify (deferred to W3.1 #40). Replaced by scaffolding-scope scenarios above (B1-01..B1-06 renumbered).

#### B.1.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B1-IT-01** | `Test_SAML_ACS_Reachable_Returns501_AuditEmitted` | integration (testcontainers) | W2.B-B1-01 |
| **W2.B-B1-IT-02** | `Test_SAML_ACS_AssertionIdCapturedInAudit` | integration | W2.B-B1-02 |
| **W2.B-B1-IT-03** | `Test_SAML_ACS_MalformedXml_Rejects400` | integration | W2.B-B1-03 |
| **W2.B-B1-IT-04** | `Test_SAML_ACS_MissingField_Rejects400` | integration | W2.B-B1-04 |
| **W2.B-B1-IT-05** | `Test_SAML_ACS_OrgNotFound_Returns404` | integration | W2.B-B1-05 |
| **W2.B-B1-IT-06** | `Test_SAML_Init_NotImplemented` | integration | W2.B-B1-06 |
| **W2.B-B1-NM-01** | `SAML-ACS-RETURNS-501-W2B-SCAFFOLDING` (postman: post valid syntactic SAML XML; verify 501 + audit row) | newman | W2.B-B1-01 |
| **W2.B-B1-NM-02** | `SAML-ACS-MALFORMED-REJECTS-400` | newman | W2.B-B1-03 |

#### Vault entries to update

- `resources/iam-organization.md` — note IdP metadata field semantics; reference per-org SAML config (read-only in W2.B)
- `rpc/iam-saml-rest.md` — NEW; document REST endpoints (`/saml/sp/init` → 501, `/saml/sp/acs` → 501 with body parse, `/saml/sp/metadata` unchanged); mark W2.B = scaffolding, link to W3.1 acceptance doc for full verify
- `edges/iam-saml-acs-to-audit.md` — NEW; ACS body parse → audit emit pattern (W2.B); link to forthcoming `iam-saml-to-jit-provision.md` (W3.1)
- `packages/iam-apps-kacho-api-saml.md` — NEW; sp_handler + verify_callback hook interface
- `KAC/KAC-W2.B-1.md` — trail

#### DoD

- [ ] `acceptance-reviewer` ✅ APPROVED B.1 section
- [ ] Branch `KAC-W2.B-1-saml-acs-scaffolding` created
- [ ] RED commit: §B.1.5 integration tests + newman cases written, CI red
- [ ] GREEN commits: handler body-parse + 501-guard + audit emit, `OnSAMLAssertion` hook interface defined, helm flag wired
- [ ] All 6 §B.1 GWT scenarios GREEN in integration
- [ ] 2 newman cases GREEN
- [ ] No TODO/FIXME in diff (501-guard is **boundary** not TODO — see §1 Запрет #11)
- [ ] vault notes updated (5 entries listed above)
- [ ] PR merged
- [ ] `make e2e` smoke: ACS endpoint reachable and returns 501 on kind
- [ ] **W3.1 #40 cross-reference**: PR description explicitly links to `sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md` §40 (SAML verify) as the W3.1 fix that turns 501 → 302

---

### B.2 — SCIM 2.0 inbound provisioning — **FULL** (incl. #41 per-org Basic-auth)

#### Scope (IN / OUT)

- **IN**: REST endpoints per existing `internal/apps/kacho/api/scim/handlers.go`:
  - `GET/POST /scim/v2/Users`, `GET/PUT/PATCH/DELETE /scim/v2/Users/{id}`
  - `GET/POST /scim/v2/Groups`, `GET/PUT/PATCH/DELETE /scim/v2/Groups/{id}`
  - `GET /scim/v2/Schemas`, `/scim/v2/ResourceTypes`, `/scim/v2/ServiceProviderConfig`
- **IN — #41 per-org Basic-auth (lives here per master plan §W3 row exclusion)**: each Organization gets a generated SCIM password (one-time copy at IdP-config-time); stored bcrypt-hashed in `organizations.scim_basic_auth_secret_hash` (NEW column via NEW migration). Bearer-token auth path (existing) stays as alternative.
- **IN**: PATCH ops per RFC 6902-style: `op` = add/replace/remove on `active`, `name.givenName`, `name.familyName`, `emails[primary=true].value`, `groups`.
- **IN**: idempotent provisioning — POST /Users with `externalId = "<idp-subject-id>"` → lookup `scim_user_mappings` first → create if missing; PUT replaces.
- **IN — RotateScimBasicAuth (Internal admin RPC)**: NEW `InternalOrganizationService.RotateScimBasicAuth(RotateScimRequest) returns (Operation)` — returns plaintext secret in `Operation.response` ONCE (subsequent reads = redacted `"<redacted>"`, parity with W1.6 #11 sa-key redaction pattern). **Internal listener only** (port 9091).
- **OUT**: Bulk operations (`/scim/v2/Bulk`) — out of scope (RFC optional; IdP rarely uses).
- **OUT**: ETag-based conditional updates — out of scope; SCIM PATCH/PUT idempotent enough for v1.
- **OUT**: Custom SCIM extension schemas — out of scope; standard `urn:ietf:params:scim:schemas:core:2.0:User` + Group only.

#### Pre-conditions / dependencies

- W1.6 — interceptors don't apply to REST `/scim/v2/...` (HTTP layer), but anti-anon principle: SCIM endpoints MUST require Basic-auth (per-org) OR Bearer-token (existing); anonymous → 401.
- Existing `scim/auth.go` + `scim/handlers.go` infrastructure (mostly implemented per file listing; missing: per-org Basic-auth wiring per finding #41).
- W1.6 #11 redaction pattern (sa-key) — for RotateScimBasicAuth one-shot secret return.

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/apps/kacho/api/scim/auth.go` (extend Basic-auth — per-org secret lookup), `internal/apps/kacho/api/scim/handlers.go` (idempotency check on POST), `internal/apps/kacho/api/scim/provisioning.go` (dedup logic), `internal/apps/kacho/api/internal_iam/scim_secret_handler.go` (NEW — RotateScimBasicAuth), `cmd/kacho-iam/phase6_listeners.go` (wire BasicAuthOrgID from config — finding #41), `internal/migrations/00XX_w2b_scim_per_org_auth.sql` (NEW; number assigned at impl-start), `internal/repo/kacho/pg/scim_org_secret_repo.go` (NEW) |
| `kacho-proto` | NEW file `kacho-proto/proto/kacho/cloud/iam/v1/internal_organization_service.proto` with `InternalOrganizationService.RotateScimBasicAuth` |
| `kacho-deploy` | helm `iam.scim.basic_auth_enabled=true` |

#### DB migrations

- `00XX_w2b_scim_per_org_auth.sql`:
  ```sql
  ALTER TABLE kacho_iam.organizations
      ADD COLUMN scim_basic_auth_secret_hash text,           -- bcrypt; nullable until generated
      ADD COLUMN scim_basic_auth_generated_at timestamptz;   -- audit when secret was generated
  CREATE INDEX organizations_scim_auth_idx
      ON kacho_iam.organizations (id)
      WHERE scim_basic_auth_secret_hash IS NOT NULL;
  ```

#### gRPC API surface

- NEW (Internal admin RPC, **internal listener only**, see §Запрет 6):
  - `InternalOrganizationService.RotateScimBasicAuth(RotateScimRequest) returns (Operation)` — returns plaintext secret in `Operation.response` (one-shot; subsequent reads = redacted, parity with W1.6 #11 sa-key redaction pattern).
  - Path: `kacho-proto/proto/kacho/cloud/iam/v1/internal_organization_service.proto` (NEW file).

#### GWT scenarios

##### W2.B-B2-01 (positive) — Okta POSTs new user → provisioned

**Given** Organization `org_okta_tenant` exists; SCIM secret rotated; IdP configured with that secret
**And** No user with email `bob@okta.com` exists locally

**When** IdP POSTs `{schemas:[...:User], externalId:"okta_user_42", userName:"bob@okta.com", emails:[{primary:true,value:"bob@okta.com"}], active:true}` to `/scim/v2/Users` with Basic-auth (`org_okta_tenant:secret`)

**Then** 201 Created with SCIM resource body (id = new user id, meta.created, meta.location)
**And** new row in `users` (email=bob@okta.com)
**And** new row in `scim_user_mappings` (external_id=okta_user_42, local_user_id=<new>, org_id=org_okta_tenant)
**And** `audit_outbox` row `iam.user.provisioned_scim`

##### W2.B-B2-02 (positive) — repeat POST same externalId → 200 OK with existing user (idempotent)

**When** IdP POSTs second time with **same** externalId

**Then** 200 OK (NOT 201) with existing user resource; **no** new rows; **no** duplicate audit-emit

##### W2.B-B2-03 (negative) — wrong Basic-auth → 401

**When** IdP POSTs with wrong password

**Then** 401 Unauthorized; SCIM error body `{schemas:["urn:ietf:params:scim:api:messages:2.0:Error"], detail:"Invalid credentials", status:"401"}`

##### W2.B-B2-04 (negative) — anonymous POST → 401

**When** request without auth header → 401, same SCIM error body

##### W2.B-B2-05 (edge) — DELETE /Users/{id} → soft-delete (deactivate), not hard-delete

**Given** user `usr_alice` provisioned via SCIM
**When** IdP DELETE `/scim/v2/Users/usr_alice`

**Then** 204 No Content
**And** `users.deleted_at` set (NOT row removed) — soft-delete per `0009_user_per_account_invite_kac125.sql` pattern
**And** `users.active = false`
**And** `audit_outbox` row `iam.user.deactivated_scim`
**And** subsequent `GET /scim/v2/Users/usr_alice` → returns user with `active: false`

##### W2.B-B2-06 (negative — parity with W1.6 Запрет #6 pattern) — RotateScimBasicAuth on external listener returns Unimplemented

**Given** kacho-iam running with external (443) and internal (9091) listeners; `InternalOrganizationService` registered on internal only

**When** Client invokes `InternalOrganizationService/RotateScimBasicAuth` via external listener (443) gRPC

**Then** `codes.Unimplemented` («method not registered on external listener») — listener-routing config in `cmd/kacho-iam/main.go` proves §Запрет #6 separation enforced
**And** Same RPC via internal listener (9091) returns Operation normally (companion positive case)

##### W2.B-B2-07 (edge — sensitive-data redaction parity W1.6 #11) — Operation.Get returns redacted secret after first read

**Given** RotateScimBasicAuth executed; Operation `op_rotate_t27` resolved with `response.scim_basic_auth_secret=<plaintext-X>`
**And** Client called `Operation.Get(op_rotate_t27)` once and consumed plaintext

**When** Client calls `Operation.Get(op_rotate_t27)` second time

**Then** Operation returned but `response.scim_basic_auth_secret = "<redacted>"` (string literal `<redacted>`); plaintext not retrievable after first read (parity with W1.6 #11 sa-key one-shot pattern)
**And** `audit_outbox` row `iam.scim_secret.redacted_read` for forensic visibility

#### B.2.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B2-IT-01** | `Test_SCIM_PostUser_HappyProvisions` | integration | B2-01 |
| **W2.B-B2-IT-02** | `Test_SCIM_PostUser_Idempotent` | integration | B2-02 |
| **W2.B-B2-IT-03** | `Test_SCIM_BasicAuth_WrongSecret_Rejects` | integration | B2-03 |
| **W2.B-B2-IT-04** | `Test_SCIM_NoAuth_Rejects` | integration | B2-04 |
| **W2.B-B2-IT-05** | `Test_SCIM_DeleteUser_SoftDeletes` | integration | B2-05 |
| **W2.B-B2-IT-06** | `Test_RotateScimBasicAuth_ExternalListener_Unimplemented` | integration (two listeners) | B2-06 |
| **W2.B-B2-IT-07** | `Test_RotateScimBasicAuth_Operation_Redacted_SecondRead` | integration | B2-07 |
| **W2.B-B2-NM-01** | `SCIM-USER-PROVISION-HAPPY` | newman | B2-01 |
| **W2.B-B2-NM-02** | `SCIM-USER-PROVISION-IDEMPOTENT` | newman | B2-02 |
| **W2.B-B2-NM-03** | `SCIM-AUTH-WRONG-SECRET-DENY` | newman | B2-03 |
| **W2.B-B2-NM-04** | `SCIM-ROTATE-SECRET-REDACTED-2ND-READ` | newman (gRPC client wrapper) | B2-07 |

#### Vault entries to update

- `resources/iam-organization.md` — Basic-auth secret field + rotation policy
- `resources/iam-scim-user-mapping.md` — NEW; dedup key per externalId
- `rpc/iam-scim-rest.md` — NEW; full endpoint catalogue
- `rpc/iam-internal-organization-service.md` — NEW; RotateScimBasicAuth one-shot semantics
- `edges/iam-scim-to-jit-provision.md` — NEW
- `packages/iam-apps-kacho-api-scim.md` — NEW
- `KAC/KAC-W2.B-2.md` — trail

#### DoD

- [ ] APPROVED B.2 section
- [ ] Branch `KAC-W2.B-2-scim-auth`
- [ ] RED commits per §B.2.5 above
- [ ] GREEN: Basic-auth per-org wiring, idempotency dedup, RotateScimBasicAuth internal RPC, redaction parity W1.6 #11
- [ ] 7 scenarios GREEN; 4 newman cases GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (7 entries)
- [ ] PR merged

---

### B.3 — JIT-activate (approval workflow end-to-end)

#### Scope (IN / OUT)

- **IN**: full end-to-end JIT flow:
  1. user has **eligibility** row in `access_bindings_jit_eligibility` (created by admin via existing JITEligibilityService.Create — W1.6 #39 fixes CreatedBy)
  2. user **requests activation** → creates `access_bindings_jit_pending` row (state=AWAITING_APPROVAL) — existing RequestJIT method
  3. approver calls `ApproveJITActivation(pending_id, justification)` → state PENDING → ACTIVE; creates `access_bindings` row (subject=user, role=eligibility.role, resource=eligibility.resource, expires_at=now()+eligibility.ttl_seconds); emits `fga_outbox` grant row (W1.5 path); emits `audit_outbox` event
  4. drainer (W1.1) applies grant to FGA → Check returns ALLOW
  5. **expiry worker** (extends existing `phase7_workers.go`): scans expired `access_bindings.expires_at < now()` originating from JIT → emits `fga_outbox` revoke row + `caep_outbox` `iam.credential.revoked` (per W1.5 finding #51 already fixed)
- **IN**: `DenyJITActivation(pending_id, reason)` → state DENIED; audit-emit only; no grant.
- **OUT**: notification (email/Slack) on Approve/Deny — UI ticket; backend just emits audit.
- **OUT**: bulk-approve UI — UI ticket.
- **OUT**: nested approval (X must approve before Y) — keep flat «single approver» per row; multi-approver = B.4 break-glass pattern.

#### Pre-conditions / dependencies

- W1.5 (**HARD-BLOCKER**) — fga_outbox + drainer must apply grants. **Without W1.5: activation succeeds in DB but FGA tuple never lands → Check denies → silent enforcement-gap**.
- W1.6 #36 — list/get caller-scope; #39 CreatedBy from principal; #43 anti-anon on `ApproveJITActivation` / `ActivateJIT` / `DenyJITActivation`.

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/service/jit_pending_service.go` (`Approve` impl), `internal/apps/kacho/api/jit_pending/handler.go` (already exists; verify wires), `internal/service/phase7_workers.go` (expiry worker — already exists per W1.5 finding #51; B.3 extends to compute next-expiry timestamp metric), `internal/repo/kacho/pg/jit_pending_repo.go` (state-CAS update method) |
| `kacho-proto` | `kacho-proto/proto/kacho/cloud/iam/v1/jit_pending_service.proto` — already has `ApproveJITActivation`/`DenyJITActivation` (verified above). No proto changes. |
| `kacho-deploy` | none |

#### DB migrations

- **No new migration**. Tables exist.

#### gRPC API surface

- **No new RPC**. Existing `JitPendingService.ApproveJITActivation` / `DenyJITActivation` / `GetJitPending` / `ListJitPending` — body of Approve is implemented in W2.B (currently stubbed per master plan "Enterprise = заглушки").

#### GWT scenarios

##### W2.B-B3-01 (positive) — approve → grant lands in FGA

**Given** eligibility row `je_t31` (user=`usr_dev`, role=`rol_proj_admin`, resource=`project:prj_x`, ttl=3600)
**And** pending row `jp_t31` (eligibility=`je_t31`, requester=`usr_dev`, approver=`usr_lead`, state=AWAITING_APPROVAL)
**And** ctx principal = `usr_lead`

**When** `JitPendingService.ApproveJITActivation(pending_id=jp_t31, justification="release week")`

**Then** Operation returned; resolved → done=true
**And** `access_bindings_jit_pending.state = APPROVED` (CAS-update `WHERE state='AWAITING_APPROVAL'`)
**And** new `access_bindings` row (subject=usr_dev, role=rol_proj_admin, resource=project:prj_x, expires_at ≈ now+1h, origin='jit')
**And** `fga_outbox` row exists, eventually drained → FGA Check `user:usr_dev, project:prj_x, project_admin` returns `allowed=true`
**And** `audit_outbox` row `iam.jit.activated` (approver=usr_lead, subject=usr_dev)

##### W2.B-B3-02 (positive) — deny → no grant, audit only

**Given** same eligibility + pending state=AWAITING_APPROVAL
**When** `DenyJITActivation(pending_id, reason="overlapping access exists")`

**Then** Operation completes; `access_bindings_jit_pending.state = DENIED`
**And** **No** access_bindings row, **no** fga_outbox row
**And** `audit_outbox` row `iam.jit.denied` (approver, subject, reason)

##### W2.B-B3-03 (negative) — non-approver tries Approve → PermissionDenied

**Given** pending row with `approver_user_id = usr_lead`
**And** ctx principal = `usr_random_outsider`

**When** `ApproveJITActivation(pending_id)`

**Then** `codes.PermissionDenied` (caller != approver, not cluster-admin)
**And** No state change

##### W2.B-B3-04 (negative) — already-decided pending → FailedPrecondition

**Given** pending row `state = APPROVED` (already activated)
**When** `ApproveJITActivation(pending_id)` again (replay or stale UI)

**Then** `codes.FailedPrecondition` («pending is not in AWAITING_APPROVAL state») — driven by CAS returning 0 rows on state-update

##### W2.B-B3-05 (edge) — concurrent Approve + Deny → exactly one succeeds

**Given** pending row state=AWAITING_APPROVAL
**When** approver A calls `Approve` and approver B calls `Deny` simultaneously (race)

**Then** Exactly one transaction succeeds; the other gets `codes.FailedPrecondition`. Resulting state = whichever won.

##### W2.B-B3-06 (edge) — expiry worker revokes grant after TTL

**Given** access_bindings row (origin=jit, expires_at = now - 1s)
**When** expiry worker tick runs

**Then** binding row deleted (or status=EXPIRED)
**And** fga_outbox revoke row → drained → FGA Check denies
**And** caep_outbox row `iam.credential.revoked` → drained → subscribers notified

#### B.3.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B3-IT-01** | `Test_JitApprove_GrantsAndDrainsToFGA` | integration | B3-01 |
| **W2.B-B3-IT-02** | `Test_JitDeny_NoGrant` | integration | B3-02 |
| **W2.B-B3-IT-03** | `Test_JitApprove_NonApprover_Denied` | integration | B3-03 |
| **W2.B-B3-IT-04** | `Test_JitApprove_AlreadyDecided_FailedPrecondition` | integration | B3-04 |
| **W2.B-B3-IT-05** | `Test_JitApprove_ConcurrentRace_OneWins` | integration (concurrent goroutines) | B3-05 |
| **W2.B-B3-IT-06** | `Test_JitExpiryWorker_RevokesAndEmitsCAEP` | integration | B3-06 |
| **W2.B-B3-NM-01** | `JIT-APPROVE-ENFORCED-FGA` (replaces stub from W1.5 plan §1.5) | newman | B3-01 |
| **W2.B-B3-NM-02** | `JIT-DENY-NO-GRANT` | newman | B3-02 |
| **W2.B-B3-NM-03** | `JIT-APPROVE-NON-APPROVER-DENY` | newman | B3-03 |
| **W2.B-B3-NM-04** | `JIT-EXPIRY-REVOKES` (replaces stub from W1.5 plan §1.5) | newman | B3-06 |

#### Vault entries to update

- `resources/iam-jit-eligibility.md` — flow + lifecycle picture
- `resources/iam-jit-pending.md` — state-machine; Approve/Deny CAS contract
- `resources/iam-access-binding.md` — `origin=jit` semantics; `expires_at` set by activate
- `rpc/iam-jit-pending-service.md` — Approve/Deny semantics, error codes
- `edges/iam-jit-to-fga.md` — Approve → fga_outbox → drainer → FGA Check
- `edges/iam-jit-to-caep.md` — expiry → caep_outbox
- `KAC/KAC-W2.B-3.md` — trail

#### DoD

- [ ] APPROVED B.3 section
- [ ] Branch `KAC-W2.B-3-jit-activate`
- [ ] RED commits per §B.3.5 above (6 integration + 4 newman)
- [ ] GREEN: Approve/Deny impl, state-CAS, fga_outbox emit, audit emit, expiry worker
- [ ] All 6 scenarios GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (7 entries)
- [ ] PR merged
- [ ] **`iam-jit-pending` newman suite 100% GREEN** (verifies W2.B-B3 closes any leftover failures post-W1.6)

---

### B.4 — Break-glass full workflow (2-person approval + auto-revoke + audit + DB-level distinctness CHECK)

#### Scope (IN / OUT)

- **IN**: complete state-machine for `cluster_break_glass_grants` (table exists, `state` column already):
  ```
  REQUESTED → AWAITING_APPROVAL_A → AWAITING_APPROVAL_B → ACTIVE → EXPIRED
                  ↓                       ↓
                DENIED                   DENIED
  ```
- **IN**: `RequestBreakGlass(cluster_id, subject_id, justification, requested_ttl)` → state=AWAITING_APPROVAL_A
- **IN**: `ApproveBreakGlassA(request_id)` → state=AWAITING_APPROVAL_B (W1.5/W1.6 already enforce: approver ≠ requester; anti-anon; FGA Check approver=break_glass_approver_a relation)
- **IN**: `ApproveBreakGlassB(request_id)` → state=ACTIVE; **atomically**: insert `cluster_admin_grants` row + emit `fga_outbox` grant + emit `audit_outbox` `iam.breakglass.activated` + emit `caep_outbox` `iam.session.refresh_required` (subject) — parity with KAC-163 W1.5 §1.6 (#52). Approver B ≠ Approver A enforced via **NEW CHECK constraint at DB level** (Запрет #10 — see §B.4 «DB migrations»).
- **IN**: `DenyBreakGlass(request_id, reason)` callable at AWAITING_APPROVAL_A or _B → state=DENIED
- **IN**: **breakglass_expiry_worker (NEW)** — separate from existing JIT-expiry worker (which lives in `phase7_workers.go` for JIT-only). NEW file `breakglass_expiry_worker.go`; **explicitly registered in `cmd/kacho-iam/main.go` alongside** the existing JIT expiry worker (both run as separate goroutines, no shared state). Scans ACTIVE grants where `expires_at < now()` → CAS state ACTIVE→EXPIRED + delete `cluster_admin_grants` row + emit fga_outbox revoke + audit + caep
- **IN**: mandatory **post-incident review** (`break_glass_post_incident_reviews` table from 0024): admin must submit review-text within `expires_at + 7d` else alert fires (B.9). Endpoint `SubmitBreakGlassReview(request_id, review_text)` (NEW RPC).
- **OUT**: PagerDuty/Slack push on ACTIVE state — out of scope (audit emit + AM rule covers alerting).
- **OUT**: hardware-token MFA-step-up on Approve — W3 (#23 mfa-fresh).
- **OUT**: BG-token-issuance (one-time JWT for grant duration) — covered by FGA grant via cluster-admin role; no separate token.

#### Pre-conditions / dependencies

- W1.5 #52 — Approve B writes cluster_admin_grants + fga_outbox atomically. **Closed.**
- W1.6 #43 — anti-anon on `Approve*` / `Deny*` / `Activate*`.

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/service/phase7_break_glass_service.go` (RequestBreakGlass/ApproveA/ApproveB/Deny — complete impl), `internal/service/breakglass_expiry_worker.go` (NEW — separate from JIT-expiry), `internal/repo/kacho/pg/break_glass_repo.go` (state-CAS methods), `internal/apps/kacho/api/break_glass/handler.go` (wires; SubmitBreakGlassReview wire), `cmd/kacho-iam/main.go` (**register breakglass_expiry_worker as NEW goroutine alongside existing JIT expiry worker**), `internal/migrations/00XX_w2b_breakglass_approver_distinct_check.sql` (NEW) |
| `kacho-proto` | `kacho-proto/proto/kacho/cloud/iam/v1/break_glass_service.proto` — already has RequestBreakGlass / ApproveBreakGlassA/B / DenyBreakGlass / Get / List (verified above). **NEW RPC**: `SubmitBreakGlassReview(SubmitBreakGlassReviewRequest) returns (Operation)` — add to `break_glass_service.proto`. Field: `request_id`, `review_text` (max 16384). |
| `kacho-deploy` | helm `alerts.breakglass_active` rule (B.9-related); no separate value |

#### DB migrations

- `00XX_w2b_breakglass_approver_distinct_check.sql` (NEW — number assigned at impl-start):
  ```sql
  -- Enforce approver distinctness at DB level per workspace CLAUDE.md §Запрет #10:
  -- software-side check is TOCTOU-prone; DB CHECK is race-free.
  -- NULL-tolerant (both approvers may be NULL during REQUESTED/AWAITING_A states).
  ALTER TABLE kacho_iam.cluster_break_glass_grants
      ADD CONSTRAINT cluster_break_glass_grants_approvers_distinct_check
      CHECK (
          approver_a_user_id IS NULL
          OR approver_b_user_id IS NULL
          OR approver_a_user_id <> approver_b_user_id
      );
  ```

#### gRPC API surface

- **NEW RPC**: `BreakGlassService.SubmitBreakGlassReview` (proto file `break_glass_service.proto`).
- Existing RPCs `RequestBreakGlass` / `ApproveBreakGlassA` / `ApproveBreakGlassB` / `DenyBreakGlass` / `ListPendingBreakGlassRequests` / `GetBreakGlassRequest` — implementations completed in B.4.

#### GWT scenarios

##### W2.B-B4-01 (positive) — full happy path: Request → A → B → ACTIVE → auto-revoke

**Given** Cluster `cluster_default` exists; `usr_oncall` is in `break_glass_requester` role; `usr_approver_a`, `usr_approver_b` are in `break_glass_approver_a` / `break_glass_approver_b` roles respectively.

**When** `usr_oncall` calls `RequestBreakGlass(cluster=cluster_default, subject=usr_oncall, justification="DB recovery", ttl_seconds=3600)`

**Then** new row state=AWAITING_APPROVAL_A; Operation done; audit `iam.breakglass.requested`

**When** `usr_approver_a` calls `ApproveBreakGlassA(request_id)`

**Then** state → AWAITING_APPROVAL_B; audit `iam.breakglass.approved_a`

**When** `usr_approver_b` calls `ApproveBreakGlassB(request_id)`

**Then** state → ACTIVE; expires_at = now + 3600; `cluster_admin_grants` row exists; fga_outbox emitted; FGA Check `user:usr_oncall, cluster:cluster_default, cluster_admin` → ALLOW (after drain); audit `iam.breakglass.activated`; caep_outbox `iam.session.refresh_required`

**And** 3600 seconds later expiry worker (breakglass_expiry_worker, NEW separate goroutine) → state EXPIRED; cluster_admin_grants row removed; FGA revoke drained; audit `iam.breakglass.expired`; caep_outbox `iam.credential.revoked`

##### W2.B-B4-02 (positive) — DenyBreakGlass at A

**When** ApproveA path → instead `DenyBreakGlass(request_id, reason="not approved by SecOps")`

**Then** state DENIED; no grant; audit `iam.breakglass.denied`

##### W2.B-B4-03 (negative) — Approver A == Approver B → DB CHECK violation → FailedPrecondition

**Given** Approver A == Approver B (same user)
**When** `usr_approver_a` calls `ApproveBreakGlassB` after their own `ApproveBreakGlassA`

**Then** Postgres CHECK constraint violation (`cluster_break_glass_grants_approvers_distinct_check`) → SQLSTATE `23514` → mapped to `codes.FailedPrecondition` («break-glass approver B must differ from approver A»). **DB-level enforcement** (Запрет #10) — race-free; cannot be bypassed by concurrent transactions.

##### W2.B-B4-04 (negative) — Approver tries to Approve B before A → FailedPrecondition

**Given** state = AWAITING_APPROVAL_A
**When** `ApproveBreakGlassB(request_id)` — wrong order

**Then** `codes.FailedPrecondition` (CAS-update finds 0 rows because state ≠ AWAITING_APPROVAL_B)

##### W2.B-B4-05 (edge) — concurrent ApproveA + DenyBreakGlass → exactly one wins

**Given** state = AWAITING_APPROVAL_A
**When** simultaneously two approvers: one ApproveA, other Deny

**Then** Exactly one CAS-update succeeds; other gets FailedPrecondition. Final state = ACTIVE_NEXT_STAGE or DENIED, never both.

##### W2.B-B4-06 (edge) — post-incident review missing → alert fires

**Given** Grant ACTIVATED at T; expires at T+1h; T+8d arrives without `SubmitBreakGlassReview` called
**When** alerting query runs (B.9 VictoriaLogs LogsQL OR VM metric `breakglass_review_missing{}`)

**Then** AM fires `BreakGlassReviewOverdue` alert with request_id, requester, expired_at

#### B.4.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B4-IT-01** | `Test_BreakGlass_FullFlowHappy` | integration | B4-01 |
| **W2.B-B4-IT-02** | `Test_BreakGlass_DenyAtA` | integration | B4-02 |
| **W2.B-B4-IT-03** | `Test_BreakGlass_SameApproverRejected_DBCheckViolation` | integration | B4-03 |
| **W2.B-B4-IT-04** | `Test_BreakGlass_OutOfOrderApprove_FailedPrecondition` | integration | B4-04 |
| **W2.B-B4-IT-05** | `Test_BreakGlass_ConcurrentApproveDeny_OneWins` | integration (concurrent) | B4-05 |
| **W2.B-B4-IT-06** | `Test_BreakGlass_ExpiryWorker_AutoRevokes` | integration | B4-01 expiry phase |
| **W2.B-B4-IT-07** | `Test_BreakGlass_SubmitReview_HappyAndIdempotent` | integration | review submit |
| **W2.B-B4-IT-08** | `Test_BreakGlass_ExpiryWorker_RunsAlongsideJitWorker` | integration | both workers coexist, no shared-state corruption |
| **W2.B-B4-NM-01** | `BREAKGLASS-HAPPY-FLOW` (replaces stub from W1.5 §1.6) | newman | B4-01 |
| **W2.B-B4-NM-02** | `BREAKGLASS-SAME-APPROVER-DENY` | newman | B4-03 |
| **W2.B-B4-NM-03** | `BREAKGLASS-EXPIRY-REVOKES` | newman | B4-01 expiry |

#### Vault entries to update

- `resources/iam-cluster-break-glass-grant.md` — state-machine; expires_at semantics; **NEW** CHECK constraint approver-distinctness
- `resources/iam-cluster-admin-grant.md` — break-glass-origin grants; idempotency key (KAC-163)
- `resources/iam-break-glass-post-incident-review.md` — NEW; mandatory review SLA
- `rpc/iam-break-glass-service.md` — full method table; state-machine
- `edges/iam-breakglass-to-fga.md` — Approve B → cluster_admin_grants + fga_outbox (parity with bootstrap_admin)
- `edges/iam-breakglass-to-caep.md` — Activate + Expire → caep_outbox
- `edges/iam-breakglass-to-audit.md` — every state-transition emits audit
- `KAC/KAC-W2.B-4.md` — trail

#### DoD

- [ ] APPROVED B.4 section
- [ ] Branch `KAC-W2.B-4-breakglass`
- [ ] RED commits per §B.4.5 above (8 integration + 3 newman)
- [ ] proto changes: SubmitBreakGlassReview RPC merged in `kacho-proto`
- [ ] GREEN: state-machine, approver-distinctness CHECK migration, expiry worker (NEW goroutine), review-submit, alert rule
- [ ] All 6 scenarios GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (8 entries)
- [ ] PR merged
- [ ] `iam-breakglass` newman suite NEW + GREEN
- [ ] **breakglass_expiry_worker registration verified** in `cmd/kacho-iam/main.go` — separate goroutine from existing JIT-expiry worker; integration test B4-IT-08 demonstrates both workers run concurrently without interference

---

### B.5 — AccessReview campaign engine

#### Scope (IN / OUT)

- **IN**: campaign lifecycle:
  1. admin calls `ScheduleAccessReview(scope_type, scope_id, deadline, reviewer_assignment_strategy)` → row in `access_review_campaigns`
  2. **enumeration worker** (NEW) reads campaign → enumerates `(subject, role, resource)` tuples in scope → writes `access_review_items` rows (state=OPEN) → assigns reviewer per `reviewer_assignment_strategy` (one of: `account_owner`, `role_assignee_self`, `explicit_list`)
  3. reviewer calls `ApproveReviewItem(item_id)` (W1.6 #35: reviewer=principal) → item.state=APPROVED; no binding change
  4. reviewer calls `RevokeReviewItem(item_id)` → item.state=REVOKED; **atomically**: delete `access_bindings` row + emit `fga_outbox` revoke + emit `audit_outbox` + emit `caep_outbox` (subject change)
  5. **deadline worker** (NEW): when `deadline < now()` AND campaign.state=ACTIVE → state=CLOSED; OPEN items → state=AUTO_REVOKED (per `expire_strategy='revoke'`) OR state=AUTO_APPROVED (per `expire_strategy='keep'`); audit
- **IN**: `CancelAccessReviewCampaign(campaign_id)` (already in proto): state=CANCELLED; OPEN items dropped from queue; audit `iam.review.campaign_cancelled`
- **OUT**: cross-campaign deduplication (item appearing in 2 campaigns) — items per-campaign distinct; no dedup
- **OUT**: reviewer delegation (reviewer says «approve all by X») — UI ticket; backend handles per-item Approve
- **OUT**: scheduled recurring campaigns (cron-style) — manual `Schedule` call only; recurrence via admin tooling

#### Pre-conditions / dependencies

- W1.5 — fga_outbox revoke path on RevokeItem
- W1.6 #35 — reviewer from principal (closed)
- W1.6 #43 — anti-anon on `Schedule*`/`Approve*`/`Revoke*`/`Cancel*`

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/service/phase7_access_review_service.go` (engine: enumerate + decide + deadline workers), `internal/service/access_review_enum_worker.go` (NEW), `internal/service/access_review_deadline_worker.go` (NEW), `internal/repo/kacho/pg/access_review_campaign_repo.go` (state-CAS, item-list-by-campaign), `internal/apps/kacho/api/access_review/handler.go` (wires existing; verify) |
| `kacho-proto` | `access_review_service.proto` already has needed RPCs. Add field on `ScheduleAccessReviewRequest`: `reviewer_assignment_strategy` (enum) + `expire_strategy` (enum). NEW fields — proto change. |
| `kacho-deploy` | none |

#### DB migrations

- **No new migration**. `access_review_campaigns` + `access_reviews` + `access_review_items` exist.

#### gRPC API surface

- Existing RPCs preserved (`ScheduleAccessReview`, `CancelAccessReviewCampaign`, `GetAccessReview`, `ListAccessReviews`, `ListAccessReviewItems`, `ApproveReviewItem`, `RevokeReviewItem`).
- **Proto field additions** to `ScheduleAccessReviewRequest`: `reviewer_assignment_strategy` (enum: ACCOUNT_OWNER / ROLE_ASSIGNEE_SELF / EXPLICIT_LIST), `explicit_reviewer_user_ids` (repeated string), `expire_strategy` (enum: KEEP / REVOKE).

#### GWT scenarios

##### W2.B-B5-01 (positive) — schedule → enumerate → review-Approve

**Given** Project `prj_x` has 3 access_bindings: (usr_a, admin), (usr_b, viewer), (usr_c, viewer); `usr_owner` is account_owner

**When** `usr_owner` calls `ScheduleAccessReview(scope=project:prj_x, deadline=now+7d, reviewer_assignment_strategy=ACCOUNT_OWNER, expire_strategy=REVOKE)`

**Then** campaign row created (state=ACTIVE); within seconds enumeration worker creates 3 items (state=OPEN, reviewer=usr_owner)

**When** `usr_owner` calls `ApproveReviewItem(item_1_id)` and `ApproveReviewItem(item_2_id)` and `RevokeReviewItem(item_3_id)`

**Then** items 1+2 state=APPROVED; item 3 state=REVOKED
**And** access_bindings row for (usr_c, viewer) deleted
**And** fga_outbox revoke row → drained → FGA Check usr_c on prj_x → DENY
**And** audit `iam.review.item_approved` × 2, `iam.review.item_revoked` × 1
**And** caep_outbox `iam.session.revoked` for usr_c

##### W2.B-B5-02 (positive) — campaign deadline expires → REVOKE strategy auto-revokes OPEN items

**Given** campaign deadline = now-1s; 1 OPEN item; expire_strategy=REVOKE

**When** deadline worker ticks

**Then** campaign state=CLOSED; item state=AUTO_REVOKED; binding deleted; fga_outbox revoke; audit `iam.review.auto_revoked`

##### W2.B-B5-03 (negative) — non-reviewer tries Approve → PermissionDenied

**Given** item assigned to `usr_owner`
**And** ctx principal = `usr_random`

**When** `ApproveReviewItem(item_id)`

**Then** `codes.PermissionDenied` (caller != assigned reviewer; W1.6 #35 enforced)

##### W2.B-B5-04 (negative) — Approve already-decided item → FailedPrecondition

**Given** item state=APPROVED
**When** ApproveReviewItem(item_id) again

**Then** `codes.FailedPrecondition` («item is not in OPEN state») — CAS finds 0 rows

##### W2.B-B5-05 (edge) — CancelAccessReviewCampaign mid-flight

**Given** campaign ACTIVE; 2 items OPEN; 1 item APPROVED
**When** admin calls `CancelAccessReviewCampaign(campaign_id)`

**Then** campaign state=CANCELLED; OPEN items → state=CANCELLED (no auto-revoke even if expire_strategy=REVOKE); APPROVED item stays APPROVED (no rollback); audit `iam.review.campaign_cancelled`

#### B.5.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B5-IT-01** | `Test_AccessReview_ScheduleEnumApprove_HappyPath` | integration | B5-01 |
| **W2.B-B5-IT-02** | `Test_AccessReview_DeadlineAutoRevokes` | integration (advance clock) | B5-02 |
| **W2.B-B5-IT-03** | `Test_AccessReview_NonReviewer_Denied` | integration | B5-03 |
| **W2.B-B5-IT-04** | `Test_AccessReview_DoubleDecide_FailedPrecondition` | integration | B5-04 |
| **W2.B-B5-IT-05** | `Test_AccessReview_Cancel_DropsOpenItems` | integration | B5-05 |
| **W2.B-B5-NM-01** | `REVIEW-SCHEDULE-AND-DECIDE-HAPPY` | newman | B5-01 |
| **W2.B-B5-NM-02** | `REVIEW-DEADLINE-AUTO-REVOKE` | newman (advance time via test-mode endpoint) | B5-02 |
| **W2.B-B5-NM-03** | `REVIEW-CANCEL-MID-FLIGHT` | newman | B5-05 |

#### Vault entries to update

- `resources/iam-access-review-campaign.md` — state-machine + reviewer-assignment strategies
- `resources/iam-access-review-item.md` — state-machine; CAS contract; revoke side-effects
- `rpc/iam-access-review-service.md` — full method table + new proto fields
- `edges/iam-review-to-fga.md` — Revoke → fga_outbox
- `edges/iam-review-to-caep.md` — Revoke → caep_outbox
- `packages/iam-service-access-review.md` — engine + workers
- `KAC/KAC-W2.B-5.md` — trail

#### DoD

- [ ] APPROVED B.5 section
- [ ] Branch `KAC-W2.B-5-access-review`
- [ ] proto changes: new fields on ScheduleAccessReviewRequest merged
- [ ] RED commits per §B.5.5 (5 integration + 3 newman)
- [ ] GREEN: enum worker, deadline worker, Approve/Revoke state-CAS, Cancel cleanup
- [ ] All 5 scenarios GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (7 entries)
- [ ] PR merged
- [ ] `iam-access-review-campaign` newman suite NEW + GREEN

---

### B.6 — ComplianceReport engine

#### Scope (IN / OUT)

- **IN**: `GenerateAccessReport(scope_type, scope_id, format)` → returns Operation; **generation worker** (NEW) executes:
  1. validate scope-visibility for principal (W1.6 #37 — already done at handler)
  2. query data: `SELECT * FROM access_bindings WHERE scope = $1` JOIN roles JOIN cluster_admin_grants
  3. render Markdown OR JSON per `format`
  4. INSERT into `compliance_reports` (id, scope, format, content_bytes, generated_at, generated_by_user_id)
  5. Operation done; response = report_id
- **IN**: `GetReportDownloadUrl(report_id)` → returns presigned URL valid for 5 minutes; URL contains HMAC signature (key from `oidc_jwks_keys`); URL contains `report_id` + `expires_at`. **Download REST handler registration owner: B.6** (registered in `internal/apps/kacho/api/compliance_report/download_handler.go`, mounted on external listener via `cmd/kacho-iam/main.go`). W2.A catalog gen merely references this path in the OpenAPI catalog; **handler ownership belongs to B.6**, not W2.A. Verifier on `/iam/v1/compliance_report_download/{token}` decodes + serves content from `compliance_reports.content_bytes`. (S3 not in scope per lean-v1 per master decisions.)
- **IN**: existing scope-filter on `GetComplianceReport` / `ListComplianceReports` (W1.6 #37 closed).
- **OUT**: PDF rendering — Markdown/JSON only
- **OUT**: S3-backed storage — DB-bytea ok for v1; PDF + S3 = post-v1
- **OUT**: scheduled report generation (cron) — manual `Generate` only

#### Pre-conditions / dependencies

- W1.6 #37 — VisibleScopeProvider wiring (closed)

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/service/compliance_report_service.go` (extend Generate impl), `internal/service/compliance_report_render.go` (NEW — MD/JSON rendering), `internal/service/compliance_report_worker.go` (NEW — async worker), `internal/apps/kacho/api/compliance_report/handler.go` (download URL handler — REST), `internal/apps/kacho/api/compliance_report/download_token.go` (NEW — HMAC sign/verify), `internal/apps/kacho/api/compliance_report/download_handler.go` (NEW — REST GET endpoint; **B.6-owned**, not W2.A) |
| `kacho-proto` | `compliance_report_service.proto` already has all 4 RPCs. No proto change. |
| `kacho-deploy` | none |

#### DB migrations

- **No new migration**. `compliance_reports` table exists (0014).

#### gRPC API surface

- Existing 4 RPCs. No additions.

#### GWT scenarios

##### W2.B-B6-01 (positive) — generate Markdown report

**Given** Project `prj_x` has 3 access_bindings, 2 roles in scope, 1 cluster_admin grant; principal=`usr_owner` has admin on prj_x
**When** `GenerateAccessReport(scope=project:prj_x, format=MARKDOWN)`

**Then** Operation completes; report_id in response
**And** `compliance_reports` row exists (format='markdown', scope='project:prj_x', generated_by=`usr_owner`)
**And** content_bytes contains valid Markdown with sections "Access Bindings", "Roles", "Cluster Admin Grants"
**And** audit `iam.report.generated`

##### W2.B-B6-02 (positive) — GetReportDownloadUrl + fetch

**Given** report `cr_t62` exists; principal=`usr_owner`
**When** `GetReportDownloadUrl(report_id=cr_t62)` → returns URL `https://api.example/iam/v1/compliance_report_download/<token>`

**Then** `<token>` decodes to {report_id=cr_t62, expires_at=now+5min, principal=usr_owner, hmac=...}
**And** GET that URL within 5 min → 200 OK with content
**And** GET that URL after 5 min → 401 (expired)

##### W2.B-B6-03 (negative) — invisible-scope principal → NotFound

**Given** report on prj_x; principal=`usr_random` (no admin on prj_x)
**When** `Generate` OR `Get` OR `GetReportDownloadUrl`

**Then** `codes.NotFound` (W1.6 #37 enforced)

##### W2.B-B6-04 (negative) — tampered download token → 401

**When** GET download URL with HMAC byte modified

**Then** 401 «download token invalid»

##### W2.B-B6-05 (edge) — concurrent Generate same scope → 2 distinct reports

**Given** 2 concurrent `Generate(scope=prj_x)` calls
**When** both complete

**Then** 2 different `compliance_reports.id` rows; both contain same data snapshot (point-in-time)

#### B.6.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B6-IT-01** | `Test_Compliance_Generate_MarkdownHappy` | integration | B6-01 |
| **W2.B-B6-IT-02** | `Test_Compliance_DownloadUrl_HappyAndExpiry` | integration (advance clock) | B6-02 |
| **W2.B-B6-IT-03** | `Test_Compliance_InvisibleScope_NotFound` | integration | B6-03 |
| **W2.B-B6-IT-04** | `Test_Compliance_DownloadToken_TamperRejected` | integration | B6-04 |
| **W2.B-B6-IT-05** | `Test_Compliance_ConcurrentGenerate_DistinctRows` | integration (concurrent) | B6-05 |
| **W2.B-B6-NM-01** | `COMPLIANCE-GENERATE-MD-HAPPY` | newman | B6-01 |
| **W2.B-B6-NM-02** | `COMPLIANCE-DOWNLOAD-URL-EXPIRES` | newman | B6-02 |
| **W2.B-B6-NM-03** | `COMPLIANCE-INVISIBLE-SCOPE-DENY` (regression with W1.6 #37) | newman | B6-03 |

#### Vault entries to update

- `resources/iam-compliance-report.md` — generation flow; Markdown/JSON formats; DB-bytea storage
- `rpc/iam-compliance-report-service.md` — Generate semantics; download URL contract
- `edges/iam-compliance-to-audit.md` — Generate → audit
- `packages/iam-service-compliance-report.md` — engine + render
- `KAC/KAC-W2.B-6.md` — trail

#### DoD

- [ ] APPROVED B.6 section
- [ ] Branch `KAC-W2.B-6-compliance`
- [ ] RED commits per §B.6.5 (5 integration + 3 newman)
- [ ] GREEN: render Markdown/JSON, async worker, download URL HMAC + REST handler registration (B.6-owned), scope-filter regression GREEN
- [ ] All 5 scenarios GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (5 entries)
- [ ] PR merged

---

### B.7 — GDPR erasure pipeline

#### Scope (IN / OUT)

- **IN**: full erasure flow per GDPR Art.17:
  1. `RequestErasure(subject_user_id, reason)` → row in `gdpr_erasure_requests` (state=REQUESTED, scheduled_for=now+30d, cancel_token_hash=bcrypt(random_secret), audit emit)
  2. response carries plaintext cancel_token ONCE (parity with W1.6 #11 sa-key redact pattern); subsequent reads return redacted
  3. `CancelErasureRequest(request_id, cancel_token)` callable within 30d window — bcrypt-compare token → state=CANCELLED (CAS `WHERE state='REQUESTED' AND scheduled_for > now()`); audit
  4. **erasure worker** (NEW): when `scheduled_for < now() AND state='REQUESTED'` → CAS state→EXECUTED; **erasure tx**:
     - `UPDATE users SET email=NULL, name=NULL, deleted_at=now(), pii_tombstoned_at=now() WHERE id=$1`
     - delete `scim_user_mappings` rows
     - emit `subject_change_outbox` (W1.2) — gateway cache invalidation; `change_type='erasure'` (NEW value, requires CHECK extension migration)
     - emit `caep_outbox` `iam.subject.erased` (RFC 8417)
     - emit `audit_outbox` `iam.subject.erasure_completed` (actor=`system:gdpr-worker`, subject=pseudonymised hash, NOT raw user_id, per GDPR)
- **IN**: `ListErasureRequests` scope-filter: caller can list **own** requests + (if admin) **all** in account
- **IN**: `GetErasureRequest` same scope-filter
- **IN — break-glass interaction (OQ-W2.B-15 RESOLVED)**: erasure executes **regardless** of any active B.4 break-glass grant for the same subject — legal compliance trumps active emergency access. Break-glass grant for the erased subject is auto-revoked as side-effect of `subject_change_outbox` cascade (downstream cache invalidation forces re-resolve, which fails since user PII is tombstoned). Tested via GWT W2.B-B7-06.
- **OUT**: erasure of related resources (instances/disks owned by user) — out of scope; tombstone in iam only; downstream services pick up via CAEP
- **OUT**: physical deletion (DELETE row) — keep row for audit-trail; tombstone semantics only (pseudonymise PII)

#### Pre-conditions / dependencies

- W1.6 #43 — anti-anon on `RequestErasure` / `CancelErasureRequest`
- W1.6 #11 redaction pattern — for cancel_token one-shot return
- W1.2 — `subject_change_outbox` exists; extension migration adds `'erasure'` to CHECK enum

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/service/gdpr_erasure_service.go` (Request/Cancel impl), `internal/service/gdpr_erasure_worker.go` (NEW), `internal/repo/kacho/pg/gdpr_erasure_repo.go` (cancel-token CAS, state-CAS), `internal/apps/kacho/api/gdpr_erasure/handler.go` (wires), `internal/migrations/00XX_w2b_gdpr_cancel_token.sql` (NEW), `internal/migrations/00XX_w2b_subject_change_outbox_check_extend.sql` (NEW), `cmd/kacho-iam/main.go` (register erasure worker) |
| `kacho-proto` | `gdpr_erasure_service.proto` — `CancelErasureRequestRequest` add field `cancel_token` (NEW). `RequestErasureResponse.metadata.cancel_token` field added to operation metadata. |
| `kacho-deploy` | none |

#### DB migrations

- `00XX_w2b_gdpr_cancel_token.sql` (NEW; number assigned at impl-start):
  ```sql
  -- Cancel-token: bcrypt-hashed, single-use, race-free via CAS.
  ALTER TABLE kacho_iam.gdpr_erasure_requests
      ADD COLUMN cancel_token_hash text;
  CREATE UNIQUE INDEX gdpr_active_request_per_subject
      ON kacho_iam.gdpr_erasure_requests (subject_user_id)
      WHERE state = 'REQUESTED';
  -- Prevents two concurrent erasure requests for same subject.

  -- Users tombstone tracking (pseudonymise audit).
  ALTER TABLE kacho_iam.users
      ADD COLUMN pii_tombstoned_at timestamptz;
  -- pii_tombstoned_at != NULL → email/name NULL'ed; row retained for FK targets.
  ```

- `00XX_w2b_subject_change_outbox_check_extend.sql` (NEW; number assigned at impl-start):
  ```sql
  -- Extend subject_change_outbox.change_type CHECK to allow 'erasure'.
  -- Existing values per W1.2: 'jit_eligibility_revoke', 'role_change', ...
  ALTER TABLE kacho_iam.subject_change_outbox
      DROP CONSTRAINT subject_change_outbox_change_type_check;
  ALTER TABLE kacho_iam.subject_change_outbox
      ADD CONSTRAINT subject_change_outbox_change_type_check
      CHECK (change_type IN (
          'jit_eligibility_revoke',
          'role_change',
          'role_grant',
          'role_revoke',
          'erasure'         -- B.7 NEW
      ));
  -- NOTE: full list of existing values to be verified against W1.2 source-of-truth migration at impl-start;
  -- ensure NEW migration includes ALL existing values + 'erasure' to avoid silent drops.
  ```

#### gRPC API surface

- `gdpr_erasure_service.proto`:
  - `CancelErasureRequestRequest` — NEW field `cancel_token` (string, required)
  - `RequestErasureResponse` — operation.response.metadata carries plaintext `cancel_token` on first response only (redacted on subsequent operation.Get per W1.6 #11 pattern)

#### GWT scenarios

##### W2.B-B7-01 (positive) — Request → wait 30d → erasure executed

**Given** user `usr_alice` exists with email=alice@x.com, name="Alice"
**When** `RequestErasure(subject=usr_alice, reason="GDPR Art.17 request")`

**Then** Operation done; response carries `cancel_token=<plaintext-X>` once; gdpr_erasure_requests row (state=REQUESTED, scheduled_for=now+30d, cancel_token_hash=bcrypt(X))
**And** subsequent `Operation.Get(op_id)` returns redacted cancel_token (`"<redacted>"`)

**When** advance clock 30d (or now+1ms in test); erasure worker ticks

**Then** state=EXECUTED; `users.email=NULL`, `users.name=NULL`, `users.pii_tombstoned_at=now`
**And** `subject_change_outbox` row (gateway cache invalidation, `change_type='erasure'`)
**And** `caep_outbox` row `iam.subject.erased` (subject_id = pseudonymised hash, NOT raw user_id)
**And** `audit_outbox` row `iam.subject.erasure_completed`

##### W2.B-B7-02 (positive) — Cancel within 30d window

**Given** request `er_t72` (state=REQUESTED, cancel_token=<X>)
**When** `CancelErasureRequest(request_id=er_t72, cancel_token=<X>)`

**Then** Operation done; state=CANCELLED (CAS-update); audit `iam.subject.erasure_cancelled`
**And** users row unchanged (email/name intact)

##### W2.B-B7-03 (negative) — Cancel with wrong token → PermissionDenied

**When** `CancelErasureRequest(request_id=er_t72, cancel_token="WRONG")`

**Then** `codes.PermissionDenied` («cancel token invalid»); state remains REQUESTED

##### W2.B-B7-04 (negative) — Cancel after grace expired → FailedPrecondition

**Given** request state=REQUESTED but `scheduled_for < now()` (expiry passed but worker hasn't ticked)
**When** Cancel with correct token

**Then** `codes.FailedPrecondition` («erasure grace period expired») — CAS includes `scheduled_for > now()`

##### W2.B-B7-05 (edge) — duplicate Request for same subject → AlreadyExists

**Given** existing request state=REQUESTED for usr_alice
**When** second `RequestErasure(subject=usr_alice)`

**Then** `codes.AlreadyExists` («erasure request already pending for subject») — partial UNIQUE index catches

##### W2.B-B7-06 (edge — OQ-W2.B-15 RESOLVED) — erasure executes regardless during active break-glass grant

**Given** user `usr_oncall` has an ACTIVE B.4 break-glass grant (cluster_admin_grants row, expires_at = now+1h, state=ACTIVE)
**And** A GDPR erasure request for `usr_oncall` exists (state=REQUESTED, scheduled_for=now-1s — past)

**When** erasure worker ticks

**Then** erasure executes regardless of active break-glass: `users.pii_tombstoned_at=now`, `users.email=NULL`, `users.name=NULL`
**And** `subject_change_outbox` row `change_type='erasure'` emitted
**And** Downstream gateway cache invalidation forces re-resolve on next request; subsequent FGA Check for `usr_oncall:cluster_admin` returns DENY because user is tombstoned (resolve-fails-on-erased pattern)
**And** Break-glass grant row still exists in `cluster_admin_grants` (not deleted by erasure worker — separate ownership), but **effectively unreachable** because subject can no longer authenticate (PII tombstoned)
**And** Audit emits both `iam.subject.erasure_completed` (pseudonymised) AND `iam.breakglass.subject_erased_during_active` (separate informational event for incident-review trail)

#### B.7.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B7-IT-01** | `Test_GDPR_RequestAndExecute_HappyPath` | integration (advance clock) | B7-01 |
| **W2.B-B7-IT-02** | `Test_GDPR_CancelWithinGrace_Cancels` | integration | B7-02 |
| **W2.B-B7-IT-03** | `Test_GDPR_CancelWrongToken_PermDenied` | integration | B7-03 |
| **W2.B-B7-IT-04** | `Test_GDPR_CancelAfterExpiry_FailedPrecondition` | integration | B7-04 |
| **W2.B-B7-IT-05** | `Test_GDPR_DuplicateRequest_AlreadyExists` | integration (partial UNIQUE) | B7-05 |
| **W2.B-B7-IT-06** | `Test_GDPR_ExecuteEmitsCAEPAndSubjectChange` | integration | B7-01 side effects |
| **W2.B-B7-IT-07** | `Test_GDPR_Execute_DuringActiveBreakGlass_StillExecutes` | integration (cross-feature B.4 + B.7) | B7-06 |
| **W2.B-B7-NM-01** | `GDPR-REQUEST-AND-CANCEL` | newman | B7-02 |
| **W2.B-B7-NM-02** | `GDPR-DUPLICATE-REQUEST-DENY` | newman | B7-05 |
| **W2.B-B7-NM-03** | `GDPR-CANCEL-WRONG-TOKEN-DENY` | newman | B7-03 |
| **W2.B-B7-NM-04** | `GDPR-ERASURE-OVERRIDES-BREAKGLASS` | newman | B7-06 |

#### Vault entries to update

- `resources/iam-gdpr-erasure-request.md` — NEW; lifecycle, cancel-token redaction, partial UNIQUE
- `resources/iam-user.md` — `pii_tombstoned_at` column + semantics
- `rpc/iam-gdpr-erasure-service.md` — full method table; cancel-token flow
- `edges/iam-gdpr-to-caep.md` — erasure → caep_outbox (iam.subject.erased)
- `edges/iam-gdpr-to-subject-change.md` — erasure → subject_change_outbox (W1.2 invalidation; `change_type='erasure'`)
- `edges/iam-gdpr-to-audit.md` — pseudonymised audit
- `edges/iam-gdpr-vs-breakglass.md` — NEW; OQ-W2.B-15 resolution: erasure trumps break-glass
- `KAC/KAC-W2.B-7.md` — trail

#### DoD

- [ ] APPROVED B.7 section
- [ ] Branch `KAC-W2.B-7-gdpr`
- [ ] proto changes: cancel_token field
- [ ] RED commits per §B.7.5 (7 integration + 4 newman)
- [ ] GREEN: cancel-token CAS, erasure worker, CAEP+subject-change emits, audit pseudonymisation, break-glass override behavior
- [ ] All 6 scenarios GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (8 entries)
- [ ] PR merged

---

### B.8 — CAEP push (signed Security Event Tokens) — **egress sign FULL** (ingress verify в W3.1 #42)

#### Scope (IN / OUT)

- **IN — egress (this is W2.B B.8)**: per OpenID CAEP spec + RFC 8417 SET:
  1. `caep_subscribers` CRUD (NEW RPCs on **InternalCAEPService** — internal listener only, §Запрет 6): `RegisterSubscriber(account_id, endpoint_url, expected_audience, event_types, signing_jwk_kid)`, `UpdateSubscriber`, `DeleteSubscriber`, `ListSubscribers`
  2. **drainer worker** (extends existing `phase8_caep_drainer.go`): reads `caep_outbox` (pending rows) → for each subscribed `(account_id, event_type)` → builds SET JWS (signed by `signing_jwk_kid` from `oidc_jwks_keys[purpose='caep_sign']` OR cluster-default if NULL) → POST to subscriber endpoint with body `application/secevent+jwt` → record delivery in `caep_event_delivery` (status=delivered / failed)
  3. retry policy: failed delivery retries exponential backoff (1s, 5s, 30s, 5min, 30min) up to 5 attempts; then status=`failed_permanent` + audit alert
  4. SET claims per RFC 8417: `iss=https://iam.<domain>`, `aud=<expected_audience>`, `iat=now`, `jti=<event_id>`, `events={<event_type>: {<event_payload>}}`
  5. **Expose `/jwks.json`** public read-only endpoint (RFC 7517 JWKS document) — subscribers verify our SETs against keys here. Only `purpose='caep_sign'` keys included; `oidc_id_token` signing keys NOT exposed via this endpoint (separation; OIDC has its own `/.well-known/openid-configuration` → `jwks_uri`).
- **IN — JWKS key purpose model**: additively extend existing `oidc_jwks_keys` (KAC-127 migration 0014) with `purpose text NOT NULL DEFAULT 'oidc_id_token'`. New CAEP signing keys inserted with `purpose='caep_sign'`. Existing rows backfill to default; no breaking change.
- **OUT — ingress (deferred to W3.1 #42)**: `caep_ingress_handler.go::parseSETBody` currently base64-decodes JWT without verifying signature — fix is **W3.1 #42** (fetch external IdP JWKS + verify SET signature, reject invalid). **Different code path** from B.8 egress; no overlap.
- **OUT**: push protocol negotiation per CAEP — fixed POST to `endpoint_url`; SSE/long-poll = post-v1
- **OUT**: subscriber-side ACK / nack — fire-and-forget on 2xx; non-2xx triggers retry; no dedicated control channel
- **OUT**: per-subscriber JWK overlay UI / advanced rotation policy (OQ-W2.B-8 RESOLVED — cluster-default in W2.B; per-subscriber overlay supported by schema but UI/admin = v2)

#### Pre-conditions / dependencies

- W1.6 #43 — anti-anon on `RegisterSubscriber` etc.
- existing `phase8_caep_drainer.go` skeleton (per `internal/service/phase8_caep_drainer.go` file listed earlier)
- existing `oidc_jwks_keys` (KAC-127 0014) — extended additively

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/service/phase8_caep_drainer.go` (extend — SET signing, retry), `internal/service/caep_signer.go` (NEW — JWS sign), `internal/apps/kacho/api/internal_iam/caep_subscriber_handler.go` (NEW — Subscriber CRUD on internal listener), `internal/apps/kacho/api/caep/jwks_handler.go` (NEW — public `/jwks.json` read-only), `internal/repo/kacho/pg/caep_subscribers_repo.go` (CRUD), `internal/migrations/00XX_w2b_caep_subscribers_extend.sql` (NEW), `internal/migrations/00XX_w2b_caep_jwks_purpose_extend.sql` (NEW), `cmd/kacho-iam/main.go` (wire internal listener + JWKS public endpoint) |
| `kacho-proto` | `internal_iam_service.proto` — extend or NEW `internal_caep_service.proto` with 4 RPCs: `RegisterSubscriber` / `UpdateSubscriber` / `DeleteSubscriber` / `ListSubscribers`. Internal-only (`Internal*` prefix). |
| `kacho-deploy` | network policy: kacho-iam pod must reach subscriber URLs (egress; configurable allowlist) |

#### DB migrations

- `00XX_w2b_caep_jwks_purpose_extend.sql` (NEW — additive on existing `oidc_jwks_keys`):
  ```sql
  -- Additively extend KAC-127 oidc_jwks_keys with purpose discriminator.
  -- Backfill existing rows to 'oidc_id_token' (default value).
  ALTER TABLE kacho_iam.oidc_jwks_keys
      ADD COLUMN purpose text NOT NULL DEFAULT 'oidc_id_token'
      CHECK (purpose IN ('oidc_id_token', 'caep_sign'));
  CREATE INDEX oidc_jwks_keys_purpose_idx ON kacho_iam.oidc_jwks_keys (purpose);
  ```

- `00XX_w2b_caep_subscribers_extend.sql` (NEW):
  ```sql
  ALTER TABLE kacho_iam.caep_subscribers
      ADD COLUMN signing_jwk_kid text REFERENCES kacho_iam.oidc_jwks_keys(kid);
  -- NULL = use cluster-default signing key (latest active purpose='caep_sign' row).
  CREATE UNIQUE INDEX caep_subscribers_account_endpoint_unique
      ON kacho_iam.caep_subscribers (account_id, endpoint_url)
      WHERE enabled = true;
  -- One enabled subscriber per (account, endpoint) tuple. Запрет #10 partial UNIQUE.
  ```

#### gRPC API surface

- **NEW proto file**: `kacho-proto/proto/kacho/cloud/iam/v1/internal_caep_service.proto`
- **NEW service `InternalCAEPService`** on internal listener (port 9091):
  - `rpc RegisterSubscriber(RegisterCAEPSubscriberRequest) returns (operation.Operation)`
  - `rpc UpdateSubscriber(UpdateCAEPSubscriberRequest) returns (operation.Operation)`
  - `rpc DeleteSubscriber(DeleteCAEPSubscriberRequest) returns (operation.Operation)`
  - `rpc ListSubscribers(ListCAEPSubscribersRequest) returns (ListCAEPSubscribersResponse)`
  - `rpc GetSubscriber(GetCAEPSubscriberRequest) returns (CAEPSubscriber)`
- **NEW REST endpoint**: `GET /jwks.json` on **external** listener (read-only, public per RFC 7517). No mutation; no Operation envelope.

#### GWT scenarios

##### W2.B-B8-01 (positive) — Register + event → SET delivered + JWS verifiable

**Given** subscriber registered: account=`acc_x`, endpoint=`https://idp.example/caep`, event_types=[`iam.session.revoked`], signing_jwk_kid=`kacho_iam_caep_sign_default`
**And** test HTTP server stands up at `https://idp.example/caep` (testcontainer or httptest)
**And** `oidc_jwks_keys` contains row with `kid=kacho_iam_caep_sign_default`, `purpose='caep_sign'`, RS256 key material

**When** test code inserts `caep_outbox` row (event=`iam.session.revoked`, subject=`usr_alice`, account=`acc_x`)
**And** drainer tick runs

**Then** subscriber receives POST `application/secevent+jwt` with body = JWS-signed SET
**And** SET payload contains `events: {"iam.session.revoked": {subject_id: "usr_alice"}}`, `iss`, `aud="https://idp.example/caep"`, `iat`, `jti`
**And** JWS signature verifies against `oidc_jwks_keys[kid=kacho_iam_caep_sign_default].public_key`
**And** `caep_event_delivery` row inserted (status=delivered, delivered_at, http_status=200, attempts=1)
**And** `caep_outbox` row status=delivered

##### W2.B-B8-02 (positive) — Update subscriber endpoint → next event delivers to new endpoint

**Given** subscriber endpoint=`https://old.example/caep`
**When** `UpdateSubscriber(id, endpoint_url="https://new.example/caep")` then trigger event

**Then** next SET goes to new.example, not old

##### W2.B-B8-03 (negative) — subscriber returns 5xx → retries with backoff

**Given** subscriber endpoint returns 503 first 4 attempts, 200 on 5th
**When** event triggers

**Then** drainer retries with exponential backoff; `caep_event_delivery.attempts=5`, status=delivered; total elapsed ≥ sum of backoff intervals

##### W2.B-B8-04 (negative) — subscriber permanently down → failed_permanent + alert

**Given** subscriber returns 500 indefinitely
**When** drainer exhausts 5 retries

**Then** `caep_event_delivery.status=failed_permanent`; audit `caep.delivery_failed`; AM rule `CAEPDeliveryFailedPermanent` fires

##### W2.B-B8-05 (edge) — disabled subscriber → no delivery, no error

**Given** subscriber row exists but `enabled=false`
**When** event triggers

**Then** no POST; no caep_event_delivery row for this subscriber

##### W2.B-B8-06 (edge) — duplicate Register for same (account, endpoint) → AlreadyExists

**When** second `RegisterSubscriber` with same account+endpoint

**Then** `codes.AlreadyExists` (partial UNIQUE index)

##### W2.B-B8-07 (edge) — `/jwks.json` exposes ONLY `purpose='caep_sign'` keys

**Given** `oidc_jwks_keys` contains 2 rows: kid=`oidc_sign_X` (purpose=oidc_id_token), kid=`caep_sign_Y` (purpose=caep_sign)

**When** Client GET `/jwks.json` (no auth, public)

**Then** HTTP 200; JWKS JSON body contains key with kid=`caep_sign_Y` only; `oidc_sign_X` NOT present
**And** Subscriber can verify B8-01 SET against keys in this response — closing the egress verify loop test

#### B.8.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B8-IT-01** | `Test_CAEP_SignAndDeliver_Happy` | integration (httptest as subscriber) | B8-01 |
| **W2.B-B8-IT-02** | `Test_CAEP_UpdateEndpoint_DeliversToNew` | integration | B8-02 |
| **W2.B-B8-IT-03** | `Test_CAEP_RetryBackoffOn5xx` | integration (httptest 503s then 200) | B8-03 |
| **W2.B-B8-IT-04** | `Test_CAEP_FailedPermanent_AfterMaxRetries` | integration | B8-04 |
| **W2.B-B8-IT-05** | `Test_CAEP_DisabledSubscriber_NoDelivery` | integration | B8-05 |
| **W2.B-B8-IT-06** | `Test_CAEP_DuplicateRegister_AlreadyExists` | integration | B8-06 |
| **W2.B-B8-IT-07** | `Test_CAEP_SignedSET_VerifiesAgainstJWKS` | integration | B8-01 signature side + B8-07 |
| **W2.B-B8-IT-08** | `Test_CAEP_JWKS_ExposesOnlyCAEPSignKeys` | integration | B8-07 |
| **W2.B-B8-NM-01** | `CAEP-REGISTER-AND-EVENT-DELIVERS` (uses internal-listener wrapper, since RegisterSubscriber is internal-only) | newman | B8-01 |
| **W2.B-B8-NM-02** | `CAEP-RETRY-ON-5XX` | newman (uses webhook.site or local mock) | B8-03 |
| **W2.B-B8-NM-03** | `CAEP-DUPLICATE-REGISTER-DENY` | newman | B8-06 |
| **W2.B-B8-NM-04** | `CAEP-JWKS-PUBLIC-FETCH` | newman | B8-07 |

#### Vault entries to update

- `resources/iam-caep-subscriber.md` — NEW; lifecycle, signing key link, UNIQUE constraint
- `resources/iam-caep-outbox.md` — NEW; emission events, drainer responsibility
- `resources/iam-caep-event-delivery.md` — NEW; retry semantics, status enum, retention
- `resources/iam-oidc-jwks-keys.md` — update (purpose discriminator added; caep_sign vs oidc_id_token separation)
- `rpc/iam-internal-caep-service.md` — NEW; subscriber CRUD on internal listener
- `rpc/iam-caep-jwks-rest.md` — NEW; public `/jwks.json` endpoint contract
- `edges/iam-caep-to-subscriber.md` — NEW; signed SET POST, retry/backoff
- `edges/iam-gdpr-to-caep.md` — already added in B.7; cross-reference
- `edges/iam-jit-to-caep.md` — already added in B.3
- `edges/iam-breakglass-to-caep.md` — already added in B.4
- `edges/iam-review-to-caep.md` — already added in B.5
- `packages/iam-service-caep.md` — drainer + signer
- `KAC/KAC-W2.B-8.md` — trail

#### DoD

- [ ] APPROVED B.8 section
- [ ] Branch `KAC-W2.B-8-caep-push`
- [ ] proto changes: internal_caep_service.proto merged
- [ ] RED commits per §B.8.5 (8 integration + 4 newman)
- [ ] GREEN: signer, drainer retry, subscriber CRUD on internal listener, JWKS purpose extend migration, public `/jwks.json` endpoint, AM rule
- [ ] All 7 scenarios GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (12 entries)
- [ ] PR merged
- [ ] **W3.1 #42 cross-reference**: PR description explicitly links to `sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md` §42 (CAEP ingress verify) as the W3.1 complement (different code path: ingress verify uses external IdP JWKS, not our `/jwks.json`)

---

### B.9 — Audit pipeline (VictoriaLogs via vector.dev)

#### Scope (IN / OUT)

- **IN**: replace stub no-op `audit.AuditLogger` in `kacho-iam` with real **structured JSON emit** to stdout (sourced from existing kacho-corelib slog or new tiny `audit/JSONEmitter` in kacho-iam).
- **IN**: every B-feature emits via the same `audit.Emit(ctx, event_type, fields)` API → marshals to single JSON line with fields: `timestamp`, `event_type`, `actor_principal`, `actor_user_id`, `actor_type`, `subject_user_id` (optional), `resource_type`, `resource_id`, `account_id`, `operation_id`, `correlation_id`, `event_payload`.
- **IN**: **vector.dev sidecar** in iam pod (`kacho-deploy` chart): reads container stdout → JSON parse → enrich (kubernetes labels, principal-resolve via `audit_outbox` join — out of scope; keep raw) → POST to VictoriaLogs HTTP push (per WS-6.2).
- **IN**: existing `audit_outbox` table retained as **durable backup** (DB-level audit-log for compliance retention; vector reads `caep_outbox`/`audit_outbox` as fallback only if stdout path fails — out of scope for now; simple stdout-only).
- **IN**: documented LogsQL queries for: «who activated break-glass in last 24h», «erasure requests by user X», «JIT activations by approver Y» (per `docs/runbooks/audit-queries.md` — NEW).
- **OUT**: SIEM forwarding (Splunk/QRadar) — vector can be reconfigured; default = VL only
- **OUT**: Merkle-chain tamper-evidence — per WS-3.3 explicit not-in-v1 decision
- **OUT**: HSM signing of audit batches — same
- **OUT**: encryption at rest of audit content — VL native, no app-layer encryption

#### Pre-conditions / dependencies

- W1.4 — principal propagation (so `actor_principal` is the true caller, not `user:bootstrap`)
- **HARD PRE-CONDITION — VictoriaLogs cluster deployed and reachable**: VL cluster must be deployed in target environment before B.9 IT-02 / NM-01 can pass. Verification command: `kubectl get svc -n kacho-observability vlogs` returns ≥1 service; `curl http://vlogs.kacho-observability.svc.cluster.local:9428/health` returns 200. **Without VL → IT-02 / NM-01 blocked**; B.9 unit tests (IT-01, IT-03, IT-04) can still run. Bring-up = WS-6.2 of production-launch-plan (`kacho-deploy` umbrella).

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/audit/emitter.go` (NEW — JSONEmitter implements existing AuditLogger interface), `internal/audit/emitter_test.go` (NEW), wire-up replaces existing no-op in `cmd/kacho-iam/main.go` |
| `kacho-corelib` | NONE (audit emit stays in iam since only iam uses it; if vpc/compute need audit later → promote to corelib). |
| `kacho-proto` | NONE |
| `kacho-deploy` | `helm/kacho-iam/values.yaml` — add vector sidecar block; `helm/kacho-iam/templates/deployment.yaml` — sidecar container; `helm/kacho-iam/files/vector.toml` — vector config (parse JSON, ship to VL); docs/runbooks/audit-queries.md (NEW) |

#### DB migrations

- **No new migration**.

#### gRPC API surface

- **No new RPC**. Audit is internal observability, no public API.

#### GWT scenarios

##### W2.B-B9-01 (positive) — every B-feature emit appears in stdout as parsable JSON

**Given** kacho-iam container running with audit emitter wired
**When** trigger an action: `JitPendingService.ApproveJITActivation(...)` (uses B.3)

**Then** container stdout contains one line (JSON) with fields: `event_type="iam.jit.activated"`, `actor_user_id="usr_lead"`, `subject_user_id="usr_dev"`, `resource_id="prj_x"`, `correlation_id=<uuid>`, `timestamp` ISO-8601, valid JSON parse

##### W2.B-B9-02 (positive) — vector sidecar ships event to VL

**Given** vector sidecar running with kacho-deploy chart; VL endpoint configured; **VL cluster reachable** (hard pre-condition above)
**When** trigger B.3 ApproveJIT

**Then** within 5 seconds, VL LogsQL `event_type:"iam.jit.activated" actor_user_id:"usr_lead"` returns ≥ 1 row

##### W2.B-B9-03 (negative) — vector sidecar down → events still emit (to stdout) — graceful degradation

**Given** vector sidecar crashed
**When** B-feature emits

**Then** kacho-iam container does NOT block / crash; stdout line emitted normally; (VL has no row, but iam unaffected). Recovery: vector restart picks up from container-runtime log buffer (depends on cluster-runtime; document in runbook).

##### W2.B-B9-04 (negative) — malformed audit field (e.g. binary in event_payload) → emit-still-succeeds, sanitized

**Given** code path tries to emit `event_payload = {"data": []byte{0x00, 0xff}}`
**When** emit

**Then** JSON marshalling escapes binary as base64 string OR drops field with `event_payload_error:"unmarshallable"`; line emitted; no panic

##### W2.B-B9-05 (edge) — burst of 1000 events in 1 second → no drops, all ship

**Given** stress-test goroutine emits 1000 events; **VL cluster reachable** (hard pre-condition)
**When** wait for vector ship interval (default 5s)

**Then** VL contains all 1000 events; no `audit_outbox_emit_failed` metric increment

#### B.9.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage | VL required? |
|---|---|---|---|---|
| **W2.B-B9-IT-01** | `Test_Audit_JSONEmitter_HappyParse` | unit | B9-01 | NO |
| **W2.B-B9-IT-02** | `Test_Audit_VectorSidecarShipsToVL` | integration (kind e2e — requires VL on cluster) | B9-02 | **YES — blocked without VL** |
| **W2.B-B9-IT-03** | `Test_Audit_VectorDown_GracefulDegradation` | integration | B9-03 | NO |
| **W2.B-B9-IT-04** | `Test_Audit_BinaryPayload_Sanitized` | unit | B9-04 | NO |
| **W2.B-B9-IT-05** | `Test_Audit_BurstNoLoss` | load (kind) | B9-05 | **YES — blocked without VL** |
| **W2.B-B9-NM-01** | `AUDIT-EVENT-SHIPS-TO-VL` (newman test: trigger action, wait, query VL via REST) | newman e2e | B9-02 | **YES — blocked without VL** |

#### Vault entries to update

- `packages/iam-audit.md` — NEW; emitter contract; field schema; correlation-id propagation
- `edges/iam-to-vector-to-victorialogs.md` — NEW; pipeline contract; sidecar pattern
- `runbooks/audit-queries.md` (in kacho-deploy or kacho-workspace) — NEW; sample LogsQL
- `KAC/KAC-W2.B-9.md` — trail

#### DoD

- [ ] APPROVED B.9 section
- [ ] **VL cluster verified reachable** in target env (`kubectl get svc -n kacho-observability vlogs` returns ≥1; `/health` returns 200)
- [ ] Branch `KAC-W2.B-9-audit-pipeline`
- [ ] RED commits per §B.9.5 (5 tests + 1 newman e2e)
- [ ] GREEN: JSONEmitter, vector sidecar wire, helm chart updated, runbook docs
- [ ] All 5 scenarios GREEN
- [ ] No TODO/FIXME
- [ ] vault updated (4 entries)
- [ ] PR merged
- [ ] **All B-features (B.1–B.8) demonstrate `audit_outbox` AND VL row per scenario in §6 — B.9 unblocks all audit-shape assertions in other features**

---

### B.10 — SPIRE + Cilium mesh mTLS (handshake & policy)

#### Scope (IN / OUT)

- **IN**: kacho-iam pod consumes SVID via SPIRE Workload API socket (`/run/spire/sockets/agent.sock`) — assumes SPIRE agent DaemonSet runs on each node (covered by W3.3 / `docs/specs/sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md`); B.10 = app-side handshake only.
- **IN**: kacho-iam Go process uses `github.com/spiffe/go-spiffe/v2/workloadapi` to fetch X.509-SVID for mTLS server certificate; auto-rotates on SVID TTL/2.
- **IN**: gRPC server on internal listener (port 9091) uses fetched SVID as TLS server cert; expects client mTLS cert with allowed SPIFFE-ID matching Cilium AP allowlist.
- **IN**: **Cilium AuthorizationPolicy** yaml in `kacho-deploy`: gates traffic to `iam:9091` by source SPIFFE-ID. Allowlist (initial):
  - `spiffe://kacho.local/ns/kacho/sa/api-gateway`
  - `spiffe://kacho.local/ns/kacho/sa/vpc-controller`
  - `spiffe://kacho.local/ns/kacho/sa/compute-controller`
  - `spiffe://kacho.local/ns/kacho/sa/ui-admin` (UI dev only)
  - `spiffe://kacho.local/ns/kacho/sa/audit-reader` (B.9-related, VL push)
- **IN**: graceful SVID rotation: app re-loads server-TLS-config when SPIRE pushes rotated SVID; existing connections drained or re-handshaken
- **OUT**: external listener (443) mTLS — uses cert-manager + Let's Encrypt per WS-5.5; not SPIFFE
- **OUT**: SPIRE control-plane bootstrap (server, registry, trust-bundle) — W3.3 (per acceptance-reviewer confirmation: W3.3 = full infra wiring including kacho-iam SVID registration; B.10 = mesh protocol policies app-side only)
- **OUT**: JWT-SVID for cross-service auth in HTTP — gRPC mTLS only in v1
- **OUT**: SPIFFE federation across trust-domains — single trust-domain `kacho.local` only

#### Pre-conditions / dependencies

- W3.3 prep: SPIRE charts deployed in kind cluster (`docs/specs/sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md` covers full SPIRE; B.10 is iam-app-side only).

#### Repos touched

| Repo | Files |
|---|---|
| `kacho-iam` | `internal/spiffe/workload_client.go` (NEW — SVID fetch + rotation), `internal/spiffe/tls_config.go` (NEW — build TLS-config from SVID), `cmd/kacho-iam/main.go` (replace plain-listener with SVID-listener for internal port; gated by config `iam.mtls.enabled=true`), `go.mod` (add go-spiffe v2) |
| `kacho-corelib` | possibly promote to `corelib/spiffe/` if vpc/compute will follow same pattern — **NOT yet**; keep in iam for B.10, promote during W3.3 |
| `kacho-proto` | NONE |
| `kacho-deploy` | `helm/kacho-iam/templates/cilium_authorization_policy.yaml` (NEW), `helm/kacho-iam/templates/spiffe_workload_socket.yaml` (NEW — mount SPIRE socket from host), `helm/kacho-iam/values.yaml` (add `mtls.enabled` + `mtls.allowed_spiffe_ids` array) |

#### DB migrations

- **No new migration**.

#### gRPC API surface

- **No new RPC**. Wire-layer change only.

#### GWT scenarios

##### W2.B-B10-01 (positive) — pod fetches SVID + serves internal listener

**Given** SPIRE agent running on node, kacho-iam pod registered with SPIRE
**When** kacho-iam starts with `IAM_MTLS_ENABLED=true`

**Then** within 10s, internal listener (port 9091) serves TLS using SVID-derived server cert
**And** `openssl s_client -showcerts -connect iam:9091` shows cert subject contains `URI:spiffe://kacho.local/ns/kacho/sa/iam`

##### W2.B-B10-02 (positive) — allowed peer (gateway) connects + RPC succeeds

**Given** api-gateway pod with own SVID `spiffe://kacho.local/ns/kacho/sa/api-gateway`; Cilium AP allows that ID
**When** gateway calls `iam-internal:9091/InternalIAMService/Check`

**Then** mTLS handshake succeeds (mutual SPIFFE-ID verified); Check returns response

##### W2.B-B10-03 (negative) — unknown peer SPIFFE-ID → connection refused

**Given** pod with SVID `spiffe://kacho.local/ns/kacho/sa/random-pod` not in allowlist
**When** attempts connect to `iam-internal:9091`

**Then** Cilium AP drops connection at L7 (RST or refused); iam never sees handshake

##### W2.B-B10-04 (negative) — peer with no SVID (plain HTTP) → connection rejected at TLS handshake

**Given** plain HTTP client (no mTLS)
**When** connects to `iam-internal:9091`

**Then** TLS handshake fails («client did not provide certificate»)

##### W2.B-B10-05 (edge) — SVID rotation mid-flight → existing connections survive OR re-handshake

**Given** active gRPC connection from gateway → iam-internal; SPIRE rotates SVID
**When** iam reloads TLS-config

**Then** Either: (a) existing connection survives (TLS session-resume); OR (b) new connection establishes successfully with rotated cert. NEVER hard-fail.

#### B.10.5 Integration tests + Newman cases

| ID | Test name | Type | Coverage |
|---|---|---|---|
| **W2.B-B10-IT-01** | `Test_SPIFFE_WorkloadAPIClient_FetchSVID` | unit (with mock workload API) | B10-01 |
| **W2.B-B10-IT-02** | `Test_SPIFFE_TLSConfig_FromSVID` | unit | B10-01 |
| **W2.B-B10-IT-03** | `Test_SPIFFE_RotationReloadsTLS` | unit | B10-05 |
| **W2.B-B10-E2E-01** | `make e2e-mtls` on kind: gateway→iam Check succeeds, unauthorized pod rejected | e2e (manual smoke) | B10-02..04 |
| **No newman** | mTLS infra-level — newman over plain HTTP cannot exercise mTLS handshake | — | — |

#### Vault entries to update

- `packages/iam-spiffe.md` — NEW; workload API client, SVID rotation, TLS-config builder
- `edges/iam-mtls-internal-listener.md` — NEW; SPIFFE-gated port 9091, allowlist
- `runbooks/mtls-troubleshooting.md` (kacho-deploy) — NEW; common failure modes
- `KAC/KAC-W2.B-10.md` — trail

#### DoD

- [ ] APPROVED B.10 section
- [ ] Branch `KAC-W2.B-10-spiffe-mtls`
- [ ] RED commits per §B.10.5 (3 unit + 1 e2e)
- [ ] GREEN: workload API client, TLS-config builder, rotation handler, Cilium AP yaml, helm wiring
- [ ] All 5 scenarios GREEN (B10-05 verified by manual rotation experiment OR test harness)
- [ ] No TODO/FIXME
- [ ] vault updated (4 entries)
- [ ] **Infra-sensitive data §«Инфра-чувствительные данные» enforcement**: SPIFFE-ID allowlist lives in helm values + Cilium AP yaml + iam config-map (internal); NEVER exposed via public gRPC reflection / proto / API. Acceptance verify: `grpcurl iam-public:443 list` does NOT include InternalIAMService.
- [ ] PR merged

---

## 7. Implementation order recommendation

Per §4 cross-feature interactions: **B.9 audit-pipeline first** because every other B-feature emits audit; without B.9 those events go to no-op and audit-shape assertions break. **B.10 SPIFFE mTLS second** because it gates the internal listener that B.8 InternalCAEPService uses.

Recommended order:

| Pos | Feature | Why |
|---|---|---|
| 1 | **B.9 audit pipeline** | All other features emit audit; B.9 enables audit-shape testing |
| 2 | **B.10 SPIFFE mTLS** | Gates internal listener that B.8 InternalCAEPService + B.2 InternalOrganizationService use; without it, internal RPCs are plain-text |
| 3 | **B.8 CAEP push (egress)** | Required by B.3 expiry, B.4 activate/expire, B.5 revoke, B.7 erasure — they all emit caep_outbox; without drainer those events queue forever |
| 4 | **B.3 JIT-activate** | Foundational ReBAC enterprise feature; sets pattern for B.4/B.5 (state-CAS + fga_outbox + audit + caep). **HARD-BLOCKED by W1.5** |
| 5 | **B.4 break-glass** | Same pattern as B.3 but more complex state-machine + NEW CHECK constraint. **HARD-BLOCKED by W1.5** |
| 6 | **B.5 access-review** | Same pattern + enumeration + deadline worker. **HARD-BLOCKED by W1.5** |
| 7 | **B.7 GDPR erasure** | Independent of B.3/B.4/B.5; depends on B.8 (CAEP) + B.9 (audit) only |
| 8 | **B.6 compliance reports** | Independent; depends on W1.6 #37 visibility provider |
| 9 | **B.1 SAML scaffolding** | Independent; scaffolding only (501-guard until W3.1 #40 wires verify) |
| 10 | **B.2 SCIM** | Independent; gates IdP-driven provisioning path |

**Parallel-safe groups** (no shared file paths, can land concurrently):
- **Group α**: B.9, B.10 (infra)
- **Group β**: B.3, B.4, B.5 (workflow features sharing state-CAS pattern; one merges first sets pattern; **all blocked by W1.5**)
- **Group γ**: B.6, B.7 (independent)
- **Group δ**: B.1, B.2 (provisioning features)

Within each group, sequential per author-bandwidth; between groups, parallel.

---

## 8. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Wave | Recommendation / Resolution |
|---|---|---|---|
| ~~**OQ-W2.B-1**~~ | ~~B.1 SAML library: `crewjam/saml` vs `russellhaering/gosaml2` vs in-house parser~~ | ~~B.1~~ | **RESOLVED — moved to W3.1.** W3.1 DEC-W3.1-3 ratifies `crewjam/saml`. W2.B B.1 (scaffolding only) does NOT use any SAML library — only raw XML body parse via stdlib `encoding/xml`. |
| **OQ-W2.B-2** | B.2 SCIM Basic-auth secret: bcrypt cost factor? | B.2 | 12 (per OWASP 2026 recommendation; balances CPU vs brute-force resistance). |
| **OQ-W2.B-3** | B.3 expiry-worker tick interval | B.3 | 60s (per WS-3.3 baseline; metric `jit_pending_pending_count{}` and `jit_pending_expired_count{}` for monitoring). |
| **OQ-W2.B-4** | B.4 post-incident review SLA — 7d hard or 7d soft (alert-only) | B.4 | 7d soft (alert + audit, NOT block); hard-blocking adds friction without controlled escape valve. Audit retains. |
| **OQ-W2.B-5** | B.5 reviewer-assignment strategy default | B.5 | `account_owner` — simplest; admin can override per-campaign. ROLE_ASSIGNEE_SELF (self-attestation) for low-risk campaigns; EXPLICIT_LIST for high-stakes. |
| **OQ-W2.B-6** | B.6 download URL TTL | B.6 | 5 min — short enough to limit URL-leak window, long enough for download. Configurable via env `IAM_COMPLIANCE_DOWNLOAD_URL_TTL_SECONDS=300`. |
| **OQ-W2.B-7** | B.7 GDPR grace period — 30d (RFC default) or configurable | B.7 | 30d hard-coded per GDPR Art.17.3; configurable would invite legal-non-compliance. |
| ~~**OQ-W2.B-8**~~ | ~~B.8 SET signing — per-subscriber JWK vs cluster-default?~~ | ~~B.8~~ | **RESOLVED — cluster-default in W2.B.** One active CAEP signing key per `oidc_jwks_keys[purpose='caep_sign']` row (cluster-default). Per-subscriber JWK overlay supported by schema (`signing_jwk_kid` nullable FK) but UI/admin tooling = v2 feature. |
| **OQ-W2.B-9** | B.8 retry max attempts | B.8 | 5 attempts with exponential backoff (1s, 5s, 30s, 5min, 30min); total ~36 min. After that → failed_permanent + audit + AM. |
| **OQ-W2.B-10** | B.9 vector.dev config — sidecar (per-pod) or DaemonSet (per-node) | B.9 | **Sidecar** for v1 — simpler per-pod isolation, no cross-tenant log mixing risk; DaemonSet = post-v1 optimization. |
| **OQ-W2.B-11** | B.10 SPIFFE socket mount — host-path vs CSI driver | B.10 | Host-path (`/run/spire/sockets`) — per SPIRE standard deployment; CSI = optional improvement, defer. |
| **OQ-W2.B-12** | B.10 mTLS-enabled default on dev kind cluster? | B.10 | **False** on dev (kind) since SPIRE wiring is in flux until W3.3; **True** on staging/prod via helm-values override. |
| **OQ-W2.B-13** | B.9 audit emitter — flush every line OR batched? | B.9 | Per-line emit to stdout (slog default); vector batches downstream. Batched at app-level = harder to debug + risk of in-process loss on crash. |
| **OQ-W2.B-14** | B.4 break-glass requires MFA-fresh on Approve? | B.4 | **Defer to W3 #23** (mfa-fresh enforcement layer). B.4 audit emit + AM alert provides post-hoc detection; pre-emptive MFA = W3. |
| ~~**OQ-W2.B-15**~~ | ~~Cross-feature: B.7 erasure of user → B.4 break-glass active for that user — what happens?~~ | ~~B.4/B.7~~ | **RESOLVED — erasure executes regardless.** Legal compliance trumps active emergency access. Break-glass grant row remains in `cluster_admin_grants` but effectively unreachable (PII tombstoned → cannot re-authenticate; downstream caches invalidated via `subject_change_outbox change_type='erasure'`). Audit emits BOTH `iam.subject.erasure_completed` AND `iam.breakglass.subject_erased_during_active` for incident-review trail. New GWT scenario **W2.B-B7-06** verifies this; integration test **W2.B-B7-IT-07**. |
| **OQ-W2.B-16** | B.5 enumeration scope — paginate items in batches? | B.5 | Yes — write items in 1000-row batches with progress field; campaign state ENUMERATING → ACTIVE only after all items written. Otherwise huge accounts (10k+ bindings) stall worker tick. |
| **OQ-W2.B-17** | B.6 download URL — HMAC vs JWT? | B.6 | HMAC over compact string (`report_id|expires_at|principal|<hmac>`) — simpler, no JWT-library round-trip; JWT overkill for 5-min one-time URL. |
| **OQ-W2.B-18** | B.8 webhook delivery — egress NetworkPolicy permits which destinations? | B.8 | Per-subscriber endpoint URLs configurable via helm `iam.caep.egress_allowlist` array; default empty (deny all); operators add IdP CIDRs. |
| **OQ-W2.B-19** | Stream A wires REST routes for these features — what's the gRPC-only acceptance signal? | All B | Use `grpcurl --plaintext kacho-iam:9091 ...` against internal listener (mTLS-off in dev); newman uses `tests/newman/lib/grpc_client.py` wrapper. Once Stream A merges, REST routes become available; newman cases switch to REST in W2.D. |
| **OQ-W2.B-20** | B.9 audit field `correlation_id` — propagation from gateway? | B.9 | Use existing `x-request-id` header (gateway sets, slog logs); correlation_id field = `ctx.Value("request_id")`. If missing, generate UUID v7 per-RPC. |

> **Resolution ownership**: `acceptance-reviewer` must answer OQ-W2.B-2/3/9 (impact integration test shape); recommendations on others can be accepted as-is unless reviewer pushes back. OQ-W2.B-1/8/15 already RESOLVED (struck through) per scope split Option Y.

---

## 9. Global DoD (Wave 2 Stream B closure)

- [ ] All 10 per-feature acceptances APPROVED by `acceptance-reviewer`
- [ ] All 10 per-feature DoD checklists ✅ (per §6.X)
- [ ] All cross-feature interactions in §4 verified by integration tests (e.g. B.3 expiry → B.8 SET delivered to test subscriber within 10s; B.7 erasure during active B.4 break-glass via IT-07)
- [ ] `audit_outbox` row emitted for every state-transition in B.3/B.4/B.5/B.7
- [ ] `caep_outbox` row emitted (and drained → subscriber received SET) for: B.3 expiry, B.4 activate, B.4 expire, B.5 revoke, B.7 execute
- [ ] vector.dev sidecar shipping to VL on kind cluster (verify via `curl http://vlogs:9428/select/logsql/query?query=event_type:iam.*`)
- [ ] kacho-iam pod serves internal listener with SPIFFE SVID (kind cluster with SPIRE up, B.10 flag enabled)
- [ ] Cilium AuthorizationPolicy enforced (unauthorized pod cannot connect to iam:9091)
- [ ] `make e2e` smoke on dev-kind passes:
  - SAML ACS endpoint returns 501 (scaffolding scope; W3.1 #40 flips to 302)
  - SCIM POST /Users provisions user
  - JIT activate → grant → expire flow
  - Break-glass A+B → ACTIVE → auto-revoke (with DB CHECK approver-distinctness verified)
  - Access-review schedule → decide → revoke flow
  - Compliance report generate + download
  - GDPR request + cancel + execute (including override-during-break-glass case)
  - CAEP subscriber receives signed SET; subscriber verifies via `/jwks.json`
  - audit visible in VL
  - mTLS internal listener (gateway → iam Check works)
- [ ] kacho-iam CI green (unit + integration + race) across all 10 feature branches
- [ ] kacho-proto: `buf lint`/`buf breaking` zero issues; gen/ regenerated and committed
- [ ] kacho-deploy: `helm template` valid; `make dev-up` succeeds with all B.* features wired
- [ ] **Запрет #5 verification**: `git log --all -- 'project/kacho-iam/internal/migrations/000{1..25}*.sql'` shows NO new commits in W2.B PR series (only NEW migration files added per §3 table)
- [ ] **Запрет #11 verification**: `! git diff main -- '*.go' '*.sql' '*.proto' | grep -E '(TODO|FIXME|XXX)\(.*KAC'` returns empty across all 10 PRs (B.1 501-guard is boundary, not TODO — explicit DOCSTRING marker `// W3.1 #40: replace 501 with verify-callback`, which is documentation, not TODO action)
- [ ] **Newman closing**: post-W2.B baseline ≥ 1300/1300 GREEN (W1.6 closed 87, W2.B adds ~30 cases per features = ~270 new cases all GREEN); W2.D adds remainder
- [ ] All per-feature PRs merged
- [ ] All per-feature vault entries updated; KAC/KAC-W2.B-{1..10}.md trails complete
- [ ] YouTrack subtasks KAC-W2.B-{1..10} → Done
- [ ] W2.B closure note in master plan / W2 column → ✅ Stream B done

---

## 10. Out of scope (явно — следующие waves)

| Что | Куда |
|---|---|
| Stream A — gateway / catalog / spec-drift (#19/#28-34/#38/#44/#45/#49/#1/#3/#4/#5/#6/#7/#14/#15/#27/#46/#55) | **W2.A** (`sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md`) |
| Stream C — API tokens / Block F | **W2.C** |
| Stream D — 13 new newman suites for 100% coverage | **W2.D** |
| W3 federation internals — #21 (CheckRelation), #23 (mfa-fresh), #25 (session-IP), #26 (CheckRelation ctx) | **W3 Chunk 5** (`sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md`) |
| **#40 SAML XML-DSig verify + JIT-provision + saml_request_state migration** | **W3.1 Chunk 5** (this is the W3.1 fix that flips B.1 501 → 302) |
| **#42 CAEP ingress SET signature verify** (`caep_ingress_handler.go::parseSETBody`) | **W3.1 Chunk 5** (different code path from B.8 egress; uses external IdP JWKS, not our `/jwks.json`) |
| SAML XML-DSig deep extensions, encrypted assertions, SLO | **W3** |
| SCIM bulk ops + ETag conditional updates | **post-v1** |
| PDF report rendering for B.6 | **post-v1** |
| S3-backed report storage | **post-v1** |
| MFA-step-up on break-glass approve | **W3 #23** |
| HSM-backed audit signing + Merkle-chain tamper-evidence | **NOT v1** (master decision) |
| Full SPIRE control-plane bring-up | **W3.3** (`docs/specs/sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md`) |
| Kafka/ClickHouse audit pipeline | **NOT v1** (master decision) |
| BG token issuance / one-time URL on break-glass | **post-v1 (FGA grant suffices)** |
| Per-subscriber CAEP JWK overlay UI/admin tooling | **v2** (schema supports it; OQ-W2.B-8 RESOLVED to cluster-default for v1) |

---

## 11. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#2/#5/#6/#8/#9/#10/#11/#12; vault discipline; security-sensitivity; «Within-service refs DB-уровень обязателен»)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` (§W3 row source-of-truth: `#21/#23/#25/#26/#40/#42` — #41 NOT listed → lives in W2.B B.2)
- Production-launch plan: `../superpowers/plans/2026-05-21-production-launch-plan.md` (WS-3, WS-5, WS-6, WS-7)
- Remediation plan: `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` (findings #40 → W3.1 / #41 → W2.B B.2 / #42 → W3.1; #35/#37/#43 — closed in W1.6, gate B-features)
- **KAC-170 review report** (this revision's source): `KAC-170-acceptance-review-report.md` (§«Migration number coordination» + §«Cross-doc scope conflict W2.B ↔ W3.1»)
- **Stream A acceptance** (parallel sibling): `sub-phase-W2.A-stream-a-gateway-catalog-spec-drift-acceptance.md`
- **W3.1 acceptance** (downstream complement for #40/#42): `sub-phase-W3.1-remediation-chunk5-federation-internals-acceptance.md`
- Predecessor acceptance docs:
  - `sub-phase-W1.4-principal-propagation-acceptance.md`
  - `sub-phase-W1.5-remediation-chunk1-fga-grant-write-acceptance.md`
  - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md`
- Existing iam Phase docs (legacy enterprise stubs being completed):
  - `sub-phase-3.6-iam-scim-saml-organization-acceptance.md`
  - `sub-phase-3.7-iam-jit-breakglass-reviews-gdpr-acceptance.md`
  - `sub-phase-3.8-iam-caep-push-acceptance.md`
  - `sub-phase-3.9-iam-audit-pipeline-acceptance.md`
  - `sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md`
- proto contracts: `project/kacho-proto/proto/kacho/cloud/iam/v1/` — `break_glass_service.proto`, `access_review_service.proto`, `compliance_report_service.proto`, `gdpr_erasure_service.proto`, `jit_pending_service.proto`, `caep_subscriber.proto` (existing); NEW `internal_caep_service.proto`, NEW `internal_organization_service.proto` (B.2)
- existing migrations: `project/kacho-iam/internal/migrations/0001_initial.sql` through `0025_nlb_operator_target_manager_roles.sql`; NEW W2.B migrations per §3 table (numbers assigned at impl-start per KAC-170 coordination meta-doc)
- handler dirs: `project/kacho-iam/internal/apps/kacho/api/{saml,scim,break_glass,access_review,compliance_report,gdpr_erasure,jit_pending,internal_iam,caep}/`
- service dirs: `project/kacho-iam/internal/service/{phase7_break_glass_service.go,phase7_access_review_service.go,phase8_caep_drainer.go,gdpr_erasure_service.go,compliance_report_service.go,jit_pending_service.go}`
- Cross-feature: `subject_change_outbox` (W1.2) for cache invalidation; `fga_outbox` (W1.5) for grant atomicity
- Vault entries to update (DoD-listed per-feature; in total ~65+ files across `resources/`, `rpc/`, `edges/`, `packages/`, `KAC/`)

---

**END OF DRAFT v2 — awaiting `acceptance-reviewer` re-review per workspace `CLAUDE.md` §Запреты #1. See KAC-172 for revision tracking.**
