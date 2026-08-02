# Sub-phase W1.3 — Gateway authz-middleware fail-closed enable — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per CLAUDE.md §Запреты #1).
> **Date**: 2026-05-23
> **YouTrack**: KAC-139 W1.3 (subtask of [KAC-136](https://prorobotech.youtrack.cloud/issue/KAC-136), child of epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) "kacho-iam → production-ready"). The KAC-139 issue itself is created by the controller after this doc reaches APPROVED.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-deploy` — `helm/umbrella/values.prod.yaml` adds `api-gateway.authz.{enabled,failOpen}` overrides (chart default `authz: {}` currently leaves prod **silently disabled** — root cause). `values.dev.yaml` already correct (`enabled: true, failOpen: false`) — no change beyond a smoke-confirmation.
>   - **Primary**: `PRO-Robotech/kacho-api-gateway` — code hardening: (a) startup validation that rejects `Enabled=true && FailOpen=true && APP_ENV=prod`, (b) per-Check deadline propagation cap (drop request deadline to `AuthZCheckTimeoutMs` so a slow upstream cannot bypass fail-closed via context-canceled-after-handler), (c) metric/log assertion lines so the running config is observable at boot, (d) deprecation-log of `AuthZFailOpen=true` in any non-dev environment.
>   - **Touched**: `PRO-Robotech/kacho-deploy` umbrella chart `charts/api-gateway-1.2.0.tgz` may need a re-bump if we add a new env var (`KACHO_API_GATEWAY_AUTHZ_REQUIRE_FAIL_CLOSED`) or — preferred — gate purely on `failOpen=false` default + deployment-template tightening (no version bump needed). Decision in §8 (OQ-W1.3-1).
>   - **NOT touched**: `kacho-iam`, `kacho-corelib`, `kacho-proto`, `kacho-compute`, `kacho-vpc` — middleware lives entirely in the api-gateway; backend interceptors (authzguard, FGA writer, drainer) are unaffected.
> **Branch (all repos)**: `KAC-139`.
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 1.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.3.
> **Predecessors**:
>   - `sub-phase-W1.1-fga-outbox-drainer-acceptance.md` (APPROVED 2026-05-23) — bootstrap-admin grants now reach OpenFGA, so fail-closed becomes safe to enable (without W1.1 every Check would deny → cluster bricked).
>   - `sub-phase-W1.2-subject-change-cache-invalidation-acceptance.md` (in-flight, GREEN tests landed) — revoke→DENY within 1s, prerequisite to claiming "fail-closed has correct fresh state".

---

## 0. Преамбула — что эта sub-итерация (précis)

W1.3 — **третий чанк Wave 1**. После W1.1 (FGA drainer) + W1.2 (cache invalidation) inputs to the gateway authz-middleware are **correct and fresh**; the missing piece is making sure the middleware is **actually mounted, enforcing, and never silently degrades to ALLOW** on production environments.

Three concrete failures W1.3 closes:

1. **A security control whose master switch defaults to off, and whose production profile never turns it on, is a control that exists in the code and not in the deployment.** The gateway's authorisation middleware is correct (§1.1) — but correctness of the decision pipeline says nothing about whether that pipeline is *mounted*. Three ordinary decisions compose into the failure: the Go-side default for the master toggle is off (a legacy-compatibility choice, reasonable in isolation); the subchart ships an empty defaults block (reasonable in isolation); and the production overlay overrides only image fields, on the assumption that anything security-relevant would already be on (reasonable in isolation). No single one of them is a mistake, and no review of any single one of them would flag anything — which is precisely why this class survives review and must be caught by a **startup guard**, not by reading values files.

   Two independent sub-questions, both to be settled by `helm template` rather than by reading (Helm's truthiness for an empty map versus a nil map is exactly the sort of premise that is assumed and then turns out false): whether the template emits the env block at all, and whether the emitted value is the one intended. The fix does not depend on the answer — see §2: production refuses to start unless the control is demonstrably on.

2. **No startup-time guard — the posture is logged, and logging is not enforcing.** Wiring prints the effective authorisation posture and proceeds no matter what it printed. A printed value is a statement *about* a decision already taken; it stops nobody, and nobody reads it on a healthy start. The class is the one recorded in `.claude/rules/security.md` §«Production-mode обязателен ВЕЗДЕ»: a guard that has been *declared* but is never *read* is a dead guard, and a dead guard is worse than an absent one, because the deployment checklist can point at it.

   What is required is **refuse-to-start**: in production posture the process must exit when the authorisation control is off, or when it is on but configured to permit on its own failure. The operator-facing refusal message must name the knob and the reason — that message is runtime diagnostics, not a published artefact, and without it the stand cannot be brought up (see `.claude/rules/security.md`, the three places explicitly exempt from publication discipline).

3. **A timeout the caller can shorten is not a bound the server owns.** The authorisation check runs on the inbound request's context, so the caller's deadline — which the caller chooses — can expire before the check completes. The check then reports failure, and what happens next is decided entirely by the fail-open/fail-closed setting. Fail-closed this is merely a retryable error; fail-open it is a permit, and the caller has a hand on the lever. The lesson generalises past this call site: **any budget that a control depends on must belong to the control, not to the request it is judging** (`.claude/rules/architecture.md`, per-call deadline on every external call).

   The remedy is ordered: first make production refuse fail-open at all (item 2), which removes the dangerous branch outright; then, if the client's own timeout turns out not to be hard-bounded, wrap the check in a server-owned `context.WithTimeout`. That second step is cheap and is taken regardless of the audit's outcome — trusting a client-side timeout to apply to the RPC and not merely to the dial is a premise, and premises of this kind are exactly what §1 warns about. Decision in §8 (OQ-W1.3-2).

W1.3 is largely a **configuration-correctness + startup-validation** chunk; the heavy lifting (middleware itself) was done in KAC-127 Phase 3 and is correct in code. We do **not** rewrite the decision pipeline. We **do** ensure that pipeline cannot be bypassed by a misconfigured helm overlay or unobserved env-var.

### 0.1 W1.3 НЕ включает

- **OPA bundle fail-closed** — out of scope of the gateway. OPA sidecars run alongside backend pods (vpc/compute/iam) per `helm/umbrella/values.yaml` §«KAC-127 Phase 3 — AuthZ core» and evaluate policies **locally**; their fail-closed-on-stale-bundle behaviour is enforced by OPA itself (`policy_failure: deny`) and by the bundle-signing JWS verification. Gateway never calls OPA. Coverage of OPA bundle-corruption / unreachable-fetch belongs to Wave 3 (acceptance §3.3 follow-up) or a dedicated `kacho-iam OpaBundleService` resilience chunk.
- **Per-resource authz cache invalidation** — already shipped in W1.2 via `InternalAuthzCacheService.InvalidateSubject`. W1.3 only enables the fail-closed semantics on top.
- **Principal propagation cross-service** — that is W1.4 (KAC-140). Without principal propagation kacho-vpc still asks IAM with `user:bootstrap` for tenant requests; that hides authz mistakes but is orthogonal to gateway fail-closed. W1.3 fails closed regardless of the principal value passed through.
- **Anti-anonymous interceptor on mutating RPCs** (finding #43 in remediation plan) — that is `authzguard` in `kacho-iam`, not gateway middleware. Covered by W1.6 Chunk 2. W1.3 must verify it does not **conflict** (anti-anonymous denies at backend → gateway sees PermissionDenied → cache stores deny → fail-closed downstream still correct).
- **Permission-catalog completeness** — already 264/264 RPCs annotated (per `values.dev.yaml` line 47-48 comment); any new RPC added between W1.3 author and W1.3 merge that has no catalog entry will be **denied** by middleware (correct fail-closed semantics for catalog-miss, see `authz.go:536-568`). No catalog re-audit in W1.3.
- **Newman suites beyond the one new AUTHZ-FAILCLOSED-OPENFGA-DOWN case** — coverage extension is W2 Поток D scope.

### 0.2 Зависимости

- **W1.1 APPROVED + merged** — bootstrap-admin tuples must be in OpenFGA before fail-closed flips on prod (otherwise every Check returns deny → cluster bricked at first tenant request). Verified per W1.1 acceptance DoD.
- **W1.2 APPROVED + merged** — revoke→DENY within 1s; fail-closed makes "stale-cache ALLOW after revoke" twice as visible (the 30s window collapses to 1s), so W1.2 must already absorb that latency drop.
- **OpenFGA HA-mini available on every target stand** — `openfgaPdb.minAvailable: 2` (per values.prod.yaml) + bootstrap-job idempotent (W0.4). On dev stand single-replica OpenFGA is acceptable (failure of the single pod = expected fail-closed 503; recovery within helm chart restart).
- **`helm/umbrella/Chart.lock` regeneration** if the api-gateway subchart version bumps (see §8 OQ-W1.3-1).

---

## 1. Current state (discovered 2026-05-23)

Exact values pulled from the repo at `KAC-132` HEAD (this branch). Sources cited inline so reviewer can spot drift.

### 1.1 Gateway middleware code

> Line numbers are deliberately omitted throughout §1. They go stale on the first edit, and — paired
> with a condition and its consequence — they compose into a reconstructable recipe in a repository
> that is public (`.claude/rules/security.md` §«Публичные артефакты»). File and behaviour are enough
> to act on; the per-site walkthrough stayed in the task's working directory.

- `internal/middleware/authz.go` — `AuthzMiddlewareConfig` carries `Enabled` (master toggle) and `FailOpen` (legacy override), and a comment at the top of the file states the intent: on IAM error, fail closed unless the fail-open override is set. **The fail-closed semantics are correctly implemented** across all three transports (unary, stream, HTTP) — each emits `Unavailable` / HTTP 503 on check-error while the override is off. **No code change is needed in the decision pipeline**, and this is the point worth carrying: the defect W1.3 addresses is *not* in the code that decides. Auditing the decision path would have found nothing.
- `internal/middleware/authz.go` — `NewAuthzMiddleware(cfg)`: with the master toggle off it returns a **no-op**, and — this is the part that matters — performs **no dependency validation** on the way. A disabled control therefore cannot report that it is misconfigured, because being disabled is the one state in which nothing is checked. Any component that can be switched off must still validate loudly enough to be noticed, or its off-state is indistinguishable from a healthy start.
- `cmd/api-gateway/main.go` — wiring builds either the real middleware or the no-op, and logs the effective posture (`enabled` / `fail_open` / cache TTL). It emits no startup error for any combination. See §0 item 2: printing a posture is not enforcing one.
- `internal/clients/iam_authorize_client.go` — to be read separately to confirm per-check deadline plumbing (§8 OQ-W1.3-2): the configured timeout is passed into the client, but it must be verified that the client applies it **around the RPC**, not only to the dial. "It is passed in" and "it bounds the call" are different claims.
- Per-subject cache invalidation port (`AsInvalidator()`), added in W1.2. W1.3 must verify the fail-closed path through it: an ALLOW cached before the authorisation backend became unreachable must not survive a subsequent invalidation during the outage. It should not — invalidation is a local memory operation and does not depend on the backend — but "should" is a premise, and this one gets a test.

### 1.2 Gateway config defaults

- `internal/config/config.go` — the AuthZ config section. The shape to note is not any single value but the **asymmetry between two defaults**: the master toggle defaults to permissive (chosen for legacy compatibility, when the control did not yet exist), while the failure-behaviour toggle defaults to safe. Both defaults were defensible when written; together they mean the safe default only takes effect once someone has already turned the control on. **A safe default nested inside a permissive one does not make the system safe** — it makes the audit of the inner default misleading.
- Timeout and cache-TTL defaults exist and are unremarkable; they are listed in the config section and are not what this chunk changes.
- **There is no production-posture guard interacting with AuthZ at all** — nothing relates `APP_ENV`-style production intent to whether authorisation is actually enforcing. That absence is the substance of W1.3: §2 introduces the guard, and the guard is what makes every default above safe to be wrong.

### 1.3 Helm umbrella values

- **api-gateway subchart** — documents an `authz` block (`enabled / failOpen / iamAuthorizeUrl / cacheTtlSeconds / checkTimeoutMs`) and ships it **empty** by default. The deployment template gates env emission on the block's truthiness; whether an empty map is truthy is a templating-semantics question, and the answer decides whether the variables are emitted-with-safe-defaults or not emitted at all. **This must be settled by `helm template`, not by reading** (§3.1 RED-test #G1). Note that *both* answers land in the same place — the control ends up off — which is why the reasoning must not stop at "the values look fine": the two paths differ in mechanism and are identical in outcome.
- **dev profile** — sets the control on explicitly. Correct; smoke-confirmation only. Worth stating plainly, because it is the reason the gap survived: **the profile people run every day was right**, so day-to-day experience offered no signal about the profile nobody exercises interactively.
- **prod profile** — the `api-gateway` block overrides image fields only, and carries no security-posture overrides. **This is the bug** — and it is a bug of *omission*, which no diff review surfaces: nothing was written incorrectly, something was never written. Omissions are found by asking a running process what posture it is in (§2 guard), never by reviewing values files.
- **umbrella OPA sidecar block** — targets backend pods, not the gateway; confirms the gateway is decoupled from the OPA path, so OPA fail-closed stays out of W1.3 scope.

### 1.4 Newman cases — currently in place

- `project/kacho-iam/tests/newman/cases/authz-deny.py` — DENY semantics on authenticated-but-unauthorised requests. Currently asserts 403/PermissionDenied; does **not** exercise OpenFGA-unreachable.
- No existing case touches OpenFGA-down scenarios. Test stack uses a real OpenFGA container per `tests/authz-fixtures/setup.sh`; no toggle to kill it mid-run exists. W1.3 adds either (a) a docker stop / k8s scale-to-zero step inside the run-script or (b) a dedicated newman suite file that paw-orchestrates via `kubectl scale openfga --replicas=0`. Decision in §8 (OQ-W1.3-3).

### 1.5 Authzguard backend interceptor (finding #43 cross-check)

- `project/kacho-iam/internal/authzguard/interceptor.go` (full file scan): anti-anonymous gate on mutating RPCs. Currently incomplete (Issue/Revoke/Approve*/Deny*/Generate*/Cancel missing — that's W1.6's chunk-2 work). For W1.3 the cross-check is: when fail-closed flips ON, anonymous mutating RPC → gateway middleware ALLOWS catalog-exempt or unauthenticated paths via existing 401 path (lines 503-528 authz.go), reaches backend, backend authzguard either denies (covered FQNs) or passes (uncovered FQNs — the #43 hole). **W1.3 must not regress this**: anonymous→fail-closed→401 from gateway should hit backend at most once with no harm; the eventual 403/501 from backend is correct. Tested in §3.4 negative case.

### 1.6 Internal listener (port 9091) — must NOT be subject to fail-closed

- `project/kacho-api-gateway/cmd/api-gateway/internal_grpc_listener.go` — separate listener for internal cluster mTLS-only RPCs (e.g. `InternalAuthzCacheService.InvalidateSubject` from W1.2). Per CLAUDE.md §запрет #6, internal listener serves admin / control-plane traffic and **does not** invoke the authz-middleware chain. Verified by reading the file: it constructs its own `grpc.NewServer(...)` with its own interceptor stack (request-id + recovery + auth-interceptor) — no `authzMW.Unary()`. W1.3 must explicitly NOT add fail-closed to this path (otherwise the W1.2 push-drainer would lose its push channel during an OpenFGA outage, defeating recovery).

---

## 2. What ships (changes by file)

### 2.1 `kacho-deploy` — `helm/umbrella/values.prod.yaml`

Add under the `api-gateway:` block (currently only lines 295-297):

```yaml
api-gateway:
  image: "docker.io/prorobotech/kacho-api-gateway:${KACHO_IMAGE_TAG}"
  imagePullPolicy: Always
  # KAC-139 (W1.3): production must fail-closed on IAM-Check error / OpenFGA
  # unreachable. Chart default `authz: {}` would render env-vars as enabled=false
  # → middleware mounts as no-op pass-through (silent disable). Make explicit.
  authz:
    enabled: true
    failOpen: false
  # KAC-139 (W1.3): production-strict authn mode — Bearer mandatory, anonymous
  # path forbidden on the public surface. (Production-mode was already documented
  # in config.go:58-65; never wired into prod overlay until now.)
  authn:
    mode: production-strict
```

### 2.2 `kacho-deploy` — `helm/umbrella/values.dev.yaml`

No functional change. Add a comment line above `authz.enabled: true` cross-referencing `KAC-139` so future operators see W1.3 confirmed dev parity. (Optional — reviewer may drop.)

### 2.3 `kacho-api-gateway` — `cmd/api-gateway/main.go` startup validation

In `buildAuthzMiddleware(cfg, logger)` (lines 533-586), insert validation **before** the existing `if !cfg.AuthZEnabled` early-return:

```go
// KAC-139 (W1.3): refuse to start in any non-dev environment when authz is
// either disabled or in fail-open mode. APP_ENV is the umbrella deploy-context
// signal (dev|staging|prod); reading directly here keeps the check at the
// composition root.
appEnv := strings.ToLower(os.Getenv("KACHO_APP_ENV"))
isProd := appEnv == "prod" || appEnv == "production" || appEnv == "staging"
if isProd && !cfg.AuthZEnabled {
    return nil, fmt.Errorf(
        "authz middleware: KACHO_API_GATEWAY_AUTHZ_ENABLED=false in %s — refuse to start (KAC-139)",
        appEnv)
}
if isProd && cfg.AuthZFailOpen {
    return nil, fmt.Errorf(
        "authz middleware: KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN=true in %s — refuse to start (KAC-139)",
        appEnv)
}
if cfg.AuthZFailOpen {
    // dev / staging may flip fail-open for emergency debugging; surface as
    // structured log + WARN metric for observability dashboards.
    logger.Warn("authz middleware: FAIL-OPEN MODE — IAM errors will allow requests; never use on prod",
        "env", appEnv, "ticket", "KAC-139")
}
```

`KACHO_APP_ENV` is a new env-var; helm chart `templates/deployment.yaml` must emit it from `.Values.env` (already supported via `extraEnv` if we choose that route — verify). Inject in `values.prod.yaml`:

```yaml
api-gateway:
  extraEnv:
    KACHO_APP_ENV: "prod"
```

And in `values.dev.yaml`:

```yaml
api-gateway:
  extraEnv:
    KACHO_APP_ENV: "dev"
```

### 2.4 `kacho-api-gateway` — bounded per-Check context

`internal/middleware/authz.go:645` — if §1.1 verification of `iam_authorize_client.go` shows the timeout is **only** on gRPC dial, wrap the Check call:

```go
checkCtx, cancel := context.WithTimeout(ctx, m.cfg.CheckTimeout)
defer cancel()
result, err := m.cfg.Checker.Check(checkCtx, AuthzCheckInput{...})
```

Add `CheckTimeout time.Duration` to `AuthzMiddlewareConfig`; default 200ms; wire from `cfg.AuthZCheckTimeoutMs` in main.go. **No-op if client-side timeout is already enforced** (decision in §8 OQ-W1.3-2).

### 2.5 `kacho-api-gateway` — boot-time effective-config log line

After `buildAuthzMiddleware` succeeds (main.go ~line 245), log a single canonical line that ops dashboards can scrape:

```
INFO  authz-mw effective-config  enabled=true  fail_open=false  env=prod
      cache_ttl_s=5  check_timeout_ms=200  iam_authorize=iam.kacho.svc.cluster.local:9090
```

This is partially present already (lines 247-256) — extend with `env` and reorder so a single grep gives the whole story.

### 2.6 `kacho-iam` — newman case `AUTHZ-FAILCLOSED-OPENFGA-DOWN`

New case file: `project/kacho-iam/tests/newman/cases/authz-failclosed.py` (declarative `cases/*.py` → `gen.py` flow, mirrors existing files). Single scenario described in §3.5; orchestration runs via a wrapper script `tests/newman/scripts/run-failclosed.sh` that:

1. Asserts api-gateway authz-enabled (curl `/metrics` for `kacho_apigw_authz_enabled` gauge — added in §2.5 if needed, or grep startup log).
2. `kubectl --context kind-kacho scale deployment kacho-umbrella-openfga --replicas=0`.
3. Waits until `kubectl get pods -l app.kubernetes.io/name=openfga` returns no Ready pod.
4. Runs newman on `authz-failclosed.json` collection.
5. Restores: `kubectl scale ... --replicas=1` (dev) or `--replicas=3` (prod parity).
6. Waits for OpenFGA Ready + bootstrap-job re-confirms tuple presence (idempotent W1.1 path).

---

## 3. GWT scenarios

All scenario IDs use the prefix `W1.3-`. Negative cases — exact gRPC code from `02-data-model-and-conventions.md §14`. Each scenario maps to at least one integration test (Go testcontainers) AND one newman case unless explicitly marked otherwise.

### 3.1 Helm-rendering scenarios (smoke before code-test)

#### Scenario W1.3-H1: prod values render explicit fail-closed

**Given** the repo at the W1.3 branch head with `values.prod.yaml` patched per §2.1
**When** an operator runs `helm template kacho-umbrella project/kacho-deploy/helm/umbrella -f project/kacho-deploy/helm/umbrella/values.prod.yaml`
**Then** the rendered `Deployment/api-gateway` carries env vars:
  - `KACHO_API_GATEWAY_AUTHZ_ENABLED` with value `"true"`
  - `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN` with value `"false"`
  - `KACHO_APP_ENV` with value `"prod"`
**And** `KACHO_API_GATEWAY_AUTHN_MODE` with value `"production-strict"`
**And** grep-confirmed in CI by a `helm-validate-prod` target (**never landed** — `deploy/Makefile` has
`helm-lint` and `helm-manifest-test`, and the `helm` CI job runs `helm template` directly) that would wrap `helm template | grep -E "^.*KACHO_API_GATEWAY_AUTHZ_(ENABLED|FAIL_OPEN)" | wc -l == 2`).

#### Scenario W1.3-H2: dev values unchanged in functional content

**Given** the repo at the W1.3 branch head
**When** `helm template` is run with `values.dev.yaml`
**Then** rendered Deployment retains `KACHO_API_GATEWAY_AUTHZ_ENABLED=true` and `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN=false`
**And** `KACHO_APP_ENV=dev` (per §2.3 wiring).

### 3.2 Per-request fail-closed (happy + deny + outage)

#### Scenario W1.3-01: OpenFGA reachable + Check ALLOW → request proxied

**Given** the kind dev stand is up via `make -C deploy dev-up` with W1.3 helm overlay applied
**And** OpenFGA is healthy (`kubectl get pods -l app.kubernetes.io/name=openfga` shows Running/Ready=1)
**And** subject `user:usr_admin_e2e` has a `cluster_admin` tuple in OpenFGA (seeded by `tests/authz-fixtures/setup.sh`)
**When** client calls `POST /iam/v1/projects` with `Authorization: Bearer <admin-jwt>` and a valid `CreateProject` payload
**Then** api-gateway authz-middleware Check returns `Allowed=true`
**And** the request is proxied to kacho-iam ProjectService.Create
**And** response is HTTP 200 (or 201 with the new Project envelope per existing acceptance KAC-105)
**And** `metrics.kacho_apigw_authz_decisions_total{outcome="allow"}` increments by 1.

#### Scenario W1.3-02: OpenFGA reachable + Check DENY → 403 PermissionDenied

**Given** the kind dev stand is up with W1.3 helm overlay
**And** subject `user:usr_viewer_e2e` has only a `reader` tuple at folder-scope, none for cluster
**When** client calls `DELETE /iam/v1/projects/{id}` with `Authorization: Bearer <viewer-jwt>`
**Then** middleware Check returns `Allowed=false, DenyReasons=["no path"]`
**And** gateway responds HTTP 403 PermissionDenied with `code=7` body (per existing PermissionDenied descriptor)
**And** the backend ProjectService.Delete is **never** invoked (verify via backend access log absence of request-id)
**And** `metrics.kacho_apigw_authz_decisions_total{outcome="deny"}` increments by 1.

#### Scenario W1.3-03: OpenFGA unreachable (pod down) → 503 Unavailable

**ID:** W1.3-03 (newman ID `AUTHZ-FAILCLOSED-OPENFGA-DOWN`)

**Given** the kind dev stand is up with W1.3 helm overlay (`authz.enabled=true, failOpen=false`)
**And** subject `user:usr_admin_e2e` would normally be ALLOWED for `iam.projects.create` (verified by W1.3-01)
**And** OpenFGA decision-cache TTL has elapsed for this subject (cache MISS guaranteed) OR cache was pre-flushed via `InternalAuthzCacheService.InvalidateSubject("user:usr_admin_e2e")`
**And** OpenFGA is then scaled to zero: `kubectl scale deployment kacho-umbrella-openfga --replicas=0` and the pod is confirmed Terminated
**When** client calls `POST /iam/v1/projects` with `Authorization: Bearer <admin-jwt>` and a valid payload
**Then** middleware Check fails (gRPC `Unavailable` from OpenFGA dial timeout via kacho-iam.AuthorizeService.Check)
**And** middleware enters `outcomeError` with `cfg.FailOpen=false`
**And** gateway responds HTTP **503** with body `{"code":14,"message":"authz service unavailable"}` (Unary/Stream path) OR gRPC `Unavailable` (proto clients)
**And** the response is **NEVER** HTTP 200 — i.e. the request is **NOT** proxied to kacho-iam ProjectService.Create
**And** `metrics.kacho_apigw_authz_errors_total` increments by 1
**And** error log line carries `fqn=kacho.cloud.iam.v1.ProjectService/Create subject=user:usr_admin_e2e err=<openfga conn error>`.

#### Scenario W1.3-04: OpenFGA returns 5xx for N retries → 503 Unavailable (no leak)

**Given** the stand is up with W1.3 helm overlay
**And** OpenFGA pod is **running but injected** to return HTTP 500 on every `/stores/{id}/check` request (test fault-injection via `kubectl patch` of OpenFGA env `OPENFGA_HTTP_FAULT_RATE=1.0` — or k8s NetworkPolicy egress-block from kacho-iam → openfga forcing TCP RST)
**When** client calls any authz-gated RPC (e.g. `POST /vpc/v1/networks`)
**Then** kacho-iam.AuthorizeService.Check returns gRPC `Unavailable` after its own retry budget (per kacho-iam internal config; out of W1.3 scope to tune)
**And** gateway sees `outcomeError`
**And** gateway returns HTTP 503 (NOT 200, NOT cached-stale-ALLOW)
**And** for the duration of the outage `metrics.kacho_apigw_authz_errors_total` increases monotonically per failed request.

#### Scenario W1.3-05: Cache HIT during OpenFGA outage — pre-outage ALLOW still served from cache, MISS becomes 503

**Given** the stand is up with W1.3 helm overlay (`AuthZCacheTTLSeconds=5`)
**And** subject `user:usr_admin_e2e` made a successful call at T=0; `outcomeAllow` cached for key `(user:usr_admin_e2e, iam.projects.create, project, *)` until T+5s
**And** OpenFGA is scaled to 0 at T=1s
**When** the same subject calls the same RPC at T=3s (within cache TTL)
**Then** middleware hits cache (no FGA call), serves `outcomeAllow`, proxies request → HTTP 200
**And** the same subject calls a **different** authz-gated RPC at T=4s (cache MISS)
**Then** middleware attempts FGA Check → outage → HTTP 503

> This scenario documents the intentional behaviour: cache is a performance layer with bounded TTL. Cache-stale-ALLOW within the 5-second window is acceptable; this is **not** a security regression because the cached decision was made against a healthy FGA. Operators can shorten `AuthZCacheTTLSeconds` to reduce the window. Documented in vault edges/iam-to-apigw-cache-invalidation.md update.

### 3.3 Mandatory enforcement — no per-RPC bypass

#### Scenario W1.3-06: mutating RPC with no Authorization header → 401 Unauthenticated

**Given** the stand is up with W1.3 helm overlay (production-strict authn mode)
**When** client calls `POST /iam/v1/projects` with NO Authorization header
**Then** **either** the upstream anti-anonymous interceptor (W1.6 future work) returns 401 Unauthenticated **or** the gateway authz-middleware path returns Unauthenticated (per `authz.go:573-588` `outcomeUnauthenticated`)
**And** the gateway never returns HTTP 200 for this anonymous mutation
**And** the response code is **16 / 401**, not **7 / 403** (per KAC-130 BUG-2 distinction documented in authz.go).

#### Scenario W1.3-07: legacy `KACHO_API_GATEWAY_AUTHZ_ENABLED=false` in prod env → startup error

**Given** the api-gateway binary is launched with `KACHO_API_GATEWAY_AUTHZ_ENABLED=false` AND `KACHO_APP_ENV=prod`
**When** `cmd/api-gateway/main.go` calls `buildAuthzMiddleware(cfg, logger)`
**Then** the function returns an error `"authz middleware: KACHO_API_GATEWAY_AUTHZ_ENABLED=false in prod — refuse to start (KAC-139)"`
**And** main.go `log.Fatalf("authz middleware: %v", err)` triggers
**And** the process exits with non-zero code BEFORE the cmux listener is bound
**And** k8s reports pod CrashLoopBackOff (operator sees the misconfig immediately).

#### Scenario W1.3-08: legacy `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN=true` in prod env → startup error

**Given** the api-gateway binary is launched with `KACHO_API_GATEWAY_AUTHZ_ENABLED=true`, `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN=true`, `KACHO_APP_ENV=prod`
**When** main.go calls `buildAuthzMiddleware(cfg, logger)`
**Then** the function returns an error `"authz middleware: KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN=true in prod — refuse to start (KAC-139)"`
**And** process exits non-zero BEFORE listener bind.

#### Scenario W1.3-09: same flags but `KACHO_APP_ENV=dev` → startup succeeds with WARN log

**Given** the api-gateway binary is launched with `KACHO_API_GATEWAY_AUTHZ_ENABLED=true`, `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN=true`, `KACHO_APP_ENV=dev`
**When** main.go calls `buildAuthzMiddleware(cfg, logger)`
**Then** the function returns the real middleware (no error)
**And** logger emits `WARN authz middleware: FAIL-OPEN MODE — IAM errors will allow requests; never use on prod env=dev ticket=KAC-139`
**And** the gateway starts and serves requests
**And** when OpenFGA is down on dev, authz Check errors → middleware ALLOWS the request (because FailOpen=true in dev) — confirming the override works for emergency debugging.

#### Scenario W1.3-10: any mutating RPC under fail-closed proxies on ALLOW, errors on outage — sweep

**Given** the dev stand with W1.3 overlay
**When** for each of the following FQNs the test runs (a) authorised happy-path and (b) OpenFGA-down path:
  - `kacho.cloud.iam.v1.AccessBindingService/Create`
  - `kacho.cloud.iam.v1.AccessBindingService/Delete`
  - `kacho.cloud.iam.v1.JitPendingService/ApproveJITActivation`
  - `kacho.cloud.iam.v1.JitPendingService/DenyJITActivation`
  - `kacho.cloud.iam.v1.BreakGlassService/ApproveBreakGlass`
  - `kacho.cloud.iam.v1.BreakGlassService/DenyBreakGlass`
  - `kacho.cloud.iam.v1.RoleService/Create` (when enabled per catalog)
  - `kacho.cloud.iam.v1.ServiceAccountService/Create`
  - `kacho.cloud.vpc.v1.NetworkService/Create`
  - `kacho.cloud.vpc.v1.SubnetService/Delete`
  - `kacho.cloud.compute.v1.InstanceService/Create`
  - `kacho.cloud.compute.v1.DiskService/Delete`
**Then** (a) returns HTTP 200/201 (per existing acceptance)
**And** (b) returns HTTP 503 Unavailable (NOT 200, NOT 403, NOT 401)
**And** for any FQN where (b) returns anything other than 503, the test FAILS — this catches per-RPC bypasses.

### 3.4 Side-effects / cross-cuts

#### Scenario W1.3-11: W1.2 push-drain edge unaffected by fail-closed flip

**Given** the stand is up with W1.3 overlay (gateway public listener fail-closed)
**And** kacho-iam emits a `subject_change_outbox` row (e.g. via `AccessBindingService.Delete`)
**When** the W1.2 drainer in kacho-iam dials the gateway **internal listener** (port 9091) for `InternalAuthzCacheService.InvalidateSubject`
**Then** the call succeeds (NOT gated by fail-closed middleware — internal listener has its own interceptor chain per §1.6)
**And** the cache invalidation is applied
**And** the next public-listener Check for that subject performs an FGA call (no stale cache).

#### Scenario W1.3-12: W1.2 push-drain edge works DURING OpenFGA outage (internal listener stays up)

**Given** the stand is up with W1.3 overlay
**And** OpenFGA is scaled to zero
**When** kacho-iam emits a `subject_change_outbox` row (revoke happened DURING outage)
**Then** the drainer can still dial gateway internal listener and invalidate the cache (the drainer call does not touch OpenFGA)
**And** when OpenFGA recovers, the next subject Check correctly returns DENY (cache was cleared)
**And** no stale ALLOW is ever served post-recovery.

#### Scenario W1.3-13: W1.6 anti-anonymous interceptor (future) does not conflict

**Given** the stand is up with W1.3 overlay
**And** W1.6 anti-anonymous interceptor is **not yet** merged (current state)
**When** an anonymous client calls a mutating RPC `POST /iam/v1/jitPending/{id}:approve`
**Then** gateway middleware returns 401 Unauthenticated (per W1.3-06)
**And** the backend `authzguard` interceptor is never reached for this request
**And** the W1.6 finding #43 is not regressed by W1.3.

When W1.6 lands later: same request → gateway 401 (unchanged) → if gateway were ever to pass it (e.g. bug regression), W1.6 backend interceptor returns Unauthenticated. Defense-in-depth holds.

#### Scenario W1.3-14: cache lookup respects fail-closed for next-request when FGA goes down mid-flight

**Given** subject S has `cached=ALLOW` for action A1 (5s TTL, fresh)
**And** OpenFGA is up at T=0
**When** S calls A1 at T=1s — cache hit, ALLOWED (200) — per W1.3-05 expected
**And** OpenFGA goes down at T=2s
**And** S calls a **different** action A2 at T=3s (cache MISS)
**Then** middleware calls FGA → error → returns 503 (fail-closed semantics for the new call)
**And** at T=4s OpenFGA recovers; S calls A2 again → cache MISS → FGA Check → 200/403 as configured
**And** at no point during the outage does A2 return ALLOW from a stale source.

#### Scenario W1.3-15: metrics observability — fail-closed denials are countable

**Given** the stand is up with W1.3 overlay
**When** 100 requests hit the gateway during an OpenFGA outage
**Then** `metrics.kacho_apigw_authz_errors_total` increments by 100
**And** `metrics.kacho_apigw_authz_decisions_total{outcome="allow"}` does **not** increment
**And** Grafana dashboard `api-gateway-overview` (existing) shows the 503-spike (operator can correlate to outage start).

### 3.5 Newman acceptance case — `AUTHZ-FAILCLOSED-OPENFGA-DOWN`

**ID:** W1.3-NM-01

**Given** the kind stand from `kacho-deploy` is up via `make -C deploy dev-up` (W1.3 helm overlay)
**And** `tests/authz-fixtures/setup.sh` has run (admin-jwt + viewer-jwt minted)
**And** OpenFGA is initially Ready (sanity check via `kubectl wait`)
**When** the wrapper script `tests/newman/scripts/run-failclosed.sh` executes:
  1. Sanity: `POST /iam/v1/projects` with admin-jwt → expects 200/201 (FGA reachable, ALLOW cached)
  2. Pre-flight: hit `/internal/v1/authz-cache:invalidate` for the admin subject to force MISS on next call
  3. Scale down: `kubectl scale deployment kacho-umbrella-openfga --replicas=0` + wait until 0 Ready
  4. Test call: `POST /iam/v1/projects` with admin-jwt + a fresh distinct payload
  5. Assert response **status code 503** AND response body matches `{"code":14,"message":"authz service unavailable"}`
  6. Test call (variant): `POST /vpc/v1/networks` with admin-jwt — assert 503
  7. Test call (variant): `DELETE /iam/v1/projects/{id}` for an existing project with admin-jwt — assert 503
  8. Recovery: `kubectl scale deployment kacho-umbrella-openfga --replicas=1` + wait Ready
  9. Wait for bootstrap-job re-apply (idempotent W1.1) or 10s grace
  10. Final call: `POST /iam/v1/projects` → assert 200/201 (cluster operational)
**Then** all assertions pass
**And** newman exit code is 0
**And** the suite registers in coverage.py output for at least 1 case under `AUTHZ-FAILCLOSED-*`.

---

## 4. Definition of Done

- [ ] All 15 GWT scenarios authored above pass as automated tests:
  - [ ] H1/H2: targets `helm-validate-prod` / `helm-validate-dev` — **not landed**; what exists is
        `make -C deploy helm-lint` + `make -C deploy helm-manifest-test` and the `helm` CI job
  - [ ] 01-05: gateway integration test `internal/middleware/authz_failclosed_integration_test.go` with testcontainers (OpenFGA + kacho-iam-stub) GREEN
  - [ ] 06-10: gateway integration `authz_failclosed_enforcement_test.go` GREEN
  - [ ] 07-09: gateway unit `cmd/api-gateway/main_failclosed_startup_test.go` GREEN
  - [ ] 11-15: cross-cut integration tests added to `cmd/api-gateway/internal_grpc_listener_w1_2_test.go` extension (or new `*_w1_3_test.go`)
  - [ ] NM-01: newman `AUTHZ-FAILCLOSED-OPENFGA-DOWN` GREEN in `make -C deploy dev-up && cd services/iam/tests/newman && ./scripts/run-failclosed.sh`
- [ ] CI green in 2 repos: `kacho-api-gateway` (build/lint/gosec/integration), `kacho-deploy` (helm-lint, helm-template, newman-e2e)
- [ ] Helm `values.prod.yaml` patched per §2.1; PR shows explicit `authz.enabled=true, authz.failOpen=false, authn.mode=production-strict, extraEnv.KACHO_APP_ENV=prod`
- [ ] Helm `values.dev.yaml` carries `extraEnv.KACHO_APP_ENV=dev` (matches startup validation)
- [ ] `cmd/api-gateway/main.go` startup-validation merged; manual smoke: `KACHO_APP_ENV=prod KACHO_API_GATEWAY_AUTHZ_ENABLED=false ./api-gateway` exits non-zero with the expected error message (recorded in PR description)
- [ ] Per-Check deadline confirmed bounded (either by `iam_authorize_client.go` Timeout or by §2.4 `context.WithTimeout` wrap) — chosen approach recorded in PR description
- [ ] Newman E2E green: 100% scenarios in §3 pass on freshly bootstrapped kind stand
- [ ] Vault updated:
  - [ ] `obsidian/kacho/KAC/KAC-139.md` created with trail
  - [ ] `obsidian/kacho/edges/iam-to-apigw-cache-invalidation.md` updated — "Latency promise" section confirms fail-closed semantics + cite W1.3
  - [ ] `obsidian/kacho/packages/apigw-middleware-authz.md` created or updated — startup-validation API documented
- [ ] After merge: `kacho-deploy` CI matrix runs `newman-e2e` against prod-values dry-run and asserts no regression in §3.1 helm-rendering scenarios
- [ ] Coverage.py output unchanged or +1 case (new AUTHZ-FAILCLOSED suite registers as 1 case minimum)
- [ ] Tests/integration ≥80% on changed gateway files (per CLAUDE.md §Запреты #11)

---

## 5. Out of scope (explicit, to prevent scope-creep)

- Principal propagation (`x-kacho-principal` header) — **W1.4** (KAC-140).
- Anti-anonymous interceptor for Issue/Revoke/Approve*/Deny*/Generate*/Cancel — **W1.6 Chunk 2** finding #43.
- Permission catalog re-audit — completed in KAC-127 Phase 3; W1.3 only relies on existing 264/264 coverage.
- OPA sidecar fail-closed (bundle unreachable / signature invalid) — backend-side concern, not gateway. Wave 3 or dedicated OPA-resilience chunk.
- Decision cache TTL tuning (currently 5s) — out of scope; default acceptable per §3.2 W1.3-05 explanation. Operators can override via `cacheTtlSeconds: <n>` in helm.
- Circuit-breaker on the IAM-AuthorizeService client — **not introduced** in W1.3 (see §8 OQ-W1.3-4 decision). Current behaviour: every request hits FGA, every failure returns 503. Acceptable for prod-v1; if FGA outage causes thundering-herd we revisit in Wave 3 observability chunk.
- Removing the `KACHO_API_GATEWAY_AUTHZ_FAIL_OPEN` env var entirely — kept as dev-emergency override. Not deleted.
- Newman cases beyond `AUTHZ-FAILCLOSED-OPENFGA-DOWN` — W2 Поток D adds breadth.
- Load-test of fail-closed behaviour (does the 503-path itself collapse under N=10k concurrent requests during outage?) — not in W1 critical path. May surface as a Wave 3 task if `kacho_apigw_authz_errors_total` rate exceeds replica-capacity.

---

## 6. Risks / mitigations

| Risk | Mitigation |
|---|---|
| Flipping `authz.enabled=true` on prod first time bricks the cluster because admin tuples were never written | Hard dependency on W1.1 APPROVED + merged + bootstrap-job re-run + tuple count verified > 0 via `openfga-bootstrap-job` post-step. Documented in W1.1 DoD; W1.3 PR cannot merge until W1.1 is in `main`. |
| `KACHO_APP_ENV` is not yet a known env var in helm chart; introducing it breaks unrelated overlays | §2.3 uses `extraEnv: {KACHO_APP_ENV: ...}` — already-supported escape-hatch in chart values.yaml line 102 (`extraEnv: {}`). No template change needed; only values changed. Existing overlays unaffected. |
| Startup validation rejects on `staging` env where ops legitimately want a debug fail-open window | Add escape-hatch env `KACHO_API_GATEWAY_AUTHZ_ALLOW_FAIL_OPEN_OVERRIDE=true` (explicit, time-bounded). Documented in §8 OQ-W1.3-5. Default: NOT added unless reviewer requests; the WARN log on dev (§3.2 W1.3-09) is the documented escape-hatch. |
| `helm template` rendering of `{{- if .Values.authz }}` with empty `{}` may be truthy (Sprig); behaviour differs from `{{- if .Values.authz.enabled }}` | H1 scenario explicitly tests rendered output, not Helm semantic. If rendering surprises us, switch chart template gate to `{{- if .Values.authz.enabled }}` in a chart bump (1.2.0 → 1.3.0) — that is a chart edit, not values-only. Decision in §8 OQ-W1.3-1. |
| OpenFGA outage during normal traffic causes user-visible 503 storm; operators escalate to fail-open in a panic | WARN log on every Fail-Open boot + dashboard alert `kacho_apigw_authz_fail_open_active{env="prod"}` (Wave 3 follow-up). For W1.3 the runbook entry in `docs/specs/03-deployment-and-operations.md` is updated to direct operators to OpenFGA pod recovery, not fail-open toggle. |
| Cache-hit during outage (§3.2 W1.3-05) creates 5s ALLOW window post-FGA-down — security perception risk | Document explicitly in vault edges note + acceptance §3.2 W1.3-05 explanation. Reviewer may choose to flush cache on FGA-Unreachable detection (active invalidation) — recommended in §8 OQ-W1.3-6 as deferred follow-up. |

---

## 7. Traceability — finding-id ↔ scenario

| Source | Finding / requirement | W1.3 scenarios |
|---|---|---|
| Master plan §«AuthZ-инфра» | Gateway fail-closed on every env | W1.3-H1, H2, 01-05, 07-08 |
| Wave 1 §W1.3 | Eliminate "skip authz" flag; OpenFGA-unreachable→Unavailable; mandatory on mutating RPC | W1.3-03, 06, 10 |
| `production-launch-plan` §WS-2.4 | "включить authz-middleware api-gateway на всех стендах, **fail-closed**" | W1.3-H1, 03, 04, 07 |
| `production-launch-plan` §WS-7.1 | "authz fail-closed везде; проверить, что недоступность OpenFGA → deny, не allow" | W1.3-03, 04, 05, NM-01 |
| `production-launch-plan` §«DoD» line 182 | "authz fail-closed; OpenFGA down → deny" | W1.3-NM-01 |
| Remediation plan #43 (anti-anonymous mutations) | W1.6 scope; W1.3 must not conflict | W1.3-06, 13 (cross-check) |
| Remediation plan §1.1 false-positive note on #17/#18 | "in-service authz действительно нет на cluster-internal listener" | W1.3-§1.6 + scenarios 11, 12 (internal listener exemption confirmed) |
| W1.2 edge `iam-to-apigw-cache-invalidation.md` | Cache invalidation push-drain must coexist with fail-closed | W1.3-11, 12, 14 |
| KAC-130 BUG-2 (auth status differentiation) | Unauthenticated=16/401 vs PermissionDenied=7/403 | W1.3-06 |
| KAC-127 Phase 3 acceptance §5.x | Authz wiring complete, catalog 264/264 | §1.1, §1.2 — preserved, not regressed |

---

## 8. Open decisions — DECISION-NEEDED with author recommendation

| ID | Question | Recommendation |
|---|---|---|
| **OQ-W1.3-1** | Chart-template gate: keep `{{- if .Values.authz }}` (empty `{}` → falsy/truthy ambiguity) or bump api-gateway chart to 1.3.0 with explicit `{{- if .Values.authz.enabled }}` (and `failOpen` defaulted independently)? | **Values-only fix (no chart bump).** Set `authz.enabled: true, failOpen: false` explicitly in `values.prod.yaml` and `values.dev.yaml` — both already do or will after W1.3. Scenario H1/H2 verifies render-correctness. Chart bump is heavier (Chart.lock, CI matrix), not justified for W1.3. If H1 reveals the empty-map ambiguity actually leaks an env-var with unintended value, escalate to chart bump in a follow-up KAC. |
| **OQ-W1.3-2** | Per-Check deadline: trust `IAMAuthorizeClientConfig.Timeout` (currently passed as `Timeout: time.Duration(cfg.AuthZCheckTimeoutMs) * time.Millisecond` at main.go:557) or add explicit `context.WithTimeout` in `authz.go:645`? | **Add explicit `context.WithTimeout`** (§2.4). Trusting client-side timeout is fragile — the client may apply it only to dial, not to RPC. The 5-line wrap is cheap and obvious. Confirm client semantics first via test; if client-side is hard-bounded, the wrap becomes a redundant no-op but never wrong. |
| **OQ-W1.3-3** | Newman OpenFGA-down orchestration: `kubectl scale --replicas=0` (heavy, requires kubectl in CI) or HTTP-fault-injection via OpenFGA env / NetworkPolicy egress block? | **`kubectl scale` for dev kind stand; document NetworkPolicy egress block as alternative for environments without kubectl.** kind always has kubectl; the wrapper script `run-failclosed.sh` shells out cleanly. NetworkPolicy is overkill for a single newman case. Wave 3 may extend with NetworkPolicy fault-injection for OPA-equivalent suites. |
| **OQ-W1.3-4** | Circuit-breaker on IAM-AuthorizeService client (e.g. `sony/gobreaker`) to short-circuit during outage? | **NOT in W1.3.** During an OpenFGA outage we WANT every request to fail-closed (return 503) — the user-visible effect is the same with or without breaker, and a breaker would mask the metric `kacho_apigw_authz_errors_total` count. Wave 3 may add a breaker once we have load-test data showing the FGA dial-pool exhausts under outage. |
| **OQ-W1.3-5** | Escape-hatch env `KACHO_API_GATEWAY_AUTHZ_ALLOW_FAIL_OPEN_OVERRIDE=true` for emergency staging operations? | **NOT added in W1.3.** Adds attack surface (operator sets it once for emergency, forgets to unset). Use the documented procedure: redeploy with `KACHO_APP_ENV=dev` overlay for the duration of the emergency. If reviewers insist on the escape-hatch we add it with mandatory expiry timestamp env (e.g. `..._OVERRIDE_EXPIRY_UNIX_TS=<ts>`), refuse start past expiry. Default: not introduced. |
| **OQ-W1.3-6** | Active cache flush on FGA-Unreachable detection (vs current passive: cache entries expire via TTL)? | **Deferred to Wave 3 observability chunk.** Active flush during outage means: at moment-of-detection we drop all cached ALLOWs, so the 5-second post-outage ALLOW window collapses immediately. Trade-off: thundering herd on FGA recovery (every subject re-Checks). Mitigated by FGA HA-mini (3 replicas on prod). Decision pending load-test data; W1.3 documents the 5s window as a known trade-off in §3.2 W1.3-05. |
| **OQ-W1.3-7** | Should W1.3 also flip `authn.mode: production-strict` in prod overlay (currently defaults to chart default; `dev` overlay sets `mode: dev`)? | **Yes — included in §2.1.** Without `production-strict`, anonymous requests still reach the catalog-exempt path; combined with fail-closed they 401 correctly (W1.3-06) but operationally we want explicit "Bearer mandatory" on prod. This is a 2-line addition adjacent to the authz block; reviewer may split into a separate KAC if scope-purity is preferred. |

---

## 9. Vault trail (to be created by subagent on merge, per CLAUDE.md §«Vault» rules)

- `obsidian/kacho/KAC/KAC-139.md` — W1.3 trail: status, repos affected (kacho-deploy, kacho-api-gateway), acceptance file path, PR list when filed, DoD checkbox state.
- `obsidian/kacho/packages/apigw-middleware-authz.md` — add startup-validation section + boot-time effective-config log line documentation.
- `obsidian/kacho/edges/iam-to-apigw-cache-invalidation.md` — add note that fail-closed makes cache stale-ALLOW window the dominant freshness concern; W1.2 invalidation latency promise (< 1s on one replica, ≤ 30s all replicas) now defines the user-visible recovery time from a wrongful ALLOW.
- (Optional) `obsidian/kacho/edges/apigw-to-iam-authorize.md` — new edge note documenting the public-listener Check call, fail-closed semantics, and dial topology (api-gateway → kacho-iam.AuthorizeService :9090, NOT through internal :9091).

#kac #feature #kacho-apigw #kacho-deploy
