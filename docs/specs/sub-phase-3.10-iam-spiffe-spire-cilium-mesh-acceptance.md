# Sub-phase 3.10 — IAM In-cluster Workload Identity (SPIFFE/SPIRE) + Service Mesh (Cilium eBPF) (KAC-127) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: KAC-127 epic (production-ready next-gen IAM); Phase 10 subtasks per plan §"Phase 10" (Tasks 10.1-10.9).
> **Author agent**: `acceptance-author` (round 2 — user feedback: no strict backward-compat).
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` — §6 Class C (SPIFFE/SPIRE + Cilium mesh), §12 (Workload Identity in-cluster operational), §13 (Compliance), §14 (Threat model: lateral movement, compromised pod, compromised image), §17 DoD.
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — Phase 10 (tasks 10.1-10.9).
> **Skill reference**: `references/workload-identity.md` §1-§3 (SPIFFE/SPIRE attestation lifecycle, SVID rotation, trust domain federation), §2.2 (Cilium eBPF mesh integration patterns).
> **Phase position**: §16 design doc "Migration plan", **Phase 10 of 13**. **Penultimate infrastructure phase** before Phase 11 production multi-region deploy.
> **Predecessors (must be merged before code begin)**:
> - Phase 1 — IAM Foundation (`sub-phase-3.1-iam-foundation-acceptance.md`): `users`, `accounts`, `projects`, `service_accounts`, `audit_outbox` tables exist; cluster_kacho_root singleton; `kacho_mesh_principal` claim format reserved in JWT claims schema.
> - Phase 2 — AuthN core (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`): end-user JWT structure stable (`sub`, `acr`, `amr`, `kacho_account_id`, `kacho_project_id`, `kacho_session_id`).
> - Phase 3 — AuthZ core (`sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`): OpenFGA `Check`/`ListObjects` endpoints stable; corelib/authz `Principal` type used by all consumer services.
> - Phase 5 — Workload Identity Federation external Class B (`sub-phase-3.5-iam-workload-identity-federation-acceptance.md`): `FederationExchangeService` returns short-lived JWT for external CI/CD; **Phase 10 is the in-cluster (Class C) counterpart** — they coexist (external WIF for CI runners, SPIFFE for in-cluster pods).
> - Phase 6 — Enterprise SSO (`sub-phase-3.6-iam-scim-saml-organization-acceptance.md`): `Organization` resource is consumer for federation bundle subscriber registry (Phase 10 federation publishes; cross-org federation consumption is Phase 11+).
> - Phase 8 — CAEP push (acceptance separate): SVID revocation events publish to `caep_outbox` upon emergency trust-domain rotation (Phase 10 emits rows; Phase 8 drainer consumes).
> - Phase 9 — Audit pipeline (acceptance separate): all SPIRE Server admin events (entry CRUD, attestation grants, rotation) write to `audit_outbox` (Phase 10 emits rows; Phase 9 drainer ships to Kafka/ClickHouse/S3).
> **Target repos / merge order (топологическая сортировка graf'а, см. workspace `CLAUDE.md` §"Кросс-репо зависимости")**:
> 1. `PRO-Robotech/kacho-proto` — `kacho.iam.v1.FederationBundleService` (public read-only — serves SPIFFE trust bundle in JWKS+SPIFFE-bundle format), `kacho.iam.v1.InternalSpiffeRegistrationService` (internal — admin CRUD for registration entries; backs Argo CD reconciler), `kacho.iam.v1.InternalSpiffeRevocationService` (internal — emergency revoke single SVID / rotate trust domain), proto annotations on existing public messages для `x-kacho-mesh-caller-spiffe-id` metadata reservation.
> 2. `PRO-Robotech/kacho-corelib` — `corelib/spiffe/` package: `workloadapi.go` (wraps go-spiffe v2 `workloadapi.Client` — auto-rotate SVID, watch source), `interceptor.go` (gRPC server interceptor — extract caller SPIFFE-ID from peer mTLS cert, populate `corelib/authz.Principal.MeshCaller`), `client.go` (gRPC client transport credentials using SPIFFE SVID source), `verifier.go` (peer SPIFFE-ID allow-list matcher with trust-domain awareness), `corelib/spiffe/testing.go` (in-memory SVID source for integration tests).
> 3. `PRO-Robotech/kacho-iam` — `internal/apps/kacho/api/spiffe/federation_bundle.go` (`FederationBundleService.Get` — sync read; returns active trust-domain bundle JWKS+SPIFFE keys), `internal/apps/kacho/api/spiffe/{create,update,delete,get,list}_registration.go` (Internal admin — registration entry CRUD), `internal/apps/kacho/api/spiffe/revoke_svid.go` / `rotate_trust_domain.go` (Internal emergency), `internal/domain/spiffe_registration.go` (self-validating domain), `migrations/0024_kac127_phase10_spiffe_registrations.sql` (kacho_iam.spiffe_registrations + trust_domain_bundles + svid_revocations tables; emit via existing audit_outbox + caep_outbox).
> 4. All `PRO-Robotech/kacho-{vpc,compute,loadbalancer,api-gateway}` services — wire `corelib/spiffe` into gRPC server bootstrap (`grpcsrv.WithSpiffeMTLS`) and gRPC client factory (`grpcclient.WithSpiffeTransport`); Deployment manifests add `/run/spire/sockets/agent.sock` hostPath volume mount + Cilium mesh annotations; remove pre-existing plaintext mTLS bootstrap (no backward-compat — see Decision Log P10-D2).
> 5. `PRO-Robotech/kacho-api-gateway` — `internal/restmux/mux.go` registers `FederationBundleService` on **public** mux at `/.well-known/spiffe-bundle` (RFC 7517 compatible JWKS endpoint + SPIFFE bundle format both served per `Accept:` header); `InternalSpiffeRegistrationService` + `InternalSpiffeRevocationService` on **internal** mux (`internalAddr` block, **NOT** on external TLS endpoint per запрет #6).
> 6. `PRO-Robotech/kacho-deploy` — primary delivery repo:
>     - `helm/umbrella/Chart.yaml` adds dependencies `spire-server`, `spire-agent`, `cilium`;
>     - `helm/umbrella/values.{dev,prod}.yaml` — `cilium.{ebpf,kubeProxyReplacement,encryption{wireguard:true},hubble{enabled,relay,ui},authentication{mode:spiffe},serviceMesh{enabled:true}}`, `spire.{server{replicas:3,ha:postgres,trustDomain:kacho.cloud,ca{plugin:pkcs11,hsm:{provider:awsCloudHSM|softHSM2}}},agent{daemonset:true,attestors:[k8s_psat,cosign]}}`;
>     - `helm/umbrella/templates/spire-server-{statefulset,service,configmap,rbac,networkpolicy,podmonitor}.yaml`;
>     - `helm/umbrella/templates/spire-agent-{daemonset,configmap,rbac,podmonitor}.yaml`;
>     - `helm/umbrella/templates/cilium-network-policies/{kacho-iam,kacho-vpc,kacho-compute,kacho-loadbalancer,kacho-api-gateway}.yaml` — default-deny ingress + egress, then explicit allow per ServiceAccount;
>     - `helm/umbrella/templates/cilium-authorization-policies/*.yaml` — SPIFFE-ID-pattern-based authentication.mode=spiffe;
>     - `spire-registration/{kacho-iam,kacho-vpc,kacho-compute,kacho-loadbalancer,kacho-api-gateway}.yaml` — per-service SPIFFE-ID registrations with cosign signature selectors;
>     - `spire-registration/cosign-attestor-config.yaml` — cosign trusted-signers (kacho-platform team key + Fulcio root for OIDC keyless if enabled);
>     - `helm/umbrella/templates/hsm-pkcs11-secret.yaml` (External Secrets pulls AWS CloudHSM credentials);
>     - `helm/umbrella/templates/federation-bundle-ingress.yaml` — public Ingress `spire.kacho.cloud/federation/bundle` (Cloudflare-fronted in Phase 11);
>     - `Makefile` targets: `make spire-bootstrap`, `make spire-rotate-trust-domain`, `make cilium-policy-dry-run`.
> 7. `PRO-Robotech/kacho-ui` — minimal: `pages/admin/spiffe/{registrations-list,bundle-info,revoke-svid}.tsx` (read-only for non-admins, admin actions for `cluster.kacho-root.security_admin`); Hubble UI iframe link in admin observability panel.
> 8. `PRO-Robotech/kacho-test` — `tests/e2e/defense_in_depth_kac127.go` — forge end-user principal scenario; `tests/e2e/mesh_lateral_movement.go` — non-allowlisted pod denied; `tests/e2e/spire_failover.go` — primary SPIRE Server kill → SVID issuance continues from replicas.
> 9. `PRO-Robotech/kacho-workspace` — vault:
>     - `obsidian/kacho/KAC/KAC-127.md` (Phase 10 update),
>     - `obsidian/kacho/resources/iam-spiffe-registration.md` (new),
>     - `obsidian/kacho/resources/iam-trust-domain-bundle.md` (new),
>     - `obsidian/kacho/resources/iam-svid-revocation.md` (new),
>     - `obsidian/kacho/rpc/iam-federation-bundle-service.md` (new — public),
>     - `obsidian/kacho/rpc/iam-internal-spiffe-registration-service.md` (new — internal-only marked),
>     - `obsidian/kacho/rpc/iam-internal-spiffe-revocation-service.md` (new — internal-only marked),
>     - `obsidian/kacho/packages/corelib-spiffe.md` (new),
>     - `obsidian/kacho/edges/all-to-mesh-mtls.md` (new — Cilium eBPF auto-mTLS replaces direct service-to-service plaintext),
>     - `obsidian/kacho/edges/spire-agent-to-server.md` (new),
>     - `obsidian/kacho/edges/spire-server-to-hsm.md` (new),
>     - `obsidian/kacho/edges/all-to-spire-workload-api.md` (new — all kacho-* pods consume `/run/spire/sockets/agent.sock`),
>     - `obsidian/kacho/edges/kacho-iam-to-cosign-fulcio.md` (new, if keyless OIDC signing enabled).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 10 — **десятая код-генерирующая Phase** под KAC-127. На входе Phase 10 уже работает (от предшествующих Phase 1-9):

- **AuthN end-user** (Phase 2): Passkey + DPoP, `acr=3` step-up, JWT с `kacho_mfa_at` / `auth_time` / `amr` claims. JWT внутри пакетного трафика kacho-* services переносится в gRPC metadata header `x-kacho-end-user-principal` (forwarded api-gateway → backend → backend).
- **AuthZ** (Phase 3): OpenFGA `Check`/`ListObjects`; Conditions `jit_window`/`break_glass_window`; OPA Rego policy bundle distributed via OCI; `corelib/authz` экспортирует `Principal` struct.
- **External WIF** (Phase 5, Class B): `FederationExchangeService` для GitHub/AWS/GCP/GitLab. Это другой класс identity (external CI/CD runners) — **сосуществует** с Phase 10, не заменяется.
- **Audit + CAEP scaffolding** (Phase 1 schema): `audit_outbox` и `caep_outbox` tables и enum-типы существуют; drainer'ы появятся в Phase 8/9.
- **Service deployment baseline**: каждый kacho-* service deployed как Deployment + Service in Kubernetes, traffic между ними — plaintext HTTP/2 gRPC поверх ClusterIP + NetworkPolicy уровня L3/L4 (port-based). Это **базовая защита**, **которая Phase 10 заменяется** auto-mTLS поверх Cilium eBPF + SPIFFE SVID identity + L7 path-aware policies.

Phase 10 закладывает **in-cluster workload identity plane** во весь рост:

1. **SPIRE Server HA deploy** — 3 реплики StatefulSet в namespace `spire-system`, Postgres-backed DataStore (отдельная schema `spire_server` в shared k8s-Postgres, либо dedicated CloudSQL instance в prod), anti-affinity per node, leader election через k8s lease для CA signing operations (только leader подписывает; followers serve attestation reads). HSM-backed root CA: production использует AWS CloudHSM или GCP Cloud HSM через PKCS#11 plugin; dev/staging — SoftHSM2 в Secret (`hsm-pkcs11-credentials`).

2. **Trust domain** = `kacho.cloud` (статический; общий для всех env'ов одного cluster). SVID format: `spiffe://kacho.cloud/ns/<namespace>/sa/<service-account>` (per registration entry attestor selectors). Production trust-domain crypto **изолирован per cluster** — staging-cluster имеет свой trust domain `kacho.staging.cloud`, prod — `kacho.cloud`, **никакой shared trust** между env'ами.

3. **SPIRE Agent DaemonSet** — `spire-agent` pod на каждом node, mounts host-path `/run/spire/sockets/` (Workload API socket exposed to all pods on that node via hostPath volume), attestor primary = `k8s_psat` (projected SA token validated against k8s API), supplementary = `cosign` (image signature against trusted signers — kacho-platform team key или Fulcio root для keyless OIDC). SVID validity = **1 hour** (chosen as balance: short enough that revocation window is short, long enough to avoid cert churn); auto-rotation begins 30 minutes before expiry (50%-lifetime trigger per SPIFFE best practice).

4. **cosign image-signature selector as mandatory** — production-edition decision: **только signed images получают SVID**. Если pod запускает unsigned image (или signature не verifies против trusted signers) — SPIRE Agent reports `attestation failed: image signature missing/invalid`, SVID не выдаётся, pod может start (Kubernetes admission Phase 10 не блокирует — это Phase 11 / OPA gatekeeper area), но без SVID не может open mTLS-handshake → все его исходящие gRPC-вызовы fail at Cilium mesh layer (no mutual SPIFFE-ID exchange). **Это enforcement supply-chain integrity** на уровне runtime identity, не на уровне admission.

5. **Cilium eBPF service mesh** — Cilium v1.16+ as cluster CNI (replaces previous network plugin; **no backward-compat** with cluster booted on Calico/Flannel — Phase 10 includes greenfield Cilium install or migration runbook in Phase 11 runbooks). Service mesh enabled: `serviceMesh.enabled=true`, `authentication.mode=spiffe` — Cilium reads SVID via SPIRE Workload API, performs auto-mTLS between pods using SPIFFE-based peer auth, **without sidecar** (eBPF dataplane, kernel-level — lower latency + memory than Istio/Linkerd sidecar). Kube-proxy replaced by Cilium eBPF (`kubeProxyReplacement: strict`). WireGuard L3 encryption between nodes (defense-in-depth at node-to-node, independent of pod-to-pod mTLS).

6. **CiliumNetworkPolicy default-deny + explicit allow** — каждый namespace где живут kacho-* services получает:
   - default-deny ingress (никаких pod-to-pod connections без explicit allow);
   - default-deny egress (никаких outbound calls кроме явно разрешённых: DNS to kube-system/coredns, SPIRE Workload API socket — file-level, OpenTelemetry collector, peer kacho-* services per dependency graph);
   - explicit allow per ServiceAccount: `kacho-iam` ingress accepts from `{kacho-vpc, kacho-compute, kacho-loadbalancer, kacho-api-gateway}` ServiceAccount labels; `kacho-vpc` ingress accepts from `{kacho-compute, kacho-loadbalancer, kacho-api-gateway, kacho-vpc-implement}`; и т.д. per runtime cross-domain edges из workspace `CLAUDE.md`.
   - L7 HTTP path-based allow на чувствительных endpoints: `kacho-iam` `/v1/internal/*` paths accept only from `kacho-vpc`/`kacho-compute`/`kacho-loadbalancer` ServiceAccount; `/v1/internal/breakglass/*` accept only from `kacho-api-gateway-internal-mux` SPIFFE-ID; `/v1/admin/*` accept only from `kacho-ui-admin-sa` (с дополнительной L7 проверкой `Authorization` header presence — Cilium не сам валидирует JWT, но требует header non-empty).

7. **CiliumNetworkPolicy is SPIFFE-aware** — policies match on `authentication.mode: required` + peer SPIFFE-ID patterns:

   ```yaml
   spec:
     authentication:
       mode: "required"
     ingress:
       - fromEndpoints:
           - matchExpressions:
               - key: io.cilium.k8s.policy.spiffe-id
                 operator: In
                 values:
                   - "spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc"
                   - "spiffe://kacho.cloud/ns/kacho-system/sa/kacho-compute"
   ```

   Это **identity-based authz** на network plane (вне зависимости от L7 application authz через OpenFGA). Каскадная защита: Cilium policy denies wrong peer SVID → never reaches L7 → never reaches OpenFGA Check. Если каким-то путём прошло (mis-config) — OpenFGA Check на end-user principal'е всё равно denies (defense-in-depth).

8. **Federation bundle endpoint** — public read-only HTTPS endpoint `https://spire.kacho.cloud/federation/bundle` (Cloudflare-fronted Ingress в Phase 11; в Phase 10 — directly k8s Ingress + cert-manager Let's Encrypt staging cert). Format: per SPIFFE Federation spec — JSON `{"trust_domain":"kacho.cloud","spiffe_sequence":N,"spiffe_refresh_hint":300,"keys":[<JWKS keys>]}`. Permits external SPIFFE-aware systems (Phase 11 cross-cluster, external partners) to verify Kachō pod SVIDs. Bundle refreshed every 300s; rotation event пишется в `trust_domain_bundles` table с `sequence_number` monotonically incremented.

9. **Hubble observability** — Cilium Hubble enabled with Relay + UI; flows exported в OpenTelemetry collector (-> Tempo/Loki по Phase 11 stack). Flow telemetry показывает: source SPIFFE-ID, destination SPIFFE-ID, encryption status (mTLS yes/no), L7 verdict (если applicable), drop reason (если applicable). Alerts на сustom Hubble metrics: spike of `policy_drops` (>50/min on prod) → PagerDuty (lateral-movement attempt detection).

10. **Defense-in-depth: mesh mTLS + end-user authz** — fundamentally Phase 10 secures **service-to-service identity** (which kacho-* sent this request), но **NOT** end-user identity. End-user identity по-прежнему carried via gRPC metadata `x-kacho-end-user-principal` (signed JWT from Phase 2 AuthN), and per-RPC authz по-прежнему uses end-user principal в OpenFGA Check (per Phase 3 AuthZ). Compromise of one pod → attacker может call `kacho-iam.Internal.Get(folder_id=X)` от имени compromised pod's SPIFFE-ID, но **не может** forge `x-kacho-end-user-principal` JWT (unsigned/wrong-signed JWT rejected by `corelib/authn` interceptor) → end-user authz check fails → 403. **This is the critical test** in §6.8.

11. **GitOps registration entries** — `kacho-deploy/spire-registration/*.yaml` declares all SPIFFE-ID → selector mappings. Argo CD watches this directory, reconciles to SPIRE Server via `InternalSpiffeRegistrationService.Upsert` (idempotent). Adding/changing entry = git commit → PR → merge → Argo CD sync (within minutes). No manual `spire-server registration create` commands in production — auditable, reviewable, rollback-able.

12. **Emergency operations** — `InternalSpiffeRevocationService.RevokeSvid(svid_id)` для single compromised SVID revoke (CAEP push triggered); `RotateTrustDomain` для compromised root CA (rare, very expensive — invalidates all existing SVIDs, all pods need re-attestation; documented runbook в Phase 11 deliverables). Single SVID revoke completes within 30 seconds (SPIRE Server pushes update to all Agents within poll interval; new outbound mTLS handshakes from revoked SVID fail).

**Phase 10 НЕ включает** (это Phases 11-13 одного эпика — НЕ «deferred»):

- **Production multi-region deploy** + Cloudflare WAF + cross-region SPIRE federation — **Phase 11**. Phase 10 deploys SPIRE/Cilium in single-cluster (dev/staging/prod-eu-central separately, no cross-region federation). Phase 11 adds federation between prod-eu-central ↔ prod-eu-west trust domains.
- **OWASP ASVS L3 + chaos + pentest** — **Phase 12**. Phase 10 has integration tests (lateral movement, defense-in-depth, failover); chaos (Litmus killing SPIRE Server, Cilium agent) — Phase 12.
- **Vault closeout** (30+ files final state) — **Phase 13**.
- **CAEP push drainer** (Phase 8): Phase 10 writes rows to `caep_outbox` on SVID revoke / trust domain rotation, **drainer** wired to webhook subscribers — Phase 8.
- **Audit pipeline drainer** (Phase 9): Phase 10 writes admin events to `audit_outbox`, drainer ships to Kafka/ClickHouse/S3 — Phase 9.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace `CLAUDE.md`) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше остаётся `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать "yandex" | в коде / proto / Rego / Helm-values / Cilium policies / vault — не упоминается; SPIFFE-ID namespace `kacho.cloud` — pure brand; cosign trusted-signers — `kacho-platform-team` GPG key fingerprint, не sourced от yandex tooling |
| **Запрет #3** — НЕ ORM | `kacho_iam.spiffe_registrations`, `trust_domain_bundles`, `svid_revocations` доступаются только через handwritten pgx + sqlc-generated queries; `corelib/spiffe/` — pure stdlib + go-spiffe v2 (single permitted external SPIFFE library) |
| **Запрет #4** — НЕ каскад через границу сервиса | SVID revoke → CAEP push (downstream subscribers reactively re-fetch) НЕ cross-DB delete; trust-domain rotation invalidates SVID set в kacho_iam locally + emits caep event, downstream services pick up at next SVID refresh — нет cross-service cascade DELETE |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 10 миграция `0024_kac127_phase10_spiffe_registrations.sql` — **новая**, не правка `0011..0014` (Phase 1) |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | `InternalSpiffeRegistrationService` + `InternalSpiffeRevocationService` зарегистрированы **только** на internal mux api-gateway (`internalAddr`); external TLS `api.kacho.local:443` их НЕ видит; **public** `FederationBundleService` — на public mux (по-другому external SPIFFE consumers не смогут получить trust bundle) |
| **Запрет #7** — НЕ broker | SPIRE Agent ↔ Server communication — direct gRPC over mTLS (не Kafka/NATS); registration sync — Argo CD pull + internal RPC (не event bus); CAEP outbox — Postgres (Phase 8 drainer обрабатывает) |
| **Запрет #8** — DB-per-service | SPIFFE registration store — внутри `kacho_iam` (схема `spire_server` для SPIRE DataStore is separate technical schema но **same Postgres instance**); НЕ shared DB между kacho-iam и SPIRE Server (даже хоть и same cluster); pgBouncer separate users (`kacho_iam`, `spire_server`) с разными `search_path` |
| **Запрет #9** — async-only мутации | `InternalSpiffeRegistrationService.Upsert/Delete` → `Operation` (async; SPIRE Server propagates to Agents в течение ~10s); `RevokeSvid` → `Operation` (async; revocation propagates ~30s); `RotateTrustDomain` → `Operation` (long-running; 5-30 min); `FederationBundleService.Get` — sync read (просто SELECT текущего bundle row + JWKS render) |
| **Запрет #10** — within-service refs на DB-уровне | `spiffe_registrations.parent_id REFERENCES spiffe_registrations(id) ON DELETE RESTRICT` (entry parent chain); `svid_revocations.spiffe_id` индексируется + matched через partial UNIQUE для idempotent revoke; `trust_domain_bundles.sequence_number` имеет CHECK + `EXCLUDE USING gist` против overlapping `active_from..active_until` rows (sequence monotonicity invariant); state machine на revocations (`PENDING → PROPAGATING → COMPLETE`) — atomic conditional UPDATE с CAS на `status` |
| **Запрет #11** — тесты в том же PR | каждый PR Phase 10 содержит: kacho-proto — buf-lint + buf-breaking; corelib/spiffe — unit-tests с in-memory SVID source + integration smoke; kacho-iam — integration-tests testcontainer Postgres (registration entry CRUD race; trust-domain rotation atomic CAS; SVID revocation idempotency); kacho-deploy — `make cilium-policy-dry-run` зелёный + Newman E2E через api-gateway; kacho-test — e2e defense-in-depth + lateral-movement + failover scenarios |

### 1.1 Production-edition specifics (round 2 user feedback: no strict backward-compat)

- **No staged migration from plaintext mTLS to SPIFFE mTLS** — Phase 10 deploys как **all-or-nothing** в каждом environment (dev → staging → prod sequentially). Cluster cutover: switch CNI к Cilium + deploy SPIRE + redeploy всех kacho-* services с SPIFFE socket mount — **в одном release**. Не tolerated: «some services on SPIFFE, some not» (это создаёт mesh-edge cases где Cilium policy denies plaintext peer). Cutover window — maintenance window per env, expected downtime 5-15 min on staging, blue/green on prod (per Phase 11 runbook).
- **Old plaintext mTLS bootstrap removed** — все kacho-* services удаляют previous `grpcsrv.WithSelfSignedTLS()` / `grpcclient.WithInsecure()` paths; mandatory `grpcsrv.WithSpiffeMTLS()` / `grpcclient.WithSpiffeTransport()`. Service без SVID source не стартует (fail-closed); previously legitimate `localhost` testing patterns мигрируют на `corelib/spiffe/testing.go` in-memory SVID source.
- **Helm values no `spiffe.enabled: false` knob** — production-edition removes feature flag; SPIFFE on always after Phase 10 merge. Dev-cluster может использовать SoftHSM (helm value `spire.server.ca.plugin=memory` for ephemeral dev, BUT `hsm: pkcs11+softhsm2` for staging-replicating-prod).
- **cosign signature mandatory** — no `cosign.required: false` flag. Unsigned image deployment → pod runs но не получит SVID → all RPC fail → quick feedback for operators. (Alternative: OPA Gatekeeper admission deny — that's Phase 11.)

---

## 2. Глоссарий / доменная модель Phase 10 (нормативно)

### 2.1 Сущности, **созданные** в Phase 10

- **SPIFFEID** (типизированный value-object в `corelib/spiffe`):
  - Format: `spiffe://<trust-domain>/<path>`, где `<trust-domain>` = `kacho.cloud` (prod) / `kacho.staging.cloud` (staging) / `kacho.dev.cloud` (dev), `<path>` = `ns/<k8s-namespace>/sa/<service-account-name>` (canonical k8s pattern).
  - Examples: `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam`, `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc`, `spiffe://kacho.cloud/ns/spire-system/sa/spire-server` (special: SPIRE Server itself).
  - Self-validation: trust-domain non-empty, RFC-compliant URI chars only, path segments non-empty, total ≤2048 octets per SPIFFE spec.

- **SPIFFE Registration Entry** (`kacho_iam.spiffe_registrations` table — managed by kacho-iam, mirrored to SPIRE Server via internal sync):
  - `id TEXT PRIMARY KEY` (prefix `sreg_`),
  - `spiffe_id TEXT NOT NULL UNIQUE` (the SVID to issue),
  - `parent_id TEXT REFERENCES spiffe_registrations(id) ON DELETE RESTRICT NULLABLE` (attestation parent; null для root entries attested by SPIRE Agent itself),
  - `selectors JSONB NOT NULL` (array of `{type, value}` — e.g. `[{"type":"k8s","value":"ns:kacho-system"}, {"type":"k8s","value":"sa:kacho-iam"}, {"type":"cosign","value":"image-signature:<fingerprint>"}]`),
  - `ttl_seconds INT NOT NULL DEFAULT 3600 CHECK (ttl_seconds BETWEEN 60 AND 14400)` (SVID validity; 1h default, 4h max),
  - `federates_with TEXT[] DEFAULT '{}'` (other trust-domains this SVID can federate to; Phase 11 multi-cluster),
  - `admin BOOL NOT NULL DEFAULT false` (admin-flag entries — can mint other SVIDs; only for SPIRE Server / Agent SPIFFE-IDs),
  - `downstream BOOL NOT NULL DEFAULT false` (downstream-flag — can mint SVIDs for child workloads; SPIRE Agent only),
  - `dns_names TEXT[] DEFAULT '{}'` (optional dns SANs on X.509 SVID),
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `created_by TEXT REFERENCES users(id) NOT NULL` (Argo CD service account user OR admin user — audit trail),
  - `updated_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `revoked_at TIMESTAMPTZ` (soft-delete; entry removed from SPIRE Server but row retained for audit).
  - **Lifecycle**: ACTIVE (revoked_at IS NULL) → REVOKED (revoked_at set). Hard-delete only via emergency RotateTrustDomain operation.
  - **Mutable fields**: `selectors`, `ttl_seconds`, `federates_with`, `dns_names` (full re-write via Upsert).
  - **Immutable fields**: `spiffe_id`, `parent_id`, `created_at`, `created_by`, `admin`, `downstream` (last two — security-sensitive flags; once set, cannot change — must delete + recreate, which surfaces in audit).
  - **DB-уровень инварианты**: unique `spiffe_id`; FK `parent_id` ON DELETE RESTRICT (prevents accidental orphaning); CHECK on `ttl_seconds`; CHECK on `selectors` JSONB shape (array of `{type,value}` non-empty) via expression CHECK.

- **TrustDomainBundle** (`kacho_iam.trust_domain_bundles` table):
  - `id TEXT PRIMARY KEY` (prefix `tdb_`),
  - `trust_domain TEXT NOT NULL` (e.g. `kacho.cloud`),
  - `sequence_number BIGINT NOT NULL` (monotonically increasing; uses Postgres sequence `trust_domain_bundle_seq`),
  - `jwks JSONB NOT NULL` (JWKS-format key set),
  - `spiffe_bundle JSONB NOT NULL` (SPIFFE-bundle-spec format),
  - `refresh_hint_seconds INT NOT NULL DEFAULT 300`,
  - `active_from TIMESTAMPTZ NOT NULL`,
  - `active_until TIMESTAMPTZ NULLABLE` (NULL = current active bundle),
  - `created_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `created_by TEXT REFERENCES users(id) NOT NULL`.
  - **DB-уровень инварианты**:
    - UNIQUE `(trust_domain, sequence_number)`,
    - CHECK `(active_until IS NULL OR active_until > active_from)`,
    - partial UNIQUE `(trust_domain) WHERE active_until IS NULL` (только **один** active bundle per trust-domain at any time),
    - EXCLUDE USING gist (`trust_domain` WITH =, `tstzrange(active_from, COALESCE(active_until, 'infinity'))` WITH &&) — non-overlapping active windows enforcement.
  - Lifecycle: each rotation INSERTs new row + atomic UPDATE прежний row's `active_until = now()` (single transaction).

- **SvidRevocation** (`kacho_iam.svid_revocations` table):
  - `id TEXT PRIMARY KEY` (prefix `srev_`),
  - `spiffe_id TEXT NOT NULL`,
  - `serial TEXT NOT NULL` (X.509 SVID cert serial number; combo with spiffe_id is unique-per-issued-cert),
  - `reason TEXT NOT NULL CHECK (reason IN ('SUPERSEDED','KEY_COMPROMISE','CESSATION_OF_OPERATION','EMERGENCY_ROTATION','UNSPECIFIED'))`,
  - `revoked_at TIMESTAMPTZ NOT NULL DEFAULT now()`,
  - `revoked_by TEXT REFERENCES users(id) NOT NULL`,
  - `status TEXT NOT NULL CHECK (status IN ('PENDING','PROPAGATING','COMPLETE','FAILED')) DEFAULT 'PENDING'`,
  - `propagation_started_at TIMESTAMPTZ`,
  - `propagation_completed_at TIMESTAMPTZ`,
  - `caep_outbox_event_id TEXT REFERENCES caep_outbox(event_id) NULLABLE` (link to CAEP push event для downstream subscriber notification).
  - **DB-уровень инварианты**:
    - partial UNIQUE `(spiffe_id, serial) WHERE status <> 'FAILED'` (idempotent revoke — already-revoked-or-propagating cert can't be revoked again, but failed attempts retry-able),
    - state machine atomic CAS: `UPDATE … SET status='PROPAGATING', propagation_started_at=now() WHERE id=$1 AND status='PENDING' RETURNING …`; same pattern для PROPAGATING→COMPLETE.

### 2.2 Сущности, **переиспользуемые / расширяемые** в Phase 10

- **corelib/authz.Principal** (from Phase 3) — extends с optional `MeshCaller *spiffe.ID` поле:
  - Populated by `corelib/spiffe.MeshInterceptor` (gRPC server interceptor) on entry — extracts peer cert chain via `peer.FromContext(ctx)`, parses URI SAN, validates trust domain, sets `Principal.MeshCaller`.
  - **NOT used** для end-user authz — `MeshCaller` purely for service-identity audit logging + Cilium policy backstop. End-user authz keeps using `Principal.ID` (the JWT `sub`).
  - If `MeshCaller` is `nil` on a request reaching backend service → indicates plaintext bypass attempt or test mode; production-mode rejects with `Unauthenticated` `mesh peer identity required`.

- **caep_outbox** (Phase 1) — gains new event-types: `iam.spiffe.svid.revoked`, `iam.spiffe.registration.updated`, `iam.spiffe.trust_domain.rotated` (all with payload schemas defined in `kacho-proto/proto/kacho/iam/caep/v1/spiffe_events.proto`).

- **audit_outbox** (Phase 1) — gains new event-types: `iam.spiffe.registration.created/updated/deleted/upserted` (with diff before/after), `iam.spiffe.svid.revoked`, `iam.spiffe.trust_domain.rotated`, `iam.spiffe.bundle.refreshed` (informational, every 5 min).

### 2.3 SPIFFE-ID assignment table (Phase 10 canonical)

| Pod | k8s namespace | k8s ServiceAccount | SPIFFE-ID | Selectors |
|---|---|---|---|---|
| kacho-iam | `kacho-system` | `kacho-iam` | `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam` | `k8s:ns:kacho-system`, `k8s:sa:kacho-iam`, `cosign:<kacho-platform-fingerprint>` |
| kacho-vpc | `kacho-system` | `kacho-vpc` | `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc` | `k8s:ns:kacho-system`, `k8s:sa:kacho-vpc`, `cosign:<kacho-platform-fingerprint>` |
| kacho-compute | `kacho-system` | `kacho-compute` | `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-compute` | similar |
| kacho-loadbalancer | `kacho-system` | `kacho-loadbalancer` | `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-loadbalancer` | similar |
| kacho-api-gateway | `kacho-system` | `kacho-api-gateway` | `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-api-gateway` | similar |
| kacho-ui (admin-tooling) | `kacho-system` | `kacho-ui-admin` | `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-ui-admin` | similar |
| kacho-vpc-implement | `kacho-system` | `kacho-vpc-implement` | `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc-implement` | similar |
| spire-server | `spire-system` | `spire-server` | `spiffe://kacho.cloud/ns/spire-system/sa/spire-server` | bootstrap (special; admin=true) |
| spire-agent | `spire-system` | `spire-agent` | `spiffe://kacho.cloud/ns/spire-system/sa/spire-agent` | bootstrap (special; downstream=true) |

### 2.4 Cilium policy assignment (Phase 10 canonical — derived from workspace `CLAUDE.md` cross-domain edges)

| Service | Ingress allowed from (SPIFFE-IDs) | Egress allowed to (SPIFFE-IDs) | L7 path-specific |
|---|---|---|---|
| **kacho-iam** | kacho-vpc, kacho-compute, kacho-loadbalancer, kacho-api-gateway, kacho-ui-admin | None (leaf-owner) | `/v1/internal/*` from {vpc, compute, loadbalancer} only; `/v1/internal/breakglass/*` from api-gateway only; `/v1/admin/*` requires `Authorization` header non-empty |
| **kacho-vpc** | kacho-compute (NIC validation), kacho-loadbalancer (subnet refs), kacho-api-gateway (public RPC proxy), kacho-vpc-implement (write-back ReportNiDataplane) | kacho-iam (ProjectService.Get + InternalIAMService.Check), kacho-compute (zone validation) | `/v1/internal/networkInterfaces/*/reportDataplane` from kacho-vpc-implement only |
| **kacho-compute** | kacho-vpc (zone fetch), kacho-loadbalancer (instance refs), kacho-api-gateway | kacho-iam (Project + Check), kacho-vpc (Subnet/SecurityGroup validation + ephemeral address IPAM) | `/v1/internal/hypervisors/*` from kacho-vpc-implement only |
| **kacho-loadbalancer** | kacho-api-gateway | kacho-iam (Project + Check), kacho-vpc (Subnet refs), kacho-compute (Instance health-check) | — |
| **kacho-api-gateway** | external (Ingress via Cloudflare in Phase 11; в Phase 10 — k8s Ingress with Let's Encrypt), kacho-ui (browser → CDN → api-gateway) | All kacho-* backend services | external-mux only: public RPCs; internal-mux only: Internal* RPCs (port 9091) |
| **kacho-vpc-implement** | spire-agent (Workload API socket file-level) | kacho-vpc (InternalNetworkInterfaceService.ReportNiDataplane), kacho-compute (InternalHypervisorService) | — |
| **All kacho-***  | spire-agent socket (hostPath; not network) | otel-collector (telemetry); kube-dns | — |

---

## 3. Decision Log (Phase 10)

### P10-D1: SPIRE Server HA = 3 replicas Postgres-backed (not in-memory, not 1-replica)

**Decision**: 3 StatefulSet replicas; Postgres DataStore (`spire_server` schema in shared kacho-Postgres cluster on staging/prod; dev может memory store); anti-affinity per node (3-node-cluster minimum); leader election via k8s `coordination.k8s.io/Lease` для CA signing.

**Rationale**:
- 1-replica = SPOF; cluster-wide outage if SPIRE Server down (no new SVIDs, existing SVIDs continue until expiry — но within 1h all pods lose mTLS).
- 3 replicas с anti-affinity per node — survives single-node failure без service interruption; majority quorum for leader-elect.
- Postgres-backed (not in-memory) — entries persist через restart; required для production audit/compliance (entry CRUD audit trail).
- shared Postgres cluster (с kacho-iam) на dev/staging для cost; separate CloudSQL HA instance на prod (Phase 11 sets up).

**Alternatives considered**: SPIRE Server in-memory (rejected — restart loses all registration entries); 2-replica (rejected — no quorum for leader-elect on 1-failure); 5-replica (rejected — overkill для 5-10 kacho-* services + ~50 pods scale).

### P10-D2: No backward-compat with plaintext mTLS (round 2 user feedback)

**Decision**: Phase 10 merge **removes** all plaintext fallback paths из corelib/grpcsrv + corelib/grpcclient. After Phase 10 deployed, **only** SPIFFE mTLS is supported. Cutover в каждом env — atomic (всё или ничего).

**Rationale**: Mixed-mode mesh (some pods on SPIFFE, others plaintext) creates Cilium policy edge cases где `authentication.mode=required` denies plaintext peer — unpredictable failures during migration window. Production-edition prefers brief downtime (5-15 min on staging) над long mixed-mode chaos.

**Alternatives considered**: Feature flag `spiffe.enabled: true|false` per service (rejected — testing matrix explodes, security-critical code paths can't be gated by config). Gradual per-namespace rollout (rejected — kacho-* all live in `kacho-system` ns).

### P10-D3: Trust domain = `kacho.cloud` per cluster (no shared cross-env trust)

**Decision**: Each cluster (`dev`, `staging`, `prod-eu-central`) has own trust domain (`kacho.dev.cloud`, `kacho.staging.cloud`, `kacho.cloud`). Cross-cluster federation = explicit per-pair federation bundle exchange (Phase 11+).

**Rationale**: Different envs must not be able to attest each other's pods (preventing staging-leak-to-prod). Same trust domain across envs = same root CA = compromise in dev compromises prod. Per-env trust domain = strict isolation.

**Alternatives considered**: Single `kacho.cloud` trust domain across all envs (rejected — security regression); per-namespace trust domain in single cluster (rejected — too granular, SPIFFE spec defines trust domain as security boundary).

### P10-D4: Root CA in HSM (PKCS#11) — production-mandatory; SoftHSM acceptable dev/staging

**Decision**: `spire.server.ca.plugin = pkcs11` always in production; backed by AWS CloudHSM (region eu-central-1) or GCP Cloud HSM (depending on cluster). Dev/staging — `softhsm2` PKCS#11 software impl backed by k8s Secret (acceptable since data not classified PII).

**Rationale**: Compliance (SOC 2 Type II, ISO 27001) requires root CA private keys never leave HSM boundary. SPIRE Server's `pkcs11` plugin loads/signs without ever exporting key. SoftHSM provides same PKCS#11 API for dev — same code path tested, fewer surprises.

**Alternatives considered**: Disk-based key (rejected — non-compliant); HashiCorp Vault Transit (rejected — adds operational dependency, slower SVID signing).

### P10-D5: Cilium eBPF (no sidecar) — service mesh

**Decision**: Cilium v1.16+, `kubeProxyReplacement: strict`, `serviceMesh.enabled: true`, `authentication.mode: spiffe`. No Istio, no Linkerd, no Envoy sidecar.

**Rationale**:
- Sidecar mesh adds ~50-200ms p99 latency overhead per hop (Envoy proxy parse + emit per request); eBPF is kernel-level, ~0.1-1ms overhead.
- Memory overhead: sidecar = 50-200MB per pod × ~50 pods = 2.5-10GB; eBPF = ~50MB total (cilium-agent on each node).
- Cilium has first-class SPIFFE integration (`authentication.mode: spiffe` directly consumes SPIRE Workload API); Istio + SPIRE requires `spire-istio-bridge` extra component.
- Single product (CNI + mesh + policy + observability) reduces operational surface.

**Alternatives considered**: Istio + SPIRE (rejected — sidecar overhead, extra component); Linkerd (rejected — does not natively consume SPIFFE SVIDs; uses own identity model); Cilium without mesh + manual mTLS in code (rejected — burden on every service, no L7 policy).

### P10-D6: WireGuard L3 encryption between nodes — defense-in-depth

**Decision**: Cilium `encryption.type: wireguard` enabled. All node-to-node traffic L3-encrypted, independent of pod-to-pod mTLS at L7.

**Rationale**: Mesh mTLS protects pod-to-pod L7 RPC. WireGuard protects **all** node-to-node L3 traffic (including kubelet ↔ API server, etcd peer traffic, host network traffic). Two independent crypto layers = defense-in-depth (compromise of one doesn't compromise other).

**Alternatives considered**: IPSec (rejected — operationally heavier, slower handshake); no L3 encryption (rejected — leaves kubelet/API server traffic on cluster network unencrypted, which is unacceptable in multi-tenant cluster).

### P10-D7: SVID validity = 1 hour; auto-rotated 30 min before expiry

**Decision**: `ttl_seconds = 3600` default; SPIRE Agent triggers rotation at 50% lifetime = 30 min before expiry. Pod sees seamless cert rotation via `corelib/spiffe.workloadapi.Client` (in-memory swap, no restart).

**Rationale**: 1h balances (a) compromise window (revocation propagates within 30s, so worst-case unrevoked-but-compromised SVID lives ≤30s + propagation delay), (b) cert churn (rotating every 1h = ~24 rotations/day per pod = ~1200/day across 50 pods — manageable for SPIRE Server). 30-min-before-expiry rotation avoids any user-facing failure from cert expiry.

**Alternatives considered**: 15 min (rejected — excessive churn on SPIRE Server, ~5000 rotations/day per 50 pods); 24 h (rejected — compromise window too long; revocation depends on Agent poll интервал, can be hours).

### P10-D8: GitOps registration entries via Argo CD

**Decision**: All `spiffe_registrations` entries declared в `kacho-deploy/spire-registration/*.yaml`. Argo CD reconciles to SPIRE Server via internal RPC (`InternalSpiffeRegistrationService.Upsert`).

**Rationale**: Auditable (git history shows who added/changed entry), reviewable (PR process), rollback-able (revert PR), no `spire-server registration create` ad-hoc commands в production (which would skip audit).

**Alternatives considered**: SPIRE Controller Manager (operator) reading CRDs directly (rejected — adds another operator; preferred to keep entry CRUD in kacho-iam for unified audit); manual CLI commands (rejected — no audit trail).

### P10-D9: k8s_psat attestor primary; cosign image-signature mandatory selector

**Decision**: Each Agent attests workloads via `k8s_psat` (projected SA token validated against k8s API) AND requires matching `cosign:<fingerprint>` selector. Both must match for SVID issuance.

**Rationale**: `k8s_psat` provides "this pod really is k8s SA X" (control plane attestation); `cosign` provides "this image really was signed by trusted signer" (supply-chain attestation). Combined = "this pod is k8s SA X running trusted image" — required for production identity.

**Alternatives considered**: `k8s_sat` (old, non-projected — wider trust, deprecated); `k8s_psat` alone (rejected — doesn't address supply-chain; unsigned image of k8s SA X gets SVID); cosign alone (rejected — doesn't bind to k8s identity; signed image can claim any SA).

### P10-D10: cosign trusted signers — kacho-platform team key + optional Fulcio root for keyless OIDC

**Decision**: Production primary = kacho-platform team's PGP/cosign key (offline-stored, rotated annually); optional secondary = Fulcio root CA for keyless OIDC (cosign sign-blob with GitHub Actions OIDC) — used for non-production builds during transition.

**Rationale**: Hardware-rooted key = strongest supply-chain assurance; keyless OIDC = convenience for non-prod CI runs. Production deploys MUST use offline-key-signed builds (Phase 11 CI gating).

**Alternatives considered**: Keyless OIDC only (rejected for prod — depends on Sigstore Fulcio uptime + OIDC issuer; offline key is more resilient); private CA chain (rejected — operational complexity).

### P10-D11: CiliumNetworkPolicy default-deny ingress + egress; explicit allow per SPIFFE-ID + SA label

**Decision**: Each `kacho-system` namespace deploys (a) default-deny CNP per pod-label, (b) explicit allow CNPs per service per CiliumNetworkPolicy `authentication.mode: required` + peer SPIFFE-ID matchers.

**Rationale**: Default-deny posture (security industry standard); explicit allow per peer SPIFFE-ID (identity-based, не IP/CIDR-based which mutates with pod restart).

**Alternatives considered**: Default-allow + explicit deny (rejected — fail-open is wrong default for security); per-namespace allow + explicit cross-namespace deny (rejected — all kacho-* in same namespace anyway).

### P10-D12: AuthorizationPolicy SPIFFE-ID-based — uses CiliumNetworkPolicy + L7 rules (no separate "AuthorizationPolicy" CRD)

**Decision**: Cilium combines L3/L4 network policy + L7 HTTP/gRPC policy в single `CiliumNetworkPolicy` CRD. Не используем Istio `AuthorizationPolicy` CRD (no Istio installed). Naming в Helm: `cilium-authorization-policies/*.yaml` файлы — это **CiliumNetworkPolicy** resources, name reflects their authz purpose.

**Rationale**: Reduce CRD count; single Cilium-managed CRD type; simpler reconciliation. Cilium `toEndpoints + toHTTP + auth=spiffe` covers same use case as Istio `AuthorizationPolicy`.

**Alternatives considered**: Install Istio just for `AuthorizationPolicy` CRD (rejected — adds Istio operational surface for one CRD); custom CRD (rejected — reinvention).

### P10-D13: L7 path-based allowlist for sensitive endpoints

**Decision**: CiliumNetworkPolicy specifies L7 HTTP `pathRegex` allowlist для `/v1/internal/*`, `/v1/admin/*` per service per peer SPIFFE-ID. Other paths default-allowed-if-mTLS-passed-and-L4-allowed.

**Rationale**: Cilium policy enforces L7 verbs (GET/POST/PUT/DELETE) + path regex. Compromised peer with valid SVID for `kacho-vpc` can still NOT reach `/v1/internal/breakglass/*` because that's L7-restricted to api-gateway-internal-mux SPIFFE-ID.

**Alternatives considered**: All-L7-or-no-L7 (rejected — too coarse-grained); L7 in every policy (rejected — performance overhead for non-sensitive paths).

### P10-D14: Federation bundle endpoint = public HTTPS (Ingress + cert-manager Let's Encrypt)

**Decision**: `https://spire.kacho.cloud/federation/bundle` (Ingress в production-namespace; cert-manager Let's Encrypt automated TLS; Cloudflare-fronted in Phase 11). Bundle format = SPIFFE Federation v1.

**Rationale**: External SPIFFE consumers need plain HTTPS endpoint (not gRPC) per SPIFFE Federation spec. Public — no auth needed (bundle is public crypto material).

**Alternatives considered**: gRPC-only endpoint (rejected — non-standard); inside cluster only (rejected — defeats federation purpose).

### P10-D15: Defense-in-depth: mesh mTLS + end-user authz (independent layers)

**Decision**: Mesh mTLS confirms service-to-service identity; end-user authz via OpenFGA `Check` continues to use `corelib/authz.Principal.ID` (end-user JWT `sub`). **Both** must pass for sensitive operations.

**Rationale**: Compromise of one pod (full root inside container) → attacker can mint requests as that pod's SPIFFE-ID, but cannot forge end-user JWT (signed by Hydra/Kratos with HSM-backed key). End-user authz fails → operation denied. Critical test in §6.8.

**Alternatives considered**: Mesh-only authz (rejected — compromise of one pod = compromise of all access of that pod, including end-user-impersonation); end-user-only authz (rejected — loses defense-in-depth, doesn't detect lateral movement).

### P10-D16: Hubble observability — flows to OpenTelemetry + Hubble UI for SOC

**Decision**: Cilium Hubble enabled (`hubble.enabled: true`, `hubble.relay.enabled: true`, `hubble.ui.enabled: true`); Hubble export to OpenTelemetry collector (-> Loki в Phase 11 stack); Hubble UI accessible via admin port-forward / Ingress в Phase 11.

**Rationale**: Flow telemetry показывает realtime source/dest SPIFFE-IDs + verdict + encryption status — critical для SOC monitoring lateral movement attempts. Alert на `policy_drops > 50/min` → PagerDuty.

**Alternatives considered**: No Hubble (rejected — loses critical observability); Hubble metrics only (rejected — drops UI which is valuable for incident response).

### P10-D17: HSM unavailable = SPIRE Server fail-closed for new SVID issuance; existing SVIDs continue

**Decision**: If PKCS#11 endpoint unreachable, SPIRE Server returns error on new attestation requests; existing SVIDs continue to be valid until expiry (max 1h); SPIRE Server emits alert (Hubble + PagerDuty).

**Rationale**: Fail-closed for new issuance (prevents downgrade attack via HSM outage); fail-open for existing SVIDs (avoids cluster-wide outage during HSM blip). Operations: HSM outage runbook — Phase 11 deliverable.

**Alternatives considered**: Hard-fail all SVIDs immediately (rejected — cluster outage from HSM blip); cached signing key in SPIRE Server memory (rejected — breaks HSM boundary, key never should leave HSM).

### P10-D18: SVID revocation propagates ≤30s; CAEP push triggered

**Decision**: `RevokeSvid` operation completes within 30s p99 — SPIRE Server adds serial to CRL, pushes to all Agents in next poll cycle (default 5s), Agents reject SVID at next mTLS handshake. CAEP event `iam.spiffe.svid.revoked` pushed to subscribers.

**Rationale**: 30s p99 = compromise window for already-issued-but-now-revoked SVID. Faster requires reducing Agent poll interval (CPU cost on Server). 30s acceptable per security threat model (compromise detection latency typically much higher).

**Alternatives considered**: 1s revocation (rejected — Agent poll cost); 5min revocation (rejected — compromise window too long).

### P10-D19: Trust domain rotation = emergency runbook operation (rare, expensive)

**Decision**: `RotateTrustDomain` operation invalidates entire trust domain key material; all kacho-* services lose mTLS until they re-attest and get new SVIDs (~5-30 min total propagation). Documented runbook (Phase 11). Cause: root CA key compromise.

**Rationale**: Trust domain rotation is recovery-from-compromise procedure. Must be possible (otherwise compromised key can't be revoked); must be rare (high disruption). Phase 10 implements the RPC + atomic DB transaction; Phase 11 documents the runbook + chaos-tests it.

### P10-D20: All RPC mutations return Operation (запрет #9) — even SPIRE admin

**Decision**: `InternalSpiffeRegistrationService.Upsert/Delete`, `InternalSpiffeRevocationService.RevokeSvid/RotateTrustDomain` all return `kacho.cloud.operation.v1.Operation`. Sync read `FederationBundleService.Get`.

**Rationale**: Consistency with rest of Kachō API (запрет #9 — all mutations async); operation tracking enables retries, observability, audit; SPIRE Server propagation is inherently async (CRL update, Agent re-sync).

### P10-D21: Internal SPIRE admin RPCs registered on internal mux only (запрет #6)

**Decision**: `InternalSpiffeRegistrationService` + `InternalSpiffeRevocationService` on api-gateway internal mux (`internalAddr`, port 9091); NOT on external TLS endpoint `api.kacho.local:443`. `FederationBundleService.Get` (read-only public bundle) — on public mux.

**Rationale**: SPIRE admin (registration/revocation) is operational control plane; exposing on external API surface = attack surface expansion. Public bundle endpoint is necessary (external SPIFFE consumers need it) and contains only public crypto material.

### P10-D22: kacho-iam owns SPIRE registration store (not direct SPIRE Server DataStore)

**Decision**: `kacho_iam.spiffe_registrations` is **source of truth**; kacho-iam pushes to SPIRE Server via SPIRE Server's own admin API (`spire-server entry create/update/delete`) on Upsert/Delete RPC. SPIRE Server DataStore (Postgres `spire_server` schema) — secondary, кажется eventual-consistent с kacho-iam.

**Rationale**: Centralizes auditing (`audit_outbox` in kacho-iam captures all registration changes); centralizes RBAC (only `cluster.kacho-root.security_admin` can mutate via internal RPC); enables GitOps via Argo CD reconciling to kacho-iam, not to SPIRE Server directly.

**Alternatives considered**: SPIRE Server DataStore as source of truth (rejected — audit gap, no centralized RBAC); CRDs with operator (rejected — adds operator dependency).

### P10-D23: cosign verification at SPIRE Agent attestor (not at admission)

**Decision**: SPIRE Agent's cosign attestor plugin verifies image signature at pod attestation time (before SVID issuance). Pod без cosign signature does NOT get SVID; without SVID, mesh mTLS fails; effectively unsigned pods cannot communicate.

**Rationale**: Admission-time gating (OPA Gatekeeper) is Phase 11 (parallel control); Phase 10's runtime-identity gate provides immediate fail-fast feedback. Bonus: covers case where image is tampered after admission (signature still verified each attestation).

**Alternatives considered**: Admission-only (rejected — runtime tampering not detected); both (combined in Phase 11; Phase 10 sets runtime baseline).

### P10-D24: SPIFFE Workload API socket = hostPath volume mount (not network)

**Decision**: Each kacho-* pod mounts `/run/spire/sockets/agent.sock` from host hostPath; that's how SPIRE Agent (DaemonSet, one per node) communicates with workloads on that node. No TCP networking for Workload API.

**Rationale**: hostPath socket = no network overhead, automatic per-node attestation (Agent on same node knows pod via local k8s API + cgroup inspection), standard SPIFFE pattern.

### P10-D25: Per-cluster trust domain naming; no global "kacho.cloud" sharing across envs

**Decision**: `kacho.cloud` = prod-eu-central, `kacho.staging.cloud` = staging, `kacho.dev.cloud` = dev. Same `corelib/spiffe` code, different trust-domain config per env.

**Rationale**: Per P10-D3 above — security isolation between envs. Code paths identical (parameterized by env var `KACHO_TRUST_DOMAIN`); only Helm value differs.

---

## 4. Architecture diagram (Phase 10 in-cluster mesh)

```
                         ┌──────────────────────────────────────────────────────────────────┐
                         │                                                                    │
                         │   spire-system namespace (3-node anti-affinity, dedicated)         │
                         │                                                                    │
                         │   ┌────────────────────┐    ┌────────────────────┐                 │
                         │   │  SPIRE Server #1   │◄──►│  SPIRE Server #2   │   StatefulSet   │
                         │   │  (leader; signs)   │    │  (follower; reads) │   anti-affinity │
                         │   └────────┬───────────┘    └─────────┬──────────┘                 │
                         │            │                          │                            │
                         │            │  ┌────────────────────┐  │                            │
                         │            ├─►│  SPIRE Server #3   │◄─┤   Postgres DataStore       │
                         │            │  │  (follower; reads) │  │   (schema: spire_server)   │
                         │            │  └────────────────────┘  │                            │
                         │            │                          │                            │
                         │            ▼                          ▼                            │
                         │   ┌────────────────────────────────────────────┐                   │
                         │   │   HSM (AWS CloudHSM / GCP Cloud HSM)       │                   │
                         │   │   PKCS#11 plugin; trust-domain root CA     │                   │
                         │   └────────────────────────────────────────────┘                   │
                         │                                                                    │
                         │   ┌────────────────────────────────────────────────────────┐       │
                         │   │   SPIRE Agent DaemonSet (one per node)                  │       │
                         │   │   Attestors: k8s_psat + cosign                          │       │
                         │   │   Workload API socket: /run/spire/sockets/agent.sock    │       │
                         │   └────────────────────────────────────────────────────────┘       │
                         │            ▲              ▲              ▲                          │
                         └────────────┼──────────────┼──────────────┼──────────────────────────┘
                                      │ attest       │ attest       │ attest
                                      │ + rotate     │ + rotate     │ + rotate
                                      │ SVID         │ SVID         │ SVID
                                      ▼              ▼              ▼
              ┌────────────────────────────────────────────────────────────────────────────┐
              │   kacho-system namespace                                                    │
              │                                                                             │
              │   ┌──────────┐  mTLS via   ┌──────────┐    mTLS via    ┌──────────────┐    │
              │   │ kacho-   │◄═══════════►│ kacho-   │◄══════════════►│ kacho-iam    │    │
              │   │ api-     │  SPIFFE     │ vpc      │  SPIFFE        │ (leaf-owner) │    │
              │   │ gateway  │  SVID       │          │  SVID          │              │    │
              │   └──────────┘             └──────────┘                └──────────────┘    │
              │      ▲                          ▲                            ▲              │
              │      │ Cilium L7                │ Cilium L7                  │ Cilium L7    │
              │      │ pathRegex                │ pathRegex                  │ pathRegex    │
              │      │ /v1/internal/*           │ /v1/internal/*             │ /v1/internal │
              │      │                          │                            │ /breakglass/ │
              │      │                          │                            │ * api-gw     │
              │      │                          │                            │ only         │
              │      │                          │                            │              │
              │   ┌──┴───────┐             ┌────┴─────┐                ┌────┴─────────┐    │
              │   │ kacho-   │             │ kacho-   │                │ kacho-       │    │
              │   │ compute  │═════════════│ load-    │                │ vpc-         │    │
              │   │          │  mTLS       │ balancer │                │ implement    │    │
              │   └──────────┘             └──────────┘                └──────────────┘    │
              │                                                                             │
              │   (All pods: Cilium eBPF dataplane; auto-mTLS using SVID;                  │
              │    CiliumNetworkPolicy default-deny ingress + egress;                       │
              │    explicit allow per peer SPIFFE-ID label + L7 path)                       │
              └─────────────────────────────────────────────────────────────────────────────┘
                                                │
                                                │  Hubble flows
                                                ▼
              ┌──────────────────────────────────────────────────────────────────┐
              │   Cilium Hubble Relay → OpenTelemetry Collector → Loki/Tempo     │
              │   (Phase 11 stack; Phase 10 just enables Hubble Relay/UI)         │
              │   Drops > 50/min → PagerDuty (lateral-movement detector)         │
              └──────────────────────────────────────────────────────────────────┘

  ┌───────────────────────────────────────────────────────────────────┐
  │  Public HTTPS endpoint: https://spire.kacho.cloud/federation/    │
  │  bundle                                                            │
  │  ─ served by FederationBundleService (kacho-iam read-only public) │
  │  ─ format: SPIFFE Federation v1 JSON (JWKS + spiffe_sequence)     │
  │  ─ refreshed every 300s; rotated on trust-domain rotation         │
  │  ─ external consumers (Phase 11 cross-cluster, partners) verify   │
  │    Kachō pod SVIDs                                                 │
  └───────────────────────────────────────────────────────────────────┘
```

### 4.1 SVID issuance flow (sequence)

```
Pod starts (kacho-vpc replicas-0 in ns kacho-system)
   │
   │ (1) Kubelet creates pod; sets up hostPath volume mount /run/spire/sockets
   │
   ▼
Pod process starts; corelib/spiffe.NewWorkloadAPIClient(socket="/run/spire/sockets/agent.sock")
   │
   │ (2) gRPC call WorkloadAPI.FetchX509SVID to SPIRE Agent on same node
   │
   ▼
SPIRE Agent receives request from local socket
   │
   │ (3) Agent inspects cgroup/PID → k8s pod metadata → SA name "kacho-vpc"
   │ (4) Agent runs k8s_psat attestor: fetches projected SA token → validates against k8s API
   │ (5) Agent runs cosign attestor: fetches image digest → verifies signature against trusted signers
   │ (6) Agent forwards selectors [k8s:ns:kacho-system, k8s:sa:kacho-vpc, cosign:<fp>] to SPIRE Server
   │
   ▼
SPIRE Server (leader)
   │
   │ (7) Server matches selectors against spiffe_registrations.selectors
   │ (8) Match found → spiffe_id = spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc
   │ (9) Server requests HSM (PKCS#11) to sign X.509 SVID (CN=spiffe-id, validity=1h)
   │ (10) Server returns SVID + bundle to Agent
   │
   ▼
SPIRE Agent caches SVID locally; serves to pod via Workload API
   │
   │ (11) corelib/spiffe.workloadapi.Client receives SVID; updates internal X509Source
   │ (12) Pod's gRPC server (TLS) uses dynamic cert provider — next handshake serves SVID
   │
   ▼
Pod gRPC server ready; mesh-mTLS handshakes succeed
```

---

## 5. Декомпозиция работ (Phase 10)

| Repo | Subtask | Plan task | Estimated PR size (LOC) |
|---|---|---|---|
| kacho-proto | new `kacho.iam.v1.FederationBundleService` + `InternalSpiffeRegistrationService` + `InternalSpiffeRevocationService` + `kacho.iam.caep.v1.SpiffeEvents` | 10.1 + 10.6 spec | ~500 LOC proto |
| kacho-corelib | new `corelib/spiffe/` package (workloadapi.go, interceptor.go, client.go, verifier.go, testing.go) | 10.2 prep | ~800 LOC + tests |
| kacho-iam | new `internal/apps/kacho/api/spiffe/*` + migration `0024` + domain + repo | 10.6 + entry CRUD impl | ~1500 LOC + tests |
| kacho-vpc | wire `corelib/spiffe` into grpcsrv + grpcclient; remove plaintext bootstrap | 10.7 | ~300 LOC delta + tests |
| kacho-compute | same | 10.7 | ~300 LOC delta + tests |
| kacho-loadbalancer | same | 10.7 | ~300 LOC delta + tests |
| kacho-api-gateway | same + register Internal services on internal mux | 10.7 + 10.6 | ~400 LOC delta + tests |
| kacho-deploy | helm umbrella chart deps (cilium, spire-server, spire-agent) + values.dev/prod + templates + registration manifests | 10.2 + 10.3 + 10.4 + 10.5 | ~2500 LOC YAML |
| kacho-ui | admin SPIFFE pages (read + revoke) | 10.7 add | ~400 LOC |
| kacho-test | e2e: defense-in-depth, lateral movement, failover | 10.8 | ~600 LOC |
| kacho-workspace | vault: 10+ new files | 10.9 close | ~30KB total |

Total estimate: **8000-10000 LOC + 30KB vault** across 11 repos.

---

## 6. Given-When-Then Scenarios

### 6.1 SPIRE Server HA deployment (5 scenarios)

#### Scenario S10.1.1: SPIRE Server 3-replica cold-start с Postgres DataStore

**ID**: S10.1.1

**Given**:
- Kubernetes cluster (3-node minimum) with namespace `spire-system` ready
- Postgres instance with schema `spire_server` created, user `spire_server` granted CRUD на schema
- Helm release `spire-server` not yet deployed
- HSM (SoftHSM2 for dev / AWS CloudHSM for staging) accessible via PKCS#11 endpoint
- Cluster admin user has `cluster.kacho-root.security_admin` role

**When**:
- `cd kacho-deploy && helm upgrade --install spire spire/spire-server -f values.dev.yaml` executed
- Helm renders StatefulSet (3 replicas), ConfigMap (server config), Service (headless + ClusterIP), RBAC (ClusterRole для k8s_psat attestor), Secret references for HSM credentials
- Argo CD also installed; reconciles applied state

**Then**:
- All 3 SPIRE Server pods reach `Ready` status within 5 min
- `kubectl get pods -n spire-system -l app=spire-server -o wide` shows pods on 3 different nodes (anti-affinity enforced)
- `kubectl logs spire-server-0 -n spire-system` contains lines:
  - `Starting SPIRE Server`,
  - `DataStore connected (postgres)`,
  - `CA loaded from PKCS#11`,
  - `RPC server listening on 0.0.0.0:8081`
- Exactly one pod holds leadership lease in `spire-system/leases/spire-server-leader-election` (verified via `kubectl get leases -n spire-system`)
- Followers respond to `WorkloadAPI.ValidateJWTSVID` reads (read-replica behavior) but reject mint operations (only leader)
- `spire-server-0` ServiceMonitor (Prometheus) scrape returns metrics `spire_server_registrations_total`, `spire_server_attestations_total`, `spire_server_signed_x509_svids_total` all ≥0

#### Scenario S10.1.2: SPIRE Server leader-election: primary kill, secondary promoted

**ID**: S10.1.2

**Given**:
- 3 SPIRE Server replicas running (per S10.1.1)
- `spire-server-0` currently holds leadership lease
- 50 kacho-* pods running with active SVIDs (validity ~30 min remaining)

**When**:
- Operator runs `kubectl delete pod spire-server-0 -n spire-system --grace-period=0 --force`
- 3 new kacho-* pods start (would normally request initial SVIDs)

**Then**:
- Within 15 seconds, one of {spire-server-1, spire-server-2} acquires leadership lease
- `kubectl get leases -n spire-system spire-server-leader-election -o yaml` shows new `holderIdentity`
- Existing kacho-* pods experience NO mTLS disruption (existing SVIDs continue valid)
- The 3 new kacho-* pods successfully obtain SVIDs within 30 seconds via the new leader
- New `spire-server-0` (recreated by StatefulSet) joins as follower; data-store sync replays from Postgres; pod reaches Ready within 2 min
- `kubectl logs <new-leader> -n spire-system` shows `Acquired leadership` log entry
- Audit event `iam.spiffe.leader_change` written to `audit_outbox` table in `kacho_iam`

#### Scenario S10.1.3: Postgres DataStore connection loss — fail-closed for new SVIDs

**ID**: S10.1.3

**Given**:
- SPIRE Server 3-replica running healthy
- 50 kacho-* pods running with active SVIDs
- Postgres `spire_server` schema accessible

**When**:
- Postgres becomes unreachable (simulated via NetworkPolicy block in test; in real prod = unavailable for 5 min)
- 3 new pods start requesting initial SVIDs
- 2 existing pods reach 30-min SVID expiry boundary, request rotation

**Then**:
- New pod SVID requests fail with `SPIRE: cannot reach DataStore`; pod logs show retry backoff
- Pods do NOT serve traffic (corelib/spiffe.workloadapi.Client blocks on first-SVID fetch)
- Existing pods at rotation boundary: SPIRE Agent caches existing SVID till expiry; mTLS continues
- After Postgres recovers, queued requests drain within 60s; new pods get SVIDs; rotations succeed
- Alert `SPIREServerDataStoreUnavailable` fires to PagerDuty (severity P2; not P1 because existing traffic unaffected)
- `kacho_iam.audit_outbox` contains row `iam.spiffe.datastore.unavailable` with timestamp

#### Scenario S10.1.4: SPIRE Server config reload via SIGHUP (зarning — registration entries via API, not config file)

**ID**: S10.1.4

**Given**:
- SPIRE Server 3-replica running
- Admin needs to update `agent.ttl` config value (impacting initial trust setup, not registration entries)

**When**:
- Admin updates Helm `values.prod.yaml` (e.g., `spire.server.agentTtl: 7200`); runs `helm upgrade`
- ConfigMap updated; StatefulSet detects pod template change → rolling update

**Then**:
- Pods restart one-by-one (StatefulSet ordering: -0 last as it's leader; -2 first, -1 second, -0 last)
- During each pod restart, leader handover occurs (gracefully; existing SVID issuance pauses for <5s per handover)
- 50 kacho-* pods experience no detectable disruption (existing SVIDs continue; new requests queue briefly)
- New TTL = 7200s applied to **future** registration entries that don't specify own TTL; existing entries unchanged
- `audit_outbox` contains `iam.spiffe.server.config_reloaded` event

#### Scenario S10.1.5: Anti-affinity violation prevented (single-node deploy attempt blocked)

**ID**: S10.1.5

**Given**:
- Cluster has only 2 nodes available (node pool scale-down during test)
- Helm values specify `spire.server.replicas: 3` and `podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution`

**When**:
- `helm upgrade spire spire/spire-server` executed

**Then**:
- StatefulSet creates pods; 2 schedule successfully on 2 separate nodes
- 3rd pod stays in `Pending` status; `kubectl describe pod spire-server-2 -n spire-system` shows `0/2 nodes available: 2 didn't match pod anti-affinity rules`
- SPIRE Server cluster operates with 2 replicas (quorum=majority of 3 = 2; leader election works)
- Alert `SPIRECriticalReplicaCount` fires (running with <3 replicas) — operator notified to scale node pool
- After node pool scaled to 3+ nodes, pending pod schedules; cluster returns to full 3-replica HA

### 6.2 Agent attestation via k8s_psat (5 scenarios)

#### Scenario S10.2.1: Pod attestation success — k8s_psat + cosign selectors match

**ID**: S10.2.1

**Given**:
- SPIRE Server + Agent operational
- Registration entry exists: `{spiffe_id=spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc, selectors=[k8s:ns:kacho-system, k8s:sa:kacho-vpc, cosign:fp_PLATFORM_TEAM_KEY]}`
- Image `ghcr.io/pro-robotech/kacho-vpc:v1.42.0` signed by kacho-platform team key (verified via `cosign verify`)
- Pod manifest: `serviceAccountName: kacho-vpc`, `namespace: kacho-system`, `image: ghcr.io/pro-robotech/kacho-vpc:v1.42.0`, `volumeMounts: [{name: spire-agent-socket, mountPath: /run/spire/sockets, readOnly: true}]`

**When**:
- Pod scheduled and started on node N1
- `corelib/spiffe.NewWorkloadAPIClient("/run/spire/sockets/agent.sock")` invoked in `cmd/kacho-vpc/main.go`
- Client calls `WorkloadAPI.FetchX509SVID`

**Then**:
- SPIRE Agent on N1 receives request via socket
- Agent runs k8s_psat: fetches `/var/run/secrets/kubernetes.io/serviceaccount/token` (projected); validates against k8s API `TokenReview` → confirms SA=`kacho-vpc`, ns=`kacho-system`
- Agent runs cosign: fetches image digest via containerd API; verifies signature against `fp_PLATFORM_TEAM_KEY` → match
- Agent forwards selectors `[k8s:ns:kacho-system, k8s:sa:kacho-vpc, cosign:fp_PLATFORM_TEAM_KEY]` to SPIRE Server
- Server matches registration entry; signs SVID via HSM
- Returns SVID to Agent → to pod
- Pod's gRPC server starts accepting mTLS connections; SVID URI SAN = `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc`
- `kubectl exec <pod> -- openssl s_client -connect localhost:8443 -showcerts` shows valid cert chain rooted in trust-domain CA
- Metrics: `spire_server_attestations_total{type=k8s_psat, status=success}` incremented; `spire_server_signed_x509_svids_total` incremented
- Audit event `iam.spiffe.svid.issued` written to `audit_outbox` with diff

#### Scenario S10.2.2: Pod attestation failure — invalid projected SA token (k8s_psat reject)

**ID**: S10.2.2

**Given**:
- Setup per S10.2.1 EXCEPT pod manifest has `serviceAccountName: kacho-iam` (wrong SA — registration entry expects `kacho-vpc`)
- Image signed correctly

**When**:
- Pod started
- Client calls `WorkloadAPI.FetchX509SVID`

**Then**:
- SPIRE Agent runs k8s_psat: validates token → SA=`kacho-iam` (not `kacho-vpc`)
- Selector mismatch: `[k8s:ns:kacho-system, k8s:sa:kacho-iam, cosign:fp_PLATFORM_TEAM_KEY]` does NOT match any registration entry with all selectors satisfied
- Agent returns `PermissionDenied: no matching registration entry` to pod
- corelib/spiffe.workloadapi.Client logs error; gRPC server fails to start (no SVID source); pod exits with non-zero (Kubernetes restarts pod indefinitely in CrashLoopBackOff)
- Metrics: `spire_server_attestations_total{type=k8s_psat, status=no_match}` incremented
- Hubble flow: no mTLS connections from this pod (it can't open them)
- Operator alerted via `KachoPodCrashLooping{namespace=kacho-system}` Alertmanager rule (already exists; no new alert needed)
- Audit event `iam.spiffe.attestation.failed` written to `audit_outbox` with reason `selector_mismatch` and offending SA name

#### Scenario S10.2.3: Pod attestation failure — image not signed

**ID**: S10.2.3

**Given**:
- Setup per S10.2.1 EXCEPT image `ghcr.io/pro-robotech/kacho-vpc:v1.42.0-unsigned` — built but NOT cosign-signed
- Pod manifest correct otherwise

**When**:
- Pod started
- Client calls `WorkloadAPI.FetchX509SVID`

**Then**:
- SPIRE Agent runs cosign attestor: fetches image; verifies signature → `cosign verify` returns "no signatures found"
- Agent selectors include `[k8s:ns:kacho-system, k8s:sa:kacho-vpc]` but NOT `cosign:fp_PLATFORM_TEAM_KEY` (signature missing)
- Registration entry requires cosign selector → no match → `PermissionDenied`
- Pod fails to start (per S10.2.2)
- Metrics: `spire_server_attestations_total{type=cosign, status=no_signature}` incremented
- Audit event `iam.spiffe.attestation.failed` with reason `cosign_signature_missing`, image digest in details
- Alert `KachoUnsignedImageDeployed` fires (severity P2) — distinguishable from S10.2.2's selector_mismatch

#### Scenario S10.2.4: Pod attestation failure — image tampered (cosign signature invalid)

**ID**: S10.2.4

**Given**:
- Setup per S10.2.1 EXCEPT image registry serves tampered image bytes (digest mismatch with signature manifest)
- This simulates supply-chain attack: attacker replaced image bytes in registry, but didn't re-sign

**When**:
- Pod started
- Client calls `WorkloadAPI.FetchX509SVID`

**Then**:
- SPIRE Agent runs cosign: fetches manifest; signature exists, but verification fails (digest hash mismatch)
- Agent returns selectors without cosign selector (or with explicit `cosign:invalid` — exact behavior plugin-specific)
- Server: no match → `PermissionDenied`
- Pod CrashLoopBackOff
- Audit event `iam.spiffe.attestation.failed` with reason `cosign_signature_invalid` AND `image_digest_mismatch`
- Alert `KachoSupplyChainAttackSuspected` fires (severity **P1** — critical — distinguishable from missing-signature scenario)

#### Scenario S10.2.5: Re-attestation после Agent restart — existing pod gets new SVID without restart

**ID**: S10.2.5

**Given**:
- Pod `kacho-vpc-replicas-0` running with active SVID (~30 min remaining validity)
- SPIRE Agent on same node running

**When**:
- Agent killed: `kubectl delete pod -n spire-system -l app=spire-agent --field-selector spec.nodeName=N1`
- Agent restarted by DaemonSet within 30s
- Pod's existing SVID expires in 30 min; rotation will be triggered ~15 min from now

**Then**:
- Existing connections continue using cached SVID (corelib/spiffe.workloadapi.Client retains in-memory SVID till expiry)
- Pod's outgoing connections during Agent downtime use cached SVID (no rotation attempt during downtime)
- After Agent restored, client reconnects to Workload API socket (auto-retry)
- 15 min before pod's SVID expires, client calls `FetchX509SVID` again → Agent attests → new SVID issued
- Pod swap to new SVID in-memory; no pod restart; no traffic disruption observed in Hubble flow (`encryption: tls` continuously)
- Metrics: `spire_agent_workload_api_connections{node=N1}` recovers to baseline

### 6.3 cosign image-signature selector (5 scenarios)

#### Scenario S10.3.1: Signed image (kacho-platform key) → SVID issued

**ID**: S10.3.1

**Given**:
- Build pipeline (`.github/workflows/release.yml`) executes `cosign sign --key=kacho-platform-team.key ghcr.io/pro-robotech/kacho-vpc@sha256:abc123`
- Image manifest annotated with signature reference
- SPIRE Agent cosign attestor configured with trusted-signers: `kacho-platform-team` public key
- Registration entry includes selector `cosign:fp_PLATFORM_TEAM_KEY`

**When**:
- Pod uses image `ghcr.io/pro-robotech/kacho-vpc:v1.42.0`

**Then**:
- (per S10.2.1) Attestation succeeds; SVID issued

#### Scenario S10.3.2: Signed image но wrong key (different team's key) → SVID denied

**ID**: S10.3.2

**Given**:
- Image signed with `attacker-team.key` (key NOT in trusted-signers list)
- Trusted-signers configured: only `kacho-platform-team`

**When**:
- Pod uses image

**Then**:
- SPIRE Agent cosign attestor: `cosign verify` finds signature, but fingerprint `fp_ATTACKER_TEAM_KEY` not in trusted list
- Selectors do NOT include `cosign:fp_PLATFORM_TEAM_KEY` (the required one)
- Registration entry not matched
- Pod CrashLoopBackOff
- Audit event `iam.spiffe.attestation.failed` reason `cosign_untrusted_signer` with attacker fingerprint logged

#### Scenario S10.3.3: Keyless OIDC signing (Fulcio root) accepted on non-prod, rejected on prod

**ID**: S10.3.3

**Given**:
- Non-prod (staging) cosign attestor config: trusted signers = `kacho-platform-team` + `fulcio-root` (sigstore.dev OIDC)
- Prod cosign attestor config: trusted signers = `kacho-platform-team` ONLY
- Image built in staging CI: signed via `cosign sign-blob --identity-token=$ACTIONS_ID_TOKEN_REQUEST_TOKEN` (keyless OIDC, GitHub Actions OIDC issuer)

**When**:
- Same image attempted to deploy to staging vs prod

**Then**:
- **Staging**: Fulcio signature verified against Fulcio root in trusted list → match → SVID issued
- **Prod**: Fulcio signature not in `kacho-platform-team` trusted list → no match → SVID denied → CrashLoopBackOff
- Documented in runbook: prod requires offline-key-signed images; keyless OIDC for non-prod only
- Phase 11 CI gate prevents keyless-only-signed images from being promoted to prod registry

#### Scenario S10.3.4: cosign attestor unavailable (e.g., Rekor down) — pod attestation falls back to k8s_psat-only?

**ID**: S10.3.4

**Given**:
- SPIRE Agent cosign attestor configured
- Rekor (sigstore transparency log; queried by some cosign configs) becomes unreachable
- Image is signed correctly; signature attestation does not require Rekor (key-based, not keyless)

**When**:
- Pod requests SVID

**Then**:
- cosign attestor uses local-key-based verification only (doesn't depend on Rekor for offline key verification)
- Attestation succeeds; SVID issued
- (For keyless OIDC scenario where Rekor IS required: attestation fails-closed; alert fires; image must be re-signed with offline key as fallback)
- Documented behavior: production uses offline keys → no Rekor dependency

#### Scenario S10.3.5: cosign trusted-signer rotation (kacho-platform team key rotation)

**ID**: S10.3.5

**Given**:
- Current cosign trusted-signers config: `kacho-platform-team-v1` key
- Operator rotates to `kacho-platform-team-v2` key (annual rotation per security policy)
- Both keys' fingerprints temporarily listed during rollover window (24h)

**When**:
- Helm `values.prod.yaml` updated; `spire.agent.cosignAttestor.trustedSigners: [v1_fp, v2_fp]`
- Helm upgrade executes; SPIRE Agent DaemonSet rolling-updates
- CI starts signing new builds with v2 key (existing builds still signed with v1)

**Then**:
- During rollover window: pods with v1-signed images AND v2-signed images both get SVIDs
- After 24h, operator removes v1 from trustedSigners (subsequent Helm upgrade)
- Old v1-signed images no longer attest; need rebuild with v2 (forces fresh build)
- Audit events `iam.spiffe.cosign.trusted_signer_added` (for v2), then `iam.spiffe.cosign.trusted_signer_removed` (for v1) — both in `audit_outbox`

### 6.4 SVID rotation (4 scenarios)

#### Scenario S10.4.1: SVID auto-rotation 30 min before expiry — no pod restart

**ID**: S10.4.1

**Given**:
- Pod running with SVID issued at T0; validity 1h (expires T0+60min)
- Active mTLS connections to peer kacho-iam (long-lived gRPC stream)

**When**:
- Time advances to T0+30min (50% lifetime trigger)

**Then**:
- corelib/spiffe.workloadapi.Client internally calls `FetchX509SVID` to refresh
- New SVID issued (same SPIFFE-ID, new cert serial, validity T0+30..T0+90)
- Client updates internal X509Source with new SVID
- Existing gRPC connections continue using old SVID until natural connection close (TLS allows old cert during session); new connections use new SVID
- No pod restart observed; no traffic interruption
- `kubectl exec <pod> -- ls -la /run/spire/sockets/` shows socket still mounted (file-level, not network)
- Metrics: `corelib_spiffe_svid_rotations_total{spiffe_id=...}` incremented; `corelib_spiffe_svid_age_seconds` reset to 0

#### Scenario S10.4.2: SVID rotation failure (Agent unreachable for 30+ min) — pod operates degraded then fails

**ID**: S10.4.2

**Given**:
- Pod running with SVID, validity 1h, currently at T0+30min (rotation needed)
- SPIRE Agent killed at T0+25min; not restored

**When**:
- Time advances to T0+60min (original SVID expires)

**Then**:
- At T0+30min: rotation attempt fails (Agent unreachable); client logs error; uses cached SVID
- Between T0+30min and T0+60min: pod continues serving via cached SVID; Hubble shows continued mTLS
- At T0+60min: cached SVID expires; client X509Source returns error; new outgoing connections fail handshake
- Peer kacho-iam rejects expired cert at TLS handshake (`tls: expired certificate`)
- Pod's gRPC server still listens but all client-handshake-needing operations fail
- Within 60s of cert expiry, pod's liveness probe (gRPC health) fails (it tries internal connection) → Kubernetes restarts pod
- Restarted pod can't attest (Agent still down) → CrashLoopBackOff
- Critical alert `KachoSVIDExpiryWithoutRotation` fires (P1)

#### Scenario S10.4.3: Cert chain validity during rotation — peer accepts both old and new

**ID**: S10.4.3

**Given**:
- Two pods (A and B), each with SVIDs
- A has active mTLS connection to B
- A's SVID is about to rotate (29 min until rotation)

**When**:
- A's SVID rotates; B simultaneously sends request on existing connection

**Then**:
- A's outgoing new connection uses new SVID
- Existing connection (where A is server-side TLS): B's cached chain still validates old SVID until session resume
- B receives response; verifies cert chain via its X509Source (which contains current trust-domain bundle); both old and new SVIDs root in same trust-domain CA → valid
- No errors observed in Hubble flow
- Metrics: `cilium_tls_handshake_total{result=success}` unchanged

#### Scenario S10.4.4: Trust-domain CA rotation — все SVIDs invalidated; mass re-attest

**ID**: S10.4.4

**Given**:
- Trust-domain CA root key compromised (simulated for chaos test)
- Operator with `cluster.kacho-root.security_admin` role runs `InternalSpiffeRevocationService.RotateTrustDomain` (via grpcurl to internal mux)
- 50 kacho-* pods running with active SVIDs

**When**:
- RotateTrustDomain operation begins
- HSM generates new CA root key (PKCS#11)
- New trust_domain_bundles row INSERTed (sequence_number+1, new JWKS); old row UPDATE active_until=now() (atomic txn)
- SPIRE Server distributes new bundle to all Agents
- All Agents stop accepting old SVID validations; existing SVIDs invalidated

**Then**:
- Operation returns `Operation` with `done=false`; status `propagation_in_progress`
- All 50 pods experience mTLS failure within ~5 min (old SVID rejected by peer's now-updated bundle)
- corelib/spiffe.workloadapi.Client retries; SPIRE Agent issues new SVID (signed by new root key)
- Within ~15-30 min, all pods restored; full mesh mTLS re-established with new trust-domain
- Operation status transitions to `done=true`; emits CAEP event `iam.spiffe.trust_domain.rotated`
- Audit event `iam.spiffe.trust_domain.rotated` in `audit_outbox` with old/new sequence numbers
- `trust_domain_bundles` table: old row has `active_until` set; new row has `active_until = NULL` (current)
- Partial UNIQUE constraint `(trust_domain) WHERE active_until IS NULL` enforces only one active bundle (violation = bug)
- `/federation/bundle` public endpoint now serves new bundle (next refresh cycle)
- Federation subscribers (Phase 11 cross-cluster) get pushed update via CAEP

### 6.5 Cilium auto-mTLS between pods (6 scenarios)

#### Scenario S10.5.1: kacho-vpc pod → kacho-iam pod — auto-mTLS via SPIFFE SVID

**ID**: S10.5.1

**Given**:
- Both kacho-vpc and kacho-iam pods running with valid SVIDs
- Cilium installed with `serviceMesh.enabled=true`, `authentication.mode=spiffe`
- CiliumNetworkPolicy `kacho-iam-ingress-allow.yaml` allows from `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc`
- kacho-vpc service makes gRPC call to `kacho-iam:8081/kacho.iam.v1.ProjectService/Get`

**When**:
- gRPC call initiated

**Then**:
- Cilium eBPF on kacho-vpc's node:
  - Identifies dest pod as kacho-iam (via Kubernetes Service endpoint resolution)
  - Performs SPIFFE mTLS handshake using kacho-vpc's SVID as client cert + kacho-iam's SVID as server cert
  - Verifies peer cert URI SAN matches expected SPIFFE-ID
  - Encrypts payload
- Cilium eBPF on kacho-iam's node: decrypts; forwards to pod
- kacho-iam pod receives request; corelib/spiffe.MeshInterceptor extracts caller SPIFFE-ID = `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc`; populates `corelib/authz.Principal.MeshCaller`
- Application authz layer (OpenFGA Check) uses `Principal.ID` (end-user JWT sub) NOT `MeshCaller` — defense-in-depth (S10.8.x)
- Response returns via same encrypted path
- Hubble flow shows: source=`kacho-vpc` SPIFFE-ID, dest=`kacho-iam` SPIFFE-ID, verdict=`FORWARDED`, encryption=`tls`, l7=`ProjectService.Get`

#### Scenario S10.5.2: Wrong-SPIFFE-ID peer rejected at TLS handshake

**ID**: S10.5.2

**Given**:
- All kacho-* pods running with valid SVIDs
- Attacker pod (compromised hypothetical scenario, simulated via test): pod in `default` namespace with SA `default`, NO registration entry, NO SVID issued
- CiliumNetworkPolicy on kacho-iam: ingress allowed only from listed SPIFFE-IDs

**When**:
- Attacker pod attempts `curl http://kacho-iam.kacho-system.svc.cluster.local:8081/kacho.iam.v1.ProjectService/Get`

**Then**:
- Cilium eBPF: attacker pod has no SVID → cannot initiate mTLS handshake → connection refused at L3/L4 level (no plaintext fallback per P10-D2)
- Curl returns error `connection reset by peer` или TLS handshake error
- Hubble flow shows: source=`default/default` (identity), dest=`kacho-iam` SPIFFE-ID, verdict=`DROPPED`, reason=`policy_denied` (or `tls_handshake_failed` if reaching that far)
- Alert `KachoPolicyDrop{src_identity=default}` fires if drops > 50/min sustained
- Audit event `iam.spiffe.attestation.attempted` (Hubble export) shows attempt; SOC can investigate

#### Scenario S10.5.3: Compromised peer with valid SVID — still blocked by Cilium policy (peer not in allow-list)

**ID**: S10.5.3

**Given**:
- All kacho-* pods running normally
- Hypothetical: a `kacho-ui-admin` pod (which has SVID `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-ui-admin`) attempts to reach `kacho-iam:/v1/internal/breakglass/*`
- CiliumNetworkPolicy `kacho-iam-internal-breakglass.yaml` allows L7 path `/v1/internal/breakglass/*` **only** from `kacho-api-gateway-internal-mux` SPIFFE-ID

**When**:
- kacho-ui-admin pod calls `kacho-iam:/v1/internal/breakglass/list`

**Then**:
- Cilium eBPF: mTLS handshake succeeds (kacho-ui-admin has valid SVID; trust-domain root validates)
- Cilium evaluates CiliumNetworkPolicy: peer SPIFFE-ID = `kacho-ui-admin`; rule for `/v1/internal/breakglass/*` requires `kacho-api-gateway-internal-mux` → no match → DROP
- Connection RST sent to source; ui-admin pod sees `connection refused` / `403` (depending on Cilium L7 verdict mode)
- Hubble flow: source=`kacho-ui-admin`, dest=`kacho-iam` path=`/v1/internal/breakglass/list`, verdict=`DROPPED`, reason=`l7_policy_denied`
- audit_outbox does NOT receive event (Cilium L7 drop happens before reaching kacho-iam; visibility only via Hubble)
- This is **L7 path-based authz** — same SPIFFE-ID can be allowed for some paths and denied for others

#### Scenario S10.5.4: WireGuard L3 encryption between nodes verified

**ID**: S10.5.4

**Given**:
- 3-node cluster
- Cilium WireGuard encryption enabled (`encryption.type=wireguard`)
- kacho-vpc pod on N1; kacho-iam pod on N2

**When**:
- gRPC call from kacho-vpc to kacho-iam

**Then**:
- Cilium establishes WireGuard tunnel between N1 and N2 (auto-managed; uses cilium-managed keys)
- Pod-to-pod traffic encapsulated in WireGuard packets at node level (in addition to mTLS at L7)
- Packet capture on inter-node interface (`tcpdump -i eth0 udp port 51871`): only WireGuard UDP packets visible; payload encrypted
- Inside the encrypted tunnel: pod IP traffic also mTLS-encrypted (double encryption)
- Hubble flow shows: `encryption=tls` at L7; node-level encryption is opaque to Hubble (it's L3)
- Metric `cilium_wireguard_peers` reports 3 peers (3-node mesh)
- Operator verification: `kubectl exec <cilium-agent> -- cilium status | grep WireGuard` shows `Encryption: WireGuard [enabled]`

#### Scenario S10.5.5: Multi-cluster external SPIFFE consumer verifies pod SVID using federation bundle

**ID**: S10.5.5

**Given**:
- External SPIFFE-aware system (e.g., hypothetical partner SaaS or external monitoring tool with SPIFFE support)
- Partner system fetches federation bundle from `https://spire.kacho.cloud/federation/bundle`
- Partner caches bundle; configures own trust to validate `kacho.cloud` SPIFFE-IDs
- Partner system makes outbound mTLS call where it acts as client; Kachō pod is server (mesh-edge case for federation)

**When**:
- Partner system attempts mTLS handshake to Kachō public endpoint (only via api-gateway public mux)

**Then**:
- Kachō pod (api-gateway) presents server SVID `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-api-gateway`
- Partner system validates cert chain using cached federation bundle → root CA matches → cert valid
- TLS handshake succeeds; partner verifies SPIFFE-ID matches its expected pattern
- Phase 10: this scenario is for **future** Phase 11 multi-cluster; Phase 10 ensures federation bundle endpoint is correct + accessible
- Test: `curl -sSL https://spire.kacho.cloud/federation/bundle | jq .` returns SPIFFE-bundle-format JSON with `trust_domain`, `spiffe_sequence`, `keys[]`

#### Scenario S10.5.6: Hubble flow telemetry exported to OpenTelemetry collector

**ID**: S10.5.6

**Given**:
- Cilium Hubble enabled with Relay; OpenTelemetry collector deployed
- Hubble configured to export flows via OTLP

**When**:
- Normal traffic flowing (kacho-vpc → kacho-iam etc.)

**Then**:
- OpenTelemetry collector receives Hubble flows; forwards to Loki (Phase 11 stack) — Phase 10 just verifies collector receives data
- `kubectl logs <otel-collector-pod> | grep "received flow"` shows flow logs
- Grafana dashboard (Phase 11) will visualize; Phase 10 verifies plumbing only
- Hubble UI accessible via `kubectl port-forward -n kube-system svc/hubble-ui 8080:80` → http://localhost:8080 shows flow graph
- Drop alerts: `policy_drops > 50/min` triggers PagerDuty page (severity P2; investigate lateral movement)

### 6.6 CiliumNetworkPolicy default-deny (6 scenarios)

#### Scenario S10.6.1: Без policy — все pod-to-pod в kacho-system блокированы (default-deny)

**ID**: S10.6.1

**Given**:
- Fresh Cilium install; default-deny CNP applied to `kacho-system` namespace
- Helm has NOT yet installed allowlist CNPs (testing baseline)
- kacho-vpc and kacho-iam pods running with SVIDs

**When**:
- kacho-vpc attempts gRPC call to kacho-iam

**Then**:
- Cilium drops at L3/L4 (no allow rule)
- Hubble flow: verdict=`DROPPED`, reason=`policy_denied`
- gRPC call returns Unavailable (connection refused)
- Pod logs error
- This baseline test verifies default-deny is in effect

#### Scenario S10.6.2: Explicit allow per ServiceAccount + SPIFFE-ID → allowed

**ID**: S10.6.2

**Given**:
- Default-deny baseline (per S10.6.1)
- Helm applies allowlist CNP: `kacho-iam-ingress-allow.yaml` declares ingress from SPIFFE-ID `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc` on port 8081

**When**:
- kacho-vpc → kacho-iam call

**Then**:
- Cilium evaluates policy; peer SPIFFE-ID matches; allow
- mTLS handshake; request processed; response
- Hubble flow: `FORWARDED`
- Successful gRPC response

#### Scenario S10.6.3: Cross-namespace deny (e.g., default ns → kacho-system)

**ID**: S10.6.3

**Given**:
- Allowlist CNPs deployed (per S10.6.2)
- Test pod in `default` namespace (no SVID)

**When**:
- Default-ns pod attempts to reach kacho-iam

**Then**:
- Cilium drops at L3/L4 (default-deny still in effect for non-explicit sources)
- Verdict=`DROPPED`, reason=`policy_denied`
- This verifies cross-namespace isolation

#### Scenario S10.6.4: L7 HTTP path-based allowlist — `/v1/internal/*` only from {vpc, compute, loadbalancer}

**ID**: S10.6.4

**Given**:
- CNP `kacho-iam-l7-internal.yaml` deployed:
  ```yaml
  ingress:
    - fromEndpoints:
        - matchLabels:
            io.cilium.k8s.policy.spiffe-id: "spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc"
            (OR kacho-compute, kacho-loadbalancer)
      toPorts:
        - ports: [{port: "8081"}]
          rules:
            http:
              - method: "POST"
                pathRegex: "^/v1/internal/.*"
  ```
- kacho-vpc, kacho-ui-admin both have valid SVIDs

**When**:
- kacho-vpc calls `/v1/internal/projects:get` → expected ALLOW
- kacho-ui-admin calls `/v1/internal/projects:get` → expected DROP (SPIFFE-ID not in matchLabels)
- kacho-vpc calls `/v1/projects:get` (public, non-internal) → expected ALLOW via separate public CNP

**Then**:
- All 3 scenarios produce expected verdicts (Hubble flow logs verified)
- L7-drops on attempts to access `/v1/internal/*` from non-listed peers

#### Scenario S10.6.5: L7 HTTP method restriction — only POST/GET allowed on certain paths

**ID**: S10.6.5

**Given**:
- CNP includes `method: "POST"` restriction for `/v1/internal/breakglass/*`

**When**:
- Authorized peer (api-gateway-internal-mux) sends DELETE to `/v1/internal/breakglass/abc123`

**Then**:
- Cilium L7 drops (method not POST)
- Verdict=`DROPPED`, reason=`l7_method_denied`
- App authz layer never reached
- This is double-defense: L7 + app-layer (OpenFGA) both enforce

#### Scenario S10.6.6: Policy hot-reload — CNP update propagates within 30s

**ID**: S10.6.6

**Given**:
- Existing CNP `kacho-iam-ingress-allow.yaml` allows {vpc, compute}
- Operator adds `kacho-loadbalancer` SPIFFE-ID to allow-list; commits PR; merges
- Argo CD syncs; updated CNP applied

**When**:
- kacho-loadbalancer pod attempts new connection to kacho-iam

**Then**:
- Within 30s of CNP apply, kacho-loadbalancer's connections succeed
- Cilium agent reloads policy without dropping existing connections
- Hubble flow: previously DROPPED packets from loadbalancer now FORWARDED
- Audit event `iam.spiffe.network_policy.updated` in `audit_outbox` (via kacho-iam admin-mirroring of CNP changes; Phase 10 optional, Phase 11 mandatory)

### 6.7 AuthorizationPolicy SPIFFE-ID-based (5 scenarios)

#### Scenario S10.7.1: kacho-vpc → kacho-iam allowed via SPIFFE pattern matchLabels

**ID**: S10.7.1

**Given**:
- CiliumNetworkPolicy uses `matchLabels: { io.cilium.k8s.policy.spiffe-id: "spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc" }`
- kacho-vpc pod with that SVID

**When**:
- Request initiated

**Then**:
- Cilium injects SPIFFE-ID as identity label; policy matches; allowed
- Verified via `cilium policy trace --src-pod kacho-vpc-replicas-0 --dst-pod kacho-iam-replicas-0`

#### Scenario S10.7.2: SPIFFE-ID pattern wildcard supported

**ID**: S10.7.2

**Given**:
- CNP uses regex pattern via `matchExpressions`:
  ```yaml
  - key: io.cilium.k8s.policy.spiffe-id
    operator: In
    values:
      - "spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc"
      - "spiffe://kacho.cloud/ns/kacho-system/sa/kacho-compute"
      - "spiffe://kacho.cloud/ns/kacho-system/sa/kacho-loadbalancer"
  ```

**When**:
- Each of kacho-vpc/compute/loadbalancer makes call

**Then**:
- All 3 match; all allowed
- 4th service NOT in list (e.g., kacho-ui-admin) → denied
- Per-environment trust domain in pattern (`kacho.cloud` vs `kacho.staging.cloud`) — staging pod cannot impersonate prod (separate trust domain not in prod policy)

#### Scenario S10.7.3: Non-allowed SPIFFE-ID → denied with clear reason

**ID**: S10.7.3

**Given**:
- Allow-list does NOT include `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-ui-admin`
- kacho-ui-admin attempts to reach kacho-iam

**When**:
- Connection initiated

**Then**:
- Hubble drop logged with verdict=`DROPPED`, source SPIFFE-ID, dest, reason=`policy_denied`
- Repeated drops over 1 min → alert
- Operator can identify offending service via SPIFFE-ID in Hubble flow

#### Scenario S10.7.4: IPv6 support — same SPIFFE-ID identity over IPv6 traffic

**ID**: S10.7.4

**Given**:
- Cluster dual-stack (IPv4 + IPv6); pods may have v6 addrs (e.g., kacho-vpc-implement which is data-plane v6-heavy)
- CNP with SPIFFE-ID identity (not IP) for allow-list

**When**:
- kacho-vpc → kacho-iam over IPv6

**Then**:
- Cilium eBPF identifies by SPIFFE-ID (independent of IP version)
- Allowed; mTLS handshake; encrypted; forwarded
- Same code path as IPv4

#### Scenario S10.7.5: AuthorizationPolicy + L7 + L4 ports combine

**ID**: S10.7.5

**Given**:
- CNP combines: SPIFFE-ID allow + L4 port 8081 + L7 pathRegex
- Caller has correct SPIFFE-ID, hits port 8081, path `/v1/projects:list` → ALLOW
- Caller has correct SPIFFE-ID, hits port 8081, path `/v1/admin/users:delete` → DENY (L7)
- Caller has correct SPIFFE-ID, hits port 9999 (wrong) → DENY (L4)

**When**:
- All 3 attempts made

**Then**:
- Each verdict matches expectations
- Multi-layer policy enforcement verified

### 6.8 Defense-in-depth: mesh + end-user authz (4 scenarios)

#### Scenario S10.8.1: Compromised kacho-vpc pod forges end-user principal → kacho-iam Check denies

**ID**: S10.8.1

**Given**:
- All kacho-* pods running with valid SVIDs (mesh fully operational)
- Hypothetical: attacker has gained root inside kacho-vpc pod (RCE через some vuln)
- Attacker generates a fake JWT claiming `sub=alice@example.com` (a real Kachō user)
- Attacker uses kacho-vpc's valid SVID for mTLS to kacho-iam, sets `x-kacho-end-user-principal: <fake-JWT>` header

**When**:
- Attacker invokes `kacho-iam.Internal.AccessBindingService.Get(folder_id=alice-private-folder)` via gRPC

**Then**:
- Cilium eBPF: peer SPIFFE-ID = `kacho-vpc` (legitimate; mTLS handshake succeeds)
- CNP allows kacho-vpc → kacho-iam internal traffic
- corelib/spiffe.MeshInterceptor: extracts caller `MeshCaller=spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc`
- corelib/authn.JWTInterceptor: parses `x-kacho-end-user-principal` JWT
  - Verifies signature using Kratos JWKS public keys
  - **Fake JWT was signed by attacker's key, not Kratos** → signature verification fails
  - Returns `Unauthenticated: invalid JWT signature`
- kacho-iam rejects request at AuthN layer; OpenFGA Check never invoked
- Audit event `iam.authn.jwt.invalid` in `audit_outbox` with `MeshCaller=kacho-vpc` (so SOC can trace compromised pod)
- Alert `KachoForgedJWTAttempt` fires (P1 — confirmed lateral movement attempt)

#### Scenario S10.8.2: Compromised kacho-vpc pod uses valid but stale JWT — still denied by ACR/ACR-at check

**ID**: S10.8.2

**Given**:
- Attacker in kacho-vpc has captured Alice's real JWT from a recent legitimate request
- JWT is valid signature; not expired; `kacho_mfa_at < 5min` window expired (10+ min ago)
- Internal endpoint `/v1/internal/breakglass/*` requires `acr=3` with `kacho_mfa_at < 5min` (step-up freshness)

**When**:
- Attacker replays JWT to break-glass endpoint

**Then**:
- mTLS passes (kacho-vpc SPIFFE-ID valid)
- Cilium L7 may already drop (kacho-vpc is NOT in `/v1/internal/breakglass/*` allow-list per S10.5.3) — but assume internal-mux pod has this access for sake of test
- corelib/authn.JWTInterceptor: validates JWT signature, expiry, etc. → passes
- Application-layer step-up gate: checks `kacho_mfa_at` claim → 10 min ago → fails freshness window
- Returns `Unauthenticated: step-up required; acr=3 with fresh_mfa required`
- Audit: `iam.authz.step_up_required` with `MeshCaller=kacho-vpc` flagged
- Multi-layer defense: even with valid replay attack, freshness check stops it

#### Scenario S10.8.3: Compromised pod cannot escalate own SPIFFE-ID

**ID**: S10.8.3

**Given**:
- Attacker in compromised kacho-vpc pod attempts to obtain `kacho-iam`'s SVID (escalation)

**When**:
- Attacker calls `WorkloadAPI.FetchX509SVID` from inside kacho-vpc pod
- Attempt: spoof k8s_psat token; pretend to be kacho-iam pod

**Then**:
- SPIRE Agent (running on host) inspects requesting process via cgroup → identifies it as kacho-vpc pod, not kacho-iam
- Agent fetches projected SA token from pod's mounted secret → token says `kacho-vpc` SA, not `kacho-iam`
- k8s_psat attestor validates token via TokenReview → returns SA=`kacho-vpc`
- Selectors include `k8s:sa:kacho-vpc`; not `k8s:sa:kacho-iam`
- Server matches kacho-vpc registration entry, not kacho-iam → returns kacho-vpc SVID (which attacker already has)
- Attacker cannot obtain kacho-iam SVID
- Lateral movement to peer service identity blocked at attestation layer
- Logged: `spire_server_attestations_total{type=k8s_psat}` shows kacho-vpc selector; nothing anomalous

#### Scenario S10.8.4: SVID revocation propagation — compromised pod's SVID revoked → all peer rejections within 30s

**ID**: S10.8.4

**Given**:
- Attacker identified in kacho-vpc-replicas-1 pod (forensics done; specific SPIFFE-ID + cert serial known)
- SOC operator with `cluster.kacho-root.security_admin` invokes `InternalSpiffeRevocationService.RevokeSvid(spiffe_id=spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc, serial=<cert-serial>, reason=KEY_COMPROMISE)`

**When**:
- Revocation operation submitted

**Then**:
- `svid_revocations` row INSERTed with `status=PENDING`
- Operation returns `Operation` immediately (async)
- Background worker (kacho-iam) atomic-CAS to `PROPAGATING`; calls SPIRE Server admin API to add cert serial to CRL
- SPIRE Server distributes CRL update to all Agents within 5s (poll interval)
- All Agents reload; next mTLS handshake from revoked SVID rejected (cert serial in CRL)
- Within 30s p99 of operation submit, attacker's existing connections fail at next handshake; new connections refused
- `svid_revocations` row transitions to `COMPLETE` (via atomic CAS); `propagation_completed_at` set
- CAEP event `iam.spiffe.svid.revoked` emitted to `caep_outbox`; Phase 8 drainer pushes to webhook subscribers
- Audit event `iam.spiffe.svid.revoked` in `audit_outbox` with reason, operator, target SPIFFE-ID, serial
- Compromised pod must restart to get new SVID; if it can't pass cosign attestation (image tampered) — does not restart successfully (security stops here)

### 6.9 Federation bundles (4 scenarios)

#### Scenario S10.9.1: Public endpoint serves trust bundle in SPIFFE Federation format

**ID**: S10.9.1

**Given**:
- `FederationBundleService` registered on api-gateway public mux
- Ingress `spire.kacho.cloud` with TLS (cert-manager Let's Encrypt staging-cert в dev)
- Current trust domain has 1 active bundle (sequence_number=42)

**When**:
- External consumer `curl -sSL https://spire.kacho.cloud/federation/bundle -H "Accept: application/json"`

**Then**:
- HTTP 200 with body:
  ```json
  {
    "trust_domain": "kacho.cloud",
    "spiffe_sequence": 42,
    "spiffe_refresh_hint": 300,
    "keys": [
      {"kty": "EC", "crv": "P-256", "x": "...", "y": "...", "use": "x509-svid", ...}
    ]
  }
  ```
- Response headers include `Cache-Control: max-age=300`, `X-Spiffe-Sequence: 42`
- For `Accept: application/jwt-set+json` → returns JWKS format (alternative)
- Phase 10 verifies endpoint serves; Phase 11 adds Cloudflare CDN caching

#### Scenario S10.9.2: External SPIFFE-aware system verifies pod SVID using fetched bundle

**ID**: S10.9.2

**Given**:
- External system (test partner consumer; simulated by test harness)
- System fetched bundle and configured local SPIFFE verifier
- Kachō api-gateway public mux SVID = `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-api-gateway`

**When**:
- External system initiates TLS to api-gateway with SPIFFE verification enabled

**Then**:
- TLS handshake: api-gateway presents server SVID
- External verifier validates cert chain against `kacho.cloud` trust bundle keys → match → cert valid
- Verifier confirms SPIFFE-ID URI SAN = expected `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-api-gateway` → match
- Handshake succeeds; request flows
- External system trusts Kachō pod identity без manual cert pinning

#### Scenario S10.9.3: Bundle rotation — sequence number incremented atomically

**ID**: S10.9.3

**Given**:
- Current bundle sequence=42; trust-domain rotation operation begins (per S10.4.4)

**When**:
- New bundle inserted with sequence=43; old row UPDATE active_until=now()

**Then**:
- DB transaction is atomic (single BEGIN ... COMMIT)
- partial UNIQUE `(trust_domain) WHERE active_until IS NULL` enforces only one active at a time (no overlap)
- EXCLUDE USING gist constraint catches any overlap attempt
- After transaction commit: `SELECT * FROM trust_domain_bundles WHERE active_until IS NULL` returns row with sequence=43
- Public endpoint refreshed next cycle (300s); sequence=43 visible
- All Agents re-attest with new bundle; in-cluster mesh recovers

#### Scenario S10.9.4: Bundle endpoint unavailable — Phase 10 fail-closed for federation, NOT for in-cluster

**ID**: S10.9.4

**Given**:
- Federation bundle Ingress fails (cert-manager renewal fails, или kacho-iam down)
- In-cluster SPIRE Server/Agent operational independently

**When**:
- External consumer can't fetch bundle; in-cluster pods continue normally

**Then**:
- External federation degraded (Phase 11 cross-cluster impact, irrelevant in Phase 10)
- In-cluster mesh unaffected (uses in-cluster SPIFFE Workload API, not public bundle endpoint)
- Alert `KachoFederationBundleEndpointDown` fires (P3)
- This isolation = important property: external endpoint dependency must NOT take down in-cluster mesh

### 6.10 Hubble observability (3 scenarios)

#### Scenario S10.10.1: Hubble Relay deployed and accessible

**ID**: S10.10.1

**Given**:
- Cilium installed with `hubble.enabled=true`, `hubble.relay.enabled=true`, `hubble.ui.enabled=true`

**When**:
- `kubectl get pods -n kube-system -l app.kubernetes.io/name=hubble-relay`

**Then**:
- Hubble Relay pod running; ClusterIP service `hubble-relay`
- `kubectl port-forward -n kube-system svc/hubble-ui 8080:80` → http://localhost:8080 loads Hubble UI
- UI displays cluster service graph; shows flows with source/dest SPIFFE-IDs, verdicts, encryption status
- `hubble status` CLI shows agent counts, flow rate, version

#### Scenario S10.10.2: Flow telemetry exported to OpenTelemetry

**ID**: S10.10.2

**Given**:
- Hubble configured to export flows via OTLP to `otel-collector.kacho-system.svc:4317`
- Collector deployed (Phase 10 minimal; Phase 11 full stack)

**When**:
- Normal mesh traffic flowing

**Then**:
- `kubectl logs <otel-collector-pod> | grep "received hubble flow"` shows flow log lines
- Phase 10: verify plumbing only; Phase 11 wires to Loki/Tempo
- Collector metrics: `otelcol_receiver_accepted_log_records_total{receiver=otlp/hubble}` > 0

#### Scenario S10.10.3: Drop alert triggers PagerDuty

**ID**: S10.10.3

**Given**:
- Alertmanager rule `KachoPolicyDropsHigh`: `rate(hubble_flows_processed_total{verdict="DROPPED"}[1m]) > 50` for 5 min
- PagerDuty integration via Alertmanager webhook

**When**:
- Simulated attack: test pod in `default` namespace makes 100 reqs/min to kacho-iam (all dropped)

**Then**:
- After 5 min sustained, alert fires
- PagerDuty incident created (severity P2 — lateral movement suspected)
- SOC engineer paged
- Incident contains: top-talker source identity (default/default), dest (kacho-iam), drop reason (policy_denied), count
- After 5 min idle, alert resolves

### 6.11 HSM-backed root CA (4 scenarios)

#### Scenario S10.11.1: PKCS#11 plugin loads CA key from HSM at SPIRE Server start

**ID**: S10.11.1

**Given**:
- Production env: AWS CloudHSM cluster operational; PKCS#11 endpoint accessible
- SPIRE Server config: `plugins.UpstreamAuthority.pkcs11 = { library: /opt/aws-cloudhsm/lib/libcloudhsm_pkcs11.so, key_label: kacho-cloud-root-2026 }`
- Helm Secret `hsm-pkcs11-credentials` populated via External Secrets

**When**:
- SPIRE Server pod starts

**Then**:
- Pod logs: `Loading PKCS#11 plugin`, `CloudHSM session opened`, `CA key loaded from HSM`, `CA certificate self-signed (Subject: spiffe://kacho.cloud)`
- `spire-server-0` Ready
- First SVID issuance signs via HSM (PKCS#11 sign operation); HSM logs show signing op
- Key NEVER leaves HSM boundary (HSM design)

#### Scenario S10.11.2: SVID signing via HSM — observed latency

**ID**: S10.11.2

**Given**:
- HSM operational; SPIRE Server signing SVIDs

**When**:
- 50 pods request initial SVIDs simultaneously (cluster cold start scenario)

**Then**:
- All 50 SVIDs signed within 30s p99
- HSM throughput: ~5-10 sigs/sec (typical CloudHSM); SPIRE Server queues; no failures
- Metric `spire_server_signing_duration_seconds_p99` ~200ms (HSM round-trip)
- If load exceeds HSM capacity → SPIRE Server logs `signing queue full`; alert `KachoHSMSigningQueueBackup` (P2)

#### Scenario S10.11.3: HSM unavailable — SPIRE Server fail-closed for new SVIDs; existing SVIDs continue

**ID**: S10.11.3

**Given**:
- HSM operational; cluster running healthy
- 50 kacho-* pods with active SVIDs

**When**:
- HSM connection lost (simulated: kill VPC peering to CloudHSM; or stop SoftHSM container in dev)
- 3 new pods start requesting initial SVIDs
- 2 existing pods reach 30-min rotation boundary

**Then**:
- New pod SVID requests: SPIRE Server logs `PKCS#11 sign failed: HSM session lost`; queues retry; eventually returns `Unavailable` to Agent → Agent returns to pod → pod CrashLoopBackOff
- Existing pod rotation: same failure; pods cache existing SVID till expiry
- Within 30 min, existing pods' SVIDs expire one-by-one; pods enter degraded state (can't open new mTLS); existing connections continue until they close
- Within 60 min (longest existing SVID expires), entire mesh degraded → critical alert
- Alert escalation: `KachoHSMUnavailable` (P1 immediately) → SRE pages → HSM team
- Phase 11 runbook: HSM recovery procedure
- After HSM restored, SVID issuance resumes; pods recover within ~5-15 min

#### Scenario S10.11.4: SoftHSM (dev/staging) — same code path verification

**ID**: S10.11.4

**Given**:
- Dev env: SoftHSM2 in pod (sidecar to SPIRE Server StatefulSet или separate Deployment)
- PKCS#11 endpoint: `softhsm2-cli` socket mounted to SPIRE Server pod
- Same SPIRE Server config as prod (just different PKCS#11 library path)

**When**:
- SPIRE Server starts in dev

**Then**:
- Same code path as prod (PKCS#11 plugin loads SoftHSM2 library; signs identically)
- Faster latency (no network HSM round-trip)
- Dev cluster tests prod code path; no SoftHSM-specific bugs reach prod
- Acceptable security in dev (private keys in k8s Secret); NOT acceptable in prod (must be CloudHSM)
- Documented: prod helm value `spire.server.ca.plugin: pkcs11+cloudhsm`; dev value `spire.server.ca.plugin: pkcs11+softhsm2`

### 6.12 GitOps registration entries via Argo CD (3 scenarios)

#### Scenario S10.12.1: Registration entry add via PR → Argo CD sync → SPIRE Server registers

**ID**: S10.12.1

**Given**:
- Argo CD installed; watches `kacho-deploy/spire-registration/*.yaml`
- Initial set of registrations deployed (kacho-iam, kacho-vpc, kacho-compute, kacho-loadbalancer, kacho-api-gateway, kacho-ui-admin)

**When**:
- New service `kacho-vpc-implement` added; team writes `kacho-deploy/spire-registration/kacho-vpc-implement.yaml`:
  ```yaml
  apiVersion: kacho.iam.v1/spiffe.kacho.io
  kind: SpiffeRegistration
  metadata:
    name: kacho-vpc-implement
  spec:
    spiffeId: spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc-implement
    selectors:
      - type: k8s
        value: "ns:kacho-system"
      - type: k8s
        value: "sa:kacho-vpc-implement"
      - type: cosign
        value: "image-signature:fp_PLATFORM_TEAM_KEY"
    ttlSeconds: 3600
  ```
- PR created, reviewed, merged

**Then**:
- Within 1-5 min, Argo CD syncs; calls kacho-iam `InternalSpiffeRegistrationService.Upsert` (via internal mux)
- kacho-iam INSERTs row into `spiffe_registrations`; emits operation
- Background worker (in kacho-iam) pushes to SPIRE Server admin API; entry registered
- kacho-vpc-implement pod (already running but in CrashLoopBackOff awaiting SVID) successfully attests next attempt; gets SVID; starts
- Audit event `iam.spiffe.registration.created` in `audit_outbox` with user=Argo CD service account
- Test: `grpcurl -plaintext localhost:9091 kacho.iam.v1.InternalSpiffeRegistrationService.List` shows new entry

#### Scenario S10.12.2: Registration entry delete via PR → SPIRE Server unregisters → pods CrashLoopBackOff

**ID**: S10.12.2

**Given**:
- Service `kacho-deprecated-service` previously had entry
- Team decommissions; deletes `kacho-deploy/spire-registration/kacho-deprecated-service.yaml`
- PR merged

**When**:
- Argo CD detects file removal; calls `InternalSpiffeRegistrationService.Delete(spiffe_id=...)`

**Then**:
- kacho-iam soft-deletes (sets `revoked_at=now()`)
- Background worker calls SPIRE Server admin API to remove entry
- Existing kacho-deprecated-service pods: SVID continues valid until expiry (1h); after that, rotation fails (no registration entry); pods CrashLoopBackOff
- Audit event `iam.spiffe.registration.deleted`
- Recommended: also scale Deployment to 0 in same PR (so pods don't loop after SVID expiry)

#### Scenario S10.12.3: Argo CD reconciler conflicts — last-writer-wins documented

**ID**: S10.12.3

**Given**:
- Argo CD reconciles registration entries
- Hypothetical: operator manually calls `InternalSpiffeRegistrationService.Upsert` via grpcurl (bypassing GitOps)

**When**:
- Manual change applied; Argo CD next sync runs (within 5 min)

**Then**:
- Argo CD detects drift (DB state ≠ git state); reapplies git state
- Manual change reverted
- Audit log shows manual change THEN reversion
- Documented: production policy = no manual changes; emergency operations use git PR with expedited review
- Phase 10 doesn't enforce; Phase 11 adds OPA Gatekeeper policy blocking non-Argo writes to `spiffe_registrations`

### 6.13 Production failover (4 scenarios)

#### Scenario S10.13.1: SPIRE Server primary down → secondary takes over within 15s

**ID**: S10.13.1

**Given**:
- 3-replica SPIRE Server HA; leader = spire-server-0
- Cluster operational with 50 kacho-* pods

**When**:
- Operator kills spire-server-0 (`kubectl delete pod spire-server-0 -n spire-system --grace-period=0 --force`)

**Then**:
- (per S10.1.2) Leader election; new leader within 15s
- No pods experience mTLS disruption
- New pods requesting initial SVIDs succeed via new leader

#### Scenario S10.13.2: SPIRE Agent killed on node — pods on that node retain cached SVIDs

**ID**: S10.13.2

**Given**:
- Node N1 has 10 kacho-* pods running
- SPIRE Agent on N1 running; manages SVIDs for those 10 pods
- Pods have SVIDs valid ~45 min remaining

**When**:
- `kubectl delete pod -n spire-system -l app=spire-agent --field-selector spec.nodeName=N1`

**Then**:
- Agent gone; DaemonSet recreates within 30s
- During 30s window: existing pods on N1 retain cached SVIDs (corelib/spiffe.workloadapi.Client in-memory); existing mTLS continues
- New Agent starts; pods reconnect to Workload API socket (auto-retry)
- Pods' next rotation request (45 min later) handled normally
- No traffic interruption

#### Scenario S10.13.3: Entire SPIRE Server StatefulSet failure (rare) — existing mesh continues until SVID expiry

**ID**: S10.13.3

**Given**:
- All 3 SPIRE Server pods crash (simulated: catastrophic Postgres + HSM dual outage)
- 50 kacho-* pods with SVIDs averaging 30 min remaining

**When**:
- Outage lasts 45 min before recovery

**Then**:
- First 30 min: existing mesh fully operational; new mTLS handshakes succeed using existing SVIDs
- After 30 min: pods at rotation boundaries fail to rotate; degraded
- After 60 min: original SVIDs start expiring; pods enter cascading degradation
- After ~75 min cumulative outage: all pods entered degraded state
- Existing connections survive until close (TLS doesn't force re-handshake during session)
- Operator must recover SPIRE Server before mesh fully fails
- Phase 11 runbook: SPIRE Server disaster recovery
- Alert `KachoSPIREClusterDown` (P1 immediately on detection)

#### Scenario S10.13.4: Cluster failover (Phase 11 scope; placeholder here)

**ID**: S10.13.4

**Given**:
- This is Phase 11 territory; Phase 10 single-cluster only

**When**:
- N/A in Phase 10

**Then**:
- Phase 10 deliverable: documented in `docs/runbooks/iam/` (Phase 11 task 11.7) that cross-cluster failover requires:
  - Per-cluster trust domain (yes, per P10-D3)
  - Federation bundles published (yes, per Phase 10 §6.9)
  - DNS/CDN failover (Phase 11)
  - Postgres HA cross-region (Phase 11)
  - HSM cross-region (Phase 11)
- Phase 10 verifies single-cluster HA is solid; multi-region is Phase 11.

---

## 7. Definition of Done (Phase 10)

### 7.1 Code/PR DoD

- [ ] `kacho-proto` PR merged: all new services + messages; `buf lint` + `buf breaking` green
- [ ] `kacho-corelib` PR merged: `corelib/spiffe` package with unit tests + race tests + 80%+ coverage; in-memory SVID testing utility documented
- [ ] `kacho-iam` PR merged: new `internal/apps/kacho/api/spiffe/*` + migration `0024_kac127_phase10_spiffe_registrations.sql` + domain types + repo + integration tests via testcontainers Postgres (≥10 race tests covering CAS state machine, partial UNIQUE conflicts, EXCLUDE constraint on trust_domain_bundles)
- [ ] `kacho-{vpc,compute,loadbalancer,api-gateway}` PRs merged: `corelib/spiffe` wired into grpcsrv + grpcclient bootstrap; plaintext bootstrap removed (no backward-compat); pod manifests updated
- [ ] `kacho-api-gateway` PR: `FederationBundleService` registered on public mux; `InternalSpiffeRegistrationService` + `InternalSpiffeRevocationService` registered on internal mux ONLY; verified via `grpcurl` from public mux returns `NotFound` on internal methods
- [ ] `kacho-deploy` PR merged: Helm umbrella adds cilium + spire-server + spire-agent dependencies; values.dev/prod populated; templates rendered cleanly (`helm template ... | kubeval`); registration manifests committed; cosign attestor config + HSM PKCS#11 secret references in place
- [ ] `kacho-ui` PR merged: admin SPIFFE pages (read + revoke); restricted to `cluster.kacho-root.security_admin`
- [ ] `kacho-test` PR merged: e2e tests for defense-in-depth (S10.8.x), lateral movement (S10.5.2-3), failover (S10.13.x); CI run green
- [ ] Each PR contains tests (per запрет #11); newman cases for FederationBundleService + admin RPCs added to `kacho-deploy/tests/newman/cases/`

### 7.2 Acceptance Scenario DoD

- [ ] All 50+ scenarios (sections §6.1-§6.13) executed; integration tests cover S10.x.y where automatable; manual tabletop for chaos-style (S10.13.3 multi-replica failure)
- [ ] `kacho-test/tests/e2e/defense_in_depth_kac127.go` covers S10.8.1-S10.8.4
- [ ] `kacho-test/tests/e2e/mesh_lateral_movement.go` covers S10.5.2, S10.5.3, S10.6.4, S10.7.3
- [ ] `kacho-test/tests/e2e/spire_failover.go` covers S10.1.2, S10.1.3, S10.13.1, S10.13.2
- [ ] Hubble UI smoke-test by operator: verify flow graph + drop visualization

### 7.3 Security DoD

- [ ] HSM (CloudHSM or equivalent) operational; PKCS#11 verified; key never exported (verified via HSM audit log)
- [ ] All kacho-* SPIFFE-IDs registered per §2.3 table
- [ ] cosign trusted-signers config = kacho-platform team key only in prod; Fulcio root + kacho-platform in dev/staging
- [ ] CiliumNetworkPolicy default-deny in effect in `kacho-system` ns (test by deploying unauthorized pod)
- [ ] Per-service allowlist CNPs cover all runtime edges from workspace `CLAUDE.md` cross-domain edges table
- [ ] L7 path-based restrictions enforced for `/v1/internal/*` and `/v1/admin/*` on each service
- [ ] WireGuard L3 encryption confirmed (cilium status)
- [ ] Federation bundle endpoint TLS-protected (cert-manager); accessible publicly without auth (correct — bundle is public material)
- [ ] All Internal SPIFFE RPCs verified NOT exposed on external TLS endpoint (test: external curl returns 404)

### 7.4 Observability DoD

- [ ] Hubble UI accessible via port-forward; flow graph populated
- [ ] PagerDuty alerts wired: `KachoSPIREClusterDown`, `KachoHSMUnavailable`, `KachoPolicyDropsHigh`, `KachoForgedJWTAttempt`, `KachoSupplyChainAttackSuspected`, `KachoFederationBundleEndpointDown`, `KachoCriticalReplicaCount`
- [ ] Audit events written to `kacho_iam.audit_outbox` for all SPIFFE admin operations
- [ ] CAEP events written to `kacho_iam.caep_outbox` for SVID revocation + trust-domain rotation
- [ ] Phase 9 audit drainer pending; Phase 10 just emits rows
- [ ] Phase 8 CAEP drainer pending; Phase 10 just emits rows

### 7.5 Documentation / Vault DoD

- [ ] `obsidian/kacho/KAC/KAC-127.md` updated with Phase 10 progress + PR URLs
- [ ] New vault entries: `iam-spiffe-registration.md`, `iam-trust-domain-bundle.md`, `iam-svid-revocation.md` (resources)
- [ ] `iam-federation-bundle-service.md`, `iam-internal-spiffe-registration-service.md`, `iam-internal-spiffe-revocation-service.md` (rpc)
- [ ] `corelib-spiffe.md` (packages)
- [ ] `all-to-mesh-mtls.md`, `spire-agent-to-server.md`, `spire-server-to-hsm.md`, `all-to-spire-workload-api.md`, `kacho-iam-to-cosign-fulcio.md` (edges)
- [ ] `obsidian/kacho/architecture.md` updated with mesh layer + Cilium dataplane
- [ ] Phase 11 runbook stubs created: `docs/runbooks/iam/{spire-server-recovery, hsm-recovery, trust-domain-rotation, svid-revocation, cilium-policy-update}.md` (full content in Phase 11 task 11.7)

### 7.6 Production Cutover DoD

- [ ] Dev cluster: Phase 10 deployed and operational for ≥1 week; no critical incidents
- [ ] Staging cluster: Phase 10 deployed via blue/green; cutover window ≤15 min downtime; operates ≥2 weeks before prod
- [ ] Prod cutover: blue/green via Phase 11 multi-cluster deploy (Phase 10 is single-cluster; prod cutover is **Phase 11 task 11.3** territory — Phase 10 closes when staging clean)
- [ ] Phase 10 closeout: YT KAC-127 Phase 10 subtasks all in `Done`; all PRs merged; staging soak ≥2 weeks; vault closed

---

## 8. Cross-repo PR-chain (Phase 10)

Топологический порядок (по workspace `CLAUDE.md` §"Кросс-репо зависимости"):

1. **kacho-proto PR**: new proto services + messages. **Self-contained**. Merge first. `buf lint`+`buf breaking` green.
2. **kacho-corelib PR**: `corelib/spiffe/` package. Imports kacho-proto via `replace ../`. Merge second.
3. **kacho-iam PR**: implementation + migration. Imports kacho-corelib. Merge third.
4. **kacho-{vpc,compute,loadbalancer,api-gateway} PRs**: parallel (no inter-dependencies between them). Each imports kacho-corelib + kacho-proto. May be merged in any order between themselves. CI in each repo temporarily pins corelib to `KAC-127-phase10` branch until kacho-corelib merged; then `ref: main`.
5. **kacho-deploy PR**: Helm umbrella chart updates. Imports source from steps 3+4. Merge fifth. Includes Cilium + SPIRE Helm dep updates; values; templates; registration manifests; cosign attestor config; HSM secret references.
6. **kacho-ui PR**: admin SPIFFE pages. Independent of mesh wiring; can merge alongside step 5 (uses public RPC FederationBundleService + internal RPCs via cluster-internal port-forward).
7. **kacho-test PR**: e2e tests. Imports api-gateway endpoint. Merge after step 5 (needs deployed services).
8. **kacho-workspace PR**: vault closeout. Last. Documents the merged state.

### 8.1 Cutover order per environment

1. **Dev**: Phase 10 PRs merged → Argo CD syncs → dev cluster gets Cilium + SPIRE → cutover (some hours downtime acceptable). Soak 1-2 weeks.
2. **Staging**: Phase 10 deployed via blue/green helm rollout. Cutover ≤15 min. Soak 2+ weeks.
3. **Prod**: NOT in Phase 10 scope (Phase 11 task 11.3 multi-region cutover handles prod).

### 8.2 Rollback strategy

- Phase 10 == "all-or-nothing per cluster" (per P10-D2). Rollback = re-deploy previous Helm release (which had plaintext mesh).
- Production cluster cutover handled by Phase 11 with blue/green (parallel old+new clusters; DNS switch for traffic shift; old cluster as rollback target).
- For Phase 10 dev/staging, traditional `helm rollback` viable.
- Rollback time SLO: 30 min from decision to restored state.

---

## 9. Out of scope (explicitly NOT in Phase 10)

- **Production multi-region deploy** + cross-region federation + Cloudflare WAF + cross-region Postgres HA — **Phase 11** (`sub-phase-3.11-iam-production-deploy-observability-acceptance.md`)
- **OWASP ASVS L3 + chaos + pentest** — **Phase 12**
- **Vault closeout (30+ files final state)** — **Phase 13**
- **CAEP push drainer** — **Phase 8** (Phase 10 emits to outbox; Phase 8 consumes)
- **Audit pipeline drainer** (Kafka + ClickHouse + S3 + HSM signing) — **Phase 9** (Phase 10 emits to outbox; Phase 9 consumes)
- **OPA Gatekeeper admission policy** (block unsigned image at admission, not just at SVID issuance) — **Phase 11** complement
- **End-user JWT signing via HSM** — Phase 11 (Phase 10 uses existing Kratos JWKS for end-user JWTs; HSM-rooted JWT issuance is Phase 11)
- **Per-tenant trust domains** — explicitly не делаем; one trust domain per cluster per P10-D3
- **External SPIFFE consumers integration with partner systems** — Phase 11+
- **Workload-to-workload short-lived SVIDs (JWT-SVID for stateless cross-mesh)** — current scope is X509-SVID for mTLS; JWT-SVID может быть Phase 12+
- **Reactive trust-domain rotation triggered by key-compromise detection** — Phase 12 chaos scenario; Phase 10 implements manual RotateTrustDomain
- **SPIFFE-CSI driver** (CSI volume for SVID file delivery) — Phase 10 uses hostPath socket; CSI is Phase 12 optimization

---

## 10. Open Questions — RESOLVED

| # | Question | Resolution |
|---|---|---|
| 1 | Should SPIRE Server DataStore share Postgres instance with kacho-iam? | **Yes for dev/staging** (separate schemas, separate users); **No for prod** — dedicated CloudSQL instance (P10-D1). Per запрет #8 — different "service" boundary (SPIRE is its own service); same instance acceptable for cost, schema-level isolation enforced. |
| 2 | cosign vs Notary v2 vs Docker Content Trust for image signature attestation? | **cosign** — most modern, sigstore-backed, native SPIRE attestor plugin exists. Notary v2 considered (planned standard) but tooling immature. DCT obsolete. (P10-D9, P10-D10) |
| 3 | SVID validity 1h vs 5min vs 24h? | **1h** — balance compromise window vs rotation churn (P10-D7) |
| 4 | Trust domain naming: env-suffix (`kacho.cloud`, `kacho.staging.cloud`) vs unified `kacho.cloud`? | **Env-suffix per cluster** — security isolation (P10-D3, P10-D25) |
| 5 | HSM provider: AWS CloudHSM vs GCP Cloud HSM vs Azure Dedicated HSM vs HashiCorp Vault Transit? | **AWS CloudHSM** (assuming AWS deployment); secondary GCP Cloud HSM for GCP cluster (Phase 11 multi-cloud); Vault Transit rejected (key proxy, not true HSM) (P10-D4) |
| 6 | Cilium serviceMesh `authentication.mode: required` vs `optional`? | **required** — no plaintext fallback (P10-D2). Production-edition. |
| 7 | Sidecar mesh (Istio/Linkerd) vs sidecarless (Cilium eBPF)? | **Cilium eBPF** — performance + first-class SPIFFE + single product (P10-D5) |
| 8 | L7 policy enforced in Cilium vs in application code? | **Both layered** — Cilium L7 path-regex first (defense-in-depth); app code OpenFGA Check second (end-user authz). Don't drop either. (P10-D13, P10-D15) |
| 9 | Federation bundle endpoint format: JWKS vs SPIFFE Federation v1 vs both? | **Both via Accept-header negotiation**; default = SPIFFE Federation v1 (P10-D14) |
| 10 | GitOps source-of-truth for registration entries: SPIRE Server DataStore vs separate kacho-iam table? | **kacho-iam table** (`spiffe_registrations`); SPIRE Server DataStore = eventual-consistent mirror (P10-D22) |
| 11 | k8s_psat vs k8s_sat? | **k8s_psat** — projected SA token (current best practice); k8s_sat deprecated (P10-D9) |
| 12 | Per-pod SVID vs per-service SVID? | **Per-service** (all kacho-vpc replicas share `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc`) — k8s-native pattern; replicas can't impersonate each other-or-other-services via SPIFFE-ID; replica-level isolation via OpenFGA + audit |
| 13 | Cilium WireGuard L3 encryption — overhead vs benefit? | **Enable**; ~5-10% throughput overhead acceptable for defense-in-depth (P10-D6) |
| 14 | Hubble UI in production — security risk? | **Restricted access**: cluster-internal only (port-forward для SRE/SOC); Phase 11 Ingress with auth-proxy. Phase 10: port-forward only. |
| 15 | SVID rotation triggered by client (50% lifetime) vs by Agent (push)? | **Client-driven** (50% lifetime); standard go-spiffe v2 pattern. Agent push не реализован в SPIRE v1.10. (P10-D7) |
| 16 | corelib/spiffe.MeshInterceptor mandatory in every handler or only sensitive ones? | **Every gRPC server**; Mesh peer identity capture is cheap (~µs); audit value high; uniform pattern. |
| 17 | What if pod's image signature is verified once (at attestation) but image is mutable in registry? | **Re-verified at each attestation**. SVID rotates every 30 min; signature re-verified at each rotation. If image tampered between rotations, next attestation fails. Plus admission-layer (Phase 11) blocks initial deploy. |
| 18 | Federation bundle endpoint behind auth or public? | **Public** — bundle is public crypto material; auth would be misleading. Rate-limit via Cloudflare in Phase 11. |
| 19 | What happens when Cilium agent on a node is updated mid-flight (rolling upgrade)? | **Brief drop window** (~5-15s per agent restart); pods on that node experience packet drops; mTLS sessions recover at next handshake. Acceptable. Documented. |
| 20 | Are SPIRE Server admin RPCs idempotent? | **Yes** — Upsert (re-apply same registration entry = no-op); Delete (delete already-deleted = no-op + audit); RevokeSvid (idempotent via `(spiffe_id, serial)` partial UNIQUE per P10-D24); RotateTrustDomain — NOT idempotent (each call rotates), guarded by operator confirmation in UI + step-up acr=3. |

---

## 11. Risks & Mitigations (Phase 10)

| Risk | Severity | Mitigation |
|---|---|---|
| **Cluster cutover downtime exceeds 15 min** (per dev/staging cutover) | High | Blue/green deploy pattern; pre-validated Helm chart in staging; rollback within 30 min |
| **HSM provisioning delay** (CloudHSM ramp-up = ~weeks) | Medium | Start in Phase 9 prep; SoftHSM2 for dev/staging same code path |
| **cosign keyless signing for non-prod has Sigstore Rekor dependency** (Rekor outages happen) | Medium | Production uses offline kacho-platform key (no Rekor dep); non-prod accepts brief unavailability |
| **Cilium upgrade compat with existing CNI (Calico/Flannel)** in pre-Phase-10 clusters | Medium | Phase 10 single greenfield deploy (no in-place CNI migration); use new cluster in Phase 11 or follow Cilium migration runbook |
| **Hubble UI flow volume too high → OOM** | Low | `hubble.flowBufferSize: 4096`; OTEL collector buffers; Loki retention 30 days |
| **SPIRE Server Postgres schema clashes with kacho-iam** | Low | Separate schemas (`spire_server` vs `kacho_iam`); separate Postgres users; `search_path` enforced |
| **PKCS#11 plugin library version mismatch with HSM firmware** | Medium | Pin library version in Helm; CloudHSM client lib upgrades per HSM provider matrix; documented in Phase 11 runbook |
| **WireGuard kernel module not available on all nodes** (older kernel) | Medium | Phase 10 requires kernel ≥5.4 (per Cilium docs); node pre-flight check in `make spire-bootstrap` |
| **L7 HTTP/2 + gRPC interactions with Cilium eBPF L7 parser** edge cases | Medium | Extensive integration testing per S10.5.x, S10.6.x; pre-prod soak 2 weeks |
| **Federation bundle endpoint compromise** (DNS hijack, MitM cert) | Medium | Cert-pinning at external consumers (Phase 11 docs); short bundle refresh-hint (300s) limits exposure |
| **Re-attestation thunder-herd after Agent restart** (50 pods all request SVID simultaneously) | Low | HSM signing queue limits; SPIRE Server backpressure; jittered re-attestation in go-spiffe v2 client (built-in) |
| **End-user JWT replay through mesh** (S10.8.2 scenario) | Mitigated | Step-up freshness check (`kacho_mfa_at < 5min` on sensitive ops); DPoP nonce binding (Phase 2 AuthN); rate-limit per principal |
| **Compromised pod replays old SVID after revocation** (race window) | Mitigated | SVID revocation propagation ≤30s p99 (P10-D18); Hubble flow detects continued usage of revoked serial; alert |

---

## 12. References

- SPIFFE spec: <https://spiffe.io/docs/latest/spiffe-about/>
- SPIRE docs: <https://spiffe.io/docs/latest/spire-about/>
- Cilium service mesh: <https://docs.cilium.io/en/stable/network/servicemesh/>
- Cilium Hubble: <https://docs.cilium.io/en/stable/observability/hubble/>
- cosign: <https://docs.sigstore.dev/cosign/overview/>
- Sigstore Fulcio: <https://docs.sigstore.dev/fulcio/overview/>
- AWS CloudHSM PKCS#11: <https://docs.aws.amazon.com/cloudhsm/latest/userguide/pkcs11-library.html>
- go-spiffe v2: <https://github.com/spiffe/go-spiffe>
- SPIFFE Federation v1: <https://github.com/spiffe/spiffe/blob/main/standards/SPIFFE_Federation.md>
- Workspace `CLAUDE.md` — запреты, кросс-репо порядок, кросс-доменные ссылки
- Design doc §6 Class C — in-cluster SPIFFE/SPIRE + Cilium mesh
- Design doc §12 — Workload Identity in-cluster operational
- Design doc §14 — Threat model
- Skill `references/workload-identity.md` §1-§3, §2.2

---

## 13. Sign-off

| Role | Agent | Action | Status |
|---|---|---|---|
| Author | `acceptance-author` (round 2 — production-edition; no backward-compat) | Draft created | ✅ |
| Reviewer | `acceptance-reviewer` | Review for: coverage, completeness, traceability, scope, alignment with запреты #1-#11, alignment with design doc §6 Class C + §12 + plan Phase 10 | ⏳ pending |
| (After APPROVED) | `superpowers:writing-plans` | Convert to detailed implementation plan per task | ⏸ blocked on APPROVED |
| (After plan) | `proto-sync`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester` | Execute tasks | ⏸ blocked on plan |

**Gate**: per запрет #1, no code begins until `acceptance-reviewer` returns ✅ APPROVED on this document. Customer (end-user) does NOT approve this acceptance — they validate smoke/e2e in step 7 per `04-roadmap-and-phasing.md` §2.

---

**End of acceptance doc — Phase 10**
