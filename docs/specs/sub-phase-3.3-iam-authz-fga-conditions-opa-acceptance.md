# Sub-phase 3.3 — IAM AuthZ Core: OpenFGA model v2 + Conditions + OPA sidecar (KAC-127 / YT KAC-123) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: [KAC-123](https://prorobotech.youtrack.cloud/issue/KAC-123) — production-ready next-gen IAM (vault-label `KAC-127`).
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` (Decision Log §1, Architecture §2, OpenFGA model v2 §4, Rego guardrails §4.1, AuthN §5, corelib/authz §7, DoD §17).
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — Phase 3 (tasks 3.1-3.7).
> **Phase position**: §16 design doc "Migration plan", **Phase 3 of 13**.
> **Predecessors (must be merged before code begin)**:
> - Phase 1 — Foundation (`sub-phase-3.1-iam-foundation-acceptance.md`): migrations `0011..0014`, в т.ч. `access_binding_conditions`, `federation_trust_policies`, `organizations`, multi-scope `roles`, `cluster_kacho_root` singleton, `permission_catalog.json`.
> - Phase 2 — AuthN core (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`): Kratos Passkey, Hydra DPoP, JWT с `amr`/`acr`/`auth_time`/`cnf.jkt`/`ext_claims.kacho_mfa_at`/`ext_claims.kacho_device_compliance`, api-gateway DPoP/mTLS validation, Principal-extraction в gRPC-metadata.
> - **Phase 2.0 / E3** baseline (`sub-phase-2.0-iam-E3-openfga-rebac-acceptance.md`, KAC-108): `corelib/authz` Check + ListObjects interfaces, per-service interceptor, AccessBindingService.Upsert→fga_outbox→FGA tuples worker, subject-cache LISTEN/NOTIFY invalidation, OpenFGA store + model v1 (stub DSL).
> **Target repos / merge order (топологическая сортировка graf'а)**:
> 1. `PRO-Robotech/kacho-proto` — расширение `AccessBindingService.Upsert` request (`condition_id` field, `expires_at` field) + `kacho.iam.opa.v1.OpaBundleService` (internal).
> 2. `PRO-Robotech/kacho-corelib` — `authz/conditions_context.go` (новый), `authz/check.go` (расширение contextual_tuples), `authz/listobjects.go` (skeleton — package + interface only; Phase 4 integrates).
> 3. `PRO-Robotech/kacho-iam` — `internal/apps/kacho/api/access_binding/upsert.go` (condition_id transmit к FGA tuple с Conditional structure), `internal/apps/kacho/api/opa/{bundle,sign_bundle}.go` + `policies/*.rego` + `policies/*_test.rego`.
> 4. `PRO-Robotech/kacho-deploy` — `helm/umbrella/templates/openfga-model-stub-configmap.yaml` (replace stub → full DSL §4), `openfga-bootstrap-job.yaml` (idempotent + Secret update), `opa-sidecar-configmap.yaml`, `opa-bundle-server-configmap.yaml`, sidecar injection в `charts/kacho-iam/templates/deployment.yaml` + `charts/kacho-api-gateway/templates/deployment.yaml` + per-backend (vpc/compute/loadbalancer).
> 5. `PRO-Robotech/kacho-workspace` — vault обновления (`obsidian/kacho/KAC/KAC-127.md`, `obsidian/kacho/architecture/authz-pipeline.md`, `obsidian/kacho/rpc/iam-opa-bundle.md`).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 3 — **second code-emitting Phase** под KAC-127 (после Phase 1 DB-foundation и Phase 2 AuthN
plane). Тут закладывается **runtime authorization pipeline** во весь рост, который дальше
переиспользуется Phases 4-13:

1. **OpenFGA Authorization Model v2 deploy** — заменяет stub-модель из E3 (KAC-108) на **полный
   DSL design §4** с типами `cluster`, `organization`, `account`, `project`, `vpc_*`,
   `compute_*`, `lb_*`, плюс **7 предустановленных Conditions** (`mfa_fresh`, `non_expired`,
   `source_ip_in_range`, `break_glass_window`, `jit_window`, `business_hours`,
   `device_compliant`). Модель **versioned + immutable**: каждое изменение модели → новый
   `authorization_model_id`, который записывается в Kubernetes Secret `openfga-model-id` и
   пиннится при каждом Check-вызове (нет implicit "latest").

2. **Conditional ReBAC** — `corelib/authz` теперь умеет передавать **contextual_tuples** на
   каждый Check (`acr_value`, `amr_claims`, `mfa_at`, `current_time`, `client_ip`,
   `device_attestation`); FGA-движок применяет CEL-like Condition-выражение и возвращает
   allowed/denied **с учётом runtime-контекста**. AccessBindingService.Upsert получает
   возможность присоединить `condition_id` (FK → `access_binding_conditions` из Phase 1) к
   biding'у — FGA tuple записывается в Conditional-форме `user:X#vpc_admin@vpc_network:Y[mfa_fresh]`.

3. **OPA sidecar pipeline** — после того как FGA Check returns ALLOW, запрос дополнительно
   проходит **OPA Rego guardrails** (deny-only). OPA — sidecar в pod'е каждого backend-сервиса
   и api-gateway, поднимает signed bundle с `kacho-iam` (1h TTL, JWS-подпись), evaluates
   6 production deny-rules (cross-tenant, SA-grant-user, org-region restriction,
   billing-project destructive, out-of-hours-prod, break-glass max 2h). OPA fails → fail-closed.

4. **Bundle signing + verification** — `kacho-iam` serves `/opa/v1/bundle.tar.gz` (Internal RPC
   `OpaBundleService.GetBundle`, signed in-band JWS с `ES256` ключом из `oidc_jwks_keys` table
   Phase 1). OPA sidecar verifies signature перед load'ом. Tampered bundle → bundle reject,
   OPA stale-bundle alarm.

5. **Rego unit-tests in CI** — `kacho-iam/policies/*_test.rego` для каждого deny-rule
   (positive: deny fires; negative: allow passes). CI fails если хоть один Rego-test red.

6. **Cache invalidation contract** — AccessBinding mutation → `kacho-iam` пишет outbox →
   worker отправляет FGA-Write + NOTIFY `kacho_iam_subjects` (Phase 2.0 E3 baseline) — все
   per-service `corelib/authz` Check-cache'и invalidate-ят per-subject entry в ≤1s.

7. **Fail-closed на FGA/OPA unavailable** — мутации **запрещены** при недоступности любого
   из двух engines; чтения опционально fail-open за feature-flag (см. §5.7).

**Phase 3 НЕ включает** (это Phases 4-13 одного и того же epic'а — НЕ "deferred"):

- ListObjects integration per List-handler (filter-on-read для большого number-of-resources) —
  **Phase 4**. Phase 3 кладёт только **skeleton** `corelib/authz/listobjects.go` (interface +
  package layout), чтобы Phase 4 не делал двойной round trip review.
- Federation Exchange RPC (Token Exchange RFC 8693), SA Hydra-clients — **Phase 5**.
- SCIM 2.0 endpoint + SAML bridge + Organization-UI — **Phase 6**.
- JIT activation RPC + Break-glass workflow + 2-person approval — **Phase 7** (Phase 3 задаёт
  только `break_glass_window` / `jit_window` Conditions и Rego deny-rule "max 2h"; сам
  workflow `ActivateJIT` / `RequestBreakGlass` — Phase 7).
- CAEP drainer + SET signing + webhook delivery — **Phase 8**.
- Audit pipeline Kafka + ClickHouse + S3 — **Phase 9**.
- SPIFFE/SPIRE + Cilium mesh — **Phase 10**.
- Multi-region + `api.kacho.cloud` TLS + Argo CD + Grafana + Alertmanager — **Phase 11**.
- OWASP ASVS L3 + fuzzing + chaos + pentest — **Phase 12**.
- Vault closeout (30+ files) — **Phase 13**.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace `CLAUDE.md`) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше остаётся `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать "yandex" | в коде / Rego / DSL / комментариях / env-name не упоминается; YC-стилистика error-text (`"<Resource> %s not found"`, `Illegal argument`) — остаётся при mapping FGA/OPA denies в gRPC `PermissionDenied` (см. §6.16) |
| **Запрет #3** — НЕ ORM | OpenFGA SDK (`openfga-go-sdk`) — это **HTTP-клиент к FGA**, не ORM (его use разрешён, как и любой sdk-клиент к peer-сервису); `kacho-iam` `policies/*.rego` storage — flatfile в репо (compile-time embed через `//go:embed`), не БД; bundle-endpoint serves Rego из `embed.FS` |
| **Запрет #4** — НЕ каскад через границу сервиса | OPA bundle pull — это HTTP read, не cascade-delete; FGA-tuples deletion — внутри `kacho-iam` outbox-worker (одна служба), не cross-service |
| **Запрет #5** — НЕ редактировать применённую миграцию | в Phase 3 **новых миграций НЕТ** (все таблицы — из Phase 1: `access_binding_conditions`, `oidc_jwks_keys`); если в ходе implementation выявится missing column — открывается **новая** миграция `0015_kac127_phase3_authz.sql` (не правка Phase 1) |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | `OpaBundleService.GetBundle` — Internal RPC на port 9091, регистрируется через `restmux.RegisterInternal()` в api-gateway, **не** в public mux. OPA sidecar обращается к `kacho-iam` через cluster-internal address (`kacho-iam-internal.kacho-system.svc.cluster.local:9091`), без TLS-edge |
| **Запрет #7** — НЕ broker, пока in-process справляется | OPA bundle pull — HTTP poll (1h TTL); FGA Check — gRPC direct; cache invalidation — Postgres LISTEN/NOTIFY (E3 baseline, без брокера) |
| **Запрет #8** — DB-per-service | OPA Rego — без БД, embed.FS из `kacho-iam` репо; FGA-engine использует свой Postgres (это **его** datastore, не shared); Rego helpers (`user_in_organization`, `principal_in_resource_account`, `within_business_hours`) читают data из bundle-стороны (data.json в bundle), не cross-DB |
| **Запрет #9** — async-only мутации | в Phase 3 нет новых мутирующих публичных RPC (расширяется только `AccessBindingService.Upsert` — он уже async-Operation из E3 KAC-108); внутренний `OpaBundleService.GetBundle` — sync read (как FGA Check), не мутация |
| **Запрет #10** — within-service refs на DB-уровне | OpenFGA-engine сам обеспечивает atomic-write tuples (single FGA Write call с atomic semantics); `access_bindings.condition_id` FK уже создан в Phase 1 (`0012_kac127_federation_jit_conditions.sql`, см. `sub-phase-3.1` §6); Phase 3 только использует existing FK |
| **Запрет #11** — тесты в том же PR | каждый PR Phase 3 содержит: kacho-proto — buf-lint + buf-breaking; corelib — unit-tests `conditions_context_test.go` + integration с openfga testcontainer; kacho-iam — integration-tests bundle endpoint + Rego-tests (`opa test policies/`) + worker race-test; kacho-deploy — `helm template` golden + chartronaut/conftest validate; smoke — newman cases (см. §7 DoD) |

---

## 2. Глоссарий / доменная модель Phase 3 (нормативно)

### 2.1 Сущности, **используемые** в Phase 3 (от Phase 1/2 — read-only здесь)

- **Cluster** — singleton `cluster_kacho_root`; FGA-object `cluster:cluster_kacho_root`,
  используется в DSL v2 для `system_admin` / `emergency_admin` / `system_viewer` relations.
- **Organization** — optional B2B-tier `organization:<org_id>`; параметризуется в DSL v2
  типом `organization` с relations `owner`, `admin`, `editor`, `viewer`, `billing_admin`,
  `scim_admin`.
- **Account** — `account:<account_id>`; relations `owner`, `admin`, `editor`, `viewer`,
  `billing_admin`; computed-cascade `or admin from organization` если `organization` link set.
- **Project** — `project:<project_id>`; relations `admin`, `editor`, `viewer`; cascade
  `or admin from account` etc.
- **Per-service resource-объекты** — `vpc_network`, `vpc_subnet`, `vpc_security_group`,
  `vpc_route_table`, `vpc_address`, `vpc_gateway`, `vpc_private_endpoint`,
  `vpc_network_interface`, `vpc_address_pool`, `compute_instance`, `compute_disk`,
  `compute_image`, `compute_snapshot`, `lb_network_load_balancer`, `lb_target_group`.
  Pattern repeats: `define project: [project]` + 3-level `admin/editor/viewer`. Дополнительно
  `compute_instance` имеет `ssh` (`[user with mfa_fresh, service_account] or admin`) и
  `console` (`[user with mfa_fresh] or admin`).
- **AccessBindingCondition** (Phase 1 table `access_binding_conditions`) — каталог
  CEL-like predicate templates; имена `predicate_name` ∈ whitelisted set:
  `mfa_fresh` / `non_expired` / `source_ip_in_range` / `break_glass_window` / `jit_window` /
  `business_hours` / `device_compliant`. `params JSONB` — per-binding-instance parameters
  (например, `{"allowed_cidrs": ["10.0.0.0/8"]}` для `source_ip_in_range`).
- **AccessBinding (extended Phase 1)** — `condition_id` FK → `access_binding_conditions`,
  nullable; `expires_at TIMESTAMPTZ` nullable. Если condition_id set — FGA tuple пишется в
  **Conditional-форме**.
- **Principal** (Phase 2 contract) — extracted из DPoP-bound JWT в api-gateway,
  propagated в gRPC-metadata `kacho-principal-bin` (proto-serialized). Поля: `subject_type`
  (`user`/`service_account`/`federated_subject`), `subject_id`, `account_id`,
  `organization_id`, `groups`, `acr`, `amr`, `mfa_at`, `auth_time`, `source_ip`,
  `device_attestation` ∈ {`attested`, `partial`, `unknown`}, `dpop_jkt`, `break_glass_active`,
  `cluster_admin` (computed flag — true if FGA has tuple `cluster:cluster_kacho_root#any_admin@<subject>`; per DSL §4 `define any_admin: system_admin or emergency_admin` — covers BOTH permanent root grants (from `cluster_admin_grants` Phase 1 table) AND time-bounded emergency grants (from `cluster_break_glass_grants` Phase 1 table with `state="ACTIVE"` + `break_glass_window` condition holding). Computed at api-gateway during JWT-validation through a single FGA Check `any_admin@cluster:cluster_kacho_root#<subject>` with current Conditions context (so an emergency_admin tuple whose `break_glass_window` condition has expired evaluates to false in the same Check — no separate state lookup needed). Cached в Principal struct for the lifetime of the JWT (15min TTL); revocation via Phase 8 CAEP forces re-auth → fresh computation. OPA Rego rules (R1, R5, R6) read `principal.cluster_admin` as a single boolean, без distinguishing permanent vs emergency origin — both grant the same guardrail-exception privileges in Phase 3).

### 2.2 Сущности, **добавляемые** в Phase 3

- **OpenFGA Authorization Model v2** — DSL §4, опубликована через `openfga-bootstrap-job`.
  Хранится в FGA-engine'е (Postgres backend FGA-store). Идентифицируется `authorization_model_id`
  (UUID, выдаётся OpenFGA при `WriteAuthorizationModel`). Хранение `id` — **Kubernetes Secret**
  `openfga-model-id` (key=`current`, namespace=`kacho-system`); читается всеми kacho-* pod'ами
  через `KACHO_OPENFGA_MODEL_ID` env (Secret-ref в Deployment), pin'ится на каждый Check-вызов.
- **OPA bundle** — tarball, generated by `kacho-iam OpaBundleService.GetBundle` (Internal RPC):
  ```
  bundle.tar.gz
  ├── .manifest         (JSON: roots=["kacho/iam/guardrails"], revision=<git-sha>)
  ├── kacho/iam/guardrails/
  │   ├── deny_billing_destructive.rego
  │   ├── deny_sa_grant_user.rego
  │   ├── deny_org_scim_mismatch.rego
  │   ├── deny_break_glass_too_long.rego
  │   ├── deny_cross_tenant.rego
  │   └── deny_prod_out_of_hours.rego
  └── data/
      ├── organizations_users.json   (SCIM-set per org — generated from `scim_user_mappings` Phase 1)
      ├── timezones.json             (per-org tz / business-hours config — from `organizations` Phase 1)
      └── billing_projects.json      (project_id list with `billing_` prefix — derived от Project records)
  ```
  Bundle signed JWS (`alg=ES256`, `kid` из current `oidc_jwks_keys` row с `current=true`),
  signature attached как `bundle.tar.gz.sig` (detached JWS).
- **OPA sidecar** — `openpolicyagent/opa:1.0.x` container, injected per pod (api-gateway +
  kacho-iam + kacho-vpc + kacho-compute + kacho-loadbalancer). Configured to pull bundle
  `http://kacho-iam-internal:9091/opa/v1/bundle.tar.gz` каждые 1h, verify signature
  через public JWK (загружается из ConfigMap `kacho-iam-jwks`), evaluates Rego на
  `POST /v1/data/kacho/iam/guardrails/deny` per request.
- **corelib/authz/conditions_context.go** — новый файл, билдит OpenFGA `ContextualTupleKeys`
  + `Context` map[string]any из Principal-метадаты. Pattern:
  ```go
  func BuildConditionContext(p *Principal, now time.Time) map[string]any {
    return map[string]any{
      "acr_value":           p.ACR,
      "amr_claims":          p.AMR,
      "current_time":        now.Unix(),
      "mfa_at":              p.MFAAt.Unix(),
      "client_ip":           p.SourceIP.String(),
      "device_attestation":  p.DeviceAttestation,
    }
  }
  ```
- **OpaCheckMiddleware** — добавляется в per-service-interceptor (после FGA Check, до handler).
  Если FGA returns ALLOW → middleware вызывает локальный OPA sidecar
  `http://localhost:8181/v1/data/kacho/iam/guardrails/deny` с payload `{input: {action, principal, target, resource, duration_seconds?}}`. Если ответ `[]` (empty deny list) → allow; иначе → deny с
  `PermissionDenied: "policy: <первое msg>"`.

### 2.3 Per-pod sidecar topology (нормативно)

```
┌──────────── kacho-api-gateway pod ────────────┐
│  ┌───────────────┐    ┌──────────────────┐   │
│  │ api-gateway   │───▶│  OPA sidecar     │   │
│  │ (gRPC-proxy+  │    │  :8181 HTTP      │   │
│  │  REST)        │◀───│  policies bundle │   │
│  └───────────────┘    └────────┬─────────┘   │
│                                │              │
│                                ▼ pull 1h      │
└────────────────────────────────┼──────────────┘
                                 │
                                 ▼
                  http://kacho-iam-internal:9091
                         /opa/v1/bundle.tar.gz
                         (signed; ES256 — see §11 Q-bundle-url)
                                 ▲
                                 │ same flow
┌──────────── kacho-vpc pod ─────┼────────────┐
│  ┌─────────────┐    ┌──────────┴──────┐    │
│  │ kacho-vpc   │───▶│  OPA sidecar    │    │
│  │ (service)   │    │  :8181 HTTP     │    │
│  └─────────────┘◀───│  same bundle    │    │
│                     └─────────────────┘    │
└────────────────────────────────────────────┘
[same for kacho-compute, kacho-loadbalancer, kacho-iam itself]
```

OPA `:8181` exposed только **внутри пода** (no Service); один sidecar = один service-process.
api-gateway pod также имеет OPA sidecar (org-wide deny ДО роутинга на backend).

### 2.4 Authz pipeline (нормативно, по шагам)

Каждый external gRPC/REST request проходит:

1. **api-gateway** TLS termination, DPoP/mTLS validation (Phase 2), Principal extraction.
2. **api-gateway OPA sidecar** — org-wide deny (e.g., cross-tenant, break-glass duration limit).
   Empty deny → proceed; non-empty → return `PermissionDenied`.
3. **gRPC-proxy → backend service** (kacho-vpc / kacho-compute / etc.), with Principal в
   metadata `kacho-principal-bin`.
4. **backend per-service interceptor** (`corelib/authz/grpc.go`, E3 KAC-108 baseline,
   extended Phase 3):
   - **(a) Conditions context build** — `conditions_context.go` builds CEL-context map from
     Principal + `time.Now()`.
   - **(b) FGA Check** — `fgaClient.Check(ctx, &openfga.CheckRequest{ StoreID, AuthorizationModelID,
     TupleKey: {User: principal_id, Relation: permission, Object: resource}, Context: cel-context,
     ContextualTuples: nil })`. Cache hit (5s TTL, LISTEN-invalidated) → fast path. FGA returns
     `allowed=false` → backend returns `PermissionDenied: "<permission>: %v"`.
   - **(c) OPA Check** — sidecar `POST localhost:8181/v1/data/kacho/iam/guardrails/deny`
     с input. Non-empty list → backend returns `PermissionDenied: "policy: <msg>"`.
   - **(d) handler proceeds** — business logic (DB write etc.).

### 2.5 Cache invalidation contract (нормативно)

Same as E3 KAC-108 baseline (Phase 2.0). When `kacho-iam`:
- Upserts AccessBinding с `condition_id` → outbox-write → worker invokes FGA Write с
  Conditional tuple → worker NOTIFY `kacho_iam_subjects` payload `{subject_id: "usr_xxx"}`.
- Subscribers (`corelib/authz` Check-cache in each backend service) listening on
  `LISTEN kacho_iam_subjects` — receive payload → invalidate cache entry for that subject_id.
- p95 invalidation latency: ≤1s (E3 NFR-4).

---

## 3. Decision Log (P3-D1..D-20) — нормативно

| # | Решение | Обоснование | Альтернатива (отвергнута) |
|---|---|---|---|
| **P3-D1** | OpenFGA Authorization Model **versioned + immutable**: каждое изменение DSL → новый `authorization_model_id`, который пиннится при Check; никакого implicit "latest" | DSL change без version-pin → race между deploy и in-flight Check'ами; OpenFGA officially рекомендует pin (см. OpenFGA docs §Versioning) | Implicit-latest — отвергнут (race, no rollback) |
| **P3-D2** | `authorization_model_id` хранится в **Kubernetes Secret** `openfga-model-id` (namespace `kacho-system`, key=`current`); все kacho-* pod'ы читают через env `KACHO_OPENFGA_MODEL_ID` (Secret-ref) | Secret atomic-updatable (helm-upgrade обновляет stringData → all consumers re-mount при следующем rollout); ConfigMap тоже atomic, но Secret уже используется для FGA-store-id (E3 baseline) — переиспользуем | ConfigMap — отвергнут (нет audit-trail кто менял; Secret через kube-RBAC более restrictive) |
| **P3-D3** | OpenFGA Conditions — **stable API** (OpenFGA 1.5+); pre-validated на model write (FGA-engine отвергает invalid CEL syntax на `WriteAuthorizationModel`) | Это OpenFGA-stable feature (release-notes 1.5.x); CEL предкомпилируется FGA — нет runtime parse-overhead | Software CEL-engine на нашей стороне (cel-go) — отвергнут (duplication, FGA уже умеет; согласованность eval semantics) |
| **P3-D4** | Conditions context передаётся **per-request** через `Context` field в `CheckRequest` (НЕ через `ContextualTuples` для principal-атрибутов) | OpenFGA semantics: `Context` — это args для CEL-функций Condition; `ContextualTuples` — для override-tuples (например, "пользователь только что invite'нут — добавь tuple inline"). Разные роли; смешивать неправильно | Контекст как ContextualTuple — отвергнут (нарушает OpenFGA modeling semantics, ломает FGA-validation) |
| **P3-D5** | **7 предустановленных Conditions** (`mfa_fresh`, `non_expired`, `source_ip_in_range`, `break_glass_window`, `jit_window`, `business_hours`, `device_compliant`) — DSL §4 design; других в Phase 3 не вводим | KAC-127 scope зафиксирован design §4; future Conditions — отдельная phase под review (Phase 7 для PIM добавит вариации) | Generic-CEL без whitelist — отвергнут (security: tenant-controllable CEL == injection) |
| **P3-D6** | **OPA sidecar** model (per-pod), **НЕ centralized OPA cluster** | (1) latency: localhost <1ms vs cross-pod ~5-10ms; (2) blast-radius: один pod fail только себе; (3) deploy: helm chart per-service, без отдельного OPA cluster | Centralized OPA — отвергнут (extra HA infra, latency, cross-pod failure-mode сложнее) |
| **P3-D7** | OPA bundle pull mode (НЕ push) — `kacho-iam` exposes `/opa/v1/bundle.tar.gz`, OPA polls 1h TTL | (1) OPA stable feature (рекомендованный mode upstream); (2) idempotent — restart sidecar просто re-pulls; (3) signed bundle == integrity verified клиентом | Push (kacho-iam → OPA REST `PUT /v1/policies/...`) — отвергнут (state-sync race, no integrity check, harder to verify) |
| **P3-D8** | Bundle **signed via in-band JWS** (ES256, `kid` из `oidc_jwks_keys`), detached signature файл `bundle.tar.gz.sig` | (1) Нативно поддерживается OPA (`bundles[].signing.keyid`); (2) переиспользуем JWKS infra Phase 1/2; (3) cosign — overkill для текстовых bundle, JWS достаточно | cosign — отвергнут (image signing, не bundle signing; нет direct OPA integration); shared-secret HMAC — отвергнут (one-leak == all-leak; asymmetric лучше) |
| **P3-D9** | Bundle revision = git-SHA `kacho-iam` репо (commit, который deploy'нут); OPA проверяет `revision` field в `.manifest` — если == cache → skip reload | Cache-efficient; tamper-detection (cached revision не совпадает с подписью → reload + verify) | Timestamp-based — отвергнут (drift между pods → unpredictable cache hit rate) |
| **P3-D10** | Rego **v1 syntax** (`import rego.v1`) — OPA 1.0.x stable | Rego v1 = stable; v0 deprecated; design §4.1 уже использует `rego.v1` (`contains` syntax, `if`-keyword) | Rego v0 — отвергнут (deprecated, скоро removed) |
| **P3-D11** | Rego **unit-tests mandatory in CI** — `opa test policies/` blocks merge | Без тестов Rego-rule может silently отказать (typo, missing field в input — становится always-allow); CI-test catches regression | "Manual review достаточно" — отвергнут (rule regressions исторически проскакивают через review) |
| **P3-D12** | **Bundle data (organizations/timezones/billing_projects)** — генерируется `kacho-iam OpaBundleService.GetBundle` из БД (read-only) каждый bundle-request | (1) Always-current (eventual consistency ≤1h TTL); (2) NoCommit-required при изменении SCIM mapping; (3) data-driven Rego — pattern OPA upstream рекомендует | Static data в репо — отвергнут (stale при SCIM-changes; bundle pulled raw из git == drift) |
| **P3-D13** | corelib/authz `Check` extended с Conditions-context — **same interface signature** (backwards-compat с E3), новое поле через optional WithConditionsContext(p) helper | E3 callers не ломаются; новые callers opt-in через builder | Breaking signature change — отвергнут (multi-PR sync во всех сервисах одновременно) |
| **P3-D14** | corelib/authz **ListObjects skeleton** (`listobjects.go` — package skeleton + interface signature) кладётся в Phase 3, **Phase 4** integrates | Skeleton снимает с Phase 4 review-round trip для package-layout; концептуально близок к Check | Полная реализация в Phase 3 — отвергнут (раздувает scope; Phase 4 теряет smoke-эпик); deferred to Phase 4 entirely — отвергнут (forces extra PR round) |
| **P3-D15** | **Cache invalidation** — same E3 baseline (`kacho_iam_subjects` LISTEN/NOTIFY), Phase 3 НЕ меняет contract; condition_id-changes тоже инвалидируют per-subject (because condition change → effective ACL change) | E3 baseline уже работает; condition-change == ACL-change ⇒ same invalidation key (subject_id) | Per-binding cache key — отвергнут (E3 уже на subject-уровне; усложнение без пользы) |
| **P3-D16** | **Fail-closed mode**: при FGA-unavailable / OPA-unavailable все мутации denied; для read опционально fail-open за feature-flag `KACHO_AUTHZ_READ_FAIL_OPEN=false` (default) | Production-defaults safety; admin может временно выставить true для read-only emergencies (logged WARNING + Critical-alert) | Always fail-open для read — отвергнут (info-leak; design §17 Functional требует fail-closed default) |
| **P3-D17** | **`cluster:cluster_kacho_root` singleton** обрабатывается специально в DSL v2 (тип `cluster` ровно с одним object_id `cluster_kacho_root`); OpenFGA-engine не enforces "singleton", это enforced **на write-side** (kacho-iam admin-tools отказывают writing tuples с другим object_id) | OpenFGA DSL не имеет singleton-конструкции; enforcement в `kacho-iam` через precondition в outbox-worker (если tuple `cluster:X` с X≠cluster_kacho_root — log+drop+alert) | Multiple cluster-objects (per-region) — отвергнут (KAC-127 design = single global cluster root); future multi-region cluster — Phase 11 (отдельный design) |
| **P3-D18** | OPA `deny`-only rules (НЕ allow-rules) — request denied if any deny-rule matches; иначе → allow | OPA upstream рекомендация для guardrails (over-permissive default; allow-list реализован FGA-ом; OPA — overlay deny); проще mental-model | Allow + deny mix — отвергнут (logical inversion confusion; tests harder) |
| **P3-D19** | **Bundle revision endpoint** `GET /opa/v1/bundle/revision` (отдельный sync API) — для quick health-check без всего bundle | (1) Liveness for bundle-pipeline; (2) OPA проверяет revision-header `If-None-Match` → 304 без полного pull (HTTP caching) | Full bundle pull для каждого health-check — отвергнут (3-5KB overhead) |
| **P3-D20** | **bundle-server endpoint** регистрируется в api-gateway через `restmux.RegisterInternal()` (port 9091); НЕ через 9090 (public). DNS: `kacho-iam-internal.kacho-system.svc.cluster.local:9091` | Запрет #6: internal admin endpoints не на external TLS-listener; OPA sidecar — cluster-internal compo, доступ через internal listener | Через 9090 (public) — отвергнут (запрет #6) |

---

## 4. Target architecture (компактно)

### 4.1 ASCII edges (новые на Phase 3)

```
[client request via TLS edge]
        │
        ▼
[kacho-api-gateway pod]
   ├── DPoP/mTLS validation (Phase 2)
   ├── Principal extraction
   ├── ────► OPA sidecar :8181  ─── (org-wide deny? cross-tenant? break-glass?)
   │                              if non-empty deny → PermissionDenied
   └── gRPC-proxy ────► backend (kacho-vpc / kacho-compute / etc.)
                              │
                              ▼
                       [backend pod]
                       per-service interceptor (corelib/authz/grpc.go):
                         (1) BuildConditionContext(principal, now)
                         (2) fgaClient.Check(modelID=pinned, context=cel-ctx)
                                 ├── ALLOW → step (3)
                                 └── DENY → PermissionDenied: "<permission>"
                         (3) opaSidecar.POST /v1/data/kacho/iam/guardrails/deny
                                 ├── [] → step (4)
                                 └── non-empty → PermissionDenied: "policy: <msg>"
                         (4) handler.HandleX(...)
                                 ├── business logic
                                 └── optional: kacho-iam.AccessBinding.Upsert (transitive)
                                         │
                                         └── outbox → worker → FGA Write (Conditional tuple)
                                                              + NOTIFY kacho_iam_subjects
                                                                      │
                                                                      ▼
                                          (LISTEN'ing subscribers в backends invalidate Check-cache)

[OPA sidecars (all pods) poll каждые 1h]
        ▲
        │ GET http://kacho-iam-internal:9091/opa/v1/bundle.tar.gz
        │ verify JWS signature using ConfigMap kacho-iam-jwks
        │ (plain HTTP cluster-internal — Phase 2 parity; integrity via JWS, not TLS)
        │
[kacho-iam] OpaBundleService.GetBundle (Internal RPC, port 9091)
   ├── reads policies/*.rego (embed.FS)
   ├── builds data/*.json (organizations_users, timezones, billing_projects from DB read-only)
   ├── tarball + sign JWS using current oidc_jwks_keys row (alg=ES256)
   └── returns tar.gz + detached .sig

[openfga-bootstrap-job — helm post-install / upgrade]
        │
        ▼
[OpenFGA engine]
   ├── WriteAuthorizationModel(dsl="<full DSL §4>") → returns new model_id
   ├── if existing Secret openfga-model-id.current already == new model_id (hash-compare DSL)
   │    → skip-write (idempotent)
   └── else → kubectl patch Secret openfga-model-id stringData.current=<new model_id>
              → rolling restart of api-gateway + all backends (helm hook annotation)
```

### 4.2 Что добавляется в каждый репо

| Репо | Файлы (новые / изменённые) |
|---|---|
| `kacho-proto/proto/kacho/cloud/iam/v1` | `access_binding.proto` — расширение `UpsertAccessBindingRequest` (добавить `string condition_id = 7;`, `google.protobuf.Timestamp expires_at = 8;`); `opa_bundle.proto` (новый, Internal service) — `service OpaBundleService { rpc GetBundle(GetBundleRequest) returns (BundleResponse); rpc GetRevision(GetRevisionRequest) returns (RevisionResponse); }`. Регенерация `gen/go/`. `buf lint` + `buf breaking` зелёные |
| `kacho-corelib/authz` | `conditions_context.go` — `BuildConditionContext(*Principal, time.Time) map[string]any` + tests; `check.go` — расширение `Check` с принятием `ConditionContext map[string]any` (optional, builder-pattern); `listobjects.go` — **skeleton-only** (package + ListObjectsClient interface + struct) для Phase 4. Integration test: openfga testcontainer + Conditional tuple write + Check с/без context → assertion |
| `kacho-iam/internal/apps/kacho/api/access_binding/upsert.go` | Принимает `condition_id` + `expires_at`; if `condition_id` not empty → fetch from `access_binding_conditions`, embed predicate-name + params в outbox payload; worker (existing E3 worker) дополняется: при writing FGA tuple — Conditional-form `{user, relation, object, condition: {name: "<predicate>", context: <params>}}` |
| `kacho-iam/internal/apps/kacho/api/opa/{bundle,sign_bundle,revision}.go` | New: `OpaBundleService.GetBundle` (Internal RPC) — embed.FS read + data-section build (from `scim_user_mappings` / `organizations` / `projects` tables) + JWS-sign using `oidc_jwks_keys.current` → returns `tar.gz + sig`. `OpaBundleService.GetRevision` — quick git-sha lookup (env `KACHO_BUILD_SHA`). `sign_bundle.go` — helper wrapping JOSE-go ES256 |
| `kacho-iam/policies/` | New folder: `deny_billing_destructive.rego`, `deny_sa_grant_user.rego`, `deny_org_scim_mismatch.rego`, `deny_break_glass_too_long.rego`, `deny_cross_tenant.rego`, `deny_prod_out_of_hours.rego` + per-file `_test.rego` (positive + negative cases) |
| `kacho-deploy/helm/umbrella/templates` | `openfga-model-stub-configmap.yaml` — replace stub-DSL на full DSL §4 (commit-ed inline as ConfigMap data); `openfga-bootstrap-job.yaml` — idempotent (hash-compare); `opa-sidecar-configmap.yaml` — OPA config (bundle endpoint URL, signing-key JWK); `opa-bundle-server-configmap.yaml` — kacho-iam runtime config (bundle revision = `Values.global.gitSha`). Sidecar injection — `charts/kacho-{api-gateway,iam,vpc,compute,loadbalancer}/templates/deployment.yaml` (`spec.template.spec.containers` += OPA container) |
| `kacho-workspace/obsidian/kacho/KAC/KAC-127.md` | Update `Затронутые сущности vault` + acceptance-checklist progress |
| `kacho-workspace/obsidian/kacho/architecture/authz-pipeline.md` | New: full authz pipeline ASCII + Conditions list + OPA Deny list (≤3KB) |
| `kacho-workspace/obsidian/kacho/rpc/iam-opa-bundle.md` | New: OpaBundleService RPC contract (internal, port 9091, bundle.tar.gz format) |
| `kacho-workspace/obsidian/kacho/edges/*-to-iam-opa-bundle-pull.md` | New: edge `<api-gateway|vpc|compute|lb|iam>-to-iam-opa-bundle-pull` — describes pull pattern, 1h TTL, signing |

### 4.3 Cross-repo runtime edges (новые на Phase 3)

| Caller | Callee | Purpose | Direction | Sync/async |
|---|---|---|---|---|
| OPA sidecar (every pod) | `kacho-iam` Internal `OpaBundleService.GetBundle` | bundle pull (signed, 1h TTL) | external → kacho-iam | sync HTTP GET |
| backend per-service interceptor | localhost OPA `:8181` | post-FGA guardrails check | intra-pod | sync HTTP POST |
| kacho-iam outbox-worker | OpenFGA `:8080` | Conditional tuple write | kacho-iam → fga | sync gRPC |
| backend per-service interceptor | OpenFGA `:8080` | Check (with Context = Conditions map) | service → fga | sync gRPC (cached 5s) |

Циклы — нет. fga и opa — leaf-engines (никто не зовёт обратно сервисы).

### 4.4 Latency budget (per-RPC authz, NFR-2 ≤30ms p95 in design §2 + §7)

- FGA Check (cache hit): ≤1ms
- FGA Check (cache miss): ≤10ms (intra-cluster gRPC, FGA P95 from upstream benchmarks)
- Conditions context build: ≤0.1ms (pure CPU map-build)
- OPA local sidecar: ≤2ms (localhost HTTP + Rego eval; OPA-upstream benchmarks ~1ms median)
- Network principal-extraction: ≤2ms (Phase 2 baseline)
- **Total budget**: ≤15ms p95 (cache miss), ≤5ms p95 (cache hit). Margin to NFR-2 (30ms) = 50%.

### 4.5 Conditions definitions (DSL §4 frozen — нормативно)

```cel
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

### 4.6 OPA Rego deny rules (design §4.1 frozen — нормативно)

| # | Rule | Source ref |
|---|---|---|
| **R1** | Deny: destructive ops (`projects.delete`, `accounts.delete`) on `prj_billing_*` projects unless `principal.cluster_admin` | design §4.1 #1 |
| **R2** | Deny: SA cannot grant role to user (escalation prevention) — action `access_bindings.upsert` + principal.type=`service_account` + target.subject_type=`user` | design §4.1 #2 |
| **R3** | Deny: granting org-wide role to user not in `organization` SCIM-set (`access_bindings.upsert` + resource_type=`organization` + `not user_in_organization(...)`) | design §4.1 #3 |
| **R4** | Deny: break-glass duration > 2h — action `cluster.break_glass.grant` + `duration_seconds > 7200` | design §4.1 #4 |
| **R5** | Deny: cross-tenant resource access — `principal.type=user` + `not principal_in_resource_account(...)` + `not cluster_admin` | design §4.1 #5 |
| **R6** | Deny: prod-project destructive (`vpc.networks.delete`, `compute.instances.delete`) outside business hours unless break-glass — `resource.project_id` ends `_prod` + `not within_business_hours(tz)` + `not break_glass_active` | design §4.1 #6 |

---

## 5. Декомпозиция по компонентам (что именно реализуется)

### 5.1 OpenFGA Authorization Model v2 deploy (`kacho-deploy`)

- Replace `kacho-deploy/helm/umbrella/templates/openfga-model-stub-configmap.yaml` data block с full DSL §4 (copy verbatim из design doc, БЕЗ comments — OpenFGA позволяет comments, но parsing safer без них; comments — в адm `kacho-deploy/docs/openfga-model-v2.md` rationale).
- `openfga-bootstrap-job.yaml` (extend E3 KAC-108 baseline):
  - **Idempotency**: job container shell-script:
    ```
    1. Read ConfigMap openfga-model.dsl
    2. POST {fga}:8080/stores/{storeID}/authorization-models/translate {dsl: ...} → get model_id_candidate
    3. Read Secret openfga-model-id.current
    4. IF candidate == current AND (re-fetch model body) == current_body → skip+exit-0
    5. ELSE → POST {fga}:8080/stores/{storeID}/authorization-models {schema:..., type_definitions:..., conditions:...} → new model_id
    6. kubectl patch Secret openfga-model-id stringData.current=<new model_id>
    7. annotate rolling-restart kacho-api-gateway + kacho-iam + kacho-vpc + kacho-compute + kacho-loadbalancer
    ```
  - Job uses `helm.sh/hook: post-install,post-upgrade` (re-runs on every helm-upgrade — but idempotent).
  - On rollback (helm rollback) — job re-runs с old DSL → no-op if same model already current; FGA engine retains old model_id (immutable, never deletes), so rollback is safe.

### 5.2 `corelib/authz` — Conditions context builder + extension

- New file `kacho-corelib/authz/conditions_context.go`:
  ```go
  // BuildConditionContext extracts CEL-runtime args from Principal + current time.
  // Result is passed to OpenFGA Check.Request.Context.
  func BuildConditionContext(p *Principal, now time.Time) map[string]any { ... }
  ```
- Extension `kacho-corelib/authz/check.go`:
  - Existing `Check(ctx, permission, object string) (allowed bool, err error)` — kept (backward-compat).
  - New `CheckWithContext(ctx, permission, object string, condCtx map[string]any) (allowed bool, err error)`.
  - Default per-service interceptor (`grpc.go`) now uses `CheckWithContext` (auto-builds context from gRPC-metadata Principal).
- New file `kacho-corelib/authz/listobjects.go` — **skeleton** (Phase 4 fills):
  ```go
  type ListObjectsClient interface {
    ListObjects(ctx context.Context, principal *Principal, relation, objectType string) ([]string, error)
  }
  // Phase 4 will: pluggable per-handler integration, cache, NOTIFY-invalidation.
  ```
  Skeleton has _test.go with `TestSkeleton_InterfaceCompiles` only — no implementation in Phase 3.
- Integration test (`corelib/authz/check_integration_test.go`):
  - Spin up `openfga/openfga:1.6.x` testcontainer
  - WriteAuthorizationModel с reduced DSL (`compute_instance` type + `ssh` relation + `mfa_fresh` condition)
  - Write tuple `user:alice#ssh@compute_instance:vm1` Conditional `mfa_fresh`
  - Check (acr=3, amr=webauthn, mfa_at=now) → allowed
  - Check (acr=2, amr=webauthn, mfa_at=now) → denied
  - Check (acr=3, amr=password, mfa_at=now) → denied (no webauthn)
  - Check (acr=3, amr=webauthn, mfa_at=now-20min) → denied (>15min)

### 5.3 `kacho-iam` — `AccessBindingService.Upsert` extension

- Existing handler (`upsert.go`, KAC-108 E3 + KAC-121 yc-style-roles + KAC-125 invites):
  - Принимает `subject_id`, `role_id`, `resource_id` + новые **`condition_id` (optional)**, **`expires_at` (optional)**.
- New logic (delta):
  1. Validate `condition_id` (if set) — `SELECT predicate_name, params FROM access_binding_conditions WHERE id=$1`. Not-found → InvalidArgument.
  2. Validate `expires_at` (if set) — must be > now() + 5min; not in past. InvalidArgument otherwise.
  3. Write `access_bindings` row (transactional) с `condition_id`, `expires_at`. Same outbox-write existing.
  4. Outbox payload extended: include `condition_predicate_name`, `condition_params` (JSONB inline) — worker uses this for FGA-Write.
  5. Worker (`fga_outbox_worker`) updated: при writing tuple — if `condition_predicate_name` not empty, FGA-tuple form:
     ```
     {
       user: "user:usr_alice", relation: "vpc_admin", object: "vpc_network:vpcn_xxx",
       condition: { name: "mfa_fresh", context: {} }
     }
     ```
     If `condition_params` non-empty (e.g., `source_ip_in_range` has params) → embedded in tuple `condition.context.allowed_cidrs`.
- Test (`upsert_integration_test.go`):
  - Insert AccessBindingCondition row `mfa_fresh` (no params).
  - Call Upsert с condition_id.
  - Wait for outbox-worker (≤2s).
  - Query FGA `Read` API → assert tuple has `condition.name == "mfa_fresh"`.
  - Concurrent test: 5 goroutines call Upsert same binding с разными condition_id → one wins (last write — CAS-via-conditional-UPDATE на `access_bindings` already in Phase 1).

### 5.4 `kacho-iam` — `OpaBundleService` (Internal RPC)

- New proto `kacho-proto/proto/kacho/cloud/iam/v1/opa_bundle.proto` (Internal service):
  ```protobuf
  service OpaBundleService {
    // Returns the bundle tarball only (no inline signature) at the OPA-standard
    // resource path. Signature must be fetched separately via GetBundleSignature.
    rpc GetBundle(GetBundleRequest) returns (BundleResponse) {
      option (google.api.http) = { get: "/opa/v1/bundle.tar.gz" };
    }
    // Returns the detached JWS signature for the current bundle revision at the
    // OPA-standard ".sig" sibling path. OPA discovers it through the bundle
    // service config `bundles.<name>.signing.keyid` + the implicit `.sig`
    // suffix convention (OPA upstream — see "Bundle Signing" docs, signed-bundle
    // delivery mode: separate-file detached signature, NOT RFC 8493 in-tarball).
    rpc GetBundleSignature(GetBundleSignatureRequest) returns (BundleSignatureResponse) {
      option (google.api.http) = { get: "/opa/v1/bundle.tar.gz.sig" };
    }
    rpc GetRevision(GetRevisionRequest) returns (RevisionResponse) {
      option (google.api.http) = { get: "/opa/v1/bundle/revision" };
    }
  }
  message GetBundleRequest {}
  message BundleResponse {
    bytes bundle_tar_gz = 1;   // tar.gz binary (NO inline signature; fetch .sig separately)
    string revision = 2;       // git-sha (also as HTTP `ETag` header for 304-cache)
  }
  message GetBundleSignatureRequest {}
  message BundleSignatureResponse {
    // Detached JWS (Compact Serialization, ES256). Payload is sha256 of the
    // matching bundle.tar.gz; OPA recomputes the digest after download and
    // verifies signature against the JWK identified by `kid` in JWS header.
    string signature_jws = 1;
    string revision = 2;       // must match revision of the bundle this signs (consistency check)
  }
  message GetRevisionRequest {}
  message RevisionResponse {
    string revision = 1;       // current build git-sha
  }
  ```
  **Delivery mode (нормативно)**: OPA-standard **detached separate-file signature** — bundle is served as plain `bundle.tar.gz` and signature is served as `bundle.tar.gz.sig` at the sibling URL path. This matches OPA upstream signed-bundle config `bundles.<name>.signing.keyid` semantics (OPA polls `<resource>` then `<resource>.sig`). **NOT** RFC 8493 / in-tarball `.signatures.json` — that mode requires repacking the bundle around the signature and is harder to debug. Separate-file mode keeps tarball byte-identical to the unsigned build artifact and allows revision-rollback by serving an older `.sig` without rebuilding the bundle. Body of JWS payload = `{ "files": [{"name":"bundle.tar.gz","hash":"<sha256-hex>","algorithm":"SHA-256"}], "revision": "<git-sha>" }` per OPA spec.
- Registration: **api-gateway internal mux only** (запрет #6); `restmux.RegisterInternal()` calls.
- Implementation `kacho-iam/internal/apps/kacho/api/opa/bundle.go`:
  - reads `policies/` from `embed.FS`
  - queries DB (read-only): `SELECT organization_id, scim_external_id, user_id FROM scim_user_mappings` → `data/organizations_users.json`; `SELECT id, timezone, business_hours_start, business_hours_end FROM organizations` → `data/timezones.json`; `SELECT id FROM projects WHERE name LIKE 'billing_%'` → `data/billing_projects.json`.
  - builds tar.gz in-memory (`archive/tar` + `compress/gzip` stdlib).
  - signs via JOSE (`gopkg.in/go-jose/go-jose.v2`) using current `oidc_jwks_keys.private_key_pem_encrypted` (decrypt with KMS-key, Phase 2 already plumbed).
  - returns BundleResponse.
- Test `bundle_integration_test.go`:
  - testcontainer Postgres + seed test data
  - GetBundle → verify tarball structure (`.manifest` exists, all 6 .rego files, `data/*.json`)
  - Verify JWS signature using ConfigMap-style JWK
  - Tamper bytes → signature fails

### 5.5 `kacho-iam/policies/` — Rego + tests

- `deny_billing_destructive.rego` (R1):
  ```rego
  package kacho.iam.guardrails
  import rego.v1

  deny contains msg if {
    input.action in {"projects.delete", "accounts.delete"}
    startswith(input.resource.id, "prj_billing_")
    not input.principal.cluster_admin
    msg := sprintf("destructive op on billing project requires cluster-admin (got %v)", [input.principal.id])
  }
  ```
  Test `deny_billing_destructive_test.rego`:
  ```rego
  package kacho.iam.guardrails_test
  import data.kacho.iam.guardrails

  test_deny_billing_project_delete_non_admin if {
    guardrails.deny["destructive op on billing project requires cluster-admin (got usr_bob)"] with input as {
      "action": "projects.delete",
      "resource": {"id": "prj_billing_acme"},
      "principal": {"id": "usr_bob", "cluster_admin": false}
    }
  }
  test_allow_billing_project_delete_cluster_admin if {
    count(guardrails.deny) == 0 with input as {
      "action": "projects.delete",
      "resource": {"id": "prj_billing_acme"},
      "principal": {"id": "usr_alice", "cluster_admin": true}
    }
  }
  test_allow_non_billing_project_delete if {
    count(guardrails.deny) == 0 with input as {
      "action": "projects.delete",
      "resource": {"id": "prj_app_acme"},
      "principal": {"id": "usr_bob", "cluster_admin": false}
    }
  }
  ```
- Same pattern for R2..R6 (6 rules × 3 tests minimum each = 18 unit tests).
- CI step: `opa test policies/ -v` — exit-nonzero → CI fail.

### 5.6 OPA sidecar deploy (`kacho-deploy`)

- `opa-sidecar-configmap.yaml` — OPA config:
  ```yaml
  services:
    kacho-iam:
      url: http://kacho-iam-internal.kacho-system.svc.cluster.local:9091/opa/v1
      response_header_timeout_seconds: 5
  bundles:
    kacho-iam-guardrails:
      service: kacho-iam
      resource: bundle.tar.gz
      polling:
        min_delay_seconds: 3000   # ~50min (with jitter → ~1h)
        max_delay_seconds: 3900
      signing:
        keyid: kacho-iam-signing-key-current
        scope: write
  keys:
    kacho-iam-signing-key-current:
      algorithm: ES256
      key: <PEM>   # from ConfigMap kacho-iam-jwks (mounted)
  decision_logs:
    console: true
  ```
- `opa-bundle-server-configmap.yaml` — for `kacho-iam` runtime: `KACHO_BUILD_SHA`, `KACHO_OPA_BUNDLE_TTL_SECONDS=3600`, `KACHO_OPA_SIGNING_KEY_KID=<jwks-current-kid>`.
- Sidecar injection в `charts/kacho-{api-gateway,iam,vpc,compute,loadbalancer}/templates/deployment.yaml`:
  ```yaml
  containers:
    - name: <existing>
      ...
    - name: opa
      image: openpolicyagent/opa:1.0.x
      args:
        - run
        - --server
        - --addr=localhost:8181
        - --config-file=/config/config.yaml
        - --log-level=info
      volumeMounts:
        - name: opa-config
          mountPath: /config
        - name: kacho-iam-jwks
          mountPath: /jwks
      readinessProbe:
        httpGet:
          path: /health?bundles=true
          port: 8181
        periodSeconds: 5
      resources:
        limits:
          memory: 256Mi
          cpu: 100m
        requests:
          memory: 64Mi
          cpu: 20m
  volumes:
    - name: opa-config
      configMap:
        name: opa-sidecar
    - name: kacho-iam-jwks
      configMap:
        name: kacho-iam-jwks
  ```

### 5.7 Fail-modes (нормативно)

| Failure | Behaviour | Verified by scenario |
|---|---|---|
| FGA-engine unreachable | All Check fail-closed → return `PermissionDenied: "authz unavailable"`; metric `corelib_authz_fail_closed_total{component="fga"}` incremented; alert fires at >0 in 5min | §6.15 |
| OPA sidecar `:8181` unreachable / non-200 | If sidecar liveness=down: fail-closed for **mutations**; for **read** ops — fail-open ONLY IF `KACHO_AUTHZ_READ_FAIL_OPEN=true` env-flag is set (default `false`) + log WARN + metric `corelib_authz_fail_open_total{op="read"}` increment + alert | §6.15 |
| Bundle signature verification fails | OPA refuses to load bundle, retains last known good bundle; metric `opa_bundle_signature_failures_total` increment; alert Critical | §6.11 |
| Bundle missing detached signature | OPA refuses to load (require_signature=true); alert | §6.11 |
| FGA returns model_id-not-found (rare — Secret out of sync) | Backend interceptor returns `Internal: "authz misconfigured"` (no fail-open); metric increment + Critical alert; admin runbook = re-run `openfga-bootstrap-job` | §6.1 |
| Condition CEL eval throws (e.g., source_ip not parseable) | OpenFGA returns Check error → caller treats as fail-closed deny; log includes condition-name + sanitized-input (no PII) | §6.6 |
| ListObjects called (Phase 3 skeleton) | Returns `Unimplemented: "ListObjects integrated in Phase 4"`; metric `corelib_authz_listobjects_called_total` — для baseline | not in Phase 3 scope; placeholder check |

---

## 6. GWT-сценарии (57 scenarios — ≥40 mandated; v2 added P3.GWT-15a/15b for console relation)

> **Convention**: каждый scenario имеет ID, **Given/When/Then**, и cross-ссылку на Decision Log
> и `acceptance-reviewer` использует это для coverage-matrix.

### 6.1 OpenFGA Authorization Model v2 deploy (4 scenarios — D-1, D-2)

#### Scenario P3.GWT-01: helm install с full DSL v2 → store + model_id created + Secret patched

**Given** clean `kacho-deploy` umbrella install (no prior FGA store).
**And** ConfigMap `openfga-model.dsl` contains DSL §4 (cluster + organization + account + project + per-service types + 7 conditions).
**And** Secret `openfga-model-id` does NOT exist.

**When** operator runs `helm install kacho ./helm/umbrella -n kacho-system`.

**Then** `openfga-bootstrap-job` Pod runs to completion (exit 0) ≤120s.
**And** OpenFGA `GET /stores` returns 1 store (`kacho-prod`).
**And** OpenFGA `GET /stores/<id>/authorization-models` returns ≥1 model.
**And** Secret `openfga-model-id` exists с key `current` containing 16-char ULID-like model id.
**And** `WriteAuthorizationModel` body contains все 6 type-definitions (cluster, organization, account, project, vpc_*, compute_*, lb_*) и 7 condition-definitions.
**And** annotation `kacho-deploy/last-applied-dsl-sha256` on Secret matches sha256(ConfigMap).

#### Scenario P3.GWT-02: helm upgrade с unchanged DSL → idempotent (skip-write)

**Given** scenario P3.GWT-01 already executed, Secret `openfga-model-id.current = M1`.

**When** operator runs `helm upgrade kacho ./helm/umbrella -n kacho-system` (no changes к ConfigMap).

**Then** `openfga-bootstrap-job` Pod runs to completion (exit 0) ≤30s.
**And** OpenFGA store retains same `M1` (no new model written).
**And** Job logs contain `"DSL sha256 matches Secret annotation → skip-write"`.
**And** Secret `openfga-model-id.current` unchanged (`== M1`).
**And** No rolling restart of api-gateway / backends.

#### Scenario P3.GWT-03: helm upgrade с modified DSL → new model_id + Secret update + rolling restart

**Given** scenario P3.GWT-01 executed, Secret current=`M1`.
**And** DSL ConfigMap edited (e.g., new relation `vpc_network.archiver`).

**When** operator runs `helm upgrade kacho ./helm/umbrella`.

**Then** job runs ≤90s, exits 0.
**And** OpenFGA `GET /stores/<id>/authorization-models` returns 2 models (`M1`, `M2`).
**And** Secret `openfga-model-id.current` = `M2`.
**And** Within 90s rolling-restart of all kacho-* Deployments completes (each Pod sees new env via Secret-ref + remount).
**And** Newly-started backend Pods log `"openfga model id pinned: M2"`.
**And** Any in-flight Check during transition either uses M1 (old pod) or M2 (new pod) — no Check fails (both models valid в FGA engine; immutable).

#### Scenario P3.GWT-04: helm rollback after upgrade → safe (no Check disruption)

**Given** scenario P3.GWT-03 executed, current=`M2`, models in FGA: M1 + M2.

**When** operator runs `helm rollback kacho 1` (rolls back к chart с DSL v1).

**Then** `openfga-bootstrap-job` re-runs.
**And** Job detects: ConfigMap DSL sha == Secret.annotation `last-applied-dsl-sha256 == M1`-сha → fast-path; Secret patches `current=M1`.
**And** FGA engine retains both M1+M2 (immutable, never deletes).
**And** Rolling restart pins back `M1` в all backends.
**And** No tuples lost (tuples are model-independent в storage layer — FGA Postgres-backed).

### 6.2 cluster:singleton tuples (4 scenarios — D-17)

#### Scenario P3.GWT-05: ClusterAdminGrant.Create → cluster:cluster_kacho_root#system_admin@user:X tuple

**Given** model v2 deployed (P3.GWT-01); Phase 1 `cluster_admin_grants` table empty.
**And** user `usr_alice_root` (registered via Phase 2 OIDC).
**And** `kacho-iam` admin tooling вызывает Internal RPC `ClusterAdminGrantService.Upsert` (Phase 1 schema exists; RPC handler — Phase 3 implementation).

**When** Upsert(`subject_id="usr_alice_root"`, `granted_by="usr_bootstrap"`).

**Then** Operation returns done=true ≤500ms (sync handler since FGA-write is fast).
**And** Row in `cluster_admin_grants` created.
**And** `fga_outbox` row queued; worker picks up ≤2s.
**And** FGA tuple `cluster:cluster_kacho_root#system_admin@user:usr_alice_root` written (verifiable via `Read` API).
**And** NOTIFY `kacho_iam_subjects` payload `{"subject_id":"usr_alice_root"}` fired — subject-cache invalidated в all backends.

#### Scenario P3.GWT-06: cluster_admin computed-cascade — system_admin → admin@any account

**Given** P3.GWT-05 executed (alice = cluster system_admin).
**And** Account `acc_unrelated` exists (alice не member acc_unrelated).
**And** VPC Network `vpcn_test` exists в Project `prj_xx` ∈ acc_unrelated.

**When** alice issues `vpc.networks.list` for `acc_unrelated` projects (через api-gateway, valid DPoP-bound JWT).

**Then** api-gateway OPA sidecar: no deny rule matches (alice has cluster_admin → R5 cross-tenant deny does NOT fire).
**And** kacho-vpc per-service interceptor: FGA Check `vpc_admin@vpc_network:vpcn_test#user:usr_alice_root` returns ALLOWED (computed via `account.admin from organization` cascade up to `cluster.system_admin`).
**And** Response 200 OK с list of vpc networks visible.

#### Scenario P3.GWT-07: ClusterBreakGlassGrant flow — singleton emergency tuple с break_glass_window condition

**Given** scenario P3.GWT-05 executed; alice = system_admin.
**And** Phase 1 `cluster_break_glass_grants` table empty.
**And** Phase 7 RPC not yet implemented, but Phase 3 schema-level write через `kacho-iam-cli` admin tool: row inserted with `subject_id="usr_bob"`, `state="ACTIVE"`, `expires_at=now()+30min`, `condition_id=<break_glass_window_cond_id>`.

**When** outbox-worker writes FGA tuple.

**Then** FGA tuple Conditional-form written: `cluster:cluster_kacho_root#emergency_admin@user:usr_bob[break_glass_window]` (params: `expires_at`).
**And** Check `system_admin@cluster:cluster_kacho_root#user:usr_bob` (with current_time = now+15min, expires_at = now+30min) → ALLOWED (via `any_admin = system_admin or emergency_admin`, and condition holds).
**And** Same Check (with current_time = now+45min) → DENIED (condition `current_time < expires_at` fails).

#### Scenario P3.GWT-08: write tuple `cluster:<wrong_id>` → kacho-iam outbox-worker rejects

**Given** model v2 deployed.
**And** Buggy admin tool tries to enqueue outbox row with `object_id = "cluster:foobar"` (not `cluster_kacho_root`).

**When** outbox-worker picks up the row.

**Then** Worker validates `object_type == "cluster" ⇒ object_id == "cluster_kacho_root"` (D-17 enforcement).
**And** Outbox row marked `status="failed_terminal"`, error=`"cluster singleton violation: expected cluster_kacho_root, got foobar"`.
**And** No FGA write attempted.
**And** Metric `kacho_iam_outbox_singleton_violations_total{object_type="cluster"}` incremented.
**And** Alert Critical fires within 1min.

### 6.3 organization tier tuples (3 scenarios — design §4 organization-type)

#### Scenario P3.GWT-09: AccessBinding (User, organization.admin, Organization) → org-level cascade

**Given** organization `org_acme` exists (Phase 1 row).
**And** Account `acc_engineering` exists, `account.organization_id=org_acme`.
**And** Project `prj_engineering_app` ∈ acc_engineering.
**And** User `usr_charlie`.
**And** Role `org.admin` (system, scope=organization, permission=`*`).

**When** Upsert AccessBinding(subject=usr_charlie, role=org.admin, resource=organization:org_acme, condition_id=null).

**Then** FGA tuple `organization:org_acme#admin@user:usr_charlie` written ≤2s.
**And** Check `editor@account:acc_engineering#user:usr_charlie` → ALLOWED (cascade `or admin from organization`).
**And** Check `editor@project:prj_engineering_app#user:usr_charlie` → ALLOWED (cascade `or editor from account or admin from organization`).
**And** Check `editor@account:acc_unrelated#user:usr_charlie` (where acc_unrelated has different organization) → DENIED.

#### Scenario P3.GWT-10: organization.billing_admin separate relation — не cascade на other admin actions

**Given** scenario P3.GWT-09 baseline.
**And** Role `org.billing_admin` (system, permission=`billing.*`).
**And** User `usr_finance`.

**When** Upsert AccessBinding(subject=usr_finance, role=org.billing_admin, resource=organization:org_acme).

**Then** FGA tuple `organization:org_acme#billing_admin@user:usr_finance` written.
**And** Check `billing_admin@account:acc_engineering#user:usr_finance` → ALLOWED (cascade `or billing_admin from organization`).
**And** Check `admin@account:acc_engineering#user:usr_finance` → DENIED (billing_admin не cascade'ит в admin; DSL §4 `define admin: [users] or any_admin from cluster or admin from organization or owner` — billing_admin не in chain).

#### Scenario P3.GWT-11: cross-org isolation — admin on org_acme не имеет access к org_other

**Given** scenarios P3.GWT-09 baseline.
**And** Organization `org_other` exists.
**And** Account `acc_other`, `account.organization_id=org_other`.

**When** Check `editor@account:acc_other#user:usr_charlie` (charlie был granted org_acme admin).

**Then** ALLOWED check → false (no cascade-path; cross-org isolation enforced by DSL).
**And** Plus: api-gateway OPA sidecar fires deny rule R5 (cross-tenant) — Belt-and-suspenders defense.

### 6.4 Conditions — mfa_fresh (6 scenarios — D-5)

#### Scenario P3.GWT-12: mfa_fresh allows when acr=3, amr contains webauthn, mfa_at recent

**Given** model v2 deployed.
**And** AccessBindingCondition row `cond_mfa_fresh` (predicate_name=`mfa_fresh`, params={}).
**And** AccessBinding(user=usr_alice, role=compute.ssh_user, resource=compute_instance:vm1, condition_id=cond_mfa_fresh).
**And** FGA tuple `compute_instance:vm1#ssh@user:usr_alice[mfa_fresh]` written.

**When** usr_alice вызывает gRPC `kacho.compute.v1.InstanceService.Ssh(vm1)` с DPoP-bound JWT (`acr=3`, `amr=["webauthn"]`, `ext_claims.kacho_mfa_at=<now-5min>`).

**Then** kacho-compute per-service interceptor builds context `{acr_value="3", amr_claims=["webauthn"], current_time=<now>, mfa_at=<now-5min>, ...}`.
**And** FGA Check returns ALLOWED.
**And** OPA Check returns empty deny list.
**And** Handler proceeds, RPC returns 200.

#### Scenario P3.GWT-13: mfa_fresh denies when acr=2 (no step-up)

**Given** scenario P3.GWT-12 baseline (same binding с condition).

**When** usr_alice вызывает `Ssh(vm1)` с DPoP-bound JWT (`acr=2`, `amr=["webauthn"]`, `mfa_at=<now-5min>`).

**Then** Context built `{acr_value="2", ...}`.
**And** FGA Check returns DENIED (`acr_value == "3"` fails в condition CEL).
**And** Backend returns `PermissionDenied: "compute.ssh"`.
**And** Metric `corelib_authz_denied_total{permission="compute.ssh", reason="condition"}` incremented.

#### Scenario P3.GWT-14: mfa_fresh denies when amr missing webauthn

**Given** scenario P3.GWT-12 baseline.

**When** usr_alice вызывает `Ssh(vm1)` с JWT (`acr=3`, `amr=["password","totp"]`, `mfa_at=<now-5min>`).

**Then** Context `{amr_claims=["password","totp"], ...}`.
**And** FGA Check returns DENIED (`"webauthn" in amr_claims` fails).
**And** Backend returns `PermissionDenied`.

#### Scenario P3.GWT-15: mfa_fresh denies when mfa_at > 15min old

**Given** scenario P3.GWT-12 baseline.

**When** usr_alice вызывает `Ssh(vm1)` с JWT (`acr=3`, `amr=["webauthn"]`, `mfa_at=<now-20min>`).

**Then** Context `{mfa_at=<now-20min>, current_time=<now>}`.
**And** FGA Check returns DENIED (`current_time - mfa_at < duration("15m")` fails: 20min > 15min).
**And** Backend returns `PermissionDenied`.
**And** Client receives error → may trigger step-up flow (Phase 2 baseline — re-authenticate WebAuthn → new mfa_at → retry succeeds).

#### Scenario P3.GWT-15a: console relation — ServiceAccount with compute.admin → ALLOWED; without admin → DENIED

**Given** model v2 deployed (DSL §4: `define console: [user with mfa_fresh] or admin` on `compute_instance`).
**And** ServiceAccount `sva_ci_bot` (Phase 2 — client_credentials grant, JWT has `kacho_principal_type="service_account"`; `amr` does NOT contain `webauthn` — WebAuthn is impossible for SA principals by design).
**And** Compute instance `vm1` in project `prj_app_dev`.
**And** AccessBinding(subject=`sva_ci_bot`, role=`compute.admin`, resource=`compute_instance:vm1`) — gives SA the `admin` relation directly on `vm1` (no condition).
**And** FGA tuple `compute_instance:vm1#admin@service_account:sva_ci_bot` written (unconditional).

**When** `sva_ci_bot` calls `kacho.compute.v1.InstanceService.Console(vm1)` через api-gateway.

**Then** kacho-compute per-service interceptor builds context (mfa_at empty / acr_value="0" / amr_claims=[] — SA has no WebAuthn).
**And** FGA Check `console@compute_instance:vm1#service_account:sva_ci_bot`:
  - first branch `[user with mfa_fresh]` does NOT match: type-restriction `user` filters out `service_account` subject (CEL condition not even evaluated — type-system rejection).
  - second branch `or admin` matches: SA has direct `admin` tuple → ALLOWED via `or`.
**And** OPA Check empty deny → handler proceeds, RPC returns 200.

**And** Negative sub-case (P3.GWT-15a.neg) — same `sva_ci_bot` БЕЗ `compute.admin` binding:
  - given: only `compute.viewer` binding (`compute_instance:vm1#viewer@service_account:sva_ci_bot`).
  - when: same `Console(vm1)` call.
  - then: FGA Check:
    - first branch `[user with mfa_fresh]` — SA filtered by type-restriction → no match.
    - second branch `or admin` — no admin tuple → no match.
    - overall → DENIED.
  - backend returns `PermissionDenied: "compute.console"`.
  - metric `corelib_authz_denied_total{permission="compute.console", reason="no-match", subject_type="service_account"}` incremented.

**Rationale** (DSL §4): `compute_instance.console` relation deliberately omits `service_account` from the type-restriction of the first branch (unlike `ssh: [user with mfa_fresh, service_account] or admin`) because interactive serial-console access is operationally restricted to humans — SAs reach VMs through `admin` only, never via the `console`-direct path.

#### Scenario P3.GWT-15b: console relation — User with viewer (no admin) → DENIED even с mfa_fresh; with admin → ALLOWED

**Given** model v2 deployed.
**And** User `usr_alice` (Phase 2 — passkey login, JWT `acr=3`, `amr=["webauthn"]`, `ext_claims.kacho_mfa_at=<now-2min>`).
**And** AccessBindingCondition `cond_mfa_fresh` (predicate=`mfa_fresh`).
**And** Compute instance `vm1`.
**And** Initial state: AccessBinding(subject=`usr_alice`, role=`compute.viewer`, resource=`compute_instance:vm1`, condition_id=`cond_mfa_fresh`) — user has `viewer` only, gated by `mfa_fresh`.
**And** FGA tuple `compute_instance:vm1#viewer@user:usr_alice[mfa_fresh]` written (Conditional).

**When** usr_alice calls `Console(vm1)` с the fresh-MFA JWT described above.

**Then** kacho-compute interceptor builds context `{acr_value="3", amr_claims=["webauthn"], mfa_at=<now-2min>, current_time=<now>}`.
**And** FGA Check `console@compute_instance:vm1#user:usr_alice`:
  - first branch `[user with mfa_fresh]` evaluates type-restriction (user ✓) + condition `mfa_fresh` (passes) — но user has NO `console`-direct tuple, only `viewer` tuple → first-branch tuple lookup misses (relation `console` is not transitively derived from `viewer`).
  - second branch `or admin` — user has no admin tuple → no match.
  - overall → DENIED.
**And** Backend returns `PermissionDenied: "compute.console"`.
**And** Metric `corelib_authz_denied_total{permission="compute.console", reason="no-match", subject_type="user"}` incremented.

**And** Follow-up: admin grants `compute.admin` to usr_alice (Upsert AccessBinding(usr_alice, compute.admin, compute_instance:vm1, condition_id=null)) — FGA tuple `compute_instance:vm1#admin@user:usr_alice` written ≤2s (E3 NFR-4 invalidation).
**And** usr_alice retries `Console(vm1)` с same fresh-MFA JWT.
**And** FGA Check now matches second branch `or admin` → ALLOWED.
**And** Note (acceptance gate): MFA-freshness is NOT re-checked on the admin path of `console` — DSL §4 defines `console: [user with mfa_fresh] or admin` без admin-side condition. This is intentional: cluster/account admins reach console without per-call step-up, relying on session-level MFA from initial login (Phase 2 baseline) + Phase 8 CAEP session revocation для emergencies. Documented в `obsidian/kacho/architecture/authz-pipeline.md` § "Console relation semantics".

### 6.5 Conditions — non_expired (3 scenarios — D-5)

#### Scenario P3.GWT-16: non_expired allows when current_time < valid_until

**Given** AccessBindingCondition `cond_non_expired` (predicate=`non_expired`, params={`valid_until_ref`=`expires_at`} — instructs worker to bind `valid_until` к binding's `expires_at` field).
**And** AccessBinding(user=usr_bob, role=vpc.editor, resource=vpc_network:vpcn_x, condition_id=cond_non_expired, expires_at=`now()+2h`).
**And** FGA tuple Conditional `vpc_network:vpcn_x#editor@user:usr_bob[non_expired]` (with context.valid_until = embedded `expires_at`).

**When** usr_bob calls Update on vpc_network:vpcn_x at `now() + 1h`.

**Then** Context built includes `valid_until=<now+2h>, current_time=<now+1h>`.
**And** FGA Check returns ALLOWED (`now+1h < now+2h`).
**And** Handler proceeds.

#### Scenario P3.GWT-17: non_expired denies when current_time >= valid_until

**Given** scenario P3.GWT-16 baseline.

**When** usr_bob calls Update at `now() + 3h` (after expires_at).

**Then** Context `{current_time=<now+3h>, valid_until=<now+2h>}`.
**And** FGA Check returns DENIED (`now+3h < now+2h` false).
**And** PermissionDenied.

#### Scenario P3.GWT-18: non_expired with NULL expires_at (binding-side) — worker rejects creation

**Given** Operator tries to Upsert AccessBinding с `condition_id=<non_expired>` но **без** `expires_at` field set.

**When** handler `kacho-iam.AccessBindingService.Upsert` validates.

**Then** Handler returns `InvalidArgument: "condition non_expired requires expires_at field"` (predicate-level validation in handler — list of predicate→required-fields is in `kacho-iam/internal/domain/conditions/predicate_requirements.go`).
**And** No outbox row inserted, no FGA write attempted.

### 6.6 Conditions — source_ip_in_range (3 scenarios — D-5)

#### Scenario P3.GWT-19: source_ip_in_range allows when client IP within CIDR

**Given** AccessBindingCondition `cond_ip_corp` (predicate=`source_ip_in_range`, params=`{"allowed_cidrs":["10.0.0.0/8","192.168.0.0/16"]}`).
**And** AccessBinding(user=usr_dave, role=vpc.editor, resource=vpc_network:vpcn_y, condition_id=cond_ip_corp).
**And** FGA tuple Conditional `vpc_network:vpcn_y#editor@user:usr_dave[source_ip_in_range]` (with context.allowed_cidrs embedded).

**When** usr_dave вызывает Update from client IP `10.42.5.7` (api-gateway extracts source_ip into Principal).

**Then** Context built includes `client_ip="10.42.5.7", allowed_cidrs=["10.0.0.0/8","192.168.0.0/16"]`.
**And** FGA Check returns ALLOWED (`"10.42.5.7" in ["10.0.0.0/8","192.168.0.0/16"]` via CEL `ipaddress` semantics).

#### Scenario P3.GWT-20: source_ip_in_range denies when client IP outside CIDR

**Given** scenario P3.GWT-19 baseline.

**When** usr_dave вызывает Update from client IP `8.8.8.8` (public).

**Then** Context `{client_ip="8.8.8.8", allowed_cidrs=[...]}`.
**And** FGA Check returns DENIED.
**And** PermissionDenied returned.

#### Scenario P3.GWT-21: source_ip_in_range — IPv6 CIDR support

**Given** AccessBindingCondition `cond_ip_v6` (predicate=`source_ip_in_range`, params=`{"allowed_cidrs":["2001:db8::/32"]}`).
**And** AccessBinding с этой condition.

**When** Client from IPv6 `2001:db8:beef::1` calls.

**Then** Context `{client_ip="2001:db8:beef::1", ...}`.
**And** Check ALLOWED (CEL `ipaddress` handles IPv6 natively).
**And** Same client from `2001:db9::1` (outside /32) → DENIED.

### 6.7 Conditions — break_glass_window (2 scenarios — D-5)

#### Scenario P3.GWT-22: break_glass_window allows in window

**Given** ClusterBreakGlassGrant `bgg_emergency_1` for usr_bob, state=ACTIVE, expires_at=`now()+1h`.
**And** AccessBindingCondition `cond_bgw` (predicate=`break_glass_window`).
**And** FGA tuple Conditional `cluster:cluster_kacho_root#emergency_admin@user:usr_bob[break_glass_window]` (context.expires_at = `now()+1h`).

**When** usr_bob вызывает `vpc.networks.delete` (destructive op) at `now() + 30min`.

**Then** Context `{current_time=<now+30min>, expires_at=<now+1h>}`.
**And** FGA Check `vpc_admin@vpc_network:..` via cluster.emergency_admin cascade → ALLOWED (condition holds).
**And** OPA: R5 cross-tenant — но bob has cluster_admin/emergency_admin → exception path → no deny.
**And** OPA: R6 prod-out-of-hours — `break_glass_active=true` (Principal flag computed from FGA emergency_admin tuple) → exception → no deny.
**And** Handler proceeds.

#### Scenario P3.GWT-23: break_glass_window denies after expires_at

**Given** scenario P3.GWT-22 baseline.

**When** usr_bob calls same RPC at `now() + 2h` (after `expires_at`).

**Then** Context `{current_time=<now+2h>, expires_at=<now+1h>}`.
**And** FGA Check DENIED (condition `current_time < expires_at` fails).
**And** Handler denies.
**And** Note: forward-ref Phase 7 — `ClusterBreakGlassGrant.state` should be auto-flipped к EXPIRED by reconciler at `now() + 1h`; Phase 3 here verifies **condition-level** expiry independent от state machine.

### 6.8 Conditions — jit_window (2 scenarios — D-5; forward-ref Phase 7)

#### Scenario P3.GWT-24: jit_window allows within ttl

**Given** AccessBindingCondition `cond_jit` (predicate=`jit_window`, params=`{"activated_at_ref":"activated_at","ttl_seconds_ref":"ttl_seconds"}` — worker binds к JIT-eligibility row).
**And** Phase 1 row `access_bindings_jit_eligibility` (subject=usr_eve, max_duration=`'2h'::interval`, approval_required=false).
**And** Phase 7 ActivateJIT не implemented в Phase 3, **но** manual SQL: `INSERT INTO access_bindings (...) VALUES (usr_eve, role.admin, project:..., condition=cond_jit, activated_at=<now>, ttl_seconds=3600)`.
**And** FGA tuple Conditional with context.activated_at + context.ttl_seconds.

**When** usr_eve calls protected RPC at `now() + 30min`.

**Then** Context `{current_time=<now+30min>, activated_at=<now>, ttl_seconds=3600}`.
**And** Check `current_time - activated_at < duration("3600s")` → `30min < 60min` → ALLOWED.

#### Scenario P3.GWT-25: jit_window denies after ttl

**Given** scenario P3.GWT-24.

**When** usr_eve calls at `now() + 90min`.

**Then** `current_time - activated_at < duration("3600s")` → `90min < 60min` false → DENIED.

### 6.9 Conditions — business_hours (3 scenarios — D-5)

#### Scenario P3.GWT-26: business_hours allows within window (org timezone)

**Given** Organization `org_acme` с `timezone="Europe/Madrid"`, `business_hours_start=9`, `business_hours_end=18`.
**And** AccessBindingCondition `cond_bh` (predicate=`business_hours`, params=`{"tz":"Europe/Madrid","start_h":9,"end_h":18}`).
**And** AccessBinding с этой condition.

**When** User calls RPC at `2026-05-19T11:00:00+02:00` (Madrid local 11am).

**Then** Context `{current_time=<...>, tz="Europe/Madrid", start_h=9, end_h=18}`.
**And** FGA evaluates `hour_of_day(current_time, "Europe/Madrid") >= 9 && < 18` → 11 в диапазоне → ALLOWED.

#### Scenario P3.GWT-27: business_hours denies outside window

**Given** scenario P3.GWT-26 baseline.

**When** User calls at `2026-05-19T23:00:00+02:00` (Madrid 11pm).

**Then** `hour_of_day(...) = 23`, `23 >= 9 && 23 < 18` → false → DENIED.

#### Scenario P3.GWT-28: business_hours respects different timezones — org with `Asia/Tokyo`

**Given** Organization `org_tokyo_corp` с `timezone="Asia/Tokyo"`, `start_h=9`, `end_h=18`.
**And** AccessBindingCondition `cond_bh_tokyo` (params={tz:"Asia/Tokyo", start_h:9, end_h:18}).
**And** AccessBinding с этой condition.

**When** User calls at `2026-05-19T08:00:00+09:00` (Tokyo 8am — before opening).

**Then** Madrid-eyed UTC is `2026-05-18T23:00:00Z`. `hour_of_day(t, "Asia/Tokyo") = 8`. `8 >= 9 && 8 < 18` → false → DENIED.

### 6.10 Conditions — device_compliant (3 scenarios — D-5)

#### Scenario P3.GWT-29: device_compliant allows when attestation in allowed list

**Given** AccessBindingCondition `cond_dev_compl` (predicate=`device_compliant`, params=`{"allowed_attestations":["attested"]}`).
**And** AccessBinding с этой condition.

**When** User calls с Principal `device_attestation="attested"` (from Phase 2 JWT `ext_claims.kacho_device_compliance`).

**Then** Context `{device_attestation="attested", allowed_attestations=["attested"]}`.
**And** Check `"attested" in ["attested"]` → ALLOWED.

#### Scenario P3.GWT-30: device_compliant denies when partial/unknown attestation

**Given** scenario P3.GWT-29.

**When** Same user calls с device_attestation=`"unknown"` (browser without device-cert).

**Then** Check `"unknown" in ["attested"]` → false → DENIED.

#### Scenario P3.GWT-31: device_compliant denies when JWT lacks attestation claim

**Given** scenario P3.GWT-29.

**When** Phase 2-degenerate case — JWT issued by older Hydra without `kacho_device_compliance` claim (Principal default=`"unknown"`).

**Then** Same as scenario P3.GWT-30: DENIED.
**And** Log warning `"device_attestation defaulted to unknown — JWT missing claim"` for visibility.

### 6.11 OPA bundle signing & loading (4 scenarios — D-7, D-8, D-9)

#### Scenario P3.GWT-32: kacho-iam serves signed bundle; OPA sidecar verifies and loads

**Given** Phase 1 oidc_jwks_keys table has 1 row `kid="key_2026_05"`, `alg="ES256"`, `current=true`.
**And** kacho-iam pod running, embed.FS contains 6 .rego files.
**And** OPA sidecar configured with bundle pull `http://kacho-iam-internal:9091/opa/v1/bundle.tar.gz` (plain cluster-internal HTTP, see §11 Q-bundle-url), signing keyid `key_2026_05` (JWK loaded from ConfigMap).

**When** OPA sidecar starts.

**Then** OPA HTTP GET `http://kacho-iam-internal:9091/opa/v1/bundle.tar.gz` succeeds (200).
**And** Response Content-Type=`application/gzip`, body=tar.gz, header `ETag: "<git-sha>"`.
**And** OPA immediately issues a **second** GET to the sibling path `http://kacho-iam-internal:9091/opa/v1/bundle.tar.gz.sig` (OPA-standard detached-signature delivery mode — see §5.4 proto def). Response 200, body = compact-JWS string.
**And** OPA verifies ES256 signature against JWK `key_2026_05`: parses JWS, checks `kid` header matches configured key, recomputes sha256 of the just-downloaded tarball, asserts the JWS payload's `files[0].hash` equals the recomputed digest → success.
**And** Signature path is **strictly** `bundle.tar.gz.sig` (sibling URL, separate HTTP GET); NOT inline in `BundleResponse`, NOT `X-Opa-Bundle-Signature` HTTP header, NOT in-tarball `.signatures.json` (RFC 8493 — rejected, see §5.4).
**And** OPA extracts policies + data, compiles Rego, loads.
**And** OPA `GET /health?bundles=true` returns 200 (bundle active).
**And** `GET /v1/data/kacho/iam/guardrails` returns rule namespace populated.

#### Scenario P3.GWT-33: Tampered bundle rejected (signature mismatch)

**Given** scenario P3.GWT-32 baseline.
**And** Operator runs adversarial proxy intercepting bundle response, modifies one byte в `deny_billing_destructive.rego`, re-signs with **wrong** key.

**When** OPA sidecar polls bundle.

**Then** Signature verification fails (wrong key OR wrong content hash).
**And** OPA logs `"bundle signature verification failed"` and **does NOT load** new bundle.
**And** OPA retains last-known-good bundle.
**And** Metric `opa_bundle_loading_failures_total{reason="signature_failed"}` incremented.
**And** Alert `OPAStaleBundle` fires if condition persists >1h.

#### Scenario P3.GWT-34: Missing detached signature rejected

**Given** Misconfigured kacho-iam (`oidc_jwks_keys` has no row with `current=true`, OR JWK decryption failed at startup, OR signing key not provisioned via Helm secret). kacho-iam serves `GET /opa/v1/bundle.tar.gz` (200, valid Rego payload) but returns `404 Not Found` для `GET /opa/v1/bundle.tar.gz.sig` (separate detached-signature endpoint per §5.4 `GetBundleSignature` RPC).

**When** OPA polls bundle, then fetches `.sig` companion per `bundles[].signing.keyid` + `verification.required=true` config.

**Then** OPA refuses to load bundle (signature endpoint returned 404 — bundle activation blocked).
**And** Bundle activation: stays last-known-good в memory.
**And** Metric `opa_bundle_loading_failures_total{reason="signature_unavailable"}` incremented.
**And** kacho-iam logs `WARN "OPA bundle signature endpoint hit without provisioned signing key"` (cardinality bounded — admin alert via Phase 9 SIEM rule).

#### Scenario P3.GWT-35: Bundle revision endpoint returns git-sha

**Given** kacho-iam built with `KACHO_BUILD_SHA="abc1234"`.

**When** Client calls `GET http://kacho-iam-internal:9091/opa/v1/bundle/revision`.

**Then** Response 200 `{"revision":"abc1234"}` (JSON).
**And** Bundle endpoint includes header `ETag: "abc1234"`; OPA sends `If-None-Match: "abc1234"` on subsequent polls → response `304 Not Modified` (skip body) — efficient cache.

### 6.12 OPA Rego deny rules — R1..R6 (6 scenarios + extra 6 for "allow" cases)

#### Scenario P3.GWT-36: R1 — destructive on billing project denied for non-admin

**Given** OPA bundle loaded (P3.GWT-32).
**And** Project `prj_billing_acme` exists (id starts с `prj_billing_`).
**And** User `usr_bob` без cluster_admin flag.

**When** usr_bob calls `kacho.iam.v1.ProjectService.Delete(prj_billing_acme)` через api-gateway.

**Then** api-gateway OPA sidecar evaluates `kacho.iam.guardrails.deny` с input `{action:"projects.delete", resource:{id:"prj_billing_acme"}, principal:{id:"usr_bob", cluster_admin:false}}`.
**And** Deny list contains msg `"destructive op on billing project requires cluster-admin (got usr_bob)"`.
**And** api-gateway returns `PermissionDenied: "policy: destructive op on billing project requires cluster-admin (got usr_bob)"`.

#### Scenario P3.GWT-37: R1 — same op allowed for cluster_admin

**Given** P3.GWT-36 baseline + usr_alice has cluster_admin tuple (P3.GWT-05).

**When** usr_alice calls same Delete.

**Then** Principal.cluster_admin computed=true (precomputed by api-gateway via FGA Check `cluster_admin@cluster_kacho_root#user:usr_alice`).
**And** OPA: rule R1 doesn't match (not cluster_admin=false fails).
**And** OPA deny list empty.
**And** Request proceeds to FGA Check.

#### Scenario P3.GWT-38: R2 — service account cannot grant role to user

**Given** OPA bundle loaded.
**And** ServiceAccount `sva_ci_bot` with role=`account.editor`.
**And** Phase 2 — sva_ci_bot has JWT с `kacho_principal_type="service_account"`.

**When** sva_ci_bot calls `kacho.iam.v1.AccessBindingService.Upsert(subject=usr_charlie, role=vpc.editor, resource=...)`.

**Then** api-gateway interceptor builds input `{action:"access_bindings.upsert", principal:{type:"service_account"}, target:{subject_type:"user"}}`.
**And** R2 fires: msg `"service accounts may not grant roles to users"`.
**And** PermissionDenied.

#### Scenario P3.GWT-39: R2 — SA grants to another SA → ALLOWED (R2 not fire)

**Given** P3.GWT-38 baseline.

**When** sva_ci_bot calls Upsert(target=`sva_other`, role=vpc.viewer, ...).

**Then** Input `{principal.type:"service_account", target.subject_type:"service_account"}`.
**And** R2 condition `target.subject_type == "user"` fails → no deny.
**And** Request proceeds (FGA-level check may still reject if SA lacks AccessBindingService.Upsert permission).

#### Scenario P3.GWT-40: R3 — grant org-wide role to non-org member denied

**Given** Organization `org_acme` (P3.GWT-09).
**And** SCIM mappings: usr_charlie ∈ org_acme; usr_external NOT ∈ org_acme.
**And** Bundle data.organizations_users contains `{"org_acme":["usr_charlie","usr_alice_root",...]}`.

**When** Admin tries Upsert(subject=usr_external, role=org.editor, resource=organization:org_acme).

**Then** Input `{action:"access_bindings.upsert", target:{resource_type:"organization", resource_id:"org_acme", subject_id:"usr_external"}}`.
**And** R3: `not user_in_organization("usr_external","org_acme")` → true → deny `"user usr_external not member of organization org_acme"`.
**And** PermissionDenied.

#### Scenario P3.GWT-41: R4 — break-glass grant > 2h denied

**Given** Admin tries to invoke (forward-ref Phase 7 RPC, или Phase 3 admin tool) ClusterBreakGlassGrant.Grant с `duration_seconds=10800` (3 hours).

**When** OPA evaluates input `{action:"cluster.break_glass.grant", duration_seconds:10800}`.

**Then** R4: `10800 > 7200` → deny `"break-glass grant cannot exceed 2 hours"`.
**And** PermissionDenied.

#### Scenario P3.GWT-42: R5 — cross-tenant denied for user

**Given** usr_charlie ∈ account `acc_engineering`.
**And** vpc_network `vpcn_other` ∈ account `acc_other`.

**When** usr_charlie calls `Get(vpcn_other)` через api-gateway.

**Then** api-gateway OPA input `{principal:{type:"user", account_id:"acc_engineering"}, target:{resource:{account_id:"acc_other"}}}`.
**And** R5: principal.account_id != target.resource.account_id + principal.cluster_admin=false → deny `"cross-tenant access blocked: acc_engineering → acc_other"`.
**And** PermissionDenied.

#### Scenario P3.GWT-43: R6 — prod project destructive outside business-hours denied (no break-glass)

**Given** Project `prj_app_prod` (ends `_prod`).
**And** Org tz `Europe/Madrid`, business hours 9-18.
**And** Current time `2026-05-19T22:00:00+02:00` (Madrid 10pm — outside).
**And** usr_alice без active break-glass.

**When** usr_alice calls `kacho.compute.v1.InstanceService.Delete(<instance в prj_app_prod>)`.

**Then** OPA input `{action:"compute.instances.delete", resource:{project_id:"prj_app_prod"}, principal:{break_glass_active:false, timezone:"Europe/Madrid"}}`.
**And** R6 fires: msg `"destructive ops on prod projects require business hours or break-glass"`.
**And** PermissionDenied.

### 6.13 Rego unit-tests (mandatory CI)

#### Scenario P3.GWT-44: opa test policies/ runs all tests successfully (positive + negative)

**Given** Repo `kacho-iam` `policies/` folder:
- 6 production .rego rule files (R1..R6)
- 18+ test cases (3 per rule: deny-fires, allow-pass-cluster-admin-exception, allow-pass-no-match)

**When** CI step runs `opa test policies/ -v`.

**Then** All 18+ tests PASS, exit code 0.
**And** Sample output `PASS: 18/18 (0 errors)`.

#### Scenario P3.GWT-45: CI fails if any Rego test fails

**Given** Operator introduces regression — removes `not input.principal.cluster_admin` от R1.

**When** CI runs `opa test`.

**Then** Test `test_allow_billing_project_delete_cluster_admin` fails (now also denies cluster_admin).
**And** CI exit-nonzero.
**And** PR cannot be merged (workflow gate).

### 6.14 Cache invalidation (3 scenarios — E3 baseline reused, D-15)

#### Scenario P3.GWT-46: AccessBinding.Upsert (with condition) → cache invalidated ≤1s

**Given** Backend kacho-vpc has cached `Check(vpc_admin@vpc_network:X#user:usr_bob)=false` (no binding initially).
**And** Admin Upsert(usr_bob, vpc.admin, vpc_network:X, condition_id=cond_mfa_fresh).

**When** Outbox-worker writes FGA tuple Conditional + NOTIFY `kacho_iam_subjects` payload `{"subject_id":"usr_bob"}`.

**Then** All backend Pods (LISTEN'ing on `kacho_iam_subjects`) receive notification ≤500ms.
**And** Each backend's `corelib/authz` Check-cache: evict all entries where `cache_key.user == "usr_bob"`.
**And** Next Check call from usr_bob → cache miss → FGA Check (с current Conditions context) → reflects new binding.
**And** Total propagation latency p95 ≤ 1s (E3 NFR-4).

#### Scenario P3.GWT-47: AccessBinding.Delete invalidates Conditional bindings

**Given** P3.GWT-46 baseline (binding active).

**When** Admin Delete that binding (existing E3 path).

**Then** outbox writes FGA Delete tuple + NOTIFY.
**And** Subscriber receives → invalidate.
**And** Next Check from usr_bob → returns false (binding gone).

#### Scenario P3.GWT-48: Condition param change (re-upsert с same subject/role/object но different condition_id)

**Given** Existing binding `(usr_bob, vpc.admin, vpc_network:X, condition_id=cond_a)`.

**When** Admin Upsert with same subject/role/object но `condition_id=cond_b`.

**Then** Outbox writes Delete (cond_a tuple) + Write (cond_b tuple) — handled by worker as two FGA ops.
**And** NOTIFY twice (Phase 3 worker может coalesce — implementation detail, test only requires final state consistency).
**And** Within ≤1s, all backends see new Conditional binding `[cond_b]`.

### 6.15 Fail-closed (3 scenarios — D-16)

#### Scenario P3.GWT-49: FGA-engine unavailable → mutation denied (fail-closed)

**Given** kacho-vpc backend running normally.
**And** Operator kills FGA pod (`kubectl delete pod -l app=openfga`).
**And** FGA recovery >5s (longer than client timeout).

**When** usr_bob calls vpc.networks.create.

**Then** Backend interceptor `corelib/authz.Check` → context-deadline-exceeded.
**And** Returns `PermissionDenied: "authz unavailable"` (НЕ Internal — explicit fail-closed messaging).
**And** Metric `corelib_authz_fail_closed_total{component="fga"}` += 1.
**And** Alert `AuthzEngineDown` fires within 5min.

#### Scenario P3.GWT-50: OPA sidecar unavailable → mutation denied (fail-closed default)

**Given** Backend pod running, but OPA sidecar `:8181` not ready (OPA loading bundle).

**When** usr_bob calls mutation.

**Then** Interceptor (after FGA ALLOW) calls localhost:8181 → connection-refused/timeout.
**And** Returns `PermissionDenied: "policy unavailable"`.
**And** Metric `corelib_authz_fail_closed_total{component="opa"}` += 1.
**And** Alert `OPASidecarDown` fires.

#### Scenario P3.GWT-51: Read fail-open with feature-flag enabled

**Given** Backend started with env `KACHO_AUTHZ_READ_FAIL_OPEN=true` (admin opt-in for emergency).
**And** FGA unavailable (P3.GWT-49 conditions).

**When** usr_bob calls vpc.networks.list (read-only).

**Then** Interceptor detects: op type=`read` AND fail-open=true → permit.
**And** Log WARN `"authz fail-open: read permitted без FGA Check"` with full request context.
**And** Metric `corelib_authz_fail_open_total{op="read"}` += 1.
**And** Alert `AuthzFailOpenActive` fires Critical (visibility).
**And** Same scenario but mutation → still fail-closed (only reads are flagged).

### 6.16 AccessBindingService.Upsert с condition (3 scenarios — D-13)

#### Scenario P3.GWT-52: Upsert с condition_id writes Conditional tuple within 2s

**Given** Existing user usr_grace, role vpc.editor.
**And** AccessBindingCondition `cond_mfa_fresh` exists в `access_binding_conditions` (Phase 1).

**When** Admin calls `AccessBindingService.Upsert(subject=usr_grace, role=vpc.editor, resource=vpc_network:vpcn_x, condition_id=cond_mfa_fresh)`.

**Then** Operation Long-Running returns immediately (KAC-127 запрет #9 — async).
**And** Within 200ms (NFR-6 E3): `access_bindings` row inserted с `condition_id=<cond_mfa_fresh.id>`.
**And** `fga_outbox` row queued.
**And** Worker picks up ≤2s, writes FGA tuple:
  ```json
  {
    "user": "user:usr_grace",
    "relation": "editor",
    "object": "vpc_network:vpcn_x",
    "condition": { "name": "mfa_fresh", "context": {} }
  }
  ```
**And** Operation.Get returns done=true.

#### Scenario P3.GWT-53: Upsert с invalid condition_id → InvalidArgument

**Given** No AccessBindingCondition with `id="cond_nonexistent"`.

**When** Admin Upsert с `condition_id="cond_nonexistent"`.

**Then** Handler validates (queries `access_binding_conditions`) → not-found.
**And** Returns `InvalidArgument: "Illegal argument condition_id 'cond_nonexistent' not found"` (YC-style error text).
**And** No row inserted, no outbox queued.

#### Scenario P3.GWT-54: Conditional binding Check evaluates context correctly end-to-end

**Given** P3.GWT-52 executed (binding с cond_mfa_fresh).

**When** usr_grace вызывает `vpc.networks.update(vpcn_x)` с two different JWT contexts (sequentially):
- (a) JWT acr=3, amr=[webauthn], mfa_at=now-2min
- (b) JWT acr=2, amr=[password], mfa_at=now-2min

**Then** (a) Backend: Check builds context `{acr_value="3", amr_claims=["webauthn"], mfa_at=...}` → FGA ALLOWED → handler proceeds → 200 OK.
**And** (b) Same backend: Check builds `{acr_value="2", ...}` → FGA DENIED → returns PermissionDenied (mfa_fresh condition fail).

### 6.17 corelib/authz/listobjects.go skeleton (1 scenario — D-14)

#### Scenario P3.GWT-55: listobjects skeleton package exists, interface defined, Unimplemented returned

**Given** `corelib/authz/listobjects.go` exists с:
```go
type ListObjectsClient interface {
    ListObjects(ctx context.Context, principal *Principal, relation, objectType string) ([]string, error)
}
type stubClient struct{}
func (stubClient) ListObjects(...) ([]string, error) {
    return nil, status.Error(codes.Unimplemented, "ListObjects integrated in Phase 4")
}
func NewListObjectsClient() ListObjectsClient { return stubClient{} }
```

**When** Phase 3 code does NOT call ListObjects (no integration yet).
**And** Hypothetical caller invokes `client.ListObjects(...)` (e.g., a smoke-test).

**Then** Returns gRPC `Unimplemented: "ListObjects integrated in Phase 4"`.
**And** Metric `corelib_authz_listobjects_called_total` += 1.
**And** Compile-test confirms interface is satisfied by stub.
**And** Phase 4 will replace stub с actual implementation без changing interface.

---

## 7. Definition of Done (Phase 3 closure)

### Functional
- [ ] OpenFGA Authorization Model v2 (full DSL §4) deployed via `openfga-bootstrap-job` (idempotent, hash-compare); Secret `openfga-model-id` populated.
- [ ] 7 Conditions (`mfa_fresh`, `non_expired`, `source_ip_in_range`, `break_glass_window`, `jit_window`, `business_hours`, `device_compliant`) loaded в FGA-engine, verifiable через `GET /stores/<id>/authorization-models/<id>/conditions`.
- [ ] `corelib/authz/conditions_context.go` builds CEL-context from Principal; integration test passes (Conditional tuple Check w/ context).
- [ ] `corelib/authz/listobjects.go` skeleton (interface + Unimplemented stub) merged; Phase 4 will fill.
- [ ] `kacho-iam AccessBindingService.Upsert` extended: принимает `condition_id` + `expires_at`; FGA tuple written в Conditional-form (verifiable via Read API).
- [ ] `kacho-iam OpaBundleService` (Internal RPC) serves signed tar.gz bundle + revision endpoint; api-gateway registers через `restmux.RegisterInternal()`.
- [ ] 6 Rego deny rules (R1..R6) in `kacho-iam/policies/`, signed by current `oidc_jwks_keys` row (ES256 JWS).
- [ ] OPA sidecar injected в api-gateway + kacho-iam + kacho-vpc + kacho-compute + kacho-loadbalancer pods; sidecar pulls bundle 1h TTL, verifies signature, loads policies.
- [ ] All RPC paths invoke OPA Check AFTER FGA Check ALLOWED, BEFORE handler-business-logic.
- [ ] Fail-closed на FGA/OPA unavailable; read fail-open feature-flagged.

### Tests / CI
- [ ] **Integration tests** (testcontainers Postgres + openfga + opa) per запрет #11:
  - `corelib/authz/check_integration_test.go` — Conditional Check positive/negative for all 7 Conditions.
  - `kacho-iam/internal/apps/kacho/api/access_binding/upsert_integration_test.go` — Upsert с condition_id → outbox → FGA Conditional tuple verified.
  - `kacho-iam/internal/apps/kacho/api/opa/bundle_integration_test.go` — bundle endpoint serves valid signed tar.gz; tamper test fails.
  - `kacho-iam/internal/apps/kacho/api/opa/sign_bundle_test.go` — JWS sign/verify roundtrip with rotated keys.
- [ ] **Rego unit-tests** (`opa test policies/` exit 0): minimum 3 tests per rule (deny-fires, allow-cluster-admin-exception, allow-no-match) = ≥18 tests; CI fails on any red.
- [ ] **Newman e2e** in `kacho-test/newman/cases/`:
  - `iam_authz_conditional_mfa_fresh.py` — happy path step-up flow (initial deny → re-auth → allow).
  - `iam_authz_opa_billing_deny.py` — R1 destructive-on-billing-project blocked.
  - `iam_authz_opa_cross_tenant.py` — R5 cross-tenant blocked.
  - `iam_authz_opa_break_glass.py` — R4 max-duration-2h enforced.
  - `iam_authz_opa_prod_out_of_hours.py` — R6 outside business-hours blocked unless break-glass.
- [ ] **k6 load test** `kacho-test/k6/iam_authz_check_latency.js` — Conditional Check pipeline p95 ≤30ms (NFR-2 + design §2).
- [ ] CI green в kacho-proto (buf lint + buf breaking), kacho-corelib (`go test ./...`), kacho-iam (`go test ./... && opa test policies/`), kacho-deploy (`helm lint` + `helm template` + chart-testing).

### Operational
- [ ] Helm template renders idempotent (helm diff no-op после повторного apply).
- [ ] Rolling restart по openfga-model-id Secret-rotation tested in dev стенд (smoke).
- [ ] OPA sidecar readinessProbe `/health?bundles=true` reflects bundle-loading state.
- [ ] Bundle revision endpoint exposed для quick polling health-check.
- [ ] Bundle endpoint NetworkPolicy denies pods outside the kacho-* ServiceAccount allowlist (`kacho-api-gateway`, `kacho-iam`, `kacho-vpc`, `kacho-compute`, `kacho-loadbalancer` — only these SAs are permitted as ingress sources to `kacho-iam-internal:9091/opa/v1/*`). Verified via test-pod в `default` namespace (no kacho ServiceAccount) running `curl http://kacho-iam-internal.kacho-system.svc.cluster.local:9091/opa/v1/bundle.tar.gz` → expect **connection-refused / timeout** (NetworkPolicy drops at L4 before HTTP). Test artefact: `kacho-deploy/tests/netpol/opa_bundle_deny_test.sh` (kubectl exec into ephemeral pod, assertion на exit-code 7=curl-connect-failed или 28=timeout). Defense-in-depth: even if a tenant-namespace pod is compromised, it cannot pull the bundle (which leaks the Rego deny-rule shapes + SCIM-set + billing-project list data — useful reconnaissance for attackers). Documented в `obsidian/kacho/architecture/network-policy-matrix.md`.

### Security / Compliance
- [ ] Запрет #6 enforced: OpaBundleService — Internal only; bundle endpoint not exposed на external TLS edge (verifiable via `kubectl exec api-gateway curl https://api.kacho.cloud/opa/v1/bundle.tar.gz` → 404).
- [ ] Запрет #11 enforced: каждый PR этой Phase contains tests in same PR.
- [ ] JWKS used для bundle signing is **separate** from JWKS used для DPoP/token-signing (different `kid` series, same `oidc_jwks_keys` table). Documented в vault `obsidian/kacho/architecture/jwks-key-roles.md`.
- [ ] All Rego deny rules emit msg with sufficient context for debugging (principal-id, target-id, action) — verifiable via newman expecting specific msg-fragments.
- [ ] Fail-open read flag default OFF; enabling logged at WARN + Critical alert.

### Documentation
- [ ] `obsidian/kacho/KAC/KAC-127.md` updated (PR links, Phase 3 checklist marked).
- [ ] New: `obsidian/kacho/architecture/authz-pipeline.md` (ASCII pipeline + Conditions list + Deny list, 1-3KB).
- [ ] New: `obsidian/kacho/rpc/iam-opa-bundle.md` (OpaBundleService Internal RPC, 1-3KB).
- [ ] New: `obsidian/kacho/edges/api-gateway-to-iam-opa-bundle-pull.md` (edge description).
- [ ] New: `obsidian/kacho/edges/vpc-to-iam-opa-bundle-pull.md` (and same для compute, lb).
- [ ] `kacho-iam/README.md` мини-секция "Authz pipeline".
- [ ] `docs/specs/01-architecture-and-services.md` дополнено разделом "OPA sidecar + Conditional FGA" (delta from E3).

### Code quality
- [ ] All Go code passes `golangci-lint` (workspace default config).
- [ ] All Rego passes `opa fmt --diff` (no fmt diffs allowed).
- [ ] No `TODO` / `FIXME` / `XXX` comments в production code (`grep -r TODO kacho-iam/internal/apps/kacho/api/opa/` returns 0).
- [ ] Production-edition: no `wontfix` / `out-of-scope` deferred items intra-Phase 3.

---

## 8. Cross-repo PR-chain (порядок merge — топосорт)

> Точная очерёдность смерж'а; CI вышестоящего pinned к feature-ветке нижестоящего до merge → после merge ref'ы возвращаются к `main`. См. workspace `CLAUDE.md` §«Кросс-репо зависимости».

| # | Репо | PR title | Что включает |
|---|---|---|---|
| **1** | `kacho-proto` | `[KAC-127][Phase 3] Conditional AccessBinding + OpaBundleService` | `access_binding.proto` (add `condition_id`, `expires_at`); `opa_bundle.proto` (new Internal); regen gen/; buf-lint + buf-breaking green |
| **2** | `kacho-corelib` | `[KAC-127][Phase 3] authz Conditions context builder + ListObjects skeleton` | `authz/conditions_context.go` + tests; `authz/check.go` extension; `authz/listobjects.go` skeleton; integration tests с openfga testcontainer |
| **3a** | `kacho-iam` | `[KAC-127][Phase 3] AccessBinding condition support + OpaBundleService + Rego policies` | Handler `upsert.go` extension; outbox-worker Conditional-tuple writer; `internal/apps/kacho/api/opa/{bundle,sign_bundle,revision}.go`; `policies/*.rego` + `policies/*_test.rego`; integration + Rego unit tests |
| **3b** | `kacho-api-gateway` | `[KAC-127][Phase 3] Register OpaBundleService Internal + Principal source_ip extraction` | `internal/restmux/mux.go` += `iamInternal.RegisterOpaBundleHandler`; Principal-extraction extended для `source_ip`/`device_attestation` claims (если уже не сделано в Phase 2 — see Phase 2 closure) |
| **4** | `kacho-deploy` | `[KAC-127][Phase 3] OpenFGA model v2 + OPA sidecar injection + bundle config` | `openfga-model-stub-configmap.yaml` (full DSL §4); `openfga-bootstrap-job.yaml` (idempotent); `opa-sidecar-configmap.yaml`; `opa-bundle-server-configmap.yaml`; per-chart sidecar injection; helm-lint + chart-testing |
| **5** | `kacho-workspace` | `[KAC-127][Phase 3] vault: authz pipeline + bundle service + KAC-127 progress` | Update `obsidian/kacho/KAC/KAC-127.md`; create `architecture/authz-pipeline.md`, `rpc/iam-opa-bundle.md`, `edges/*-to-iam-opa-bundle-pull.md` |

CI ref-pins (temporary, removed после merge):
- During step 2 work: kacho-corelib CI `kacho-proto-ref: KAC-127` (feature-branch).
- During step 3a/3b: kacho-iam / kacho-api-gateway CI `kacho-proto-ref: KAC-127`, `kacho-corelib-ref: KAC-127`.
- During step 4: kacho-deploy CI builds images с `--build-arg KACHO_PROTO_REF=KAC-127` etc.
- After all PRs merged: revert refs к `main` в next batch-commit.

Branch policy: branch `KAC-127` в каждом из 5 затронутых репо; после merge — `gh pr merge --delete-branch`.

---

## 9. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| OpenFGA Conditions CEL не поддерживает все 7 предустановленных predicates как-is | High | Pre-validation: integration test `corelib/authz/check_integration_test.go` поднимает openfga 1.6.x и WriteAuthorizationModel с DSL §4 — если parse fails → DSL должна быть исправлена ДО merge (early-fail на CI step 2) |
| OPA bundle signing — JWK rotation race (bundle подписан старым ключом, OPA уже ротировал) | Medium | OPA config с **two-key acceptance** (current + previous); kacho-iam JWKS endpoint serves both; rotation policy: 1h overlap minimum (Phase 1 `oidc_jwks_keys` уже supports `rotated_at` + previous-current pattern) |
| Sidecar resource overhead (5 services × ~64MB OPA = 320MB cluster-wide) | Low | Resource limits 256Mi/cpu100m (см. §5.6); OPA upstream benchmarks ~50MB steady-state for bundle this size; alert if sidecar OOM-killed >1/day |
| OPA bundle build latency (kacho-iam serves bundle на каждый poll — много pods × 1h TTL) | Low | Bundle is cached server-side (built once per DB-snapshot, cached 5 min); ETag/304 Not Modified support → most polls return 304 (no body); load test confirms throughput ≥100req/s |
| Conditional Check latency overhead vs unconditional (more CPU в FGA-engine) | Medium | Latency budget §4.4: cache-hit ≤1ms (unchanged); cache-miss +2-3ms за CEL eval. k6 test (DoD §Tests) confirms p95 ≤30ms (NFR-2 with 50% margin) |
| Helm rollback race с openfga-model-id Secret | Low | Job is idempotent (P3.GWT-04); FGA models immutable; rolling restart ordered by helm-hook `post-rollback` |
| Adversarial bundle injection (MitM between kacho-iam and OPA sidecar) | High | Phase 3: bundle pull is plain HTTP cluster-internal (see §11 Q-bundle-url) — **integrity guaranteed by detached JWS signature** (ES256, mandatory `verification.required=true` in OPA bundle config; signature covers sha256 of tarball). Any MitM that substitutes the bundle body cannot forge the JWS without the private key (stored encrypted in `oidc_jwks_keys` only on kacho-iam). NetworkPolicy (DoD §Operational) further restricts which pods can reach the bundle endpoint (kacho-* SA allowlist), eliminating tenant-pod-side MitM vectors. Phase 10 SPIFFE/Cilium mTLS adds in-transit confidentiality + workload-identity binding (current bundle data is non-secret — public SCIM mappings, public org-tz, public billing-project list — so confidentiality is nice-to-have, not required) |
| Conditions cache-key explosion (every unique CEL context → different cache entry) | Medium | Cache key = `(principal_id, permission, object_id)` — NOT including condition-context (cache invalidates on subject-change; condition-eval happens fresh per Check). Memory overhead bounded by tuple-count |
| Cluster_admin/emergency_admin precomputed flag в Principal — staleness | Low | api-gateway computes flag on JWT-validation (Phase 2 baseline); JWT TTL=15min → max staleness 15min. Revocation via Phase 8 CAEP пушит session_revocations → API-GW evicts session → forces re-auth → fresh flag |

---

## 10. Out of Scope (явно отложено в последующие Phases)

| Feature | Phase |
|---|---|
| ListObjects API integration in List-handlers per service | Phase 4 |
| Federation Exchange RPC (Token Exchange RFC 8693), SA Hydra-clients | Phase 5 |
| SCIM 2.0 endpoint + SAML bridge + Organization-UI | Phase 6 |
| JIT activation RPC + Break-glass workflow + 2-person approval + Access Reviews automation + GDPR erasure cron | Phase 7 |
| CAEP drainer + SET signing + webhook delivery + retry/backoff | Phase 8 |
| Audit pipeline Kafka + ClickHouse + S3+Glacier + HSM batch signing | Phase 9 |
| SPIFFE/SPIRE + Cilium service mesh | Phase 10 |
| Multi-region active-active + `api.kacho.cloud` TLS + Argo CD + Grafana + Alertmanager | Phase 11 |
| OWASP ASVS L3 conformance + fuzzing + chaos + pentest + bug bounty | Phase 12 |
| Vault closeout (30+ files) | Phase 13 |

В Phase 3 НЕ делаются никакие из вышеперечисленных. Если в ходе implementation возникнет вопрос
"может, всё-таки сделать X сейчас" — ответ "нет", это нарушение production-edition discipline.

---

## 11. Open Questions Resolved (inline)

| Q | Resolution |
|---|---|
| Какой keyid использовать для bundle signing — same as Hydra access-token signing? | **Separate kid series** (one `oidc_jwks_keys` table, разные `alg` группы; `kid` для bundle = `bundle_<rotated_at>`, для access-tokens = `at_<rotated_at>`). Logically separated; physically same table. Documented в vault. |
| **Q-bundle-url**: Bundle pull URL должен быть `https://` или `http://` на cluster-internal port 9091? | **`http://` plain cluster-internal HTTP** в Phase 3 — consistent с Phase 2 Hydra-hook URL `http://kacho-iam.kacho-system.svc.cluster.local:9091/iam/v1/hooks/token`. Bundle integrity guaranteed via **detached JWS signature** (ES256, mandatory at OPA `verification.required=true`) — signature verification catches any tamper / MitM substitution, поэтому plain-HTTP в cluster-internal сети acceptable. TLS-encryption (in-transit confidentiality) добавляется Phase 10 SPIFFE/Cilium-mesh mTLS (workload-identity-bound mTLS на каждый pod-to-pod hop). Defense layers: (1) Phase 3 — JWS signature (integrity); (2) Phase 10 — SPIFFE mTLS (confidentiality + workload auth). Бундл не содержит секретов (data — публичные SCIM-маппинги + публичные org-timezone-конфиги + публичный список billing-проектов; signing-key private key всегда remains в kacho-iam) → конфиденциальность bundle body не critical в Phase 3. Доказательство consistency: Phase 2 Hydra-hook (карат токены через plain HTTP, integrity via mTLS-issued Hydra JWT валидируется на kacho-iam side); тот же threat-model. URL prefix унифицирован — `http://` во всех cluster-internal calls в Phases 1-9, `https://` появляется только на external TLS edge через api-gateway. |
| Что если backend стартует с `KACHO_OPENFGA_MODEL_ID` env, который из stale Secret (несколько minutes за rolling)? | Hash-compare DSL: backend at startup compares pinned model_id с FGA `GET /authorization-models` — if not found, fail-startup (won't accept traffic). Helm rolling-restart порядок: bootstrap-job first (post-install/upgrade hook waits for completion), then backends rolling-restart on Secret-change. |
| Если FGA-store пуст (рестарт persistence-volume) — что бутстрэп-джоб делает? | Detects empty store via `GET /stores` → creates store + writes model + writes baseline tuples (`cluster:cluster_kacho_root#system_admin@user:<bootstrap_root_email lookup>`). Baseline-tuple write — Phase 1 seed migration via `cluster_admin_grants` already-populated. Phase 3 bootstrap-job triggers outbox-worker re-flush at the end. |
| Sidecar OPA — что если bundle ещё не загружен на старте pod'а? | Pod readinessProbe (sidecar) blocks pod becoming Ready until OPA `/health?bundles=true` returns 200. Service routing skips not-ready pod. No request reaches not-ready interceptor. |
| Можно ли pin'ить ConditionalTuple cache (т.е., кэшировать с учётом context)? | **Нет** в Phase 3 — overcomplex, error-prone. Cache всегда (principal_id, permission, object_id) → bool; Condition-eval re-runs per Check на FGA-side. Acceptable since FGA Check itself is 5-10ms p95 cache-miss. |
| Что если OPA sidecar crashes / OOM-killed mid-request? | Pod restart-policy=Always; k8s liveness fails → pod restart; в interval downtime — interceptor fail-closes (P3.GWT-50); SLO of <1 unhealthy minute per month per pod. |
| Rego data из БД — staleness? | 1h TTL = max staleness 1h for SCIM-set, timezone, billing-projects list. Acceptable per design (SCIM bulk-sync typical 1h granularity; billing-project deletion is rare admin op). Future Phase 8 CAEP может push SCIM-change as cache-invalidation event для real-time refresh (out of scope here). |

---

## 12. Связь с регламентом (повтор для reviewer convenience)

- **Запрет #1**: gate is this document → APPROVED → kодинг.
- **Запрет #2**: no "yandex" в Rego, DSL, .proto, Go-имена. YC-style стилистика error-text — допустима (например, `"Illegal argument condition_id"`).
- **Запрет #3**: openfga-go-sdk — gRPC client (не ORM); JOSE-go (не ORM); embed.FS (не ORM).
- **Запрет #4**: bundle pull — не cascade-delete.
- **Запрет #5**: zero migrations Phase 3 (or new 0015_ if discovered need).
- **Запрет #6**: OpaBundleService Internal only.
- **Запрет #7**: no broker; LISTEN/NOTIFY + HTTP polling.
- **Запрет #8**: OPA data via bundle-build, not cross-DB.
- **Запрет #9**: AccessBindingService.Upsert remains async Operation; OpaBundleService.GetBundle is sync read (not mutation).
- **Запрет #10**: FGA tuples atomic-write через FGA-engine (its own atomicity); access_bindings DB-uniqueness from Phase 1.
- **Запрет #11**: integration tests + Rego unit tests + newman e2e в каждом PR.

---

## 13. Phase 3 changelog

- **2026-05-19** — DRAFT v1 создан (`acceptance-author`). Decision Log P3-D1..D20 закрыт inline. 55 GWT scenarios (target ≥40 met). Out-of-scope = Phases 4-13 (no intra-Phase deferred items).
- **2026-05-19** — DRAFT v2 review-fix pass (`acceptance-author` applying CHANGES REQUESTED from `acceptance-reviewer`): (1) **CR1** — added `P3.GWT-15a` + `P3.GWT-15b` to §6.4 covering `compute_instance.console` relation (DSL §4: `console: [user with mfa_fresh] or admin` — без service_account in the first branch), bringing §6.4 from 4 to 6 scenarios and total from 55 to 57; (2) **CR2** — bundle pull URL fixed from `https://` to `http://` across §2.2, §2.3 ASCII, §4.1, §5.6 OPA config, §6.11 P3.GWT-32, P3.GWT-35 (consistent with Phase 2 Hydra-hook plain-HTTP cluster-internal; integrity via JWS, confidentiality deferred to Phase 10 SPIFFE mTLS); new §11 Open Question `Q-bundle-url` documents the rationale; §9 Risk row "Adversarial bundle injection" updated. (3) **Minor #2** — §2.1 Principal.cluster_admin computation extended to use `any_admin` relation (covers both permanent `system_admin` and time-bounded `emergency_admin` from `cluster_break_glass_grants` with active `break_glass_window` condition). (4) **Minor #3** — §5.4 proto: added separate `GetBundleSignature` RPC at `/opa/v1/bundle.tar.gz.sig` sibling path (OPA-standard detached-signature mode); `BundleResponse.signature_jws` removed (no inline); P3.GWT-32 explicit that signature is fetched via second GET to `bundle.tar.gz.sig`. (5) **Minor #6** — §7 DoD Operational: added NetworkPolicy bullet (kacho-* SA allowlist on bundle endpoint; default-ns test-pod must get connection-refused). Open Questions §11 count went from 7 to 8.
