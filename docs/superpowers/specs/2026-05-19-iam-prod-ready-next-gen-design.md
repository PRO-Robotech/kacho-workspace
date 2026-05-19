# Kachō IAM — Production-ready Next-Gen Design (KAC-127 vault-label / YT KAC-123)

**Дата**: 2026-05-19
**Status**: DRAFT (awaiting acceptance docs per-phase)
**YouTrack**: KAC-123 (https://prorobotech.youtrack.cloud/issue/KAC-123)
**Workspace skill применён**: `.claude/skills/iam-architect/` (SKILL.md + 7 references)
**Vision-предусловие**: `docs/superpowers/specs/2026-05-19-iam-revolutionary-architecture-design.md`
**Baseline (in main)**: KAC-108 (OpenFGA E3) + KAC-125 (User per-Account + Invite)
**Superseded by this**: KAC-126 design (incremental → реализуется через KAC-127 phases (YT KAC-123)).

---

## 0. TL;DR

Этот документ — **production-ready** spec для полной перестройки Kachō IAM, выбирающий из revolutionary architecture document'а всё, что **готово к 2026-Q2 production**, и **исключающий тяжёлую аудит-инфраструктуру** (Kafka audit-topic, ClickHouse OLAP, S3+Glacier cold storage, HSM batch signing, SIEM webhooks, Merkle-chain tamper-evidence). Audit на этом этапе — минимум через `slog` + `audit_outbox` table-skeleton под будущий migration.

8 phases:
1. **Foundation** — data model (Cluster/Organization/ext entities), bootstrap migration.
2. **AuthN core** — WebAuthn/Passkey + DPoP-bound JWT + step-up.
3. **AuthZ core** — OpenFGA model v2 (cluster→org→account→project→resource) + Conditions + OPA guardrails.
4. **List filtering** — OpenFGA `ListObjects` per List-handler.
5. **Workload Identity** — SA tokens (Hydra Class A) + Federation Trust Policies (Class B: GitHub/AWS/GCP).
6. **Enterprise SSO** — SCIM 2.0 inbound + SAML bridge (Jackson/WorkOS).
7. **JIT / PIM** — Just-in-Time elevation + Break-glass с 2-person approve.
8. **CAEP push** — real-time revoke propagation ≤ 10s через push-based webhooks для SP-subscribers.

**Excluded (отложено в будущие эпики)**:
- Audit pipeline hardening (Kafka audit-topic, ClickHouse OLAP, S3+Glacier cold, HSM batch signing, SIEM webhooks, Merkle-chain tamper-evidence).
- **Workload Identity & in-cluster mTLS** (SPIFFE/SPIRE + service mesh Cilium/Linkerd) — отдельный эпик после первой production-итерации. На MVP service-to-service auth = cluster network policies + Internal listener + end-user principal forwarding в gRPC metadata (как сейчас в KAC-108).

---

## 1. Decision Log (final, supersedes KAC-126 D-list)

| # | Decision | Alternative considered | Why |
|---|---|---|---|
| D-1 | **AuthN stack = ORY Kratos + Hydra**, Zitadel out | Zitadel monolith | Open-source, decoupled identity ↔ OIDC issuer; Kratos hooks для invite/recovery |
| D-2 | **AuthZ engine = OpenFGA** (Keto deprecated, Cedar/SpiceDB out for now) | SpiceDB, Cedar, Keto | KAC-108 baseline; mature ListObjects + Conditions; Auth0 backing |
| D-3 | **OPA sidecar** для org-wide deny guardrails | Inline в kacho-iam | Rego — industry standard; K8s admission compat |
| D-4 | **Identity hierarchy** = cluster → organization (optional) → account → project → resource | Single-level Account | B2B enterprise customers need org grouping для SCIM/SAML/billing |
| D-5 | **Custom Role multi-scope** (project / account / organization) | Только project | Реальная гибкость: team shares cross-project role; org-wide shared roles |
| D-6 | **DPoP-bound JWT** (RFC 9449) для SPA/mobile; mTLS-bound для backend M2M | Bearer JWT | Token theft mitigation |
| D-7 | **WebAuthn/Passkey-first** AuthN; TOTP fallback; SMS deprecated for AAL2+ | Password+TOTP | Phishing-resistant; NIST 800-63B AAL2 by Passkey alone |
| D-8 | **Workload Identity Federation** для CI/CD (GitHub/AWS/GCP) через RFC 8693 Token Exchange | Static client_secret only | Zero static M2M secrets |
| D-9 | **SCIM 2.0** endpoint для enterprise inbound | Manual user import | Auto-provisioning из Okta/Azure/Google Workspace |
| D-10 | **SAML 2.0** через bridge (Jackson или WorkOS) | Native SAML в Kratos | Kratos OSS не имеет SAML; bridge простой |
| D-11 | **AccessBinding.status** ∈ {PENDING, ACTIVE, REVOKED} | Hard-delete row | Audit retention; GDPR-compliant |
| D-12 | **Conditions overlay** на AccessBinding (CEL-like) — time/IP/MFA/JIT-window | Static permissions only | ABAC overlay поверх ReBAC |
| D-13 | **PIM/JIT elevation** для admin-роль; standing admin = exception | Standing admin | Reduce insider attack surface |
| D-14 | **Break-glass** = 2-person approve + PagerDuty alert + 2h auto-expire | Single-admin emergency | NIST best practice |
| D-15 | **CAEP push pipeline** для revoke ≤ 10s глобально | TTL-only invalidation | Real-time security signal propagation |
| D-16 | **Workload Identity (SPIFFE/SPIRE) и service mesh mTLS — out of scope MVP**; отдельный future эпик. На MVP service-to-service auth = K8s NetworkPolicy + Internal listener + end-user principal forwarding | Полная mesh-инфра с deploy дня 1 | Pragmatic — mesh deploy + integration в каждом сервисе = недели работы; KAC-108 уже даёт защиту через end-user principal в gRPC metadata; defense-in-depth уровень "достаточно" для production-MVP |
| D-17 | **Cluster:singleton** OpenFGA-объект для kacho-system:* roles | Static env-list / Domain-suffix | Гомогенно с моделью; audit-trail |
| D-18 | **Audit pipeline = MINIMUM** (slog → stdout + `audit_outbox` skeleton); полноценная Kafka+ClickHouse+S3 — отложено | Full pipeline | User explicit out-of-scope для production-ready MVP |
| D-19 | **Migration strategy** = greenfield wipe `kacho_iam` schema; no prod tenants | Dual-write migration | dev-стенд e2c825 only |

---

## 2. Architecture (concrete components)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              EDGE                                        │
│ Cloudflare WAF → kacho-api-gateway (TLS edge)                            │
│                       │ JWT(DPoP) validate via Hydra JWKS                │
│                       │ Principal in ctx (gRPC metadata)                 │
│                       │ Service-to-service: cluster-internal listener +  │
│                       │   K8s NetworkPolicy (mesh/SPIFFE — future epic)  │
└──────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                        IDENTITY PLANE                                     │
│ ┌────────────────────┐  ┌────────────────────┐  ┌────────────────────┐  │
│ │ ORY Kratos          │  │ ORY Hydra          │  │ SAML/OIDC bridge   │  │
│ │ (identity store +   │  │ (OAuth2.1 + OIDC + │  │ (Jackson — for B2B │  │
│ │  WebAuthn / Passkey │  │  DPoP + JWKS)      │  │  SCIM-less)        │  │
│ │  + Hooks)           │  │                    │  │                    │  │
│ └────────────────────┘  └────────────────────┘  └────────────────────┘  │
│                       │                                                   │
│        Workload Identity Federation (Trust Policy engine in kacho-iam)   │
│                       │                                                   │
│        SCIM 2.0 endpoint (/scim/v2/Users, /Groups) in kacho-iam          │
└──────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       AUTHORIZATION PLANE                                 │
│ ┌──────────────────────┐  ┌──────────────────────┐                       │
│ │ OpenFGA              │  │ OPA sidecar           │                       │
│ │ - Check / ListObjects│  │ - Org-wide deny rules │                       │
│ │ - Conditions (CEL)   │  │ - Rego policies       │                       │
│ │ - Contextual tuples  │  │                       │                       │
│ │ - Outbox-sync from DB│  │                       │                       │
│ └──────────────────────┘  └──────────────────────┘                       │
│                                                                            │
│ kacho-iam — Role catalog, binding lifecycle, PIM/JIT logic, CAEP emit    │
│ corelib/authz/ — Check + ListObjects clients; cache 5s + LISTEN-invalid. │
└──────────────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       EVENT PLANE (MINIMUM)                              │
│ ┌──────────────────────┐  ┌──────────────────────┐                       │
│ │ audit_outbox table   │  │ caep_outbox table     │                       │
│ │ → slog/stdout drainer│  │ → webhook drainer     │                       │
│ │ (full pipeline TBD)  │  │ (real-time revoke push│                       │
│ │                      │  │ to subscribed SPs)    │                       │
│ └──────────────────────┘  └──────────────────────┘                       │
└──────────────────────────────────────────────────────────────────────────┘
```

> **Workload Identity (SPIFFE/SPIRE) и in-cluster service mesh mTLS — out of scope** этого эпика;
> отдельный future эпик. На MVP service-to-service auth = K8s NetworkPolicy + Internal listener
> + end-user principal forwarding в gRPC metadata. Это **сохраняет** существующий defense-in-depth
> уровень KAC-108 без новых тяжёлых инфра-компонентов.

### Component versions (target 2026-Q2)

| Component | Version | Notes |
|---|---|---|
| ORY Kratos | v1.4+ | WebAuthn + recovery hooks |
| ORY Hydra | v2.4+ | DPoP support, JWT introspect |
| OpenFGA | v1.6+ | Conditions stable; ListObjects optimized |
| OPA | v1.0+ | Rego v1; bundle pull mode |
| Postgres | 16+ | LISTEN/NOTIFY; partial UNIQUE; CHECK |
| Go | 1.22+ (already) | slog stdlib |
| ~~SPIRE~~ | — | out of scope MVP (future epic) |
| ~~Linkerd / Cilium~~ | — | out of scope MVP (future epic) |

---

## 3. Identity Model (final entity schema)

See `references/identity-model.md` (skill ref) for full detail. Summary tables here.

### 3.1 Tables `kacho_iam` schema (post-migration `0011`)

| Table | Purpose | Status (vs KAC-108/126) |
|---|---|---|
| `clusters` | singleton row, id=`cluster_kacho_root` | NEW in KAC-127 (YT KAC-123) |
| `cluster_admin_grants` | source-of-truth for system_admin tuples | NEW |
| `cluster_break_glass_grants` | time-bounded emergency grants + audit | NEW |
| `organizations` | optional B2B tier above Account | NEW |
| `accounts` | existing + adds `organization_id` FK NULL | EXTEND |
| `projects` | existing | unchanged |
| `users` | existing per-Account; KAC-125 schema | unchanged |
| `service_accounts` | existing; adds `project_id` (preferred) + `enabled` | EXTEND |
| `service_account_oauth_clients` | Class A: static OAuth client mapping | NEW |
| `federation_trust_policies` | Class B: OIDC federation rules | NEW |
| `groups` | existing; adds `scim_managed` + `external_id` | EXTEND |
| `group_members` | existing | unchanged |
| `roles` | existing; `account_id` → multi-scope: `cluster_id`/`organization_id`/`account_id`/`project_id` (one non-NULL) | REFACTOR |
| `access_bindings` | existing; adds `status` (PENDING/ACTIVE/REVOKED), `expires_at`, `condition_id` | EXTEND |
| `access_binding_conditions` | CEL-like expressions for ABAC overlay | NEW |
| `access_bindings_jit_eligibility` | who can self-activate which role | NEW |
| `access_reviews` + `access_review_items` | recertification cycles | NEW |
| `audit_outbox` | append-only event log skeleton (drainer = slog/stdout for MVP) | NEW |
| `caep_outbox` | CAEP event queue → webhook drainer | NEW |
| `caep_subscribers` | SP-registered CAEP webhooks | NEW |
| `gdpr_erasure_requests` | future async erasure pipeline (Phase 9) | NEW (schema only) |

### 3.2 Lifecycle state machines

```
User:           PENDING → ACTIVE → BLOCKED → DELETED (Phase 9: erasure)
SA:             ACTIVE → DISABLED → DELETED (keys revoked first)
AccessBinding:  PENDING → ACTIVE → REVOKED (soft; row retained)
Account:        ACTIVE → SUSPENDED → DELETED (Phase 9: cool-off pipeline)
Organization:   ACTIVE → ARCHIVED → DELETED
Project:        ACTIVE → ARCHIVED → DELETED
Group:          ACTIVE → DELETED (SCIM-managed = immutable from UI)
Custom Role:    ACTIVE → DELETED (only if no active bindings; FK RESTRICT)
```

### 3.3 ID conventions (Crockford-base32 unless noted)

| Entity | Prefix | Length |
|---|---|---|
| Cluster | `cluster_kacho_root` | hardcoded singleton |
| Organization | `org_` | 20 |
| Account | `acc_` | 20 |
| Project | `prj_` | 20 |
| User | `usr_` | 20 |
| ServiceAccount | `sva_` | 20 |
| Group | `grp_` | 20 |
| Role (custom) | `rol_` | 20 |
| Role (system) | `rol_kacho_<name>` | deterministic |
| AccessBinding | `acb_` | 20 |
| Federation policy | `ftp_` | 20 |
| Condition | `cond_` | 20 |
| Audit event | `evt_<ULID>` | time-sortable |

---

## 4. OpenFGA Authorization Model v2 (final DSL)

```
model
  schema 1.1

# === Subject types ===
type user
type service_account
type group
  relations
    define member: [user, service_account, group#member]

# === Cluster (singleton) ===
type cluster
  relations
    define system_admin:    [user, service_account]
    define emergency_admin: [user with break_glass_window]
    define system_viewer:   [user, service_account]
    define any_admin:       system_admin or emergency_admin

# === Organization (optional B2B tier) ===
type organization
  relations
    define cluster:       [cluster]
    define owner:         [user]
    define admin:         [user, service_account, group#member]
                          or any_admin from cluster
                          or owner
    define editor:        [user, service_account, group#member] or admin
    define viewer:        [user, service_account, group#member] or editor
    define billing_admin: [user] or admin

# === Account ===
type account
  relations
    define cluster:       [cluster]
    define organization:  [organization]
    define owner:         [user]
    define admin:         [user, service_account, group#member]
                          or any_admin from cluster
                          or admin from organization
                          or owner
    define editor:        [user, service_account, group#member] or admin or editor from organization
    define viewer:        [user, service_account, group#member] or editor or viewer from organization

# === Project ===
type project
  relations
    define account: [account]
    define admin:   [user, service_account, group#member] or admin from account
    define editor:  [user, service_account, group#member] or admin or editor from account
    define viewer:  [user, service_account, group#member] or editor or viewer from account

# === Per-service resources (pattern; repeat для vpc_subnet, compute_instance, etc.) ===
type vpc_network
  relations
    define project: [project]
    define admin:   [user, service_account, group#member] or admin from project
    define editor:  [user, service_account, group#member] or editor from project or admin
    define viewer:  [user, service_account, group#member] or viewer from project or editor

type compute_instance
  relations
    define project: [project]
    define admin:   [user, service_account, group#member] or admin from project
    define editor:  [user, service_account, group#member] or editor from project or admin
    define viewer:  [user, service_account, group#member] or viewer from project or editor
    define ssh:     [user with mfa_fresh, service_account] or admin
    define console: [user with mfa_fresh] or admin

# === Conditions (ABAC overlay) ===

condition mfa_fresh(amr_claims: list<string>, acr_value: string, current_time: timestamp, mfa_at: timestamp) {
  acr_value == "3" &&
  "webauthn" in amr_claims &&
  current_time - mfa_at < duration("15m")
}

condition non_expired(current_time: timestamp, valid_until: timestamp) {
  current_time < valid_until
}

condition source_ip_in_range(client_ip: ipaddress, allowed_cidrs: list<ipaddress>) {
  client_ip in allowed_cidrs
}

condition break_glass_window(current_time: timestamp, expires_at: timestamp) {
  current_time < expires_at
}

condition business_hours(current_time: timestamp, tz: string, start_h: int, end_h: int) {
  hour_of_day(current_time, tz) >= start_h && hour_of_day(current_time, tz) < end_h
}

condition jit_window(current_time: timestamp, activated_at: timestamp, ttl_seconds: int) {
  current_time - activated_at < duration(format("%ds", ttl_seconds))
}
```

### 4.1 OPA guardrails (Rego)

```rego
package kacho.iam.guardrails

# Deny: destructive ops on billing-* projects unless cluster-admin
deny[msg] {
  input.action in {"projects.delete", "accounts.delete"}
  startswith(input.resource.id, "prj_billing_")
  not input.principal.cluster_admin
  msg := sprintf("destructive op on billing project requires cluster-admin (got %v)", [input.principal.id])
}

# Deny: SA cannot grant role to user (escalation prevention)
deny[msg] {
  input.action == "access_bindings.upsert"
  input.principal.type == "service_account"
  input.target.subject_type == "user"
  msg := "service accounts may not grant roles to users"
}

# Deny: granting org-wide role to user not in organization SCIM-set
deny[msg] {
  input.action == "access_bindings.upsert"
  input.target.resource_type == "organization"
  org_id := input.target.resource_id
  not user_in_organization(input.target.subject_id, org_id)
  msg := sprintf("user %v not member of organization %v", [input.target.subject_id, org_id])
}

# Deny: max session lifetime for break-glass = 2h
deny[msg] {
  input.action == "cluster.break_glass.grant"
  input.duration_seconds > 7200
  msg := "break-glass grant cannot exceed 2 hours"
}
```

---

## 5. AuthN — concrete flows

### 5.1 Token shapes

```
Access Token (JWT, signed RS256, TTL 15min):
{
  iss: "https://hydra.kacho.cloud",
  sub: "usr_alice_acc_a1b2",     # User row id (per-Account); maps to identity via external_id
  aud: "https://api.kacho.cloud",
  exp: ..., iat: ..., jti: <uuid>,
  acr: "2",                       # AAL2 (Passkey)
  amr: ["webauthn"],
  cnf: { jkt: "<DPoP-thumbprint>" },  # DPoP binding
  scope: "openid profile",
  ext_claims: {
    kacho_external_id: "<Kratos sub>",
    kacho_active_account: "acc_a1b2",
    kacho_organization_id: "org_acme" | null,
    kacho_groups: ["grp_eng", ...]   # rarely; usually look up at Check time
  }
}

Service Account Token (JWT, RS256, TTL 60min):
{
  iss: "https://hydra.kacho.cloud",
  sub: "sva_ci_deployer",
  aud: "https://api.kacho.cloud",
  scope: "kacho.iam kacho.vpc kacho.compute",
  client_id: "sva_ci_deployer",
  ext_claims: {
    kacho_principal_type: "service_account",
    kacho_account_id: "acc_a1b2",
    kacho_project_id: "prj_default"
  }
}

DPoP JWT (per-request, ES256/Ed25519, TTL 60s):
{
  typ: "dpop+jwt",
  alg: "ES256",
  jwk: { ... },                    # public key embedded
  htm: "POST",
  htu: "https://api.kacho.cloud/iam/v1/access_bindings:upsert",
  iat: ..., jti: <uuid>
}
```

### 5.2 Token validation pipeline (api-gateway)

```
On each request:
  1. Extract Authorization header → parse type (DPoP|Bearer).
  2. Verify JWT signature via Hydra JWKS (cached 24h; refresh on kid miss).
  3. Validate iss/aud/exp/nbf/iat (clock skew ≤5min).
  4. Check jti not in session_revocations table (CAEP-managed; 30-day TTL).
  5. If DPoP:
     a. Parse DPoP header JWT.
     b. Verify signature with embedded jwk.
     c. Validate cnf.jkt thumbprint matches.
     d. Validate htm/htu match request.
     e. Validate iat fresh (≤60s); jti not in DPoP-replay cache (2min TTL).
  6. Extract principal → gRPC metadata → ctx for downstream services.
```

### 5.3 Session lifetimes

| Token | Lifetime | Rotation |
|---|---|---|
| Access (user) | 15 min | Refresh-rotation |
| Refresh (user) | 30 days | One-time-use; family-revoke on reuse |
| ID token | 15 min | Re-issue from refresh |
| Access (SA, client_credentials) | 60 min | Re-acquire on demand |
| Magic-link (recovery, invite) | 7d max; 15min recovery | Single-use |
| WebAuthn challenge | 60 sec | One-time |
| DPoP JWT | per-request | jti cache 2min |
| Federation exchange | 15 min | New OIDC exchange |
| Session cookie | 30min idle / 8h absolute | Rotate on AAL change |
| Step-up elevation | 15 min | Re-challenge |
| JIT admin elevation | 1h default (max 8h) | Re-activate |
| Break-glass elevation | 2h max | Auto-expire |

### 5.4 ORY config snippets (target)

`kratos.yml`:
```yaml
identity:
  default_schema_id: kacho_user_v1

selfservice:
  flows:
    registration:
      enabled: true
      after:
        webauthn:
          hooks:
            - hook: web_hook
              config:
                url: http://kacho-iam:9091/v1/internal/users:upsertFromIdentity
                method: POST
                body: file:///hooks/upsert-identity.jsonnet
                response:
                  ignore: false      # block registration on hook failure
                  parse: false
    login:
      ui_url: https://kacho.cloud/sign-in
      after:
        password:
          hooks: [{ hook: revoke_active_sessions }, { hook: require_aal2 }]
        webauthn: [...]

  methods:
    password: { enabled: true, config: { min_password_length: 14, identifier_similarity_check_enabled: true } }
    webauthn: { enabled: true, config: { passwordless: true, rp: { display_name: Kachō, id: kacho.cloud } } }
    totp: { enabled: true }
```

`hydra.yml`:
```yaml
strategies:
  access_token: jwt
  jwt:
    scope_claim: list

urls:
  self:
    public: https://hydra.kacho.cloud
    admin:  http://hydra-admin.internal:4445
  consent: https://kacho.cloud/oauth/consent
  login:   https://kacho.cloud/oauth/login

ttl:
  access_token: 15m
  refresh_token: 720h         # 30 days
  id_token: 15m
  auth_code: 1m

oauth2:
  pkce: { enforced: true, enforced_for_public_clients: true }
  refresh_token_hook: http://kacho-iam:9091/v1/internal/hydra:refresh_hook   # rotation check
  token_hook: http://kacho-iam:9091/v1/internal/hydra:token_hook              # injects ext_claims
  dpop: { enabled: true }
  expose_internal_errors: false
```

---

## 6. Workload Identity (concrete)

### 6.1 Class A (Hydra OAuth client_credentials)

```
ServiceAccount SA1
    │
    ├─ DB row: sva_ci (project_id, account_id, name, enabled)
    │
    ├─ hydra-admin POST /admin/clients:
    │     { client_id: "sva_ci", grant_types: ["client_credentials"], scope: "kacho", token_endpoint_auth_method: "client_secret_basic" }
    │     → { client_id: "sva_ci", client_secret: "<random>" }
    │
    └─ DB: INSERT service_account_oauth_clients (sva_id, hydra_client_id);
       return secret to user ONE-SHOT.

External system uses:
    POST https://hydra.kacho.cloud/oauth2/token
      -u sva_ci:<secret>
      -d grant_type=client_credentials
      → access_token (JWT, 60min)
```

### 6.2 Class B (Workload Identity Federation — recommended for CI/CD)

```
Trust policy (admin creates):
    id: ftp_<id>
    service_account_id: sva_ci_deployer
    issuer: https://token.actions.githubusercontent.com
    audience: https://api.kacho.cloud
    subject_pattern: "repo:my-org/my-repo:ref:refs/heads/main"
    additional_claims_filter: { environment: "production" }
    conditions: [ { source_ip_in: ["140.82.112.0/20"] } ]   # GitHub IPs
    max_token_ttl: 15m
    expires_at: 2026-12-31T00:00:00Z

External CI requests:
    1. GitHub Actions runtime → OIDC token (signed by GitHub).
    2. POST /iam/v1/federations:exchange
         grant_type=urn:ietf:params:oauth:grant-type:token-exchange
         subject_token=<GitHub JWT>
         subject_token_type=urn:ietf:params:oauth:token-type:jwt
    3. kacho-iam FederationExchangeService:
         - Verify GitHub JWKS (cached 24h).
         - Match against federation_trust_policies WHERE issuer=GitHub AND subject_pattern matches.
         - Apply Conditions (source_ip in CIDR, expires_at).
         - Emit audit event "federation.exchange.success".
         - Issue Kachō JWT (sub=sva_ci_deployer, TTL=15min).
```

### 6.3 In-cluster service-to-service auth (MVP, без mesh)

> **SPIFFE/SPIRE + service mesh — out of scope MVP**; см. D-16 и §0 «Excluded». Этот раздел описывает то, что **остаётся** на этой итерации.

```
В кластере kacho-* сервисы общаются через cluster-internal listener (порт 9091, без TLS).
Защита идёт через два слоя, оба уже на месте после KAC-108:

1. K8s NetworkPolicy:
     - Internal listener (9091) принимает соединения только из kacho-* ServiceAccounts.
     - Внешние pods (или скомпрометированный customer-workload pod) не могут открыть TCP.
     - Селекторы по namespace + serviceAccount.

2. End-user principal forwarding:
     - api-gateway валидирует JWT (DPoP) → ставит principal в gRPC metadata
       `x-kacho-end-user-principal=usr_alice_acc_a1b2`.
     - Backend services (vpc/compute/lb/iam) при internal-call'е тоже **forward**
       тот же principal дальше (whitelist-fields propagation).
     - Authz всегда основан на этом principal, НЕ на caller-service identity.
     - Это значит: компромисс одного pod-а не даёт права end-user'а Bob'а
       (нужно, чтобы JWT Bob'а реально прошёл api-gateway).

3. TLS edge (snippet):
     - Между cluster-external (Cloudflare → kacho-api-gateway:443) — TLS.
     - Между kacho-api-gateway → backend сервисами — plaintext gRPC внутри cluster
       (K8s NetworkPolicy + cluster-internal сеть).

Будущий эпик (после MVP):
     - SPIFFE/SPIRE deploy → каждый pod получает SVID.
     - Service mesh (Cilium или Linkerd) → автоматический mTLS sidecar/eBPF.
     - AuthorizationPolicy с SPIFFE-ID-based allowlist.
     - Defense-in-depth: mesh-identity + end-user principal оба проверяются.
     - Это **расширяет** существующий defense, не заменяет.
```

---

## 7. List filtering (final design)

Replaces KAC-108 D-8 "single parent-Check". Now: every List-RPC in vpc/compute/lb uses `ListObjects`.

```go
// vpc.NetworkService.List
func (s *NetworkService) List(ctx context.Context, req *vpcv1.ListNetworksRequest) (*vpcv1.ListNetworksResponse, error) {
    principal := authn.MustPrincipal(ctx)

    allowedIDs, err := s.authz.ListAllowedIDs(ctx, principal, "vpc_network", "viewer", authz.ListObjectsOptions{
        Consistency: authz.MINIMIZE_LATENCY,
        ProjectScope: req.ProjectId,   // hint for OpenFGA contextual_tuples (optional)
    })
    if err != nil {
        return nil, status.Errorf(codes.Unavailable, "authz lookup failed: %v", err)
    }
    if len(allowedIDs) == 0 {
        return &vpcv1.ListNetworksResponse{Networks: nil}, nil
    }

    networks, nextToken, err := s.repo.ListByIDs(ctx, allowedIDs, req.PageSize, req.PageToken)
    if err != nil {
        return nil, status.Errorf(codes.Internal, "db query failed: %v", err)
    }
    return &vpcv1.ListNetworksResponse{Networks: networks, NextPageToken: nextToken}, nil
}
```

### 7.1 corelib/authz interface (final)

```go
package authz

type Principal struct {
    ID       string // usr_..., sva_...
    Type     string // "user" | "service_account"
    AccountID    string
    OrganizationID string
    SessionACR   string
    SessionAMR   []string
    SessionMFAAt time.Time
    SourceIP     net.IP
}

type CheckClient interface {
    Check(ctx context.Context, p Principal, relation, objectType, objectID string, ctxTuples ...ContextualTuple) (allowed bool, err error)
}

type ListObjectsClient interface {
    ListAllowedIDs(ctx context.Context, p Principal, objectType, relation string, opts ListObjectsOptions) (ids []string, consistencyToken string, err error)
}

type ListObjectsOptions struct {
    Consistency      Consistency      // MINIMIZE_LATENCY | HIGHER_CONSISTENCY | AT_LEAST_AS_FRESH
    ConsistencyToken string           // from previous Write
    ContextualTuples []ContextualTuple
}
```

### 7.2 Cache + invalidation

```go
// Internal: LRU with 5s TTL per (principal_id, object_type, relation).
// Background: pgx.LISTEN("kacho_iam_subjects") → on NOTIFY subject_id, invalidate all cache entries containing that subject.
// On any Write to access_bindings → emit NOTIFY in same TX.
```

### 7.3 SLA

| Op | p50 | p95 | p99 |
|---|---|---|---|
| Check (cache hit) | 0.1ms | 0.5ms | 1ms |
| Check (cache miss) | 5ms | 20ms | 50ms |
| ListObjects (cache hit) | 0.1ms | 0.5ms | 1ms |
| ListObjects (cache miss, ≤100 ids) | 10ms | 50ms | 100ms |
| ListObjects (cache miss, ≤1000 ids) | 25ms | 100ms | 250ms |

---

## 8. Service catalog & permission registry

Build pipeline auto-generates permission catalog из proto annotations:

```protobuf
import "kacho/iam/v1/authz.proto";

service NetworkService {
  rpc Create(CreateNetworkRequest) returns (operation.Operation) {
    option (kacho.iam.authz.permission) = "vpc.networks.create";
    option (kacho.iam.authz.required_relation) = "editor";
    option (kacho.iam.authz.scope_extractor) = {
      object_type: "project",
      from_request_field: "project_id"
    };
  }
  rpc Get(GetNetworkRequest) returns (Network) {
    option (kacho.iam.authz.permission) = "vpc.networks.get";
    option (kacho.iam.authz.required_relation) = "viewer";
    option (kacho.iam.authz.scope_extractor) = {
      object_type: "vpc_network",
      from_request_field: "network_id"
    };
  }
  rpc List(ListNetworksRequest) returns (ListNetworksResponse) {
    option (kacho.iam.authz.permission) = "vpc.networks.list";
    option (kacho.iam.authz.list_filter) = {
      object_type: "vpc_network",
      relation: "viewer"
    };
  }
}
```

Build pipeline:
1. `protoc-gen-kacho-permissions` plugin reads annotations → emits `permission_catalog.json` (committed in kacho-proto/gen/).
2. `permission_catalog.json` consumed by kacho-iam at startup → seeded into `system_role_permissions`.
3. UI cascader (KAC-122 style) reads catalog → 3-level cascader (domain → resource → verb).
4. Custom-role creation validates permissions against catalog → reject unknown.

---

## 9. Audit (minimum for this epic; full pipeline = Phase 9 future)

### 9.1 What WE implement

- **`audit_outbox` table** — every mutation writes row in same TX as primary write.
- **Drainer (worker)** — pulls from `audit_outbox` → emits structured `slog.Info` to stdout with `event_type`/`actor`/`target`/`outcome`/`request_id`.
- **K8s log collection** — relies on cluster's native (Loki / kubectl logs) for now.
- **No** Kafka, ClickHouse, S3, HSM, SIEM webhook, Merkle chain.

### 9.2 Event types emitted (MVP set)

```
iam.user.created
iam.user.activated
iam.user.blocked
iam.user.invited

iam.account.created
iam.account.updated
iam.account.suspended

iam.project.created
iam.project.updated
iam.project.deleted

iam.organization.created       (Phase 6)
iam.role.system.upserted        (Internal RPC)
iam.role.custom.created
iam.role.custom.deleted

iam.access_binding.created
iam.access_binding.activated   (PENDING→ACTIVE)
iam.access_binding.revoked

iam.cluster.admin.granted
iam.cluster.admin.revoked
iam.cluster.break_glass.granted   → CAEP+alert
iam.cluster.break_glass.expired

iam.jit.activated
iam.jit.expired

iam.sa.key.created
iam.sa.key.revoked
iam.federation.policy.created
iam.federation.exchange.success
iam.federation.exchange.denied

iam.scim.user.synced
iam.scim.group.synced

authn.signin.success
authn.signin.failure
authn.mfa.enrolled
authn.passkey.created
authn.passkey.revoked
authn.session.revoked
authn.token.refreshed
authn.recovery.completed
```

### 9.3 Future migration to full pipeline (Phase 9)

Schema `audit_outbox` already shaped to fit Kafka producer's expected JSON; switching drainer = swap implementation (no migration needed).

---

## 10. CAEP push pipeline

### 10.1 Schema

```sql
CREATE TABLE caep_subscribers (
  id TEXT PRIMARY KEY,
  account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
  endpoint_url TEXT NOT NULL,
  signing_key_pem TEXT NOT NULL,           -- subscriber's pubkey for verifying SETs we emit; signed-back option
  event_types TEXT[] NOT NULL,             -- subset of session-revoked, token-claims-change, ...
  enabled BOOL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  failure_count INT DEFAULT 0,
  last_success_at TIMESTAMPTZ NULL
);

CREATE TABLE caep_outbox (
  id TEXT PRIMARY KEY,
  event_type TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  attempts INT DEFAULT 0,
  status TEXT CHECK IN ('pending', 'in_flight', 'delivered', 'failed_terminal') DEFAULT 'pending',
  next_attempt_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### 10.2 Event flow

```
[Admin revokes binding]
    │
    ▼
[kacho-iam:
   UPDATE access_bindings SET status='REVOKED'
   INSERT fga_outbox (tuple_delete)
   INSERT caep_outbox (event_type='token-claims-change', subject_id=usr_alice, payload={...})
   NOTIFY 'kacho_iam_subjects' usr_alice]
    │
    ├─→ fga_outbox drainer → OpenFGA Delete tuple ≤ 2s
    ├─→ caep_outbox drainer → for each enabled subscriber matching subject's account:
    │     POST <endpoint> Authorization: Bearer <SET-signed-JWT>
    │     Retry exponential (1s, 5s, 30s, 5min, 1h); max 8 attempts.
    │     On 4xx: mark failed_terminal.
    │     On success: status=delivered + failure_count reset.
    │
    ├─→ Internal CAEP receiver (api-gateway):
    │     INSERT session_revocations (jti, revoked_at, reason, user_id)
    │     Pub/sub → service caches invalidate
    │
    └─→ kacho-iam_subjects NOTIFY → corelib/authz cache invalidate
```

### 10.3 SET (Security Event Token) shape

```json
{
  "iss": "https://api.kacho.cloud",
  "aud": "https://customer-saas.example.com/caep/inbox",
  "iat": 1716000000,
  "jti": "evt_01h2n4z9...",
  "events": {
    "https://schemas.openid.net/secevent/caep/event-type/token-claims-change": {
      "subject": {
        "format": "opaque",
        "id": "usr_alice_acc_a1b2"
      },
      "claims": {
        "kacho_active_account": "acc_a1b2",
        "removed_bindings": ["acb_xyz1", "acb_xyz2"]
      },
      "event_timestamp": 1716000000
    }
  }
}
```

Signed by kacho-iam private key (Hydra-issuer key share).

---

## 11. Threat model

| Threat | Defense |
|---|---|
| Token theft (XSS in browser) | DPoP bound to non-extractable key; CAEP push-revoke; short access TTL |
| Phishing for credentials | Passkey origin-bound; WebAuthn ceremony refuses fake domain |
| Confused deputy (svc A → B with A's privs) | Principal in gRPC metadata; Check uses ctx-principal not service identity |
| Privilege escalation | OPA Deny rules; SA cannot grant to user; binding-creator cannot exceed own privs |
| TOCTOU (Check then act) | Atomic write with UNIQUE constraints + CAS-pattern |
| Stale grants after employee leaves | SCIM lifecycle hook → cascade revoke + CAEP push |
| Open invite link replay | Single-use; bind to email; expiry ≤7d |
| Algorithm confusion (alg=none, HS256-as-public) | Whitelist algs; reject `none`; rotation in JWKS |
| Compromised admin → mass-grant | OPA rate-limit deny; SIEM detection rule (>10 grants/5min) — Phase 9 |
| Insider rouge admin | JIT/PIM + 2-person approve break-glass; audit append-only |
| Stale cache after revoke | LISTEN-NOTIFY + 5s TTL + DPoP-jti CAEP push |
| Lateral movement after pod compromise | K8s NetworkPolicy на internal listener; end-user principal в gRPC metadata (компромет pod-а ≠ компромет end-user токена); CAEP push для быстрого revoke. **(Future:** SPIFFE/SPIRE + mesh mTLS как extra layer — отдельный эпик.) |
| Mass extraction via SA | Rate-limits per-SA; CAEP push on token-claims-change |
| Audit gap (no log) | audit_outbox in same TX as mutation; slog-emit for MVP; future Kafka |
| Cross-tenant leak | Account = identity boundary; ListObjects filters per principal; OPA cross-tenant deny |
| DPoP replay | jti cache 2min server-side; htm/htu binding; iat freshness ≤60s |

---

## 12. User journeys (linked to `references/user-journeys.md`)

Все 30 journeys из skill reference (J1-J30) применимы. Этот эпик реализует **27** (исключения: J27 audit log export, J28 access review automation, J25 GDPR erasure — отложено в Phase 9).

Поверх skill reference, **специфичные для production-ready scope** дополнения:

### J31 — Cluster admin grant new cluster-admin via `kacho-cli admin grant-cluster-admin`

1. Caller logs in (must be cluster-admin already).
2. CLI `kacho admin cluster-admin add --subject usr_new --rationale "On-call rotation"`.
3. POST /v1/internal/cluster:grantAdmin (internal-mux only).
4. kacho-iam: permission check, INSERT cluster_admin_grants, INSERT fga_outbox.
5. Audit event "iam.cluster.admin.granted" → slog stdout.
6. Tuple drains to OpenFGA ≤ 2s.

### J32 — Workload Identity Federation new GitHub repo

1. Admin in target Project → "+ Trust Policy".
2. UI POST /v1/service_accounts/<sva-id>/federations:create.
3. Backend validates: issuer is whitelisted GitHub URL; subject_pattern not too permissive (no `*`).
4. INSERT federation_trust_policies.
5. Audit "iam.federation.policy.created".
6. GitHub Actions in target repo can now exchange OIDC → Kachō token (TTL ≤15min).

### J33 — Step-up for cluster-admin op

1. User has acr=2 (Passkey).
2. Tries to grant cluster-admin to others.
3. api-gateway interceptor: required_acr="3" for cluster.admin ops.
4. 401 → step-up flow.
5. User re-Passkey with user_verification → acr=3.
6. Retries; succeeds.

### J34 — JIT admin elevation

1. User Bob is in `access_bindings_jit_eligibility` for `roles/project.admin@prj_x`.
2. Bob clicks "Activate Admin" in UI → step-up to acr=3.
3. POST /v1/access_bindings:activateJIT {role_id, resource, duration_seconds=3600}.
4. kacho-iam:
   - INSERT access_bindings (status=ACTIVE, condition: jit_window(activated_at=now, ttl=3600)).
   - INSERT fga_outbox with Conditional tuple.
   - Audit "iam.jit.activated".
5. After 1h: condition fails → access effectively revoked.
6. Audit "iam.jit.expired" → slog.

### J35 — Break-glass with 2-person approve

1. SRE Alice: `kacho admin break-glass-request --incident INC-001 --duration 2h`.
2. CLI POST /v1/internal/cluster:requestBreakGlass.
3. kacho-iam:
   - INSERT cluster_break_glass_grants (status=AWAITING_APPROVAL, requested_by=usr_alice).
   - Emit Slack/PagerDuty alert to security@.
4. Approver Bob (existing cluster-admin) reviews; CLI `kacho admin break-glass-approve --request-id req_xyz`.
5. kacho-iam:
   - UPDATE break_glass_grants SET approved_by_a=usr_bob.
6. Approver Carol (SRE manager) reviews; CLI approve.
7. kacho-iam:
   - UPDATE approved_by_b=usr_carol, status=ACTIVE.
   - INSERT fga_outbox with conditional tuple cluster:singleton#emergency_admin@user:usr_alice (break_glass_window condition).
   - PagerDuty incident page + Slack + email security@.
   - Audit "iam.cluster.break_glass.granted".
8. After 2h: condition expires; access revoked.
9. Audit "iam.cluster.break_glass.expired".
10. Mandatory post-incident review within 7 days.

---

## 13. Migration plan — Phases breakdown

| Phase | Scope | Duration | Acceptance doc |
|---|---|---|---|
| **1 Foundation** | DB schema (Org + Cluster + Federation + Conditions + JIT + Audit/CAEP outboxes); bootstrap migration 0011; identity tables enrichment | 2 weeks | `sub-phase-3.1-iam-foundation-acceptance.md` |
| **2 AuthN core** | Kratos WebAuthn enabled; Hydra DPoP; api-gw token validation; step-up; recovery via Kratos | 2-3 weeks | `sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md` |
| **3 AuthZ core** | OpenFGA model v2 deploy; Conditions; OPA sidecar deploy; Check-interceptor reuse from KAC-108 | 2-3 weeks | `sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md` |
| **4 List filtering** | corelib/authz/listobjects.go; per-service List-handler rewrite (vpc/compute/lb); k6 SLA | 2 weeks | `sub-phase-3.4-iam-list-filtering-acceptance.md` |
| **5 Workload Identity** | SA-keys via Hydra (Class A); FederationExchangeService (Class B); GitHub/AWS/GCP integration docs | 2-3 weeks | `sub-phase-3.5-iam-workload-identity-federation-acceptance.md` |
| **6 Enterprise SSO** | SCIM 2.0 endpoint; SAML bridge (Jackson) deploy; Organization tier full integration | 3-4 weeks | `sub-phase-3.6-iam-scim-saml-organization-acceptance.md` |
| **7 JIT/PIM** | access_bindings_jit_eligibility; ActivateJIT RPC; break_glass with 2-person approve; alerting | 2 weeks | `sub-phase-3.7-iam-jit-breakglass-acceptance.md` |
| **8 CAEP push** | caep_outbox + drainer; SET signing; subscriber registry; webhook delivery retry/backoff; internal CAEP receiver in api-gateway | 2-3 weeks | `sub-phase-3.8-iam-caep-push-acceptance.md` |
| ~~Workload Identity (SPIFFE/SPIRE) + service mesh~~ | ~~SVID-based mTLS in-cluster~~ | OUT OF SCOPE — отдельный future эпик | — |
| ~~9 Audit infra~~ | ~~Kafka audit-topic, ClickHouse, S3+Glacier, HSM, SIEM, Merkle~~ | **OUT OF SCOPE** | — |

**Total effort estimate**: 18-23 weeks (~4.5-5.5 months) at single-engineer cadence; parallelizable to ~3-4 months with 2 engineers.

### 13.1 Per-phase PR-chain order (within each phase)

1. `kacho-proto` — new .proto + regen stubs.
2. `kacho-corelib` — new utility packages (authz extensions, hydra/kratos/spire/scim/saml clients).
3. `kacho-iam` — main service changes (migration + domain + repo + service + handler).
4. Peer services (vpc/compute/lb) where affected (Phase 4 only).
5. `kacho-api-gateway` — register new RPCs.
6. `kacho-deploy` — helm/values updates + new components.
7. `kacho-ui` — UI changes.
8. `kacho-workspace` — vault docs + acceptance docs final state.

### 13.2 Per-PR mandatory (запрет #11)

Integration tests (testcontainers Postgres) + newman cases (gen.py → Postman collection) **в том же PR**. Никаких "tests-followup" без явного KAC-tests тикета.

---

## 14. Definition of Done (epic-level)

- [ ] Acceptance doc per phase APPROVED by `acceptance-reviewer`.
- [ ] All 8 phases merged with integration tests + newman cases.
- [ ] OpenFGA v2 model deployed on e2c825; bootstrap-job idempotent.
- [ ] kacho_iam migration `0011_kac123_*.sql` applied; all new tables present.
- [ ] Smoke (e2c825):
   - signup → WebAuthn (Passkey on test device) → Account+Project+admin auto.
   - Invite (existing user) → instant ACTIVE binding.
   - Invite (new email) → PENDING + magic-link via Kratos.
   - List networks: empty grants → {}; 2-id grants → 2 networks.
   - SA-key Create via Hydra → JWT login validates.
   - Federation: simulated GitHub OIDC → exchange → Kachō JWT → API call success.
   - JIT activation: eligible user → step-up → admin for 1h → expires.
   - Break-glass: 2 approvers → grant 2h → PagerDuty fires → auto-revoke.
   - CAEP push: revoke binding → subscribed test-SP receives SET within 10s.
   - Cluster-admin: only callable on internal-mux port, blocked on public TLS.
- [ ] Reactivity revoke ≤ 10s (k6 load test + CAEP latency).
- [ ] Newman regression ≥ 60 cases.
- [ ] k6 load tests: Check p95 ≤ 20ms; ListObjects p95 ≤ 100ms; CAEP delivery p95 ≤ 2s.
- [ ] Vault: 15+ files updated (resources/iam-*, rpc/iam-*, edges/iam-*, packages/iam-*, KAC-127 trail).
- [ ] PR'ы merged в 10 репо в правильном порядке.
- [ ] YT KAC-123 в Done; all 8 subtasks Done; sprint cleanup.

---

## 15. Open questions (per-phase)

### Phase 1
- Q1.1: Org-tier — обязателен ли для всех customers, или вводим только под enterprise? **Recommend**: optional, accounts.organization_id NULL допустим (single-user / SMB).
- Q1.2: Cluster.id — hardcoded `cluster_kacho_root` или per-installation (multi-cluster topology)?

### Phase 2
- Q2.1: Password как fallback при отсутствии Passkey-supporting device — minimum length 14? Argon2id config: m=64MB, t=3, p=4?
- Q2.2: DPoP non-extractable key — что делать если браузер не поддерживает (Safari < 16, Firefox < 90)? Bearer fallback?

### Phase 3
- Q3.1: OPA bundle distribution — push (admin pre-configures) или pull (OPA pulls from kacho-iam-served endpoint)? **Recommend**: pull для consistency.
- Q3.2: Conditions support coverage — какие условия в MVP (mfa_fresh, non_expired, source_ip), какие отложить (business_hours, geo)?

### Phase 4
- Q4.1: ListObjects на 10000+ resources — нужна ли пагинация на FGA side? OpenFGA `ListObjects` имеет `MaxResults` parameter.

### Phase 5
- Q5.1: GitHub Actions OIDC token — какие IP ranges разрешать (140.82.0.0/16 + ...)? Use GitHub-published meta endpoint?
- Q5.2: AWS IRSA / GCP WIF setup — Phase 5 deliver скрипты для customer-side setup, или только docs?

### Phase 6
- Q6.1: SCIM bearer token rotation — manual per customer? Schedule reminder?
- Q6.2: SAML bridge — Jackson или WorkOS open-source? Jackson — preferred (self-host).

### Phase 7
- Q7.1: JIT eligible-list management — who can edit? Cluster-admin? Account-admin? Both?
- Q7.2: Break-glass approver pool — fixed list (env-configured) или derived (`access_bindings_breakglass_approvers` table)?

### Phase 8
- Q8.1: CAEP subscriber signing — sign our SET with kacho-iam private key (same as Hydra) или separate signer?
- Q8.2: ~~SPIFFE federation across regions~~ — N/A на MVP (SPIFFE/SPIRE out of scope).

---

## 16. References

- Workspace skill: `.claude/skills/iam-architect/SKILL.md`
- Identity model: `.claude/skills/iam-architect/references/identity-model.md`
- AuthN: `.claude/skills/iam-architect/references/oidc-oauth2.md`
- ReBAC: `.claude/skills/iam-architect/references/zanzibar-rebac.md`
- Workload Identity: `.claude/skills/iam-architect/references/workload-identity.md`
- Cloud patterns: `.claude/skills/iam-architect/references/cloud-iam-patterns.md`
- Security 2026: `.claude/skills/iam-architect/references/security-2026.md`
- User journeys (30): `.claude/skills/iam-architect/references/user-journeys.md`
- Audit/compliance (Phase 9 context): `.claude/skills/iam-architect/references/audit-compliance.md`
- Vision doc: `docs/superpowers/specs/2026-05-19-iam-revolutionary-architecture-design.md`
- Baseline KAC-108: `docs/specs/sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md`
- Baseline KAC-125: `docs/specs/sub-phase-2.0-iam-KAC-125-user-invite-flow-acceptance.md`

---

**End of design doc**. Acceptance docs per phase (Phase 1-8) пишутся `acceptance-author` агентом перед каждой фазой; coding-gate per CLAUDE.md запрет #1.
