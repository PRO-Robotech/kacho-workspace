# Sub-phase W3.2 — Observability customisation для kacho-iam — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: (TBD — subtask of эпика `KAC-134` "kacho-iam → production-ready", Wave 3)
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-deploy` — observability chart customisation
>     - `helm/umbrella/charts/observability/files/dashboards/iam-overview.json` (extend)
>     - `helm/umbrella/charts/observability/files/dashboards/iam-authz-fga.json` (extend)
>     - `helm/umbrella/charts/observability/files/dashboards/iam-anti-anon.json` (**NEW**)
>     - `helm/umbrella/charts/observability/files/dashboards/iam-outbox-drainer.json` (**NEW**)
>     - `helm/umbrella/charts/observability/files/dashboards/iam-jit-sakeys.json` (**NEW**)
>     - `helm/umbrella/charts/observability/files/dashboards/iam-audit-pipeline.json` (extend — add VictoriaLogs panels)
>     - `helm/umbrella/charts/observability/templates/vmrules/iam-*.yaml` (**NEW** dir) — VMRule CRDs replacing existing PrometheusRule (or coexisting if Mimir kept)
>     - `helm/umbrella/charts/observability/files/iam-logs-queries.yaml` (**NEW**) — saved LogsQL queries
>     - `helm/umbrella/charts/observability/files/iam-trace-sampling.yaml` (**NEW**) — VictoriaTraces head-based sampling policy
>     - `helm/umbrella/charts/observability/values.yaml` (extend — vmsingle/vmselect/vlogs/vtraces section if not present)
>   - **Secondary (kacho-iam, optional emit additions)**: `PRO-Robotech/kacho-iam` —
>     - `internal/observability/metrics.go` — register new counter `kacho_iam_anti_anon_denied_total{rpc}` (W1.3 may already emit; verify) и counter `kacho_iam_audit_emit_failed_total` (если ещё не emit'ится)
>     - `internal/observability/tracing.go` — verify span attributes include `kacho.principal.type`, `kacho.tenant.id`, `kacho.rpc.method`
>   - **NOT touched (verified)**: `kacho-proto` (no new RPC / no proto change); `kacho-api-gateway` (no new RPC; existing gateway anti-anon metric already в `kacho_api_gateway_anti_anon_denied_total` per W1.3); `kacho-corelib` (otel-emit already wired in `corelib/observability/`); migrations — нет.
> **Branch (kacho-deploy)**: `KAC-W3.2` (off `main`); **branch (kacho-iam, если потребуется emit additions)**: `KAC-W3.2`.
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 3.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave3.md` (TBD — пишется при старте W3).
> **Source of scope**:
> - `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Waves table — W3 row «observability customisation (dashboards/alerts)».
> - `docs/superpowers/plans/2026-05-21-production-launch-plan.md` WS-6 (Observability) + Часть 4 DoD «Observability: метрики/логи/трейсы/алерты/дашборды/runbooks».
> - `docs/superpowers/plans/2026-05-21-production-launch-plan.md` §6 DECISION-AUDIT — VictoriaLogs + vector.dev стек (НЕ Kafka/ClickHouse/HSM/Merkle).
> - Existing umbrella obs chart `project/kacho-deploy/helm/umbrella/charts/observability/` — это **baseline** (Prometheus-style: Grafana/Mimir/Loki/Tempo + 3 PrometheusRule файла + 11 dashboard JSON). W3.2 — **миграция / параллельное добавление** VictoriaMetrics/VictoriaLogs/VictoriaTraces (соответствует master-plan tech-stack «VictoriaMetrics+Logs+Traces») для kacho-iam-specific signals.
>
> **Predecessors (must be `main`-merged before W3.2 impl starts)**:
> - **W1.1** ([[KAC-137]]) — `fga_outbox` table + drainer existence. W3.2 emit metrics: `kacho_iam_fga_outbox_pending_total`, `kacho_iam_fga_outbox_drainer_iterations_total`, `kacho_iam_fga_outbox_drain_latency_seconds`. Без W1.1 эти signals не существуют → дашборд показывает «no data».
> - **W1.2** ([[KAC-138]]) — `subject_change_outbox` table + cache invalidation pipeline. W3.2 emit: `kacho_iam_subject_change_outbox_pending_total`, `kacho_iam_subject_change_outbox_lag_seconds`, `kacho_api_gateway_authz_cache_invalidations_total`. Without W1.2 — no data on cache-invalidation alerts.
> - **W1.3** ([[KAC-139]]) — gateway anti-anon enable + fail-closed. Emits `kacho_api_gateway_anti_anon_denied_total{rpc,method}` (gateway-side) и `kacho_iam_anti_anon_denied_total{rpc}` (iam-interceptor-side). W3.2 dashboards/alerts depend on these counters being live.
> - **W2.B.9** (audit pipeline VictoriaLogs ingestion) — emits structured audit logs via vector.dev sink → VictoriaLogs. W3.2 saved LogsQL queries assume `_stream={kacho_service="kacho-iam", kacho_audit="true"}` тэгирование уже работает. Если W2.B.9 ещё не merged на момент старта W3.2 — audit-LogsQL panels deferred к закрытию W2.B.9.
>
> **Why W3.2 завершает observability для kacho-iam**: после W1.1–W1.3 + W2.B.9 backend emit'ит **новые** kacho-iam-specific сигналы (fga_outbox depth, subject_change_outbox lag, anti-anon denied, JIT-pending queue, SA-key issue rate, audit-emit failures). **Существующий** observability chart покрывает только generic IAM (AuthN success, FGA Check latency, token issuance, JWKS rotation, CAEP delivery). **W3.2 закрывает gap** — кастомизация под все W1-W2-emit'нутые сигналы + переход на VictoriaMetrics/Logs/Traces стек (per master-plan tech-stack и AUDIT decision из prod-launch-plan §6).

---

## 0. Преамбула — что эта sub-итерация (précis)

W3.2 кастомизирует observability stack под **новые** kacho-iam-specific сигналы, которые
emit'ятся после Wave 1 + Wave 2.B:

| Сигнал | Источник (Wave) | Тип | Используется в |
|---|---|---|---|
| `kacho_iam_fga_outbox_pending_total` | W1.1 | gauge | dashboard `iam-outbox-drainer`; alert `FGAOutboxBacklogHigh` |
| `kacho_iam_fga_outbox_drainer_iterations_total{outcome}` | W1.1 | counter | dashboard, alert `FGADrainerStalled` |
| `kacho_iam_fga_outbox_drain_latency_seconds` | W1.1 | histogram | dashboard `iam-outbox-drainer` |
| `kacho_iam_subject_change_outbox_pending_total` | W1.2 | gauge | dashboard `iam-outbox-drainer`; alert `SubjectChangeBacklogHigh` |
| `kacho_iam_subject_change_outbox_lag_seconds` | W1.2 | gauge | dashboard, alert `CacheInvalidationLagHigh` |
| `kacho_api_gateway_anti_anon_denied_total{method,rpc}` | W1.3 | counter | dashboard `iam-anti-anon`; alert `AntiAnonHitSpike` |
| `kacho_iam_anti_anon_denied_total{rpc}` | W1.3 / interceptor | counter | dashboard `iam-anti-anon` |
| `kacho_iam_jit_pending_queue_depth` | W2.B (JIT) | gauge | dashboard `iam-jit-sakeys`; alert `JITPendingQueueDepthHigh` |
| `kacho_iam_sa_key_issued_total{kind}` | W2.B (SA-key) | counter | dashboard `iam-jit-sakeys` |
| `kacho_iam_audit_events_emitted_total{kind,outcome}` | W2.B.9 | counter | dashboard `iam-audit-pipeline`; alert `AuditEmitFailureRate` |
| `kacho_iam_audit_emit_failed_total` | W2.B.9 | counter | alert `AuditEmitFailureRate` (page severity) |
| **per-RPC**: `kacho_rpc_requests_total{service,method,grpc_code}` | corelib otel (already exists) | counter | dashboard `iam-overview` (extend — per-RPC RED) |
| **per-RPC**: `kacho_rpc_request_duration_seconds_bucket{service,method}` | corelib otel | histogram | dashboard (p50/p95/p99) |
| **trace spans** | corelib otel (already exists) | trace | service-dependency map verification; sampling 10%/100%-on-error |
| **audit logs** | W2.B.9 vector.dev → VictoriaLogs | log-event | saved LogsQL queries (`iam-logs-queries.yaml`) |

W3.2 поставляет:

1. **Dashboards-as-code** — 3 новых JSON + 3 extension'а к существующим (Grafana совместим VictoriaMetrics через Prometheus datasource API). Все panels — PromQL/MetricsQL queries against `vmsingle` (или `mimir` если оба datasource'а оставлены — см. OQ-W3.2-1).
2. **Alert rules** — VMRule CRDs (`operator.victoriametrics.com/v1beta1`) либо PrometheusRule (если VictoriaMetrics deploy'ится в Prometheus-compatible mode без operator) — 9 новых правил под kacho-iam-specific сигналы.
3. **Saved LogsQL queries** — `iam-logs-queries.yaml` file (loaded as ConfigMap, mounted в VictoriaLogs UI / consumable through API). Queries: per-tenant audit trail, BreakGlass approve, mass SA-key issue, repeated PermissionDenied from one principal, GDPR erasure verification.
4. **Trace sampling policy** — `iam-trace-sampling.yaml` (otel-collector / VictoriaTraces config). Head-based 10% baseline, 100% on errors (grpc_status != 0), 100% on slow-spans (duration > 1s).
5. **Service-dependency map verification test** — integration test проверяет, что VictoriaTraces возвращает expected edges из kacho-iam: `kacho-iam → postgres`, `kacho-iam → openfga`, `kacho-iam → kratos` (если есть), `kacho-iam → hydra` (если есть), `kacho-iam → vector.dev` (audit sink).

### 0.1 W3.2 НЕ включает

- **Observability customisation для kacho-vpc / kacho-compute / kacho-loadbalancer (NLB)** — это отдельные эпики (post-W3 для vpc/compute; kacho-loadbalancer/NLB sub-phase 4.0). W3.2 — **только kacho-iam-specific signals**. Generic stack baseline (VictoriaMetrics deploy / vmagent scrape config / vlogs deploy) — предполагается уже задеплоен (W3.3 / WS-2 prod-launch infra работа).
- **Formal SLO definition** (multi-burn-rate, error budget, alert-on-burn-rate-burn) — это рекомендованная работа, но **separate work-item** после W3.2. W3.2 не определяет SLI/SLO формально; даёт raw RED-метрики на которых SLO позже посчитается. Существующий `iam-slo-burn-rate.json` dashboard и `slo-burn-rate.yaml` rule — оставляем as-is (не трогаем).
- **Pager rotation / on-call schedule / PagerDuty service** — это **process**, не infra. AlertManager уже имеет PagerDuty integration в umbrella chart (`alertmanager.pagerduty.enabled=true` per existing values.yaml); W3.2 не меняет alert routing; новые alerts naturally подцепят существующий routing через `severity:` label (P1/P2/P3/P4 mapping уже есть).
- **Custom Grafana plugins** (panels не из core, exotic visualisations) — не нужно; всё реализуемо через core panels (stat / graph / table / heatmap / state-timeline).
- **Tenant-facing dashboards** (per-tenant view доступный через UI tenant-admin'у) — это отдельный проект (kacho-ui customer-facing observability). W3.2 — **admin-internal** dashboards (cluster-internal grafana ingress, OIDC-gated; см. §1 §6 в `CLAUDE.md` Запреты — Internal-vs-external для admin observability). Tenant-visible audit query — **только** через kacho-iam APIs (`/iam/v1/audit_events:search` если будет; в W3.2-scope нет), не через прямой VictoriaLogs read.
- **Runbooks** — обновлять runbook URL в new alerts на placeholder (`https://github.com/PRO-Robotech/kacho-deploy/blob/main/docs/runbooks/iam/<runbook>.md`); файлы runbook'ов **сами** — отдельная работа (часть W3.4 freeze checklist). W3.2 alert annotations указывают expected runbook path, но **физически файлы создаются вне scope** — finding-issue в kacho-deploy если runbook'и отсутствуют на момент freeze.
- **Migration сейчас активных PrometheusRule на VMRule** — coexistence model: новые kacho-iam customizations пишутся как VMRule (operator.victoriametrics.com); существующие 3 PrometheusRule (`iam-availability`, `slo-burn-rate`, `replication-lag`) остаются для совместимости (vmoperator понимает PrometheusRule через `additionalScrapeConfigs`). Если deploy решит окончательно мигрировать — separate work. OQ-W3.2-1 обсуждает.
- **VictoriaMetrics / VictoriaLogs / VictoriaTraces deploy itself** — это W3.3 (cluster-baseline infra) либо предполагается уже задеплоено через operator. W3.2 — **customisation поверх deployed stack**. Если на момент старта W3.2 deploy ещё на Mimir/Loki/Tempo (per current umbrella chart) — W3.2 поставляется в Prometheus-compatible форме (PromQL queries работают на Mimir тоже; LogsQL замещается на LogQL для Loki — см. OQ-W3.2-2 для backward-compat strategy).

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** | gate данного doc; impl стартует только после APPROVED. |
| **Запрет #2** | в коде/комментариях/тестах не упоминается. |
| **Запрет #3** | ORM не применим — observability-config — JSON dashboards + YAML rules, не Go-код с DB. |
| **Запрет #4** | observability stack — отдельный namespace `observability-system`; никакого cross-service cascade-delete. |
| **Запрет #5** | applied migrations не редактируем — W3.2 не добавляет миграций. |
| **Запрет #6** (Internal-vs-external) | **Critical**: admin-internal observability stack (grafana, vmui, vlogs UI, vtraces UI) хостится на cluster-internal ingress (см. existing `grafana.ingress.host: grafana.{{ .Values.kacho.domain }}` + OIDC-gated). Tenant-visible metrics/logs **не** экспонируются напрямую; tenant-facing audit query — через `kacho-iam` APIs (separate scope). Trace data / log-streams содержат placement-hint'ы (`principal.type`, `kacho.tenant.id`) — раскрывать только cluster-admin'у через OIDC group claim `kacho-cloud-admins`. |
| **Запрет #6** уточнение | Internal-only kacho-iam admin RPCs (e.g. `InternalIAMService.Check`) emit метрики/traces — эти signals **остаются** в общем VictoriaMetrics, **но** их per-method dashboards/alerts помечены `audience=cluster-admin` label и filterable в Grafana через folder permission («Internal admin» folder, OIDC group-restricted). |
| **Запрет #7** | broker отсутствует. (vector.dev — sidecar, не broker.) |
| **Запрет #8** | каждая service-DB остаётся отдельной; observability shared cluster-wide ОК (cross-cutting concern). |
| **Запрет #9** | observability — read-only data plane, не RPC мутации. |
| **Запрет #10** (within-service refs DB-level) | n/a — нет DB-state в W3.2. |
| **Запрет #11** (NO TODO / tech debt) | новые alerts с runbook URL — physical runbook file может отсутствовать на момент W3.2 merge; это **out-of-scope (separate work-item)**, не TODO. Документировано в §0.1 как «runbook files — separate work». Acceptance-reviewer enforces: no `TODO`/`FIXME` в delivered JSON/YAML files. |
| **Запрет #12** (test-first + tests-in-PR + RED→GREEN) | для observability — pre-deploy synthetic-trigger integration test. См. §5/§7. |
| **CLAUDE.md §«Инфра-чувствительные данные»** | W3.2 scope = kacho-iam (control-plane, не data-plane), placement/SID/HV-id метрик нет → все W3.2 signals не инфра-чувствительные. Audit-log events могут содержать `principal.id` / `tenant.id` — раскрывать только cluster-admin (OIDC group filter); tenant-internal принципалы НЕ должны видеть friend-tenant identity-данные через прямой VL access (см. §6 — Internal-vs-external). |
| **CLAUDE.md §Принцип переиспользования через kacho-corelib** | otel emit primitives уже в corelib (`corelib/observability/`). W3.2 не добавляет corelib helpers; iam-specific counters регистрируются в `kacho-iam/internal/observability/metrics.go` (single-service usage). |
| **CLAUDE.md §«Within-service refs DB-уровень обязателен»** | n/a. |
| **Vault discipline** | NEW: `obsidian/kacho/observability/iam-dashboards.md`, `iam-alerts.md`, `iam-logsql-saved.md`, `iam-trace-sampling.md`. UPDATE: `architecture.md` (observability layer reference); `KAC/KAC-W3.2.md` trail. |

---

## 2. Глоссарий

- **RED method** — Rate, Errors, Duration: per-RPC RPS, error rate (per gRPC code), duration percentiles. Applied к kacho-iam gRPC services.
- **USE method** — Utilization, Saturation, Errors: per-resource (DB pool, drainer goroutine, outbox queue). Applied к internal kacho-iam resources.
- **golden signals** — latency / traffic / errors / saturation (Google SRE book). RED + USE = full coverage.
- **p50/p95/p99** — percentile latency from histogram_quantile via PromQL/MetricsQL `histogram_quantile(0.95, sum by (le) (rate(<metric>[5m])))`.
- **head-based sampling** — decision at trace start (root span); 10% baseline keeps random 10% of all traces; deterministic via trace-id hash. Alternative — tail-based (decide at span finish on error / slow) — not used in W3.2 default (more complex; defer).
- **VictoriaMetrics single-node (vmsingle)** vs **cluster (vmstorage/vmselect/vmagent)** — deploy topology choice; W3.2 не выбирает (baseline за W3.3); writes assume vmsingle для dev, cluster для prod.
- **VictoriaLogs (VL)** — log-aggregation server with LogsQL query language; ingest path: vector.dev sink → VL HTTP API. Stream-based с tag-indexed search.
- **VictoriaTraces (VT)** — trace-store with Jaeger-compatible API; ingest path: otel-collector OTLP → VT.
- **VMRule** — `operator.victoriametrics.com/v1beta1` CRD; defines alert/recording rules. Equivalent to PrometheusRule (`monitoring.coreos.com/v1`), но VictoriaMetrics-native.
- **PromQL/MetricsQL** — query languages; VictoriaMetrics supports both. W3.2 queries — PromQL-compatible subset for cross-deploy compat (Mimir-fallback).
- **LogsQL** — VictoriaLogs query language; not PromQL-compatible. E.g.: `_stream:{kacho_service="kacho-iam"} kacho_audit:true | stats count() by (principal_id)`.
- **service-dependency map** — VictoriaTraces Jaeger-API `/api/dependencies` endpoint; returns service→service call edges aggregated from traces. Used для verification: kacho-iam → expected peers.
- **anti-anon hit** — request denied by anti-anon interceptor (W1.3 / W1.6 #43); counter `kacho_api_gateway_anti_anon_denied_total{method,rpc}` increments. Spike = potential attack или misconfigured client.
- **JIT-pending queue depth** — count of `jit_pending` rows in state=PENDING_APPROVAL; gauge sampled every N seconds by background metric-collector goroutine in kacho-iam (или derive via DB scrape с pgbouncer-stats-exporter pattern — W3.2 chooses goroutine-emit, см. §5.1).

---

## 3. Decisions (приняты до старта W3.2)

| ID | Решение | Обоснование |
|---|---|---|
| **D-W3.2-A** | Observability stack — **VictoriaMetrics + VictoriaLogs + VictoriaTraces** (НЕ Prometheus / Loki / Tempo / Grafana Cloud) | Per master-plan tech-stack + AUDIT decision (prod-launch-plan §6). VictoriaMetrics — cheaper storage at scale, MetricsQL extensions. VictoriaLogs — purpose-built log-aggregation (cheaper than Loki for high-cardinality streams). VictoriaTraces — Jaeger-compatible, integrates with otel-collector. Self-hosted on cluster (not Grafana Cloud SaaS). |
| **D-W3.2-B** | Grafana **остаётся** — datasource type = «Prometheus» pointed at VictoriaMetrics (`vmselect:8481/select/0/prometheus/`); «Loki» datasource pointed at VictoriaLogs (`/select/logsql/query`); «Jaeger» datasource pointed at VictoriaTraces | Grafana — единственный mature UI с rich panels + alerting + OIDC + RBAC. VictoriaMetrics/Logs/Traces — backend storage; Grafana — viz. Существующий umbrella chart already deploys Grafana — переключаем datasource URL без замены UI. |
| **D-W3.2-C** | AlertManager **остаётся** (existing); новые VMRules / PrometheusRules feed in через **same** AlertManager. Severity routing — P1/P2/P3/P4 → PagerDuty/Slack channels (existing config). | Не переписываем routing; новые rules используют существующий severity contract. |
| **D-W3.2-D** | Pager destination — **PagerDuty** (existing umbrella chart `alertmanager.pagerduty.enabled=true`). Не webhook stub. | Уже есть в umbrella chart; не требует новой работы. **Пользователь упомянул «не PagerDuty — alert webhook stub»** — это **противоречит** existing chart config. Эскалирую в OQ-W3.2-3 для resolution. |
| **D-W3.2-E** | Trace sampling — **head-based 10% baseline, 100% on error** (грубо tail-OR-head комбинация: head-decision OR error-promote). Implementation в otel-collector через `tail_sampling` processor in spite of name (it handles both head and error-promote). Saturation guard: cap at 100 spans/s/service to prevent ingest overload. | Industry default. Tail-based «slow span» promotion — defer. Per umbrella values.yaml `sampling.controlPlane=1.0` для iam — переоценить: 100% control-plane sampling on prod = expensive; 10%+errors более устойчиво. Reviewer to confirm в OQ-W3.2-4. |
| **D-W3.2-F** | Alert thresholds — **calibrated post-baseline-deploy**, не hardcoded в W3.2. Initial PR ставит «conservative initial» values из existing literature (e.g. error rate >5% warn / >20% page); первая неделя на dev-стенде → tune. Acceptance-reviewer не блокирует merge на thresholds, документация даёт rationale + calibration plan. | Threshold tuning без baseline traffic — guesswork. OQ-W3.2-5. |
| **D-W3.2-G** | LogsQL queries — **stored as YAML file** (`iam-logs-queries.yaml`) loaded as ConfigMap; **не embedded в Grafana dashboards**. Reason: VictoriaLogs UI consumes ConfigMap directly; Grafana «Loki»-datasource also reads from query-file path through external loader. | Decouple query definitions from UI tool; reusable in CLI (`vlogs-cli`), CI checks, custom scripts. |
| **D-W3.2-H** | Dashboards — **Grafana JSON** (not jsonnet/grafonnet). | Existing chart uses raw JSON; не вводим новую сборочную систему ради W3.2. Если позже команда мигрирует на jsonnet — separate work. |
| **D-W3.2-I** | New counters в kacho-iam (если ещё не emit'ятся): `kacho_iam_audit_emit_failed_total`, `kacho_iam_jit_pending_queue_depth`, `kacho_iam_sa_key_issued_total{kind}`. Registered via `corelib/observability/registry` (existing pattern). | Emit-side work — minimal; counters trivially registered. Verification of W1.3 anti-anon counter naming (gateway-side vs iam-side) — см. OQ-W3.2-6. |

---

## 4. Open questions (DECISION-NEEDED) — нужно разрешить до старта impl

| ID | Вопрос | Рекомендация автора |
|---|---|---|
| **OQ-W3.2-1** | Existing umbrella chart использует Mimir/Loki/Tempo. W3.2 поставляет VictoriaMetrics/VL/VT. **Coexistence** (оба deploy'ятся) ИЛИ **replace** (remove Mimir/Loki/Tempo)? | **Coexistence на dev-kind / replace на prod**. Flag `observability.backend=victoria|grafana-stack` в values.yaml. Default `victoria`. Existing PrometheusRule файлы переносятся as-is (vmoperator понимает PrometheusRule CRD). Existing dashboard JSON queries are PromQL-compatible — работают против VictoriaMetrics через Prometheus-datasource. Replace decision — separate **W3.3 deploy work**. |
| **OQ-W3.2-2** | Backward-compat: если W3.2 merge'ится до W3.3 (deploy switch), dashboards указывают datasource «VictoriaMetrics» который ещё не deployed. | **Datasource UID параметризован**: dashboard JSON содержит placeholder `${DS_PROMETHEUS}` который Grafana resolves к active Prometheus-type datasource (Mimir или VictoriaMetrics). LogsQL queries — отдельный file, not in dashboards, deployed только когда VL is up. **W3.2 merge не блокирует на W3.3** — dashboards work против любого Prometheus-compatible backend. |
| **OQ-W3.2-3** | Pager destination — user указал «не PagerDuty — alert webhook stub», но existing chart uses PagerDuty integration. | **Сохранить PagerDuty** (existing chart). User'ское замечание интерпретирую как «не вводить **новую** PagerDuty integration ради W3.2» — existing config достаточен. Если user хочет webhook stub вместо — clarify в acceptance-reviewer pass; alternative — `alertmanager.pagerduty.enabled=false` flag для dev, webhook on prod. **Default: existing PagerDuty.** |
| **OQ-W3.2-4** | Trace sampling rate для kacho-iam: 100% (existing `sampling.controlPlane=1.0`) ИЛИ 10%+errors (W3.2 D-W3.2-E rec)? | **10% + errors для prod, 100% для dev**. Per-environment flag `observability.otelCollector.sampling.controlPlane=1.0|0.1`. Default in `values.yaml`: 1.0 (dev/staging); override in `values.prod.yaml`: 0.1. Reasoning: control-plane traffic под нагрузкой (10k RPS gateway) на 100% sampling = expensive. |
| **OQ-W3.2-5** | Alert thresholds calibration: какие initial values для `fga_outbox_pending > N`, `subject_change_outbox_lag > T`, `anti_anon_rate > X`? | **Initial conservative defaults** (will be tuned post-baseline-week-1): fga_outbox_pending > 100 for 5m → warn; > 1000 for 5m → page. subject_change_outbox_lag > 30s → warn. anti_anon_rate baseline TBD (no historic data); ставим placeholder `for 5m: rate > 10/min` → warn (явно «calibration needed» в alert annotation). Per-RPC error rate >5%/>20% — industry-standard, OK as-is. JIT-pending queue >50 → warn. audit_emit_failed > 0 → page (any failure is compliance risk). |
| **OQ-W3.2-6** | Anti-anon counter naming: gateway-side `kacho_api_gateway_anti_anon_denied_total{rpc,method}` ИЛИ iam-side `kacho_iam_anti_anon_denied_total{rpc}`? Где gateway middleware (W1.3) emit'ит — в gateway-namespace или iam-namespace? | **Оба**: gateway-side counter под gateway-namespace (W1.3 уже emit'ит — verify в impl); iam-side counter (W1.6 #43 interceptor) — отдельный counter под iam-namespace. Dashboard `iam-anti-anon` aggregates обе через `sum by (rpc) (kacho_api_gateway_anti_anon_denied_total{service="kacho-iam"}) + sum by (rpc) (kacho_iam_anti_anon_denied_total)`. Reviewer to confirm counter names exist in W1.3/W1.6 code; otherwise W3.2 PR adds emit лейбл в iam-interceptor as small follow-up. |
| **OQ-W3.2-7** | Dashboards для cluster-admin vs tenant-admin **разделение**? | **Cluster-admin only в W3.2**. Tenant-admin observability — отдельный проект (kacho-ui customer-facing). Grafana folder `Kacho Cloud / IAM (admin)` — OIDC-group-gated на `kacho-cloud-admins`. Запрет #6 enforced: tenant principals **не** имеют доступ к dashboards (no OIDC group claim). |
| **OQ-W3.2-8** | Saved LogsQL queries — формат: VictoriaLogs server-side stored queries (если поддерживается) ИЛИ client-side YAML с CLI consumer? | **Client-side YAML** + Grafana «Loki» datasource manual entry. VictoriaLogs пока не имеет server-side saved-queries feature. YAML — single source of truth, version-controlled, CI-lintable. CLI consumer — простой `vlogs query -f iam-logs-queries.yaml -q query-name -p var=value`. |
| **OQ-W3.2-9** | Synthetic-trigger integration test для alerts: deploy stack on ephemeral kind, generate synthetic load to trigger alert, verify AlertManager fires within X minutes. Where lives the test? | **`kacho-deploy/e2e/observability-alerts-test.sh`** — bash + kubectl + curl AlertManager API. Не testcontainers-go (Helm chart deploy too heavy for unit-test). Run on CI matrix `e2e-observability` separately from main e2e (slower; runs on PR merge to main only). |
| **OQ-W3.2-10** | Service-dependency map verification — какие edges expected from kacho-iam в W3.2 (post-W1-W2-merged state)? | Expected edges (verify in dependency map): `kacho-api-gateway → kacho-iam` (incoming); `kacho-iam → postgres-kacho-iam`; `kacho-iam → openfga` (FGA Check + Write); `kacho-iam → kratos` (if Kratos federation enabled); `kacho-iam → hydra` (if Hydra OAuth backend); `kacho-iam → vector-aggregator` (audit sink); optionally `kacho-iam → kacho-iam` (self-call: internal RPCs). **Не expected**: `kacho-iam → kacho-vpc` (нет cross-edge); `kacho-iam → kacho-compute` (нет). Acceptance-reviewer validates list matches W1-W2-finalised architecture. |

---

## 5. Implementation steps (impl spec)

### 5.1 Dashboards (Grafana JSON)

| File | Status | Coverage |
|---|---|---|
| `iam-overview.json` | EXTEND | Add panels: per-RPC RED (panel matrix: top-10 RPCs by RPS / error rate / p95 / p99) — `topk(10, sum by (method) (rate(kacho_rpc_requests_total{service="kacho-iam"}[5m])))` для RPS panel; analogous для error/duration. |
| `iam-authz-fga.json` | EXTEND | Add panels: FGA tuple-write latency p95 (`histogram_quantile(0.95, sum by (le, op) (rate(openfga_request_duration_ms_bucket{op=~"Write\|Delete"}[5m])))`); FGA tuple-write rate (`sum(rate(openfga_request_count_total{op=~"Write\|Delete"}[5m]))`). |
| `iam-anti-anon.json` | **NEW** | Panels: (1) anti-anon denies per minute timeseries — `sum(rate(kacho_api_gateway_anti_anon_denied_total{service="kacho-iam"}[1m])) + sum(rate(kacho_iam_anti_anon_denied_total[1m]))`; (2) top-10 RPC by anti-anon denies — `topk(10, sum by (rpc) (kacho_api_gateway_anti_anon_denied_total{service="kacho-iam"} + on(rpc) kacho_iam_anti_anon_denied_total))`; (3) deny-rate (denies / total-requests) — `sum(rate(kacho_api_gateway_anti_anon_denied_total{service="kacho-iam"}[5m])) / sum(rate(kacho_api_gateway_requests_total{service="kacho-iam"}[5m]))`; (4) per-source-IP deny rate (if anti-anon emits `src_ip` label — stretch). |
| `iam-outbox-drainer.json` | **NEW** | Panels: (1) `fga_outbox_pending_total` gauge over time; (2) `subject_change_outbox_pending_total` gauge; (3) drainer iteration rate (`rate(kacho_iam_fga_outbox_drainer_iterations_total[1m])`) split by `outcome` label; (4) drain latency p50/p95/p99 (`histogram_quantile(...)`); (5) subject_change_outbox_lag_seconds gauge; (6) authz cache invalidations rate (`rate(kacho_api_gateway_authz_cache_invalidations_total[1m])`). |
| `iam-jit-sakeys.json` | **NEW** | Panels: (1) JIT-pending queue depth gauge over time; (2) SA-key issue rate split by `kind` label; (3) JIT-approval latency (request → approve, derived from audit log via `kacho_iam_jit_approval_seconds_bucket` если emit'ится; otherwise — skip с note «requires W2.B emit»); (4) JIT-deny rate. |
| `iam-audit-pipeline.json` | EXTEND | Existing panels — оставить. Add: (1) audit events emitted per minute (`sum(rate(kacho_iam_audit_events_emitted_total[1m]))` split by `kind`); (2) audit emit failure rate (`rate(kacho_iam_audit_emit_failed_total[5m])`); (3) **VictoriaLogs-backed panel**: «last 100 audit events» — via Grafana «Loki»-datasource pointed at VictoriaLogs, LogsQL: `_stream:{kacho_service="kacho-iam", kacho_audit="true"}`. |

Каждый new dashboard JSON содержит:
- `uid` matching filename (e.g. `iam-anti-anon`)
- `tags`: `["kacho", "iam", "<topic>"]`
- `time.from = "now-6h"`, `refresh = "30s"` defaults
- `schemaVersion: 39` (existing baseline)
- Datasource refs by template variable `${DS_PROMETHEUS}` (resolved at Grafana load time) — see OQ-W3.2-2

Dashboards registered in `observability.grafana.dashboards` list (existing values.yaml structure) — append new uids:
```yaml
dashboards:
  - "iam-overview"           # extended
  - "iam-authn"              # untouched
  - "iam-authz-fga"          # extended
  - "iam-audit-pipeline"     # extended
  - "iam-caep-pipeline"      # untouched
  - "iam-spiffe-mesh"        # untouched
  - "iam-slo-burn-rate"      # untouched
  - "iam-anti-anon"          # NEW
  - "iam-outbox-drainer"     # NEW
  - "iam-jit-sakeys"         # NEW
  # ... other existing entries unchanged
```

### 5.2 Alert rules (VMRule CRDs)

New file: `helm/umbrella/charts/observability/templates/vmrules/iam-outbox.yaml`:

```yaml
apiVersion: operator.victoriametrics.com/v1beta1
kind: VMRule
metadata:
  name: "iam-outbox-alerts"
  namespace: {{ .Values.observability.namespace | quote }}
spec:
  groups:
    - name: kacho-iam-outbox
      rules:
        - alert: KachoIAMFGAOutboxBacklogHigh
          expr: kacho_iam_fga_outbox_pending_total > 100
          for: 5m
          labels:
            severity: P3
            service: kacho-iam
            calibration: needed
          annotations:
            summary: "FGA outbox backlog > 100 pending for 5m"
            description: "fga_outbox drainer may be slow or paused. Pending tuples won't reach OpenFGA → grant→allow won't work for new bindings. Check drainer pod logs."
            runbook_url: "https://github.com/PRO-Robotech/kacho-deploy/blob/main/docs/runbooks/iam/fga-outbox-backlog.md"

        - alert: KachoIAMFGAOutboxBacklogCritical
          expr: kacho_iam_fga_outbox_pending_total > 1000
          for: 5m
          labels:
            severity: P1
            service: kacho-iam
          annotations:
            summary: "FGA outbox backlog > 1000 pending for 5m — drainer stuck"
            description: "Drainer appears stuck. Critical: bindings created within last 5m+ will NOT enforce authz (grant→allow broken)."
            runbook_url: "https://github.com/PRO-Robotech/kacho-deploy/blob/main/docs/runbooks/iam/fga-outbox-backlog.md"

        - alert: KachoIAMFGADrainerStalled
          expr: rate(kacho_iam_fga_outbox_drainer_iterations_total[5m]) == 0
          for: 5m
          labels:
            severity: P1
            service: kacho-iam
          annotations:
            summary: "FGA drainer no iterations for 5m"
            description: "Drainer goroutine appears stopped. Check pod readiness, LISTEN/NOTIFY connection health."
            runbook_url: "https://github.com/PRO-Robotech/kacho-deploy/blob/main/docs/runbooks/iam/fga-drainer-stalled.md"

        - alert: KachoIAMSubjectChangeBacklogHigh
          expr: kacho_iam_subject_change_outbox_pending_total > 50
          for: 5m
          labels:
            severity: P3
            service: kacho-iam
          annotations:
            summary: "subject_change_outbox backlog > 50 for 5m"
            description: "Cache invalidation events queued. On-revoke authz cache TTL may extend (stale allow on revoke). Check cache invalidation pipeline."
            runbook_url: "https://github.com/PRO-Robotech/kacho-deploy/blob/main/docs/runbooks/iam/cache-invalidation-backlog.md"

        - alert: KachoIAMCacheInvalidationLagHigh
          expr: kacho_iam_subject_change_outbox_lag_seconds > 30
          for: 5m
          labels:
            severity: P2
            service: kacho-iam
          annotations:
            summary: "Cache invalidation lag > 30s for 5m"
            description: "Revoke→cache-invalidate path slow. Stale ALLOWs may persist 30s+ after revoke."
            runbook_url: "https://github.com/PRO-Robotech/kacho-deploy/blob/main/docs/runbooks/iam/cache-invalidation-lag.md"
```

Additional VMRule files (per-domain split):

- `iam-anti-anon.yaml` — alerts `KachoIAMAntiAnonHitSpike` (rate > baseline+3σ) + `KachoIAMAntiAnonAttackSuspected` (rate > 100/min for 5m from single src_ip if label available).
- `iam-rpc-errors.yaml` — alerts `KachoIAMRPCErrorRateHigh` (>5% per-RPC for 5m → warn), `KachoIAMRPCErrorRateCritical` (>20% per-RPC for 5m → page).
- `iam-jit-sakeys.yaml` — alerts `KachoIAMJITPendingQueueDeep` (depth > 50 for 10m → warn — approver bottleneck), `KachoIAMSAKeyIssueRateAbnormal` (rate > baseline+3σ → warn — potential abuse).
- `iam-audit.yaml` — alerts `KachoIAMAuditEmitFailed` (any failure > 0 in 5m → page — compliance loss risk).

Per-alert annotations:
- `summary` — one-line human-readable
- `description` — context + symptom + impact
- `runbook_url` — link to physical runbook (file may not yet exist; tracked separately per §0.1)
- `calibration: needed` label on initial-deploy alerts where threshold is placeholder

Initial-deploy alerts with `calibration: needed` label are auto-filtered from PagerDuty severity:critical routing for first 7 days (AlertManager inhibition rule — separate config).

### 5.3 Saved LogsQL queries (`iam-logs-queries.yaml`)

```yaml
# helm/umbrella/charts/observability/files/iam-logs-queries.yaml
#
# Loaded as ConfigMap into observability namespace; consumable by:
# - VictoriaLogs UI (manual paste)
# - vlogs-cli (`vlogs query -f /path/to/iam-logs-queries.yaml -q <name>`)
# - Grafana «Loki» datasource ad-hoc (copy-paste)
#
# All queries scoped to kacho-iam by base stream selector.

apiVersion: v1
kind: ConfigMap
metadata:
  name: iam-logs-queries
  namespace: {{ .Values.observability.namespace | quote }}
data:
  queries.yaml: |
    queries:
      - name: per-tenant-audit-trail
        description: "All audit events for a specific tenant in last N hours"
        params:
          - { name: tenant_id, type: string, required: true }
          - { name: hours, type: int, default: 24 }
        logsql: |
          _stream:{kacho_service="kacho-iam", kacho_audit="true"}
          AND kacho.tenant.id:"{tenant_id}"
          AND _time:>now-{hours}h
          | sort by (_time desc)
          | limit 1000

      - name: breakglass-approve-events
        description: "BreakGlass approve events in last N hours (compliance review)"
        params:
          - { name: hours, type: int, default: 168 }   # 7d default
        logsql: |
          _stream:{kacho_service="kacho-iam", kacho_audit="true"}
          AND kacho.action:"BreakGlass.ApproveB"
          AND _time:>now-{hours}h
          | sort by (_time desc)

      - name: mass-sa-key-issue-detect
        description: "Principals issuing >10 SA keys in last hour (potential abuse)"
        params:
          - { name: threshold, type: int, default: 10 }
        logsql: |
          _stream:{kacho_service="kacho-iam", kacho_audit="true"}
          AND kacho.action:"SAKey.Issue"
          AND _time:>now-1h
          | stats count() by (kacho.principal.id)
          | filter count > {threshold}
          | sort by (count desc)

      - name: repeated-permission-denied
        description: "Principals with >N PermissionDenied in last hour (probing or misconfigured)"
        params:
          - { name: threshold, type: int, default: 20 }
        logsql: |
          _stream:{kacho_service="kacho-iam"}
          AND kacho.grpc.code:"PermissionDenied"
          AND _time:>now-1h
          | stats count() by (kacho.principal.id, kacho.rpc.method)
          | filter count > {threshold}
          | sort by (count desc)

      - name: gdpr-erasure-verification
        description: "GDPR erasure events for a user (audit trail for verification)"
        params:
          - { name: user_id, type: string, required: true }
        logsql: |
          _stream:{kacho_service="kacho-iam", kacho_audit="true"}
          AND kacho.action:~"GdprErasure.*"
          AND kacho.target.user_id:"{user_id}"
          | sort by (_time asc)

      - name: anti-anon-deny-by-rpc
        description: "Anti-anon denies grouped by RPC in last hour (top abusers)"
        params: []
        logsql: |
          _stream:{kacho_service="kacho-iam"}
          AND kacho.event:"anti_anon_denied"
          AND _time:>now-1h
          | stats count() by (kacho.rpc.method, kacho.src.ip)
          | sort by (count desc)
          | limit 100

      - name: jit-approval-latency
        description: "JIT approval latency derived from audit (request → approve span)"
        params:
          - { name: hours, type: int, default: 24 }
        logsql: |
          _stream:{kacho_service="kacho-iam", kacho_audit="true"}
          AND kacho.action:~"JitPending\\.(Request|Approve)"
          AND _time:>now-{hours}h
          | sort by (_time asc)
          # Pairing logic: client-side aggregation by kacho.jit.id
```

### 5.4 Trace sampling policy (`iam-trace-sampling.yaml`)

Otel-collector config snippet (appended to existing otel-collector-config):

```yaml
# helm/umbrella/charts/observability/files/iam-trace-sampling.yaml
#
# Sampling policy for kacho-iam traces. Loaded into otel-collector config as
# `tail_sampling` processor section (despite name, supports both head decision
# via rate and error-promote).

processors:
  tail_sampling/iam:
    decision_wait: 10s
    num_traces: 50000
    expected_new_traces_per_sec: 1000
    policies:
      # 100% for any trace with at least one error span.
      - name: errors-policy
        type: status_code
        status_code:
          status_codes: [ERROR]

      # 100% for slow traces (root span duration > 1s).
      - name: slow-traces
        type: latency
        latency:
          threshold_ms: 1000

      # 100% for cluster-admin / break-glass action traces (force-trace via attribute).
      - name: privileged-action
        type: string_attribute
        string_attribute:
          key: kacho.action.privileged
          values: ["true"]

      # Baseline: probabilistic 10% sampling for all kacho-iam spans.
      - name: probabilistic-baseline
        type: probabilistic
        probabilistic:
          sampling_percentage: 10
          attribute_source: trace_id
```

Per-environment override:
- `values.yaml` (dev): `sampling.kachoIam.baseline = 100` (100% sample on dev for full visibility).
- `values.prod.yaml`: `sampling.kachoIam.baseline = 10` (10% prod default; per OQ-W3.2-4).

### 5.5 kacho-iam emit-side additions (if not yet emitted by W1/W2)

Verify in W1.1/W1.2/W1.3/W2.B.9 codepath, что counters emit'ятся. Если missing — small PR в kacho-iam:

```go
// internal/observability/metrics.go (new or extended)
var (
    AuditEmitFailedTotal = corelib_observability.RegisterCounter(
        "kacho_iam_audit_emit_failed_total",
        "Number of audit events that failed to emit to sink",
        nil,
    )
    JitPendingQueueDepth = corelib_observability.RegisterGauge(
        "kacho_iam_jit_pending_queue_depth",
        "Current number of jit_pending rows in PENDING_APPROVAL state",
        nil,
    )
    SAKeyIssuedTotal = corelib_observability.RegisterCounter(
        "kacho_iam_sa_key_issued_total",
        "Number of SA keys issued",
        []string{"kind"},   // "client_credentials" | "static_token"
    )
)
```

Gauge `JitPendingQueueDepth` sampled by background goroutine every 30s:
```go
func (s *JitPendingService) StartMetricsLoop(ctx context.Context) {
    ticker := time.NewTicker(30 * time.Second)
    defer ticker.Stop()
    for {
        select {
        case <-ctx.Done(): return
        case <-ticker.C:
            count, err := s.pending.CountByState(ctx, "PENDING_APPROVAL")
            if err == nil { JitPendingQueueDepth.Set(float64(count)) }
        }
    }
}
```

Verify trace span attributes (in `corelib/observability/tracing.go` and iam handler instrumentation):
- `kacho.principal.type` (user / service_account / anonymous / system)
- `kacho.principal.id` (PrincipalUserID; for system → "bootstrap")
- `kacho.tenant.id` (project_id or account_id, resolved from request scope)
- `kacho.rpc.method` (`/kacho.cloud.iam.v1.UserService/Get`)
- `kacho.grpc.code` (set on span finish)
- `kacho.action.privileged` ("true" for BreakGlass.*, GdprErasure.*)

---

## 6. Сценарии (Given-When-Then) — основа интеграционных тестов

> Scenarios reflect post-deploy verification: kind cluster + helm umbrella with `observability.enabled=true` + kacho-iam deployed + synthetic load tooling (k6 / ghz / curl scripts).

### 6.1 Positive — happy path

#### Сценарий W3.2-DASH-01 — dashboards load with live traffic, all panels populated

**ID**: W3.2-DASH-01

**Given** kind cluster with umbrella chart deployed (`make dev-up`) включая observability stack
**And** kacho-iam serving traffic, k6 driving 100 RPS mixed iam workload for 10 minutes
**And** Grafana UI accessible at `grafana.<domain>` with OIDC admin login

**When** open dashboards: `iam-overview`, `iam-anti-anon`, `iam-outbox-drainer`, `iam-jit-sakeys`, `iam-audit-pipeline`, `iam-authz-fga`

**Then** all 6 dashboards load without errors (no «datasource not found», no «query parse error»)
**And** at least 80% of panels show non-empty data (some panels — e.g. fga_outbox_pending — may correctly show 0 if no backlog)
**And** no panel shows red error indicator

---

#### Сценарий W3.2-DASH-02 — per-RPC RED panels populated from live traffic

**ID**: W3.2-DASH-02

**Given** k6 generates traffic to specific iam RPCs (`UserService.Get`, `AccessBindingService.Create`, `ProjectService.List`)

**When** open `iam-overview` dashboard → «Top 10 RPCs by RPS» panel

**Then** the 3 driven RPCs appear with expected approximate RPS values (within ±20% of k6 send rate)
**And** «Top 10 RPCs by p95 latency» panel shows non-zero values for those RPCs

---

#### Сценарий W3.2-ALERT-01 — alert fires when fga_outbox backlog crosses threshold

**ID**: W3.2-ALERT-01

**Given** kacho-iam deployed; fga_outbox drainer running normally
**And** synthetic-trigger: manually scale fga_outbox drainer deployment to 0 replicas (`kubectl scale deploy kacho-iam-fga-drainer --replicas=0`)
**And** generate 150+ AccessBinding.Create operations to fill fga_outbox > 100

**When** wait 6 minutes (for `for: 5m` threshold to elapse)

**Then** AlertManager `/api/v2/alerts` returns active alert `KachoIAMFGAOutboxBacklogHigh` with `state=firing`
**And** alert labels include `severity=P3`, `service=kacho-iam`, `calibration=needed`
**And** alert annotations include `runbook_url`

**Cleanup**: scale drainer back to 1 replica; verify alert resolves within 5min.

---

#### Сценарий W3.2-ALERT-02 — drainer-stalled alert fires when drainer rate=0

**ID**: W3.2-ALERT-02

**Given** drainer pod alive but no work to do (idle state)
**And** synthetic-trigger: pause drainer via `kubectl exec -- kill -STOP 1` on drainer goroutine OR drop LISTEN/NOTIFY connection

**When** wait 6 minutes

**Then** alert `KachoIAMFGADrainerStalled` fires (rate = 0 for 5m)
**And** severity = P1

---

#### Сценарий W3.2-ALERT-03 — anti-anon hit spike alert fires on synthetic flood

**ID**: W3.2-ALERT-03

**Given** stable baseline of anti-anon hits (k6 baseline: ~0.5/min legitimate misconfigured calls)
**And** synthetic-trigger: anonymous load (curl loop calling `POST /iam/v1/users` with no auth header) at 20 RPS for 5 minutes

**When** wait 6 minutes

**Then** alert `KachoIAMAntiAnonHitSpike` fires (rate spike > baseline+3σ)
**And** Grafana `iam-anti-anon` dashboard «Top 10 RPC by anti-anon denies» panel shows `/iam/v1/users:create` at top

---

#### Сценарий W3.2-LOGSQL-01 — saved query returns BreakGlass approve events

**ID**: W3.2-LOGSQL-01

**Given** vector.dev sink → VictoriaLogs pipeline operational (W2.B.9 merged)
**And** synthetic-trigger: execute BreakGlass.Request → BreakGlass.ApproveA → BreakGlass.ApproveB sequence on test fixtures
**And** audit events emitted to VictoriaLogs

**When** load `iam-logs-queries.yaml`, execute `breakglass-approve-events` query with `hours=1`

**Then** query returns at least 1 event matching `kacho.action="BreakGlass.ApproveB"`
**And** event includes `kacho.principal.id` (approver), `kacho.target.request_id`, `_time` within last hour

---

#### Сценарий W3.2-LOGSQL-02 — per-tenant audit trail isolation

**ID**: W3.2-LOGSQL-02

**Given** two tenants T1 and T2 each issuing API calls; audit events emitted for both

**When** load query `per-tenant-audit-trail` with `tenant_id=T1`

**Then** returned events ALL have `kacho.tenant.id=T1`
**And** ZERO events have `kacho.tenant.id=T2`
**And** total count ≥ 10 events for T1

---

#### Сценарий W3.2-TRACE-01 — trace sampling: error trace 100% sampled

**ID**: W3.2-TRACE-01

**Given** kacho-iam deployed with `sampling.kachoIam.baseline=10`, error-policy=100%
**And** synthetic-trigger: generate 100 requests, of which 10 fail with InvalidArgument (e.g. malformed body)

**When** wait 30s for spans to flush to VictoriaTraces
**And** query VictoriaTraces `/api/traces?service=kacho-iam&tags=grpc.status_code=3&limit=50`

**Then** at least 9 of 10 error traces are present (allowing 10% loss for ingestion race; expected 100% but with finite buffer)
**And** success traces in same time window — approximately 10% sampling rate (10/100 = 10 ± 5 traces visible)

---

#### Сценарий W3.2-TRACE-02 — service dependency map shows expected edges

**ID**: W3.2-TRACE-02

**Given** kacho-iam deployed; running for 10min; traffic generating cross-service calls (kacho-iam → openfga, kacho-iam → postgres, kacho-iam → kratos если enabled)

**When** query VictoriaTraces `/api/dependencies?endTs=<now-ms>&lookback=600000`

**Then** dependencies list includes edges:
  - `kacho-api-gateway → kacho-iam` (callCount > 0)
  - `kacho-iam → postgres-kacho-iam` (callCount > 0)
  - `kacho-iam → openfga` (callCount > 0)
**And** NO edge `kacho-iam → kacho-vpc` (must not exist)
**And** NO edge `kacho-iam → kacho-compute` (must not exist)

---

### 6.2 Negative — graceful failure modes

#### Сценарий W3.2-NEG-01 — panel shows «no data» gracefully on metric not yet emitted

**ID**: W3.2-NEG-01

**Given** fresh deploy, no traffic yet
**And** `kacho_iam_jit_pending_queue_depth` not yet emitted (metric exists in code but no sample taken)

**When** open `iam-jit-sakeys` dashboard → «JIT pending queue depth» panel

**Then** panel renders without error
**And** shows «No data» state (not an error / red indicator)
**And** dashboard load completes (other panels not affected)

---

#### Сценарий W3.2-NEG-02 — alert silenced when underlying metric flatlines (no false-positive)

**ID**: W3.2-NEG-02

**Given** kacho-iam pod scaled to 0 replicas (e.g. for maintenance)
**And** no metric `kacho_iam_fga_outbox_pending_total` is emitted for 10 minutes

**When** wait 15 minutes

**Then** alert `KachoIAMFGAOutboxBacklogHigh` does NOT fire (metric absent ≠ metric > 100)
**And** instead, separate `KachoIAMScrapeAbsent` alert fires (existing) if scrape-absent rule covers iam (это другой alert, не false-positive backlog)

---

#### Сценарий W3.2-NEG-03 — datasource unavailable: dashboard gracefully degrades

**ID**: W3.2-NEG-03

**Given** VictoriaMetrics datasource temporarily unavailable (e.g. vmselect pod restart)

**When** user opens `iam-overview` dashboard during downtime

**Then** dashboard shows clear error per panel («Data source unavailable») — not corrupted UI
**And** when datasource recovers, panels auto-refresh с next interval (30s default) and populate

---

#### Сценарий W3.2-NEG-04 — LogsQL query returns 0 events when filter matches nothing

**ID**: W3.2-NEG-04

**Given** VictoriaLogs operational, no events match filter

**When** run `mass-sa-key-issue-detect` with `threshold=1000` (unrealistically high)

**Then** query returns 0 rows
**And** returns successfully (not error)

---

### 6.3 Edge cases

#### Сценарий W3.2-EDGE-01 — trace sampling under high load saturation guard

**ID**: W3.2-EDGE-01

**Given** kacho-iam under 1000 RPS load
**And** sampling `baseline=10` → expected ~100 traces/s sent to VT

**When** wait 5min, check VictoriaTraces ingest rate via VT metrics

**Then** ingest rate is approximately 100 traces/s (within 80-120 range)
**And** otel-collector does NOT drop trace data due to overflow (check otel-collector logs / metrics for `dropped_spans` = 0)
**And** error traces still 100% captured (`kacho.grpc.code=Internal` etc.)

---

#### Сценарий W3.2-EDGE-02 — privileged action force-trace 100%

**ID**: W3.2-EDGE-02

**Given** kacho-iam baseline 10% sampling
**And** BreakGlass.ApproveB called 5 times with `kacho.action.privileged=true` span attribute

**When** query VT for those 5 traces

**Then** all 5 traces present (100% sampling override applied)
**And** baseline non-privileged traces still ~10% rate

---

#### Сценарий W3.2-EDGE-03 — alert calibration label inhibits PagerDuty for first 7 days

**ID**: W3.2-EDGE-03

**Given** new deploy, all alerts with `calibration: needed` label fire continuously due to placeholder thresholds
**And** AlertManager inhibition rule: `calibration=needed` AND `_age < 7d` → suppress PagerDuty routing (allow Slack только)

**When** alert `KachoIAMFGAOutboxBacklogHigh` (with `calibration: needed`) fires on day 1

**Then** Slack notification sent to `#kacho-iam-alerts`
**And** PagerDuty incident NOT created
**And** after 7 days, inhibition lapses → PagerDuty incident created on subsequent fire

---

#### Сценарий W3.2-EDGE-04 — dashboard datasource template variable resolves to active backend

**ID**: W3.2-EDGE-04

**Given** dashboard JSON uses `${DS_PROMETHEUS}` placeholder
**And** Grafana has both «Mimir» (legacy) and «VictoriaMetrics» (new) Prometheus-type datasources
**And** Grafana default Prometheus datasource = «VictoriaMetrics»

**When** load `iam-overview` dashboard

**Then** all panels query VictoriaMetrics (default resolution)
**And** user can manually switch to «Mimir» via dashboard datasource selector if needed

---

### 6.4 Tenant-scope isolation (Запрет #6)

#### Сценарий W3.2-ISO-01 — non-cluster-admin OIDC user cannot access admin dashboards folder

**ID**: W3.2-ISO-01

**Given** Grafana folder «Kacho Cloud / IAM (admin)» — permission: OIDC group `kacho-cloud-admins` only
**And** test user with OIDC claim `groups=["kacho-tenant-user"]` (NOT admin)

**When** test user logs into Grafana → tries to access `iam-overview` dashboard URL directly

**Then** Grafana returns 403 / «Access denied» page
**And** dashboard NOT visible in folder listing

---

#### Сценарий W3.2-ISO-02 — direct VictoriaLogs API not exposed to tenant principals

**ID**: W3.2-ISO-02

**Given** VictoriaLogs deployed on cluster-internal service (no Ingress)
**And** tenant principal has no kubectl access / cluster-network access

**When** tenant principal attempts to query VL via `https://vlogs.<domain>/select/logsql/query`

**Then** request fails: connection refused / DNS not resolved / 401 unauthorized (depending on network setup)
**And** tenant's only path to their audit events is via kacho-iam APIs (separate scope; W3.2 не реализует)

---

### 6.5 Service-dependency map verification (test-first against W1-W2 architecture)

#### Сценарий W3.2-DEP-01 — expected dependency graph matches W1-W2-finalised architecture

**ID**: W3.2-DEP-01

**Given** kacho-iam fully deployed post-W1+W2 merge; load running 10min

**When** query `/api/dependencies` from VictoriaTraces

**Then** dependency graph matches expected (verified per OQ-W3.2-10):
  - **Expected incoming**: `kacho-api-gateway → kacho-iam`
  - **Expected outgoing**: `kacho-iam → postgres-kacho-iam`, `kacho-iam → openfga`, `kacho-iam → kratos` (if federation), `kacho-iam → hydra` (if OAuth), `kacho-iam → vector-aggregator` (audit)
  - **Forbidden**: `kacho-iam → kacho-vpc`, `kacho-iam → kacho-compute` (regression-detector — if these appear, architecture has unexpected edge)

If forbidden edges appear → test fails; investigate.

---

## 7. Test plan

### 7.1 Integration tests (synthetic-trigger E2E)

Location: `kacho-deploy/e2e/observability-alerts-test.sh` (bash + kubectl + curl).

| Test | Trigger | Verification | Time budget |
|---|---|---|---|
| `test_fga_outbox_alert.sh` | `kubectl scale deploy kacho-iam-fga-drainer --replicas=0` + generate 150 AB.Create | Poll AlertManager `/api/v2/alerts` for `KachoIAMFGAOutboxBacklogHigh` state=firing within 7min | 10min |
| `test_drainer_stalled_alert.sh` | Drainer alive but no LISTEN/NOTIFY (kill `pg_listen` connection) | Poll for `KachoIAMFGADrainerStalled` | 10min |
| `test_anti_anon_spike_alert.sh` | curl loop anonymous POST /iam/v1/users at 20 RPS for 5min | Poll for `KachoIAMAntiAnonHitSpike` | 10min |
| `test_audit_emit_failure_alert.sh` | Stop vector-aggregator pod (block sink) | Poll for `KachoIAMAuditEmitFailed` (page-severity) | 10min |
| `test_logsql_query_breakglass.sh` | Execute BG.Request → ApproveA → ApproveB; wait 30s for VL ingestion | Run saved query `breakglass-approve-events`; assert count ≥ 1 | 5min |
| `test_trace_sampling_error_promote.sh` | Generate 100 reqs, 10 error; wait 30s for VT ingestion | Query VT for error traces; assert ≥ 9 of 10 present | 5min |
| `test_service_dependency_map.sh` | Drive normal traffic for 10min; query VT `/api/dependencies` | Assert expected edges present, forbidden edges absent | 12min |
| `test_dashboard_loads.sh` | Open each new dashboard via Grafana API `/api/dashboards/uid/<uid>`; assert HTTP 200 + valid JSON | All 6 dashboards | 2min |
| `test_dashboard_panels_populated.sh` | After 10min traffic, query each panel's expr via Grafana datasource API; assert ≥80% return non-empty data | All 6 dashboards | 15min |

Total budget: ~80min E2E run. Triggered on PR merge to main (separate CI matrix); not on every PR (too slow).

### 7.2 Unit tests

- **Dashboard JSON validation**: `tools/dashboard-lint.py` — parse all JSON, verify schema_version, all panels have valid `datasource` reference, no broken syntax. CI on every PR.
- **VMRule YAML validation**: `helm lint` + `vmrule-lint` (if available) — verify PromQL syntax (parse via `promtool check rules` even if VMRule CRD — query language is compat). CI on every PR.
- **LogsQL queries validation**: `tools/logsql-lint.py` — parse YAML, send each query (with mock params) to test-VL endpoint with `?dry_run=true`, expect 200. CI on every PR.
- **Sampling config validation**: otel-collector `--dry-run` против `iam-trace-sampling.yaml` snippet merged with full collector config. CI on every PR.

### 7.3 Newman E2E

**None.** Observability — non-functional concern, не RPC-driven. Functional newman suites (existing) continue to test functional API behaviour; они **косвенно** drive observability traffic, но specific observability assertions — через §7.1 integration tests, не newman.

### 7.4 Manual smoke / acceptance review

- Screenshot каждого нового dashboard (6 total) → attach to PR description.
- AlertManager UI screenshot showing all new alerts in inhibit-state (clean baseline, no false-positives).
- VT service-dependency map screenshot showing expected edges.

### 7.5 Test-first discipline (Запрет #12)

**RED → GREEN ordering**:

1. **RED phase**: write all §7.1 integration tests; commit; run on dev-kind WITHOUT W3.2 changes deployed. **Expected: all tests fail** (alerts don't fire because rules don't exist; dashboards 404; LogsQL queries return errors). Capture RED output evidence.
2. **GREEN phase**: deliver §5.1–5.5 artifacts; redeploy chart; rerun §7.1 tests. **Expected: all GREEN.** Capture GREEN output evidence.
3. PR description shows RED→GREEN pair per test.

**Test-only PR restriction (Запрет #13)**: W3.2 is NOT test-only (it delivers production artifacts: dashboards, rules, configs). However, sub-component «dashboard JSON validation» and similar tooling tests, if added to kacho-deploy without product changes, follow the test-only rules (no TODO, no skip, document RED findings as Issues).

---

## 8. Definition of Done

### 8.1 Per-deliverable DoD

- [ ] **Dashboards**: 3 new JSON files + 3 extended; all загружаются в Grafana без ошибок; uid'ы registered in `observability.grafana.dashboards`; folder permission set (OIDC group `kacho-cloud-admins`).
- [ ] **VMRule files**: 4 new VMRule (или PrometheusRule fallback) — `iam-outbox.yaml`, `iam-anti-anon.yaml`, `iam-rpc-errors.yaml`, `iam-jit-sakeys.yaml`, `iam-audit.yaml`; helm lint clean; vmoperator принимает CRDs.
- [ ] **LogsQL queries**: `iam-logs-queries.yaml` ConfigMap; 7 queries; each parses against VL (smoke: dry-run против test-VL endpoint).
- [ ] **Trace sampling**: `iam-trace-sampling.yaml` snippet integrated into otel-collector config; values.yaml flag `observability.otelCollector.sampling.kachoIam.baseline` (default 10 prod, 100 dev).
- [ ] **kacho-iam emit additions (if needed)**: 3 new counters registered; smoke на dev shows non-zero values after traffic.
- [ ] **Span attributes**: `kacho.principal.type`, `kacho.principal.id`, `kacho.tenant.id`, `kacho.rpc.method`, `kacho.action.privileged` populated on all iam spans (verify via VT trace inspect).
- [ ] **Service dependency map**: matches OQ-W3.2-10 expected list; no forbidden edges.

### 8.2 Test DoD

- [ ] §7.1 integration tests — RED captured pre-impl, GREEN captured post-impl; evidence in PR description.
- [ ] §7.2 unit tests (lint, validate) — all GREEN in CI.
- [ ] §7.4 screenshots attached to PR.

### 8.3 Global DoD

- [ ] `acceptance-reviewer` ✅ APPROVED данного doc; all OQs resolved.
- [ ] Branch `KAC-W3.2` создан в `kacho-deploy` (+ `kacho-iam` if emit additions).
- [ ] All §5 artifacts merged on `main`.
- [ ] CI зелёный (helm-lint, dashboard-lint, vmrule-lint, logsql-lint, sampling-config-lint, integration-tests).
- [ ] `make dev-up` на kind разворачивает stack; smoke verifies dashboards + alerts work.
- [ ] PR merged.
- [ ] Vault updated:
  - [ ] `obsidian/kacho/observability/iam-dashboards.md` — NEW (list of dashboards + uid + tags + key panels)
  - [ ] `obsidian/kacho/observability/iam-alerts.md` — NEW (list of alerts + thresholds + severity routing + runbook URLs)
  - [ ] `obsidian/kacho/observability/iam-logsql-saved.md` — NEW (list of saved queries + params + use cases)
  - [ ] `obsidian/kacho/observability/iam-trace-sampling.md` — NEW (sampling policy + per-env config + privileged-action force-trace)
  - [ ] `obsidian/kacho/architecture.md` — UPDATE «Observability layer» section with VictoriaMetrics/Logs/Traces stack note + kacho-iam-specific signals reference
  - [ ] `obsidian/kacho/KAC/KAC-W3.2.md` — trail (PRs, screenshots, acceptance checklist)
- [ ] YouTrack KAC-W3.2:
  - [ ] In Progress on impl start
  - [ ] PR links commented
  - [ ] Done on merge + smoke + dashboard screenshots attached
- [ ] W3 tracker `2026-05-23-iam-prod-ready-wave3.md` updated: W3.2 row → ✅ done + date.
- [ ] W3 closure signal toward freeze (W3.4): «observability customisation complete»; remaining freeze items — separate.

---

## 9. Out of scope (явно — на следующие waves / эпики)

| Что | Куда |
|---|---|
| Observability customisation для kacho-vpc | Отдельный эпик (post-W3 vpc-prod-ready) |
| Observability customisation для kacho-compute | Отдельный эпик (post-W3 compute-prod-ready) |
| Observability customisation для kacho-loadbalancer / NLB | Sub-phase 4.x (kacho-nlb domain) |
| Formal SLO definition (multi-burn-rate, error budget) | Separate work-item after W3.2 (sloth-driven, already deployed) |
| Pager rotation / on-call schedule | Process work (not infra); separate runbook |
| Tenant-facing observability dashboards | kacho-ui customer-facing project |
| Runbook MD files (target of `runbook_url`) | W3.4 freeze checklist + separate writing work |
| Custom Grafana plugins / exotic visualisations | Not required |
| Migration of existing Mimir/Loki/Tempo dashboards to VictoriaMetrics-native syntax | W3.3 deploy switch (if executed) |
| SPIRE+Cilium wiring | W3.3 (separate epic row) |
| Freeze checklist | W3.4 |
| Product-completion-freeze details | Master plan §M5+ |

---

## 10. Traceability — signal ↔ dashboard ↔ alert ↔ logsql ↔ trace

| Signal (Wave emit) | Dashboard panel | Alert | LogsQL | Trace attribute |
|---|---|---|---|---|
| `kacho_iam_fga_outbox_pending_total` (W1.1) | `iam-outbox-drainer` § FGA backlog | `KachoIAMFGAOutboxBacklogHigh` (P3), `Critical` (P1) | — | — |
| `kacho_iam_fga_outbox_drainer_iterations_total` (W1.1) | `iam-outbox-drainer` § iteration rate | `KachoIAMFGADrainerStalled` (P1) | — | — |
| `kacho_iam_fga_outbox_drain_latency_seconds` (W1.1) | `iam-outbox-drainer` § p50/p95/p99 | — | — | — |
| `kacho_iam_subject_change_outbox_pending_total` (W1.2) | `iam-outbox-drainer` § subject-change backlog | `KachoIAMSubjectChangeBacklogHigh` (P3) | — | — |
| `kacho_iam_subject_change_outbox_lag_seconds` (W1.2) | `iam-outbox-drainer` § lag | `KachoIAMCacheInvalidationLagHigh` (P2) | — | — |
| `kacho_api_gateway_anti_anon_denied_total` (W1.3 gateway) | `iam-anti-anon` § per-RPC denies | `KachoIAMAntiAnonHitSpike` (P3) | `anti-anon-deny-by-rpc` | `kacho.event=anti_anon_denied` |
| `kacho_iam_anti_anon_denied_total` (W1.6 #43 interceptor) | `iam-anti-anon` § iam-side denies | (same alert aggregates both) | `anti-anon-deny-by-rpc` | — |
| `kacho_iam_jit_pending_queue_depth` (W2.B) | `iam-jit-sakeys` § queue depth | `KachoIAMJITPendingQueueDeep` (P3) | `jit-approval-latency` | `kacho.action=JitPending.*` |
| `kacho_iam_sa_key_issued_total` (W2.B) | `iam-jit-sakeys` § issue rate | `KachoIAMSAKeyIssueRateAbnormal` (P3) | `mass-sa-key-issue-detect` | `kacho.action=SAKey.Issue` |
| `kacho_iam_audit_events_emitted_total` (W2.B.9) | `iam-audit-pipeline` § events/min | — | — | — |
| `kacho_iam_audit_emit_failed_total` (W2.B.9) | `iam-audit-pipeline` § failure rate | `KachoIAMAuditEmitFailed` (P1) | — | — |
| `kacho_rpc_requests_total` (corelib) | `iam-overview` § top-10 RPC RPS | `KachoIAMRPCErrorRateHigh` (P3), `Critical` (P1) | `repeated-permission-denied` | `kacho.rpc.method`, `kacho.grpc.code` |
| `kacho_rpc_request_duration_seconds_bucket` (corelib) | `iam-overview` § p95/p99 latency | — | — | — |
| (traces — corelib otel) | — | — | — | `kacho.principal.type`, `kacho.tenant.id`, `kacho.action.privileged` |
| (audit logs — vector.dev → VL) | `iam-audit-pipeline` § last events | — | All 7 saved queries | — |
| (service-dependency map — VT) | — | — | — | All spans contribute |

---

## 11. Ссылки

- Workspace rules: `../../CLAUDE.md` (запреты #1, #6, #11, #12; vault discipline; «Инфра-чувствительные данные»)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md` (если есть; observability emit conventions)
- Source of scope: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` Waves §W3
- Source of stack decision: `../superpowers/plans/2026-05-21-production-launch-plan.md` §WS-6 + §6 (DECISION-AUDIT VictoriaLogs + vector.dev)
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md`
- Wave 3 plan: `../superpowers/plans/2026-05-23-iam-prod-ready-wave3.md` (TBD — будет написан при старте W3)
- Predecessor acceptance docs:
  - `sub-phase-W1.1-fga-outbox-drainer-acceptance.md` (fga_outbox emit)
  - `sub-phase-W1.2-subject-change-cache-invalidation-acceptance.md` (subject_change_outbox emit)
  - `sub-phase-W1.3-gateway-authz-failclosed-acceptance.md` (anti-anon counter emit)
  - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md` (iam-side anti-anon)
  - Wave 2.B audit-pipeline acceptance (TBD W2.B.9)
- Existing observability chart baseline:
  - `project/kacho-deploy/helm/umbrella/charts/observability/values.yaml`
  - `project/kacho-deploy/helm/umbrella/charts/observability/templates/prometheus-rules/iam-availability.yaml` (existing — coexist)
  - `project/kacho-deploy/helm/umbrella/charts/observability/files/dashboards/iam-*.json` (existing 7 — extend 3, untouched 4)
- Reference for VMRule CRD shape: VictoriaMetrics operator docs (https://docs.victoriametrics.com/operator/) — outside the repo
- Reference for LogsQL syntax: VictoriaLogs docs (https://docs.victoriametrics.com/victorialogs/logsql/) — outside the repo
- Reference for VictoriaTraces Jaeger-API: VictoriaTraces docs (https://docs.victoriametrics.com/victoriatraces/) — outside the repo
- Vault entries to update / create (DoD §8.3):
  - `obsidian/kacho/observability/iam-dashboards.md` (NEW)
  - `obsidian/kacho/observability/iam-alerts.md` (NEW)
  - `obsidian/kacho/observability/iam-logsql-saved.md` (NEW)
  - `obsidian/kacho/observability/iam-trace-sampling.md` (NEW)
  - `obsidian/kacho/architecture.md` (UPDATE)
  - `obsidian/kacho/KAC/KAC-W3.2.md` (NEW trail)
