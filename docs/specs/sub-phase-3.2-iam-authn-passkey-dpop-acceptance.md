# Sub-phase 3.2 (IAM AuthN Core — Kratos Passkey + Hydra DPoP + Step-up + Recovery) — Acceptance

> **Статус**: DRAFT
> **Дата**: 2026-05-19
> **Автор**: acceptance-author (Phase 2 / KAC-127)
> **Ревьюер**: acceptance-reviewer
> **Epic**: KAC-127 — Production-Ready Next-Gen IAM (YT KAC-123)
> **Phase**: 2 of 13 (AuthN core)
> **Worktree**: `kacho-workspace-KAC-127/`
> **Branch**: `KAC-127` (per затронутый репо)
> **Design**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` §5 (AuthN flows; token shapes; ACR/step-up matrix; recovery & lifecycle), §13.5 (observability)
> **Plan**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` Phase 2 (tasks 2.1–2.9)
> **Foundation**: `docs/specs/sub-phase-3.1-iam-foundation-acceptance.md` (Phase 1 — `oidc_jwks_keys`, `session_revocations`, `audit_outbox` готовы)

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 2 — второй продуктивный кусок KAC-127 (production edition). На фундаменте Phase 1 (DB-таблицы `oidc_jwks_keys`, `session_revocations`, `audit_outbox`, `caep_outbox`) разворачивается **полный production-grade AuthN-стек**:

1. **ORY Kratos v1.4.x** конфигурируется под:
   - **WebAuthn / Passkey** как primary factor (passwordless=true; conditional UI autofill; user_verification=`required` для ACR=3, `preferred` для ACR=2).
   - **Password fallback** — Argon2id (m=64MB, t=3, p=4 — NIST 800-63B compliant) + Have-I-Been-Pwned (HIBP) range-API check (k-anonymity hash prefix; SHA-1 first 5 chars).
   - **TOTP secondary MFA** — RFC 6238, 6-digit, 30s step, SHA-1 (Authenticator-compat).
   - **Recovery via magic-link** — 5min TTL, single-use (UUID v4 token), IP-bound (X-Forwarded-For check), force re-Passkey enrollment после восстановления.
   - **Identity schema v2** (`kacho_user_v1.json`) — backward-compatible надстройка над KAC-117 baseline schema.
   - **Webhook hooks** — post-registration / post-login → `kacho-iam` `UpsertFromIdentity` + ACR enforcement (require_aal2 / require_aal3).

2. **ORY Hydra v2.4.x** конфигурируется под:
   - **OAuth 2.1 compliant** — Implicit и ROPC grant'ы удалены; AuthCode+PKCE, ClientCredentials, RefreshToken, DeviceCode, JWT-Bearer, TokenExchange (RFC 8693).
   - **DPoP enabled (RFC 9449)** — sender-constrained tokens для public clients (UI / CLI / SDK); cnf.jkt thumbprint validation.
   - **mTLS-bound tokens enabled (RFC 8705)** — для backend M2M (CI/CD, service-to-service вне in-cluster mesh); cnf.x5t#S256 validation.
   - **JWT signing alg whitelist** — RS256, ES256, EdDSA (per-kid pinning); HS256 запрещён (algorithm confusion mitigation); PASETO v4 interface present но disabled.
   - **JWKS rotation 90d** — current + previous keys опубликованы; overlap window = max_access_token_TTL × 2 = 30min minimum.
   - **Refresh token rotation** — family-tracked; reuse detection триггерит family-revoke (RFC 6749 §10.4 + IETF OAuth 2.1 §6.1).
   - **Token TTL** — access 15min / refresh 30d / id_token 15min / auth_code 1min.
   - **Back-channel logout (RFC 8254)** — IdP-initiated logout token → SP receives → session_revocations INSERT.
   - **token_hook + refresh_token_hook** → callback в `kacho-iam` для inject `ext_claims` (active_account, organization_id, principal_type, kacho_device_compliance, kacho_mfa_at).

3. **kacho-api-gateway** получает:
   - **DPoP validator** — strict RFC 9449 compliance (htm/htu match, iat freshness ≤60s, jti replay cache 2min, cnf.jkt thumbprint).
   - **mTLS validator** — RFC 8705 cnf.x5t#S256 thumbprint match против presented client cert.
   - **session_revocations cache** — 5s in-memory + Postgres LISTEN `session_revoked` channel для invalidation ≤1s.
   - **JWT signature validation** — JWKS pulled from Hydra `/.well-known/jwks.json`; cached 24h; force-refresh on `kid` miss.
   - **Algorithm whitelist enforcement** — `alg=none`, HS256, и любые non-whitelisted alg отвергаются с `WWW-Authenticate: Bearer error="invalid_token"`.
   - **Step-up challenge** — при недостаточном ACR returns `401` + `WWW-Authenticate: Bearer error="insufficient_user_authentication", acr_values="3"` (OpenID Connect Core §5.5.1.1).

4. **kacho-iam** получает:
   - **token_hook handler** (`POST /iam/v1/hooks/token`) — Hydra вызывает на каждый token issue; kacho-iam inject ext_claims в JWT before signing.
   - **refresh_token_hook handler** (`POST /iam/v1/hooks/refresh`) — Hydra вызывает на refresh; kacho-iam verifies user enabled + re-issues ext_claims.
   - **UpsertFromIdentity rewrite** (`POST /iam/v1/internal/users:upsertFromIdentity`) — production-grade idempotent: на signup/signin создаёт per-Account User row, активирует PENDING bindings (Phase 1 lifecycle), emit'ит audit events.
   - **JWKS rotation cron worker** — daily check `oidc_jwks_keys`; если current key age > 90d → CTE-rotation (см. Phase 1 §2.6); publish via Hydra-admin `PUT /admin/keys`.

5. **kacho-ui** получает auth-pages production-grade:
   - **SigninPage** — Conditional UI autofill (WebAuthn Level 3); fallback на explicit Passkey ceremony; secondary password+TOTP form.
   - **RegistrationPage** — Passkey primary CTA; password+TOTP secondary CTA; HIBP-feedback на password input.
   - **StepUpModal** — модал переавторизации через Passkey при ACR<required; redirect-back с original request.
   - **RecoveryPage** — магик-линк ввод + force-Passkey enrollment.
   - **BFF token storage** — refresh token в httpOnly secure SameSite=Strict cookie; access token в memory + DPoP-bound (private key non-extractable WebCrypto / IndexedDB).

**Phase 2 НЕ включает** (это Phases 3–13 одного и того же эпика — НЕ "deferred"):

- OpenFGA model v2 deploy + Conditions CEL evaluator + OPA bundle signing — **Phase 3**.
- ListObjects integration per-service — **Phase 4**.
- FederationExchangeService RPC (RFC 8693 Token Exchange) + SA Hydra-clients (Class A IssueKey) — **Phase 5**.
- SCIM 2.0 endpoint + SAML bridge Boxyhq Jackson + Organization-UI — **Phase 6**.
- ActivateJIT RPC + Approval workflow + Break-glass 2-person flow + GDPR erasure cron — **Phase 7**.
- CAEP drainer + SET signing + webhook delivery + exponential backoff (Phase 2 пишет `caep_outbox` rows на admin force-block, но не отправляет webhook'и subscribers'ам) — **Phase 8**.
- Kafka audit topic + ClickHouse + S3+Glacier + HSM batch signing — **Phase 9** (Phase 2 пишет в `audit_outbox`).
- SPIRE/SPIFFE + Cilium service mesh — **Phase 10**.
- Multi-region active-active + Cloudflare WAF + Argo CD — **Phase 11**.
- OWASP ASVS L3 conformance, FIDO Alliance WebAuthn conformance test, OpenID Foundation self-certification — **Phase 12**.
- Vault closeout (30+ files) — **Phase 13**.

Phase 2 — это **production-ready AuthN core**: после merge'а всех 7 PR'ов user может signup через Passkey, получить JWT с `cnf.jkt` DPoP-binding, refresh-rotate безопасно, восстановить аккаунт через magic-link, перейти на ACR=3 для admin-операций, и быть force-logout'нут админом через session_revocations ≤ 1s.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace CLAUDE.md) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать "yandex" | ни в одном handwritten-файле, helm value, env var, error string не упоминается; стилистически error-text следует YC-form ("Illegal argument <thing>", "<Resource> %s not found", "insufficient_user_authentication") — без бренда |
| **Запрет #3** — НЕ ORM | token_hook handler и UpsertFromIdentity в kacho-iam используют sqlc + handwritten pgx; никакого gorm/ent/bun |
| **Запрет #4** — НЕ каскад через границу сервиса | session_revocations / oidc_jwks_keys / audit_outbox — всё в `kacho_iam` DB; api-gateway читает через LISTEN/NOTIFY и REST/gRPC `Internal*` методы, **не** через cross-DB FK |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 2 не добавляет новые миграции в kacho-iam (все таблицы уже созданы Phase 1). Если потребуется ALTER (например, additional column на `oidc_jwks_keys.encryption_kid` для KMS envelope encryption) — отдельный новый файл `0015_kac127_phase2_jwks_encryption.sql` |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | `InternalUserService.UpsertFromIdentity` (port 9091 — internal listener), `InternalIAMService.GetJWKSStatus` (admin observability) — НЕ публикуются на external `api.kacho.cloud:443`. Webhook endpoints Hydra (`/iam/v1/hooks/token`, `/iam/v1/hooks/refresh`) — внутренний listener, доступны только Hydra service-account через cluster-internal DNS (Hydra ↔ kacho-iam без публичного hop'а) |
| **Запрет #7** — НЕ broker, пока in-process справляется | Phase 2 не вводит Kafka — `audit_outbox` пишется в Postgres; LISTEN/NOTIFY на `session_revoked` — in-process для api-gateway cache invalidation. Kafka producer — Phase 9 (audit drainer) |
| **Запрет #8** — DB-per-service | Hydra держит свою `hydra` DB (issuer / oauth_clients / refresh_tokens); Kratos держит свою `kratos` DB (identities / sessions / recovery_codes); kacho-iam — свою `kacho_iam` DB; никаких shared таблиц между сервисами |
| **Запрет #9** — async-only мутации (Operation envelope) | UpsertFromIdentity — **внутренний** webhook (вызывается Hydra/Kratos), не публичный CRUD — допустим synchronous response (это hook-протокол, не public API). Все публичные мутации kacho-iam, появляющиеся в этой phase (нет таковых; Phase 2 — конфигурация инфраструктуры + internal hooks + UI) уже соответствуют контракту |
| **Запрет #10** — within-service refs на DB-уровне | session_revocations INSERT — `INSERT ... ON CONFLICT (token_jti) DO NOTHING` (idempotent); oidc_jwks_keys rotation — CTE single-statement pattern из Phase 1 §2.6 (partial UNIQUE + atomic swap); user upsert — `INSERT ... ON CONFLICT (external_id, account_id) DO UPDATE` (idempotent). Никаких software-side check-then-act |
| **Запрет #11** — тесты в том же PR | каждый из 7 PR'ов содержит integration-tests (testcontainers Postgres + httptest для hooks) + newman cases для black-box validation через api-gateway. Подробный list — §7.1 Definition of Done |
| **Infra-sensitive data** (workspace CLAUDE.md §«Инфра-чувствительные данные») | `oidc_jwks_keys.private_key_pem_encrypted` — internal-only поле; никогда не возвращается через публичный API; admin-observability — только через `InternalIAMService.GetJWKSStatus` (returns public-portion + rotation timestamps) |

---

## 2. Глоссарий / доменная модель Phase 2 (нормативно)

### 2.1 ACR (Authentication Context Class Reference) / AMR (Authentication Methods References)

Стандарт OpenID Connect Core 1.0 §2 — claims в ID Token / Access Token, описывающие силу аутентификации.

| ACR value | Semantic | Required AMR (one of) | NIST 800-63B mapping |
|---|---|---|---|
| `0` | anonymous / public read | — | n/a |
| `1` | low — single-factor non-phishing-resistant | `pwd` (password only) | AAL1 |
| `2` | medium — single-factor phishing-resistant OR multi-factor | `webauthn` (Passkey) OR `pwd`+`mfa` (password+TOTP) | AAL2 |
| `3` | high — phishing-resistant multi-factor with user_verification | `webauthn` (Passkey with user_verification flag=`true`) | AAL3 (hardware-bound passkey ≈ AAL3) |

AMR values are strings per RFC 8176:
- `pwd` — password (Argon2id-hashed in Kratos)
- `webauthn` — WebAuthn / FIDO2 assertion
- `otp` — TOTP (RFC 6238) или HOTP
- `mfa` — generic multi-factor marker
- `user` — user-presence verified (WebAuthn UP flag)
- `uv` — user_verification verified (WebAuthn UV flag)

### 2.2 ACR / step-up matrix (нормативно — из design doc §5.3)

| Operation class | Required ACR | Required AMR (one of) | Example |
|---|---|---|---|
| Anonymous public read | 0 | — | `/.well-known/openid-configuration`, `/healthz` |
| User read on own data | 1 | `pwd` OR `webauthn` | `GET /iam/v1/users/me` |
| User mutate on own resources | 2 | `webauthn` OR `pwd`+`otp` | `POST /vpc/v1/networks` |
| Admin mutate (project/account level) | 2 | `webauthn` OR `pwd`+`otp` | `POST /iam/v1/accessBindings` |
| Cluster-admin actions (Internal RPC) | 3 | `webauthn` + `uv` | `POST /iam/v1/internal/clusterAdminGrants` |
| Break-glass approval | 3 | `webauthn` + `uv` | `POST /iam/v1/internal/breakGlass:approve` |
| GDPR erasure confirm | 3 | `webauthn` + `uv` | `POST /iam/v1/users/{id}:erase` |
| Bulk SCIM operation | 2 | — (service_account validates через mTLS-bound + scope) | `POST /scim/v2/Bulk` |
| SA token issue (own SA in admin project) | 2 | `webauthn` OR `pwd`+`otp` | `POST /iam/v1/serviceAccounts/{id}:issueKey` |
| Federation policy create | 3 | `webauthn` + `uv` | `POST /iam/v1/federations/trustPolicies` |

Required ACR извлекается из `permission_catalog.json` (Phase 1 §2.7 field `required_acr_min`).

### 2.3 Token shapes (нормативно — из design doc §5.1)

**Access Token (JWT, RS256/ES256/EdDSA per signing key; TTL 15min):**

```json
{
  "iss":   "https://hydra.kacho.cloud",
  "sub":   "usr_alice_acc_a1b2",
  "aud":   ["https://api.kacho.cloud"],
  "exp":   1715000900,
  "iat":   1715000000,
  "nbf":   1715000000,
  "jti":   "01HZQ8M5J7QTAEXAMPLEUUIDV7",
  "acr":   "2",
  "amr":   ["webauthn"],
  "auth_time": 1715000000,
  "cnf":   { "jkt": "wztGUf4iz7bRoXPbB1AcRP8Wn4PnFLuKxKsAcUTxDqg" },
  "scope": "openid profile email",
  "ext_claims": {
    "kacho_external_id":       "krt_id_xxx",
    "kacho_active_account":    "acc_a1b2",
    "kacho_organization_id":   null,
    "kacho_groups":            [],
    "kacho_principal_type":    "user",
    "kacho_device_compliance": "attested",
    "kacho_mfa_at":            1715000000
  }
}
```

**Refresh token**: opaque random string (≥ 32 bytes base64url); family-tracked; one-time-use; TTL 30d; family_id stored in Hydra DB.

**DPoP JWT (RFC 9449)** — per-request proof, embedded in `DPoP` HTTP header:

```json
{
  "typ":  "dpop+jwt",
  "alg":  "ES256",
  "jwk":  { "kty": "EC", "crv": "P-256", "x": "...", "y": "..." },
  "htm":  "POST",
  "htu":  "https://api.kacho.cloud/vpc/v1/networks",
  "iat":  1715000000,
  "jti":  "01HZQ8M6KDPOPJTIEXAMPLEUUIDV7"
}
```

**mTLS-bound token (RFC 8705)** — cnf claim instead of jkt:

```json
{ "cnf": { "x5t#S256": "vmXf9WlmmYRhV3VdoTuB1qO1nKgYDz0iiqMxgCxUpzs" } }
```

### 2.4 JWKS rotation invariant (нормативно)

Phase 1 §2.6 зафиксировал DB-уровень. Phase 2 добавляет use-case:

**Worker контракт**:

1. Daily cron (раз в 24h, jittered ±2h) tick.
2. Query `oidc_jwks_keys WHERE current = true ORDER BY alg` — current key per signing algorithm (RS256, ES256, EdDSA).
3. Если `now() - created_at >= 90 days` → rotate this alg.
4. Rotate flow:
   - Generate new keypair (RSA-2048 для RS256; P-256 для ES256; Ed25519 для EdDSA).
   - Encrypt private key с KMS envelope encryption (`private_key_pem_encrypted` — KMS-CMK ciphertext; в dev — простой AES-GCM с `KACHO_IAM_JWKS_ENC_KEY` env).
   - Single-statement CTE (Phase 1 §2.6): UPDATE old SET current=false, rotated_at=now() ... INSERT new ... current=true.
   - PUT `/admin/keys/{set}` (Hydra-admin API) — публикует public-портрет нового ключа.
   - **Grace window**: старый ключ remains `current=false, rotated_at=now()` ещё 30min (`= access_token_TTL × 2 = 15min × 2`).
   - Через 30min separate cleanup-pass — DELETE keys WHERE rotated_at < now() - interval '30 minutes' (additional safety: keep last 1 historical key per alg, чтобы не сломать клиенты со stale `kid`).
5. Hydra `/.well-known/jwks.json` показывает **current + previous** keys per alg (overlap window).

**Bootstrap (Phase 2 first run)** — `oidc_jwks_keys` пустая после Phase 1; worker на старте:
- Если `count(*) FILTER (WHERE alg=$alg AND current=true) = 0` → simple INSERT (не CTE; partial UNIQUE разрешает первую row).
- Bootstrap'ит все 3 algs (RS256, ES256, EdDSA) — Hydra ConfigMap указывает default = ES256.

### 2.5 Session revocation cache invariant (нормативно)

API-gateway держит in-memory cache `session_revocations` для O(1) lookup на каждом запросе:

```
type SessionRevocationCache struct {
    mu       sync.RWMutex
    revoked  map[string]struct{}        // token_jti → present means revoked
    notifyCh chan struct{}              // Postgres LISTEN trigger
    db       *pgxpool.Pool
}
```

**Invalidation protocol**:

1. Admin / CAEP receiver INSERT row в `session_revocations(token_jti, revoked_at, reason)`.
2. `pg_notify('session_revoked', token_jti)` — fired in same TX (LISTEN/NOTIFY trigger after INSERT).
3. Все api-gateway pods, имеющие `LISTEN session_revoked` connection, получают notification ≤ 100ms (network-latency-bound).
4. Cache добавляет jti в `revoked` map в ≤ 1ms.
5. **End-to-end SLA**: `INSERT → token rejected` ≤ 1s p95 (production target: ≤ 500ms p95).

**Cold-start / reconnect**:
- API-gateway pod start → SELECT all `token_jti FROM session_revocations WHERE revoked_at > now() - interval '15 minutes'` (window = access_token_TTL); bulk-load в map.
- LISTEN reconnect (network blip) → trigger full re-sync (same SELECT).

**TTL / cleanup**:
- Cleanup job: DELETE FROM session_revocations WHERE revoked_at < now() - interval '24 hours' (overlap для recently-issued tokens; access_token_TTL=15min, refresh=30d — но revocation list нужна только пока access token valid; refresh revoke — отдельно через Hydra-admin `DELETE /oauth2/auth/sessions/login`).

### 2.6 DPoP replay cache invariant (нормативно)

API-gateway держит cache для DPoP `jti` values для replay-protection (RFC 9449 §11.1):

```
type DPoPReplayCache struct {
    // LRU + TTL; capacity 100K entries; entry TTL = 120s (2× iat freshness window).
    cache *lru.Cache[string, time.Time]
}
```

**Replay protection invariant**:
- DPoP JWT содержит `jti` (UUID v7).
- На каждый incoming request:
  1. Parse DPoP header → extract `jti`.
  2. `cache.Add(jti, time.Now())` — if `jti` already present (returns `evicted=false` for existing entry) → **reject with 401 invalid_dpop_proof**.
  3. Entries expire через 120s; новые запросы со старым jti после expiry — также reject'нутся, потому что `iat` freshness check (≤60s) тоже fails.

**Distributed concern**: multi-pod api-gateway — каждый pod держит свой LRU. Атакующий, попавший на другой pod с replay'д jti, обойдёт detection на этом pod'е. **Mitigation в Phase 2**: rely на iat freshness (≤60s) + sticky-session (если есть). **Production-grade fix в Phase 10**: shared Redis для DPoP replay cache (но пока не вводим Redis — запрет #7; in-memory LRU + iat freshness покрывает 99% threat model'а; survivable risk).

### 2.7 Step-up flow (нормативно)

OpenID Connect Core 1.0 §3.1.2.1 + RFC 9470 (OAuth 2.0 Step-up Authentication Challenge Protocol):

**Sequence**:

1. Client отправляет request с access_token имеющим `acr="2"`.
2. API-gateway видит permission `required_acr_min="3"` для этого RPC.
3. API-gateway отвергает request:
   ```
   HTTP/1.1 401 Unauthorized
   WWW-Authenticate: Bearer error="insufficient_user_authentication",
       error_description="Required ACR 3 for this resource; presented ACR 2",
       acr_values="3"
   ```
4. Client (UI) parses `WWW-Authenticate`; opens StepUpModal.
5. User triggers Passkey ceremony с user_verification=`required`.
6. Kratos: WebAuthn assertion verified → session AAL bumped to 3.
7. Hydra: re-issue access token с `acr="3"`, `amr=["webauthn","uv"]`.
8. UI re-plays original request с новым token → succeeds.

**Original-request preservation**: UI хранит pending request в memory (не localStorage — XSS risk); после step-up — restore + re-fire.

### 2.8 Recovery flow (нормативно)

**User forgot all factors**:

1. User clicks "Forgot password / Passkey?" → RecoveryPage.
2. Inputs email → kacho-iam → Kratos `/self-service/recovery` API → generates magic-link.
3. Email sent с link `https://app.kacho.cloud/recovery?token=<uuid-v4>`.
4. **Link invariants**:
   - TTL = 5min from issuance.
   - Single-use (Kratos marks code as used on first redemption).
   - IP-bound — Kratos records issuing IP; on redemption verifies X-Forwarded-For === issuing IP (Phase 2 — **strict** exact-match; relaxed /24-subnet match — explicit scope of Phase 12 post-pentest hardening, см. §10 Q5).
5. User clicks link → Kratos validates → session bumped to AAL1 (recovery-elevated).
6. **Force enrollment**: kacho-ui после recovery success требует add new Passkey (заменить старый, потерянный) ИЛИ verify backup-code (если был сохранён).
7. После successful Passkey enrollment — session bumped to AAL2/3; old Passkey credentials REMOVED (`DELETE FROM kratos.identity_credentials WHERE identity_id = $1 AND type = 'webauthn' AND id != $new`).
8. **Audit event**: `iam.user.recovery.completed` written в `audit_outbox`.
9. **CAEP push**: invalidate all existing sessions for this user (revoke refresh tokens; INSERT `session_revocations` для всех active access tokens — discovered через Hydra-admin `GET /admin/sessions/login?subject=...`).

**Failure modes**:
- TTL exceeded → Kratos returns `400 invalid_or_expired_code`.
- Single-use violated → `400 code_already_used`.
- IP mismatch → `400 ip_changed_during_recovery`.

### 2.9 Refresh token rotation + family-revoke (нормативно)

RFC 6749 §10.4 + OAuth 2.1 §6.1:

**State**:
- Each refresh token has `family_id` (UUID generated at initial token issuance).
- Each new refresh-via-rotation gets same `family_id`, new `id` and `previous_id` (link to predecessor).

**Happy path**:
1. Client presents `refresh_token=A` (family=F).
2. Hydra: A valid, marks A as used (`used_at=now()`), issues new `B` (family=F, previous=A).
3. Client uses B going forward.

**Reuse-detection (attack scenario)**:
1. Attacker steals A; legit client also has A.
2. Both attempt refresh с A.
3. First request wins → B issued.
4. Second request с A → Hydra видит `used_at IS NOT NULL` for A → **family-revoke**: DELETE all tokens WHERE family_id = F.
5. Both legit и attacker теперь locked out; user должен заново signin.
6. Audit event: `authn.refresh.family_revoked` с reason=`reuse_detected`.

**Concurrent legit refresh**:
- Client app instance #1 и #2 (same user, two tabs) — оба имеют access token close to expiry, оба refresh одновременно с A.
- Race: оба запроса reach Hydra; first wins (UPDATE refresh_tokens SET used_at=now() WHERE id=A AND used_at IS NULL RETURNING ...).
- Second получает 0 rows → 400 invalid_grant.
- **Не triggers** family-revoke в этом случае (Hydra distinguishes "race-during-rotation" vs "reuse-after-rotation": race-during = both arrived within ≤ 1s of each other → 400 only; reuse-after = A used > 1s ago → family-revoke).
- В Phase 2 принимаем Hydra default behavior (force-rotate=true; reuse-grace-window=1s).

### 2.10 Back-channel logout (RFC 8254)

**IdP-initiated logout**:

1. Admin invokes `POST /iam/v1/internal/users/{id}:forceLogout`.
2. kacho-iam:
   - Calls Hydra-admin `DELETE /oauth2/auth/sessions/login?subject={user_id}` — invalidates all sessions for user.
   - For each active access token (queried from Hydra introspection): INSERT into `session_revocations(token_jti, revoked_at, reason='force_logout')`.
   - Hydra sends **logout_token** (RFC 8254 §2.4) to each registered SP backchannel_logout_uri.
   - SPs (kacho-ui via BFF) receive logout_token, verify signature, clear local session.
3. Audit event: `iam.user.force_logout` в `audit_outbox`.

**Logout token format** (signed JWT):

```json
{
  "iss":    "https://hydra.kacho.cloud",
  "sub":    "usr_alice_acc_a1b2",
  "aud":    "<client_id>",
  "iat":    1715000000,
  "jti":    "01HZQ8M7LOGOUTEXAMPLEUUIDV7",
  "events": { "http://schemas.openid.net/event/backchannel-logout": {} },
  "sid":    "<session_id>"
}
```

---

## 3. Decision Log (Phase 2 specific)

> Колонка «Maps to global D-N» — трассировка на design doc `2026-05-19-iam-prod-ready-next-gen-design.md` §1 (D-1..D-28). `—` означает Phase-2-specific решение без прямого соответствия.

| # | Decision | Rationale | Maps to global D-N |
|---|---|---|---|
| P2-D1 | **WebAuthn `passwordless=true` (Passkey-first) в Kratos config** — Passkey primary factor, не secondary | Phishing-resistant из коробки; UX лучше password+TOTP; FIDO Alliance state-of-the-art 2025; password оставлен как fallback в случаях, когда device лост и нет backup Passkey | D-2 (AuthN production-flows) |
| P2-D2 | **`user_verification=required` для ACR=3**, `preferred` для ACR=2 | RFC 8176 + NIST 800-63B AAL3: hardware-bound + biometric = AAL3-eligible; для ACR=2 хватает user_presence (UP flag) | D-2 |
| P2-D3 | **Password fallback — Argon2id (m=64MB, t=3, p=4)** | NIST 800-63B рекомендация; OWASP Password Storage Cheat Sheet baseline 2024; Kratos default уже Argon2id, нам нужно только убедиться в parameters | D-2 |
| P2-D4 | **HIBP check на password input** — range-API (k-anonymity prefix) | OWASP A07:2021 Identification & Authentication Failures; range-API не отправляет полный hash, только SHA-1 prefix (5 chars) | — |
| P2-D5 | **TOTP secondary fallback (RFC 6238)** — для users без Passkey-capable device | Backward compat; не primary path; password+TOTP = AMR `["pwd","otp","mfa"]` → ACR=2 | D-2 |
| P2-D6 | **DPoP (RFC 9449) для public clients**, **mTLS-bound (RFC 8705) для backend M2M** | Sender-constrained tokens защищают от token theft (XSS, log leak); DPoP — public clients (UI / CLI / mobile); mTLS — backend (CI/CD, k8s ServiceAccounts с pinned client cert); SPIFFE SVID (Phase 10) заменит mTLS-bound для in-cluster | D-2 |
| P2-D7 | **JWT alg whitelist: RS256 + ES256 + EdDSA** — explicit pinning per-kid; `none` / HS256 hard-rejected | RFC 8725 §2.1 + algorithm confusion CVE-2015-9235 (jsonwebtoken lib bug history); per-kid alg pinning (JWKS publishes `kid` → `alg`; validator enforces) — defense-in-depth | D-2 |
| P2-D8 | **PASETO v4 — interface present, disabled в Phase 2** | PASETO лучше JWT (no alg field, pre-fixed cipher), но industry — JWT; интерфейс готовится в gateway для future migration без breaking | D-2 |
| P2-D9 | **Refresh-token rotation enforced + family-revoke on reuse** | OAuth 2.1 §6.1 mandate; Hydra default behavior; reuse-grace-window=1s (Hydra default) принимаем (race vs attack distinguishable) | D-2 |
| P2-D10 | **JWKS rotation 90d (current+previous)** | Industry baseline (Google, Auth0, Okta); overlap = `access_token_TTL × 2 = 30min`; daily cron jitter ±2h spread'ит rotation load | D-2 |
| P2-D11 | **Hydra token_hook + refresh_hook → kacho-iam** (synchronous HTTP, NOT async) | Hydra requires synchronous response (timeout 5s default; if hook fails → token issue fails — fail-closed); ext_claims нужны in-line при signing; не Operation envelope (это hook-protocol, не public API) | — |
| P2-D12 | **UpsertFromIdentity — InternalUserService на port 9091** (cluster-internal) | Hydra ↔ kacho-iam communication — внутренний listener (не публичный endpoint); CLAUDE.md запрет #6 + #6 admin-UI правило | D-2 |
| P2-D13 | **Session revocation cache 5s TTL + Postgres LISTEN/NOTIFY invalidation** | LISTEN/NOTIFY достаточно для in-cluster (запрет #7 — не Kafka); 5s TTL — fallback если NOTIFY connection drop'нулся; cold-start bulk-load из DB | D-19 (CAEP storage) |
| P2-D14 | **Magic-link recovery: 5min TTL + IP-bound + single-use + force re-Passkey** | NIST 800-63B 4.7.1 + OWASP Forgot Password Cheat Sheet; force re-enrollment гарантирует что lost device не остался valid factor; IP-bind mitigates email-interception (если attacker украл email-link, но он не в том же IP — reject) | D-2 |
| P2-D15 | **Step-up via `acr_values=3` challenge** (RFC 9470) | Standards-based; OIDC Core §5.5.1.1; SPI-агностик: любой OIDC-compliant SP может trigger step-up | — |
| P2-D16 | **DPoP replay cache — in-memory LRU per-pod (NOT shared Redis в Phase 2)** | Запрет #7 (no broker / no Redis); in-memory LRU + `iat` freshness (≤60s) покрывает 99% threat model; cross-pod replay possible но window ≤ 60s — survivable; Phase 10 (mesh) добавит shared cache через Cilium-backed Redis-equivalent | — |
| P2-D17 | **CAEP outbox writes в Phase 2, drainer/webhook delivery — Phase 8** | Phase 1 создала `caep_outbox` таблицу; Phase 2 пишет события `force_logout` / `recovery_completed`; Phase 8 добавит drainer + signed SET delivery — Phase 2 не блокируется отсутствием webhook subscribers | D-19 |
| P2-D18 | **Audit outbox writes в Phase 2, Kafka producer — Phase 9** | Phase 1 создала `audit_outbox`; Phase 2 emit'ит `authn.signin.success` / `authn.signin.failure` / `iam.user.created` / `iam.user.recovery.completed` / `iam.user.force_logout` / `authn.refresh.family_revoked` rows; Phase 9 добавит Kafka producer + ClickHouse consumer | D-20 |
| P2-D19 | **kacho-ui BFF pattern: refresh token в httpOnly cookie, access в memory** | OWASP SPA Security Cheat Sheet 2024; httpOnly + Secure + SameSite=Strict cookie защищает refresh от XSS exfiltration; access token в memory (не localStorage) — короткий TTL, XSS-replayable но требует active session window | — |
| P2-D20 | **DPoP private key в IndexedDB (non-extractable WebCrypto)** | WebCrypto API позволяет `extractable=false` для ECDSA P-256 key; private key никогда не покидает browser sandbox; IndexedDB используется для persistence между tabs / page reloads | — |
| P2-D21 | **kacho_user_v1.json identity schema** — extends KAC-117 baseline без breaking | Phase 1 не менял `users` table (no-change note §2.1); Phase 2 identity schema **только описывает traits**, не меняет DB schema kacho-iam (Kratos identity_credentials — отдельная Kratos DB; mapping в `kacho_iam.users` идёт через `external_id`) | — |
| P2-D22 | **JWKS private key encryption — KMS envelope в prod, AES-GCM с env-key в dev** | Phase 11 финализирует KMS integration (AWS KMS / GCP KMS / cosign); Phase 2 in dev — простой AES-GCM с `KACHO_IAM_JWKS_ENC_KEY` (32-byte hex); production helm-values.prod.yaml mounts KMS-CMK ARN | D-2 |
| P2-D23 | **Algorithm-confusion mitigation: hard-rejection `alg=none`, HS256 без HMAC-context, `kid` без матча в JWKS** | RFC 8725 §2.1 + CVE-2015-9235; validator проверяет alg ∈ whitelist ДО любого crypto-op; HS256 принципиально нет в whitelist (asymmetric only); `kid` missing → reject (no fallback to "first key") | D-2 |
| P2-D24 | **Newman + Playwright + k6 — все 3 test pyramid'а в Phase 2** | Newman: black-box через api-gateway (auth flows happy/negative); Playwright: e2e UI (Passkey ceremony симулируется через CDP virtual-authenticator); k6: token-validation latency SLA (p95 ≤ 5ms per request на pre-warmed JWKS cache) | — |

---

## 4. Target architecture (компактно)

```
                           User browser (kacho-ui SPA)
                                        │
                                        │ 1. Signup/Signin via SigninPage / RegistrationPage
                                        ▼
                           ┌────────────────────────────┐
                           │   ORY Kratos (v1.4.x)      │
                           │   - WebAuthn / Passkey     │
                           │   - Password fallback      │
                           │   - TOTP secondary         │
                           │   - Recovery magic-link    │
                           │   - Identity schema v2     │
                           │   - Kratos DB (Postgres)   │
                           └────────────┬───────────────┘
                                        │ 2. Webhook post-registration / post-login
                                        ▼
                           ┌────────────────────────────┐
                           │   kacho-iam                │
                           │   - /iam/v1/internal/      │
                           │       users:upsertFromId   │
                           │   - /iam/v1/hooks/token    │
                           │   - /iam/v1/hooks/refresh  │
                           │   - JWKS rotation cron     │
                           │   - kacho_iam DB           │
                           └────────────┬───────────────┘
                                        │ 3. OAuth2.1 authorize / token / refresh
                                        ▼
                           ┌────────────────────────────┐
                           │   ORY Hydra (v2.4.x)       │
                           │   - OAuth 2.1 + OIDC       │
                           │   - DPoP (RFC 9449)        │
                           │   - mTLS-bound (RFC 8705)  │
                           │   - JWKS (current+prev)    │
                           │   - Back-channel logout    │
                           │   - Hydra DB (Postgres)    │
                           └────────────┬───────────────┘
                                        │ 4. token_hook → kacho-iam (inject ext_claims)
                                        │ 5. JWT signed; refresh_token issued
                                        ▼
                           User browser receives:
                             - access_token (JWT, in memory)
                             - refresh_token (httpOnly cookie via BFF)
                             - DPoP private key (IndexedDB, non-extractable)
                                        │
                                        │ 6. Every request: Authorization: DPoP <jwt> + DPoP: <dpop-jwt>
                                        ▼
                           ┌────────────────────────────┐
                           │   kacho-api-gateway        │
                           │   - JWT validator          │
                           │   - DPoP validator         │
                           │     (htm/htu/iat/jti/jkt)  │
                           │   - mTLS validator (RFC8705)│
                           │   - session_revocations    │
                           │     cache (5s + LISTEN)    │
                           │   - DPoP replay cache (LRU)│
                           │   - Step-up challenge      │
                           │     (WWW-Authenticate)     │
                           └────────────┬───────────────┘
                                        │ 7. Forward с gRPC metadata principal
                                        ▼
                           ┌────────────────────────────┐
                           │   Backend services         │
                           │   (kacho-vpc / compute /…) │
                           └────────────────────────────┘

  Async-pipeline (Phase 2 пишет rows; drainers — Phase 8/9):
    audit_outbox    ← authn.signin.success / .failure / iam.user.created / ...
    caep_outbox     ← force_logout / recovery_completed
    session_revocations ← admin-force-block + recovery-cascade
```

---

## 5. Декомпозиция по компонентам

### 5.1 kacho-deploy — Kratos config

- **`helm/umbrella/charts/kacho-iam/templates/kratos-config-configmap.yaml`** (modified):
  - Selfservice flows: registration / login / settings / recovery / verification enabled.
  - Methods enabled:
    - `webauthn`: `enabled: true`, `passwordless: true`, `rp.id: app.kacho.cloud`, `rp.origin: https://app.kacho.cloud`, `rp.display_name: "Kachō Cloud"`.
    - `password`: `enabled: true`, `min_password_length: 8`, `identifier_similarity_check_enabled: true`, `haveibeenpwned_enabled: true`, `haveibeenpwned_host: api.pwnedpasswords.com`.
    - `totp`: `enabled: true`, `issuer: "Kachō Cloud"`.
    - `lookup_secret` (backup-codes): `enabled: true`.
  - Identity schema URL: `file:///etc/config/kratos/identity.schema.json` (mounted from sibling ConfigMap).
  - Recovery: `enabled: true`, `lifespan: 5m`, `use: code` (magic-link).
  - Hooks:
    - `post.registration.hooks`: `[{hook: web_hook, config: {url: 'http://kacho-iam.kacho-system.svc.cluster.local:9091/iam/v1/internal/users:upsertFromIdentity', method: POST, auth: {type: api_key, config: {name: X-Kacho-Hook-Token, value: '$KACHO_IAM_HOOK_TOKEN', in: header}}}}, {hook: show_verification_ui}]`.
    - `post.login.hooks`: `[{hook: web_hook, config: {url: 'http://kacho-iam.kacho-system.svc.cluster.local:9091/iam/v1/internal/users:upsertFromIdentity', method: POST, auth: ...}}, {hook: require_verified_address}]`.
    - `post.recovery.hooks`: `[{hook: revoke_active_sessions}, {hook: web_hook, config: {url: '.../iam/v1/internal/users:onRecoveryCompleted', ...}}]`.

- **`helm/umbrella/charts/kacho-iam/configmaps/kratos-identity-schema.yaml`** (new):
  - `identity.schema.json` v2 — extends KAC-117 baseline:
    ```json
    {
      "$id": "https://schemas.kacho.cloud/identity/v2",
      "$schema": "http://json-schema.org/draft-07/schema#",
      "title": "Kachō User Identity v2",
      "type": "object",
      "properties": {
        "traits": {
          "type": "object",
          "properties": {
            "email":  { "type": "string", "format": "email", "ory.sh/kratos": { "credentials": { "password": {"identifier": true}, "webauthn": {"identifier": true} }, "verification": {"via": "email"}, "recovery": {"via": "email"} } },
            "display_name": { "type": "string", "minLength": 1, "maxLength": 128 }
          },
          "required": ["email"],
          "additionalProperties": false
        }
      }
    }
    ```

### 5.2 kacho-deploy — Hydra config

- **`helm/umbrella/values.dev.yaml`** + **`helm/umbrella/values.prod.yaml`** — Hydra subchart values block:
  ```yaml
  hydra:
    config:
      urls:
        self:
          issuer: https://hydra.kacho.cloud
          public: https://hydra.kacho.cloud
        login: https://app.kacho.cloud/auth/login
        consent: https://app.kacho.cloud/auth/consent
        logout: https://app.kacho.cloud/auth/logout
      ttl:
        access_token: 15m
        refresh_token: 720h        # 30 days
        id_token: 15m
        auth_code: 1m
      strategies:
        access_token: jwt
        jwt:
          scope_claim: list
      oauth2:
        grant:
          jwt:
            iat_optional: false
            jti_optional: false
            max_ttl: 720h
          authorization_code:
            require_pkce: true
            ttl: 1m
        token_hook:
          url: http://kacho-iam.kacho-system.svc.cluster.local:9091/iam/v1/hooks/token
          auth:
            type: api_key
            config:
              in: header
              name: X-Kacho-Hook-Token
              value: $KACHO_IAM_HOOK_TOKEN
        refresh_token_hook:
          url: http://kacho-iam.kacho-system.svc.cluster.local:9091/iam/v1/hooks/refresh
          auth:
            type: api_key
            config:
              in: header
              name: X-Kacho-Hook-Token
              value: $KACHO_IAM_HOOK_TOKEN
        refresh_token_rotation: true
        refresh_token_rotation_grace_period: 1s
        exclude_not_before_claim: false
        client_credentials:
          default_grant_allowed_scope: false
        dpop:
          enabled: true
          signing_algorithms: [ES256, EdDSA]
          iat_skew_tolerance: 60s
        mtls:
          enabled: true
          cnf_thumbprint_algorithm: SHA-256
      webfinger:
        jwks:
          broadcast_keys: [kacho-rs256-current, kacho-rs256-previous, kacho-es256-current, kacho-es256-previous, kacho-eddsa-current, kacho-eddsa-previous]
      log:
        level: info
        leak_sensitive_values: false
      tracing:
        provider: otel
        providers:
          otlp:
            endpoint: otel-collector.observability.svc.cluster.local:4317
            insecure: true
    secrets:
      cookie: $KACHO_HYDRA_COOKIE_SECRET
      system: $KACHO_HYDRA_SYSTEM_SECRET
  ```
  - Removed grants по умолчанию через `strategies.access_token=jwt` + explicit `oauth2.grant.authorization_code.require_pkce=true`; Implicit и ROPC отключаются через absence в `oauth2.grant.*` блоке (Hydra v2.4 default: оба disabled если не configured).

### 5.3 kacho-api-gateway — DPoP/mTLS validation

- **Modify `internal/auth/jwt_validator.go`** — добавить:
  - Алгоритм whitelist `{RS256, ES256, EdDSA}` (explicit; `alg=none`/`HS*` reject).
  - Per-kid alg pinning (если JWT alg ≠ jwks-entry alg для same kid → reject).
  - DPoP-mode detection (если `Authorization: DPoP <jwt>` schema instead of `Bearer`).
- **Create `internal/auth/dpop_validator.go`** (new):
  - `Validate(ctx, dpopJWT, accessToken, request) error`:
    1. Parse DPoP JWT header (typ=`dpop+jwt`, alg ∈ {ES256, EdDSA}; reject иначе).
    2. Extract embedded `jwk`; verify DPoP JWT signature.
    3. Compute thumbprint `jkt = base64url(SHA-256(canonical-jwk))` (RFC 7638).
    4. Compare с `accessToken.cnf.jkt` → если mismatch → reject.
    5. Validate `htm == request.Method`; `htu == canonical-htu(request.URL)` (RFC 9449 §4.1; htu без query/fragment).
    6. Validate `iat` freshness: `|now - iat| ≤ 60s`.
    7. Check `jti` в `DPoPReplayCache`: если present → reject; иначе add (TTL 120s).
- **Create `internal/auth/mtls_validator.go`** (new):
  - `Validate(ctx, accessToken, clientCert) error`:
    1. Если access token имеет `cnf.x5t#S256` → mTLS-bound mode.
    2. Compute `x5t#S256 = base64url(SHA-256(clientCert.Raw))`.
    3. Compare → если mismatch → reject.
    4. Если client cert не presented но token mTLS-bound → reject.
- **Create `internal/auth/session_revocations_cache.go`** (new):
  - `Init(ctx, db) error`: bulk-load `SELECT token_jti FROM session_revocations WHERE revoked_at > now() - interval '15 minutes'`; start `LISTEN session_revoked` goroutine; on NOTIFY add jti to map.
  - `IsRevoked(jti) bool`: O(1) map lookup.
  - Reconnect-loop с exponential backoff; on reconnect full re-sync.
- **Modify `internal/auth/middleware.go`**:
  - Step-up: если `requiredACR > token.acr` → return 401 с `WWW-Authenticate: Bearer error="insufficient_user_authentication", acr_values="<required>"`.
  - Required ACR извлекается из `permission_catalog.json` (Phase 1) для текущей RPC FQN.

### 5.4 kacho-iam — token_hook + refresh_hook handlers

- **Create `internal/apps/kacho/api/hydra/token_hook.go`** (new):
  - HTTP handler `POST /iam/v1/hooks/token`.
  - Bearer `X-Kacho-Hook-Token` validated против env `KACHO_IAM_HOOK_TOKEN` (shared secret Hydra ↔ kacho-iam).
  - Parse Hydra hook payload (per Hydra docs: `session.access_token`, `session.id_token`, `request.client_id`, `request.granted_scopes`, `subject`).
  - Lookup `users` table by `external_id` (== Kratos identity sub).
  - Resolve `active_account` (если user has multi-Account membership; default: first ACTIVE binding).
  - Resolve `organization_id` (через `accounts.organization_id`; NULL если personal).
  - Resolve `principal_type` (`user` если sub matches users.external_id; `service_account` если matches service_accounts.id).
  - Resolve `device_compliance` (Phase 2: всегда `attested` если webauthn used, `unknown` otherwise; full attestation chain — Phase 12).
  - Resolve `mfa_at` (от session.auth_time).
  - Return JSON:
    ```json
    {
      "session": {
        "access_token": {
          "ext_claims": {
            "kacho_external_id":       "<external_id>",
            "kacho_active_account":    "<acc_id>",
            "kacho_organization_id":   "<org_id_or_null>",
            "kacho_groups":            [],
            "kacho_principal_type":    "user",
            "kacho_device_compliance": "attested",
            "kacho_mfa_at":            <unix_ts>
          }
        }
      }
    }
    ```
  - Audit emit: `authn.token.issued` в `audit_outbox` (idempotent ON CONFLICT (request_jti) DO NOTHING).
- **Create `internal/apps/kacho/api/hydra/refresh_hook.go`** (new):
  - HTTP handler `POST /iam/v1/hooks/refresh`.
  - Lookup user; verify `enabled=true` (если admin force-blocked — reject с `403 user_disabled` → Hydra пропагирует как `invalid_grant`).
  - Re-issue ext_claims (same as token_hook).
  - Audit emit: `authn.refresh.issued`.

### 5.5 kacho-iam — UpsertFromIdentity rewrite

- **Rewrite `internal/apps/kacho/api/user/internal_upsert.go`**:
  - HTTP handler `POST /iam/v1/internal/users:upsertFromIdentity` (Internal listener port 9091).
  - Request body (Kratos webhook format):
    ```json
    {
      "identity": {
        "id":     "<kratos_uuid>",
        "traits": { "email": "alice@example.com", "display_name": "Alice" },
        "schema_id": "kacho_user_v1",
        "verifiable_addresses": [{"value": "alice@example.com", "verified": true}]
      },
      "flow":  { "id": "<flow_id>", "type": "registration|login|recovery" }
    }
    ```
  - Use-case `UpsertFromIdentity`:
    1. Lookup `users WHERE external_id = $kratos_uuid` (per-Account row может быть N).
    2. Если ни одной row → first-time registration:
       - Call `BootstrapWorker` (existing from KAC-117/125): create default `Account` + `Project` + `admin-binding` (`access_bindings.status='ACTIVE'`).
       - INSERT `users(id, account_id, external_id, email, display_name, invite_status='ACTIVE', created_at=now())`.
       - Emit `iam.user.created` в `audit_outbox`.
    3. Если есть row(s):
       - UPDATE `email` / `display_name` если changed (Kratos source-of-truth).
       - Активировать PENDING bindings: `UPDATE access_bindings SET status='ACTIVE', activated_at=now() WHERE subject_type='user' AND subject_id IN (<user ids>) AND status='PENDING'` (Phase 1 lifecycle).
       - Emit `iam.user.activated` (если any PENDING → ACTIVE).
    4. Emit `authn.signin.success` audit row (для flow.type='login').
  - Idempotency: вся операция в одной TX; ON CONFLICT (external_id, account_id) DO UPDATE.
  - Response: `200 OK` пустой (Kratos hooks не требуют payload).

### 5.6 kacho-iam — JWKS rotation cron worker

- **Create `internal/apps/kacho/jobs/jwks_rotator.go`** (new):
  - Goroutine, started в `cmd/kacho-iam/main.go` wiring; tick interval = 1h (jittered ±10min).
  - On each tick:
    1. Query `oidc_jwks_keys WHERE current = true GROUP BY alg` (one row per alg).
    2. Для каждого alg в {`RS256`, `ES256`, `EdDSA`}:
       - Если row не существует → bootstrap (INSERT new key с `current=true`).
       - Если row exists и `now() - created_at >= 90 days` → rotate:
         - Generate new keypair (RSA-2048 / EC P-256 / Ed25519).
         - Encrypt private_key_pem через `KACHO_IAM_JWKS_ENC_KEY` AES-GCM (dev) / KMS (prod).
         - Execute CTE single-statement (Phase 1 §2.6).
         - POST `/admin/keys/hydra.openid.id-token` (Hydra-admin endpoint) — publish public portion of new key.
         - Emit `iam.jwks.rotated` audit row.
    3. Cleanup pass: `DELETE FROM oidc_jwks_keys WHERE rotated_at < now() - interval '30 minutes' AND current = false` (keep current + last 1 previous; older deleted).
  - Production-grade: `pg_advisory_lock(0xJWKS_LOCK_ID)` обеспечивает что только 1 pod выполняет rotation одномоментно (HA-safe).

### 5.7 kacho-ui — Auth pages

- **Modify `src/pages/auth/SigninPage.tsx`**:
  - On mount: вызывает `navigator.credentials.get({mediation: "conditional", publicKey: {challenge: <from-Kratos>, rpId: "app.kacho.cloud", userVerification: "preferred"}})` — Conditional UI autofill (WebAuthn Level 3; Chrome 108+, Safari 16+).
  - Fallback button "Sign in with Passkey" — explicit ceremony.
  - Secondary "Sign in with password" → password+TOTP form.
- **Modify `src/pages/auth/RegistrationPage.tsx`**:
  - Primary CTA "Sign up with Passkey" — calls Kratos `/self-service/registration/browser` flow → triggers WebAuthn registration (`navigator.credentials.create`).
  - Secondary CTA "Sign up with password" — password input с HIBP-feedback (real-time SHA-1 prefix call, debounced 500ms).
  - HIBP feedback: показывает "Password compromised, choose another" если k-anonymity match.
- **Create `src/pages/auth/StepUpModal.tsx`** (new):
  - Modal, opened когда API response 401 `insufficient_user_authentication`.
  - Triggers Passkey ceremony с `userVerification: "required"`.
  - On success → re-fires original API request с new access token.
  - On cancel → user remains на текущей странице, original request не fired.
- **Create `src/pages/auth/RecoveryPage.tsx`** (new):
  - Step 1: email input → POST `/self-service/recovery` → "Check email" message.
  - Step 2: ?token=... URL → POST `/self-service/recovery/<code>` → verify; на success → step 3.
  - Step 3: Force re-Passkey enrollment (WebAuthn create) → success → redirect to `/`.
- **BFF (`src/api/bff.ts`)**:
  - Refresh token stored в httpOnly cookie (set by Kratos / Hydra; BFF только relay'ит).
  - Access token in memory (React context).
  - DPoP private key:
    - On signin: generate ECDSA P-256 keypair via `crypto.subtle.generateKey({name: "ECDSA", namedCurve: "P-256"}, false /* non-extractable */, ["sign"])`.
    - Store в IndexedDB (`kacho-dpop-key` store, single entry).
    - On each API request: generate DPoP JWT (htm + htu + iat + jti) signed с this key; attach Authorization + DPoP headers.

### 5.8 Cross-repo: kacho-proto

- **Modify `proto/kacho/iam/v1/internal_user_service.proto`**:
  - Add RPC `UpsertFromIdentity(UpsertFromIdentityRequest) returns (UpsertFromIdentityResponse)` (внутренний; не в публичных proxy paths).
  - Add RPC `OnRecoveryCompleted(OnRecoveryCompletedRequest) returns (OnRecoveryCompletedResponse)`.
- **Add `proto/kacho/iam/v1/internal_iam_service.proto`** (new RPCs):
  - `GetJWKSStatus(google.protobuf.Empty) returns (JWKSStatusResponse)` — admin observability (current key created_at, rotation due in N days, per-alg).
  - `ForceLogout(ForceLogoutRequest) returns (operation.Operation)` — admin force-block; async (writes session_revocations + caep_outbox row).

---

## 6. Given-When-Then сценарии

### 6.1 Passkey registration

#### Scenario 6.1.1 — First-device Passkey enrollment (happy path)

**Given** Kratos config готов с `webauthn.enabled=true, webauthn.passwordless=true`
  **And** kacho-iam endpoint `POST /iam/v1/internal/users:upsertFromIdentity` доступен на cluster-internal listener (9091)
  **And** User Alice ещё не зарегистрирован (`SELECT count(*) FROM users WHERE email='alice@example.com' = 0`)
  **And** Browser Alice поддерживает WebAuthn Level 3 (Chrome ≥ 108)

**When** Alice открывает `https://app.kacho.cloud/auth/registration`
  **And** Кликает "Sign up with Passkey"
  **And** Вводит `email=alice@example.com`, `display_name=Alice`
  **And** Browser показывает WebAuthn prompt; Alice одобряет (Touch ID / Windows Hello / security key)

**Then** Browser отправляет `POST /self-service/registration` в Kratos с WebAuthn attestation
  **And** Kratos verifies attestation (rp.id=app.kacho.cloud match; user_verification=preferred satisfied)
  **And** Kratos INSERT в `kratos.identities` row + `kratos.identity_credentials` row (type=webauthn)
  **And** Kratos вызывает webhook `POST http://kacho-iam.../iam/v1/internal/users:upsertFromIdentity` с identity payload
  **And** kacho-iam BootstrapWorker создаёт default `acc_<id>` Account + `prj_default` Project + admin-binding (status='ACTIVE')
  **And** kacho-iam INSERT в `users (id, account_id, external_id=<kratos_uuid>, email='alice@example.com', display_name='Alice', invite_status='ACTIVE')`
  **And** kacho-iam INSERT row в `audit_outbox` с event_type=`iam.user.created`
  **And** Kratos issues session (AAL2 — Passkey без user_verification → AMR=`["webauthn"]`, ACR=2)
  **And** Kratos redirects browser на `/` (kacho-ui Dashboard)
  **And** Hydra OAuth flow начинается → access token issued с `acr=2`, `amr=["webauthn"]`, `cnf.jkt=<thumbprint>`

#### Scenario 6.1.2 — Adding second device (subsequent Passkey enrollment)

**Given** Alice уже зарегистрирована и signin'нута (session AAL2)
  **And** В `kratos.identity_credentials` есть 1 row type='webauthn' (Alice's laptop Passkey)

**When** Alice идёт в Settings → "Add Passkey"
  **And** Подтверждает на новом устройстве (например, телефон)

**Then** Kratos INSERT новую row в `kratos.identity_credentials` с тем же identity_id, type='webauthn', но new credential_id
  **And** Kratos hooks НЕ вызывают webhook upsertFromIdentity (это settings flow, не registration)
  **And** Audit row `iam.user.passkey_added` пишется в `audit_outbox` через Kratos settings webhook (`/iam/v1/internal/users:onSettingsUpdated`)
  **And** Subsequent signin Alice может использовать любое из 2 устройств

#### Scenario 6.1.3 — Passkey registration с user_verification=required (для ACR=3 capability)

**Given** Browser Alice имеет biometric-capable authenticator (Touch ID / Windows Hello)
  **And** Kratos config — WebAuthn registration NOT enforces user_verification (relaxed для broad compatibility)

**When** Alice регистрирует Passkey
  **And** Authenticator поддерживает UV (Touch ID prompts fingerprint)
  **And** Authenticator returns assertion с `flags.uv=true`

**Then** Kratos записывает `uv_initialized=true` в credential metadata
  **And** Subsequent ceremonies с `userVerification: "required"` succeed для этого credential
  **And** ACR=3 attainable (через step-up)

#### Scenario 6.1.4 — Registration fails with wrong RP origin (phishing-resistance verified)

**Given** Attacker hosts `https://phishing-app.kacho-clone.com/auth/registration` proxy'ing к Kratos

**When** User clicks через phishing link
  **And** Browser отправляет WebAuthn ceremony к Kratos с `origin: phishing-app.kacho-clone.com`

**Then** Browser WebAuthn API сам rejects ceremony (origin не matches Kratos rp.id=`app.kacho.cloud`)
  **And** Никакой credential НЕ создаётся
  **And** Audit row `authn.registration.origin_mismatch` пишется (если Kratos получил аномальный request)

#### Scenario 6.1.5 — UpsertFromIdentity idempotent — re-fire webhook не дублирует rows

**Given** Alice уже зарегистрирована (1 row в `users`)
  **And** Kratos webhook доставляется повторно (retry на временной 500-ке)

**When** kacho-iam получает второй POST `/iam/v1/internal/users:upsertFromIdentity` с тем же `external_id`

**Then** kacho-iam UPDATE existing row (`email` / `display_name` если изменились) ON CONFLICT (external_id, account_id) DO UPDATE
  **And** `SELECT count(*) FROM users WHERE external_id=$1` остаётся `= 1`
  **And** `iam.user.created` audit row НЕ дублируется (idempotency через `request_jti` in payload + `INSERT ... ON CONFLICT (request_jti) DO NOTHING`)

### 6.2 Passkey signin

#### Scenario 6.2.1 — Conditional UI autofill (Passkey discoverable credential)

**Given** Alice уже зарегистрирована с discoverable Passkey
  **And** Браузер supports Conditional UI (WebAuthn Level 3; `PublicKeyCredential.isConditionalMediationAvailable() → true`)

**When** Alice открывает `https://app.kacho.cloud/auth/login`
  **And** SigninPage on-mount вызывает `navigator.credentials.get({mediation: "conditional", ...})`
  **And** Browser shows autofill suggestion в username input (без явного click)
  **And** Alice выбирает её Passkey

**Then** Browser sends WebAuthn assertion to Kratos `/self-service/login`
  **And** Kratos verifies signature + user_handle match
  **And** Kratos issues session
  **And** Hydra → access token issued с `acr=2, amr=["webauthn"]`
  **And** UI redirects на dashboard

#### Scenario 6.2.2 — Explicit Passkey ceremony

**Given** Alice уже зарегистрирована
  **And** Браузер НЕ supports Conditional UI (older Safari)

**When** Alice clicks "Sign in with Passkey" → explicit ceremony
  **And** Auth prompt появляется

**Then** Same flow as 6.2.1 (autofill omitted) → JWT issued

#### Scenario 6.2.3 — Phishing-resistant: wrong origin rejected

**Given** Same setup as 6.1.4 (attacker proxies Kratos через clone domain)

**When** Alice пытается signin через phishing site

**Then** Browser WebAuthn API rejects ceremony (origin mismatch)
  **And** Никакой valid assertion не создаётся
  **And** Attacker не получает Passkey signature

#### Scenario 6.2.4 — User_verification gating: registration без UV, signin требует UV → fail с степ-ап

**Given** Alice зарегистрировала Passkey БЕЗ user_verification (UV-capable device отсутствовал)
  **And** Alice вызывает admin operation (ACR=3 required, AMR должен включать `uv`)

**When** API-gateway видит presented token имеет `acr=2, amr=["webauthn"]` (no `uv`)
  **And** Required permission: `acr_min=3, amr_required="webauthn"+"uv"`

**Then** API-gateway returns 401 с `WWW-Authenticate: Bearer error="insufficient_user_authentication", acr_values="3"`
  **And** UI opens StepUpModal
  **And** StepUpModal triggers `navigator.credentials.get({userVerification: "required"})`
  **And** Если authenticator не supports UV → browser fails ceremony → UI показывает "Add a biometric-capable Passkey to perform this action"

### 6.3 Password+TOTP fallback

#### Scenario 6.3.1 — Registration с password+TOTP (fallback path)

**Given** Browser Bob не supports WebAuthn (Internet Explorer, или старый device)
  **And** Kratos config password.enabled=true

**When** Bob открывает RegistrationPage
  **And** Кликает "Sign up with password"
  **And** Вводит email=`bob@example.com`, password=`StrongP@ssw0rd!2025`, display_name=`Bob`
  **And** Submits

**Then** Browser SPA sends к HIBP `api.pwnedpasswords.com/range/<sha1-prefix>` с first 5 chars of SHA-1(password)
  **And** HIBP returns list of suffix hashes; password's full SHA-1 НЕ matches → клиент proceeds
  **And** Kratos validates password length ≥ 8 + Argon2id-hashes (m=64MB, t=3, p=4) + stores в `kratos.identity_credentials` (type=password)
  **And** Kratos chained-prompts TOTP enrollment (mandatory next step в same registration flow)
  **And** Bob scans QR code в Authenticator app; вводит 6-digit code
  **And** Kratos verifies TOTP code + stores secret encrypted
  **And** Kratos webhook fires → kacho-iam upsertFromIdentity → user row created
  **And** Session issued с `acr=2, amr=["pwd","otp","mfa"]`

#### Scenario 6.3.2 — Signin с password+TOTP

**Given** Bob уже зарегистрирован (password + TOTP enrolled)

**When** Bob входит password в SigninPage
  **And** Submits → Kratos validates password (Argon2id verify)
  **And** Kratos затем prompts TOTP code (AAL bump)
  **And** Bob вводит 6-digit code из authenticator app
  **And** Kratos verifies

**Then** Session issued с `acr=2, amr=["pwd","otp","mfa"]`
  **And** JWT access token issued с `acr=2, amr=["pwd","otp","mfa"]`

#### Scenario 6.3.3 — HIBP check rejects pwned password

**Given** Bob пытается зарегистрироваться с password=`123456` (известно скомпрометирован)

**When** Browser sends SHA-1(`123456`)=`7C4A8D09CA3762AF61E59520943DC26494F8941B` → prefix `7C4A8` к HIBP
  **And** HIBP returns suffix `D09CA3762AF61E59520943DC26494F8941B:[count]` → match

**Then** UI показывает "Password has been seen N times in data breaches; choose another"
  **And** Registration НЕ proceeds
  **And** kacho-iam НЕ создаёт user row (registration never completes)

#### Scenario 6.3.4 — Password length < 8 → InvalidArgument

**Given** Bob enters password=`short`

**When** Kratos validates

**Then** Kratos returns `400 password_too_short`
  **And** UI showsfield-level error "Password must be at least 8 characters"

### 6.4 DPoP token validation

#### Scenario 6.4.1 — Valid DPoP-bound request succeeds

**Given** Alice signed in; access token имеет `cnf.jkt=<thumbprint>`
  **And** Browser держит DPoP private key в IndexedDB (ECDSA P-256, non-extractable)

**When** kacho-ui вызывает `POST https://api.kacho.cloud/iam/v1/users/me`
  **And** UI generates DPoP JWT: `{typ:"dpop+jwt", alg:"ES256", jwk:<pub>, htm:"POST", htu:"https://api.kacho.cloud/iam/v1/users/me", iat:now(), jti:<uuid-v7>}` signed via WebCrypto
  **And** UI attaches headers `Authorization: DPoP <access_token>` + `DPoP: <dpop_jwt>`

**Then** kacho-api-gateway:
  1. Parses Authorization header → scheme=`DPoP`, token=JWT.
  2. Verifies JWT signature через Hydra JWKS (cached).
  3. Validates `iss`, `aud`, `exp`, `nbf`, `iat`; alg=`ES256` (whitelisted).
  4. Checks `jti` НЕ в `session_revocations` cache.
  5. Parses DPoP header; validates dpop_jwt signature через embedded `jwk`.
  6. Computes thumbprint `jkt = base64url(SHA-256(canonical_jwk))` (RFC 7638).
  7. Compares с `access_token.cnf.jkt` → match → pass.
  8. Validates `htm=POST == request.Method=POST` → pass.
  9. Validates `htu=https://api.kacho.cloud/iam/v1/users/me == canonical_request_url` → pass.
  10. Validates `now() - dpop.iat ≤ 60s` → pass.
  11. Checks `dpop.jti` НЕ в `DPoPReplayCache` → adds → pass.
  12. Forwards request к kacho-iam с gRPC metadata principal
  **And** kacho-iam returns user data
  **And** Response 200 OK

#### Scenario 6.4.2 — htm mismatch → 401

**Given** Same setup as 6.4.1
  **And** UI generates DPoP JWT с `htm:"GET"`

**When** UI fires `POST` request

**Then** api-gateway validates `htm=GET != request.Method=POST`
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: DPoP error="invalid_dpop_proof", error_description="htm claim does not match HTTP method"`
  **And** Никакого forwarding к backend

#### Scenario 6.4.3 — htu mismatch → 401

**Given** Same setup as 6.4.1
  **And** UI generates DPoP JWT с `htu:"https://api.kacho.cloud/vpc/v1/networks"` (wrong path)

**When** UI fires `POST https://api.kacho.cloud/iam/v1/users/me`

**Then** api-gateway validates `htu != canonical_request_url`
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: DPoP error="invalid_dpop_proof", error_description="htu claim does not match request URL"`

#### Scenario 6.4.4 — jti replay → 401

**Given** Same setup as 6.4.1
  **And** UI правильно fires первый request → succeeds; `dpop.jti=<x>` добавлен в `DPoPReplayCache`

**When** Attacker captures DPoP JWT + access token (man-in-the-middle на скомпрометированном CA или log leak)
  **And** Attacker replays the captured headers к `POST https://api.kacho.cloud/iam/v1/users/me` (within 60s window)

**Then** api-gateway видит `dpop.jti=<x>` уже в `DPoPReplayCache`
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: DPoP error="invalid_dpop_proof", error_description="DPoP jti already used"`

#### Scenario 6.4.5 — iat freshness exceeded → 401

**Given** Same setup as 6.4.1
  **And** UI generates DPoP JWT с `iat=now()-300s` (5 minutes ago)

**When** UI fires request

**Then** api-gateway validates `now() - dpop.iat = 300s > 60s threshold`
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: DPoP error="invalid_dpop_proof", error_description="DPoP proof iat is too old"`

#### Scenario 6.4.6 — cnf.jkt thumbprint mismatch (token theft attempt) → 401

**Given** Alice's access token имеет `cnf.jkt=<alice_thumbprint>`
  **And** Attacker украл token + DPoP JWT pair; attacker генерирует свой DPoP JWT с другим keypair

**When** Attacker fires request с Alice's access token + attacker's DPoP JWT (правильный htm/htu/iat/jti, но JWK другой)

**Then** api-gateway computes thumbprint attacker's jwk → `<attacker_thumbprint>`
  **And** Compares с `cnf.jkt = <alice_thumbprint>` → mismatch
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: DPoP error="invalid_dpop_proof", error_description="cnf.jkt thumbprint mismatch"`
  **And** Audit row `authn.dpop.thumbprint_mismatch` пишется (security alert candidate в Phase 9)

### 6.5 mTLS-bound tokens

#### Scenario 6.5.1 — Backend M2M client с mTLS-bound token succeeds

**Given** ServiceAccount `sva_ci_deployer` имеет static Hydra client `cli_xxx` (Class A — Phase 5; для Phase 2 предполагается уже configured manually)
  **And** Client certificate с CN=`sva_ci_deployer.kacho.cloud` provisioned и mounted в CI pod
  **And** Hydra config `oauth2.mtls.enabled=true`

**When** CI pod requests token: `POST https://hydra.kacho.cloud/oauth2/token` с client cert в mTLS handshake + `grant_type=client_credentials` + `client_id=cli_xxx` + `client_secret=<secret>`
  **And** Hydra extracts client cert thumbprint `x5t#S256 = base64url(SHA-256(cert.Raw))`
  **And** Hydra issues access token с `cnf.x5t#S256=<thumbprint>` (no jkt)

**Then** CI pod fires API request: `POST https://api.kacho.cloud/vpc/v1/networks` с mTLS handshake (same client cert) + `Authorization: Bearer <token>`
  **And** api-gateway validates JWT signature/exp/aud
  **And** api-gateway computes `x5t#S256` of presented client cert
  **And** Compares с `cnf.x5t#S256` → match → pass
  **And** Forwards к kacho-vpc

#### Scenario 6.5.2 — mTLS-bound token used WITHOUT client cert → 401

**Given** Same setup as 6.5.1; token issued mTLS-bound

**When** Attacker stole token; fires request WITHOUT mTLS client cert (только plain TLS)

**Then** api-gateway detects `cnf.x5t#S256` present in token, но no client cert presented
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: Bearer error="invalid_token", error_description="mTLS-bound token requires client certificate"`

#### Scenario 6.5.3 — Cert rotation: new cert presented, old token still valid → mismatch → 401

**Given** Old cert thumbprint=A; access token bound to A
  **And** CI rotates cert → new cert thumbprint=B

**When** CI fires request с new cert (B) + old token (cnf.x5t#S256=A)

**Then** api-gateway computes B != A → mismatch
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: Bearer error="invalid_token", error_description="cnf.x5t#S256 does not match client certificate"`
  **And** CI должен re-issue token с new cert (Hydra `/oauth2/token` с new cert in handshake → new cnf.x5t#S256=B)

### 6.6 Step-up to ACR=3

#### Scenario 6.6.1 — Admin RPC требует ACR=3, presented ACR=2 → 401 insufficient_user_authentication

**Given** Alice имеет cluster-admin role; access token `acr=2, amr=["webauthn"]`
  **And** Permission catalog: `kacho.cloud.iam.v1.InternalClusterAdminService/Grant` имеет `required_acr_min="3"`

**When** Alice (через admin UI) вызывает `POST /iam/v1/internal/clusterAdminGrants` с valid payload

**Then** api-gateway видит token.acr=`2` < required `3`
  **And** Returns:
    ```
    HTTP/1.1 401 Unauthorized
    WWW-Authenticate: Bearer error="insufficient_user_authentication",
        error_description="Required ACR 3 for this resource; presented ACR 2",
        acr_values="3"
    ```
  **And** Никакого forwarding к kacho-iam (gateway-level early reject)

#### Scenario 6.6.2 — Step-up flow: UI triggers re-Passkey ceremony

**Given** Same setup as 6.6.1; UI получает 401 insufficient_user_authentication

**When** kacho-ui parses `WWW-Authenticate` header → extracts `acr_values=3`
  **And** Opens `StepUpModal` с button "Verify identity"
  **And** Alice клика на button → UI вызывает `navigator.credentials.get({publicKey: {challenge: <new>, userVerification: "required"}, mediation: "required"})`
  **And** Alice проходит biometric verification
  **And** Browser sends new assertion к Kratos `/self-service/login` с aal=`aal3` parameter
  **And** Kratos bumps session AAL to 3 (AMR adds `"uv"`)
  **And** Kratos `/self-service/login/flows` returns success
  **And** UI вызывает Hydra `/oauth2/token` с `acr_values=3` (re-issues access token)
  **And** Hydra issues new access token с `acr=3, amr=["webauthn","uv"]`

**Then** UI replays original request с new access token
  **And** api-gateway validates: token.acr=3 ≥ required 3 → pass
  **And** Request succeeds (200 OK)
  **And** Audit row `iam.cluster_admin.grant.created` + `authn.step_up.completed` пишется

#### Scenario 6.6.3 — Step-up cancelled by user → original request not replayed

**Given** Same setup as 6.6.1; StepUpModal opened

**When** Alice cancels (Esc / close button)

**Then** Original request НЕ replayed
  **And** UI shows toast "Action requires verification"
  **And** Audit row `authn.step_up.cancelled` пишется

#### Scenario 6.6.4 — Step-up with non-UV authenticator → fails gracefully

**Given** Alice's Passkey НЕ supports user_verification (UV-incapable device — old security key)
  **And** Alice triggers step-up

**When** Browser tries `userVerification: "required"`; authenticator не может provide UV → browser fails ceremony

**Then** UI shows "This action requires a biometric-capable Passkey. Add one in Settings."
  **And** Original request НЕ replayed

### 6.7 Refresh token rotation

#### Scenario 6.7.1 — Happy path refresh

**Given** Alice signed in; access token (jti=A1) + refresh token (id=R1, family=F1)
  **And** Access token approaching expiry (≤ 1min remaining)

**When** kacho-ui детектит close-to-expiry и вызывает Hydra `/oauth2/token` с `grant_type=refresh_token, refresh_token=R1`
  **And** Hydra UPDATE `refresh_tokens SET used_at=now() WHERE id=R1 AND used_at IS NULL RETURNING ...` (race-safe single UPDATE)
  **And** Hydra issues new access token (jti=A2) + new refresh token (id=R2, family=F1, previous_id=R1)
  **And** Hydra вызывает refresh_hook → kacho-iam re-injects ext_claims

**Then** UI receives new pair; updates in-memory access token; cookie updates with new refresh token
  **And** Audit row `authn.refresh.issued` пишется

#### Scenario 6.7.2 — Reuse detection → family-revoke

**Given** Same setup; R1 used → R2 issued
  **And** Attacker украл R1 ранее (до R2 issuance)
  **And** > 1s прошло после R1 used (вне reuse-grace-window)

**When** Attacker fires `POST /oauth2/token` с `grant_type=refresh_token, refresh_token=R1`
  **And** Hydra видит `R1.used_at IS NOT NULL` AND `now() - R1.used_at > 1s`

**Then** Hydra triggers family-revoke:
  - `DELETE FROM refresh_tokens WHERE family_id = F1` (revokes both R1 и R2)
  - Returns `400 invalid_grant`
  **And** Audit row `authn.refresh.family_revoked` с `reason=reuse_detected` пишется
  **And** Legitimate Alice's next refresh-attempt (с R2) also fails → forced re-signin
  **And** Audit row `authn.signin.forced_after_family_revoke` (на next signin)

#### Scenario 6.7.3 — Concurrent legit refresh (race, both within 1s)

**Given** Alice has 2 browser tabs; both have access token close to expiry; both trigger refresh c R1

**When** Tab 1 sends refresh first; Tab 2 sends 50ms later
  **And** Both arrive в Hydra within < 1s of each other

**Then** Tab 1's UPDATE wins (`UPDATE refresh_tokens SET used_at=now() WHERE id=R1 AND used_at IS NULL RETURNING ...` returns 1 row)
  **And** Tab 1 receives new pair (A2, R2)
  **And** Tab 2's UPDATE sees `used_at IS NOT NULL` AND `now() - used_at < 1s` (grace window) → returns `400 invalid_grant` (НЕ family-revoke)
  **And** Tab 2 UI sees 400 → retries with R2 (через cookie sync between tabs via BroadcastChannel или next-natural-refresh) → succeeds
  **And** Audit row `authn.refresh.race_grace_window` пишется

#### Scenario 6.7.4 — Refresh after admin force-block → invalid_grant

**Given** Alice's account force-blocked by admin (`UPDATE users SET enabled=false WHERE id=...`)
  **And** Refresh token still valid (not revoked при block — refresh-hook gate'ит)

**When** UI tries refresh

**Then** Hydra вызывает refresh_hook к kacho-iam
  **And** kacho-iam видит `user.enabled=false` → returns HTTP 403 `user_disabled`
  **And** Hydra пропагирует как `400 invalid_grant`
  **And** Audit row `authn.refresh.user_disabled` пишется

### 6.8 JWKS rotation

#### Scenario 6.8.1 — Bootstrap: первая rotation на чистой DB

**Given** `oidc_jwks_keys` пустая (после Phase 1 миграций; нет ни одной row)
  **And** kacho-iam JWKSRotator worker запускается

**When** Worker tick fires (after startup delay)
  **And** Worker query `SELECT count(*) FROM oidc_jwks_keys WHERE alg='RS256' AND current=true` returns 0

**Then** Worker генерирует RSA-2048 keypair
  **And** Encrypts private_key_pem через AES-GCM с env key
  **And** INSERT row в `oidc_jwks_keys (kid='kacho-rs256-<ulid>', alg='RS256', public_key_pem, private_key_pem_encrypted, current=true, created_at=now(), expires_at=now()+90d)`
  **And** POST `/admin/keys/hydra.openid.id-token` к Hydra-admin с public key
  **And** Same для ES256 и EdDSA
  **And** Hydra `/.well-known/jwks.json` returns 3 keys (one per alg, all current=true)
  **And** Audit row `iam.jwks.bootstrapped` пишется

#### Scenario 6.8.2 — Rotation после 90 days

**Given** Existing row: `alg='RS256', kid='kacho-rs256-old', current=true, created_at=now()-91d`

**When** Worker tick fires; query identifies row age > 90d → rotation triggered
  **And** Worker генерирует new RSA-2048 keypair (kid='kacho-rs256-new')

**Then** Worker executes single-statement CTE (Phase 1 §2.6):
  ```sql
  WITH old AS (
      UPDATE oidc_jwks_keys
         SET current = false, rotated_at = now()
       WHERE alg = 'RS256' AND current = true
      RETURNING kid
  )
  INSERT INTO oidc_jwks_keys (kid, alg, public_key_pem, private_key_pem_encrypted, current, created_at, expires_at)
  VALUES ('kacho-rs256-new', 'RS256', $1, $2, true, now(), now() + interval '90 days');
  ```
  **And** Statement succeeds atomically (no intermediate `2 current=true` state)
  **And** Worker POST'ит new public key к Hydra-admin `/admin/keys/hydra.openid.id-token`
  **And** Hydra `/.well-known/jwks.json` показывает оба keys (current=`kacho-rs256-new`, previous=`kacho-rs256-old`)
  **And** Audit row `iam.jwks.rotated` пишется с `old_kid` + `new_kid`

#### Scenario 6.8.3 — Old key валиден для already-issued tokens (overlap window 30min)

**Given** Same as 6.8.2; old key rotated_at=now()
  **And** Existing access token (jti=A1) подписан с old_kid; expires now()+10min

**When** Client fires request с этим token
  **And** api-gateway parses JWT header → extracts `kid=kacho-rs256-old`
  **And** Looks up JWKS cache → finds `kacho-rs256-old` (still in /.well-known/jwks.json)
  **And** Verifies signature → pass

**Then** Request succeeds
  **And** Token остаётся valid до своего `exp`

#### Scenario 6.8.4 — Cleanup pass: old key удаляется после grace window

**Given** Same as 6.8.2; rotation completed; `rotated_at=now()-31min`

**When** Worker cleanup pass fires (next tick)
  **And** Query `SELECT kid FROM oidc_jwks_keys WHERE rotated_at < now() - interval '30 minutes' AND current = false` returns 1 row

**Then** Worker DELETE rows один за другим (per kid; via Hydra-admin `DELETE /admin/keys/<kid>` first, then DELETE local row)
  **And** Hydra `/.well-known/jwks.json` теперь показывает только current key
  **And** Audit row `iam.jwks.cleaned_up` пишется

#### Scenario 6.8.5 — Concurrent rotation under HA (2 pods) — advisory lock

**Given** kacho-iam HA: 2 replicas
  **And** Both reach rotation tick одновременно (NTP-synced clocks)

**When** Both pods вызывают `SELECT pg_advisory_lock(0x4A574B53)` (constant lock id для JWKS-rotation)
  **And** Pod 1 acquires lock; pod 2 blocks
  **And** Pod 1 проверяет current key age, rotates, releases lock
  **And** Pod 2 acquires; пере-проверяет age → видит уже rotated → skip

**Then** Ровно 1 rotation executed (no double-rotate, no race)
  **And** Pod 2 advisory_unlock; tick completes без actions

### 6.9 Recovery

#### Scenario 6.9.1 — Magic-link recovery happy path

**Given** Alice потеряла свой Passkey device
  **And** Alice has access к her registered email (`alice@example.com`)

**When** Alice clicks "Forgot password / Passkey?" → RecoveryPage
  **And** Inputs email → kacho-ui POST `/self-service/recovery/api` к Kratos
  **And** Kratos generates magic-link code (UUID v4)
  **And** Kratos INSERT в `kratos.recovery_codes (code_hash, identity_id, issued_ip='1.2.3.4', expires_at=now()+5min, used_at=NULL)`
  **And** Kratos email courier sends email с link `https://app.kacho.cloud/recovery?token=<code>`
  **And** Alice clicks link (same IP=1.2.3.4)
  **And** Kratos POST `/self-service/recovery` с code → validates expires_at + ip_match + used_at IS NULL
  **And** Kratos marks `used_at=now()` (single-use enforced)
  **And** Kratos issues elevated session (`aal=aal1`, marker `recovery_active=true`)

**Then** UI redirects к step 3 (force re-Passkey enrollment page)
  **And** Alice проходит WebAuthn registration ceremony — adds new Passkey
  **And** Kratos INSERT new `identity_credentials (type=webauthn)` row
  **And** Kratos DELETES старые `identity_credentials WHERE identity_id = $1 AND type = 'webauthn' AND id != <new>` (revoke old factors)
  **And** kacho-iam webhook `/iam/v1/internal/users:onRecoveryCompleted` fires
  **And** kacho-iam INSERT в `audit_outbox` событие `iam.user.recovery.completed`
  **And** kacho-iam invalidates all existing sessions: INSERT в `session_revocations` для каждого active jti (queried через Hydra-admin)
  **And** kacho-iam INSERT в `caep_outbox` row `event_type=session_revoked` для CAEP push (Phase 8)
  **And** Session AAL bumped to 2 (Passkey)
  **And** Audit row `authn.signin.success` + `iam.user.passkey_added` пишутся

#### Scenario 6.9.2 — TTL exceeded

**Given** Magic-link issued 6 минут назад

**When** Alice clicks link

**Then** Kratos validates expires_at < now() → returns `400 recovery_code_expired`
  **And** UI shows "This recovery link has expired. Please request a new one."
  **And** Old code marked `used_at=now()` (security: invalidate even on failure)

#### Scenario 6.9.3 — Single-use violated

**Given** Alice clicked link once → succeeded
  **And** Attacker also has the link (email inbox compromised)
  **And** Attacker clicks within 5min window

**When** Attacker submits code

**Then** Kratos validates `used_at IS NOT NULL` → returns `400 recovery_code_already_used`
  **And** Audit row `authn.recovery.replay_attempted` пишется (security alert candidate в Phase 9)

#### Scenario 6.9.4 — IP-bound recovery: different IP rejected

**Given** Magic-link issued from IP=1.2.3.4
  **And** Alice's email accessed from IP=5.6.7.8 (different network)

**When** Alice clicks link from IP=5.6.7.8

**Then** Kratos validates issued_ip != current_ip → returns `400 ip_changed_during_recovery`
  **And** Audit row `authn.recovery.ip_mismatch` пишется

### 6.10 Back-channel logout (RFC 8254)

#### Scenario 6.10.1 — Admin force-logout cascades to SP

**Given** Alice signed in; session_id=`S1`; active access token (jti=A1)
  **And** kacho-ui registered как back-channel-logout-capable client в Hydra (with `backchannel_logout_uri=https://app.kacho.cloud/bff/back-channel-logout`)
  **And** Admin Bob (ACR=3) signs in

**When** Bob вызывает `POST /iam/v1/internal/users/{alice_id}:forceLogout`
  **And** API-gateway validates token (Bob's acr=3, permission `iam.users.force_logout` ok)
  **And** Forwards к kacho-iam

**Then** kacho-iam executes ForceLogout use-case:
  1. Calls Hydra-admin `DELETE /oauth2/auth/sessions/login?subject=<alice_id>` → invalidates session S1 (revokes refresh tokens).
  2. Queries Hydra introspection для active access tokens с subject=alice_id → returns [jti=A1].
  3. INSERT в `session_revocations(token_jti='A1', revoked_at=now(), reason='force_logout', revoked_by='<bob_id>')`.
  4. INSERT в `audit_outbox` row `iam.user.force_logout`.
  5. INSERT в `caep_outbox` row `event_type=token_claims_change` для CAEP push.
  6. Hydra (after DELETE session) sends signed logout_token к kacho-ui BFF `https://app.kacho.cloud/bff/back-channel-logout`.
  **And** kacho-ui BFF verifies logout_token signature через Hydra JWKS
  **And** Validates iss/aud/sid/events claim
  **And** Clears Alice's session in BFF storage (refresh-token cookie invalidated)
  **And** Audit row `iam.user.back_channel_logout_delivered` пишется

#### Scenario 6.10.2 — Cross-tenant isolation на back-channel logout

**Given** Two organizations: org_a (subscribers including kacho-ui для tenants org_a), org_b
  **And** Alice (acc_a1b2 ∈ org_a) force-logged-out

**When** Hydra distributes logout_token

**Then** logout_token sent ТОЛЬКО к kacho-ui-org_a (sub=`usr_alice_acc_a1b2`)
  **And** kacho-ui-org_b НЕ получает токен (no matching sub)
  **And** Audit row delivers per-tenant (audit row `iam.user.back_channel_logout_delivered` имеет `tenant=org_a` field)

### 6.11 Session revocation cache

#### Scenario 6.11.1 — Admin force-block triggers cache invalidation ≤1s

**Given** Alice signed in; access token jti=A1 valid for next 10min
  **And** kacho-api-gateway pod has `LISTEN session_revoked` connection active
  **And** Alice fires `GET /iam/v1/users/me` каждые 100ms (busy loop)

**When** Admin Bob (через UI или CLI) вызывает ForceLogout для Alice
  **And** kacho-iam INSERT в `session_revocations(token_jti='A1', ...)` + `pg_notify('session_revoked', 'A1')` в same TX
  **And** TX commits at `t0`

**Then** Postgres delivers NOTIFY к api-gateway pod connection within ≤ 100ms (`t0+100ms`)
  **And** Pod's listener adds 'A1' to in-memory `revoked` map (≤ 1ms)
  **And** На next Alice's request (within next 100ms loop tick = `t0+100ms..t0+200ms`):
    - api-gateway lookup `revoked[A1]` → found
    - Returns `401 Unauthorized` с `WWW-Authenticate: Bearer error="invalid_token", error_description="Session revoked"`
  **And** **Measured SLA**: `t_revoke → t_token_rejected ≤ 1s p95` (newman case с polling loop verifies)

#### Scenario 6.11.2 — LISTEN reconnect after network blip

**Given** api-gateway pod LISTEN connection drops (TCP timeout, ≤30s)
  **And** During drop period, admin force-blocks user → row inserted в session_revocations

**When** Pod listener reconnects (`pgxpool` auto-reconnect logic)

**Then** Pod issues full re-sync: `SELECT token_jti FROM session_revocations WHERE revoked_at > now() - interval '15 minutes'`
  **And** Picks up missed jti's
  **And** Cache becomes consistent
  **And** Next request с revoked jti → 401

#### Scenario 6.11.3 — Cold-start: pod restart loads recent revocations

**Given** Pod restarting; in-memory cache empty
  **And** session_revocations contains 50 rows revoked within last 15min

**When** Pod starts; runs `Init()`:
  - SELECT recent rows → bulk-load в map.
  - Start LISTEN goroutine.

**Then** Cache populated с 50 jti's
  **And** First request с one of revoked jti's → immediate 401 (no DB roundtrip)
  **And** Startup latency для bulk-load measured ≤ 500ms (verified by integration test)

### 6.12 NIST 800-63B AAL mapping

#### Scenario 6.12.1 — Passkey alone (no UV) → AAL2

**Given** Alice signed in с Passkey без user_verification
  **And** Token `acr=2, amr=["webauthn"]`

**When** Token used для permission `required_acr_min="2"`

**Then** api-gateway accepts (acr=2 ≥ required 2)
  **And** Maps to NIST AAL2 (single-factor authenticator + soft-impersonation-resistant)

#### Scenario 6.12.2 — Passkey + UV (biometric) → AAL3

**Given** Alice signed in с Passkey + user_verification
  **And** Token `acr=3, amr=["webauthn","uv"]`

**When** Token used для permission `required_acr_min="3"`

**Then** api-gateway accepts (acr=3 ≥ required 3)
  **And** Maps to NIST AAL3 (multi-factor hardware-bound + biometric)

#### Scenario 6.12.3 — Password+TOTP → AAL2 (cannot satisfy AAL3)

**Given** Bob signed in с password+TOTP
  **And** Token `acr=2, amr=["pwd","otp","mfa"]`

**When** Bob attempts admin RPC (required_acr_min=3)

**Then** api-gateway: acr=2 < 3 → 401 insufficient_user_authentication
  **And** UI prompts: "Add a biometric-capable Passkey to access cluster-admin actions"
  **And** Step-up flow НЕ works (TOTP не upgrades to AAL3 — only Passkey+UV)

### 6.13 Algorithm confusion mitigation

#### Scenario 6.13.1 — alg=none rejected

**Given** Attacker crafts JWT с header `{"alg":"none","typ":"JWT"}`, valid claims, no signature

**When** Attacker fires request с this token

**Then** api-gateway parses header; alg=`none` НЕ в whitelist `{RS256, ES256, EdDSA}`
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: Bearer error="invalid_token", error_description="alg none not allowed"`
  **And** Audit row `authn.token.alg_none_rejected` пишется (security alert candidate Phase 9)

#### Scenario 6.13.2 — HS256 с public key (algorithm confusion CVE-2015-9235) rejected

**Given** Attacker crafts JWT с header `{"alg":"HS256","kid":"kacho-rs256-current"}`, signature=HMAC-SHA256(public_key_pem, header.payload)

**When** Attacker fires request

**Then** api-gateway parses header; alg=`HS256` НЕ в whitelist (only RS256/ES256/EdDSA — all asymmetric)
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: Bearer error="invalid_token", error_description="alg HS256 not allowed"`
  **And** Audit row `authn.token.alg_confusion_attempt` пишется

#### Scenario 6.13.3 — kid mismatch — no fallback to first key

**Given** JWT has `kid="kacho-rs256-attacker-forged"` (not in JWKS)
  **And** Signature wouldn't validate against any current key

**When** api-gateway parses header; queries JWKS cache для `kid=kacho-rs256-attacker-forged`

**Then** Cache miss → force-refresh JWKS from Hydra
  **And** После refresh — still не найден
  **And** Returns `401 Unauthorized` с `WWW-Authenticate: Bearer error="invalid_token", error_description="kid not recognized"`
  **And** **No fallback** к "first key in JWKS" (defense against forged kid)

---

## 7. Definition of Done — Phase 2 closure

### 7.1 Functional tests

- [ ] Все 7 PR'ов (см. §8) merged в main their repos
- [ ] **Integration tests зелёные**:
    - `kacho-api-gateway/internal/auth/jwt_validator_test.go` (Scenarios 6.13.1–6.13.3 + alg whitelist).
    - `kacho-api-gateway/internal/auth/dpop_validator_test.go` (Scenarios 6.4.1–6.4.6 incl. happy + 5 negative; testcontainers Postgres для JWKS cache).
    - `kacho-api-gateway/internal/auth/mtls_validator_test.go` (Scenarios 6.5.1–6.5.3).
    - `kacho-api-gateway/internal/auth/session_revocations_cache_test.go` (Scenarios 6.11.1–6.11.3 incl. concurrent NOTIFY race с 100 goroutines).
    - `kacho-api-gateway/internal/auth/step_up_test.go` (Scenarios 6.6.1–6.6.4 + ACR matrix coverage).
    - `kacho-iam/internal/apps/kacho/api/hydra/token_hook_test.go` (httptest; valid hook payload → ext_claims response; invalid hook-token → 401; missing user → graceful fallback).
    - `kacho-iam/internal/apps/kacho/api/hydra/refresh_hook_test.go` (Scenario 6.7.4 — disabled user; happy refresh).
    - `kacho-iam/internal/apps/kacho/api/user/internal_upsert_test.go` (Scenarios 6.1.1, 6.1.5 — idempotency + first-time bootstrap + concurrent same-identity race с 10 goroutines).
    - `kacho-iam/internal/apps/kacho/jobs/jwks_rotator_test.go` (Scenarios 6.8.1–6.8.5 incl. CTE atomic swap, partial UNIQUE invariant, multi-alg coexistence, advisory_lock HA-safe).
- [ ] **Newman E2E зелёный** (`kacho-test/tests/newman/cases/auth.py`):
    - case `auth_passkey_registration_happy` (6.1.1).
    - case `auth_passkey_signin_conditional_ui` (6.2.1).
    - case `auth_password_totp_happy` (6.3.1).
    - case `auth_hibp_rejects_pwned_password` (6.3.3).
    - case `auth_dpop_happy` (6.4.1).
    - case `auth_dpop_htm_mismatch_401` (6.4.2).
    - case `auth_dpop_htu_mismatch_401` (6.4.3).
    - case `auth_dpop_jti_replay_401` (6.4.4).
    - case `auth_dpop_iat_expired_401` (6.4.5).
    - case `auth_dpop_thumbprint_mismatch_401` (6.4.6).
    - case `auth_mtls_happy` (6.5.1).
    - case `auth_mtls_no_cert_401` (6.5.2).
    - case `auth_step_up_required` (6.6.1).
    - case `auth_step_up_completion` (6.6.2).
    - case `auth_refresh_happy` (6.7.1).
    - case `auth_refresh_reuse_family_revoke` (6.7.2).
    - case `auth_jwks_overlap_old_key_works` (6.8.3).
    - case `auth_recovery_happy` (6.9.1).
    - case `auth_recovery_ttl_expired` (6.9.2).
    - case `auth_recovery_replay_rejected` (6.9.3).
    - case `auth_back_channel_logout` (6.10.1).
    - case `auth_session_revoked_cache_invalidation` (6.11.1) — polling loop verifies ≤ 1s SLA.
    - case `auth_alg_none_rejected` (6.13.1).
    - case `auth_alg_confusion_hs256_rejected` (6.13.2).
- [ ] **Playwright e2e зелёный** (`kacho-ui/e2e/auth.spec.ts`):
    - Использует Chrome DevTools Protocol `Page.addVirtualAuthenticator` для симуляции WebAuthn в CI.
    - `signup_passkey_flow` (6.1.1 + UI rendering).
    - `signin_conditional_ui_autofill` (6.2.1 — verify autofill suggestion appears).
    - `step_up_modal_flow` (6.6.2 — verify modal opens + Passkey ceremony + original request replay).
    - `recovery_force_passkey_flow` (6.9.1 — verify force re-enrollment page).
    - `force_logout_back_channel_clears_ui_session` (6.10.1 — verify UI session cleared within 5s).
- [ ] **k6 load test зелёный** (`kacho-test/k6/auth-load.js`):
    - Target SLA: p95 token validation latency ≤ 5ms per request (JWKS cache pre-warmed).
    - Concurrent connections: 500 sustained for 10min.
    - Throughput: ≥ 10K validations/sec across 3 api-gateway replicas.
    - Verification: p95 latency, p99 latency, error rate < 0.01%.

### 7.2 Quality gates

- [ ] CI grep check: 0 матчей `// TODO|// FIXME|// XXX|// HACK` в новых файлах (production edition).
- [ ] CI grep check: 0 матчей `"yandex"` в любом case (запрет #2).
- [ ] `golangci-lint --strict` проходит без waivers на новом коде (kacho-iam + kacho-api-gateway).
- [ ] `buf lint` проходит для новых proto файлов (`internal_user_service.proto` extensions; `internal_iam_service.proto` new RPCs).
- [ ] `buf breaking` против main: только additive changes для public proto; internal RPCs free to break.
- [ ] `gosec` без High/Critical на новом коде.
- [ ] `eslint` + TypeScript `tsc --strict` проходят на kacho-ui новых компонентах.
- [ ] OWASP ZAP baseline scan на `https://app.kacho.cloud` dev стенде — 0 High/Critical findings (Phase 12 — full pentest; Phase 2 — automated scan only).

### 7.3 Smoke checklist на dev стенд (kacho-deploy `make dev-up` clean baseline)

- [ ] User signup через kacho-ui `https://app.kacho.cloud/auth/registration` с Passkey → succeeds (verified visually + browser console clean).
- [ ] User signin через Conditional UI autofill → JWT issued с `acr=2, cnf.jkt=<thumbprint>, ext_claims.kacho_active_account=acc_<id>`.
- [ ] `curl -v https://api.kacho.cloud/iam/v1/users/me -H "Authorization: DPoP <token>" -H "DPoP: <dpop_jwt>"` → 200 OK с user JSON.
- [ ] Step-up flow: вызов `POST /iam/v1/internal/clusterAdminGrants` с acr=2 token → 401 + WWW-Authenticate; UI opens modal; ceremony; replay → 200.
- [ ] Force-logout: admin вызывает `POST /iam/v1/internal/users/<user_id>:forceLogout`; observe в DB `SELECT * FROM session_revocations WHERE token_jti=...` row appeared; observe next user request → 401 within 1s.
- [ ] JWKS rotation: manually `UPDATE oidc_jwks_keys SET created_at = now() - interval '91 days' WHERE alg='RS256'`; trigger rotator → observe new row inserted + Hydra `/.well-known/jwks.json` shows 2 keys; old token still validates against old key.
- [ ] Recovery flow: forgot-password → email → link click → force Passkey enrollment → new Passkey works.
- [ ] HIBP check: try password `123456` в registration → blocked с "Password compromised".

### 7.4 Vault updates (после merge всех PR'ов)

- [ ] `obsidian/kacho/resources/iam-oidc-jwks-key.md` — updated (Phase 2 rotation use-case + KMS encryption decision).
- [ ] `obsidian/kacho/resources/iam-session-revocation.md` — updated (cache invalidation protocol + LISTEN/NOTIFY).
- [ ] `obsidian/kacho/resources/iam-audit-outbox.md` — updated (Phase 2 audit events list: `authn.signin.success/.failure`, `authn.refresh.issued/.family_revoked`, `iam.user.created/.activated/.recovery.completed/.force_logout`, `iam.jwks.bootstrapped/.rotated`, `authn.dpop.thumbprint_mismatch`, `authn.token.alg_none_rejected/.alg_confusion_attempt`).
- [ ] `obsidian/kacho/rpc/iam-internal-user-service.md` — updated (added `UpsertFromIdentity`, `OnRecoveryCompleted`).
- [ ] `obsidian/kacho/rpc/iam-internal-iam-service.md` (new) — JWKS-status, ForceLogout admin RPCs.
- [ ] `obsidian/kacho/rpc/iam-hydra-hooks.md` (new) — token_hook, refresh_hook contract.
- [ ] `obsidian/kacho/edges/hydra-to-iam-token-hook.md` (new) — synchronous HTTP hook protocol.
- [ ] `obsidian/kacho/edges/kratos-to-iam-upsert-identity.md` (new) — webhook protocol.
- [ ] `obsidian/kacho/edges/api-gateway-to-iam-session-revocations.md` (new) — LISTEN/NOTIFY invalidation.
- [ ] `obsidian/kacho/packages/api-gateway-internal-auth.md` (new) — DPoP / mTLS / session-cache validators.
- [ ] `obsidian/kacho/packages/iam-internal-apps-jobs-jwks-rotator.md` (new) — rotation worker.
- [ ] `obsidian/kacho/packages/iam-internal-apps-api-hydra.md` (new) — token_hook + refresh_hook handlers.
- [ ] `obsidian/kacho/architecture.md` — diagram updated с AuthN plane (Kratos / Hydra / kacho-iam / api-gateway / kacho-ui).
- [ ] `obsidian/kacho/KAC/KAC-127.md` — обновлено: Phase 2 чек-лист закрыт, PR-URL'ы добавлены.

### 7.5 Cross-repo PR-chain merged (порядок — §8)

- [ ] PR #1 kacho-proto (`internal_user_service.proto` + `internal_iam_service.proto` extensions; regen `gen/`) — merged.
- [ ] PR #2 kacho-corelib (если потребуются DPoP helpers — `corelib/auth/dpop.go` с thumbprint computation; reused между api-gateway и tests) — merged. Если не потребуется (helpers оказываются api-gateway-internal) — этот PR skipped.
- [ ] PR #3 kacho-iam (token_hook + refresh_hook + UpsertFromIdentity rewrite + JWKS rotation worker + ForceLogout RPC) — merged.
- [ ] PR #4 kacho-api-gateway (DPoP + mTLS + session-cache + step-up middleware) — merged.
- [ ] PR #5 kacho-deploy (Kratos config + Hydra config + helm values для dev и prod + secret references) — merged.
- [ ] PR #6 kacho-ui (SigninPage + RegistrationPage + StepUpModal + RecoveryPage + BFF DPoP setup) — merged.
- [ ] PR #7 kacho-workspace (этот acceptance-doc → APPROVED → status flip; vault updates) — merged.

---

## 8. Cross-repo PR-chain (порядок merge)

Согласно workspace `CLAUDE.md` §«Кросс-репо зависимости и порядок выполнения», топологическая сортировка graph'а build-зависимостей:

1. **kacho-proto** — new internal-service proto messages + regen `gen/go/...`. CI'ы `buf lint`, `buf breaking` зелёные. Branch `KAC-127`.
2. **kacho-corelib** — если потребуются DPoP helpers (`corelib/auth/dpop/thumbprint.go` для RFC 7638 JWK thumbprint computation; reused в api-gateway + future SDK). Если нет — этот шаг skipped. Branch `KAC-127`.
3. **kacho-iam** — token_hook + refresh_hook handlers, UpsertFromIdentity rewrite (production-grade idempotent), JWKS rotation worker, ForceLogout admin RPC, OnRecoveryCompleted hook. Зависит от kacho-corelib + kacho-proto. Branch `KAC-127`.
4. **kacho-api-gateway** — DPoP / mTLS / session-revocations validators, step-up middleware, JWT alg whitelist. Зависит от kacho-corelib (DPoP helpers если в corelib). Branch `KAC-127`.
5. **kacho-deploy** — Kratos config (WebAuthn passwordless, password Argon2id+HIBP, TOTP, recovery, hooks), Hydra config (DPoP enabled, mTLS enabled, refresh-rotation, JWKS, token_hook URL), helm-values для dev/prod, secret references. Зависит от backend сервисов having endpoints ready. Branch `KAC-127`.
6. **kacho-ui** — SigninPage, RegistrationPage, StepUpModal, RecoveryPage, BFF DPoP private-key generation/storage. Зависит от backend (api-gateway routes) ready на dev стенде. Branch `KAC-127`.
7. **kacho-workspace** — этот acceptance-doc финализирован → APPROVED → status flip; vault entries созданы/обновлены; KAC-127 Obsidian-note обновлена с Phase 2 PR URLs. Branch `KAC-127`.

> CI ref-pinning: до merge'а каждого upstream PR, downstream CI пиннит `replace ../<upstream>` к feature branch (e.g. kacho-iam CI пиннит `replace ../kacho-corelib => github.com/PRO-Robotech/kacho-corelib KAC-127`). После merge'а upstream PR → ref на main; локально `go.work` уже main-ref-friendly через worktree.

---

## 9. Out-of-scope для этой phase (НО IN scope для дальнейших phases — НЕ "deferred")

| Item | Where | Why not here |
|---|---|---|
| OpenFGA model v2 deploy + Conditions CEL evaluator + OPA sidecar bundle signing | **Phase 3** | AuthZ engine; зависит от готовой `access_binding_conditions` (Phase 1) + AuthN ext_claims (Phase 2) |
| ListObjects per-service integration + cache invalidation | **Phase 4** | List filtering; зависит от Phase 3 |
| ServiceAccount IssueKey RPC (Class A Hydra static client) + FederationExchangeService (Class B Token Exchange RFC 8693) | **Phase 5** | Workload Identity Federation; Phase 2 предполагает SA OAuth clients существуют (manual provisioning); Phase 5 автоматизирует |
| SCIM 2.0 endpoint + Boxyhq Jackson SAML bridge + per-Organization SSO UI | **Phase 6** | Enterprise SSO; зависит от готовой `scim_user_mappings` |
| ActivateJIT RPC + Approval workflow + Break-glass 2-person flow + Access Reviews + GDPR erasure cron | **Phase 7** | PIM/JIT lifecycle; зависит от `access_bindings_jit_eligibility` |
| CAEP drainer + SET signing + webhook delivery + exponential retry/backoff (Phase 2 пишет `caep_outbox` rows, но webhook delivery — Phase 8) | **Phase 8** | Real-time revoke; Phase 2 emit'ит события в `caep_outbox`, Phase 8 добавит drainer |
| Kafka audit topic + ClickHouse + S3+Glacier + HSM batch signing + Merkle chain + SIEM forwarders (Phase 2 пишет `audit_outbox` rows; Kafka producer / ClickHouse consumer — Phase 9) | **Phase 9** | Audit pipeline; Phase 2 emit'ит события в `audit_outbox` |
| SPIRE Server + Agent + Cilium service mesh + cosign image-signature attestor + shared DPoP replay cache | **Phase 10** | In-cluster Workload Identity (Class C); Phase 2 DPoP replay cache per-pod (acceptable risk) |
| Multi-region active-active + api.kacho.cloud TLS + Cloudflare WAF + cert-manager + Argo CD + Grafana + Alertmanager + runbooks | **Phase 11** | Production deployment + Observability |
| OWASP ASVS L3 conformance + continuous fuzzing + chaos + pentest + bug bounty + OpenID Foundation cert + FIDO WebAuthn conformance | **Phase 12** | Security verification |
| Vault closeout (30+ files) + production runbooks finalization | **Phase 13** | Documentation |

**Production edition note**: ничего из перечисленного выше не "deferred" / "follow-up" / "future epic" — всё планируется и закрывается в рамках KAC-127. Phase 2 — production-ready AuthN core, который разблокирует AuthZ (Phase 3) и all subsequent phases.

---

## 10. Open questions

Все open questions resolve'нуты inline до отправки на `acceptance-reviewer` (production edition, запрет на "TBD"):

1. **Q**: kacho-iam hook endpoints (`/iam/v1/hooks/token`, `/iam/v1/hooks/refresh`, `/iam/v1/internal/users:upsertFromIdentity`) — на каком listener'е, internal или public? — **A**: на **internal listener (9091, cluster-internal DNS)**, согласно запрету #6 (Internal admin-UI правило). Hydra ↔ kacho-iam communication остаётся внутри cluster (Kubernetes Service DNS `kacho-iam.kacho-system.svc.cluster.local:9091`); не публикуются на TLS edge. Аутентификация — shared bearer secret `X-Kacho-Hook-Token` (env `KACHO_IAM_HOOK_TOKEN`, provisioned via helm secret). В Phase 10 mTLS via SPIFFE SVID заменит shared secret.

2. **Q**: DPoP replay cache размер / TTL — какие numbers? — **A**: LRU capacity **100K entries** (на pod), TTL **120s** (= 2× iat freshness window). Memory footprint: ~32 bytes per entry × 100K = 3.2MB per pod (acceptable). Cardinality estimate: 10K requests/sec × 60s window = 600K theoretical, но per-pod load = 10K/sec ÷ 3 pods = 3.3K/sec × 60s = 200K entries; 100K — sufficient для steady-state, eviction-by-TTL обрабатывает overflow gracefully (false-negative replay-rejection возможен в edge case бы при > 100K, но iat freshness даёт second layer защиты).

3. **Q**: JWKS rotation — что если worker crash'нулся в середине rotation flow (CTE done, но Hydra POST не успел)? — **A**: На next tick worker делает state-reconciliation: query `oidc_jwks_keys WHERE current=true GROUP BY alg`; для каждой row делает `GET /admin/keys/<kid>` к Hydra — если не найден, POST'ит. Idempotent. CTE гарантирует DB consistency; Hydra-side eventually consistent via reconciliation. Audit row `iam.jwks.reconciled` пишется если detected drift.

4. **Q**: session_revocations cleanup — какой retention? — **A**: **24 hours** (overlap для recently-issued access tokens; access_token_TTL=15min, но keep 24h как safety margin для clock-skew/replay-attempts). Cleanup job runs daily в kacho-iam (`internal/apps/kacho/jobs/session_revocations_cleanup.go`). Refresh-token revoke — Hydra-side (DELETE refresh_tokens row), не нужна в session_revocations.

5. **Q**: Recovery IP-bind strict vs relaxed? — **A**: Phase 2 — **strict** (exact match X-Forwarded-For). Edge cases (mobile carriers с rotating IPs, corporate NAT с changing public IP) приведут к failure — пользователь должен request new link с правильного IP. Phase 12 (post-pentest) может смягчить до /24 subnet match (если бизнес-impact оправдывает). Audit row `authn.recovery.ip_mismatch` пишется для observability.

6. **Q**: TOTP — что если пользователь потерял authenticator app, но имеет valid password (no Passkey, no backup-code)? — **A**: Reset через email-verified recovery (Scenario 6.9.1); после magic-link click — force re-enrollment TOTP (или Passkey). Phase 2 supports both fallback paths.

7. **Q**: `kacho_device_compliance` claim — как заполняется? — **A**: Phase 2 — heuristic: `"attested"` если AMR contains `"webauthn"` (assumes authenticator hardware-bound), `"unknown"` otherwise. **Real attestation chain validation** — Phase 12 (full FIDO Alliance certification path: parse attestation statement, verify against authenticator metadata service `mds.fidoalliance.org`, validate AAGUID against allowlist). Phase 2 принимает heuristic как production-acceptable baseline (matches industry default; Auth0/Okta делают то же).

8. **Q**: Conditional UI fallback — что если browser не поддерживает (Safari < 16)? — **A**: SigninPage детектит через `if (!PublicKeyCredential.isConditionalMediationAvailable?.())` → показывает explicit "Sign in with Passkey" button (Scenario 6.2.2 path). UX degrades gracefully.

9. **Q**: Refresh-token reuse-grace-window 1s — достаточно? — **A**: Hydra default; покрывает legitimate concurrent refresh (tabs / parallel requests); attacker имеющий stolen refresh-token reuses в течение 1s window — детектируется как race, family НЕ revoke'нется, но second request fails (400). Trade-off: false-positive family-revoke (legit user inconvenienced re-signin) vs false-negative reuse (attacker undetected). 1s — industry default, acceptable.

10. **Q**: token_hook timeout — что если kacho-iam slow? — **A**: Hydra default token_hook timeout = 5s. Если kacho-iam latency > 5s → Hydra fails token issuance → user sees `400 server_error`. Mitigation: token_hook handler — fast read-only path (lookup в users + accounts, без вызова OpenFGA — это Phase 3). p99 latency target ≤ 50ms (in-memory lookup на pre-warmed pgx pool). k6 load test (см. §7.1) verifies.

11. **Q**: Cookie SameSite=Strict — что если UI на subdomain отличном от api? — **A**: kacho-ui на `app.kacho.cloud`; api на `api.kacho.cloud` — same eTLD+1 (`kacho.cloud`); SameSite=Strict cookie set на `app.kacho.cloud` available для fetch к `api.kacho.cloud` через CORS с credentials. CORS config api-gateway: `Access-Control-Allow-Origin: https://app.kacho.cloud; Access-Control-Allow-Credentials: true`. Verified in Scenario 6.4.1 happy-path Newman test.

12. **Q**: WebCrypto non-extractable key persistence — что если user clears IndexedDB? — **A**: Key пропадает; refresh-token cookie всё ещё valid, но access-token при следующем refresh не сможет быть DPoP-bound (no private key для DPoP JWT). UI детектит missing key в IndexedDB → triggers forced re-signin (через `cnf.jkt` mismatch на первом request → 401 → UI redirects to login). Inconvenience но secure: user re-authenticates, new keypair generated, new DPoP-bound tokens.

13. **Q**: Hydra-admin endpoint — какой network access pattern? — **A**: Hydra-admin (`hydra.kacho-system.svc.cluster.local:4445`) — cluster-internal only (не публичный); accessible from kacho-iam pods (JWKS rotation worker, ForceLogout use-case). Network policy denies all non-kacho-iam pods (Phase 10 Cilium AuthorizationPolicy; Phase 2 — namespace-level NetworkPolicy в helm).

14. **Q**: Force-logout: что если admin force-logout'ит SAM, у которого ещё нет active sessions? — **A**: Idempotent — `session_revocations` INSERT ON CONFLICT (token_jti) DO NOTHING (jti может уже быть revoked); Hydra-admin `DELETE /oauth2/auth/sessions/login` returns 204 без error если session not found. CAEP outbox row пишется один раз (idempotency через unique-by-`(subject, event_id)`). Audit row пишется один раз через `(request_id, event_type)` partial UNIQUE.

15. **Q**: HIBP API rate-limiting — что если HIBP down или rate-limited? — **A**: HIBP range-API `api.pwnedpasswords.com` — public, no auth, generous rate-limit (typically не лимитирует разумных consumers). На production timeout (3s) → клиент пропускает HIBP check + WARNING logged (`authn.hibp.check_skipped`). Fail-open (НЕ блокировать signup из-за HIBP down) — UX > security здесь, потому что HIBP — additional layer (Argon2id уже защищает); Phase 12 может ужесточить до fail-closed по результатам threat model.

---

> Конец acceptance-документа. Передаётся `acceptance-reviewer` для проверки coverage / completeness / traceability / scope. После `✅ APPROVED` статус выше — DRAFT → APPROVED, и начинается Phase 2 implementation (tasks 2.2–2.9 per plan).
