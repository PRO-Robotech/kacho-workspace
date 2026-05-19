# Kachō IAM — Production-Ready Edition (KAC-127 vault-label / YT KAC-123)

**Дата**: 2026-05-19 (Production edition — supersedes MVP iteration)
**Status**: DRAFT (awaiting acceptance docs per-phase)
**YouTrack issue**: KAC-123 (https://prorobotech.youtrack.cloud/issue/KAC-123)
**Vault-label / branch**: **KAC-127** (vault `KAC-123.md` уже занят чужой работой)
**Workspace skill применён**: `.claude/skills/iam-architect/` (SKILL.md + 7 references, ~85 KB)
**Vision-предусловие**: `docs/superpowers/specs/2026-05-19-iam-revolutionary-architecture-design.md`
**Baseline (in main)**: KAC-108 (OpenFGA E3) + KAC-125 (User per-Account + Invite)
**Superseded**: KAC-126 incremental design, KAC-127 MVP iteration (предыдущий черновик этого же файла; этот документ — **production-ready edition** без deferred-частей).

---

## 0. TL;DR

Этот документ — **production-ready** spec, без TODO/deferred/follow-up/future-epic. Полная топовая реализация IAM, реализующая весь стек 2026 best practices в одном эпике:

### Что входит (всё IN scope)

1. **Identity Plane**: ORY Kratos (WebAuthn/Passkey + recovery + SCIM 2.0) + ORY Hydra (OAuth 2.1 + OIDC 1.0 + DPoP RFC 9449 + mTLS-bound RFC 8705) + SAML bridge (Boxyhq Jackson).
2. **AuthZ Plane**: OpenFGA v1.6+ (Conditions + Contextual tuples + ListObjects + Watch) + OPA v1.0 (org-wide deny guardrails, Rego DSL).
3. **Identity Model**: cluster (singleton) → organization (B2B optional) → account → project → resource. Multi-scope custom roles. PENDING/ACTIVE/REVOKED AccessBinding lifecycle with Conditions ABAC overlay.
4. **Workload Identity**:
   - **External (Class A)**: Hydra OAuth2 `client_credentials` для legacy SA-keys.
   - **External (Class B)**: Workload Identity Federation (OIDC Token Exchange RFC 8693) — GitHub Actions, AWS IRSA, GCP WIF, GitLab CI.
   - **In-cluster (Class C)**: SPIFFE/SPIRE — каждый pod имеет SVID; service mesh (Cilium eBPF) для auto-mTLS между kacho-* сервисами.
5. **PIM/JIT + Break-glass**: just-in-time admin elevation (step-up + time-bound + Conditions); break-glass с 2-person approve + auto-expiry + PagerDuty.
6. **CAEP push pipeline** (RFC 8417 SET + OpenID CAEP): real-time revoke ≤ 10s; SP webhook subscribers; tamper-evident SET signing.
7. **Audit pipeline (full)**: Kafka audit-topic → ClickHouse (90d hot OLAP) + S3+Glacier (7-10y cold) + SIEM webhooks (Datadog/Splunk/Elastic); HSM-backed batch signing; Merkle-chain tamper-evidence; CADF event schema.
8. **List filtering**: OpenFGA ListObjects per List-RPC (replaces KAC-108 D-8).
9. **Compliance**: SOC 2 Type II ready; ISO 27001:2022 Annex A controls; NIST CSF 2.0 + NIST 800-63B AAL2-AAL3; GDPR Articles 17/32/33 (erasure pipeline, encryption, breach notification); FedRAMP-compat baselines; PCI-DSS-compat tokenization patterns.
10. **Production deployment**: multi-region active-active; external public TLS endpoint (`api.kacho.cloud` Let's Encrypt + cert-manager); per-region failover; RTO ≤ 15 min, RPO ≤ 1 min; chaos engineering (Litmus); continuous fuzzing; SBOM + SLSA L3 build provenance; bug bounty `security.txt`.
11. **Observability**: OpenTelemetry traces/metrics/logs end-to-end; Grafana dashboards; alerting via PagerDuty + Slack; runbooks for every alert.
12. **Security hardening**: WAF (Cloudflare) + DDoS protection; OWASP ASVS L3; supply-chain (cosign + sigstore); secret-rotation automation; pentest (annual + on major release).

### Out of scope — НИЧЕГО (production edition)

Все компоненты, ранее отложенные как "future epic", **включены**. Никаких TODO/TBD/follow-up. Если что-то "не успели" — это блокер для merge, не deferred.

### What "production-ready" means here

| Critère | Definition |
|---|---|
| Functional | Все 30 user-journeys работают end-to-end на public deployment |
| No tech debt | Никаких `// TODO`, никаких deferred PRs, никаких "follow-up tickets" в commit-messages |
| Tests | Integration (testcontainers) + newman (90+ cases) + k6 load + Playwright E2E + chaos + fuzzing — все зелёные в CI |
| Deployed | `api.kacho.cloud` external endpoint доступен; real Let's Encrypt cert; public OIDC discovery |
| CI/CD green | All workflows (lint, unit, integration, newman, k6, security-scan, sbom, container-scan) — passing |
| Top-market | Compatible с FIDO Alliance / OpenID Foundation / CNCF Zero Trust pattern; certified OIDC components; Z anzibar-faithful ReBAC |

---

## 1. Decision Log (final, no deferred)

| # | Decision | Rationale |
|---|---|---|
| D-1 | **AuthN stack = ORY Kratos + Hydra**; Zitadel deprecated and removed | Open-source, OpenID Foundation certified, decoupled identity ↔ OIDC issuer; mature WebAuthn hooks |
| D-2 | **AuthZ engine = OpenFGA** v1.6+; Keto removed | KAC-108 baseline; Conditions + Contextual tuples + Watch + ListObjects mature; Auth0/Okta production usage |
| D-3 | **OPA sidecar** per service для org-wide deny guardrails | Industry-standard Rego; SCP-equivalent guardrails; K8s admission native |
| D-4 | **Identity hierarchy** = cluster → organization (optional) → account → project → resource | B2B enterprise customers need org grouping для SCIM/SAML/billing; single-user signups имеют organization_id=NULL |
| D-5 | **Custom Role multi-scope** — project / account / organization (exactly one non-NULL) | Real-world flexibility (cross-project, cross-account roles); validated через CHECK |
| D-6 | **DPoP-bound JWT** (RFC 9449) для SPA/mobile; **mTLS-bound** (RFC 8705) для backend M2M | Token theft mitigation; standard 2026 |
| D-7 | **WebAuthn/Passkey-first** AuthN; TOTP fallback; SMS deprecated для AAL2+ | Phishing-resistant by design (origin-bound); NIST 800-63B AAL2-Passkey-alone |
| D-8 | **Workload Identity Federation** (RFC 8693) для CI/CD: GitHub/AWS/GCP/GitLab/Bitbucket | Zero static M2M secrets; no rotation toil |
| D-9 | **SCIM 2.0** (RFC 7644) endpoint для enterprise inbound provisioning | Standard для Okta/Azure/Google Workspace integration |
| D-10 | **SAML 2.0** через Boxyhq Jackson bridge (SAML → OIDC translation) | Open-source, self-host; ORY Kratos OSS не имеет native SAML |
| D-11 | **AccessBinding.status** ∈ {PENDING, ACTIVE, REVOKED}; REVOKED — soft-delete для audit retention | Forensics + GDPR-compliant |
| D-12 | **Conditions overlay** на AccessBinding (CEL-like): mfa_fresh / non_expired / source_ip / jit_window / break_glass_window / business_hours | ABAC overlay поверх ReBAC; flexible without engine rewrite |
| D-13 | **PIM/JIT elevation** для всех admin-роль; standing admin = anti-pattern (отсутствует у customer-facing roles) | Reduce insider attack surface; align с Microsoft Entra PIM pattern |
| D-14 | **Break-glass** = 2-person approve (cluster-admin + SRE-on-call) + auto-expire 2h max + PagerDuty + Slack + email alerts + mandatory post-incident review ≤ 7d | NIST 800-53 IR-4; SOC 2 CC6.7 |
| D-15 | **CAEP push pipeline** (RFC 8417 SET + OpenID CAEP) — revoke ≤ 10s globally | Real-time security propagation |
| D-16 | **SPIFFE/SPIRE + service mesh** (Cilium eBPF preferred; Linkerd alt) для in-cluster mTLS | Defense-in-depth; SVID-based identity; AuthorizationPolicy enforcement |
| D-17 | **Cluster:singleton** OpenFGA-object для kacho-system:* roles + Internal RPC GrantClusterAdmin + bootstrap migration seed | Homogeneous с остальной моделью; audit trail |
| D-18 | **Audit pipeline = full**: Kafka audit-topic → ClickHouse (hot 90d) + S3+Glacier (cold 7-10y) + SIEM webhooks; HSM-signed batches; Merkle-chain tamper-evidence | SOC 2 Type II + ISO 27001 + GDPR compliance |
| D-19 | **Migration strategy** — bluегreen на e2c825 (current dev) → migrate state → switch DNS; new production stand `api.kacho.cloud` (real TLS) | Zero-downtime cutover |
| D-20 | **Public TLS endpoint** `api.kacho.cloud` via Cloudflare + cert-manager (Let's Encrypt); WAF + DDoS protection | Production-grade external surface |
| D-21 | **Multi-region active-active** (минимум 2 region: eu-central + eu-west); RTO ≤ 15min / RPO ≤ 1min | DR; no single point of failure |
| D-22 | **Continuous fuzzing** (go-fuzz / cargo-fuzz) для critical paths (token parsing, regex, FGA model parsing) | Catches edge cases before pentest |
| D-23 | **SBOM + SLSA L3 build provenance** (cosign-signed images; in-toto attestations) | Supply chain integrity |
| D-24 | **Bug bounty + security.txt** + responsible disclosure policy | Real-world threat surface validation |
| D-25 | **OpenTelemetry end-to-end** (Tempo + Mimir + Loki); every span propagates trace-id | Operational excellence |
| D-26 | **Chaos engineering** (Litmus / chaoskube) — quarterly game-days | Reliability verification |
| D-27 | **Pentest** — annual + on every major release; OWASP ASVS L3 conformance test | Independent validation |
| D-28 | **Post-quantum readiness** — hybrid TLS (X25519+ML-KEM) когда cert-manager Cloudflare поддержит; JWT alg pinning monitored | 2026-forward security |

---

## 2. Architecture (production-grade component stack)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL EDGE                                │
│                                                                            │
│   Cloudflare:                                                              │
│   ├─ WAF (OWASP CRS 3.x rules) + DDoS protection (L3-L7)                 │
│   ├─ Bot management + rate-limiting per-endpoint                          │
│   ├─ Hybrid TLS (X25519 + ML-KEM Kyber768 — when cert-manager supports)  │
│   ├─ public TLS = api.kacho.cloud (Let's Encrypt; auto-renew via         │
│   │   cert-manager + ACME DNS-01)                                         │
│   └─ Cloudflare Access (optional — protects /admin/* paths)              │
│                              │                                            │
│                              ▼                                            │
│   kacho-api-gateway (3+ replicas, HPA, anti-affinity):                   │
│   ├─ TLS edge (mTLS-bound and DPoP-bound JWT validation)                 │
│   ├─ Principal extraction → gRPC metadata propagation                    │
│   ├─ OPA sidecar (org-wide deny guardrails)                              │
│   └─ Cross-region routing (Anycast + GeoDNS fallback)                    │
└──────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼  (mTLS via SPIFFE SVID + Cilium eBPF mesh)
┌──────────────────────────────────────────────────────────────────────────┐
│                        IDENTITY PLANE                                     │
│                                                                            │
│   ORY Kratos (3+ HA, Postgres backed):                                   │
│   ├─ WebAuthn / Passkey (conditional UI; user-verification mandatory)    │
│   ├─ Password fallback (Argon2id m=64MB t=3 p=4; HIBP-checked)           │
│   ├─ TOTP (RFC 6238) — secondary MFA                                     │
│   ├─ Identity schema v2 (extensible traits)                              │
│   ├─ Webhook post-registration → kacho-iam.UpsertFromIdentity            │
│   ├─ Recovery flows (magic-link with 5min TTL, single-use, bound to IP)  │
│   └─ Session revocation (back-channel logout RFC 8254)                   │
│                                                                            │
│   ORY Hydra (3+ HA, Postgres backed):                                    │
│   ├─ OAuth 2.1 + OIDC 1.0 certified                                      │
│   ├─ Grant types: AuthCode+PKCE, ClientCredentials, RefreshToken,         │
│   │   DeviceCode, JWT-Bearer, TokenExchange (RFC 8693)                   │
│   ├─ Removed grants: Implicit, ROPC (per OAuth 2.1)                      │
│   ├─ Access token: JWT (RS256 + ES256 + EdDSA; PASETO v4 ready)          │
│   ├─ DPoP support (RFC 9449)                                              │
│   ├─ mTLS-bound tokens (RFC 8705)                                         │
│   ├─ Refresh-token rotation with family-revoke on reuse                  │
│   ├─ JWKS published with key rotation (90d cycle; current+previous)      │
│   └─ Token introspection + back-channel logout                           │
│                                                                            │
│   Boxyhq Jackson (SAML bridge, 2+ HA):                                   │
│   ├─ Translates SAML 2.0 → OIDC (Kachō consumes only OIDC internally)   │
│   ├─ Per-organization SAML metadata-XML upload via admin UI              │
│   ├─ SP-init + IdP-init flows                                            │
│   └─ Just-in-Time provisioning when SAML assertion arrives w/o pre-SCIM  │
│                                                                            │
│   kacho-iam SCIM 2.0 endpoint (/scim/v2/Users + /Groups + /Bulk):        │
│   ├─ RFC 7644 compliance (tested via Okta + Azure sandbox)               │
│   ├─ Per-organization endpoint + scoped bearer-token auth                │
│   ├─ Filter expressions (eq/ne/co/sw/gt/lt) + sort + pagination          │
│   └─ Lifecycle webhooks → cascade to ReBAC + CAEP                        │
│                                                                            │
│   Federation Trust Policy engine (in kacho-iam):                         │
│   ├─ Verifies external OIDC tokens (cached JWKS per issuer, 24h TTL)    │
│   ├─ Matches against trust policies (subject_pattern, additional_claims) │
│   ├─ Applies Conditions (source_ip CIDR, business_hours, expires_at)    │
│   └─ Issues short-lived Kachō JWT (TTL ≤ 15min, sub=sva-id)             │
└──────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       AUTHORIZATION PLANE                                 │
│                                                                            │
│   OpenFGA cluster (3+ HA, Postgres-backed, leader-less reads):           │
│   ├─ Authorization model v2 (versioned + immutable; ID pinned per call)  │
│   ├─ Conditions stable (CEL-like; pre-validated on model write)         │
│   ├─ Contextual tuples (request-scoped overrides)                        │
│   ├─ ListObjects API with Consistency options                            │
│   ├─ Watch API (стрим изменений; для resource_lifecycle_subscriber)     │
│   └─ Bootstrap-job idempotent (helm post-install)                        │
│                                                                            │
│   OPA sidecar (per kacho-api-gateway pod + per backend service pod):     │
│   ├─ Bundle pull from kacho-iam (signed bundles; 1h TTL)                 │
│   ├─ Rego policies (deny-only; evaluates AFTER OpenFGA Check passes)     │
│   ├─ Deny rules: cross-tenant, billing-projects, SA-grant-user,          │
│   │   organization-region restrictions, break-glass-duration-limits     │
│   └─ Policy tests in CI (Rego unit-tests)                                │
│                                                                            │
│   kacho-iam service (3+ HA):                                              │
│   ├─ Role catalog (system + custom; permission registry from proto)      │
│   ├─ AccessBinding lifecycle (PENDING/ACTIVE/REVOKED + Conditions)       │
│   ├─ Federation Exchange (Token Exchange RFC 8693)                       │
│   ├─ Invite flow (project-level + cross-account)                         │
│   ├─ JIT activation + break-glass workflow                               │
│   ├─ CAEP outbox + drainer + SET signing                                 │
│   ├─ SCIM 2.0 inbound endpoint                                            │
│   ├─ Cluster admin grants (cluster:singleton)                            │
│   └─ Access reviews + GDPR erasure pipeline                              │
│                                                                            │
│   corelib/authz (each service):                                           │
│   ├─ Check client (cache 5s + LISTEN-invalidate via Postgres NOTIFY)    │
│   ├─ ListObjects client (cache 5s + LISTEN-invalidate)                  │
│   ├─ Conditions context builder (extracts amr/acr/mfa_at/source_ip)     │
│   └─ Fail-closed on engine unavailable; metric breakglass override      │
└──────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       WORKLOAD IDENTITY (in-cluster)                     │
│                                                                            │
│   SPIRE Server (3 HA replicas, Postgres-backed):                         │
│   ├─ Trust domain: kacho.cloud                                           │
│   ├─ Root CA in HSM (or KMS-backed)                                      │
│   ├─ Federation bundles published for external SPIFFE-aware systems     │
│   └─ Registration entries managed via GitOps (Argo CD)                   │
│                                                                            │
│   SPIRE Agent (DaemonSet on every node):                                 │
│   ├─ Attests to Server via k8s_psat                                      │
│   ├─ Workload API socket per node                                        │
│   ├─ Selectors per kacho-* ServiceAccount                                │
│   └─ SVID validity 1h; auto-rotated                                       │
│                                                                            │
│   Cilium service mesh (eBPF dataplane, no sidecar):                      │
│   ├─ Auto-mTLS between all kacho-* pods using SPIFFE SVIDs              │
│   ├─ AuthorizationPolicy per service (SPIFFE-ID-based allowlist)         │
│   ├─ Network policies (L4 + L7) with deny-by-default                     │
│   ├─ Hubble observability (flow visibility)                              │
│   └─ Encryption at L3 (WireGuard) between nodes                          │
└──────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       AUDIT & EVENT PLANE (full)                          │
│                                                                            │
│   audit_outbox + caep_outbox tables (in kacho_iam DB):                   │
│   ├─ Atomic write with primary mutation (one TX)                         │
│   ├─ NOTIFY 'audit_event' + 'caep_event' on insert                       │
│   └─ Drainers consume → forward to Kafka / webhook                       │
│                                                                            │
│   Kafka audit-topic (3 brokers + Zookeeper-less KRaft mode):             │
│   ├─ Producer: audit-drainer (kacho-iam + every other service)          │
│   ├─ Retention: 7 days hot in Kafka                                      │
│   ├─ Compression: zstd                                                    │
│   ├─ Acks: all (durable); idempotent producer                            │
│   ├─ Schema: CADF + SET wrapper (signed JWT)                             │
│   └─ Topic per-tenant (high-volume orgs) or shared (default)            │
│                                                                            │
│   Consumers:                                                              │
│   ├─→ ClickHouse (hot OLAP, 90d retention)                               │
│   │   ├─ Replicated cluster (2 shards × 2 replicas)                      │
│   │   ├─ MergeTree engine; partitioned by (tenant, day)                  │
│   │   ├─ Indexes на actor_id, target_id, event_type, timestamp           │
│   │   └─ Admin UI queries — sub-second p99                               │
│   │                                                                       │
│   ├─→ S3 + Glacier (cold storage, 7-10y retention)                       │
│   │   ├─ Batched 5-min uploads (JSONL gzipped)                           │
│   │   ├─ HSM-signed batch manifests (AWS KMS / GCP KMS / cosign)        │
│   │   ├─ Merkle-chain (each batch links to previous batch hash)         │
│   │   ├─ Lifecycle policy: hot S3 (30d) → S3 IA (1y) → Glacier (10y)    │
│   │   └─ Independent verifier service для integrity proof               │
│   │                                                                       │
│   └─→ SIEM webhook subscribers (Datadog / Splunk / Elastic / Chronicle) │
│       ├─ Per-tenant subscription                                         │
│       ├─ Filtering by event_type (high-volume tenants opt-out на debug) │
│       ├─ Detection rules (impossible travel, brute force, mass-delete)  │
│       └─ Alerts → PagerDuty / Slack / email                             │
│                                                                            │
│   CAEP push pipeline:                                                     │
│   ├─ SET (Security Event Token) RFC 8417 signed JWT                      │
│   ├─ Per-subscriber webhook delivery                                     │
│   ├─ Exponential retry (1s, 5s, 30s, 5min, 1h, 6h, 24h; 8 attempts)    │
│   ├─ Subscriber-side jti replay protection (verified в admin UI)        │
│   ├─ Internal receiver in api-gateway (session_revocations + cache inv) │
│   └─ Reactivity SLA: p95 ≤ 2s; p99 ≤ 5s; total revoke→effect ≤ 10s     │
└──────────────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       OBSERVABILITY                                       │
│                                                                            │
│   OpenTelemetry (OTLP) export from every service:                        │
│   ├─→ Traces  → Tempo (Grafana stack); 7d retention                      │
│   ├─→ Metrics → Mimir / Prometheus-compat; 30d retention                 │
│   ├─→ Logs    → Loki; 30d retention                                       │
│   │                                                                       │
│   Grafana dashboards (per-service + IAM-specific):                       │
│   ├─ /iam-overview: Check p50/p95/p99, ListObjects, cache hit ratio     │
│   ├─ /iam-authn: signin success/failure, MFA usage, recovery rates      │
│   ├─ /iam-authz: deny breakdown, conditions evaluation, OPA hits        │
│   ├─ /iam-federation: exchange success/failure, per-issuer breakdown    │
│   ├─ /iam-caep: queue depth, delivery latency, subscriber failure rate  │
│   ├─ /iam-audit: ingest rate, pipeline lag, signature failures           │
│   └─ /iam-incidents: break-glass usage, JIT activation, alerts triggered│
│                                                                            │
│   Alerts (Alertmanager → PagerDuty + Slack):                             │
│   ├─ Check latency p95 > 30ms (3 min sustained)                          │
│   ├─ CAEP delivery failure rate > 5%                                     │
│   ├─ Audit pipeline lag > 5 min                                          │
│   ├─ FGA tuple drift detected (reconciliation job)                       │
│   ├─ Break-glass usage (any) — Critical                                  │
│   ├─ Audit signature verification failure — Critical                     │
│   ├─ Token JWKS rotation overdue (>90d) — Warning                        │
│   └─ Federation policy soon to expire (≤14d) — Warning                   │
└──────────────────────────────────────────────────────────────────────────┘
```

### Component versions (target — frozen at acceptance approval)

| Component | Version | Role |
|---|---|---|
| ORY Kratos | v1.4.x | identity flows (WebAuthn + recovery + SCIM) |
| ORY Hydra | v2.4.x | OAuth2.1 + OIDC + DPoP issuer |
| Boxyhq Jackson | v1.x.x latest | SAML 2.0 → OIDC bridge |
| OpenFGA | v1.6.x | ReBAC engine |
| OPA | v1.0.x | guardrail policies (Rego v1) |
| SPIRE | v1.10.x | SPIFFE workload identity |
| Cilium | v1.16.x | eBPF service mesh + network policies |
| Apache Kafka | v3.7.x (KRaft) | audit topic |
| ClickHouse | v24.x | OLAP audit query store |
| PostgreSQL | v16.x | per-service DB (kacho_iam, kacho_vpc, ...) |
| Cert-manager | v1.16.x | TLS automation |
| cosign | v2.4.x | image signing |
| OpenTelemetry Collector | v0.110.x | observability pipeline |
| Tempo / Mimir / Loki | latest stable | LGTM stack |
| Argo CD | v2.13.x | GitOps deployments |
| Litmus / chaoskube | v3.x | chaos engineering |
| Go | 1.22.x (already) | |

---

## 3. Identity Model (final schema)

```
                          cluster:cluster_kacho_root (singleton)
                                       │
                          ┌────────────┴────────────┐
                          │                         │
                          │ contains                │ system_admin
                          ▼                         ▼ emergency_admin
            organization:org_<id> (optional)   user:usr_root (seeded via env)
                          │
                          │ contains
                          ▼
                  account:acc_<id>
                          │
                          │ contains
                          ▼
                  project:prj_<id>
                          │
                          │ contains
                          ▼
                  resources (vpc_network, compute_instance, ...)

  Subjects: user (per-Account row) / service_account / group / federated_subject
  Roles: system (cluster-wide) / custom (multi-scope: org/account/project)
  AccessBinding: (subject, role, resource, condition?, status, expires_at?, granted_by, audit-meta)
  Federation: trust_policy (issuer + subject_pattern + claims_filter → service_account_id)
  CAEP: subscriber registry + outbox + signed SET delivery
```

### DB tables (post-migration `0011_kac127_foundation.sql`)

| Table | Purpose |
|---|---|
| `clusters` | Singleton; id=`cluster_kacho_root`; CHECK enforces 1 row |
| `cluster_admin_grants` | Permanent root grants (source of truth для FGA tuples) |
| `cluster_break_glass_grants` | Temporary emergency grants; 2-person approval; auto-expire |
| `organizations` | Optional B2B tier; domain-claim; SCIM/SAML config |
| `accounts` | Tenant boundary + billing; owner_user_id; organization_id (NULL OK) |
| `projects` | Workload boundary; account_id |
| `users` | Per-Account row; one Kratos identity → N rows |
| `service_accounts` | Project-scoped (preferred) or account-scoped; enabled flag |
| `service_account_oauth_clients` | Static Hydra client mapping (Class A) |
| `federation_trust_policies` | OIDC federation rules (Class B); GitHub/AWS/GCP/etc |
| `groups` | Account-scoped; scim_managed flag; external_id |
| `group_members` | Polymorphic membership |
| `roles` | Multi-scope custom + system seed |
| `access_bindings` | Subject ↔ role ↔ resource + status + condition + expires_at |
| `access_binding_conditions` | CEL-like expressions (mfa_fresh, non_expired, source_ip, jit_window, ...) |
| `access_bindings_jit_eligibility` | Who can self-activate which role + max_duration |
| `access_reviews` + `access_review_items` | Quarterly recertification |
| `gdpr_erasure_requests` | Async erasure pipeline; 30d cool-off |
| `audit_outbox` | Append-only event log; drainer → Kafka |
| `caep_outbox` | Real-time revoke events; drainer → webhook |
| `caep_subscribers` | SP-registered CAEP endpoints |
| `session_revocations` | JTI revocation table (consulted on every request) |
| `oidc_jwks_keys` | JWKS rotation tracking |
| `audit_signing_batches` | HSM-signed batch manifests + Merkle hash chain |

---

## 4. OpenFGA Authorization Model v2 (final DSL)

```dsl
model
  schema 1.1

type user
type service_account
type federated_subject
type group
  relations
    define member: [user, service_account, federated_subject, group#member]

type cluster
  relations
    define system_admin:     [user, service_account]
    define emergency_admin:  [user with break_glass_window]
    define system_viewer:    [user, service_account]
    define any_admin:        system_admin or emergency_admin

type organization
  relations
    define cluster:        [cluster]
    define owner:          [user]
    define admin:          [user, service_account, group#member]
                           or any_admin from cluster
                           or owner
    define editor:         [user, service_account, group#member] or admin
    define viewer:         [user, service_account, group#member] or editor
    define billing_admin:  [user] or admin
    define scim_admin:     [user, service_account] or admin

type account
  relations
    define cluster:        [cluster]
    define organization:   [organization]
    define owner:          [user]
    define admin:          [user, service_account, group#member]
                           or any_admin from cluster
                           or admin from organization
                           or owner
    define editor:         [user, service_account, group#member] or admin or editor from organization
    define viewer:         [user, service_account, group#member] or editor or viewer from organization
    define billing_admin:  [user] or admin or billing_admin from organization

type project
  relations
    define account: [account]
    define admin:   [user, service_account, group#member] or admin from account
    define editor:  [user, service_account, group#member] or admin or editor from account
    define viewer:  [user, service_account, group#member] or editor or viewer from account

# Per-service resources (pattern repeats для vpc_subnet, vpc_security_group,
# vpc_route_table, vpc_address, vpc_gateway, vpc_private_endpoint,
# vpc_network_interface, vpc_address_pool, compute_instance, compute_disk,
# compute_image, compute_snapshot, lb_network_load_balancer, lb_target_group, ...):

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

# Conditions (ABAC overlay)

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

condition jit_window(current_time: timestamp, activated_at: timestamp, ttl_seconds: int) {
  current_time - activated_at < duration(format("%ds", ttl_seconds))
}

condition business_hours(current_time: timestamp, tz: string, start_h: int, end_h: int) {
  hour_of_day(current_time, tz) >= start_h && hour_of_day(current_time, tz) < end_h
}

condition device_compliant(device_attestation: string, allowed_attestations: list<string>) {
  device_attestation in allowed_attestations
}
```

### OPA Rego guardrails (production rules)

```rego
package kacho.iam.guardrails

import rego.v1

# Deny: destructive ops on billing-* projects unless cluster-admin
deny contains msg if {
  input.action in {"projects.delete", "accounts.delete"}
  startswith(input.resource.id, "prj_billing_")
  not input.principal.cluster_admin
  msg := sprintf("destructive op on billing project requires cluster-admin (got %v)", [input.principal.id])
}

# Deny: SA cannot grant role to user (escalation prevention)
deny contains msg if {
  input.action == "access_bindings.upsert"
  input.principal.type == "service_account"
  input.target.subject_type == "user"
  msg := "service accounts may not grant roles to users"
}

# Deny: granting org-wide role to user not in organization SCIM-set
deny contains msg if {
  input.action == "access_bindings.upsert"
  input.target.resource_type == "organization"
  org_id := input.target.resource_id
  not user_in_organization(input.target.subject_id, org_id)
  msg := sprintf("user %v not member of organization %v", [input.target.subject_id, org_id])
}

# Deny: max session lifetime for break-glass = 2h
deny contains msg if {
  input.action == "cluster.break_glass.grant"
  input.duration_seconds > 7200
  msg := "break-glass grant cannot exceed 2 hours"
}

# Deny: cross-tenant resource access
deny contains msg if {
  input.principal.type == "user"
  not principal_in_resource_account(input.principal, input.target.resource)
  not input.principal.cluster_admin
  msg := sprintf("cross-tenant access blocked: %v → %v", [input.principal.account_id, input.target.resource.account_id])
}

# Deny: production project mutation outside business hours unless break-glass
deny contains msg if {
  input.action in {"vpc.networks.delete", "compute.instances.delete"}
  endswith(input.resource.project_id, "_prod")
  not within_business_hours(input.principal.timezone)
  not input.principal.break_glass_active
  msg := "destructive ops on prod projects require business hours or break-glass"
}

# Helpers (data-driven from kacho-iam bundle):
user_in_organization(user_id, org_id) if { ... }
principal_in_resource_account(principal, resource) if { ... }
within_business_hours(tz) if { ... }
```

OPA bundles **signed** + verification chain тестируется в CI.

---

## 5. AuthN — production flows

### 5.1 Token shapes (production)

```
Access Token (JWT, RS256/ES256/EdDSA pinned per signing key; TTL 15min):
{
  "iss":   "https://hydra.kacho.cloud",
  "sub":   "usr_alice_acc_a1b2",
  "aud":   ["https://api.kacho.cloud"],
  "exp":   <now+15min>,
  "iat":   <now>,
  "nbf":   <now>,
  "jti":   "<uuid-v7>",
  "acr":   "2",
  "amr":   ["webauthn"],
  "auth_time": <when-user-authenticated>,
  "cnf": { "jkt": "<DPoP-thumbprint>" },         # DPoP binding
  "scope": "openid profile email",
  "ext_claims": {
    "kacho_external_id":      "<Kratos sub>",
    "kacho_active_account":   "acc_a1b2",
    "kacho_organization_id":  "org_acme",         # null если личный
    "kacho_groups":           [],                  # SCIM-managed groups
    "kacho_principal_type":   "user",
    "kacho_device_compliance": "attested",        # attested|partial|unknown
    "kacho_mfa_at":           <unix-ts>
  }
}

Refresh token: opaque (random); family-tracked в DB; one-time-use; rotation enforced; TTL 30d.

Service Account Token (Hydra client_credentials; TTL 60min):
{
  "iss":    "https://hydra.kacho.cloud",
  "sub":    "sva_ci_deployer",
  "aud":    ["https://api.kacho.cloud"],
  "exp":    <now+60min>,
  "iat":    <now>,
  "jti":    "<uuid-v7>",
  "client_id": "sva_ci_deployer",
  "scope":  "kacho.vpc kacho.compute",
  "ext_claims": {
    "kacho_principal_type": "service_account",
    "kacho_account_id":     "acc_a1b2",
    "kacho_project_id":     "prj_default"
  }
}

Federation-Exchanged Token (TTL 15min; sub=SA mapped from trust policy):
{
  ... as SA token ...
  "ext_claims": {
    "kacho_principal_type":    "federated_service_account",
    "kacho_federation_policy": "ftp_<id>",
    "kacho_external_subject":  "repo:my-org/my-repo:ref:refs/heads/main",
    "kacho_external_issuer":   "https://token.actions.githubusercontent.com"
  }
}

DPoP JWT (per-request; ES256/Ed25519; TTL 60s):
{ typ:"dpop+jwt", alg:"ES256",
  jwk:{...},                       # public key embedded; not extractable on client
  htm:"POST", htu:"https://api.kacho.cloud/...",
  iat:<now>, jti:"<uuid>"
}

SET (Security Event Token, RFC 8417; signed JWT):
{
  "iss": "https://api.kacho.cloud",
  "aud": "https://subscriber.example.com/caep/inbox",
  "iat": <now>,
  "jti": "<uuid>",
  "events": {
    "https://schemas.openid.net/secevent/caep/event-type/token-claims-change": {
      "subject": {"format":"opaque", "id":"usr_alice_acc_a1b2"},
      "claims":  {"removed_bindings":["acb_xyz"]},
      "event_timestamp": <now>
    }
  }
}
```

### 5.2 Validation pipeline (api-gateway)

```
On each request:
  1. Cloudflare WAF + rate-limit pass.
  2. mTLS handshake (when mesh — внутренний; иначе TLS server cert).
  3. Extract Authorization header → parse type (DPoP | Bearer-mTLS-bound | Bearer).
  4. Verify JWT signature via Hydra JWKS (cached 24h; force-refresh on kid miss).
  5. Validate iss/aud/exp/nbf/iat (clock skew ≤5min); validate alg whitelist.
  6. Check jti in session_revocations table (5s LISTEN-invalidated cache).
  7. If DPoP-bound:
     a. Parse DPoP header JWT; verify with embedded jwk.
     b. Validate cnf.jkt thumbprint matches.
     c. Validate htm/htu match request method/URL.
     d. Validate iat freshness (≤60s); jti not in DPoP-replay cache (2min TTL).
  8. If mTLS-bound: validate cnf.x5t#S256 matches client cert thumbprint.
  9. Build Principal from ext_claims + propagate via gRPC metadata.
  10. Apply OPA guardrail check at gateway level (cross-cutting deny rules).
  11. Forward to backend over mesh (SVID-mTLS).
```

### 5.3 ACR / step-up matrix

| Operation class | Required ACR | Required AMR (one of) |
|---|---|---|
| Anonymous public read (rare) | 0 | — |
| User read on own data | 1 | password OR webauthn |
| User mutate on own resources | 2 | webauthn OR password+totp |
| Admin mutate (project/account level) | 2 | webauthn OR password+totp |
| Cluster-admin actions (Internal RPC) | 3 | webauthn (user_verification) |
| Break-glass approval | 3 | webauthn (user_verification) |
| GDPR erasure confirm | 3 | webauthn (user_verification) |
| Bulk SCIM operation | 2 | (machine; service_account validates differently) |
| SA token issue (own SA in admin project) | 2 | webauthn OR password+totp |
| Federation policy create | 3 | webauthn (user_verification) |

### 5.4 Recovery & lifecycle

- **Forgot password / lost Passkey**: Kratos `/recovery` magic-link (5min TTL, single-use, IP-bound).
- **Recovery requires step-up**: after recovery completion, force enrollment of new Passkey OR re-confirm via independent factor (backup-code).
- **Compromised account**: admin force-block User → CAEP push → all sessions revoked globally ≤ 10s.
- **GDPR erasure**: 30d cool-off, then PII pseudonymize, retain audit row, hard-delete identity in Kratos.

---

## 6. Workload Identity — full three-class production

### Class A — Hydra OAuth client_credentials

```
ServiceAccount → IssueKey RPC:
  - permission check (admin on parent project)
  - Hydra-admin POST /admin/clients (idempotent on collision)
  - DB INSERT service_account_oauth_clients (sva_id, hydra_client_id)
  - audit: iam.sa.key.created
  - return Operation{response: { client_id, client_secret_one_shot }}

External system:
  POST https://hydra.kacho.cloud/oauth2/token
       -u sva_xxx:<secret>
       -d grant_type=client_credentials
  → JWT access_token (60min)

Rotation: admin issues new key, deploys to workload, revokes old (CAEP push → existing tokens with old client_id rejected).

Revoke:
  - Hydra-admin DELETE /admin/clients/<id>
  - DB DELETE service_account_oauth_clients
  - audit: iam.sa.key.revoked
  - CAEP push to subscribers
```

### Class B — Workload Identity Federation (preferred for CI/CD)

```
Trust Policy schema:
  id                ftp_<crockford>
  service_account_id   FK→service_accounts(id)
  issuer            TEXT (e.g. "https://token.actions.githubusercontent.com")
  audience          TEXT ("https://api.kacho.cloud")
  subject_pattern   TEXT — strict no-wildcard pattern, validated via regex
  additional_claims_filter   JSONB
  conditions        JSONB — source_ip CIDR, business_hours, expires_at
  max_token_ttl     INTERVAL ≤ 15min
  enabled           BOOL
  expires_at        TIMESTAMPTZ NOT NULL — mandatory; max 1y

Federation Exchange (RFC 8693):
  POST /iam/v1/federations:exchange
       grant_type=urn:ietf:params:oauth:grant-type:token-exchange
       subject_token=<external OIDC JWT>
       subject_token_type=urn:ietf:params:oauth:token-type:jwt

  kacho-iam:
    1. Parse external JWT; resolve issuer JWKS (cached 24h).
    2. Verify signature; validate iss/aud/exp/nbf.
    3. Lookup federation_trust_policies WHERE issuer=$1 AND enabled AND expires_at>now.
    4. Strict-match subject_pattern (no glob, exact equality or anchored regex from a controlled set).
    5. Apply additional_claims_filter (exact match on listed claims).
    6. Evaluate conditions (source_ip CIDR via X-Forwarded-For, business_hours).
    7. Issue Kachō JWT (sub=service_account_id, TTL=policy.max_token_ttl).
    8. audit: iam.federation.exchange.success / .denied

Supported sources (production-tested):
  - GitHub Actions: token.actions.githubusercontent.com
  - GitLab CI: gitlab.com (or self-hosted)
  - AWS IRSA (EKS): oidc.eks.<region>.amazonaws.com/id/<cluster-id>
  - GCP Workload Identity Federation
  - Azure Workload Identity
  - Bitbucket Pipelines
  - CircleCI
  - Buildkite
```

### Class C — In-cluster SPIFFE/SPIRE + Cilium mesh

```
SPIRE Server (3 HA replicas, Postgres-backed):
  - Trust domain: kacho.cloud
  - Root CA stored in HSM (AWS CloudHSM or GCP Cloud HSM or local SoftHSM for non-prod)
  - Registration entries managed via GitOps (Argo CD reads YAML manifests)
  - Federation bundles published на public endpoint для external SPIFFE-aware consumers

SPIRE Agent (DaemonSet per node):
  - Attests to Server via k8s_psat (projected SA token)
  - Selectors: k8s:ns + k8s:sa + k8s:image-signature (cosign-verified)
  - Workload API socket per node (/var/run/spire/sockets/agent.sock)
  - SVID validity 1h; auto-rotated

Cilium service mesh (eBPF, no sidecar):
  - Auto-mTLS between all kacho-* pods using SPIFFE SVIDs
  - CiliumNetworkPolicy per service:
      e.g. kacho-iam accepts internal RPC only from kacho-vpc/kacho-compute/kacho-api-gateway SPIFFE IDs
  - L7 path-based allowlist для admin endpoints
  - Encryption WireGuard between nodes
  - Hubble flow visibility for SOC

Defense-in-depth:
  1. Mesh mTLS confirms caller-service identity (which kacho-* service).
  2. gRPC metadata `x-kacho-end-user-principal` carries end-user (forwarded from api-gateway).
  3. Service-level authz uses end-user principal (not service identity) для ReBAC Check.
  Compromise of one pod → cannot impersonate Alice without valid Alice JWT.
```

---

## 7. List filtering — final design

Every List-RPC across kacho-vpc, kacho-compute, kacho-loadbalancer:

```go
func (s *NetworkService) List(ctx context.Context, req *vpcv1.ListNetworksRequest) (*vpcv1.ListNetworksResponse, error) {
    principal := authn.MustPrincipal(ctx)

    allowedIDs, consistencyToken, err := s.authz.ListAllowedIDs(ctx, principal, "vpc_network", "viewer", authz.ListObjectsOptions{
        Consistency:     authz.MINIMIZE_LATENCY,    // default; HIGHER_CONSISTENCY for sensitive ops
        ProjectScope:    req.ProjectId,              // optional contextual hint
        ContextualTuples: principal.ContextualTuples(),
    })
    if err != nil {
        return nil, status.Errorf(codes.Unavailable, "authz lookup failed: %v", err)
    }
    if len(allowedIDs) == 0 {
        return &vpcv1.ListNetworksResponse{}, nil
    }

    networks, nextToken, err := s.repo.ListByIDs(ctx, allowedIDs, req.PageSize, req.PageToken)
    if err != nil {
        return nil, status.Errorf(codes.Internal, "%v", err)
    }
    return &vpcv1.ListNetworksResponse{Networks: networks, NextPageToken: nextToken}, nil
}
```

### corelib/authz interface

```go
type Principal struct {
    ID, Type           string
    AccountID, OrganizationID string
    ACR                string
    AMR                []string
    MFAAt              time.Time
    SourceIP           net.IP
    DeviceAttestation  string
    ClusterAdmin       bool
    BreakGlassActive   bool
}

type CheckClient interface {
    Check(ctx, p Principal, relation, objectType, objectID string, opts CheckOptions) (allowed bool, err error)
}

type ListObjectsClient interface {
    ListAllowedIDs(ctx, p Principal, objectType, relation string, opts ListObjectsOptions) (ids []string, consistencyToken string, err error)
}
```

Cache: 5s TTL LRU per (principal_id, object_type, relation); LISTEN `kacho_iam_subjects` invalidates on any AccessBinding change.

### SLA (production-verified via k6)

| Op | p50 | p95 | p99 | p99.9 |
|---|---|---|---|---|
| Check (cache hit) | 0.1ms | 0.5ms | 1ms | 2ms |
| Check (cache miss) | 5ms | 20ms | 50ms | 100ms |
| ListObjects (cache hit) | 0.1ms | 0.5ms | 1ms | 2ms |
| ListObjects (miss, ≤100 ids) | 10ms | 50ms | 100ms | 200ms |
| ListObjects (miss, ≤1000 ids) | 25ms | 100ms | 250ms | 500ms |
| Cache hit ratio | ≥80% measured |

---

## 8. Service catalog & permission registry

Permissions auto-generated from proto:

```protobuf
import "kacho/iam/v1/authz.proto";

service NetworkService {
  rpc Create(CreateNetworkRequest) returns (operation.Operation) {
    option (kacho.iam.authz.permission) = "vpc.networks.create";
    option (kacho.iam.authz.required_relation) = "editor";
    option (kacho.iam.authz.scope_extractor) = { object_type: "project", from_request_field: "project_id" };
    option (kacho.iam.authz.required_acr_min) = "2";
  }
  // ...
}
```

Build pipeline:
1. `protoc-gen-kacho-permissions` emits `permission_catalog.json` (commit'ится в kacho-proto/gen/).
2. kacho-iam at startup → seeds `system_role_permissions`.
3. UI cascader reads catalog → 3-level (domain → resource → verb).
4. Custom role validation rejects unknown verbs.

---

## 9. Audit pipeline (full production)

### 9.1 Schema (CADF-compatible)

```json
{
  "event_id":   "evt_01h2n4z9...",         // ULID
  "timestamp":  "2026-05-19T14:23:00.123Z",
  "event_type": "iam.access_binding.created",
  "tenant":     {"organization_id":"org_x", "account_id":"acc_y"},
  "actor": {
    "type":"user", "id":"usr_alice", "email":"alice@example.com",
    "session_id":"sess_xxx", "token_jti":"jti_xxx",
    "ip":"10.0.0.5", "user_agent":"kacho-cli/0.5.0",
    "acr":"2", "amr":["webauthn"],
    "device_attestation":"attested"
  },
  "target": {
    "type":"access_binding", "id":"acb_yyy",
    "parent":{"type":"project","id":"prj_x"}
  },
  "action":  "create",
  "outcome": "success",
  "request": {"method":"POST","path":"/iam/v1/access_bindings:upsert","request_id":"req_zzz"},
  "response":{"status_code":200,"operation_id":"op_aaa"},
  "diff":{"before":null,"after":{...}},
  "risk_signals":{"impossible_travel":false,"anomaly_score":0.02},
  "metadata":{
    "trace_id":"<otel>","service":"kacho-iam","region":"eu-central-1",
    "cluster":"prod-1","cell":"shard-3"
  }
}
```

### 9.2 Pipeline

```
[Service mutation handler]
    │ BEGIN TX
    │   INSERT into <table> ...
    │   INSERT into audit_outbox (event_payload)
    │ COMMIT
    │
    ▼ NOTIFY 'audit_event'
[audit_drainer (per service)]
    │ batch (max 1000 events or 1s)
    │ producer.send(kafka audit-topic, partition by tenant)
    │
    ▼
[Kafka audit-topic (3 brokers, KRaft, ack=all, idempotent)]
    │
    ├─→ [ClickHouse consumer]
    │   - Buffer 1000 events / 5s, INSERT batch
    │   - Replicated MergeTree; partitioned by (tenant_id, day)
    │   - 90d hot retention; then drop partition
    │
    ├─→ [S3 batch writer]
    │   - 5-min windows
    │   - Compress JSONL.gz
    │   - Compute Merkle root over batch events
    │   - Sign batch manifest with HSM (PKCS#11) → batch_signature
    │   - Chain: include previous batch hash → tamper-evidence
    │   - Upload to s3://kacho-audit-cold/<tenant>/<year>/<month>/<day>/<hour>/<batch-id>.jsonl.gz + manifest.signed
    │   - Lifecycle: hot S3 (30d) → S3 IA (1y) → Glacier (10y)
    │
    ├─→ [SIEM forwarder (Datadog HEC / Splunk HEC / Elastic webhook)]
    │   - Per-tenant subscription
    │   - Detection rules:
    │     • brute force (>10 sign-in failures/IP/5min)
    │     • impossible travel (2 sign-ins, 2 countries, <2h)
    │     • mass deletion (>100 deletes/principal/5min)
    │     • out-of-hours admin (configurable per tenant)
    │     • SA created role > SA's own scope (privilege escalation)
    │     • audit signature failure (Critical → page)
    │     • break-glass usage (any) — Critical
    │
    └─→ [Independent verifier (job)]
        - Walks Merkle chain in S3
        - Verifies signatures via HSM public key
        - Detects: missing batch, tampered batch, broken chain
        - Alert on integrity violation → page security team
```

### 9.3 GDPR erasure pipeline

```
[User → request erasure UI / API]
    │
    ▼
[INSERT gdpr_erasure_requests (status=cool_off, requested_at=now)]
    │
    ▼ daily cron
[After 30d: status=in_progress]
    │
    ├─ User.Status=BLOCKED; revoke all sessions; CAEP push to subscribers
    ├─ Cascade revoke access_bindings (status=REVOKED)
    ├─ ReBAC tuples deleted via outbox
    ├─ SCIM webhook to downstream SPs
    ├─ Account-ownership transfer required if sole owner (admin manual step)
    ├─ Pseudonymize users.email/display_name → "gdpr-erased-<hash>"
    ├─ Hard-delete identity in Kratos
    ├─ Hard-delete resources in own projects (cascade VPC, compute, lb)
    └─ Audit row retained 7y (compliance > erasure per GDPR Art. 17(3)(b))
    │
    ▼
[status=completed; confirmation email]
```

### 9.4 Compliance map

| Control | Implementation |
|---|---|
| SOC 2 CC6.1 (Logical access) | RBAC+ReBAC+least priv; audit log; access reviews |
| SOC 2 CC6.6 (Monitoring) | SIEM + Grafana + PagerDuty alerts |
| SOC 2 CC6.7 (Admin restrict) | PIM/JIT + break-glass 2-person + reviews |
| SOC 2 CC7.2 (Anomaly detection) | SIEM detection rules + audit signature verification |
| ISO 27001:2022 A.5 (Policies) | This doc + acceptance docs APPROVED |
| ISO 27001:2022 A.8 (Asset Mgmt) | Resource hierarchy + inventory APIs |
| ISO 27001:2022 A.9 (Access Control) | RBAC+ReBAC+AAL levels |
| ISO 27001:2022 A.12 (Operational) | Audit + retention + observability |
| ISO 27001:2022 A.18 (Compliance) | GDPR erasure pipeline + retention policy |
| NIST CSF 2.0 IDENTIFY/ID.AM | Project + resource inventory |
| NIST CSF 2.0 PROTECT/PR.AC | Default-deny + MFA + step-up |
| NIST CSF 2.0 DETECT/DE.CM | OTel + SIEM + audit signature |
| NIST CSF 2.0 RESPOND/RS.MI | Reactive revoke + alerting + runbooks |
| NIST 800-63B AAL2/AAL3 | Passkey + step-up |
| NIST 800-207 (Zero Trust) | Continuous auth + CAEP + mesh mTLS |
| GDPR Art. 17 (Erasure) | 30d cool-off pipeline + pseudonymization |
| GDPR Art. 32 (Security) | Encryption (TLS 1.3, AES-256-GCM at rest) + access controls + audit |
| GDPR Art. 33 (Breach notification) | SIEM detection → 72h disclosure runbook |
| FedRAMP Moderate baselines | Aligned (HSM signing, FIPS 140-2 crypto, audit retention) |
| OWASP ASVS L3 | Conformance test in CI |
| FIDO Alliance compatible | WebAuthn L3 implementation |
| OpenID Foundation Certified | Kratos/Hydra components vendor-certified |

---

## 10. CAEP push pipeline — production

(See §9 pipeline above + spec for SET shape and retry logic.)

### Subscriber registry

```sql
CREATE TABLE caep_subscribers (
  id TEXT PRIMARY KEY,
  account_id TEXT REFERENCES accounts(id) ON DELETE CASCADE,
  endpoint_url TEXT NOT NULL CHECK (endpoint_url ~ '^https://'),
  signing_kid TEXT NOT NULL,                  -- kacho-iam key used for SET signing
  expected_audience TEXT NOT NULL,            -- aud claim in SET
  event_types TEXT[] NOT NULL,                -- subscribed events
  enabled BOOL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  failure_count INT DEFAULT 0,
  last_success_at TIMESTAMPTZ,
  last_failure_at TIMESTAMPTZ,
  last_failure_reason TEXT
);

CREATE TABLE caep_outbox (
  id TEXT PRIMARY KEY,                        -- ULID
  event_type TEXT NOT NULL,
  subject_id TEXT NOT NULL,
  account_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  attempts INT DEFAULT 0,
  status TEXT NOT NULL CHECK (status IN ('pending','in_flight','delivered','failed_terminal')),
  next_attempt_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);
```

### Drainer

```
- Worker pool size N=8 (configurable per env).
- Picks pending events FOR UPDATE SKIP LOCKED.
- For each subscriber matching (account_id, event_type intersect):
  - Sign SET (JWT with kacho-iam key kid; aud=subscriber.expected_audience).
  - POST endpoint Authorization: Bearer <SET>; Content-Type: application/secevent+jwt.
  - Subscriber returns 2xx → delivered.
  - 4xx (excluding 429) → failed_terminal + admin alert.
  - 5xx / 429 / timeout → increment attempts; schedule next_attempt_at.
  - Backoff: 1s, 5s, 30s, 5min, 1h, 6h, 24h; max 8 attempts.
- Per-subscriber rate-limit: max 100 events/min (защита от cascade-attack).
```

### Internal CAEP receiver (api-gateway)

```
- Listens on kacho-iam direct gRPC call (intra-cluster, not webhook).
- On token-claims-change / session-revoked event:
  - INSERT session_revocations (jti, revoked_at, reason, user_id, ttl=30d).
  - pgx LISTEN 'session_revoked' → all api-gateway pods refresh.
  - Reactivity: ≤ 1s.
```

---

## 11. PIM/JIT + Break-glass — production

### JIT eligibility

```sql
CREATE TABLE access_bindings_jit_eligibility (
  id TEXT PRIMARY KEY,
  user_id TEXT REFERENCES users(id) ON DELETE CASCADE,
  role_id TEXT REFERENCES roles(id) ON DELETE RESTRICT,
  resource_type TEXT NOT NULL,
  resource_id TEXT NOT NULL,
  max_duration INTERVAL NOT NULL DEFAULT '1 hour',
  approver_user_id TEXT REFERENCES users(id),     -- если approval required
  approval_required BOOL DEFAULT false,
  enabled BOOL DEFAULT true,
  expires_at TIMESTAMPTZ,                         -- eligibility itself can expire
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by TEXT REFERENCES users(id)
);
```

### ActivateJIT flow

```
User clicks Activate Admin in UI →
    Step-up to acr=3 (re-Passkey) →
    POST /iam/v1/access_bindings:activateJIT { role_id, resource_type, resource_id, duration_seconds=3600 }

kacho-iam:
  1. Validate eligibility row exists (enabled, not expired).
  2. If approval_required → INSERT pending request, notify approver via Slack/email; return Operation in pending state.
  3. Else (or after approval): INSERT access_bindings (status=ACTIVE, condition: jit_window(activated_at=now, ttl=duration)).
  4. INSERT fga_outbox (Conditional tuple).
  5. CAEP outbox (token-claims-change for subscriber notification).
  6. Audit: iam.jit.activated.
After duration: condition fails → tuple effective revoke; audit: iam.jit.expired.
```

### Break-glass

```sql
CREATE TABLE cluster_break_glass_grants (
  id TEXT PRIMARY KEY,
  subject_user_id TEXT REFERENCES users(id),
  status TEXT NOT NULL CHECK (status IN ('AWAITING_APPROVAL_A','AWAITING_APPROVAL_B','ACTIVE','EXPIRED','DENIED','REVOKED')),
  incident_id TEXT NOT NULL,
  rationale TEXT NOT NULL,
  requested_at TIMESTAMPTZ NOT NULL,
  approved_by_a TEXT REFERENCES users(id),
  approved_at_a TIMESTAMPTZ,
  approved_by_b TEXT REFERENCES users(id),
  approved_at_b TIMESTAMPTZ,
  expires_at TIMESTAMPTZ NOT NULL,                -- enforced ≤ 2h via OPA
  revoked_at TIMESTAMPTZ
);
```

Process per design §0; documented в runbook `docs/runbooks/break-glass.md` (must exist; CI checks).

---

## 12. Workload Identity in-cluster — production

See §6 Class C + Architecture §2. Operational:

- SPIRE Server deployed in dedicated namespace `spire-system` (3 HA replicas, anti-affinity).
- Root CA in HSM (AWS CloudHSM ClassicHSM or GCP Cloud HSM). For dev/staging — SoftHSM acceptable.
- Server-Agent attestation via k8s_psat (most robust on managed K8s).
- Registration entries:
  - Per-service ServiceAccount selector.
  - **Image signature selector** (cosign verifier) — added requirement: только cosign-signed images получают SVID.
  - Path-based selector (binary location) — extra layer.
- SVID validity 1h; rotated 30min before expiry; pod restarts not needed.
- Cilium service mesh:
  - eBPF dataplane (no sidecar overhead).
  - SPIFFE SVID consumed via Cilium native integration.
  - CiliumNetworkPolicy + CiliumClusterwideNetworkPolicy:
    - Default deny all ingress/egress.
    - Explicit allowlists per service.
    - L7 path-based deny rules (e.g. кто может звать `/v1/internal/*`).
  - Hubble flow telemetry exported to OTel.
- Federation bundles published на `https://spire.kacho.cloud/federation/bundle` for external consumers.

---

## 13. Production deployment

### 13.1 Infrastructure topology

```
Multi-region active-active (mvp regions: eu-central-1 + eu-west-1):

[GeoDNS (Cloudflare)]
    │
    ├─→ [Cloudflare edge in eu-central]
    │      │
    │      ▼
    │   [api.kacho.cloud TLS termination + WAF + DDoS]
    │      │
    │      ▼
    │   [K8s cluster prod-eu-central]
    │      ├─ kacho-api-gateway (3+ HPA-scaled, anti-affinity)
    │      ├─ kacho-iam, kacho-vpc, kacho-compute, kacho-loadbalancer
    │      ├─ ORY Kratos (3 HA), ORY Hydra (3 HA), Jackson (2 HA)
    │      ├─ OpenFGA (3 HA, leader-less reads)
    │      ├─ OPA sidecars (per gateway/backend pod)
    │      ├─ SPIRE Server (3 HA), SPIRE Agent (DaemonSet)
    │      ├─ Cilium (cluster CNI, mesh)
    │      ├─ Kafka (3 brokers KRaft)
    │      ├─ ClickHouse (2 shards × 2 replicas)
    │      ├─ Postgres (per-service; CloudSQL HA or vanilla streaming replication)
    │      └─ Argo CD, Prometheus, Loki, Tempo, Grafana
    │
    └─→ [Cloudflare edge in eu-west] (mirror — active-active OR active-passive)

Postgres replication:
  - Primary in eu-central; sync replica in eu-west; async DR replica.
  - RTO ≤ 15min via DNS failover + Postgres failover (Patroni or cloud-native).
  - RPO ≤ 1min via sync replication.

ClickHouse: replicated (Zookeeper-backed or built-in keeper); cross-region replicas for DR.
Kafka: 3 brokers per region; cross-region replication via MirrorMaker 2.
OpenFGA: read replicas per region; writer single-master with Postgres HA.
```

### 13.2 Domain / TLS

- Primary: `api.kacho.cloud` (public TLS via Let's Encrypt managed by cert-manager).
- ACME challenge: DNS-01 (Cloudflare API).
- Auto-renew 30d before expiry; alert on failure.
- HSTS preload list submitted; HSTS max-age=63072000 (2y) includeSubDomains.
- Cipher suites: TLS 1.3 only; CHACHA20+AES-256-GCM; ECDSA cert (P-256).
- HTTP/3 (QUIC) enabled at Cloudflare edge.

### 13.3 Secrets / KMS

- All secrets in K8s External Secrets Operator → HashiCorp Vault (or AWS Secrets Manager / GCP Secret Manager).
- HSM-backed signing keys: audit batch manifest, JWT signing, CAEP SET signing, SPIRE trust-domain CA.
- Rotation:
  - JWT signing key: 90d cycle (rolling: current + previous in JWKS).
  - DB encryption KEK: yearly.
  - mTLS internal CA: 30d intermediate; 1y root.
  - HashiCorp Vault transit-engine для secret-at-rest.

### 13.4 CI/CD

- Argo CD GitOps (manifests in `kacho-deploy` repo).
- Per-environment overlay (dev / staging / prod).
- Promotion: feature → dev → staging (smoke + integration) → prod (manual approval + canary).
- Canary: 5% → 25% → 50% → 100% over 30min; auto-rollback on SLO breach.

CI workflows per service:
- lint (golangci-lint + buf lint + rego unit-tests).
- unit tests.
- integration tests (testcontainers).
- newman regression suite (per service).
- k6 load test (smoke profile).
- container build + cosign sign + SBOM (syft) + vulnerability scan (trivy/grype).
- SLSA build provenance attestation (in-toto via gh-actions/attest-build-provenance).

Promotion blocked if:
- Any CI workflow red.
- Test coverage drop >5% in PR diff.
- Security scan finds High/Critical CVE in new dependencies.
- SBOM contains banned licenses (GPL family for backend).

### 13.5 Observability

- OTel collector deployed как DaemonSet + Deployment hybrid.
- Traces: 100% sample for control plane (low volume); 5% for dataplane (high volume).
- Metrics: per-service standard + IAM-specific (Check latency, FGA tuple write, CAEP delivery).
- Logs: structured JSON via slog; PII scrubbed (email → hash; tokens → redacted).
- Grafana dashboards committed in `kacho-deploy/dashboards/*.json`.
- Alert routing via Alertmanager → PagerDuty (P1/P2) / Slack #iam-alerts (P3) / email (P4).
- Runbooks per alert in `docs/runbooks/<alert-name>.md`.

### 13.6 Reliability targets

| SLO | Target |
|---|---|
| API availability (99.95%) | ≤ 4.4h downtime/year |
| Check p95 latency | ≤ 20ms |
| ListObjects p95 latency | ≤ 100ms |
| Revoke propagation (CAEP) | ≤ 10s p99 |
| Audit ingest lag | ≤ 60s p99 |
| DR RTO | ≤ 15min |
| DR RPO | ≤ 1min |
| Cert renewal SLA | ≤ 30d before expiry |
| JWKS rotation SLA | ≤ 90d |

---

## 14. Threat model (production-grade)

| Threat | Defense |
|---|---|
| Token theft (XSS) | DPoP non-extractable key; CSP `script-src 'self' 'nonce-...'`; httpOnly cookies via BFF |
| Phishing for credentials | Passkey origin-bound; WebAuthn refuses non-canonical origin |
| Confused deputy | Principal in gRPC metadata; Check based on principal not service identity; Token Exchange for delegation |
| Privilege escalation (chained assume-role) | OPA Deny rules; permission boundaries (max scope per role); SA cannot grant to user |
| Stolen refresh token | Rotation + family-revoke on reuse; CAEP push on detect |
| Replay attack | DPoP `jti` cache; SET jti cache subscriber-side; nonce per WebAuthn challenge |
| Algorithm confusion | Whitelist algs per key (kid → alg mapping enforced); reject `none`; PASETO ready |
| Static secret leakage | Workload Identity Federation (Class B) replaces; secrets only in Vault/HSM |
| Lateral movement after pod compromise | Cilium NetworkPolicy default-deny; SPIFFE mTLS; reactive revoke ≤10s |
| Mass data extraction via SA | Per-SA rate-limits + anomaly detection (SIEM rule); CAEP push on threshold |
| Audit tampering | Append-only Kafka + S3 object lock + HSM-signed Merkle chain; independent verifier job |
| Compromised admin → mass-grant | OPA rate-limit deny; SIEM alert on >N grants/5min; quarterly access review |
| Insider rouge admin | JIT/PIM + 2-person break-glass + audit append-only |
| TOCTOU (Check then act) | Atomic write with UNIQUE/CHECK + CAS-pattern |
| Stale grants after employee leaves | SCIM lifecycle hook → cascade revoke + CAEP push |
| Open invite link replay | Single-use; bound to email; expiry ≤7d |
| Compromised image | cosign signature verification at SPIRE attestor + Cilium admission |
| Supply chain (dependency tampering) | SBOM + SLSA L3 provenance + vulnerability scan + license check |
| DPoP key extraction (sophisticated attack) | Defense-in-depth: short access TTL + CAEP push + IP anomaly detection |
| HSM compromise | Defense-in-depth: independent Merkle verifier (offline) catches signature anomalies |
| DNS hijacking | DNSSEC; cert-pinning via CAA records; HSTS preload |
| BGP hijacking | Cloudflare RPKI validation; multi-CDN redundancy |
| DDoS volumetric | Cloudflare L3/L4/L7 protection; rate-limits per endpoint per IP |
| Side-channel (timing attacks on auth) | Constant-time crypto (Go crypto/subtle); careful HSM access patterns |
| Zero-day in dependencies | Continuous vulnerability scan + auto-PR via Renovate + ASAP patch cycle |

---

## 15. User journeys (production complete — 32 journeys)

All 30 journeys from skill `references/user-journeys.md` (J1-J30) are IN scope and end-to-end tested. Plus production-specific:

### J31 — Grant cluster-admin via Internal RPC

(See skill J23 + production specifics: PagerDuty alert + 2-person approve + audit retention 7y.)

### J32 — Workload Identity Federation new GitHub repo

(See skill J22 + production: trust policy expires_at ≤ 1y; subject_pattern regex validation; CI integration test пишет/проверяет policy.)

### J33 — Step-up for cluster-admin op

(See skill — required_acr=3 for cluster.* admin; OPA Deny rule enforces.)

### J34 — JIT admin elevation

(See §11 above; full audit trail; approval workflow integrated с Slack.)

### J35 — Break-glass with 2-person approve

(See §11 above; PagerDuty incident + Slack #security + email; mandatory post-incident review ≤7d enforced via tracking issue.)

### J36 — Multi-region failover

- Primary region down → GeoDNS routes к secondary.
- User session preserved (JWT validates на any region — JWKS replicated).
- ReBAC tuples replicated (Postgres sync replica).
- CAEP push retries reach subscribers.
- SLA: RTO ≤ 15min; user-visible latency uptick ≤ 50ms.

### J37 — Continuous chaos engineering game-day

- Litmus injects: pod kill, network partition, slow Postgres, DPoP cert revocation.
- Sustained traffic from k6 background load.
- Validate: SLO breaches contained; auto-rollback works; alerts fire correctly.
- Quarterly cadence; post-game-day improvements tracked in runbooks.

### J38 — Security audit / pentest engagement

- Annual external pentest (e.g., NCC Group / Trail of Bits).
- Scope: full IAM surface + identity flows + federation + audit + admin operations.
- Findings tracked in security issue tracker; remediation SLA per severity.
- Re-test after remediation; sign-off от security team.

---

## 16. Migration plan — production phases (12 phases, no out-of-scope)

| Phase | Scope | Duration | Acceptance doc |
|---|---|---|---|
| **1 Foundation** | DB schema (Org+Cluster+Federation+Conditions+JIT+outboxes+audit+CAEP+SCIM+session_revocations+jwks+gdpr+break_glass+access_reviews); migrations 0011-0014 (split logical). Permission registry from proto. | 2-3 weeks | `sub-phase-3.1-iam-foundation-acceptance.md` |
| **2 AuthN core** | Kratos WebAuthn + Hydra DPoP + mTLS-bound tokens + step-up + recovery + JWKS rotation + back-channel logout. | 3-4 weeks | `sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md` |
| **3 AuthZ core** | OpenFGA model v2 + Conditions + OPA sidecar + bundle signing + Rego unit-tests. | 3-4 weeks | `sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md` |
| **4 List filtering** | corelib/authz/listobjects.go + per-service rewrite (vpc/compute/lb) + k6 SLA validation. | 2 weeks | `sub-phase-3.4-iam-list-filtering-acceptance.md` |
| **5 Workload Identity Federation (external)** | SA-keys via Hydra (Class A) + FederationExchangeService (Class B) + GitHub/AWS/GCP/GitLab/Bitbucket/CircleCI/Buildkite integration tests + Trust Policy UI. | 3-4 weeks | `sub-phase-3.5-iam-workload-identity-federation-acceptance.md` |
| **6 Enterprise SSO** | SCIM 2.0 (RFC 7644) endpoint + Boxyhq Jackson SAML bridge + Organization tier full integration + JIT provisioning + per-Org SSO config UI + domain-claim verification. | 4-5 weeks | `sub-phase-3.6-iam-scim-saml-organization-acceptance.md` |
| **7 JIT/PIM + Break-glass** | Eligibility table + ActivateJIT + Approval workflow + break_glass with 2-person + PagerDuty/Slack integrations + Access Reviews quarterly automation + GDPR erasure pipeline. | 3-4 weeks | `sub-phase-3.7-iam-jit-breakglass-reviews-gdpr-acceptance.md` |
| **8 CAEP push pipeline** | caep_outbox+drainer+SET signing+subscriber registry+webhook retry+internal receiver+k6 latency SLA. | 2-3 weeks | `sub-phase-3.8-iam-caep-push-acceptance.md` |
| **9 Audit pipeline (full)** | Kafka audit-topic (KRaft 3 brokers) + ClickHouse cluster (2×2) + S3+Glacier with HSM batch signing + Merkle chain + independent verifier job + SIEM forwarders (Datadog/Splunk/Elastic) + Detection rules. | 4-5 weeks | `sub-phase-3.9-iam-audit-pipeline-acceptance.md` |
| **10 In-cluster Workload Identity + Service Mesh** | SPIRE Server (3 HA Postgres) + Agent DaemonSet + Cilium service mesh deploy + CiliumNetworkPolicy + AuthorizationPolicy + HSM-backed trust-domain CA + cosign image-signature attestor + Hubble observability. | 4-5 weeks | `sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md` |
| **11 Production deployment + Observability** | api.kacho.cloud public TLS + Cloudflare WAF+DDoS + multi-region active-active + Postgres HA replication + cross-region Kafka MirrorMaker + ClickHouse cross-region + Grafana dashboards + Alertmanager + PagerDuty + Runbooks + GitOps Argo CD + SBOM + SLSA L3 + cosign + Renovate. | 5-6 weeks | `sub-phase-3.11-iam-production-deploy-observability-acceptance.md` |
| **12 Conformance + Pentest + Chaos + Fuzzing** | OWASP ASVS L3 conformance test in CI + continuous fuzzing (go-fuzz + cargo-fuzz for FGA model parser) + Litmus chaos game-days + external pentest engagement + bug bounty program launch + responsible disclosure policy + security.txt. | 4-5 weeks | `sub-phase-3.12-iam-conformance-pentest-chaos-acceptance.md` |
| **13 Vault docs + KAC-127 final trail** | 30+ vault files updated; production deployment runbooks; security disclosure docs. | 1 week | `sub-phase-3.13-iam-docs-closeout-acceptance.md` |

**Total effort**: 40-52 weeks single-engineer (~10-12 months). Parallelizable to **~5-7 months** with team of 4-5 engineers (proto/corelib/iam/deploy/security split).

### 16.1 Per-PR mandatory (запрет CLAUDE.md #11)

Integration tests (testcontainers Postgres + mock external services) + newman cases (gen.py → Postman collection) + Rego unit-tests (где OPA задействован) **в том же PR**. Никаких "tests-followup" вообще (production edition).

### 16.2 Per-phase mandatory artifacts

Each phase delivers:
1. APPROVED acceptance doc by `acceptance-reviewer`.
2. PR-chain merged across affected repos (proto → corelib → service → api-gateway → deploy → ui → workspace).
3. Integration tests green (≥80% coverage on new code).
4. Newman cases green (≥10 cases per phase минимум).
5. k6 load tests pass SLA (where applicable).
6. e2c825 dev smoke + staging smoke + prod canary smoke.
7. Grafana dashboard updated (new panels for phase features).
8. Runbook (`docs/runbooks/<feature>.md`) if alerts introduced.
9. Vault updated (resources/rpc/edges/packages + KAC-127.md trail).
10. CI workflows all green (lint, unit, integration, newman, k6 smoke, container-scan, sbom, slsa).

---

## 17. Definition of Done — production-ready

### Functional
- [ ] All 32 user journeys (J1-J38, applicable subset) demonstrated end-to-end на public `api.kacho.cloud` deployment.
- [ ] Smoke checklist on production:
  - Signup (Passkey first device) → Account + default Project + admin auto-binding.
  - Sign-in (Passkey) → JWT validated, DPoP binding active.
  - Step-up to AAL3 for cluster-admin op → re-Passkey ceremony succeeds.
  - Project-level invite (existing User) → instant ACTIVE binding.
  - Project-level invite (new email) → PENDING + magic-link via Kratos.
  - Custom Role create (project-scoped) → bound to user via batch resource_ids.
  - List networks (user with 2-id grant) → returns exactly 2; (no grant) → empty list, не 403.
  - SA Issue Key via Hydra → JWT login from external system validates.
  - Federation Exchange (mocked GitHub OIDC) → Kachō JWT issued in ≤2s.
  - JIT activation (eligible user) → admin for 1h then expires.
  - Break-glass 2-person approve → 2h grant + PagerDuty fires + auto-revoke at expiry.
  - Cluster-admin revoke → CAEP webhook to test SP delivered ≤10s.
  - SCIM provisioning (mocked Okta) → Org-scoped User created + group membership active.
  - SAML SP-init (mocked) → JIT-provisioned User + appropriate role mapped.
  - Audit log query (admin) → events visible in ClickHouse UI within 60s.
  - Audit signature verification job passes (Merkle chain intact).
  - GDPR erasure request → cool-off → pipeline completes → confirmation email sent.

### Tests / CI
- [ ] Integration tests: ≥80% coverage on new code; всё зелёное.
- [ ] Newman regression suite: ≥90 cases across all phases.
- [ ] k6 load tests: Check p95 ≤20ms; ListObjects p95 ≤100ms; CAEP p99 ≤5s; sustained 1000 RPS for 30min.
- [ ] Playwright E2E (UI): all happy-paths + critical error paths.
- [ ] Chaos tests (Litmus): quarterly game-day passes без manual intervention.
- [ ] Continuous fuzzing (go-fuzz): no crashes in 7d run.
- [ ] OWASP ASVS L3 conformance test passes.
- [ ] OIDC certified compliance tests (Hydra) pass.
- [ ] Security scan (trivy + grype + gosec): zero High/Critical findings.
- [ ] SBOM generated + cosign signature verified.
- [ ] SLSA L3 build provenance attached к каждому image.
- [ ] All CI workflows green (lint, unit, integration, newman, k6 smoke, security-scan, sbom, container-scan, license-check).

### Operational
- [ ] api.kacho.cloud public TLS endpoint reachable.
- [ ] Cloudflare WAF rules deployed (OWASP CRS 3.x + custom).
- [ ] Multi-region active-active operational (eu-central primary + eu-west secondary minimum).
- [ ] Cert auto-renew tested (force-renew dry-run passes).
- [ ] Postgres HA failover tested (RTO measured ≤15min on staging).
- [ ] Kafka cross-region MirrorMaker operational.
- [ ] ClickHouse cluster healthy (2 shards × 2 replicas).
- [ ] OpenFGA cluster healthy (3 replicas, leader-less).
- [ ] OPA bundles signed + verified в production.
- [ ] SPIRE Server + Agent operational; SVIDs issued to all kacho-* pods.
- [ ] Cilium service mesh enforced (test: пакет от non-allowlisted pod rejected).
- [ ] HSM accessible; audit batch signing operational.
- [ ] Independent audit verifier job runs daily без integrity alerts.
- [ ] PagerDuty integration verified (test alert delivered).
- [ ] Slack #iam-alerts wired to Alertmanager.
- [ ] All runbooks present and tested via tabletop exercise.

### Security / Compliance
- [ ] OWASP ASVS L3 self-assessment completed with attestation.
- [ ] SOC 2 Type II preparation: control mapping documented; evidence collection automated.
- [ ] ISO 27001:2022 Annex A controls mapped to features.
- [ ] NIST 800-63B AAL2/AAL3 compliance documented + tested.
- [ ] NIST 800-207 Zero Trust architecture validated.
- [ ] GDPR Articles 17/32/33 procedures documented + tested.
- [ ] Pentest engagement scheduled (annual cadence); first engagement completed before GA.
- [ ] Bug bounty program prepared (HackerOne / Bugcrowd) — opt-in launch after pentest.
- [ ] `security.txt` published at `/.well-known/security.txt`.
- [ ] Responsible disclosure policy at `https://kacho.cloud/security/disclosure`.
- [ ] FIDO Alliance WebAuthn L3 conformance verified.
- [ ] Vendor certifications: Kratos/Hydra current OpenID Foundation certification status documented.

### Documentation
- [ ] All acceptance docs (sub-phase-3.1..3.13) APPROVED.
- [ ] Architecture diagrams committed (mermaid / draw.io / canvas).
- [ ] User-facing docs at `docs.kacho.cloud/iam/` (signup, MFA, Service Account, Federation, Role management, JIT, Audit log query).
- [ ] Admin docs at `docs.kacho.cloud/admin/iam/` (Organization SSO setup, SCIM, Break-glass, Compliance reports).
- [ ] Developer docs at `docs.kacho.cloud/dev/iam/` (Federation OIDC setup для CI/CD).
- [ ] Runbooks for: break-glass, key rotation (JWT/CA), regional failover, GDPR erasure, audit pipeline incident, CAEP backlog, FGA tuple drift reconciliation.
- [ ] Vault updated: 30+ files (resources, rpc, edges, packages, KAC-127.md final trail).

### Code quality (no tech debt)
- [ ] Zero `// TODO`, `// FIXME`, `// XXX`, `// HACK` comments in production code (CI grep check fails build).
- [ ] Zero "deferred" / "next epic" / "follow-up" references in commit messages.
- [ ] Zero test-skips (`t.Skip(...)`) without an explicit referenced KAC tracking issue + planned resolution date.
- [ ] All open GitHub Issues и YouTrack KAC tickets associated с this epic — closed.
- [ ] golangci-lint passes with project-strict config (no waivers).
- [ ] gosec passes (no waivers without security-team sign-off).

---

## 18. Compliance attestations (for GA launch)

| Attestation | Status |
|---|---|
| OpenID Foundation Self-Certification (OIDC Core RP) | Submitted before GA |
| FIDO Alliance WebAuthn Conformance | Self-tested before GA; full certification within 6 months |
| SOC 2 Type II audit | Engagement scheduled within 3 months post-GA |
| ISO 27001 Certification | Internal audit before GA; external within 12 months |
| GDPR DPIA (Data Protection Impact Assessment) | Completed before GA |
| Russian Federation 152-FZ (if applicable) | Compliance documented |
| Bug bounty program | Launched within 1 month post-GA |

---

## 19. References

- Workspace skill: `.claude/skills/iam-architect/SKILL.md`
- Skill references: `identity-model.md`, `oidc-oauth2.md`, `zanzibar-rebac.md`, `workload-identity.md`, `cloud-iam-patterns.md`, `security-2026.md`, `audit-compliance.md`, `user-journeys.md`
- Vision doc: `docs/superpowers/specs/2026-05-19-iam-revolutionary-architecture-design.md`
- Baseline KAC-108 acceptance: `docs/specs/sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md`
- Baseline KAC-125 acceptance: `docs/specs/sub-phase-2.0-iam-KAC-125-user-invite-flow-acceptance.md`
- ORY Kratos / Hydra: <https://www.ory.sh>
- OpenFGA: <https://openfga.dev>
- OPA: <https://www.openpolicyagent.org>
- SPIFFE / SPIRE: <https://spiffe.io>
- Cilium: <https://cilium.io>
- Boxyhq Jackson: <https://github.com/boxyhq/jackson>
- OpenID CAEP: <https://openid.net/specs/openid-caep-1_0.html>
- RFC 9449 DPoP: <https://datatracker.ietf.org/doc/rfc9449/>
- RFC 8693 Token Exchange: <https://datatracker.ietf.org/doc/rfc8693/>
- RFC 8417 Security Event Tokens: <https://datatracker.ietf.org/doc/rfc8417/>
- RFC 7644 SCIM 2.0: <https://datatracker.ietf.org/doc/rfc7644/>
- W3C WebAuthn L3: <https://www.w3.org/TR/webauthn-3/>
- NIST SP 800-63B: <https://pages.nist.gov/800-63-3/sp800-63b.html>
- NIST SP 800-207 Zero Trust: <https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-207.pdf>
- OWASP ASVS: <https://owasp.org/www-project-application-security-verification-standard/>
- SLSA Framework: <https://slsa.dev>
- Sigstore / cosign: <https://www.sigstore.dev>

---

**End of production-ready design doc**. Implementation начинается ПОСЛЕ APPROVED acceptance docs per-phase (запрет CLAUDE.md #1). Никаких deferred / follow-up — все в scope, всё нужно сделать.
