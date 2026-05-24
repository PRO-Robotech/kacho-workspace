# Test Plan — W3.2: Observability customisation (dashboards / alerts / LogsQL / traces)

> **Source**: [docs/specs/sub-phase-W3.2-observability-customisation-acceptance.md](sub-phase-W3.2-observability-customisation-acceptance.md) (APPROVED 2026-05-24)
> **Status**: PLAN (no code yet — code lives in deploy-side YAML PRs)
> **Branch (eventual impl)**: `KAC-XXX-w3-2-observability` (kacho-deploy + kacho-iam emit-side additions if needed)
> **Parent KAC**: KAC-170 (epic bundle)

## 1. Per-GWT mapping

W3.2 deliverables are mainly **declarative YAML** (Grafana dashboards, VMRule alerts, LogsQL saved
queries, trace-sampling policies). Tests here verify **behavior in a live observability stack**
(VictoriaMetrics + VictoriaLogs + VictoriaTraces + Grafana) — not Go code. So integration tests
follow «trigger synthetic event → observe expected signal in stack» pattern.

### 6.1 Positive — happy path

| GWT id | Scenario summary | Integration test | Newman case | Manual / e2e |
|---|---|---|---|---|
| W3.2-DASH-01 | All dashboards load + all panels populated under live traffic | `tests/observability/dash_load_integration_test.go::Test_Dashboards_AllLoad_AllPanelsPopulated` (uses Grafana API + queries each panel JSON) | — | Manual smoke during deploy: open Grafana, verify each panel |
| W3.2-DASH-02 | Per-RPC RED panels populated from live traffic (latency/error-rate/throughput) | `tests/observability/red_panels_integration_test.go::Test_RedPanels_PopulatedFromTraffic` (triggers synthetic newman load + curl VM `/api/v1/query_range`) | — | — |
| W3.2-ALERT-01 | fga_outbox backlog crosses threshold → alert fires | `tests/observability/alerts_integration_test.go::Test_Alert_FgaOutboxBacklog_Fires` (stops drainer for 60s; queries Alertmanager `/api/v2/alerts`) | — | — |
| W3.2-ALERT-02 | Drainer rate=0 → drainer-stalled alert fires | `tests/observability/alerts_integration_test.go::Test_Alert_DrainerStalled_Fires` | — | — |
| W3.2-ALERT-03 | Synthetic anon-flood → anti-anon hit spike alert fires | `tests/observability/alerts_integration_test.go::Test_Alert_AntiAnonSpike_Fires` (newman flood + Alertmanager poll) | — | — |
| W3.2-LOGSQL-01 | Saved query returns BreakGlass approve events | `tests/observability/logsql_integration_test.go::Test_LogsQL_BreakGlassApproveEvents_Returns` (triggers BG approve + curl VL `/select/logsql/query`) | — | — |
| W3.2-LOGSQL-02 | Per-tenant audit-trail isolation (tenant A query returns only A's events) | `tests/observability/logsql_integration_test.go::Test_LogsQL_PerTenantIsolation` | — | — |
| W3.2-TRACE-01 | Error trace 100% sampled (force-trace policy) | `tests/observability/trace_sampling_integration_test.go::Test_Trace_ErrorPath_AlwaysSampled` (curl VT `/api/traces?service=kacho-iam&minDuration=…`) | — | — |
| W3.2-TRACE-02 | Service-dependency map shows expected edges | `tests/observability/trace_dependency_integration_test.go::Test_Trace_ServiceDependencyMap_ExpectedEdges` (queries VT service-dependency endpoint) | — | — |

### 6.2 Negative — graceful failure modes

| GWT id | Scenario summary | Integration test | Newman case |
|---|---|---|---|
| W3.2-NEG-01 | Panel shows "no data" gracefully on metric not-yet-emitted | `tests/observability/dash_load_integration_test.go::Test_Panel_NoData_GracefulMessage` | — |
| W3.2-NEG-02 | Alert silenced when underlying metric flatlines (no false-positive) | `tests/observability/alerts_integration_test.go::Test_Alert_MetricFlatline_NoFalsePositive` | — |
| W3.2-NEG-03 | Datasource unavailable → dashboard gracefully degrades | `tests/observability/dash_load_integration_test.go::Test_Dashboard_DatasourceDown_Graceful` | — |
| W3.2-NEG-04 | LogsQL query returns 0 events when filter matches nothing | `tests/observability/logsql_integration_test.go::Test_LogsQL_EmptyResult_Returns0NotError` | — |

### 6.3 Edge cases

| GWT id | Scenario summary | Integration test | Newman case |
|---|---|---|---|
| W3.2-EDGE-01 | Trace sampling under high load → saturation guard kicks in | `tests/observability/trace_sampling_integration_test.go::Test_Trace_HighLoadSaturationGuard` (synthetic burst + assert trace-drop rate stays bounded) | — |
| W3.2-EDGE-02 | Privileged action (BG approve / cluster-admin gates) force-trace 100% | `tests/observability/trace_sampling_integration_test.go::Test_Trace_PrivilegedAction_ForceSampled` | — |
| W3.2-EDGE-03 | Alert calibration label inhibits PagerDuty for first 7 days | `tests/observability/alerts_integration_test.go::Test_Alert_CalibrationLabel_InhibitsPagerDuty` (verifies Alertmanager routing config respects label `calibration=true`) | — |
| W3.2-EDGE-04 | Dashboard datasource template variable resolves to active backend | `tests/observability/dash_load_integration_test.go::Test_Dashboard_TemplateVariable_ResolvesActiveBackend` | — |

### 6.4 Tenant-scope isolation (§Запрет #6)

| GWT id | Scenario summary | Integration test | Newman case |
|---|---|---|---|
| W3.2-ISO-01 | Non-cluster-admin OIDC user cannot access admin dashboards folder | `tests/observability/iso_integration_test.go::Test_Iso_NonClusterAdmin_NoAdminFolderAccess` (Grafana API auth + folder ACL check) | `iam-grafana-authz.py::GRAFANA-NON-ADMIN-FOLDER-DENY` |
| W3.2-ISO-02 | Direct VictoriaLogs API NOT exposed to tenant principals | `tests/observability/iso_integration_test.go::Test_Iso_VLAPI_NotExposedToTenants` (curl VL with tenant JWT → 401/404) | `iam-grafana-authz.py::VL-API-TENANT-DENY` |

### 6.5 Service-dependency map verification

| GWT id | Scenario summary | Integration test | Newman case |
|---|---|---|---|
| W3.2-DEP-01 | Expected dependency graph matches W1-W2-finalised architecture (no spurious edges, no missing edges) | `tests/observability/dep_graph_integration_test.go::Test_DepGraph_MatchesExpectedArchitecture` (queries VT service-dependency, compares against fixture `expected-deps.yaml`) | — |

## 2. Test infrastructure required

- **Helm umbrella**: kind cluster + helm umbrella with full Victoria stack (VictoriaMetrics / VictoriaLogs / VictoriaTraces / vmalert / Alertmanager / Grafana) + kacho-iam pod
- **Synthetic-trigger helpers**:
  - `tests/observability/triggers/newman_load.sh` — runs a small newman flood against api-gateway to populate metrics
  - `tests/observability/triggers/drainer_pause.sh` — kubectl exec into iam pod, sends SIGSTOP to drainer for N seconds, then SIGCONT
  - `tests/observability/triggers/anon_flood.sh` — sends N anonymous requests to anti-anon-gated endpoints
- **Backend API clients (Go)**:
  - `pkg/grafana_client/` — uses Grafana HTTP API for dashboard load + panel query
  - `pkg/vm_client/` — VM `/api/v1/query` + `/api/v1/query_range`
  - `pkg/vl_client/` — VictoriaLogs `/select/logsql/query`
  - `pkg/vt_client/` — VictoriaTraces Jaeger-compatible `/api/traces`
  - `pkg/alertmanager_client/` — `/api/v2/alerts` + `/api/v2/silences`
- **Fixtures**:
  - `tests/observability/fixtures/expected-deps.yaml` — canonical service-dependency edges from W1+W2 (e.g. `kacho-api-gateway → kacho-iam`, `kacho-iam → openfga`, no `kacho-vpc → kacho-iam` etc.)
  - `tests/observability/fixtures/dashboards/` — Grafana dashboard JSON exports for diff-baseline
- **CI requirement**: tests run on kind cluster with full helm umbrella; ≥10min runtime acceptable (this is acceptance-level, not unit-test cadence)

## 3. Coverage gates (DoD on impl-PR)

- **All §6 scenarios green** (W3.2-DASH-01..02, ALERT-01..03, LOGSQL-01..02, TRACE-01..02, NEG-01..04, EDGE-01..04, ISO-01..02, DEP-01)
- **Dashboard JSON valid** (`grafana-cli validate dashboard.json` on each)
- **VMRule CRD valid** (`promtool check rules <rule-file>` for syntax; `vmalert --rule.check` for VM-specific)
- **Trace sampling policy validated** (Otel trace-sampling DSL syntax check)
- **Saved LogsQL queries syntax-check** (curl VL with `&dry_run=1` if supported, else assert query returns valid response in fixture)
- **Tenant-isolation gates** (W3.2-ISO-01, ISO-02) must pass — these are security-critical
- **No alert false-positive rate > 1%** in 7-day calibration window (verified by EDGE-03 + manual review)

## 4. Test sequencing for TDD (RED-before-GREEN per workspace §12)

1. **RED phase**: write all §6 integration tests + fixtures first. CI shows:
   - DASH-01 red: dashboards not yet committed
   - ALERT-01 red: VMRule not yet defined
   - LOGSQL-01 red: saved query not in iam-logs-queries.yaml
   - TRACE-01 red: sampling policy missing
   - DEP-01 red: expected-deps.yaml may match if W1/W2 architecture is final
2. **GREEN phase per deliverable (per acceptance §5)**:
   - §5.1 Dashboards committed → DASH-01/02 + NEG-01/03 + EDGE-04 GREEN
   - §5.2 VMRule CRDs committed → ALERT-01..03 + NEG-02 + EDGE-03 GREEN
   - §5.3 Saved LogsQL queries → LOGSQL-01..02 + NEG-04 + ISO-02 GREEN
   - §5.4 Trace sampling policy → TRACE-01..02 + EDGE-01..02 GREEN
   - §5.5 kacho-iam emit-side additions (if metric gaps found) → backfills DASH-01/02 + ALERT-01..03 green by introducing missing metrics
3. **Manual smoke (per acceptance §7.4)**: each dashboard reviewed in Grafana UI; each alert manually tested via threshold-cross trigger
4. **RED→GREEN evidence per deliverable in PR description**

## 5. Out-of-scope tests (boundary, not omission)

- **Live PagerDuty integration** — out of W3.2; PagerDuty wired but routing inhibited by `calibration=true` label (EDGE-03)
- **kacho-vpc / kacho-compute dashboards** — separate per-domain epics; W3.2 is iam-only customisation
- **Log retention SLA** — separate VictoriaLogs tuning concern; W3.2 ensures queries work, not retention configured
- **Metric cardinality optimization** — separate epic (workspace skill `victoriametrics-cardinality-analysis`)
- **Trace storage backend tuning** — out of scope
- **Custom alert receivers (Slack/email)** — wired via Alertmanager config; routing config is W3.2, receiver specifics are deploy-config
- **Audit-log forensics queries beyond §5.3 enumerated** — implementer can add, but baseline DoD only enumerated 2 (W3.2-LOGSQL-01/02)
- **Performance/load test** — separate k6 epic

## 6. Coverage gaps observed in acceptance doc

- **Acceptance §5.5 («kacho-iam emit-side additions»)** is conditional («if not yet emitted by W1/W2»). At impl-start, implementer must audit current metric/log/span emits against §5.1-5.4 requirements; if missing, file a sub-task (extra emit work). **Recommended**: implementer creates `tests/observability/coverage_audit.go` that lists required metrics/logs/spans and asserts presence in registry — RED initially, GREEN as §5.5 closes gaps. Not a doc gap, an impl-discovery activity.
- **DEP-01 fixture (`expected-deps.yaml`)** depends on W1+W2 finalised architecture. If W1.x or W2.x merge late, the fixture must be regenerated. Implementer must add `make refresh-expected-deps` target. Acceptance §6.5 hints but doesn't enumerate.
- **W3.2-ISO-01 / ISO-02 enforcement** requires Grafana role-mapping (admin vs viewer) and VL API tenant-token-introspection. Acceptance §6.4 enumerates verification but doesn't enumerate the helm-chart values. Implementer adds.
- **EDGE-03 (PagerDuty inhibition window 7 days)** — Alertmanager routing config detail; acceptance §6.3 enumerates the requirement; implementer adds to alertmanager.yaml.

These are **impl-discovery gaps**, not acceptance-doc omissions. Acceptance covers the **what** correctly; **how** is impl's job.

## 7. Cross-reference

- Acceptance source: [docs/specs/sub-phase-W3.2-observability-customisation-acceptance.md](sub-phase-W3.2-observability-customisation-acceptance.md)
- Companion plans: [test-plan-W2.B.md](test-plan-W2.B.md) (B.9 audit pipeline emits to VL — predecessor to LOGSQL-01..02), [test-plan-W3.1.md](test-plan-W3.1.md) (#40/#42 audit emits surface in LogsQL queries), [test-plan-W3.3.md](test-plan-W3.3.md) (mTLS metric `kacho_iam_mtls_handshake_total` surface in alerts)
- Workspace rules: `CLAUDE.md` §«Запреты» #6 (Internal-vs-external — VL API gated for tenants), §«Инфра-чувствительные данные» (placement/SID info NEVER in tenant-visible dashboards)
- Workspace skills (referenced by implementer): `victoriametrics-query`, `victorialogs-query`, `victoriatraces-query`, `alertmanager-query`, `investigating-with-observability`
- Naming conventions: integration tests in `tests/observability/<area>_integration_test.go::Test_<Area>_<Scenario>` (NOT inside `internal/` — these are deploy-side cluster tests, not service-level)
