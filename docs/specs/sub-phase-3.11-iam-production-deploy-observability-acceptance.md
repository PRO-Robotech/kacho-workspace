# Sub-phase 3.11 — IAM Production deployment + Observability (KAC-127) — Acceptance

> **Status**: DRAFT — awaiting `acceptance-reviewer` APPROVED.
> **Date**: 2026-05-19
> **YouTrack**: KAC-127 epic (production-ready next-gen IAM); Phase 11 subtasks per plan §"Phase 11" (Tasks 11.1-11.9).
> **Author agent**: `acceptance-author` (production-edition; no strict backward-compat).
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Design doc**: `docs/superpowers/specs/2026-05-19-iam-prod-ready-next-gen-design.md` — §13 Production deployment (§13.1 topology, §13.2 domain/TLS, §13.3 secrets/KMS, §13.4 CI/CD, §13.5 observability, §13.6 SLO targets), §14 Threat model (DNS hijacking / BGP hijacking / DDoS volumetric / Compromised image / Supply chain / Zero-day), §17 Definition of Done.
> **Plan doc**: `docs/superpowers/plans/2026-05-19-iam-prod-ready-next-gen-plan.md` — Phase 11 (tasks 11.1-11.9).
> **Phase position**: §16 design doc "Migration plan", **Phase 11 of 13**. **Final infrastructure phase before conformance/chaos/pentest (Phase 12) and vault closeout (Phase 13)**.
> **Predecessors (must be merged before code begin)**:
> - Phase 1 — Foundation (`sub-phase-3.1-iam-foundation-acceptance.md`): all DB schema (users, accounts, projects, audit_outbox, caep_outbox, jwks, gdpr, session_revocations, break_glass, access_reviews) exists; cluster_kacho_root singleton seeded.
> - Phase 2 — AuthN core (`sub-phase-3.2-iam-authn-passkey-dpop-acceptance.md`): Kratos WebAuthn + Hydra DPoP + step-up acr=3 + JWKS rotation operational; end-user JWT stable.
> - Phase 3 — AuthZ core (`sub-phase-3.3-iam-authz-fga-conditions-opa-acceptance.md`): OpenFGA v2 + Conditions + OPA sidecar operational; `corelib/authz.Principal` used cluster-wide.
> - Phase 4 — List filtering: ListObjects p95 ≤100ms verified single-region.
> - Phase 5 — Workload Identity Federation (external Class B): `FederationExchangeService` operational.
> - Phase 6 — Enterprise SSO: SCIM 2.0 + SAML bridge operational.
> - Phase 7 — JIT/PIM + Break-glass: 2-person approve + auto-expire + PagerDuty wire stub exists (Phase 11 wires real PagerDuty integration).
> - Phase 8 — CAEP push pipeline (`sub-phase-3.8-iam-caep-push-acceptance.md`): caep_outbox drainer + SET signing + subscriber registry operational single-region (Phase 11 adds cross-region replication of subscriber registry + webhook retry from secondary region).
> - Phase 9 — Audit pipeline (`sub-phase-3.9-iam-audit-pipeline-acceptance.md`): Kafka audit-topic + ClickHouse 2×2 + S3+Glacier + HSM batch signing operational single-region (Phase 11 adds Kafka MirrorMaker 2 cross-region replication + ClickHouse cross-region replicas + S3 multi-region buckets with cross-region replication).
> - Phase 10 — In-cluster Workload Identity + Service Mesh (`sub-phase-3.10-iam-spiffe-spire-cilium-mesh-acceptance.md`): SPIRE Server + Cilium eBPF mesh + WireGuard L3 encryption + cosign image signature attestor operational on single cluster per env (Phase 11 adds cross-cluster federation between prod-eu-central ↔ prod-eu-west trust domains).
>
> **Target repos / merge order (топологическая сортировка graf'а, см. workspace `CLAUDE.md` §"Кросс-репо зависимости")**:
> 1. `PRO-Robotech/kacho-proto` — minimal: no new RPC; only proto annotations on existing messages для `x-kacho-region` metadata and SLO label conventions. (Bulk of Phase 11 is `kacho-deploy` work.)
> 2. `PRO-Robotech/kacho-corelib` — `corelib/observability/` extensions: `otel/tracer.go` (OTLP exporter with trace-id propagation header `traceparent` per W3C Trace Context), `otel/meter.go` (Prometheus-compat metric exporter to Mimir), `otel/logger.go` (slog handler with structured JSON + automatic trace-id field), `region/region.go` (`KACHO_REGION` env var binding; `region.Current()` returns one of `eu-central`/`eu-west`), `slo/budget.go` (SLO error-budget calculator helper for handler-side rate-limit decisions on budget burn).
> 3. All `PRO-Robotech/kacho-{iam,vpc,compute,loadbalancer,api-gateway}` services — wire `corelib/observability/otel` into `cmd/<svc>/main.go` composition root (replace existing ad-hoc Prometheus / log setup); pod labels gain `app.kubernetes.io/component`, `app.kubernetes.io/part-of: kacho-iam-platform`, `kacho.cloud/region: <eu-central|eu-west>`, `kacho.cloud/canary: <true|false>` per Argo CD ArgoRollouts orchestration; readiness/liveness probes consume new health endpoints `/health/live`, `/health/ready`, `/health/startup`.
> 4. `PRO-Robotech/kacho-api-gateway` — `internal/restmux/mux.go` adds region-aware routing headers (`x-kacho-region` set on every response); rate-limit middleware per principal (delegates to Cloudflare edge for IP-level; per-principal in-process token bucket).
> 5. `PRO-Robotech/kacho-deploy` — primary delivery repo (bulk of Phase 11):
>     - `cloudflare-config/{worker.js,dns.tf,waf-rules.tf,page-rules.tf,bot-management.tf,rate-limit.tf}` — Terraform-managed Cloudflare config;
>     - `helm/umbrella/templates/cert-manager-{clusterissuer-letsencrypt-prod,clusterissuer-letsencrypt-staging,api-kacho-cloud-certificate}.yaml`;
>     - `helm/umbrella/templates/ingress-{api,spire,grafana,hubble,argocd}-kacho-cloud.yaml`;
>     - `helm/umbrella/templates/postgres-ha-patroni-{statefulset,configmap,service,pdb,backup-cronjob}.yaml`;
>     - `helm/umbrella/templates/kafka-mirrormaker2-{deployment,configmap,topics-configmap}.yaml`;
>     - `helm/umbrella/templates/clickhouse-cross-region-{replication,materialized-view,distributed-table}.yaml`;
>     - `helm/umbrella/templates/openfga-{read-replica-deployment,writer-statefulset,migration-job,consistency-watchdog}.yaml`;
>     - `helm/umbrella/templates/otel-collector-{daemonset,deployment,configmap-receivers,configmap-exporters,configmap-pipelines}.yaml`;
>     - `helm/umbrella/templates/{tempo,mimir,loki,grafana}-deployment.yaml`;
>     - `helm/umbrella/templates/alertmanager-{deployment,configmap-routing,pagerduty-secret,slack-secret}.yaml`;
>     - `dashboards/{iam-overview,iam-authn,iam-authz,iam-audit-pipeline,iam-caep-pipeline,iam-spiffe-mesh,iam-slo-burn-rate,api-gateway,vpc-overview,compute-overview,loadbalancer-overview,cross-region-replication-lag}.json` — Grafana dashboard JSON committed (each rendered via `grafonnet` or hand-authored);
>     - `alerts/{iam-availability,iam-authz-check-latency,iam-audit-ingest-lag,iam-caep-delivery-lag,iam-jwks-rotation-overdue,iam-cert-renewal-failed,iam-region-failover,iam-postgres-replication-lag,iam-kafka-mirrormaker-lag,iam-clickhouse-replication-lag,iam-openfga-write-error-rate,iam-hubble-policy-drops-spike,iam-supply-chain-anomaly,iam-pkce-failure-rate-spike}.yaml` — Alertmanager `PrometheusRule` CRDs;
>     - `clusters/{prod-eu-central,prod-eu-west,staging,dev}/overrides.yaml` — per-cluster Helm value overrides (region label, Postgres role primary/replica, OpenFGA writer/reader flag, Kafka MirrorMaker role);
>     - `argocd-projects/kacho-iam-platform.yaml` — ArgoCD `AppProject` definition with allowed namespaces + sync policies + RBAC;
>     - `argocd-apps/{dev,staging,prod-eu-central,prod-eu-west}/{kacho-iam,kacho-vpc,kacho-compute,kacho-loadbalancer,kacho-api-gateway,kacho-ui,observability-stack,security-stack,data-plane-stack}.yaml` — ArgoCD `Application` manifests per env per stack;
>     - `argocd-rollouts/{kacho-iam,kacho-vpc,kacho-compute,kacho-loadbalancer,kacho-api-gateway}-rollout.yaml` — `argoproj.io/Rollout` CRDs with canary strategy (5/25/50/100 over 30 min) + analysis templates;
>     - `argocd-analysis-templates/{slo-burn-rate-5m,slo-burn-rate-30m,error-rate-canary-vs-stable,latency-canary-vs-stable}.yaml` — `AnalysisTemplate` CRDs that gate canary promotion;
>     - `renovate.json` (root) + per-sibling `.github/renovate.json` — Renovate configuration with grouped PR (Go deps / Helm charts / npm deps / Docker base images), security-CVE labels, semver-policy;
>     - `.github/workflows/release-iam.yml` (template applied to each sibling) — build container + syft SBOM (SPDX + CycloneDX) + cosign sign --keyless (Sigstore Fulcio) OR cosign sign --key (offline kacho-platform key for prod releases) + in-toto attest-build-provenance (gh-actions/attest-build-provenance@v2) + trivy scan + grype scan + gosec scan; gate fails on HIGH/CRITICAL CVE in new dependencies OR banned-license (GPLv3 family in backend);
>     - `Makefile` targets: `make multi-region-cutover-dry-run`, `make failover-drill-staging`, `make cert-renewal-dry-run`, `make slo-burn-report`, `make sbom-verify`, `make slsa-verify-image`.
> 6. `PRO-Robotech/kacho-deploy/docs/runbooks/iam/` — Phase 11 mandatory deliverable:
>     - `break-glass.md` (Phase 7 stub → full runbook),
>     - `key-rotation.md` (JWT signing / mTLS CA / DB KEK rotation),
>     - `regional-failover.md` (eu-central → eu-west DNS + Postgres + Kafka cutover steps),
>     - `gdpr-erasure.md` (Phase 7 GDPR pipeline operator playbook),
>     - `audit-pipeline-incident.md` (Kafka backlog / ClickHouse split-brain / S3 batch sign failures),
>     - `caep-backlog.md` (subscriber unreachable / retry exhaustion),
>     - `fga-tuple-drift-reconciliation.md` (eventual consistency token drift between regions),
>     - `jwks-rotation-overdue.md` (90d cycle missed; expedited rotation procedure),
>     - `cert-renewal-failed.md` (Let's Encrypt rate-limit / DNS-01 propagation failure / Cloudflare API token rotation),
>     - `kratos-flow-broken.md` (login/registration flow stuck; downstream Hydra failures),
>     - `hydra-token-error.md` (token issuance failure / signing key load failure),
>     - `hsm-recovery.md` (cross-references Phase 10 P10-D17 fail-closed behaviour),
>     - `spire-server-recovery.md` (Phase 10 stub → full incident runbook),
>     - `cilium-policy-update.md` (rollback bad CNP without losing default-deny),
>     - `slo-budget-burn.md` (page when error budget burn rate > 14.4 over 1h — exhausts 30-day budget in 2.5d).
> 7. `PRO-Robotech/kacho-test` — `tests/e2e/{multi_region_failover,cert_auto_renew,slo_burn_synthetic,supply_chain_unsigned_image,argocd_canary_rollback}.go`.
> 8. `PRO-Robotech/kacho-ui` — minimal: `pages/admin/observability/{slo-dashboard-embed,runbook-index,region-status}.tsx`; SOC view embeds Grafana with auth-proxy (Cloudflare Access).
> 9. `PRO-Robotech/kacho-workspace` — vault:
>     - `obsidian/kacho/KAC/KAC-127.md` (Phase 11 progress update),
>     - `obsidian/kacho/architecture.md` (multi-region topology diagram),
>     - `obsidian/kacho/edges/cloudflare-to-api-gateway.md` (new — public TLS termination edge),
>     - `obsidian/kacho/edges/api-gateway-to-cloudflare.md` (new — egress from cluster to Cloudflare API for cert-manager ACME challenges),
>     - `obsidian/kacho/edges/postgres-primary-to-replica.md` (new — cross-region streaming replication),
>     - `obsidian/kacho/edges/kafka-mirrormaker-cross-region.md` (new),
>     - `obsidian/kacho/edges/clickhouse-replicated-merge-tree-cross-region.md` (new),
>     - `obsidian/kacho/edges/argocd-to-kacho-deploy-git.md` (new — GitOps pull),
>     - `obsidian/kacho/edges/argocd-to-cluster-kubeapi.md` (new — GitOps apply),
>     - `obsidian/kacho/edges/otel-collector-to-mimir-tempo-loki.md` (new),
>     - `obsidian/kacho/edges/alertmanager-to-pagerduty.md` (new),
>     - `obsidian/kacho/edges/alertmanager-to-slack.md` (new),
>     - `obsidian/kacho/packages/corelib-observability-otel.md` (new),
>     - `obsidian/kacho/packages/corelib-region.md` (new),
>     - `obsidian/kacho/packages/corelib-slo-budget.md` (new),
>     - `obsidian/kacho/operations/multi-region-topology.md` (new — runbook index),
>     - `obsidian/kacho/operations/slo-targets.md` (new — SLO table + burn rate alerting).

---

## 0. Преамбула — место этой sub-итерации в epic

Phase 11 — **одиннадцатая код-генерирующая Phase** под KAC-127, и **последняя инфраструктурная** до conformance/chaos/pentest (Phase 12) и vault closeout (Phase 13). На входе Phase 11 уже работает (от предшествующих Phase 1-10):

- **AuthN end-user**, **AuthZ ReBAC+ABAC+OPA**, **JIT/PIM + Break-glass**, **CAEP push**, **Audit pipeline (Kafka+ClickHouse+S3+HSM-signed)**, **SPIFFE/SPIRE in-cluster Workload Identity**, **Cilium eBPF service mesh** — все эти plane'ы functional, но **в едином кластере** (dev / staging / prod-eu-central separately, no cross-region active-active).
- **Observability** на baseline-уровне: каждый сервис эмитит Prometheus metrics + slog JSON в stdout (без OTel сборки end-to-end). Grafana уже стоит как часть `kacho-deploy` Phase 0.1 stand для VPC monitoring, но **не аггрегирует** IAM-specific метрики, не строит dashboards для CAEP/Audit/FGA/JWKS, не имеет SLO burn-rate panels, не интегрирован с Tempo/Loki.
- **Alerting** на baseline-уровне: один Alertmanager c stub-config (без PagerDuty/Slack); алерты per service не описаны; runbooks отсутствуют (только Phase 10 P10 P11-D-stub references).
- **Deployment** на baseline-уровне: `kacho-deploy` имеет Helm umbrella chart для одного env'a; `make dev-up` поднимает локально через docker-compose; Argo CD GitOps **не настроен**; cutover вручную через `helm upgrade`; rollback — manual `helm rollback`.
- **Domain / public TLS endpoint**: cluster `api.kacho.local` (internal hostname) + self-signed cert. Никакого `api.kacho.cloud` (публичного TLS endpoint'а) нет, никакого WAF/DDoS, никакого Cloudflare.
- **Supply-chain artifacts**: container images подписаны cosign keyless OIDC (Phase 10 Argo CD/SPIRE cosign attestor требует это), но **SBOM** + **SLSA L3 build provenance** + **vulnerability scan gate** в CI **не добавлены systematic**; зависимости обновляются ad-hoc, без Renovate.

Phase 11 закладывает **production-grade external surface + multi-region active-active + observability + supply-chain** во весь рост:

1. **Public TLS endpoint `api.kacho.cloud`** — primary external-facing hostname (Cloudflare-managed DNS, TLS termination at Cloudflare edge + Let's Encrypt origin cert in cluster via cert-manager). All external clients (browsers via `kacho-ui`, `kacho-yc-shim` CLI shim, external CAEP receivers, external SPIFFE federation consumers) connect here. The internal `api.kacho.local` listener is retained for cluster-internal port-forward / admin debugging only.

2. **Cloudflare WAF + DDoS + bot management + HTTP/3** at the edge:
    - **WAF**: OWASP CRS 3.x rule set (managed rules); custom rules deny known-bad patterns (SQLi attempts, path traversal, malicious user-agents).
    - **DDoS**: L3/L4 (Cloudflare Magic Transit auto-mitigation) + L7 (challenge-response on suspicious patterns; rate-limits per endpoint per IP).
    - **Bot management**: Cloudflare Bot Score header; rate-limit aggressive bots; legitimate bots (Google, Bing) whitelisted.
    - **HTTP/3 (QUIC)**: enabled at Cloudflare edge (Cloudflare → client; Cloudflare → origin remains HTTP/2 over TLS).
    - **Cloudflare Access** (optional, Phase 11): protects `/admin/*` paths with SSO challenge (used by SOC / SRE for Grafana / Hubble UI / Argo CD UI access — independent of in-app authz).

3. **Multi-region active-active deploy** (mvp regions: `prod-eu-central` + `prod-eu-west`):
    - **GeoDNS**: Cloudflare routes user requests to nearest healthy region based on Anycast.
    - **Both regions serve writes**: writer single-master pattern per stateful component (Postgres primary in eu-central, sync replica in eu-west; on failover roles swap atomically via Patroni leader election); OpenFGA writer single-master, read replicas per region; Kafka 3 brokers per region; ClickHouse 2 shards × 2 replicas per region.
    - **Failover semantics**: RTO ≤15 min (DNS TTL 60s + Patroni leader-election ≤30s + traffic drain/refill 5-10 min); RPO ≤1 min (Postgres sync replication; Kafka MirrorMaker 2 cross-region replication; ClickHouse Replicated MergeTree with ZooKeeper-backed consensus or built-in Keeper).
    - **No data loss on planned failover**; up to 60s data loss possible on hard primary-region outage (the un-replicated tail of sync stream).

4. **Postgres HA via Patroni** (3 nodes per region; primary + sync standby per region + async DR replica cross-region):
    - **Per-region HA**: 3-node Patroni cluster (primary + 2 standbys); auto-failover within region on primary-pod-kill < 30s.
    - **Cross-region replication**: eu-central primary streams to eu-west sync standby (low RPO) + async DR replica in eu-west (catches up after primary failure).
    - **Backup**: WAL-G to S3 (encrypted with KMS); point-in-time-recovery (PITR); daily base backup; 30-day retention hot, 7-year cold via S3 Glacier (audit-related schemas only).

5. **Kafka MirrorMaker 2 cross-region replication**:
    - `audit-events` topic replicated eu-central → eu-west with offset translation; Phase 9 ClickHouse consumer in eu-west reads replicated topic.
    - `caep-events` topic replicated; Phase 8 drainer in eu-west reads replicated topic.
    - **Consumer offset preservation**: on regional failover, consumers (Phase 9 ClickHouse loader, Phase 8 CAEP drainer) read from replicated offsets without duplicates (MirrorMaker 2 `OffsetSyncs` topic).

6. **ClickHouse cross-region replication**:
    - `ReplicatedMergeTree` tables with ZooKeeper-backed metadata (or built-in Keeper); 2 shards × 2 replicas per region; cross-region async replication via async fetches.
    - **Distributed** query support: a query in eu-west region returns same audit-event row as eu-central within ≤30s replication lag.
    - **No split-brain**: ZooKeeper/Keeper quorum (3+ nodes cross-region) prevents simultaneous writes to same shard from two regions; one writer master per shard at any time.

7. **OpenFGA read replicas per region; writer single-master**:
    - Writer: single-master in eu-central (writes go to single Postgres primary; eu-west routes writes back to eu-central via internal RPC).
    - Read replicas: per-region OpenFGA replica reads from local Postgres replica; **consistency token** (FGA `OpenFGATuple` consistency value) cross-region propagation tested (Phase 4 ListObjects test extended).
    - On regional failover: writer role moves to eu-west; consistency tokens continue to propagate (cluster cluster); brief 30-60s write-unavailability window during leader election.

8. **Argo CD GitOps**:
    - `kacho-deploy` repo manifests are source of truth.
    - `argocd-projects/kacho-iam-platform.yaml` defines AppProject with allowed namespaces (`kacho-system`, `spire-system`, `observability-system`, `argocd-system`, `cert-manager-system`) + RBAC (only `cluster.kacho-root.platform_admin` can sync prod env).
    - Per-env Applications: `argocd-apps/{env}/{stack}.yaml` for each combination of env (dev/staging/prod-eu-central/prod-eu-west) × stack (kacho-iam, kacho-vpc, kacho-compute, kacho-loadbalancer, kacho-api-gateway, kacho-ui, observability-stack, security-stack, data-plane-stack).
    - **Sync waves**: data-plane-stack (Postgres HA, Kafka, ClickHouse, OpenFGA, ZooKeeper) → security-stack (SPIRE, Cilium, cert-manager) → observability-stack (OTel, Tempo, Mimir, Loki, Grafana, Alertmanager) → application-stack (kacho-iam, kacho-vpc, etc.) → edge-stack (Ingress controllers, Cloudflare worker config).
    - **Canary via ArgoRollouts**: 5% → 25% → 50% → 100% over 30 min per app; analysis templates measure SLO burn rate (canary vs stable error rate, latency p95/p99); **auto-rollback on SLO breach**: if canary's 5-min-window error rate > 2× stable's, ArgoRollouts pauses + rolls back automatically; PagerDuty alert fires.

9. **cert-manager + Let's Encrypt ACME DNS-01 (Cloudflare API token)**:
    - `ClusterIssuer` Let's Encrypt prod (rate-limited; used for `api.kacho.cloud`) + Let's Encrypt staging (used for dev/staging clusters).
    - `Certificate` resource for `api.kacho.cloud` (5 subdomains: `api`, `spire`, `grafana`, `hubble`, `argocd`); cert-manager handles DNS-01 challenge via Cloudflare API token (secret `cert-manager-cloudflare-token` in `cert-manager-system` namespace; rotation policy: yearly).
    - **Auto-renew**: 30 days before expiry; alert `KachoCertRenewalFailed` fires if renewal fails 3 times.
    - **HSTS preload submission**: HSTS header `max-age=63072000; includeSubDomains; preload` served; domain submitted to `hstspreload.org` (manual one-time step documented; **REQUIRES** operator action).

10. **SBOM via syft + SLSA L3 provenance via in-toto + cosign signing + Trivy/Grype/gosec scan**:
    - Per-release CI workflow (`.github/workflows/release-iam.yml` applied to each kacho-* sibling repo) runs syft → produces SBOM in SPDX + CycloneDX formats; SBOM attached to container image registry as OCI artifact via `cosign attach`.
    - SLSA L3 provenance via `gh-actions/attest-build-provenance@v2` → in-toto Statement format → attached as cosign signature on image.
    - cosign keyless signing (Sigstore Fulcio, GitHub Actions OIDC) for **non-prod** builds; cosign sign --key (offline kacho-platform-team PGP/cosign key) for **prod** builds.
    - Trivy + Grype + gosec scan → gate fails on HIGH/CRITICAL CVE in new dependencies OR banned-license (GPLv3 family in backend); existing CVE accepted only with explicit `gh-issue` tracking + remediation SLA per severity.
    - Verification at deploy time: Argo CD sync hook runs `cosign verify` against deployed image; SPIRE Agent's cosign attestor (Phase 10) re-verifies at SVID issuance.

11. **Renovate auto-PR weekly + ASAP security updates**:
    - `renovate.json` config: Go deps grouped by topic (kacho-corelib siblings as single group; observability deps as single group; pgx ecosystem as single group); Helm chart deps grouped; npm/UI deps grouped; Docker base images grouped.
    - Security updates: ASAP (Renovate `vulnerabilityAlerts` enabled, auto-merge minor security CVE if test green).
    - Banned-license check: Renovate rejects any PR introducing GPLv3+ dependency in backend modules; allows MIT/Apache-2.0/BSD/MPL-2.0/Unlicense; LGPL allowed only as transitive (not direct).

12. **OpenTelemetry end-to-end + LGTM stack (Tempo + Mimir + Loki + Grafana)**:
    - **OTel Collector** deployed как hybrid (DaemonSet on every node for log scraping via filelog receiver + dedicated Deployment cluster for metrics aggregation + trace processing); receives OTLP/gRPC from every kacho-* service.
    - **Traces**: 100% sample for control-plane RPC (`kacho-iam`, `kacho-api-gateway`); 5% sample for high-volume data-plane (`kacho-vpc` Watch, `kacho-compute` Lifecycle reconcile, `kacho-loadbalancer` health-check); exported to **Tempo** (7d retention).
    - **Metrics**: per-service standard (Go runtime: GC, goroutines, alloc; gRPC: latency, errors, requests; HTTP: latency, errors, codes) + IAM-specific (Check latency, FGA tuple write rate, CAEP delivery latency, JWKS rotation age, audit Kafka producer lag); exported to **Mimir** (Prometheus-compatible; 30d retention; long-term storage S3 if cost permits).
    - **Logs**: structured slog JSON; PII scrubbed at slog handler (`email → sha256:<hash>`, `password|secret|token → "<redacted>"`); exported to **Loki** via OTel Collector logging receiver (30d retention).
    - **Grafana**: dashboards committed in `kacho-deploy/dashboards/*.json`; per-service + IAM-specific + SLO burn-rate + cross-region replication lag.
    - **Alertmanager**: routing — PagerDuty (P1: cluster down / data loss / supply-chain attack / Hydra/Kratos down; P2: SLO breach / replication lag > threshold) / Slack `#iam-alerts` (P3: warning-level; canary auto-rollback events) / email (P4: informational; quarterly access review reminders).

13. **Runbooks per alert** in `docs/runbooks/iam/*.md` — **mandatory deliverable**; every alert in `alerts/*.yaml` has `annotations.runbook_url` pointing to a `kacho-deploy` runbook file; runbook contains: **Problem → Diagnosis → Mitigation → Escalation → Post-mortem template**; tabletop exercise conducted per critical runbook (break-glass, regional-failover, GDPR-erasure, cert-renewal-failed) — exercise transcripts committed in `docs/runbooks/iam/tabletop-transcripts/`.

14. **SLO targets** (per design doc §13.6):
    - API availability: 99.95% (≤ 4.4h downtime/year) — measured via synthetic black-box probe from external location every 30s.
    - Check p95 latency: ≤ 20ms.
    - ListObjects p95 latency: ≤ 100ms.
    - Revoke propagation (CAEP): ≤ 10s p99.
    - Audit ingest lag: ≤ 60s p99.
    - DR RTO: ≤ 15 min.
    - DR RPO: ≤ 1 min.
    - Cert renewal SLA: ≤ 30 days before expiry (auto-renew kicks at 30d-mark).
    - JWKS rotation SLA: ≤ 90 days (rolling cycle).
    - **Burn rate alerting** (Google SRE workbook style): page on 14.4× burn over 1h window OR 6× burn over 6h window (both exhaust 30d budget very fast).

15. **Per-service HPA (CPU/memory + custom metrics)**:
    - Standard `cpu` (70% target) + `memory` (80% target) HPA.
    - Custom: `kacho-iam` scales on `iam_authz_check_qps` (target 1000/replica); `kacho-api-gateway` scales on `apigw_grpc_concurrent_streams` (target 200/replica).
    - Min replicas: 3 per region (anti-affinity per node); max: 50 per region (cost-cap; alert if hit).

16. **Bluegreen cutover** from existing single-region dev/staging stand to production multi-region stand:
    - Existing `e2c825` dev stand → keep for dev; production stands `prod-eu-central` + `prod-eu-west` are **net-new clusters** provisioned per Phase 11 prerequisites.
    - DNS switch from `api.kacho.local` (internal dev) → `api.kacho.cloud` (public) is **operator-initiated** (per phase 11 runbook); rollback via DNS revert + Cloudflare orange-cloud disable.
    - Smoke verify: external `kacho-yc-shim` CLI exercises Phase 1-10 happy paths (signup → login → DPoP → ProjectService.Get → VPC.NetworkService.Upsert → FGA Check) end-to-end against `api.kacho.cloud`.

**Phase 11 НЕ включает** (это Phase 12-13 одного эпика — НЕ «deferred»):

- **OWASP ASVS L3 conformance** + **continuous fuzzing (go-fuzz)** + **Litmus chaos game-day** + **External pentest engagement** + **Bug bounty program / security.txt** + **OpenID Foundation Self-Certification** + **FIDO Alliance WebAuthn conformance** — **Phase 12** (`sub-phase-3.12-iam-conformance-pentest-chaos-acceptance.md`).
- **Vault closeout (30+ files final state)** — **Phase 13**.
- **Per-tenant isolated regions** (compliance: data residency per EU/US/APAC); Phase 11 ships two EU regions (eu-central + eu-west); US/APAC = follow-up epic, not Phase 11.
- **CAEP back-channel receive** (external IdPs push security events INTO Kachō); Phase 11 has CAEP push-out (from Phase 8); receive is post-Phase-13.
- **mTLS-bound JWT (RFC 8705 cnf=x5t#S256)** — already in scope of Phase 2 AuthN; Phase 11 just deploys the existing infra to production.
- **Post-quantum hybrid TLS (X25519+ML-KEM Kyber768)** — Phase 11 monitors cert-manager + Cloudflare PQ readiness; activates when both support; **not gated** on Phase 11 sign-off (it's a continuous enablement track, design doc D-28).
- **AWS Marketplace / Cloud Foundation listing** — separate go-to-market track post-Phase-13.

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** (workspace `CLAUDE.md`) — кодирование только после `acceptance-reviewer` APPROVED | этот документ — gate; статус выше остаётся `DRAFT` до APPROVED |
| **Запрет #2** — НЕ упоминать "yandex" | в Cloudflare config / cert-manager / Helm-values / Argo CD manifests / Grafana dashboards / Alertmanager configs / Runbooks — не упоминается; brand strings `kacho.cloud`, `kacho-platform-team`, `Kachō Cloud`; CDN provider — Cloudflare; HSM — AWS CloudHSM / GCP Cloud HSM |
| **Запрет #3** — НЕ ORM | observability extensions в `corelib/observability/` — pure stdlib + OTel SDK; no DB access introduced in Phase 11 (purely deploy + observability); existing pgx + sqlc paths unchanged |
| **Запрет #4** — НЕ каскад через границу сервиса | regional failover does NOT trigger cross-service DELETE cascades; each service's own data-plane (kacho_iam, kacho_vpc, kacho_compute Postgres) failover independently per its own Patroni cluster; observability stack (Tempo/Mimir/Loki) failover independently |
| **Запрет #5** — НЕ редактировать применённую миграцию | Phase 11 не вводит новые миграции в сервисные БД (purely deploy + observability); Patroni `pg_basebackup` resync на standby уровне — не migration |
| **Запрет #6** — `Internal.*` НЕ на external TLS endpoint | `api.kacho.cloud` Ingress mapped к **public mux only** (port 8081 на api-gateway); `internal mux` (port 9091) NOT exposed via Cloudflare Ingress; Cloudflare Access guards admin Ingress'ы (Grafana, Hubble UI, Argo CD UI) — they live on **separate hostnames** (`grafana.kacho.cloud`, `hubble.kacho.cloud`, `argocd.kacho.cloud`), still TLS but cluster-internal mux endpoints (port 9091) NOT directly Cloudflare-exposed — admin UIs proxy them server-side |
| **Запрет #7** — НЕ broker | Phase 11 не добавляет broker; используем Kafka, который уже есть с Phase 9 audit pipeline (Phase 9 уже legitimized Kafka under запрет #7 — там было обосновано как "in-process больше не справляется при production volume"); Phase 11 just extends Kafka cross-region via MirrorMaker 2 |
| **Запрет #8** — DB-per-service | каждый сервис имеет свой Patroni cluster (kacho_iam Postgres HA, kacho_vpc Postgres HA, kacho_compute Postgres HA, kacho_loadbalancer Postgres HA); НЕ shared Postgres между сервисами; cross-region replication — within-service (per-Postgres-cluster), не cross-service |
| **Запрет #9** — async-only мутации | Phase 11 не вводит новые RPC mutations; all existing mutations (Phase 1-10) уже return Operation; canary cutover orchestrated by ArgoRollouts — это deploy-time mechanism, не API-mutation |
| **Запрет #10** — within-service refs на DB-уровне | Phase 11 не вводит новые within-service refs (no migrations); Patroni замена streaming replication — DB-internal mechanism, не software refcheck |
| **Запрет #11** — тесты в том же PR | каждый PR Phase 11 содержит: kacho-proto — n/a (минимальные annotation changes); kacho-corelib — unit-tests на `corelib/observability/otel/*` + `corelib/region/*` + `corelib/slo/budget.go`; kacho-deploy — `make multi-region-cutover-dry-run` + `make failover-drill-staging` + `make sbom-verify` + `make slsa-verify-image` + helm template validation (`helm template ... | kubeval`); kacho-test — e2e: multi_region_failover, cert_auto_renew, slo_burn_synthetic, supply_chain_unsigned_image, argocd_canary_rollback |

### 1.1 Production-edition specifics (no strict backward-compat)

- **No staged Cloudflare ramp-up** — `api.kacho.cloud` cut over to Cloudflare proxy mode (orange-cloud) atomically per phase 11 runbook; no "DNS-only" intermediate phase. WAF rules deploy in `simulate` mode for 24h pre-cutover (logs but doesn't block); promoted to `block` mode at cutover.
- **Old `api.kacho.local` listener removed from external clients** — internal listener retained for cluster-internal admin port-forward, but **NOT** advertised publicly; `kacho-yc-shim` CLI default endpoint updated to `api.kacho.cloud` (PRE Phase 11 was `api.kacho.local` for dev/staging).
- **Helm values no `multiregion.enabled: false` knob in prod** — production-edition removes feature flag; cross-region replication always on after Phase 11 prod cutover; dev/staging use single-region overrides (override-files explicit, not flag).
- **No `observability.opt_in: false`** — OTel/LGTM stack always on; PII scrubbing always on; sampling rates per service tuned in Helm values not flag-gated.
- **No PagerDuty bypass** — production P1/P2 alerts ALWAYS page; "snooze" applies only per-alert per-incident, never globally.
- **External resource prerequisites markers** — operations the platform cannot self-provision (domain registration, Cloudflare account, multi-region cloud accounts, HSM provisioning, PagerDuty/Slack tenants) are documented as **explicit prerequisite gates** (see §3 Decision Log + §6 GWT preambles) using format `# REQUIRES <action>`. Phase 11 acceptance does NOT verify these gates as automatable scenarios — they MUST be operator-confirmed BEFORE cutover dry-run.

---

## 2. Глоссарий / доменная модель Phase 11 (нормативно)

### 2.1 Сущности, **созданные** в Phase 11 (deployment + observability)

- **Region** (`corelib/region` package value-object):
  - Enum: `eu-central` | `eu-west` | `staging` | `dev`.
  - Bound via env var `KACHO_REGION`; mandatory in production manifests; `region.Current()` panics if unset in production binary (allowed empty in tests).
  - Propagated in response HTTP header `x-kacho-region` and in OTel resource attributes `kacho.cloud/region`.
  - **Not a domain ресурс** — pure deploy-time metadata.

- **SLO Budget** (`corelib/slo` package value-object):
  - Per-SLO 30d rolling error budget; `slo.Budget(name).BurnRate(window)` returns current burn rate (units: budget consumed per window / total budget over 30d).
  - Burn rate > 14.4 over 1h window → page (P1 alert `KachoSLOBudgetBurn`).
  - Burn rate > 6 over 6h window → page (P2 alert `KachoSLOBudgetBurnSustained`).
  - Burn rate < 1 over 30d → green; admins can deploy.
  - **Not stored** — computed at query time from Mimir metrics.

- **ArgoCD Application / AppProject** (deploy-time CRD):
  - `argocd-projects/kacho-iam-platform.yaml` defines AppProject; limits which namespaces / repos can be synced.
  - `argocd-apps/{env}/{stack}.yaml` — Application CRD per (env, stack) combination.
  - Per-cluster, per-env labels: `app.kubernetes.io/managed-by: argocd`, `argoproj.io/instance: <env>`.
  - Sync waves via `argocd.argoproj.io/sync-wave` annotation: -10 = data-plane, -5 = security, -3 = observability, 0 = application, 5 = edge.

- **ArgoRollouts Rollout** (deploy-time CRD):
  - `argocd-rollouts/{svc}-rollout.yaml` defines canary strategy.
  - Steps: 5% (15min) → 25% (5min) → 50% (5min) → 75% (3min) → 100% (2min) — total 30 min.
  - AnalysisTemplate refs: `slo-burn-rate-5m`, `error-rate-canary-vs-stable`, `latency-canary-vs-stable`.
  - Failure mode: pause + roll back (set stable replicas to 100%, canary to 0%, emit PagerDuty `KachoCanaryRolledBack`).

- **Cloudflare WAF Rule Set** (Terraform-managed):
  - OWASP CRS 3.x managed rule set ON (sensitivity: medium).
  - Custom rules: SQLi denial; path traversal denial; user-agent denial for known scrapers; rate-limit per `cf.client.ip + http.request.uri.path` (100 req / 60s for `/v1/auth/*`; 10 req / 60s for `/v1/iam/v1/breakglass:activate`).
  - WAF actions logged → Cloudflare Logpush → S3 → ClickHouse (Phase 9 audit pipeline extension; pipeline runs Phase 11+).
  - Test mode `simulate` → 24h soak before promoting to `block`.

- **cert-manager Certificate** (deploy-time CRD):
  - `Certificate/api-kacho-cloud-tls` in `kacho-system` namespace; secret `api-kacho-cloud-tls-secret`; DNS names: `api.kacho.cloud`, `spire.kacho.cloud`, `grafana.kacho.cloud`, `hubble.kacho.cloud`, `argocd.kacho.cloud`.
  - `IssuerRef`: `ClusterIssuer/letsencrypt-prod` (prod) or `ClusterIssuer/letsencrypt-staging` (dev/staging).
  - DNS-01 challenge via Cloudflare API token (secret `cert-manager-cloudflare-token`); cert-manager solver `dns01.cloudflare`.
  - Auto-renew 30d before `notAfter`; status conditions tracked в Prometheus via cert-manager-controller metrics (`certmanager_certificate_expiration_timestamp_seconds`).

- **Patroni Cluster** (deploy-time StatefulSet config):
  - 3 nodes per region (primary + 2 sync standbys); cross-region — async DR replica eu-central → eu-west.
  - DCS = etcd (3 nodes anti-affinity); leader election via etcd lease.
  - Failover: < 30s within region; cross-region (planned) ≤ 15 min via DNS + Patroni manual promote.

- **Kafka MirrorMaker 2** (deploy-time Deployment):
  - One MM2 cluster per direction: eu-central → eu-west (audit-events + caep-events topics).
  - Per-topic offset translation via `mm2-offset-syncs` internal topic; consumers see consistent offsets cross-region.
  - Replication lag exported as `mm2_replication_lag_ms` metric → Mimir → alert `KachoKafkaMirrorMakerLag` if > 5s sustained 5min.

- **ClickHouse Replicated MergeTree + Distributed table**:
  - Per-region: 2 shards × 2 replicas (4 nodes) backed by `ReplicatedMergeTree` + ZooKeeper-backed (or Keeper) metadata.
  - Cross-region: async fetch replication (each region's shard replica from eu-central → eu-west uses `clickhouse-keeper` async fetch); replication lag exported `chr_replica_max_absolute_delay`.
  - Distributed table `audit_events_dist` spans cluster `audit_cluster` defined per env; queries from either region return data from both shards transparently.

- **OpenTelemetry Collector** (DaemonSet + Deployment):
  - DaemonSet: filelog receiver (scrape Pod stdout → forward to Loki); host-metrics receiver (node-level CPU/mem/disk).
  - Deployment (3 replicas, cluster-wide): OTLP/gRPC receiver (from kacho-* services); processors: `attributes` (PII scrub: `email → sha256`, `password|token → redact`), `resource` (add `kacho.cloud/region`, `kacho.cloud/cluster`, `kacho.cloud/canary`), `batch`, `tail_sampling` (Tempo 100% for control-plane / 5% for data-plane).
  - Exporters: `otlp/tempo` (traces), `prometheus/mimir` (metrics via remote-write), `loki/loki` (logs via push-API).

- **Tempo / Mimir / Loki / Grafana** (deploy-time Deployments):
  - Tempo single-binary or microservices (per env scale); 7d retention; S3 backend.
  - Mimir microservices (ingester, querier, store-gateway, compactor); 30d retention; S3 backend; ruler for recording rules + alerts.
  - Loki single-binary or microservices; 30d retention; S3 backend.
  - Grafana: dashboards mounted via ConfigMap; data sources Mimir + Tempo + Loki configured via JSON config; OIDC auth via Kratos (`grafana.kacho.cloud` SSO).

- **Alertmanager + PagerDuty + Slack integration**:
  - Alertmanager 3 replicas (anti-affinity); routes via labels `severity: P1|P2|P3|P4`, `team: iam-platform`.
  - PagerDuty receiver: webhook URL + service key (secret `alertmanager-pagerduty-key`); P1/P2 → page; P3/P4 → no PD.
  - Slack receiver: webhook URL + `#iam-alerts` channel (secret `alertmanager-slack-webhook`); P1-P3 → message; P4 → no Slack.
  - Email receiver: SMTP relay → on-call rotation email aliases; all severities → email (low-priority informational).

### 2.2 Сущности, **переиспользуемые / расширяемые** в Phase 11

- **corelib/observability** (Phase 0.1 baseline) — extended with `otel/` subpackages (`tracer.go`, `meter.go`, `logger.go`); previous slog-only logger replaced with OTel-bridged slog; metrics endpoint replaced with OTLP push.
- **corelib/grpcsrv** (Phase 0.1) — gains OTel server interceptor (trace span per RPC; metric per RPC); SPIFFE mTLS interceptor (Phase 10) chain ordering documented: `otel → spiffe → authn → authz → handler`.
- **corelib/grpcclient** (Phase 0.1) — gains OTel client interceptor (trace span propagation via `traceparent` header).
- **audit_outbox** (Phase 1) — new event-types: `iam.deploy.canary.started`, `iam.deploy.canary.promoted`, `iam.deploy.canary.rolled_back`, `iam.deploy.regional_failover.started`, `iam.deploy.regional_failover.completed`, `iam.deploy.cert_renewed`, `iam.deploy.cert_renewal_failed`.
- **caep_outbox** (Phase 1, 8) — no new event-types in Phase 11; existing CAEP events replicated cross-region via Kafka MirrorMaker 2.

### 2.3 SLO targets (Phase 11 canonical; design doc §13.6)

| SLO | Target | Measurement | Burn-rate alert |
|---|---|---|---|
| **API availability** | 99.95% (≤ 4.4h/year) | Synthetic blackbox probe from external location every 30s against `api.kacho.cloud/health/live` | `KachoAPIAvailabilityBurn1h` (P1) > 14.4×; `KachoAPIAvailabilityBurn6h` (P2) > 6× |
| **Check p95 latency** | ≤ 20ms | Histogram `iam_authz_check_duration_seconds_bucket` p95 over 5min window | `KachoAuthzCheckLatencyHigh` (P2) > 20ms sustained 10min |
| **ListObjects p95 latency** | ≤ 100ms | Histogram `iam_authz_listobjects_duration_seconds_bucket` p95 over 5min | `KachoAuthzListObjectsLatencyHigh` (P2) > 100ms sustained 10min |
| **CAEP delivery latency** | ≤ 10s p99 | Histogram `caep_delivery_duration_seconds_bucket` p99 over 5min | `KachoCAEPDeliveryLag` (P2) > 10s sustained 5min |
| **Audit ingest lag** | ≤ 60s p99 | Histogram `audit_ingest_lag_seconds_bucket` p99 over 5min | `KachoAuditIngestLag` (P2) > 60s sustained 5min |
| **DR RTO** | ≤ 15 min | Measured during quarterly failover drill (`make failover-drill-staging`) | n/a (drill-validated) |
| **DR RPO** | ≤ 1 min | Postgres sync replication lag `pg_replication_lag_seconds` | `KachoPostgresReplicationLag` (P1) > 60s |
| **Cert renewal SLA** | ≤ 30d before expiry | cert-manager metric `certmanager_certificate_expiration_timestamp_seconds - time()` | `KachoCertRenewalOverdue` (P2) < 30d |
| **JWKS rotation SLA** | ≤ 90d | kacho-iam metric `iam_jwks_key_age_seconds` for current signing key | `KachoJWKSRotationOverdue` (P2) > 90d * 0.9 |
| **Kafka MirrorMaker lag** | ≤ 5s p99 | `mm2_replication_lag_ms` per topic per direction | `KachoKafkaMirrorMakerLag` (P2) > 5s sustained 5min |
| **ClickHouse cross-region lag** | ≤ 30s p99 | `chr_replica_max_absolute_delay` | `KachoClickHouseReplicationLag` (P2) > 30s sustained 5min |
| **OpenFGA write error rate** | ≤ 0.1% | Counter ratio | `KachoOpenFGAWriteErrorRate` (P2) > 0.1% sustained 5min |

### 2.4 Regional ownership (Phase 11 canonical)

| Stateful component | Writer master region | Read replica regions | Failover mechanism |
|---|---|---|---|
| **kacho_iam Postgres** | eu-central (primary) | eu-west (sync standby) + eu-west (async DR) | Patroni leader election |
| **kacho_vpc Postgres** | eu-central (primary) | eu-west (sync) + eu-west (async DR) | Patroni leader election |
| **kacho_compute Postgres** | eu-central (primary) | eu-west (sync) + eu-west (async DR) | Patroni leader election |
| **kacho_loadbalancer Postgres** | eu-central (primary) | eu-west (sync) + eu-west (async DR) | Patroni leader election |
| **OpenFGA** | eu-central writer single-master | eu-central reader + eu-west reader | Postgres failover triggers writer move |
| **Kafka** | eu-central 3 brokers AND eu-west 3 brokers (both active) | n/a (MirrorMaker replicates topics) | Per-cluster Kafka KRaft quorum |
| **ClickHouse** | eu-central 2 shards × 2 replicas AND eu-west 2 shards × 2 replicas | cross-region async fetch | ZooKeeper/Keeper quorum |
| **SPIRE Server (Phase 10)** | per-cluster (3 replicas single cluster) | n/a per Phase 10 trust-domain isolation | per-cluster Patroni-backed Postgres DataStore |
| **Cilium (Phase 10)** | per-cluster | n/a | per-cluster cilium-agent DaemonSet |
| **Tempo (observability)** | eu-central | eu-west (separate Tempo cluster + S3 cross-region bucket replication) | per-region; on regional failure, dashboards point to surviving region |
| **Mimir** | eu-central writer + eu-west writer (both active; HA receiver) | per-region readers; long-term S3 multi-region | per-region; HA dedup |
| **Loki** | per-region | per-region; long-term S3 multi-region | per-region |
| **Grafana** | eu-central (primary) | eu-west (read-only failover) | DNS failover |

---

## 3. Decision Log (Phase 11)

### P11-D1: Public domain = `api.kacho.cloud` Cloudflare-managed DNS (operator prerequisite)

**Decision**: Domain `kacho.cloud` registered (operator action; **REQUIRES domain registration completed** — Phase 11 precondition gate); DNS at Cloudflare; primary external hostname `api.kacho.cloud`; secondary public subdomains `spire.kacho.cloud` (federation bundle, Phase 10), `grafana.kacho.cloud` (Cloudflare-Access-protected), `hubble.kacho.cloud` (Cloudflare-Access-protected), `argocd.kacho.cloud` (Cloudflare-Access-protected).

**Rationale**: Production grade requires stable, branded, externally-resolvable hostname; Cloudflare-managed DNS provides Anycast, DNSSEC, fast TTL propagation, RPKI for BGP hijack defense, and integrated WAF/DDoS without separate vendor. Subdomain pattern keeps admin surfaces on separate hostnames so they can carry Cloudflare Access independently of public API.

**Alternatives considered**: Route53 + AWS WAF (rejected — Cloudflare's L3/L7 DDoS protection + bot management is industry-leading at this scale; multi-vendor adds operational surface); self-hosted DNS (rejected — no Anycast, slow propagation, security maintenance burden); subdomain pattern `api-{env}.kacho.cloud` for envs (rejected — production stays on bare `api.kacho.cloud`; dev/staging keep internal `*.kacho.local`).

### P11-D2: TLS 1.3 only; ECDSA P-256 certs; HSTS preload max-age=2y

**Decision**: Cipher suites = TLS 1.3 only (no TLS 1.2 fallback); ECDSA P-256 certificate (RSA-2048 alternate); HSTS header `max-age=63072000; includeSubDomains; preload` served on every response; domain submitted to `hstspreload.org` (operator action; **REQUIRES HSTS preload submission**).

**Rationale**: TLS 1.3 mandatory closes downgrade attacks; ECDSA P-256 smaller signature + faster handshake than RSA; HSTS preload eliminates first-visit MITM window (browser ships hardcoded HSTS for our domain). Submission is one-time operator step but irreversible (12+ months to remove via opt-out); committed.

**Alternatives considered**: TLS 1.2+TLS 1.3 (rejected — keeps known weak ciphers exploitable); RSA-only (rejected — ECDSA faster handshake matters at 99.95% SLO); no HSTS preload (rejected — leaves window for first-visit MITM).

### P11-D3: HTTP/3 (QUIC) enabled at Cloudflare edge only; origin remains HTTP/2

**Decision**: Cloudflare → client uses HTTP/3 (QUIC) when client supports; Cloudflare → origin (k8s Ingress) remains HTTP/2 over TLS (k8s Ingress NGINX QUIC support immature, kernel UDP perf not validated for our workload).

**Rationale**: HTTP/3 client-facing reduces latency (1-RTT TLS+QUIC vs 2-RTT TLS+TCP); mobile networks benefit most. Origin HTTP/2 is mature and adequate. Revisit origin HTTP/3 in Phase 12+ if NGINX QUIC stabilizes.

**Alternatives considered**: HTTP/3 end-to-end (rejected — origin maturity gap); HTTP/2 only (rejected — leaves mobile latency on table).

### P11-D4: Multi-region active-active (eu-central + eu-west; both serve writes)

**Decision**: Two production regions: `prod-eu-central` (primary writer master per stateful) + `prod-eu-west` (sync replica writer-on-failover); both regions serve reads continuously; GeoDNS routes user requests to nearest region. **REQUIRES multi-region cloud accounts** (AWS or GCP eu-central + eu-west provisioned; operator prerequisite).

**Rationale**: Active-active reduces failover time vs cold-standby (no warm-up); GeoDNS reduces user-perceived latency by routing to nearest region; satisfies design doc D-21 (RTO ≤15min / RPO ≤1min); satisfies J36 user journey (multi-region failover preserves session via JWKS replication).

**Alternatives considered**: Active-passive (rejected — cold start = 5-10min just to warm caches; doesn't hit RTO 15min reliably); single-region (rejected — design D-21 mandates multi-region for production); three regions (rejected for Phase 11 — eu-central+eu-west is mvp; APAC/US follow-up epic).

### P11-D5: Postgres HA via Patroni (per-region 3-node + cross-region sync standby)

**Decision**: Patroni 3-node cluster per region per service-Postgres; primary in eu-central; sync standby in eu-west; async DR replica in eu-west. DCS = etcd 3-node anti-affinity. WAL-G to S3 for PITR + base backups.

**Rationale**: Patroni is production-mature OSS solution; sync replication satisfies RPO ≤1 min; cross-region sync replica enables fast failover without warm-up; etcd DCS provides distributed consensus for leader election; WAL-G + S3 satisfies backup + PITR + 7-year archival via Glacier.

**Alternatives considered**: CloudSQL HA / Aurora (acceptable for AWS; deferred to per-cloud per-env override; **REQUIRES cloud HSQL provider** — operator selection); Stolon (rejected — Patroni broader community); manual streaming replication (rejected — no automatic failover); pgpool-II (rejected — connection pooling not HA).

### P11-D6: Kafka MirrorMaker 2 cross-region (audit-events + caep-events)

**Decision**: MM2 replicates `audit-events` and `caep-events` topics eu-central → eu-west; offset-syncs topic enables consumer-offset translation; ClickHouse loader (Phase 9) + CAEP drainer (Phase 8) in eu-west region read from replicated topics with translated offsets on regional failover.

**Rationale**: Kafka native cross-region replication via MM2 is canonical for audit/event topics; offset translation prevents duplicates on failover; satisfies design doc D-21 RTO/RPO.

**Alternatives considered**: Confluent Replicator (rejected — proprietary, vendor lock-in); Kafka Connect manually (rejected — MM2 supersedes); single-region Kafka (rejected — leaves audit pipeline single-region SPOF).

### P11-D7: ClickHouse cross-region via Replicated MergeTree + Keeper

**Decision**: Per-region 2 shards × 2 replicas via `ReplicatedMergeTree`; cluster `audit_cluster` defined per env spans all regions for distributed queries; ZooKeeper-backed or built-in Keeper for consensus (Phase 11 uses Keeper to reduce operational surface).

**Rationale**: `ReplicatedMergeTree` is canonical ClickHouse HA pattern; Keeper avoids separate ZooKeeper; distributed table allows query from any region returns data from all shards; replication lag bounded ≤30s p99.

**Alternatives considered**: Single-region ClickHouse + S3 export to other regions (rejected — distributed query latency hit; doesn't meet RTO); CockroachDB (rejected — OLAP analytics not its strength); BigQuery / Snowflake (rejected — vendor lock-in; cross-region replication expensive).

### P11-D8: OpenFGA read replicas per region; writer single-master

**Decision**: OpenFGA writer single-master in eu-central (writes route to writer regardless of caller region; +5-30ms cross-region hop cost); read replicas per region (`Check`/`ListObjects` served locally). On regional failover writer role moves to eu-west (manual promote via runbook, ~30-60s write-unavailability window).

**Rationale**: ReBAC consistency model needs single writer for global tuple ordering; cross-region async replication of tuples acceptable for read (consistency token allows clients to read-after-write within same region; cross-region eventual within seconds).

**Alternatives considered**: Active-active writer (rejected — OpenFGA does not natively support multi-writer; conflict resolution complex); single-region writer no read replicas (rejected — Check p95 ≤20ms requires local reads).

### P11-D9: Argo CD GitOps; canary 5→25→50→100 over 30 min; auto-rollback on SLO breach

**Decision**: All Helm releases driven by Argo CD watching `kacho-deploy` repo; ArgoRollouts orchestrates canary; AnalysisTemplate gates each step on (a) error rate canary vs stable ≤2× baseline (b) SLO burn rate < 14.4× (c) p95 latency canary vs stable ≤1.5× baseline. Failed analysis pauses; sustained failure auto-rolls back. PagerDuty `KachoCanaryRolledBack` fires.

**Rationale**: GitOps gives audit trail, reviewable changes, rollback via git revert; ArgoRollouts standard pattern for canary; SLO-based gating prevents bad release affecting users at 5% traffic threshold; 30-min duration balances catch-rate (longer = more signal) vs deploy throughput.

**Alternatives considered**: FluxCD (rejected — comparable but Argo CD ecosystem maturity higher; Argo CD UI superior for SRE); Spinnaker (rejected — heavier operational surface); manual `helm upgrade` (rejected — no audit, no canary, no auto-rollback).

### P11-D10: cert-manager + Let's Encrypt ACME DNS-01 via Cloudflare API

**Decision**: `ClusterIssuer/letsencrypt-prod` (prod) + `ClusterIssuer/letsencrypt-staging` (dev/staging); Certificate for 5 subdomains; DNS-01 challenge via Cloudflare API token (secret rotated yearly). Auto-renew at 30d before expiry. **REQUIRES Cloudflare API token in K8s Secret** (operator prerequisite; created with Zone:DNS:Edit scope only).

**Rationale**: Let's Encrypt free + ACME automation = no manual cert handling; DNS-01 supports wildcard certs (we don't need wildcards but DNS-01 also doesn't expose HTTP-01 endpoint); cert-manager handles renewal + rotation; staging issuer used for non-prod to avoid LE rate-limits.

**Alternatives considered**: AWS ACM (rejected — only works with AWS endpoints; not portable cross-cloud); ZeroSSL (rejected — Let's Encrypt mature + free); manual cert renewal (rejected — operational burden, missed-renewal risk).

### P11-D11: SBOM = syft (SPDX + CycloneDX); attached as OCI artifact

**Decision**: Per-release CI generates SBOM via syft in BOTH SPDX-JSON and CycloneDX-JSON formats; attached to image via `cosign attach sbom`. SBOM ingested into vulnerability scanning pipeline (Phase 12 extends with continuous CVE matching).

**Rationale**: SPDX is ISO standard (compliance), CycloneDX is OWASP standard (industry); both formats consumed by different tooling (Dependency-Track, Snyk, GitHub Security); cosign attach makes SBOM cryptographically bound to image.

**Alternatives considered**: Single format (rejected — different consumers use different formats; minimal cost to dual-publish); trivy sbom (rejected — trivy SBOM format less standardized than syft).

### P11-D12: SLSA L3 build provenance via gh-actions/attest-build-provenance@v2

**Decision**: Per-release CI generates in-toto Statement (SLSA Provenance v1.0 predicate) via GitHub Action `actions/attest-build-provenance@v2`; attestation attached as cosign signature; deploy-time verifier confirms provenance subject matches image digest + builder identity matches `github.com/PRO-Robotech/<repo>` + workflow file matches `.github/workflows/release-iam.yml`.

**Rationale**: SLSA L3 requires (a) source integrity (git provenance) (b) build platform integrity (hosted GitHub-Actions runners) (c) provenance generation by builder (gh-actions/attest-build-provenance signs in-toto Statement with Fulcio OIDC); meets compliance requirements for SOC 2 + supply-chain attestation.

**Alternatives considered**: Manual SLSA generation (rejected — error-prone, not Sigstore-rooted); self-hosted runner (rejected — degrades SLSA L3 to L2; hosted runners audited by GitHub).

### P11-D13: cosign keyless OIDC for non-prod; offline key for prod

**Decision**: Non-prod release CI: cosign sign-blob --keyless via Sigstore Fulcio + GitHub Actions OIDC (no key management). Prod release CI: cosign sign --key <kacho-platform-team-cosign-key>; key stored offline (HSM-backed in operator vault); annually rotated.

**Rationale**: Keyless OIDC = convenience for fast non-prod iteration + auditability via Rekor transparency log; offline key for prod = highest assurance (no Rekor/Fulcio uptime dependency in critical path; no IAM token compromise → sign). Phase 10 SPIRE attestor verifies BOTH signature methods (cosign verify reads either).

**Alternatives considered**: Keyless only (rejected for prod — Rekor outage = no deploys; Phase 10 already requires offline key for prod attestor); offline only (rejected for non-prod — operator overhead too high for daily iteration).

### P11-D14: Container vulnerability scan (Trivy + Grype + gosec); block on HIGH/CRITICAL

**Decision**: Per-release CI runs trivy + grype + gosec scans; PR-promotion blocked if ANY HIGH/CRITICAL CVE introduced in PR diff (delta-only; existing pre-PR CVE accepted with `gh-issue` tracking + remediation SLA). gosec for Go-specific source patterns (hardcoded credentials, SQL string concat).

**Rationale**: Two scanners (trivy, grype) reduce false-negative rate (different CVE DBs); gosec catches application-layer bugs scanners miss; delta-only blocking prevents legacy CVE deadlock while preventing new regressions.

**Alternatives considered**: Single scanner (rejected — CVE DB coverage gaps); block on all CVE regardless of severity (rejected — most LOW/MEDIUM CVE are theoretical; would deadlock); ignore in CI (rejected — supply-chain attack defense critical).

### P11-D15: Renovate auto-PR weekly + ASAP security updates; grouped by topic

**Decision**: Renovate config: schedule weekly batch PR + immediate security-CVE PR; grouped: kacho-corelib + kacho-proto (single PR; consistent versions), Helm chart deps, Docker base images, observability stack (OTel/Tempo/Mimir/Loki), npm for UI. Auto-merge minor security CVE if green CI; manual approve major versions.

**Rationale**: Weekly batch reduces PR noise vs daily-per-dep; grouping reduces merge conflicts; ASAP security catches zero-days; banned-license check (GPLv3 family in backend) prevents license-compliance regression.

**Alternatives considered**: Dependabot (rejected — Renovate richer grouping); manual updates (rejected — slow, misses patches); no-update (rejected — accumulates CVE debt).

### P11-D16: OTel Collector deployed hybrid DaemonSet + Deployment

**Decision**: DaemonSet for node-local concerns (filelog scraping, host-metrics); Deployment (3 replicas) for cluster-wide aggregation (OTLP/gRPC from kacho-* services + processors + exporters). PII scrubbing processor inserted at top of pipeline.

**Rationale**: Filelog needs node access (Pod stdout via /var/log); host-metrics needs hostNetwork; both = DaemonSet pattern. Cluster-wide aggregation needs HA = Deployment. Hybrid reduces per-node memory (DaemonSet has minimal processors; Deployment has full pipeline).

**Alternatives considered**: DaemonSet only (rejected — no HA for processing); Deployment only (rejected — filelog/host-metrics need DaemonSet); managed OTel (rejected — no cloud-portable; degrades multi-region story).

### P11-D17: LGTM stack (Tempo + Mimir + Loki + Grafana)

**Decision**: Grafana Labs LGTM stack — Tempo (traces), Mimir (Prometheus-compat metrics), Loki (logs), Grafana (UI). All Apache-2.0; S3 backend for retention; per-tenant isolation via header (Phase 12+ for multi-tenant SaaS; Phase 11 single-tenant `kacho-platform`).

**Rationale**: Single vendor (Grafana Labs) reduces operational surface; Apache-2.0 OSS no vendor lock-in; S3 backend cheap long-term storage; Prometheus-compat means existing recording rules + Alertmanager unchanged; mature production deployments at scale.

**Alternatives considered**: Datadog (rejected — vendor lock-in, cost scales linearly with cardinality); Elastic stack (rejected — Logstash + Elasticsearch heavyweight; recent license changes); split vendors per signal (rejected — operational fragmentation).

### P11-D18: Alertmanager routing: PagerDuty (P1/P2) + Slack (P1-P3) + email (all)

**Decision**: Severity labels P1 (page; cluster-down, data-loss, supply-chain attack), P2 (page; SLO breach, replication lag), P3 (Slack only; warning), P4 (email only; informational). PagerDuty service per severity; Slack channel `#iam-alerts`; email to on-call rotation.

**Rationale**: Tiered severity ensures critical alerts wake people (PagerDuty); P3 surface in chat for awareness without paging; email captures all for audit/review. SLO-based labels keep alert taxonomy aligned with reliability.

**Alternatives considered**: PagerDuty for all (rejected — alert fatigue → ignored P1s); Slack for all (rejected — Slack missable, no 24/7 escalation); custom in-house pager (rejected — operational burden).

### P11-D19: Runbook mandatory per alert; tabletop tested quarterly

**Decision**: Every Prometheus alert rule has `annotations.runbook_url` pointing to runbook in `kacho-deploy/docs/runbooks/iam/<name>.md`. Each critical runbook (break-glass, regional-failover, GDPR-erasure, cert-renewal-failed) tabletop-tested quarterly (recorded transcript committed to `docs/runbooks/iam/tabletop-transcripts/`).

**Rationale**: Alert without runbook is noise; on-call SRE needs Problem → Diagnosis → Mitigation → Escalation → Post-mortem template; tabletop validates runbook is followable under stress.

**Alternatives considered**: Inline runbook in alert annotations (rejected — limited length, no version control); informal "ask SRE channel" (rejected — depends on individual availability, knowledge loss).

### P11-D20: SLO availability target = 99.95% (≤4.4h/year downtime)

**Decision**: Synthetic blackbox probe from external Cloudflare worker location every 30s → ` api.kacho.cloud/health/live` → expected 200 OK + `<10s` latency. Availability = uptime / total_time over 30-day rolling window. Burn-rate alerts at 14.4× (1h) and 6× (6h).

**Rationale**: 99.95% is industry-standard for control-plane (not 99.99% which requires 5x cost increase for incremental gain); blackbox external probe = user-perceived availability (not internal liveness); burn-rate alerting catches fast incidents (1h) + slow degradation (6h).

**Alternatives considered**: 99.99% (rejected — 5x cost for marginal user gain; achievable only with global multi-region active-active + multi-cloud); 99.9% (rejected — design doc D-21 mandates better); internal-probe-only (rejected — misses CDN/edge issues).

### P11-D21: Per-service HPA standard + custom metrics

**Decision**: HPA on CPU 70% + memory 80% + custom metric where applicable (`iam_authz_check_qps` for kacho-iam, `apigw_grpc_concurrent_streams` for api-gateway). Min replicas 3 per region (anti-affinity per node); max 50 per region (cost-cap).

**Rationale**: CPU/memory baseline catches general load; custom metric catches workload-specific (Check QPS is the IAM-defining load — scale on it not just CPU); min 3 = HA + anti-affinity; max 50 + alert prevents runaway scale.

**Alternatives considered**: VPA only (rejected — vertical scaling has hard limits, slow); cluster-autoscaler-only (rejected — pod-level HPA + cluster-level CA both needed); single replica (rejected — no HA).

### P11-D22: Bluегreen cutover from dev `e2c825` stand to production stand

**Decision**: dev `e2c825` stand (existing single-region) remains for development; production stands `prod-eu-central` + `prod-eu-west` are net-new clusters (operator-provisioned per prerequisite). DNS cutover from `api.kacho.local` (internal dev) → `api.kacho.cloud` (public production) is operator-initiated per phase 11 runbook. Smoke verify by external `kacho-yc-shim` CLI against `api.kacho.cloud`.

**Rationale**: Production cluster is greenfield (not in-place upgrade of dev) — clean state, no migration risk; bluегreen via DNS allows instant rollback (revert DNS); smoke CLI ensures Phase 1-10 functionality available externally.

**Alternatives considered**: In-place upgrade of dev cluster (rejected — dev has experimental state, would carry forward; production needs clean state); manual cutover testing (rejected — too risky without dry-run automation).

### P11-D23: Cloudflare WAF rule promotion: simulate 24h → block

**Decision**: Cloudflare WAF rules (OWASP CRS 3.x + custom) deploy in `simulate` mode (logs only, no block); 24h soak; review logs; promote to `block` mode at cutover. Rate-limit rules deploy in `block` mode immediately (low false-positive risk).

**Rationale**: WAF false positives can lock out legitimate users; 24h simulate window allows tuning; rate-limit rules well-bounded enough to deploy directly.

**Alternatives considered**: Block immediately (rejected — false-positive risk); never block (rejected — defeats WAF purpose); A/B test (rejected — complex routing).

### P11-D24: Renovate banned-license: GPLv3 family blocked in backend; allowed in UI

**Decision**: Renovate `packageRules` rejects new dependency in Go modules if license matches `GPL-3.0`, `GPL-3.0-or-later`, `AGPL-3.0`, `AGPL-3.0-or-later`; allowed in UI (`kacho-ui`) since React/MIT ecosystem doesn't typically use GPLv3. LGPL allowed only transitive.

**Rationale**: GPLv3 + AGPL in backend creates copyleft obligations on Kachō codebase; LGPL transitive-only is acceptable (no source-share trigger); MIT/Apache/BSD/MPL-2.0 permissive — safe.

**Alternatives considered**: Block all copyleft (rejected — too broad, blocks LGPL safe-transitive); allow GPLv3 (rejected — legal risk for proprietary SaaS); license-aware not enforced (rejected — incident risk).

### P11-D25: Multi-region Helm chart structure: per-cluster `overrides.yaml`

**Decision**: Single umbrella Helm chart `kacho-platform`; per-cluster overrides via `clusters/{cluster-name}/overrides.yaml` (region label, Postgres role primary/replica, MirrorMaker direction); Argo CD Application references overrides per cluster.

**Rationale**: Single chart = single source of truth; overrides per cluster = no template duplication; Argo CD per-app per-cluster sync model = standard GitOps pattern.

**Alternatives considered**: Separate charts per cluster (rejected — duplication, drift); Kustomize layered overrides (rejected — Argo CD Helm + Kustomize composition fragile); per-env values file with no per-cluster (rejected — multi-region needs per-cluster differentiation).

### P11-D26: HSTS preload submission = operator action (NOT automatable)

**Decision**: HSTS preload submission via `hstspreload.org` web form is **operator manual action**; documented as REQUIRES gate; submission verified by checking `chrome://net-internals/#hsts` lookup for `kacho.cloud` shows STATIC preload entry.

**Rationale**: hstspreload.org has no API; submission is intentionally manual (preload is near-irreversible); cannot automate.

**Alternatives considered**: Skip HSTS preload (rejected — leaves first-visit MITM window); rely on header only (rejected — first visit unprotected).

### P11-D27: Cloudflare Access for admin UIs (Grafana, Hubble, Argo CD)

**Decision**: `grafana.kacho.cloud`, `hubble.kacho.cloud`, `argocd.kacho.cloud` are protected by Cloudflare Access (OIDC challenge against Kratos; group membership `cluster.kacho-root.platform_admin` or `cluster.kacho-root.security_admin` required); independent of in-app authz (defense-in-depth).

**Rationale**: Admin UIs aren't user-facing — Cloudflare Access adds SSO challenge layer at edge; even if admin UI has app-layer authz bypass bug, Access blocks unauthenticated request; defense-in-depth.

**Alternatives considered**: App-layer authz only (rejected — single layer; bypass = full access); IP allowlist (rejected — admins work from many locations); VPN-only (rejected — operational burden, no granular RBAC).

### P11-D28: External resource prerequisites are operator-action gates (NOT TODO)

**Decision**: Operations the platform cannot self-provision are documented as explicit prerequisite gates with `# REQUIRES <action>` markers in acceptance + runbooks; gates MUST be operator-confirmed BEFORE Phase 11 cutover dry-run. They are NOT "TODO" / "follow-up" — they are external dependencies of Phase 11.

**External prerequisites enumerated**:
- **REQUIRES domain registration completed** (`kacho.cloud` registered with registrar)
- **REQUIRES Cloudflare account** (zone added, API token provisioned)
- **REQUIRES multi-region cloud accounts** (e.g., AWS eu-central-1 + eu-west-1, or GCP europe-west3 + europe-west4)
- **REQUIRES HSM provisioning** (AWS CloudHSM or GCP Cloud HSM in prod region; SoftHSM acceptable dev/staging per Phase 10 P10-D4)
- **REQUIRES PagerDuty tenant + service keys** (service per severity P1/P2)
- **REQUIRES Slack workspace + webhook** (channel `#iam-alerts`)
- **REQUIRES SMTP relay** (for email severity P4)
- **REQUIRES container registry** (e.g., GHCR or ECR) with cosign signing enabled
- **REQUIRES Sigstore Fulcio + Rekor availability** (for keyless signing in non-prod CI)
- **REQUIRES Cloudflare API token in K8s Secret** with `Zone:DNS:Edit` scope (for cert-manager DNS-01)
- **REQUIRES HSTS preload submission** at `hstspreload.org` after first prod cert
- **REQUIRES OIDC IdP for Cloudflare Access** (Kratos IdP from Phase 2 — already operational)

**Rationale**: Acceptance docs must distinguish what the engineering team delivers from what operator provisioning provides; treating prereqs as in-scope tests would deadlock acceptance (can't sign off without external accounts being ready); explicit gate semantics keep acceptance honest.

**Alternatives considered**: Treat as "out of scope" (rejected — they're directly required, not deferred); treat as TODO (rejected — TODO implies engineering work; these are operations work); skip mention (rejected — operator surprise on cutover).

### P11-D29: Per-region Postgres failover RTO ≤30s in-region; ≤15min cross-region

**Decision**: In-region failover (Patroni primary kill within region): <30s; cross-region failover (entire region offline): ≤15 min (DNS TTL 60s + Patroni manual promote 30s + connection drain/refill 5-10 min + traffic rebalance 2-3 min). Drill quarterly via `make failover-drill-staging`.

**Rationale**: 30s in-region = within typical request retry window (gRPC default 5 attempts); 15min cross-region matches design doc D-21 RTO; quarterly drill validates without prod risk.

**Alternatives considered**: <60s cross-region (rejected — DNS TTL alone is 60s; physical limit); <5min in-region (rejected — Patroni leader-elect needs etcd quorum + WAL apply); skip drill (rejected — runbooks rot without exercise).

### P11-D30: Tempo trace sampling 100% control-plane / 5% data-plane

**Decision**: Control-plane RPCs (kacho-iam Check/ListObjects, kacho-api-gateway any RPC, kacho-iam Internal*) sampled at 100% (low volume, high signal); data-plane high-volume reconcilers (kacho-vpc Watch, kacho-compute Lifecycle, kacho-loadbalancer health-check) sampled at 5%. Tail-based sampling for errors (always sample failed RPC regardless of base rate).

**Rationale**: 100% control plane = full audit + debug trail; 5% data-plane keeps Tempo storage manageable; tail-sampling catches errors guaranteed.

**Alternatives considered**: 100% everything (rejected — Tempo storage cost prohibitive at scale); 1% everything (rejected — control plane signal loss); head-based only (rejected — misses errors at low base rate).

---

## 4. Architecture diagram (Phase 11 production multi-region topology)

```
                                  ┌──────────────────────────────────────────────────────┐
                                  │   External users / kacho-yc-shim CLI / browsers     │
                                  │   (worldwide)                                        │
                                  └────────────────────────────┬─────────────────────────┘
                                                               │
                                                               ▼
                                  ┌───────────────────────────────────────────────────────┐
                                  │   GeoDNS (Cloudflare; api.kacho.cloud Anycast)       │
                                  │   ─ DNSSEC enabled                                    │
                                  │   ─ RPKI for BGP hijack defense                       │
                                  │   ─ TTL 60s                                           │
                                  └───────────┬───────────────────────────┬───────────────┘
                                              │                           │
                                              │ nearest region            │ nearest region
                                              ▼                           ▼
                ┌─────────────────────────────────────────┐   ┌─────────────────────────────────────────┐
                │   Cloudflare edge eu-central             │   │   Cloudflare edge eu-west                │
                │   ─ TLS 1.3 termination (LE cert)       │   │   ─ TLS 1.3 termination                  │
                │   ─ HTTP/3 (QUIC) toward client          │   │   ─ HTTP/3 toward client                 │
                │   ─ WAF (OWASP CRS 3.x + custom)         │   │   ─ same                                 │
                │   ─ DDoS L3/L4/L7                        │   │   ─ same                                 │
                │   ─ Bot management                       │   │   ─ same                                 │
                │   ─ Rate-limits per endpoint per IP      │   │   ─ same                                 │
                │   ─ Cloudflare Access for /admin/* paths │   │   ─ same                                 │
                └────────────────┬─────────────────────────┘   └────────────────┬─────────────────────────┘
                                 │ HTTP/2 + TLS origin                          │ HTTP/2 + TLS origin
                                 ▼                                              ▼
                ┌─────────────────────────────────────────────┐   ┌─────────────────────────────────────────────┐
                │   K8s cluster prod-eu-central                │   │   K8s cluster prod-eu-west                   │
                │   ──────────────────────────────────────────  │   │   ──────────────────────────────────────────  │
                │   Ingress NGINX (terminate origin TLS)        │   │   Ingress NGINX                              │
                │                                                │   │                                              │
                │   ┌────────────────────────────────────────┐  │   │   ┌────────────────────────────────────────┐ │
                │   │  kacho-api-gateway (3+ HPA-scaled,     │  │   │   │  kacho-api-gateway (3+ HPA-scaled,     │ │
                │   │   anti-affinity per node)              │  │   │   │   anti-affinity)                        │ │
                │   └────┬────────────────────────────────────┘  │   │   └────┬────────────────────────────────────┘ │
                │        │ Cilium eBPF mesh + SPIFFE mTLS         │   │        │ same                                 │ │
                │        ▼                                        │   │        ▼                                      │ │
                │   kacho-iam, kacho-vpc, kacho-compute,           │   │   kacho-iam, kacho-vpc, kacho-compute,        │ │
                │   kacho-loadbalancer (each 3+ replicas;          │   │   kacho-loadbalancer (each 3+ replicas;       │ │
                │     anti-affinity; HPA)                          │   │     anti-affinity; HPA)                       │ │
                │                                                  │   │                                               │ │
                │   ┌────────────────────────────────────────┐    │   │   ┌────────────────────────────────────────┐  │ │
                │   │  Patroni 3-node Postgres clusters      │    │   │   │  Patroni 3-node Postgres clusters      │  │ │
                │   │  (per-service: kacho_iam, kacho_vpc,   │    │   │   │  (sync replicas of eu-central writers; │  │ │
                │   │   kacho_compute, kacho_loadbalancer)   │    │   │   │   plus async DR replicas)              │  │ │
                │   │  PRIMARY in eu-central                  │    │   │   │  STANDBY (sync stream from primary)    │  │ │
                │   └────────────────┬───────────────────────┘    │   │   └────────────────────────────────────────┘  │ │
                │                    │ streaming repl                │   │                                              │ │
                │                    └───────────────────────────────┼───┼───────────────────────────────────┐          │ │
                │                                                    │   │                                   │          │ │
                │   ┌────────────────────────────────────────┐       │   │                                   │          │ │
                │   │  OpenFGA writer-master (single global) │       │   │  OpenFGA reader (read-only)       │          │ │
                │   │  + reader in this region               │       │   │  reads local Postgres replica     │          │ │
                │   └────────────────────────────────────────┘       │   └───────────────────────────────────┘          │ │
                │                                                    │                                                  │ │
                │   ┌────────────────────────────────────────┐       │   ┌────────────────────────────────────────┐    │ │
                │   │  Kafka KRaft (3 brokers)                │═══════════│  Kafka KRaft (3 brokers)                │   │ │
                │   │  audit-events + caep-events topics      │ MM2 │   │  replicated topics + own producers      │   │ │
                │   └────────────────────────────────────────┘  ═════════└────────────────────────────────────────┘    │ │
                │                                                    │                                                  │ │
                │   ┌────────────────────────────────────────┐       │   ┌────────────────────────────────────────┐    │ │
                │   │  ClickHouse 2 shards × 2 replicas        │═════════│  ClickHouse 2 shards × 2 replicas        │   │ │
                │   │  Replicated MergeTree + Keeper           │ async│   │  async fetch from eu-central             │   │ │
                │   └────────────────────────────────────────┘  ═════════└────────────────────────────────────────┘    │ │
                │                                                    │                                                  │ │
                │   SPIRE Server 3 HA (Phase 10) + Cilium (Phase 10) │   SPIRE Server 3 HA + Cilium (own trust domain  │ │
                │   trust domain: kacho.cloud                       │   shared: kacho.cloud — federated bundles)      │ │
                │                                                    │                                                  │ │
                │   ┌────────────────────────────────────────┐       │   ┌────────────────────────────────────────┐    │ │
                │   │  Observability stack:                   │       │   │  Observability stack:                   │    │ │
                │   │   ─ OTel Collector (DS + Deployment)    │       │   │   ─ OTel Collector                      │    │ │
                │   │   ─ Tempo (traces, S3 backend)          │       │   │   ─ Tempo                                │    │ │
                │   │   ─ Mimir (metrics, S3 backend, HA      │       │   │   ─ Mimir (HA receiver dedup)            │    │ │
                │   │      receiver dedup)                    │       │   │                                          │    │ │
                │   │   ─ Loki (logs, S3 backend)             │       │   │   ─ Loki                                 │    │ │
                │   │   ─ Grafana (PRIMARY UI; OIDC SSO)      │       │   │   ─ Grafana (READ-ONLY failover)         │    │ │
                │   │   ─ Alertmanager 3 replicas             │       │   │   ─ Alertmanager 3 replicas              │    │ │
                │   │      ─ PagerDuty integration            │       │   │      ─ PagerDuty (same routing)          │    │ │
                │   │      ─ Slack #iam-alerts                │       │   │      ─ Slack same                        │    │ │
                │   │      ─ Email on-call                    │       │   │                                          │    │ │
                │   └────────────────────────────────────────┘       │   └────────────────────────────────────────┘    │ │
                │                                                    │                                                  │ │
                │   ┌────────────────────────────────────────┐       │   ┌────────────────────────────────────────┐    │ │
                │   │  Argo CD (PRIMARY control plane)        │       │   │  Argo CD (READ-ONLY failover)            │    │ │
                │   │   ─ watches kacho-deploy GitHub repo    │       │   │   ─ same repo                            │    │ │
                │   │   ─ syncs Helm/Kustomize manifests      │       │   │   ─ syncs same manifests                 │    │ │
                │   │   ─ ArgoRollouts: canary 5/25/50/100    │       │   │   ─ ArgoRollouts same                    │    │ │
                │   │      over 30min; auto-rollback on       │       │   │                                          │    │ │
                │   │      SLO breach                          │       │   │                                          │    │ │
                │   └────────────────────────────────────────┘       │   └────────────────────────────────────────┘    │ │
                └─────────────────────────────────────────────────┘   └─────────────────────────────────────────────┘ │
                                  │                                                            │                       │ │
                                  └───────────────┐         ┌─────────────────────────────────┘                       │ │
                                                  ▼         ▼                                                          │ │
                                       ┌─────────────────────────────────────────┐                                     │ │
                                       │  GitHub (kacho-deploy + sibling repos)  │                                     │ │
                                       │  ─ source of truth for manifests        │                                     │ │
                                       │  ─ release CI:                           │                                     │ │
                                       │     ─ build container                    │                                     │ │
                                       │     ─ syft SBOM (SPDX + CycloneDX)       │                                     │ │
                                       │     ─ trivy + grype + gosec scan         │                                     │ │
                                       │     ─ cosign sign (keyless OIDC for     │                                     │ │
                                       │       non-prod; offline key for prod)    │                                     │ │
                                       │     ─ in-toto SLSA L3 provenance         │                                     │ │
                                       │     ─ Renovate weekly + ASAP security    │                                     │ │
                                       └─────────────────────────────────────────┘                                     │ │
                                                                                                                          │ │
                                       ┌─────────────────────────────────────────┐                                     │ │
                                       │  Container Registry (GHCR / ECR)        │                                     │ │
                                       │  ─ signed images + attached SBOM        │                                     │ │
                                       │  ─ SLSA L3 attestation cosign-attached  │                                     │ │
                                       └─────────────────────────────────────────┘                                     │ │
                                                                                                                          │ │
                                       ┌─────────────────────────────────────────┐                                     │ │
                                       │  PagerDuty + Slack + Email (P1-P4)      │                                     │ │
                                       │  ─ on-call rotation                      │                                     │ │
                                       │  ─ tabletop-tested runbooks per alert    │                                     │ │
                                       └─────────────────────────────────────────┘                                     │ │
                                                                                                                          │ │
                                       ┌─────────────────────────────────────────┐                                     │ │
                                       │  S3 multi-region (backup + cold archive)│                                     │ │
                                       │  ─ WAL-G base+WAL backups (PITR)         │                                     │ │
                                       │  ─ ClickHouse cold tier                   │                                     │ │
                                       │  ─ Audit batches (Glacier 7y)            │                                     │ │
                                       │  ─ Mimir/Loki/Tempo long-term storage    │                                     │ │
                                       └─────────────────────────────────────────┘                                     │ │
                                                                                                                          │ │
```

### 4.1 Canary deploy flow (sequence)

```
PR merged to kacho-deploy main branch
   │
   │ (1) Argo CD detects git change (poll/webhook)
   │
   ▼
Argo CD reconciles Application in target env (dev → staging → prod-eu-central → prod-eu-west)
   │
   │ (2) Sync waves apply in order: -10 data-plane → -5 security → -3 obs → 0 app → 5 edge
   │ (3) For app stack: ArgoRollouts CRD detects new image; begins canary
   │
   ▼
Step 1: 5% traffic to canary; 15 min observation
   │
   │ (4) AnalysisTemplate runs: query Mimir for canary error rate vs stable error rate;
   │     latency p95 canary vs stable; SLO burn rate
   │ (5) If analysis fails 2 consecutive checks (1min interval): PAUSE
   │ (6) If pause persists > 5 min OR error rate > 5× stable: AUTO-ROLLBACK
   │      → ArgoRollouts sets canary replicas = 0, stable = 100%
   │      → PagerDuty alert KachoCanaryRolledBack fires
   │      → audit_outbox row inserted (iam.deploy.canary.rolled_back)
   │
   ▼
Step 2: 25% traffic to canary; 5 min observation (same gating)
   │
   ▼
Step 3: 50% traffic; 5 min
   │
   ▼
Step 4: 75% traffic; 3 min
   │
   ▼
Step 5: 100% traffic; 2 min
   │
   │ (7) Promote: canary becomes new stable; old stable scaled down; audit row (iam.deploy.canary.promoted)
   │
   ▼
Deploy complete; Slack #iam-alerts informational message
```

### 4.2 Regional failover flow (sequence)

```
Primary region (eu-central) detected unhealthy (synthetic probe failure > 2 min sustained)
   │
   │ (1) PagerDuty P1 alert KachoRegionalOutage fires
   │
   ▼
On-call SRE acknowledges; consults regional-failover runbook
   │
   │ (2) Manual decision: failover yes/no (some outages recover; partial degradation may not justify failover)
   │ (3) If failover: SRE invokes `make failover-prod` (CLI wrapper around runbook steps)
   │
   ▼
Step 1: Update Cloudflare GeoDNS to route all traffic to eu-west
   │ (DNS TTL 60s; propagation expected ≤90s)
   │
   ▼
Step 2: Patroni promote standby in eu-west to primary (per service)
   │ (each Postgres cluster: ~30s leader election + WAL apply)
   │ (4) OpenFGA writer role moves: kacho-iam connects to new primary
   │ (5) Kafka MirrorMaker direction reversed: now eu-west → eu-central (when central recovers)
   │ (6) ClickHouse: writes route to surviving region; cross-region async fetch resumes when central back
   │
   ▼
Step 3: Connection drain/refill (api-gateway in surviving region scales up to absorb full traffic)
   │ (HPA scales to absorb 2× normal load; ~2-5 min for new replicas ready)
   │
   ▼
Step 4: Smoke verify via synthetic probe + canary kacho-yc-shim CLI commands
   │ (7) Audit row: iam.deploy.regional_failover.completed
   │ (8) Slack #iam-alerts informational + Grafana dashboard updated
   │
   ▼
Failover complete; total elapsed time target ≤15 min from incident detection
```

---

## 5. Декомпозиция работ (Phase 11)

| Repo | Subtask | Plan task | Estimated PR size |
|---|---|---|---|
| kacho-proto | minimal: proto annotations on existing messages (region, canary labels) | 11.1 prep | ~50 LOC proto delta |
| kacho-corelib | `corelib/observability/otel/{tracer,meter,logger}.go` + `corelib/region/region.go` + `corelib/slo/budget.go` | 11.6 prep | ~600 LOC + tests |
| kacho-iam | wire corelib/observability/otel + corelib/region into main.go; add custom metrics (Check QPS, FGA write latency, JWKS rotation age); audit-outbox event-types for deploy events | 11.6 + 11.4 | ~250 LOC delta + tests |
| kacho-vpc | same wiring + custom metrics | 11.6 | ~200 LOC delta + tests |
| kacho-compute | same | 11.6 | ~200 LOC delta + tests |
| kacho-loadbalancer | same | 11.6 | ~200 LOC delta + tests |
| kacho-api-gateway | same + region-aware response header (`x-kacho-region`) + per-principal rate-limit middleware | 11.6 + 11.2 | ~300 LOC delta + tests |
| kacho-deploy | bulk of Phase 11 — see below | 11.2 + 11.3 + 11.4 + 11.5 + 11.6 + 11.7 + 11.8 | ~12,000 LOC YAML + ~1,500 LOC TF + ~2,000 LOC JSON dashboards + ~3,000 LOC runbook markdown |
| kacho-deploy/cloudflare-config | Terraform managed Cloudflare config (DNS, WAF, rate-limit, page rules, bot management) | 11.2 | ~1,500 LOC Terraform |
| kacho-deploy/helm/umbrella/templates | cert-manager + Ingress + Patroni Postgres HA + Kafka MirrorMaker + ClickHouse cross-region + OpenFGA replicas + OTel + Tempo + Mimir + Loki + Grafana + Alertmanager + ArgoCD + ArgoRollouts | 11.2 + 11.3 + 11.4 + 11.6 | ~8,000 LOC YAML |
| kacho-deploy/dashboards | Grafana JSON: iam-overview, iam-authn, iam-authz, iam-audit-pipeline, iam-caep-pipeline, iam-spiffe-mesh, iam-slo-burn-rate, api-gateway, vpc-overview, compute-overview, loadbalancer-overview, cross-region-replication-lag | 11.6 | ~2,000 LOC JSON |
| kacho-deploy/alerts | Alertmanager PrometheusRule CRDs (14+ alert files) | 11.6 + 11.7 | ~1,500 LOC YAML |
| kacho-deploy/docs/runbooks/iam | 15 runbook markdown files; tabletop transcripts subfolder | 11.7 | ~3,000 LOC markdown |
| kacho-deploy/clusters/{env}/overrides.yaml | per-cluster Helm value overrides | 11.3 | ~500 LOC YAML |
| kacho-deploy/argocd-projects + argocd-apps + argocd-rollouts + argocd-analysis-templates | GitOps + canary CRDs | 11.4 | ~2,500 LOC YAML |
| kacho-deploy/renovate.json + .github/renovate.json per sibling | Renovate config | 11.8 | ~300 LOC JSON |
| .github/workflows/release-iam.yml per sibling | SBOM + SLSA + cosign + scan CI workflow (template applied per repo) | 11.5 | ~400 LOC YAML per repo × 6 repos ≈ 2,400 LOC |
| kacho-test | e2e: multi_region_failover, cert_auto_renew, slo_burn_synthetic, supply_chain_unsigned_image, argocd_canary_rollback | 11.9 | ~1,200 LOC Go + tests |
| kacho-ui | admin observability pages | 11.7 | ~600 LOC tsx |
| kacho-workspace | vault: 16+ new files | 11.9 close | ~40KB total |

**Total estimate**: ~30,000 LOC across 11 repos (vast majority YAML/JSON/Terraform/markdown — production-deployment phase is config-heavy, code-light).

---

## 6. Given-When-Then Scenarios

> **Prerequisites convention**: each section begins with `# REQUIRES <action>` markers for operator-action gates per P11-D28. Acceptance scenarios assume gates are CONFIRMED; the markers are exposed so operators see the gate before running tests.

### 6.1 Domain + TLS (api.kacho.cloud + cert-manager + HSTS preload + HTTP/3) (6 scenarios)

> **REQUIRES**: domain registration completed (`kacho.cloud` registered with registrar); Cloudflare account + zone added; Cloudflare API token in K8s Secret with `Zone:DNS:Edit` scope; HSTS preload submission at `hstspreload.org` (after first prod cert successfully issued).

#### Scenario S11.1.1: api.kacho.cloud DNS resolves to Cloudflare anycast

**ID**: S11.1.1

**Given**:
- Domain `kacho.cloud` is registered (operator prerequisite confirmed)
- Cloudflare zone `kacho.cloud` exists with NS records pointing at Cloudflare
- `cloudflare-config/dns.tf` applied: A/AAAA proxied record for `api.kacho.cloud` orange-cloud enabled
- DNSSEC enabled at registrar with DS records published

**When** external client performs `dig api.kacho.cloud A +short` and `dig api.kacho.cloud AAAA +short`

**Then**
- IPv4 response returns Cloudflare anycast IPs (in Cloudflare-published ranges per `https://www.cloudflare.com/ips-v4`)
- IPv6 response returns Cloudflare anycast IPs (`https://www.cloudflare.com/ips-v6`)
- DNSSEC validation passes (`dig +dnssec api.kacho.cloud` returns `ad` flag)
- TTL ≤ 60s
- Same query from different geographic locations returns IPs in nearest Cloudflare region (verify via `mtr` from 2+ external probe points)

#### Scenario S11.1.2: Let's Encrypt prod certificate issued via DNS-01 challenge

**ID**: S11.1.2

**Given**:
- `kacho-deploy/helm/umbrella/templates/cert-manager-clusterissuer-letsencrypt-prod.yaml` applied:
  - `ClusterIssuer/letsencrypt-prod` with `acme.server: https://acme-v02.api.letsencrypt.org/directory`
  - `solvers.dns01.cloudflare.apiTokenSecretRef: cert-manager-cloudflare-token / api-token`
- `kacho-deploy/helm/umbrella/templates/api-kacho-cloud-certificate.yaml` applied:
  - `Certificate/api-kacho-cloud-tls` with `dnsNames: [api.kacho.cloud, spire.kacho.cloud, grafana.kacho.cloud, hubble.kacho.cloud, argocd.kacho.cloud]`
- Secret `cert-manager-cloudflare-token` populated with Cloudflare API token (Zone:DNS:Edit scope)

**When** cert-manager controller reconciles `Certificate/api-kacho-cloud-tls`

**Then**
- cert-manager creates `Order` + `Challenge` resources
- Cloudflare DNS records `_acme-challenge.<subdomain>.kacho.cloud TXT` are created via API
- Let's Encrypt validates challenge; issues cert
- Within 10 min: secret `api-kacho-cloud-tls-secret` populated with PEM-encoded cert + key
- `Certificate.status.conditions[type=Ready].status == "True"`
- Cert SAN includes all 5 dnsNames
- Cert issuer = Let's Encrypt Authority X3 / R3 / R10 (validate via `openssl x509 -in <crt> -text -noout | grep Issuer`)
- Cert validity > 89 days (LE issues 90d certs)
- Prometheus metric `certmanager_certificate_expiration_timestamp_seconds{name="api-kacho-cloud-tls"}` populated

#### Scenario S11.1.3: cert-manager auto-renews cert 30 days before expiry

**ID**: S11.1.3

**Given**:
- Cert `api-kacho-cloud-tls` issued at time T0 with validity 90 days (expiry T0+90d)
- cert-manager renewal policy: renew when `notAfter - now() < 30d`
- Test mode: simulate clock skew via `make cert-renewal-dry-run` (advance time markers; no actual clock change)

**When** time advances to T0+60d (30d before expiry)

**Then**
- cert-manager detects renewal-due via `notAfter - now() < 30d`
- Initiates new Order + DNS-01 challenge
- Within 10 min: new cert issued; secret rotated atomically
- Prometheus metric `certmanager_certificate_renewals_total{name="api-kacho-cloud-tls"}` incremented
- Ingress NGINX picks up new cert (watches secret) within 60s
- External `openssl s_client -connect api.kacho.cloud:443` shows new cert serial number
- Old cert remains valid (90d window); no downtime
- Audit row in `kacho_iam.audit_outbox`: type `iam.deploy.cert_renewed`, target `api-kacho-cloud-tls`

#### Scenario S11.1.4: HSTS header served on every response; preload submitted

**ID**: S11.1.4

**Given**:
- Cloudflare page rule + origin Ingress configured to serve `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload`
- HSTS preload submission at `hstspreload.org` confirmed (operator prerequisite: domain shows STATIC preload entry in Chrome `chrome://net-internals/#hsts`)

**When** external client requests `https://api.kacho.cloud/health/live`

**Then**
- Response status 200
- Response header `Strict-Transport-Security: max-age=63072000; includeSubDomains; preload` present
- max-age = 63072000 (2 years exactly)
- Browser hardcoded preload list contains `kacho.cloud` (verify via `chrome://net-internals/#hsts` query type domain → static_sts_observed: true)

#### Scenario S11.1.5: TLS 1.3 only; cipher suite check

**ID**: S11.1.5

**Given**:
- Cloudflare zone SSL/TLS settings: Minimum TLS 1.3
- Cloudflare cipher suite policy: TLS 1.3 cipher suites only (TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256, TLS_AES_128_GCM_SHA256)
- Origin cert is ECDSA P-256

**When** external client probes via `nmap --script ssl-enum-ciphers -p 443 api.kacho.cloud`

**Then**
- TLS 1.2 connection REJECTED (`ssl_handshake_failure` or `protocol_version` alert)
- TLS 1.3 connection SUCCEEDS
- Only ciphers TLS_AES_256_GCM_SHA384 + TLS_CHACHA20_POLY1305_SHA256 + TLS_AES_128_GCM_SHA256 reported
- Cert signature algorithm = ECDSA P-256 (`openssl x509 -in <crt> -text | grep "Signature Algorithm"`)
- nmap rating = `A+` per Mozilla SSL config

#### Scenario S11.1.6: HTTP/3 (QUIC) enabled at Cloudflare edge; HTTP/2 fallback at origin

**ID**: S11.1.6

**Given**:
- Cloudflare zone Network setting: HTTP/3 (with QUIC) enabled
- Origin Ingress NGINX configured for HTTP/2 + TLS

**When** external client with HTTP/3 support (curl 8.x with `--http3-only`) requests `https://api.kacho.cloud/health/live`

**Then**
- Connection negotiated as HTTP/3 (QUIC over UDP/443)
- Response status 200
- Response header `Alt-Svc: h3=":443"; ma=86400` present (advertising HTTP/3 to clients)
- Client without HTTP/3 falls back to HTTP/2 successfully (`curl --http2-prior-knowledge`)
- Origin-side Ingress NGINX access log shows HTTP/2 (`$server_protocol == HTTP/2.0`), not HTTP/3

### 6.2 Cloudflare WAF + DDoS + bot management (5 scenarios)

> **REQUIRES**: Cloudflare account on Pro plan or higher (WAF managed rule sets); Cloudflare Bot Management subscription enabled.

#### Scenario S11.2.1: WAF OWASP CRS 3.x managed rules block known attack patterns

**ID**: S11.2.1

**Given**:
- `cloudflare-config/waf-rules.tf` applied: OWASP CRS 3.x managed rule set ON, sensitivity = medium
- WAF promoted to `block` mode after 24h `simulate` soak (operator-confirmed gate)

**When** synthetic attack: `curl 'https://api.kacho.cloud/v1/users?id=1%27%20OR%20%271%27%3D%271'` (SQLi-pattern in query string)

**Then**
- Response status 403 (Cloudflare WAF block)
- Response header `cf-ray` present (Cloudflare ray ID for log lookup)
- Cloudflare Logpush exports event to S3 → Phase 9 audit pipeline picks it up
- Grafana panel `iam-overview / WAF blocks per hour` reflects increment within 5 min
- Origin server never sees the request (Ingress NGINX access log empty for this ray ID)

#### Scenario S11.2.2: DDoS L3/L4 mitigation absorbs volumetric flood

**ID**: S11.2.2 (operator-validated; documented but not part of automated CI — requires synthetic flood from outside platform)

**Given**:
- Cloudflare DDoS L3/L4 protection enabled (default Cloudflare plan)
- Synthetic flood generator outside Cloudflare's ranges (e.g., hping3 from offnet test rig) — operator-only

**When** flood sends 50k UDP SYN/sec to `api.kacho.cloud:443` for 60s

**Then**
- Cloudflare absorbs flood; no traffic reaches origin (Ingress NGINX rate stays at normal baseline)
- Synthetic blackbox probe from non-flood source continues to return 200 (legitimate users unaffected)
- Cloudflare dashboard shows flood traffic absorbed (operator-verified)
- No PagerDuty alert fires for this (Cloudflare absorbs entirely)
- Documented in `kacho-deploy/docs/runbooks/iam/ddos-incident.md` runbook (tabletop-tested)

#### Scenario S11.2.3: Bot management rate-limits aggressive scrapers; allows legitimate bots

**ID**: S11.2.3

**Given**:
- `cloudflare-config/bot-management.tf` applied: Bot Score header injection; rate-limit on Bot Score < 30 (aggressive bots)
- Known-good bots (Google, Bing, etc.) on allowlist via Verified Bot rule

**When**:
- Request A: User-Agent = `Googlebot/2.1` (verified Google IP)
- Request B: User-Agent = `python-requests/2.31.0` (uncategorized; bot score < 30 by behavior)
- Request C: synthetic 100 requests/10s from same IP with UA `MysteryBot/1.0`

**Then**
- Request A: Allowed; response 200
- Request B: First 10 allowed; subsequent rate-limited 429
- Request C: First few allowed, then aggressively rate-limited (Bot Score drops <10 with sustained 10rps)
- Bot Score header `cf-bot-score` populated on each request reaching origin (for audit)

#### Scenario S11.2.4: Rate-limit per endpoint per IP enforced at edge

**ID**: S11.2.4

**Given**:
- `cloudflare-config/rate-limit.tf` applied:
  - `/v1/auth/*` endpoints: 100 req / 60s per IP
  - `/v1/iam/v1/breakglass:activate` endpoint: 10 req / 60s per IP
  - General `/v1/*` endpoints: 1000 req / 60s per IP

**When** synthetic client from single IP attempts 200 requests to `https://api.kacho.cloud/v1/auth/login` within 30s

**Then**
- First 100 requests: variously 200/400/401 based on actual auth result
- Requests 101+: 429 Too Many Requests from Cloudflare (NOT origin)
- Response header `cf-ray` + `retry-after: <seconds>` present
- Sustained for 60s; counter resets after window
- Origin NGINX access log shows only first 100 requests (not 101-200)
- Cloudflare Logpush exports rate-limit-block events

#### Scenario S11.2.5: WAF custom rule for path-traversal blocks `..` patterns

**ID**: S11.2.5

**Given**:
- `cloudflare-config/waf-rules.tf` includes custom rule:
  ```hcl
  rule {
    action      = "block"
    expression  = "(http.request.uri.path contains \"../\") or (http.request.uri.path contains \"..%2F\") or (http.request.uri.path contains \"..\\\\\")"
    description = "Block path traversal patterns"
  }
  ```

**When** synthetic attack: `curl 'https://api.kacho.cloud/v1/../../../etc/passwd'`

**Then**
- Response status 403 (Cloudflare WAF block)
- Cloudflare ray ID logged with custom rule reference
- Origin never receives the request

### 6.3 Multi-region active-active deploy (5 scenarios)

> **REQUIRES**: multi-region cloud accounts provisioned (e.g., AWS eu-central-1 + eu-west-1 with VPC peering OR GCP europe-west3 + europe-west4 with VPC interconnect); minimum 6 nodes per region (Patroni 3 + observability 3 + etc.); cross-region private network <30ms p99 latency.

#### Scenario S11.3.1: Both regions serve traffic via GeoDNS

**ID**: S11.3.1

**Given**:
- `prod-eu-central` cluster deployed (Argo CD synced; all stacks green)
- `prod-eu-west` cluster deployed (Argo CD synced; all stacks green)
- Cloudflare GeoDNS configured: `api.kacho.cloud` routes to nearest region via Anycast (Cloudflare's built-in)
- Synthetic blackbox probes at multiple geographic locations (eu-central-1 EC2 instance, eu-west-1 EC2 instance, us-east-1 EC2 instance)

**When** each probe issues `curl -H 'cache-control: no-cache' https://api.kacho.cloud/health/live` 100 times

**Then**
- eu-central probe: response header `x-kacho-region: eu-central` >= 95% of responses
- eu-west probe: response header `x-kacho-region: eu-west` >= 95% of responses
- us-east probe: header value depends on Cloudflare anycast routing; consistent within ~30min windows
- Each probe sees response status 200 for ≥99.9% of requests
- Grafana panel `iam-overview / requests by region` shows traffic split

#### Scenario S11.3.2: Forced regional failover from eu-central → eu-west; RTO ≤15 min

**ID**: S11.3.2 (staging-only forced; prod via real outage drill)

**Given**:
- Staging cluster simulating prod topology (2 regions: staging-eu-central + staging-eu-west)
- `make failover-drill-staging` ready
- Baseline: api.kacho.staging.cloud responding 99.95% from eu-central
- Synthetic blackbox probe every 10s during drill

**When** operator executes `make failover-drill-staging` which:
1. Stops all kacho-* pods + Postgres primary in staging-eu-central (force-kill)
2. Updates Cloudflare GeoDNS to route 100% traffic to staging-eu-west
3. Triggers Patroni promote standby → primary in staging-eu-west

**Then**
- T+0: synthetic probe error rate spikes; PagerDuty P1 alert `KachoRegionalOutage` fires
- T+90s: GeoDNS propagated; traffic shifts to staging-eu-west
- T+2min: Patroni leader-elected in staging-eu-west; Postgres accepting writes
- T+5min: api-gateway in staging-eu-west scaled up (HPA) to absorb full traffic
- T+10min: synthetic probe success rate >99% sustained
- T+15min: failover declared complete (operator confirmation in PagerDuty incident)
- Total RTO measured ≤15 min from incident detection
- Audit row in `audit_outbox`: type `iam.deploy.regional_failover.completed`; metadata includes drill-id
- Grafana dashboard `cross-region-replication-lag` shows replication paused (one direction); no data loss confirmed via row count

#### Scenario S11.3.3: Postgres sync replication lag measured ≤1 min p99 (RPO)

**ID**: S11.3.3

**Given**:
- Patroni cluster kacho_iam-prod-eu-central with primary + 2 sync standbys (1 in eu-central; 1 in eu-west)
- Sustained write load: 1000 transactions/sec from synthetic load generator
- Prometheus scraping pg_stat_replication metrics every 15s

**When** measured over 30-min sustained load window

**Then**
- `pg_replication_lag_seconds{role="sync_standby"}` p50 < 1s
- `pg_replication_lag_seconds{role="sync_standby"}` p99 < 60s
- No commit confirmed at primary without sync standby ACK (verified via Postgres synchronous_commit setting `remote_write`)
- Alert `KachoPostgresReplicationLag` does NOT fire (threshold > 60s)
- Grafana panel `cross-region-replication-lag / Postgres` shows lag distribution

#### Scenario S11.3.4: Failover preserves active user session (JWKS replicated)

**ID**: S11.3.4

**Given**:
- User logged in; JWT issued with `kid=kacho-prod-2026-Q2-1` (Hydra signing key)
- JWT replicated in eu-west (Hydra Postgres sync replication includes JWKS table)
- User has active session via DPoP-bound access token

**When**:
1. User makes RPC `kacho.iam.v1.ProjectService.Get` (authenticated; succeeds in eu-central)
2. Forced regional failover from eu-central → eu-west (per S11.3.2)
3. User retries same RPC after failover

**Then**
- Step 3 RPC succeeds (status 200)
- JWT signature validates against replicated JWKS in eu-west
- DPoP `cnf` claim validated (key bound)
- Response header `x-kacho-region: eu-west`
- User experiences brief retry (one failed attempt + auto-retry) but no re-login required
- J36 user journey verified end-to-end

#### Scenario S11.3.5: Cross-region write routing for single-master OpenFGA

**ID**: S11.3.5

**Given**:
- OpenFGA writer single-master in eu-central; readers in both regions
- Pre-failover; eu-central healthy
- User in eu-west region makes `kacho.iam.v1.AccessBindingService.Write` (writes a FGA tuple)

**When** RPC processed by kacho-iam pod in eu-west

**Then**
- kacho-iam in eu-west detects writer-master location via service discovery (`fga-writer.kacho-system.svc.cluster.local`)
- gRPC call to OpenFGA writer in eu-central (cross-region hop, ~10-30ms added latency)
- Write succeeds; tuple persisted in eu-central Postgres (OpenFGA writer DB)
- Subsequent read from same user in eu-west region sees the tuple (consistency token returned by write echoes for next read)
- Replication lag eu-central → eu-west readers measured ≤5s p99
- If writer-master in eu-central unavailable: gRPC call fails fast; PagerDuty alert `KachoOpenFGAWriterUnreachable` fires; failover runbook triggered

### 6.4 Postgres HA via Patroni (5 scenarios)

> **REQUIRES**: etcd 3-node cluster operational in each region (DCS for Patroni); WAL-G S3 bucket configured per region.

#### Scenario S11.4.1: Patroni leader election on cold-start

**ID**: S11.4.1

**Given**:
- 3-node Patroni cluster kacho_iam-prod-eu-central; no leader currently
- etcd cluster healthy with 3 voting members
- All 3 Patroni nodes start simultaneously

**When** Patroni controllers begin leader election

**Then**
- Within 30s: exactly one node becomes leader (claims etcd lease)
- Other 2 nodes register as sync standbys
- Postgres primary on leader accepts connections on port 5432
- `pg_is_in_recovery()` returns false on leader, true on standbys
- Patroni HTTP API `GET /` on leader returns `state: "running", role: "master"`
- Prometheus metric `patroni_master == 1` for leader, `0` for standbys
- `patroni_sync_standby{member="<eu-central-2>"} == 1` (the sync standby)

#### Scenario S11.4.2: In-region failover < 30s on primary-pod-kill

**ID**: S11.4.2

**Given**:
- Patroni cluster healthy: leader + 2 sync standbys
- Sustained write load 100 transactions/sec

**When** operator kills primary pod: `kubectl delete pod patroni-kacho-iam-prod-eu-central-0 --force --grace-period=0`

**Then**
- Within 10s: etcd lease times out; Patroni triggers leader election
- Within 20s: one of the sync standbys promoted; accepts writes (`pg_is_in_recovery() = false`)
- Within 30s: kacho-iam pods reconnect (gRPC client retry + Postgres connection pool refresh); writes resume
- Sustained writes show brief 20-30s gap in `iam_db_writes_total` metric
- Audit row: `iam.deploy.regional_failover.started` (in-region; metadata `scope: in-region`)
- After 1 min: replacement pod restarts as new sync standby (previous primary catches up via pg_rewind)

#### Scenario S11.4.3: Cross-region async DR replica catches up

**ID**: S11.4.3

**Given**:
- kacho_iam-prod-eu-central Patroni cluster (3 nodes, 1 leader + 2 sync standbys)
- Async DR replica in eu-west streaming from leader
- Network latency eu-central ↔ eu-west: ~20ms p50

**When** measured over 1h sustained 1000 transactions/sec load

**Then**
- Async DR replica lag (`pg_replication_lag_seconds{role="async_dr"}`) p50 < 5s
- Async DR replica lag p99 < 30s
- DR replica can be promoted manually via `patronictl failover --candidate <dr-replica>` (runbook scenario; tested in staging quarterly)
- After promote: writes accepted in eu-west; previous eu-central nodes reconfigured as standbys to new eu-west primary
- Documented in `regional-failover.md` runbook

#### Scenario S11.4.4: WAL-G base backup + WAL archive + PITR

**ID**: S11.4.4

**Given**:
- WAL-G configured on primary; daily base backup at 02:00 UTC + continuous WAL archive
- S3 bucket `kacho-postgres-backups-eu-central` (encrypted with KMS-managed key)
- Retention: 30d hot in S3 Standard; 7y cold in Glacier (audit-relevant only)

**When**:
1. Inject test data row at T0 (`INSERT INTO kacho_iam.users (id, ...) VALUES (...)`)
2. Continue writes for 1h to T0+1h
3. Operator initiates PITR to T0+30min (via runbook)

**Then**
- WAL-G restores base backup nearest before T0+30min
- Applies WAL files up to LSN at T0+30min
- Restored cluster has row inserted at T0 (was before T0+30min)
- Rows inserted between T0+30min and T0+1h NOT present (rolled back)
- Restore completes in < 30 min for 100GB cluster (operator-verified per backup size class)

#### Scenario S11.4.5: No data loss on planned failover

**ID**: S11.4.5

**Given**:
- Patroni cluster with leader + sync standby
- Test write transaction: `INSERT INTO test_table VALUES (..., $timestamp)` committed
- `synchronous_commit = remote_write` (commit requires sync standby ACK)

**When** planned failover via `patronictl switchover --leader <current> --candidate <sync-standby>` (clean shutdown)

**Then**
- Switchover completes in < 30s
- New leader is the sync standby
- Test write transaction VISIBLE on new leader (no data loss)
- Replication continues; old leader rejoins as sync standby (after pg_rewind)
- Audit row: `iam.deploy.regional_failover.completed`; metadata `scope: in-region, type: planned`

### 6.5 Kafka cross-region MirrorMaker 2 (4 scenarios)

> **REQUIRES**: Kafka KRaft 3 brokers per region (no ZooKeeper); MirrorMaker 2 deployment ready; both regions' Kafka clusters healthy.

#### Scenario S11.5.1: audit-events topic replicated eu-central → eu-west

**ID**: S11.5.1

**Given**:
- MirrorMaker 2 deployed in eu-west; source = eu-central Kafka; target = eu-west Kafka
- Topics replicated: `audit-events`, `caep-events`, `__consumer_offsets`
- Phase 9 audit-producer in eu-central writes to `audit-events` topic at ~100 msg/sec

**When** observed over 30 min

**Then**
- Topic `audit-events` exists in eu-west Kafka cluster with same partitions as eu-central
- Messages flowing eu-central → eu-west via MM2
- Replication lag `mm2_replication_lag_ms` p99 < 5000 (5s)
- Message offsets in eu-west are TRANSLATED: same logical row but different physical offset (MM2 maps via `mm2-offset-syncs`)
- Phase 9 ClickHouse loader in eu-west reads replicated topic; rows match those in eu-central within 30s

#### Scenario S11.5.2: Consumer offset preservation on regional failover

**ID**: S11.5.2

**Given**:
- Phase 8 CAEP drainer consuming `caep-events` in eu-central; current consumer group offset 12345 for partition 0
- MM2 mirrored consumer offsets to `__consumer_offsets` in eu-west
- Force failover: eu-central Kafka offline; CAEP drainer in eu-west takes over

**When** CAEP drainer in eu-west resumes consumption

**Then**
- Drainer reads from `caep-events` in eu-west Kafka
- Translated offset 12345 (eu-central) → equivalent offset in eu-west (e.g., 12350) via MM2 offset-syncs
- No duplicate webhook deliveries to subscribers (each event delivered exactly once across failover)
- No skipped events (offsets contiguous post-failover)
- Audit log shows continuous CAEP delivery without gap

#### Scenario S11.5.3: Backpressure on MM2 lag > 5s sustained 5min triggers alert

**ID**: S11.5.3

**Given**:
- MM2 alert rule `KachoKafkaMirrorMakerLag` fires when `mm2_replication_lag_ms > 5000` sustained 5 min
- Synthetic network slowdown injected between regions (e.g., tc netem 200ms delay)

**When** lag exceeds 5000ms

**Then**
- Within 5 min sustained: Alertmanager fires `KachoKafkaMirrorMakerLag` (P2)
- PagerDuty alert created; Slack `#iam-alerts` notification
- Runbook `audit-pipeline-incident.md` linked in alert annotations
- Grafana panel `cross-region-replication-lag / Kafka MM2` shows red status

#### Scenario S11.5.4: Topic schema unchanged across replication

**ID**: S11.5.4

**Given**:
- Phase 9 `audit-events` topic uses CADF + custom envelope schema (registered in Schema Registry if used)
- MM2 replicates with no schema transformation

**When** consumer in eu-west reads replicated message

**Then**
- Message schema identical to eu-central producer's output
- Avro/JSON schema field-by-field match (verified by schema-registry compatibility check OR field-level diff)
- No fields dropped, renamed, or reordered
- Message timestamp preserved (eu-central producer ts)
- Message headers preserved (including trace-id for correlation)

### 6.6 ClickHouse cross-region replication (4 scenarios)

> **REQUIRES**: ClickHouse 4 nodes per region (2 shards × 2 replicas); Keeper (or external ZK) quorum cross-region (3+ nodes); cross-region async network reliable.

#### Scenario S11.6.1: ReplicatedMergeTree replication within region

**ID**: S11.6.1

**Given**:
- ClickHouse cluster `audit_cluster_eu_central` with 2 shards × 2 replicas
- `ReplicatedMergeTree` table `audit_events_local` on each replica
- Keeper-backed ZNode paths for replication metadata

**When** producer inserts 10k rows into `audit_events_dist` (Distributed table)

**Then**
- Distributed table routes inserts to appropriate shard (consistent hashing)
- Within shard: leader replica accepts INSERT; replicates to follower via async fetch
- After 30s: `system.replicas` shows `absolute_delay < 5s` on follower for both shards
- SELECT from any replica in cluster returns full count (10k rows)
- Total inserts split roughly 50/50 across shards (verified via shard-key distribution)

#### Scenario S11.6.2: Cross-region replication lag ≤30s p99

**ID**: S11.6.2

**Given**:
- `audit_events_local` table in eu-central replicates async to `audit_events_local` in eu-west (separate clusters; cross-region async fetch via Keeper coordinator)
- Sustained write load 100 rows/sec from eu-central producer

**When** measured over 30 min

**Then**
- `chr_replica_max_absolute_delay` (cross-region) p99 ≤ 30s
- SELECT from eu-west replica returns rows inserted in eu-central within 30s
- Alert `KachoClickHouseReplicationLag` does NOT fire (threshold > 30s sustained 5min)
- Grafana panel `cross-region-replication-lag / ClickHouse` shows lag distribution

#### Scenario S11.6.3: Queries served from any region; no split-brain

**ID**: S11.6.3

**Given**:
- ClickHouse cluster healthy in both regions; cross-region replication active
- Query `SELECT count(*) FROM audit_events_dist WHERE event_type = 'iam.user.login_success' AND date = today()`

**When** query executed from kacho-iam in eu-central AND from kacho-iam in eu-west

**Then**
- Both queries return same count (within replication lag tolerance ≤30s)
- Both queries return < 200ms (ClickHouse query latency)
- Distributed query plan visible in `system.query_log`; shards from both regions queried
- No "split-brain": Keeper quorum (3+ nodes spanning regions) ensures single coordinator per shard

#### Scenario S11.6.4: Recovery from temporary network partition

**ID**: S11.6.4

**Given**:
- ClickHouse cross-region replication active
- Synthetic network partition: eu-central ↔ eu-west blocked for 5 min (tc netem drop 100%)

**When** partition heals after 5 min

**Then**
- During partition: each region continues local writes; cross-region replication queued in Keeper
- After heal: Keeper coordinates async fetch; replication catches up within ~5 min (depends on backlog)
- `chr_replica_max_absolute_delay` peaks at ~5 min during catch-up; returns to normal
- No data loss; both regions converge to same row count
- Audit log: no `KachoClickHouseSplitBrain` alert fired (Keeper quorum prevented split)

### 6.7 OpenFGA read replicas + writer single-master (4 scenarios)

#### Scenario S11.7.1: Read replica serves Check from local region

**ID**: S11.7.1

**Given**:
- OpenFGA writer single-master in eu-central
- Read replicas in both regions (eu-central + eu-west) reading from local Postgres replica
- User in eu-west requests Check on existing tuple

**When** kacho-iam in eu-west invokes OpenFGA Check

**Then**
- gRPC call routes to local OpenFGA reader in eu-west (`fga-reader.kacho-system.svc.cluster.local`)
- Check latency < 20ms p95 (local Postgres read)
- No cross-region hop for read path
- Response returns `allowed: true/false` consistent with global tuple state

#### Scenario S11.7.2: Write routes to writer single-master

**ID**: S11.7.2

**Given**:
- Tuple-write request from kacho-iam in eu-west: `Write(tuple = "user:alice#viewer@project:proj1")`

**When** kacho-iam invokes OpenFGA Write

**Then**
- gRPC call routes to writer-master (`fga-writer.kacho-system.svc.cluster.local` resolves to eu-central pods)
- Cross-region hop adds ~10-30ms latency vs in-region write
- Write succeeds; tuple persisted in eu-central Postgres (writer DB)
- Response returns `consistency_token` (FGA's read-after-write marker)
- Subsequent read from eu-west reader with consistency_token waits for replication then returns updated state

#### Scenario S11.7.3: Consistency token cross-region propagation

**ID**: S11.7.3

**Given**:
- User in eu-west writes tuple T at time T0; receives consistency_token CT0
- User immediately reads with the same consistency_token from eu-west reader

**When** reader receives Check with `consistency_token=CT0`

**Then**
- Reader checks local DB replication position vs CT0
- If local position >= CT0: serve from local read (low latency)
- If local position < CT0: wait up to 5s for replication; then serve (slight latency hit)
- Read returns updated state including tuple T (verified by Check returning `allowed:true` for `user:alice#viewer@project:proj1`)
- Replication lag eu-central writer → eu-west reader ≤ 5s p99

#### Scenario S11.7.4: Writer-master failover writes write-unavailability window ≤60s

**ID**: S11.7.4

**Given**:
- OpenFGA writer-master in eu-central healthy
- Postgres failover: eu-central primary → eu-west sync standby (per S11.4)

**When** failover executes

**Then**
- During Postgres failover (30s): OpenFGA writer returns errors for ~30s
- kacho-iam Write RPC returns `Unavailable` with retry guidance (gRPC `RETRY_INFO` detail)
- After failover: writer-master role moves to eu-west; future writes succeed there
- Total write-unavailability window ≤ 60s (Postgres failover + DNS update for `fga-writer` service)
- Audit log: brief gap in `iam.authz.tuple_writes` metric
- Reads remain available throughout (local readers in both regions)

### 6.8 Argo CD GitOps + canary 5/25/50/100 + auto-rollback (6 scenarios)

> **REQUIRES**: Argo CD installed in each cluster; ArgoRollouts CRDs installed; GitHub OAuth app for Argo CD UI Cloudflare Access.

#### Scenario S11.8.1: Per-env overlay correct for prod-eu-central

**ID**: S11.8.1

**Given**:
- `argocd-apps/prod-eu-central/kacho-iam.yaml` defines Application:
  ```yaml
  source:
    repoURL: https://github.com/PRO-Robotech/kacho-deploy
    targetRevision: main
    path: helm/umbrella
    helm:
      valueFiles:
        - values.yaml
        - clusters/prod-eu-central/overrides.yaml
  destination:
    server: <prod-eu-central-cluster>
    namespace: kacho-system
  syncPolicy:
    automated: { prune: true, selfHeal: true }
  ```

**When** Argo CD reconciles Application

**Then**
- Helm template renders with both values.yaml + prod-eu-central/overrides.yaml merged
- Overrides set: `region: eu-central`, `postgres.role: primary`, `openfga.role: writer-master`, `mirrormaker.direction: eu-central-to-eu-west`
- Cluster applies manifests; Argo CD status `Synced` + `Healthy`
- Image tags pinned to specific SHA (`kacho-iam:sha-abc123def`); Renovate-managed updates create PRs to bump

#### Scenario S11.8.2: Canary 5→25→50→100 over 30 min with passing analysis

**ID**: S11.8.2

**Given**:
- `argocd-rollouts/kacho-iam-rollout.yaml` defines Rollout with steps:
  ```yaml
  steps:
    - setWeight: 5
    - pause: { duration: 15m }
    - analysis: { templates: [{ templateName: slo-burn-rate-5m }] }
    - setWeight: 25
    - pause: { duration: 5m }
    - analysis: ...
    - setWeight: 50
    - ... etc
  ```
- New image `kacho-iam:sha-xyz789` rolled out
- Existing stable serves baseline traffic

**When** Rollout begins; canary deployed

**Then**
- T+0: canary takes 5% of traffic; stable 95%
- T+15min: analysis `slo-burn-rate-5m` queries Mimir for canary vs stable burn rate; passes (canary burn rate < 1.5× stable)
- T+15min: weight bumps to 25%; another analysis
- T+20min: 50%; T+25min: 75%; T+27min: 100%
- T+30min: promote complete; stable replicas scaled to old replica count; canary becomes new stable
- Audit row: `iam.deploy.canary.promoted` with from-sha + to-sha + total-duration
- Slack `#iam-alerts` posts "✅ kacho-iam promoted sha-xyz789 → 100% in prod-eu-central"

#### Scenario S11.8.3: SLO breach during canary triggers auto-rollback

**ID**: S11.8.3

**Given**:
- Rollout in progress at 25% weight; canary image has bug (synthetic: 50% of requests return 500)
- AnalysisTemplate `slo-burn-rate-5m` queries `(rate(http_requests_total{status=~"5..",canary="true"}[5m]) / rate(http_requests_total{canary="true"}[5m])) / (rate(http_requests_total{status=~"5..",canary="false"}[5m]) / rate(http_requests_total{canary="false"}[5m]))`

**When** analysis evaluates after 25% step pause

**Then**
- Analysis returns ratio ≥ 5 (canary error rate 5× stable)
- ArgoRollouts marks Rollout `Degraded`; PAUSE
- Within 5 min pause: sustained failure detected
- ArgoRollouts triggers auto-rollback: canary replicas → 0; stable replicas → 100%
- PagerDuty alert `KachoCanaryRolledBack` fires (P2)
- Audit row: `iam.deploy.canary.rolled_back` with metadata `reason: slo-burn-rate, from-sha, to-sha, weight-at-rollback: 25%`
- Slack `#iam-alerts` posts "❌ kacho-iam rolled back from sha-xyz789 at 25% weight (SLO burn rate 5.2× baseline)"

#### Scenario S11.8.4: Sync wave dependency order respected

**ID**: S11.8.4

**Given**:
- Fresh cluster install; all Argo CD Applications applied simultaneously
- Sync waves:
  - -10: data-plane-stack (Postgres HA, Kafka, ClickHouse, OpenFGA, etcd)
  - -5: security-stack (SPIRE, Cilium, cert-manager)
  - -3: observability-stack (OTel, Tempo, Mimir, Loki, Grafana, Alertmanager)
  - 0: application-stack (kacho-iam, kacho-vpc, kacho-compute, kacho-loadbalancer, kacho-api-gateway)
  - 5: edge-stack (Ingress controllers, Cloudflare worker)

**When** Argo CD applies all Applications

**Then**
- Wave -10 syncs first; waits until `Healthy` before -5 begins
- Wave -5 syncs; waits until `Healthy` (SPIRE Server registered + Cilium DaemonSet ready)
- Wave -3 syncs; observability infrastructure online before apps depend on it
- Wave 0 syncs; kacho-* apps start with SPIFFE mTLS + OTel exporting
- Wave 5 syncs; Ingress controllers configured for app endpoints
- Bootstrap total time: ~15-20 min for fresh cluster
- No app pod CrashLoops due to missing dependencies (Postgres ready before kacho-iam starts; SPIRE Server ready before SVID requests)

#### Scenario S11.8.5: Argo CD self-heal corrects manual drift

**ID**: S11.8.5

**Given**:
- Argo CD Application with `syncPolicy.automated.selfHeal: true`
- Operator manually edits kacho-iam Deployment replica count (`kubectl scale deployment kacho-iam --replicas=10`)

**When** Argo CD detects drift on next reconcile (~3 min)

**Then**
- Argo CD restores replica count to manifest-declared value (e.g., 3)
- Argo CD UI shows "Auto-sync corrected" event
- Audit log: `argocd.application.self-healed` event (Argo CD events; not kacho audit)
- Slack `#iam-alerts` posts "ℹ️ Argo CD self-healed kacho-iam in prod-eu-central (replicas 10 → 3)"

#### Scenario S11.8.6: Argo CD RBAC restricts prod sync to platform_admin only

**ID**: S11.8.6

**Given**:
- `argocd-projects/kacho-iam-platform.yaml` defines AppProject with `roles`:
  - `prod-sync-admin` role can sync apps in `prod-*` clusters
  - Mapped to group `cluster.kacho-root.platform_admin` (via OIDC groups claim from Kratos)
- User Alice in `developer` group (NOT platform_admin)

**When** Alice attempts via Argo CD UI: "Sync kacho-iam-prod-eu-central"

**Then**
- Argo CD UI denies operation: "User does not have permission for action sync on project kacho-iam-platform"
- API call `POST /api/v1/applications/kacho-iam-prod-eu-central/sync` returns 403
- Cloudflare Access has already gated `argocd.kacho.cloud` for OIDC challenge (defense-in-depth — Alice may not even reach Argo CD UI if not in any cluster-admin group)
- Audit log: Argo CD events show denied operation

### 6.9 SBOM + SLSA L3 + cosign + vulnerability scan (5 scenarios)

> **REQUIRES**: GitHub Actions OIDC for keyless cosign; offline kacho-platform-team cosign key for prod (HSM-backed); container registry accepts cosign signatures + SBOM artifacts.

#### Scenario S11.9.1: Each release container has SBOM attached

**ID**: S11.9.1

**Given**:
- `.github/workflows/release-iam.yml` template applied to `kacho-iam` repo
- New release triggered (tag `v0.11.0` pushed)

**When** CI runs

**Then**
- syft generates SBOM in SPDX-JSON + CycloneDX-JSON formats
- `cosign attach sbom --sbom <spdx-json> ghcr.io/PRO-Robotech/kacho-iam:v0.11.0` succeeds
- `cosign download sbom ghcr.io/PRO-Robotech/kacho-iam:v0.11.0` returns SBOM
- SBOM contains: all Go module dependencies with versions + licenses; base image (e.g., `cgr.dev/chainguard/static:latest`) + its components
- Verification: `make sbom-verify IMAGE=ghcr.io/PRO-Robotech/kacho-iam:v0.11.0` returns OK

#### Scenario S11.9.2: SLSA L3 provenance attached + verifiable

**ID**: S11.9.2

**Given**:
- `.github/workflows/release-iam.yml` includes `actions/attest-build-provenance@v2` step

**When** CI runs

**Then**
- in-toto Statement (SLSA Provenance v1.0 predicate) generated
- Attestation attached to image as cosign signature (predicate type `https://slsa.dev/provenance/v1`)
- `cosign verify-attestation --type slsaprovenance --certificate-identity-regexp 'https://github.com/PRO-Robotech/kacho-iam' --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' ghcr.io/PRO-Robotech/kacho-iam:v0.11.0` succeeds
- Verified predicate.builder.id == `https://github.com/actions/runner`
- Verified predicate.invocation.configSource.uri == `git+https://github.com/PRO-Robotech/kacho-iam@refs/tags/v0.11.0`
- Verified subject.digest matches image manifest digest

#### Scenario S11.9.3: cosign signature verifies; SPIRE attestor accepts

**ID**: S11.9.3

**Given**:
- prod build signed with offline kacho-platform-team cosign key (operator-held)
- Public key published in `kacho-deploy/cosign-trusted-signers/kacho-platform-team.pub`
- SPIRE Agent cosign attestor configured with this public key as trusted signer

**When**:
1. Verify externally: `cosign verify --key kacho-platform-team.pub ghcr.io/PRO-Robotech/kacho-iam:v0.11.0`
2. Deploy image to cluster; SPIRE Agent attests workload

**Then**
- Step 1: cosign verify returns OK + signature payload
- Step 2: SPIRE Agent's cosign attestor downloads image, verifies signature against trusted key, includes `cosign:<fingerprint>` selector in attestation
- SPIRE Server matches selector to `spiffe_registrations` entry → issues SVID
- Pod's mTLS handshake succeeds

#### Scenario S11.9.4: Vulnerability scan gate blocks HIGH/CRITICAL CVE in new dep

**ID**: S11.9.4

**Given**:
- `.github/workflows/release-iam.yml` runs trivy + grype + gosec scans
- PR adds dependency `vulnerable-pkg@v1.0.0` (synthetic; has known CVE-2026-9999 rated HIGH)

**When** PR CI runs

**Then**
- trivy scan reports CVE-2026-9999 in `vulnerable-pkg@v1.0.0` rated HIGH
- grype scan corroborates (cross-check between scanners)
- CI step "Block on HIGH/CRITICAL in new deps" fails:
  - Compares PR base SBOM vs PR head SBOM
  - Detects new dep `vulnerable-pkg@v1.0.0` with HIGH CVE
  - Exits non-zero; PR check fails
- PR cannot merge until either: (a) dep removed (b) upgraded to non-vulnerable version (c) explicit waiver in `.security-waiver.yaml` with KAC-ticket + expiry date + reviewer sign-off

#### Scenario S11.9.5: gosec catches hardcoded credentials in PR diff

**ID**: S11.9.5

**Given**:
- `.github/workflows/release-iam.yml` runs gosec
- PR adds Go code: `password := "hardcoded_secret_123"` (synthetic; gosec rule G101)

**When** PR CI runs

**Then**
- gosec reports G101 in PR diff
- CI step "Block on gosec HIGH/CRITICAL" fails
- PR check shows annotation pointing to violation line
- PR cannot merge until credential moved to Secret OR explicit `// nosec G101 -- reason ...` annotation + reviewer sign-off

### 6.10 Renovate auto-PR (3 scenarios)

#### Scenario S11.10.1: Weekly batch PR for Go deps grouped by topic

**ID**: S11.10.1

**Given**:
- `kacho-iam/.github/renovate.json` with:
  ```json
  {
    "schedule": ["after 9am on monday"],
    "groupName": {
      "kacho-corelib siblings": "Kachō corelib + proto",
      "pgx ecosystem": ["pgx*", "tern", "sqlc-gen-*"],
      "observability": ["go.opentelemetry.io/*", "github.com/prometheus/*"]
    }
  }
  ```
- Multiple deps have new versions available

**When** Monday 09:00 UTC; Renovate runs

**Then**
- Single PR per group; e.g., "chore(deps): update pgx ecosystem (pgx v5.5.0 → v5.6.0, sqlc-gen-go v1.25.0 → v1.26.0)"
- Each grouped PR contains multiple deps in single commit
- Tests run on PR; auto-merge minor + patch if green
- Major version bumps require manual review

#### Scenario S11.10.2: Security CVE triggers immediate PR; auto-merged if green

**ID**: S11.10.2

**Given**:
- Renovate config `vulnerabilityAlerts.enabled: true`
- New CVE-2026-XXXX disclosed for `existing-dep@v1.2.3` → patched in `v1.2.4`

**When** Renovate detects vulnerability advisory

**Then**
- Immediate PR (not waiting for weekly schedule): "fix(security): upgrade existing-dep v1.2.3 → v1.2.4 (CVE-2026-XXXX)"
- PR labeled `security` + `vulnerability:HIGH`
- CI runs; if green: auto-merge enabled (since security update)
- If CI fails: PR remains open; security@ team notified via Slack

#### Scenario S11.10.3: Banned-license PR rejected

**ID**: S11.10.3

**Given**:
- Renovate config: `packageRules` reject if license matches `GPL-3.0|AGPL-3.0`
- PR proposes adding `gplv3-pkg@v2.0.0` (synthetic; GPL-3.0 license)

**When** Renovate evaluates

**Then**
- Renovate does NOT create PR for this dep
- Log entry in Renovate UI: "Skipped gplv3-pkg@v2.0.0 due to package rule: license GPL-3.0 disallowed"
- If a developer manually adds it: CI gate "license-check" step fails, PR cannot merge

### 6.11 OpenTelemetry traces + metrics + logs end-to-end (6 scenarios)

> **REQUIRES**: OTel Collector deployed (DaemonSet + Deployment); Tempo/Mimir/Loki/Grafana operational; S3 backend buckets provisioned per region.

#### Scenario S11.11.1: Trace propagated end-to-end from api-gateway → backend service

**ID**: S11.11.1

**Given**:
- OTel SDK wired in `corelib/observability/otel` for all kacho-* services
- W3C Trace Context propagation: `traceparent` header carried via gRPC metadata
- Tempo deployed; OTel Collector exports traces to Tempo

**When** external client makes request `GET /v1/iam/v1/projects/proj-abc`:
1. Cloudflare → kacho-api-gateway (Public mux gRPC)
2. kacho-api-gateway → kacho-iam (ProjectService.Get RPC)
3. kacho-iam → OpenFGA Check (gRPC)
4. kacho-iam → Postgres query

**Then**
- Single trace ID visible in Tempo (`tempo-cli query <traceid>`)
- Trace contains 4+ spans: api-gateway HTTP handler, api-gateway gRPC client, kacho-iam gRPC handler, OpenFGA Check, Postgres query
- Parent-child relationships correct (api-gateway parent of kacho-iam, etc.)
- Each span has `kacho.cloud/region: eu-central`, `kacho.cloud/cluster: prod-eu-central`, `service.name: kacho-<svc>` attributes
- Trace ID visible in OTLP logs (slog field `trace_id`) — log → trace correlation in Grafana
- Trace ID visible in HTTP response header `traceresponse` (W3C)

#### Scenario S11.11.2: Metrics scraped via Mimir; standard Go + custom IAM metrics present

**ID**: S11.11.2

**Given**:
- OTel Collector exports metrics to Mimir via remote-write
- Mimir 30d retention configured

**When** Grafana queries Mimir for metric `iam_authz_check_duration_seconds_bucket{service="kacho-iam",region="eu-central"}`

**Then**
- Metric exists; histogram with buckets 0.001 / 0.005 / 0.01 / 0.025 / 0.05 / 0.1 / 0.5 / 1.0
- p95 calculated via `histogram_quantile(0.95, ...)` ≤ 20ms (SLO target)
- Other custom metrics present: `iam_jwks_key_age_seconds`, `iam_audit_outbox_lag_seconds`, `iam_caep_delivery_duration_seconds`
- Standard Go runtime metrics: `go_goroutines`, `go_memstats_alloc_bytes`, `process_cpu_seconds_total`
- gRPC metrics: `grpc_server_handled_total{grpc_code="OK|...",grpc_method="..."}`

#### Scenario S11.11.3: Structured logs in Loki with PII scrubbed

**ID**: S11.11.3

**Given**:
- slog logger with OTel handler exports to Loki via OTel Collector
- PII scrubbing processor: emails → `sha256:<hash>`; secrets/tokens → `<redacted>`

**When** kacho-iam logs:
```go
slog.Info("user logged in", "user_email", "alice@example.com", "session_id", "sess-abc", "access_token", "secret-token-123")
```

**Then**
- Log in Loki visible via Grafana Logs panel
- Field `user_email` = `sha256:b5e2cf6b...` (32-char hex hash)
- Field `access_token` = `<redacted>`
- Field `session_id` = `sess-abc` (not scrubbed; non-PII)
- Log line contains `trace_id` for correlation
- Log query `{service="kacho-iam"} |= "user logged in"` returns logs across all replicas

#### Scenario S11.11.4: Grafana dashboards live and load correctly

**ID**: S11.11.4

**Given**:
- `kacho-deploy/dashboards/*.json` mounted via ConfigMap in Grafana namespace
- Grafana provisioning loads dashboards on startup

**When** operator opens Grafana UI at `grafana.kacho.cloud` (after Cloudflare Access auth)

**Then**
- Dashboards listed in left nav: iam-overview, iam-authn, iam-authz, iam-audit-pipeline, iam-caep-pipeline, iam-spiffe-mesh, iam-slo-burn-rate, api-gateway, vpc-overview, compute-overview, loadbalancer-overview, cross-region-replication-lag
- Each dashboard opens; panels render with live data from Mimir/Tempo/Loki
- `iam-slo-burn-rate` dashboard shows: API availability (target 99.95%), Check p95 (≤20ms), ListObjects p95 (≤100ms), CAEP delivery p99 (≤10s), Audit ingest lag p99 (≤60s), DR RTO drill last-run timestamp + result
- `cross-region-replication-lag` shows: Postgres sync lag, Kafka MM2 lag, ClickHouse async fetch lag — all green if within thresholds

#### Scenario S11.11.5: Tail-sampling: error traces always sampled regardless of base rate

**ID**: S11.11.5

**Given**:
- OTel Collector tail_sampling processor configured: 100% control-plane / 5% data-plane base; ALWAYS sample on error (status code != OK)

**When**:
- 100 data-plane RPCs (kacho-vpc Watch) — 95 succeed, 5 return UNAVAILABLE error

**Then**
- Of 95 successful traces: ~5% sampled (≈ 5 traces in Tempo)
- All 5 error traces: 100% sampled (all 5 in Tempo with `status.code=2` error indication)
- Tempo query `{ status=error service.name=kacho-vpc }` returns at least 5 traces

#### Scenario S11.11.6: PII scrubbing also applied to span attributes

**ID**: S11.11.6

**Given**:
- OTel Collector `attributes` processor at top of pipeline: `actions: [hash:email-fields, redact:secret-fields]`

**When** kacho-iam emits span with attributes `user.email="alice@example.com"`, `request.auth_token="xyz"`

**Then**
- Span in Tempo shows `user.email = sha256:b5e2cf...`
- Span shows `request.auth_token = <redacted>`
- Original values NOT present in Tempo or in OTLP raw export
- Same processor applies to log fields (S11.11.3) ensuring consistency

### 6.12 Alerting (Alertmanager + PagerDuty + Slack + email) (6 scenarios)

> **REQUIRES**: PagerDuty tenant + service keys provisioned; Slack workspace + webhook URL; SMTP relay accessible from cluster.

#### Scenario S11.12.1: Alertmanager fires on SLO availability burn rate > 14.4× (1h window)

**ID**: S11.12.1

**Given**:
- PrometheusRule `iam-availability-burn-1h.yaml`:
  ```yaml
  - alert: KachoAPIAvailabilityBurn1h
    expr: |
      (1 - (sum(rate(probe_success{job="blackbox-api-kacho-cloud"}[1h]))
            / sum(rate(probe_total{job="blackbox-api-kacho-cloud"}[1h])))) * 30 * 24 * 60 / 60 * 24 > 14.4
    for: 5m
    labels: { severity: P1, team: iam-platform }
    annotations:
      runbook_url: https://github.com/PRO-Robotech/kacho-deploy/blob/main/docs/runbooks/iam/slo-budget-burn.md
  ```
- Synthetic outage: 50% of blackbox probes failing for last 1h

**When** Mimir ruler evaluates rule

**Then**
- Burn rate calculated > 14.4× (would exhaust 30d budget in 2.5 days)
- After 5min `for` clause: Alertmanager receives firing alert
- Alertmanager routes by severity P1 → PagerDuty
- PagerDuty incident created with title `KachoAPIAvailabilityBurn1h` + runbook_url annotation
- Slack `#iam-alerts` posts notification (P1 also goes to Slack per routing)
- Email sent to on-call alias

#### Scenario S11.12.2: PagerDuty integration for P1 incidents creates incident

**ID**: S11.12.2

**Given**:
- Alertmanager `pagerduty_configs` with service_key from secret `alertmanager-pagerduty-key`
- Test alert manually injected via `amtool alert add KachoTestP1 severity=P1`

**When** Alertmanager processes

**Then**
- HTTP POST to PagerDuty Events API v2 within 10s
- PagerDuty incident created (verifiable in PagerDuty UI)
- Incident has alert details: alert name, runbook URL, severity, region label
- On-call user paged per rotation
- Incident auto-resolves when alert clears (`resolved` event sent)

#### Scenario S11.12.3: Slack #iam-alerts wired for P1-P3

**ID**: S11.12.3

**Given**:
- Alertmanager `slack_configs` with webhook URL from secret `alertmanager-slack-webhook`
- Channel `#iam-alerts` configured

**When** P2 alert fires (e.g., `KachoAuthzCheckLatencyHigh`)

**Then**
- Slack post in `#iam-alerts` within 10s
- Message contains: alert name, severity, region, current value, threshold, runbook URL (clickable), Grafana dashboard link
- Message uses Slack block formatting (color-coded by severity: P1=red, P2=orange, P3=yellow)
- Resolution notification when alert clears (gray message "resolved")

#### Scenario S11.12.4: Email receiver for P4 (informational)

**ID**: S11.12.4

**Given**:
- Alertmanager `email_configs` to `iam-on-call@kacho.cloud` for severity=P4
- SMTP relay accessible

**When** P4 alert fires (e.g., `KachoQuarterlyAccessReviewReminder`)

**Then**
- Email sent to `iam-on-call@kacho.cloud` within 60s
- Email body contains alert details + runbook + dashboard link
- No PagerDuty / Slack notification (P4 is email-only)

#### Scenario S11.12.5: Runbook URL annotation present in every alert

**ID**: S11.12.5

**Given**:
- All PrometheusRule files in `alerts/*.yaml`
- CI check `make alerts-runbook-check` enforces every alert rule has `annotations.runbook_url`

**When** CI runs

**Then**
- Script iterates all alert rules; checks `annotations.runbook_url` non-empty + URL points to existing file in `docs/runbooks/iam/`
- Any rule missing runbook → CI fail
- Any rule pointing to non-existent runbook file → CI fail
- Currently 14+ alerts; 14+ runbook files in `docs/runbooks/iam/`

#### Scenario S11.12.6: Alert routing groups by service + region; reduces noise

**ID**: S11.12.6

**Given**:
- Alertmanager routing tree:
  ```yaml
  route:
    group_by: ['alertname', 'service', 'region']
    group_wait: 30s
    group_interval: 5m
    repeat_interval: 4h
    routes:
      - matchers: [severity="P1"]
        receiver: pagerduty-p1
      - matchers: [severity="P2"]
        receiver: pagerduty-p2
      - matchers: [severity="P3"]
        receiver: slack-iam-alerts
      - matchers: [severity="P4"]
        receiver: email-on-call
  ```

**When** 10 alerts fire simultaneously for `KachoAuthzCheckLatencyHigh` across 10 different pods in eu-central

**Then**
- Alertmanager groups them by `alertname + service + region`
- Single PagerDuty incident created (not 10)
- Single Slack message with "10 alerts" summary
- After `repeat_interval` 4h: re-notification if still firing

### 6.13 Runbooks tabletop tested (4 scenarios)

> **REQUIRES**: SRE team trained on runbooks; quarterly tabletop calendar scheduled; tabletop transcripts committed to git.

#### Scenario S11.13.1: Break-glass tabletop exercise transcript exists + passes

**ID**: S11.13.1

**Given**:
- `docs/runbooks/iam/break-glass.md` exists with Problem → Diagnosis → Mitigation → Escalation → Post-mortem template
- Quarterly tabletop scheduled

**When** SRE team conducts tabletop:
- Scenario: cluster.kacho-root admin role lost (last admin offboarded; can't grant new admin)
- 2-person manual approve via emergency break-glass procedure

**Then**
- Tabletop transcript committed at `docs/runbooks/iam/tabletop-transcripts/break-glass-2026Q3.md`
- Transcript covers: timing each step, what worked, what didn't, runbook gaps identified
- Runbook updated based on findings (if any gaps); committed as separate PR
- Audit row: `iam.deploy.runbook_tabletop_executed` with runbook + outcome

#### Scenario S11.13.2: Regional failover tabletop validates RTO ≤15min process

**ID**: S11.13.2

**Given**:
- `docs/runbooks/iam/regional-failover.md` exists
- Tabletop on staging cluster

**When** SRE executes `make failover-drill-staging`

**Then**
- All steps in runbook executed successfully
- RTO measured ≤15 min from `failover initiated` to `failover complete` markers
- RPO measured ≤1 min (Postgres sync replication snapshot)
- Transcript committed
- Quarterly cadence enforced

#### Scenario S11.13.3: GDPR erasure tabletop covers full pipeline

**ID**: S11.13.3

**Given**:
- `docs/runbooks/iam/gdpr-erasure.md` exists (Phase 7 GDPR pipeline)
- Synthetic user `gdpr-test-user-2026Q3@kacho.cloud` with data in Postgres + ClickHouse + S3 archive + caep_outbox

**When** SRE executes erasure procedure

**Then**
- Postgres rows tombstoned (cryptographic erasure via column-level encryption key destruction OR row delete with audit row)
- ClickHouse rows in `audit_events` marked for tombstone (next merge erases)
- S3 archive: data-at-rest encryption key for user's slice destroyed (cryptographic erasure)
- CAEP push event sent to subscribers notifying erasure
- Verification: subsequent queries for user-id return no PII
- Transcript committed

#### Scenario S11.13.4: Cert renewal failed tabletop tests recovery

**ID**: S11.13.4

**Given**:
- `docs/runbooks/iam/cert-renewal-failed.md` exists
- Synthetic: Cloudflare API token revoked → cert renewal will fail
- Cert 35d to expiry (within 30d auto-renew window but failing)

**When** cert-manager fails renewal 3 times; alert `KachoCertRenewalFailed` fires

**Then**
- SRE follows runbook:
  1. Diagnose: check cert-manager logs; identify Cloudflare API token issue
  2. Mitigate: rotate Cloudflare API token (create new with same scope; update Secret)
  3. Trigger renewal: `kubectl cert-manager renew certificate api-kacho-cloud-tls`
- New cert issued within 10 min
- Alert resolves
- Transcript committed; runbook updated if token rotation procedure was unclear

### 6.14 SLO 99.95% measured (4 scenarios)

#### Scenario S11.14.1: Availability metric computed from blackbox probe

**ID**: S11.14.1

**Given**:
- Blackbox-exporter deployed in 3+ external probe locations (Cloudflare Workers OR external EC2 instances) probing `https://api.kacho.cloud/health/live` every 30s
- Metric `probe_success{job="blackbox-api-kacho-cloud"}` (0/1)
- Recording rule: `availability:1h = sum(rate(probe_success[1h])) / sum(rate(probe_total[1h]))`

**When** Grafana queries over 30d window

**Then**
- `availability:30d` ≥ 0.9995 (target 99.95%)
- Grafana panel displays current availability + trend
- Burn rate panel shows budget consumption

#### Scenario S11.14.2: Error budget visualization shows 30d consumption

**ID**: S11.14.2

**Given**:
- 30d rolling SLO budget = 0.05% of total minutes (≈21.6 min/30d)
- Currently consumed: 5 min (synthetic downtime tracked)

**When** dashboard `iam-slo-burn-rate` opens

**Then**
- Panel "Error budget remaining": shows 16.6 min remaining (≈77% remaining)
- Panel "Burn rate (1h)": shows current rate; green if < 1×, yellow 1-6×, red > 14.4×
- Panel "Time to budget exhaustion at current rate": shows projection
- Historical incidents annotated (links to runbooks)

#### Scenario S11.14.3: SLO dashboards link to incident postmortems

**ID**: S11.14.3

**Given**:
- Incident 2026-09-15: 12-min outage (PagerDuty incident P-12345)
- Postmortem committed at `docs/runbooks/iam/postmortems/2026-09-15-p-12345.md`

**When** SLO dashboard "Budget consumption events" panel opens

**Then**
- Event "2026-09-15 outage P-12345 (12min)" displayed
- Click link → opens postmortem markdown in GitHub
- Postmortem follows template: Timeline, Root cause, Mitigation, Action items
- Action items tracked as KAC-tickets

#### Scenario S11.14.4: Synthetic blackbox probe deployed external location (not in cluster)

**ID**: S11.14.4

**Given**:
- Blackbox probe runs from at least one location NOT inside `prod-eu-central` or `prod-eu-west` clusters (otherwise probe down = cluster down = no probe at all = false-positive 100% availability)
- Options: Cloudflare Worker, third-party uptime monitor (Pingdom/Uptimerobot), external small EC2 instance in different cloud/region

**When** synthetic outage of both prod clusters

**Then**
- External probe detects failure; metric `probe_success = 0`
- Alert fires within 5 min
- This works even if internal cluster monitoring (Prometheus inside clusters) is down

### 6.15 Bluegreen cutover from dev e2c825 stand to production (3 scenarios)

> **REQUIRES**: production cluster provisioned + Argo CD synced + all Phase 1-10 verified passing in prod cluster (per S11.8.4 cold-start scenario).

#### Scenario S11.15.1: DNS cutover from api.kacho.local → api.kacho.cloud

**ID**: S11.15.1

**Given**:
- Existing dev `e2c825` stand serves `api.kacho.local` (internal DNS only)
- Production stand `prod-eu-central` + `prod-eu-west` ready, serving `api.kacho.cloud` (external Cloudflare DNS)
- `kacho-yc-shim` CLI default endpoint config: `api.kacho.local` (pre-Phase 11) → `api.kacho.cloud` (Phase 11)

**When** operator initiates cutover per `docs/runbooks/iam/regional-failover.md` (initial cutover variant):
1. Confirm production stand healthy (all SLO dashboards green; sustained for ≥48h)
2. Update kacho-yc-shim default config to `api.kacho.cloud`
3. Announce internally
4. Cloudflare orange-cloud already enabled for `api.kacho.cloud` (set during S11.1.1)
5. Internal `api.kacho.local` listener kept up for cluster-internal port-forward / admin debugging

**Then**
- External clients (browsers via `kacho-ui` at `app.kacho.cloud`, CLI via `kacho-yc-shim`) connect to `api.kacho.cloud`
- TLS handshake terminates at Cloudflare; backend HTTP/2 to origin
- Synthetic blackbox probe sustains > 99.9% success rate during cutover
- No rollback needed (cutover is additive: dev stand unaffected; production stand serves real users; internal listener still available)
- Audit row: `iam.deploy.initial_cutover_completed`

#### Scenario S11.15.2: Smoke verify via kacho-yc-shim CLI exercises Phase 1-10 happy paths

**ID**: S11.15.2

**Given**:
- Production cutover complete
- `kacho-yc-shim` CLI configured with `api.kacho.cloud` endpoint + OIDC config

**When** smoke test executes:
1. `kacho-yc-shim auth login` (Kratos WebAuthn passkey OR password)
2. `kacho-yc-shim iam projects get proj-test` (Phase 1 + 2 + 3: AuthN + AuthZ + ProjectService)
3. `kacho-yc-shim vpc networks list --project proj-test` (Phase 4 list filtering)
4. `kacho-yc-shim compute instances create --image ubuntu-22 --zone eu-central-1a --project proj-test` (Phase 4)
5. `kacho-yc-shim iam access-bindings create --principal user:alice --role editor --resource project:proj-test` (Phase 3 FGA write)
6. Wait 5 min; check Phase 9 audit pipeline returns event via `kacho-yc-shim iam audit query --event-type iam.access_binding.created`

**Then**
- All 6 steps return success
- Each step completes within expected latency
- Audit pipeline visible in ClickHouse (Phase 9) within 60s
- CAEP event delivered to test webhook (Phase 8) within 10s
- Smoke transcript committed at `docs/runbooks/iam/smoke-transcripts/initial-cutover-YYYY-MM-DD.md`

#### Scenario S11.15.3: Rollback path documented + tested

**ID**: S11.15.3

**Given**:
- Production stand experiencing issue post-cutover
- Rollback decision threshold defined in runbook: P1 incident sustained > 30 min without mitigation

**When** SRE invokes rollback per `docs/runbooks/iam/regional-failover.md` (rollback variant):
1. Update Cloudflare DNS: temporarily revert `api.kacho.cloud` to point to LEGACY backend (if legacy still available) OR enable Cloudflare "I'm Under Attack" mode while debugging
2. If absolute necessity: redirect users to maintenance page via Cloudflare worker
3. Active investigation; rollforward when fixed

**Then**
- Documented in runbook as last-resort option
- Rollback time SLO: 5 min for DNS-only rollback (revert Cloudflare config); 30 min for Argo CD revert to prior release (use `argo rollouts undo`)
- Tabletop-tested at least once per quarter
- Post-rollback postmortem mandatory; KAC-ticket tracked

---

## 7. Definition of Done (Phase 11)

### 7.1 Code / PR DoD

- [ ] `kacho-proto` PR merged: minimal proto annotation deltas; `buf lint` + `buf breaking` green
- [ ] `kacho-corelib` PR merged: `corelib/observability/otel/*` + `corelib/region/*` + `corelib/slo/budget.go` with unit-tests + 80%+ coverage
- [ ] `kacho-{iam,vpc,compute,loadbalancer,api-gateway}` PRs merged: OTel + region wiring in `cmd/<svc>/main.go`; custom metrics defined; audit-outbox event-types for deploy events; tests in PR per запрет #11
- [ ] `kacho-api-gateway` PR: region-aware response header; per-principal rate-limit middleware; tests
- [ ] `kacho-deploy` PR(s) merged — Phase 11 bulk; can be multiple PRs split by sub-stack:
  - [ ] Cloudflare Terraform PR — DNS, WAF, rate-limit, bot management, page rules; `terraform plan` clean; applied to staging zone first
  - [ ] cert-manager + Ingress PR — ClusterIssuers + Certificate + Ingress manifests
  - [ ] Patroni Postgres HA PR — per-service StatefulSet + ConfigMap + Service + PDB + backup CronJob
  - [ ] Kafka MirrorMaker 2 PR — MM2 Deployment + topic configs
  - [ ] ClickHouse cross-region PR — cluster config + Replicated MergeTree + Distributed table
  - [ ] OpenFGA replicas PR — writer + reader Deployments + migration job
  - [ ] OTel + LGTM stack PR — Collector + Tempo + Mimir + Loki + Grafana
  - [ ] Alertmanager + PagerDuty/Slack PR — Alertmanager + secrets + routing
  - [ ] ArgoCD + ArgoRollouts PR — AppProject + Applications + Rollouts + AnalysisTemplates
  - [ ] Renovate config PR — root `renovate.json` + per-sibling configs
  - [ ] Release CI workflow PR — `.github/workflows/release-iam.yml` applied per sibling (6 repos)
  - [ ] Helm template validation green (`helm template ... | kubeval`); ArgoCD diff dry-run clean
- [ ] `kacho-deploy/dashboards/*.json` committed (12+ dashboards); Grafana load test passes (`make grafana-load-test`)
- [ ] `kacho-deploy/alerts/*.yaml` committed (14+ alert files); CI check `make alerts-runbook-check` enforces runbook URL per alert
- [ ] `kacho-deploy/docs/runbooks/iam/*.md` committed (15 runbooks); each runbook follows Problem→Diagnosis→Mitigation→Escalation→Post-mortem template
- [ ] `kacho-test` PR merged: e2e tests for multi_region_failover, cert_auto_renew, slo_burn_synthetic, supply_chain_unsigned_image, argocd_canary_rollback; CI green
- [ ] `kacho-ui` PR merged: admin observability pages (SLO embed, runbook index, region status); accessible only to platform_admin/security_admin groups
- [ ] Each PR contains tests (per запрет #11); newman cases added where applicable; integration tests where DB/system involvement

### 7.2 Acceptance Scenario DoD

- [ ] All 60+ scenarios (sections §6.1-§6.15) executed; automated where possible
- [ ] `kacho-test/tests/e2e/multi_region_failover.go` covers S11.3.2, S11.3.4, S11.3.5, S11.4.2, S11.4.5, S11.5.2, S11.7.4
- [ ] `kacho-test/tests/e2e/cert_auto_renew.go` covers S11.1.2, S11.1.3
- [ ] `kacho-test/tests/e2e/slo_burn_synthetic.go` covers S11.12.1, S11.14.1, S11.14.2
- [ ] `kacho-test/tests/e2e/supply_chain_unsigned_image.go` covers S11.9.3 (deploy unsigned image; expect no SVID → no mesh)
- [ ] `kacho-test/tests/e2e/argocd_canary_rollback.go` covers S11.8.2, S11.8.3
- [ ] Manual tabletop scenarios documented and exercise transcript committed: S11.13.1, S11.13.2, S11.13.3, S11.13.4
- [ ] DDoS L3/L4 (S11.2.2) operator-validated separately (not in CI) and documented

### 7.3 Security DoD

- [ ] Cloudflare WAF in `block` mode after 24h `simulate` soak; OWASP CRS 3.x + custom rules deployed
- [ ] HSTS preload submission confirmed (operator verifies `chrome://net-internals/#hsts` shows STATIC entry for `kacho.cloud`)
- [ ] TLS 1.3 only enforced; cipher suite policy applied; ECDSA P-256 cert verified
- [ ] HTTP/3 enabled at Cloudflare edge; HTTP/2 fallback at origin verified
- [ ] cert-manager auto-renew works; 30d-before-expiry threshold tested
- [ ] Rate-limits per endpoint per IP verified via synthetic test
- [ ] Cloudflare Access guards admin UIs (Grafana/Hubble/Argo CD); OIDC challenge against Kratos enforced
- [ ] All container images signed (cosign keyless for non-prod; offline key for prod); SBOM attached; SLSA L3 provenance verifiable
- [ ] Trivy + Grype + gosec gate in CI; HIGH/CRITICAL CVE in new deps blocks merge
- [ ] Renovate banned-license check rejects GPLv3+ in backend
- [ ] OWASP ZAP baseline scan run against `api.kacho.cloud` post-cutover; results triaged; HIGH/CRITICAL fixed before sign-off (low/info acceptable with KAC-ticket)

### 7.4 Observability DoD

- [ ] OTel Collector deployed (DaemonSet + Deployment); end-to-end trace propagation verified S11.11.1
- [ ] Tempo/Mimir/Loki/Grafana operational; dashboards load with live data S11.11.4
- [ ] PII scrubbing applied in OTel pipeline (logs + spans); verified S11.11.3, S11.11.6
- [ ] All 12+ Grafana dashboards committed and live
- [ ] All 14+ Alertmanager alerts have `runbook_url` annotation pointing to existing runbook
- [ ] PagerDuty integration verified (test alert delivered); P1/P2 routing operational
- [ ] Slack `#iam-alerts` integration verified (test message posted)
- [ ] Email receiver for P4 verified (test sent)
- [ ] Synthetic blackbox probe from external location (NOT in any kacho cluster) probing every 30s
- [ ] SLO targets measured and currently within target (99.95% availability, ≤20ms Check p95, ≤100ms ListObjects p95, ≤10s CAEP p99, ≤60s audit ingest p99, ≤1min RPO, ≤15min RTO drill-validated)

### 7.5 Multi-region DoD

- [ ] Both regions (`prod-eu-central` + `prod-eu-west`) deployed; Argo CD synced; healthy
- [ ] GeoDNS routes traffic to nearest region (S11.3.1)
- [ ] Patroni HA per service; in-region failover ≤30s tested S11.4.2
- [ ] Postgres cross-region sync replica lag p99 ≤1 min S11.3.3
- [ ] Async DR replica catches up cross-region S11.4.3
- [ ] WAL-G backups operational; PITR tested S11.4.4
- [ ] Kafka MirrorMaker 2 replicates audit-events + caep-events; lag p99 ≤5s S11.5.1, S11.5.3
- [ ] ClickHouse cross-region replication lag p99 ≤30s S11.6.2
- [ ] No split-brain on network partition recovery S11.6.4
- [ ] OpenFGA writer single-master; readers per region; consistency token cross-region S11.7.1-S11.7.4
- [ ] Failover drill on staging: RTO measured ≤15 min, RPO ≤1 min S11.3.2

### 7.6 Supply chain DoD

- [ ] Every release container in registry has: SBOM attached (SPDX + CycloneDX); SLSA L3 provenance attestation; cosign signature
- [ ] Verification commands work: `make sbom-verify IMAGE=...`; `cosign verify-attestation --type slsaprovenance ...`; `cosign verify --key ... ...`
- [ ] Phase 10 SPIRE cosign attestor accepts both keyless OIDC (non-prod) and offline key (prod) signed images
- [ ] CI gate: HIGH/CRITICAL CVE in new deps blocks PR
- [ ] CI gate: banned-license in backend modules blocks PR
- [ ] CI gate: gosec HIGH/CRITICAL blocks PR
- [ ] Renovate weekly schedule active; security CVE auto-PR < 24h from disclosure
- [ ] Container registry scan continuous (Trivy daily); CVE alerts triaged

### 7.7 GitOps / Deployment DoD

- [ ] Argo CD operational in each cluster; Applications synced; AppProject RBAC enforced
- [ ] Per-cluster overrides correct (S11.8.1)
- [ ] Canary 5→25→50→100 over 30 min works (S11.8.2)
- [ ] Auto-rollback on SLO breach works (S11.8.3)
- [ ] Sync wave dependency order respected (S11.8.4)
- [ ] Self-heal corrects manual drift (S11.8.5)
- [ ] RBAC restricts prod sync to platform_admin only (S11.8.6)
- [ ] Cloudflare Access guards Argo CD UI

### 7.8 Documentation / Vault / Runbooks DoD

- [ ] `obsidian/kacho/KAC/KAC-127.md` updated with Phase 11 progress + PR URLs
- [ ] New vault entries committed (16+ files per §0 list)
- [ ] `obsidian/kacho/architecture.md` updated with multi-region topology + observability stack
- [ ] `obsidian/kacho/operations/multi-region-topology.md` + `obsidian/kacho/operations/slo-targets.md` created
- [ ] 15 runbooks in `kacho-deploy/docs/runbooks/iam/` (full content; not stubs)
- [ ] 4 critical runbooks tabletop-tested with transcripts committed (break-glass, regional-failover, gdpr-erasure, cert-renewal-failed)
- [ ] Postmortem template at `docs/runbooks/iam/postmortems/_template.md` referenced from all runbooks

### 7.9 Operator prerequisites (gates BEFORE cutover dry-run)

- [ ] **REQUIRES**: domain registration completed (`kacho.cloud` registered)
- [ ] **REQUIRES**: Cloudflare account on Pro plan or higher
- [ ] **REQUIRES**: Cloudflare zone added; NS records published; DNSSEC configured at registrar
- [ ] **REQUIRES**: Cloudflare API token in K8s Secret with `Zone:DNS:Edit` scope
- [ ] **REQUIRES**: multi-region cloud accounts provisioned (e.g., AWS eu-central-1 + eu-west-1)
- [ ] **REQUIRES**: HSM provisioned in production region (AWS CloudHSM or GCP Cloud HSM)
- [ ] **REQUIRES**: PagerDuty tenant + service keys per severity (P1, P2)
- [ ] **REQUIRES**: Slack workspace + `#iam-alerts` channel + webhook URL
- [ ] **REQUIRES**: SMTP relay accessible from cluster (for email severity P4)
- [ ] **REQUIRES**: container registry configured (GHCR/ECR) with cosign support
- [ ] **REQUIRES**: Sigstore Fulcio + Rekor accessible (for keyless signing non-prod CI)
- [ ] **REQUIRES**: GitHub OAuth app for Cloudflare Access (admin UIs)
- [ ] **REQUIRES**: HSTS preload submission at `hstspreload.org` (after first prod cert)

### 7.10 Production Cutover DoD

- [ ] Dev `e2c825` stand: continues operating (no decommission in Phase 11)
- [ ] Staging stand: Phase 11 deployed via blue/green; cutover ≤15 min; soak ≥2 weeks
- [ ] `prod-eu-central` + `prod-eu-west` clusters: Phase 11 deployed via Argo CD; sustained 99.95% availability ≥1 week
- [ ] Initial public cutover (DNS to `api.kacho.cloud`) executed per runbook; smoke verified S11.15.2
- [ ] No P1 incidents during first 7 days post-cutover (or all P1 incidents resolved within RTO target)
- [ ] Postmortem written for any P1 incident; action items tracked in KAC-tickets
- [ ] Phase 11 closeout: YT KAC-127 Phase 11 subtasks all in `Done`; all PRs merged; staging soak ≥2 weeks; prod soak ≥1 week

---

## 8. Cross-repo PR-chain (Phase 11)

Топологический порядок (по workspace `CLAUDE.md` §"Кросс-репо зависимости"):

1. **kacho-proto PR**: minimal proto annotation deltas. Merge first.
2. **kacho-corelib PR**: `corelib/observability/otel` + `corelib/region` + `corelib/slo`. Imports kacho-proto via `replace ../`. Merge second.
3. **kacho-iam, kacho-vpc, kacho-compute, kacho-loadbalancer, kacho-api-gateway PRs**: parallel (no inter-dependencies). Each imports kacho-corelib + kacho-proto. May merge in any order between themselves. CI in each repo temporarily pins corelib to `KAC-127-phase11` branch until corelib merged; then `ref: main`.
4. **kacho-deploy PRs**: bulk; can be split by sub-stack for reviewability:
   - PR-A: Cloudflare Terraform (depends on operator prereqs only)
   - PR-B: cert-manager + Ingress (depends on PR-A for Cloudflare API token Secret)
   - PR-C: Patroni Postgres HA (independent)
   - PR-D: Kafka MirrorMaker 2 (depends on PR-C for Postgres backing)
   - PR-E: ClickHouse cross-region (depends on PR-C)
   - PR-F: OpenFGA replicas (depends on PR-C)
   - PR-G: OTel + LGTM stack (independent)
   - PR-H: Alertmanager + PagerDuty/Slack (depends on PR-G)
   - PR-I: Argo CD + Rollouts (depends on PR-A through PR-H)
   - PR-J: Renovate config (root + per-sibling)
   - PR-K: Release CI workflow templates (per-sibling PRs)
   - PR-L: Dashboards + Alerts + Runbooks (depends on PR-G and PR-H)
   Internal dependency order managed via Argo CD sync waves; Helm template validation gates each PR.
5. **kacho-ui PR**: admin observability pages. Independent of bulk deploy work; can merge alongside kacho-deploy PRs.
6. **kacho-test PR**: e2e tests. Imports api-gateway endpoint. Merge after kacho-deploy PR-I (Argo CD operational; cutover ready).
7. **kacho-workspace PR**: vault closeout for Phase 11. Last. Documents merged state.

### 8.1 Cutover order per environment

1. **Dev**: Phase 11 PRs merged → Argo CD syncs → dev cluster gets full stack. Soak 1-2 weeks.
2. **Staging**: Phase 11 deployed via blue/green helm rollout. Cutover ≤15 min. Soak 2+ weeks. Failover drill exercised.
3. **Prod**:
   - `prod-eu-central` cluster: greenfield provision; Argo CD syncs; sustained ≥1 week before cutover.
   - `prod-eu-west` cluster: greenfield provision; Argo CD syncs; sustained ≥1 week before cutover.
   - Cloudflare DNS cutover `api.kacho.cloud` → orange-cloud enabled.
   - WAF rules promoted from `simulate` → `block` after 24h soak.
   - HSTS preload submitted.
   - Smoke verify via `kacho-yc-shim` CLI.
   - Slack announcement; runbook tab open for first 24h.

### 8.2 Rollback strategy

- **Full Phase 11 rollback** (worst case): revert Cloudflare DNS `api.kacho.cloud` to maintenance page (Cloudflare worker serving 503 + "service temporarily unavailable" + ETA); investigate; rollforward when fixed. ~5 min for DNS-only rollback.
- **Per-service rollback** during canary: ArgoRollouts auto-rollback handles this (S11.8.3).
- **Per-region rollback**: Cloudflare GeoDNS shifts traffic to surviving region while bad region investigated; ~90s DNS propagation.
- **Database state rollback**: WAL-G PITR available; tested S11.4.4. Used only as absolute last resort.
- Rollback time SLO: 30 min from decision to restored state for in-place rollback; 5 min for DNS-cutover rollback.

---

## 9. Out of scope (explicitly NOT in Phase 11)

- **OWASP ASVS L3 conformance test suite** — **Phase 12** (`sub-phase-3.12-iam-conformance-pentest-chaos-acceptance.md`); Phase 11 ships baseline OWASP ZAP scan but not full ASVS coverage
- **Continuous fuzzing (go-fuzz / native Go fuzz)** — **Phase 12**
- **Litmus chaos engineering / game-day** — **Phase 12** (Phase 11 has failover drill via `make failover-drill-staging` but not chaos suite)
- **External pentest engagement (NCC Group / Trail of Bits)** — **Phase 12** task 12.5
- **Bug bounty program + security.txt + disclosure.html** — **Phase 12** task 12.6
- **OpenID Foundation self-certification** — **Phase 12** task 12.7
- **FIDO Alliance WebAuthn conformance self-test** — **Phase 12**
- **Vault closeout (30+ files final state)** — **Phase 13**
- **US / APAC regions** — follow-up epic post-Phase-13; Phase 11 ships eu-central + eu-west mvp
- **Per-tenant data residency / isolated regions** — follow-up
- **CAEP back-channel receive** (Kachō receives external IdP push) — follow-up post-Phase-13
- **mTLS-bound JWT (RFC 8705 cnf=x5t#S256)** — already implemented in Phase 2 AuthN; Phase 11 just deploys to production
- **Post-quantum hybrid TLS (X25519+ML-KEM Kyber768)** — continuous enablement track per design D-28; activated when cert-manager + Cloudflare both support PQ; NOT gated on Phase 11 sign-off
- **AWS Marketplace listing / Cloud Foundation onboarding** — separate go-to-market track post-Phase-13
- **DDoS L7 application-layer mitigation custom rules beyond Cloudflare defaults** — Phase 12 if profiling shows need
- **Service-to-service rate-limit** (cross-service mesh-level QoS) — Phase 11 has per-principal rate-limit at edge; mesh-level requires Cilium L7 policy extension (Phase 12 if needed)

---

## 10. Open Questions — RESOLVED

| # | Question | Resolution |
|---|---|---|
| 1 | Cloudflare vs Fastly vs AWS CloudFront vs Akamai? | **Cloudflare** — best DDoS + WAF + bot management combo at production scale; Cloudflare Access for admin UIs; native HTTP/3 + Anycast + DNSSEC + RPKI (P11-D1) |
| 2 | TLS 1.2 fallback or TLS 1.3 only? | **TLS 1.3 only** — closes downgrade attacks (P11-D2) |
| 3 | HTTP/3 origin or HTTP/2 origin? | **HTTP/2 origin** — NGINX QUIC maturity gap (P11-D3); revisit in Phase 12 |
| 4 | Active-active vs active-passive multi-region? | **Active-active** — faster failover, no cold-start (P11-D4) |
| 5 | Patroni vs CloudSQL HA vs Aurora? | **Patroni** for portability (mvp); CloudSQL/Aurora acceptable as per-cloud override (P11-D5) |
| 6 | Kafka MirrorMaker 2 vs Confluent Replicator vs custom? | **MM2** — OSS canonical; offset translation built-in (P11-D6) |
| 7 | ClickHouse with ZooKeeper vs Keeper? | **Keeper** built-in — reduces operational surface (P11-D7) |
| 8 | OpenFGA writer multi-master? | **Single-master** — OpenFGA doesn't support multi-writer natively; conflict resolution complex (P11-D8) |
| 9 | Argo CD vs FluxCD? | **Argo CD** — ecosystem maturity + UI superior; ArgoRollouts canary pattern (P11-D9) |
| 10 | Canary duration: 30 min vs longer? | **30 min** — balances catch rate (longer = more signal) vs deploy throughput (P11-D9) |
| 11 | SLO availability target: 99.9% vs 99.95% vs 99.99%? | **99.95%** — industry-standard control-plane; 99.99% requires 5x cost for marginal gain (P11-D20) |
| 12 | LGTM vs Datadog vs Elastic? | **LGTM** — Apache-2.0 OSS, S3 backend, no vendor lock-in (P11-D17) |
| 13 | OTel sampling: 100% everything vs tail-based? | **100% control-plane / 5% data-plane + tail-sample errors** — balances storage cost + signal (P11-D30) |
| 14 | PagerDuty vs Opsgenie vs custom? | **PagerDuty** — industry standard; mature mobile + escalation (P11-D18) |
| 15 | Banned-license: GPLv3 in backend? | **Block** GPLv3/AGPL family in backend Go modules; allow LGPL transitive (P11-D24) |
| 16 | cosign keyless OIDC vs offline key? | **Keyless for non-prod; offline key for prod** (P11-D13) |
| 17 | SLSA L2 vs L3? | **L3** via gh-actions/attest-build-provenance (P11-D12) — meets SOC 2 supply-chain requirements |
| 18 | Cert-manager DNS-01 vs HTTP-01 challenge? | **DNS-01 via Cloudflare API** — supports wildcards if needed; doesn't expose HTTP-01 endpoint (P11-D10) |
| 19 | HSTS preload: submit or not? | **Submit** — closes first-visit MITM window; one-time manual action (P11-D26) |
| 20 | Cloudflare Access for admin UIs (Grafana, Argo CD)? | **Yes** — defense-in-depth; OIDC challenge at edge independent of in-app authz (P11-D27) |
| 21 | Runbook tabletop frequency? | **Quarterly** for critical (break-glass, regional-failover, GDPR, cert-renewal); annual for less-critical (P11-D19) |
| 22 | Renovate vs Dependabot? | **Renovate** — richer grouping (P11-D15) |
| 23 | Per-cluster Helm chart vs single chart with overrides? | **Single chart with per-cluster overrides** (P11-D25) |
| 24 | Two ECDSA P-256 cert chains vs ECDSA + RSA dual? | **ECDSA only** — faster handshake; clients without ECDSA support are negligible (P11-D2) |
| 25 | Operator prerequisites in scope or out? | **Out of scope but explicit gates** with REQUIRES markers (P11-D28) |
| 26 | Synthetic blackbox probe location: inside or outside cluster? | **Outside cluster** (Cloudflare Worker / external cloud probe) — measures user-perceived availability not internal liveness (S11.14.4) |
| 27 | Error budget burn-rate alerts: which windows? | **1h (14.4×) + 6h (6×)** per Google SRE workbook; catches fast (1h) and slow (6h) burns (P11-D20) |
| 28 | DDoS L4/L7 — do we need anything beyond Cloudflare defaults? | **No** for Phase 11; Cloudflare DDoS protection sufficient at expected load; Phase 12 chaos game-day will profile and add custom rules if needed |
| 29 | Per-tenant rate-limit at edge vs per-IP only? | **Per-IP at Cloudflare edge + per-principal in api-gateway middleware** — two layers (P11-D14 implicit in Cloudflare + api-gateway design) |
| 30 | What does the `api.kacho.cloud` domain serve when both regions down? | **Cloudflare worker fallback page** serving 503 + maintenance message + ETA + status page link (`status.kacho.cloud`); on-call paged immediately |

---

## 11. Risks & Mitigations (Phase 11)

| Risk | Severity | Mitigation |
|---|---|---|
| **HSTS preload submission accidentally + irreversible** for >12 months | High | Submit only after thorough soak; documented in runbook; explicit operator confirmation step |
| **Let's Encrypt rate-limit on first prod cert** (5 cert per registered domain per week) | Medium | Use LE staging issuer for non-prod; first prod cert issued once; subsequent are renewals (not new) |
| **Cloudflare API token compromise** could allow attacker to redirect DNS | High | API token scoped to `Zone:DNS:Edit` only (no Zone:Edit); rotate yearly; alert on API audit log anomaly |
| **Cross-region Postgres replication lag exceeds 1 min** under load | Medium | Patroni `synchronous_commit=remote_write` enforces ACK; if lag persists, sync standby auto-disables (alert); failover available |
| **Argo CD canary auto-rollback misfires** (false positive SLO breach) | Medium | AnalysisTemplate threshold tuned conservatively (5× error rate, 1.5× latency); manual override available |
| **Renovate auto-merge breaks production** | Medium | Auto-merge only for minor + patch with CI green; major + security require manual review; staging soak 48h before prod |
| **OTel collector OOM under spike traffic** | Medium | Resource limits + HPA on Deployment; DaemonSet has only minimal pipeline; head-sampling drops excess before processing |
| **PagerDuty outage during incident** | Low | Slack + email as secondary channels; runbook escalation includes phone tree fallback |
| **HSM provisioning delay** (CloudHSM ramp-up ~weeks) | Medium | Start in Phase 10 prep; SoftHSM2 for dev/staging same code path |
| **Cloudflare WAF false positive locks out legitimate users** | Medium | 24h `simulate` soak before `block`; log review; whitelist known IPs; emergency disable via Cloudflare dashboard |
| **Multi-region split-brain on partial network partition** | High | Patroni etcd DCS (single quorum); Keeper (ClickHouse) quorum spans regions; Kafka KRaft per-region (no cross-region quorum); fail safe to read-only on minority side |
| **WAL-G S3 backup costs grow unbounded** | Low | 30d hot + selective Glacier; lifecycle policy enforced; alert on bucket growth >2× expected |
| **Per-region SLO regression masked by other region** | Medium | Per-region SLO dashboards + alerts; aggregate dashboard + per-region drill-down |
| **Cosign Sigstore Rekor outage** blocks non-prod releases | Low | Production uses offline key (no Rekor dep); non-prod accepts brief unavailability; release CI retries with backoff |
| **Long-running release PR (>1 week) accumulates Renovate drift** | Low | Rebase weekly; conflict resolution standard |
| **Tabletop runbook execution exposes runbook bugs at worst time** | Medium | Quarterly tabletops in advance of any production incident; transcripts + post-tabletop runbook updates |
| **HSTS preload entry blocks subdomain experiments** | Medium | Test subdomains live on separate domain (e.g., `kacho-experiments.cloud`); production preload boundary documented |
| **Cloudflare Access OIDC outage blocks admin UI access during incident** | Low | Cloudflare Access supports session-token caching (~hours); SRE accesses admin UI before token expiry; runbook documents break-glass to bypass via Cloudflare account direct console |
| **MirrorMaker 2 misconfiguration causes consumer duplicates on failover** | High | Test failover quarterly via `make failover-drill-staging`; consumer idempotency verified at application layer |
| **ClickHouse cross-region replication backlog grows during partition** | Medium | Keeper-coordinated retry; alert if backlog > 1h sustained; manual catch-up procedure in runbook |

---

## 12. References

- Design doc §13 Production deployment + §13.5 Observability + §13.6 SLO targets + §14 Threat model
- Plan doc §"Phase 11" tasks 11.1-11.9
- Workspace `CLAUDE.md` — запреты, кросс-репо порядок, кросс-доменные ссылки
- Cloudflare WAF managed rules: <https://developers.cloudflare.com/waf/managed-rules/>
- Cloudflare Access: <https://developers.cloudflare.com/cloudflare-one/applications/configure-apps/>
- HSTS preload: <https://hstspreload.org>
- cert-manager: <https://cert-manager.io/docs/>
- Let's Encrypt ACME: <https://letsencrypt.org/docs/>
- Patroni: <https://patroni.readthedocs.io/>
- WAL-G: <https://github.com/wal-g/wal-g>
- Kafka MirrorMaker 2: <https://kafka.apache.org/documentation/#georeplication>
- ClickHouse Replicated MergeTree + Keeper: <https://clickhouse.com/docs/en/engines/table-engines/mergetree-family/replication>
- OpenFGA replicas + consistency: <https://openfga.dev/docs/getting-started/consistency-token>
- Argo CD: <https://argo-cd.readthedocs.io>
- Argo Rollouts: <https://argoproj.github.io/argo-rollouts/>
- SLSA framework: <https://slsa.dev>
- in-toto attest-build-provenance: <https://github.com/actions/attest-build-provenance>
- cosign + sigstore: <https://docs.sigstore.dev/cosign/overview/>
- syft (SBOM): <https://github.com/anchore/syft>
- Trivy: <https://aquasecurity.github.io/trivy/>
- Grype: <https://github.com/anchore/grype>
- gosec: <https://github.com/securego/gosec>
- Renovate: <https://docs.renovatebot.com/>
- OpenTelemetry: <https://opentelemetry.io/docs/>
- Grafana LGTM stack: <https://grafana.com/oss/>
- Tempo: <https://grafana.com/docs/tempo/latest/>
- Mimir: <https://grafana.com/docs/mimir/latest/>
- Loki: <https://grafana.com/docs/loki/latest/>
- Alertmanager: <https://prometheus.io/docs/alerting/latest/alertmanager/>
- PagerDuty Events API v2: <https://developer.pagerduty.com/api-reference/>
- Google SRE workbook — Error Budget Policy: <https://sre.google/workbook/error-budget-policy/>

---

## 13. Sign-off

| Role | Agent | Action | Status |
|---|---|---|---|
| Author | `acceptance-author` (production-edition; no strict backward-compat; operator-prereq markers explicit) | Draft created | ✅ |
| Reviewer | `acceptance-reviewer` | Review for: coverage, completeness, traceability, scope, alignment with запреты #1-#11, alignment with design doc §13 + §13.5 + §14 + plan Phase 11 | ⏳ pending |
| (After APPROVED) | `superpowers:writing-plans` | Convert to detailed implementation plan per task | ⏸ blocked on APPROVED |
| (After plan) | `proto-sync`, `rpc-implementer`, `migration-writer`, `api-gateway-registrar`, `integration-tester`, plus deploy-specialist roles | Execute tasks | ⏸ blocked on plan |

**Gate**: per запрет #1, no code begins until `acceptance-reviewer` returns ✅ APPROVED on this document. Customer (end-user) does NOT approve this acceptance — they validate smoke/e2e in step 7 per `04-roadmap-and-phasing.md` §2.

**Operator prerequisite gates**: per P11-D28, external resource provisioning (domain, Cloudflare, multi-region cloud accounts, HSM, PagerDuty, Slack, SMTP, container registry, HSTS preload submission) MUST be operator-confirmed BEFORE cutover dry-run; these gates are documented in §7.9 and referenced via `# REQUIRES` markers throughout §6. They are NOT engineering deliverables and NOT "TODO" — they are explicit external dependencies of Phase 11.

---

**End of acceptance doc — Phase 11**
