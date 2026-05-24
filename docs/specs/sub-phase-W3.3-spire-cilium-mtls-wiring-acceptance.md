# Sub-phase W3.3 — SPIRE + Cilium ServiceMesh mTLS wiring (kacho-iam за SVID) — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per workspace `CLAUDE.md` §Запреты #1).
> **Date**: 2026-05-24
> **YouTrack**: KAC-W3.3 (TBD — subtask of master epic `KAC-iam-prod-ready`, child of Wave W3 «finalize»). Open via `mcp__youtrack__create_issue` at impl-start; link as subtask of the Wave-W3 tracker.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer`
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-iam` —
>     - `cmd/kacho-iam/main.go` (build internal-listener gRPC server creds from Workload API X.509 SVID source; switch from `grpcsrv.NewServer(...)` no-creds → `grpc.Creds(spiffegrpc.Creds(...))`)
>     - `cmd/kacho-iam/w1_2_wiring.go` (dial-out clients to api-gateway internal mux already exists; replace `insecure.NewCredentials()` placeholder with Workload API X.509 source creds — annotated `// Production path: real mTLS. For now we still use insecure as a placeholder`)
>     - NEW `internal/spire/source.go` — thin wrapper around `github.com/spiffe/go-spiffe/v2/workloadapi.NewX509Source` + refresh-on-rotation observability + fail-closed-on-init policy
>     - NEW `internal/spire/grpc.go` — `ServerCreds(src) credentials.TransportCredentials` + `ClientCreds(src, expectedTrustDomain) credentials.TransportCredentials` helpers (re-export wrappers around `grpccredentials.MTLSServerCredentials` / `MTLSClientCredentials` with kacho-specific identity matchers)
>     - `internal/observability/spire_metrics.go` (NEW — prometheus counters/gauges: SVID expiry timestamp, refresh-fail counter, peer-handshake counters per source-SPIFFE-ID)
>   - **Secondary (peer-services that dial kacho-iam internal listener)**: same `internal/spire/` thin wrappers, swap `insecure.NewCredentials()` → Workload API source creds on dial.
>     - `PRO-Robotech/kacho-api-gateway` — `internal/clients/iam_internal_client.go` (dial-out for authz-cache invalidate + `InternalIAMService.Check`)
>     - `PRO-Robotech/kacho-vpc` — `internal/clients/iam_client.go` (per-RPC authz Check via internal listener)
>     - `PRO-Robotech/kacho-compute` — `internal/clients/iam_client.go` (same)
>     - **Out of scope for W3.3**: NLB / loadbalancer clients (whole service deferred per master plan); UI-admin (browser-bridge, not pod-to-pod).
>   - **Deploy**: `PRO-Robotech/kacho-workspace/project/kacho-deploy` —
>     - `helm/umbrella/spire-registration/kacho-iam.yaml` — already exists (`spiffe://{{ trustDomain }}/ns/kacho-system/sa/kacho-iam`); **extend** with explicit `kacho-iam-worker` Deployment if separate worker pod exists (KAC-127 W1.1 outbox-drainer — see W1 acceptance; today it runs in same `kacho-iam` Deployment, so single SPIFFE-ID is sufficient — VERIFY at impl-start, OQ-W3.3-3)
>     - `helm/umbrella/charts/cilium/templates/cilium-mtls-enforce.yaml` — already enforces mTLS on ports 9090/9091 for `kacho.cloud/mesh-enabled=true` pods; **add** kacho-iam-specific `CiliumNetworkPolicy` (separate file `helm/umbrella/charts/cilium/templates/kacho-iam-ingress-allowlist.yaml`) for SPIFFE-ID source-allowlist on port 9091
>     - `helm/umbrella/charts/kacho-iam/values.yaml` + `templates/deployment.yaml` — add `kacho.cloud/mesh-enabled: "true"` pod label (if missing); add `SPIFFE_ENDPOINT_SOCKET=unix:///run/spire/sockets/agent.sock` env; mount `spire-agent-socket` hostPath volume (DaemonSet exposes it)
>     - `helm/umbrella/values.yaml` — config flag `spire.kacho_iam.required: true` (fail-closed on init when SVID source unavailable) for staging/prod; `false` for dev-kind to allow rapid iteration without SPIRE running
>   - **NOT touched**: `kacho-proto` (no new RPC, no new proto field — SVID + trust bundle are runtime credentials, not API surface, per `CLAUDE.md` §«Инфра-чувствительные данные»); `kacho-corelib` — see OQ-W3.3-5 (recommendation: add thin `corelib/spire/` package after kacho-iam wiring lands, as second consumer — vpc/compute — joins; W3.3 keeps it iam-local first iteration). Migration storage: **no new DB migration**.
> **Branch (kacho-iam)**: `KAC-<W3.3-issue-id>` (off `main`).
> **Branch (deploy)**: same KAC-id in `kacho-deploy`.
> **Branch (vpc / compute / api-gateway)**: same KAC-id in each — but **gated** on kacho-iam server-side cutover (see §5.5 sequencing).
> **Master plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 3 row («SPIRE+Cilium wiring kacho-iam за SVID») + §Decisions «SPIRE: В scope (charts есть, wiring остаётся)».
> **Production launch plan**: `docs/superpowers/plans/2026-05-21-production-launch-plan.md` DECISION-MESH («SPIRE+Cilium» — initially descoped from prod-v1; reintroduced in W3 per master-plan decision).
> **Predecessor specs**:
>   - **W2.B.10 (Enterprise SPIRE-mTLS Block B item 10)** — defines protocol-level mTLS mesh policy expectations (SPIFFE-ID schema for ALL kacho-* services, trust domain selection, cosign supply-chain selector). **MUST be APPROVED + merged before W3.3 impl starts**. If W2.B.10 has not run yet, W3.3 carves out kacho-iam-only subset and the cross-service allowlist (§5.3) is reduced to placeholders that fail-closed pending B.10. See §0.2 «Predecessor verification».
>   - **W1.4** (principal propagation cross-service) — **MERGED** ([[KAC-140]]). Required because once kacho-iam internal listener requires mTLS, peer-services must also propagate caller identity at app-layer; SVID gives the *workload* identity (which **service** is calling), principal-propagation gives the *end-user* identity (which user the request acts on behalf of). Both are needed: SVID = "this is api-gateway calling", principal-propagation = "and the original user is `usr_alice`".
>   - **W3.2** (observability dashboards/alerts) — **NOT a hard predecessor** but W3.3 emits 4 new prometheus metrics that W3.2 dashboards should later display. If W3.2 lands first, W3.3 just adds metrics; if W3.3 lands first, W3.2 picks them up.
>
> **Why W3.3 matters**: today kacho-iam's internal listener (port 9091) is **insecure** — `w1_2_wiring.go:70-75` literally says `// Production path: real mTLS. For now we still use insecure as a placeholder`. The internal listener carries all admin-tooling RPCs (`InternalIAMService.Check` for per-RPC authz, `SessionRevocationsService.Push`, `InternalBreakGlassService`, `GdprErasureService`, `InternalUserService.UpsertFromIdentity`, `InternalIamHooksService.Notify*`) — every one of these is privileged. Any pod that can reach the cluster-internal Service IP can call them with **no authentication** ([[CLAUDE.md]] §«Запреты» #6 is enforced at the **network-segregation** level only — separate listener — but the gRPC handshake itself is plaintext). W3.3 closes this gap by binding kacho-iam pod identity to a SPIRE-issued X.509 SVID, exposing the listener with mTLS using that SVID, and applying a `CiliumNetworkPolicy` that only allows known SPIFFE-IDs through to port 9091 at the L4 + L7 levels.

---

## 0. Преамбула — current state, desired state, why both layers

### 0.1 Current state (2026-05-24)

| Surface | Current credentials | Authentication of caller |
|---|---|---|
| **Public listener** `:9090` (kacho-iam) | Plaintext gRPC | Per-RPC JWT (Hydra access token) via `UnaryPrincipalExtract` interceptor + (where wired) gateway authz-middleware (W1.3) |
| **Internal listener** `:9091` (kacho-iam) | **Plaintext gRPC** | No anti-anonymous interceptor on internal (`main.go:246-252` — `// admin tooling и setup-jobs ходят через internal без auth-context`); No mTLS — any pod with network reach can call privileged RPCs |
| **Hooks HTTP** `:HOOKS_PORT` (kacho-iam) | Plaintext HTTP | Webhook secret / DPoP — out-of-scope for W3.3 |
| **Cilium ClusterwidePolicy** (`cilium-mtls-enforce.yaml`) | Configures mTLS authentication mode `required` for egress from `kacho.cloud/mesh-enabled=true` pods to peer-pods on ports 9090/9091 | **Already enforces SPIFFE mTLS at L4** for east-west kacho-* traffic when `mtlsEnforcePolicy.enabled=true` — but **only the Cilium-managed transparent mTLS layer**; the **gRPC server in the pod still terminates plaintext** because Cilium-mTLS is sidecar-less and tunnels through the kernel, presenting a localhost-loopback plaintext socket to the workload. So even with policy enforced, the **gRPC handshake** at the app layer is still plaintext (defense-in-depth gap). |
| **api-gateway → kacho-iam internal dial** (`w1_2_wiring.go:70-75`) | `insecure.NewCredentials()` — explicit `// For now we still use insecure as a placeholder` | None at gRPC layer |
| **vpc / compute → kacho-iam internal dial** | Same — `insecure.NewCredentials()` (verified at impl-start, see §0.2 task A1) | None at gRPC layer |
| **SPIRE Server (HA, 2 replicas)** | Deployed via `charts/spire-server/` (KAC-127 Phase 10) | — |
| **SPIRE Agent (DaemonSet, one per node)** | Deployed via `charts/spire-agent/` | — |
| **Existing SPIFFE registration entries** (`spire-registration/kacho-*.yaml`) | YAML manifests with `spiffe://{{ trustDomain }}/ns/kacho-system/sa/<svc>` and k8s_psat + cosign selectors | Applied as `SpiffeID` CRDs by `spire-server-register-job` |

### 0.2 Desired state after W3.3

| Surface | Desired credentials | Authentication of caller |
|---|---|---|
| **Public listener** `:9090` (kacho-iam) | **Unchanged** — plaintext gRPC + JWT-bearer | (Out of W3.3 scope — terminates Hydra-issued JWT; if we add mTLS to public, that's a separate epic for tenant-cert-management — descoped per [[KAC-127]] decision «no external domain for v1») |
| **Internal listener** `:9091` (kacho-iam) | **mTLS, SVID-based** via SPIRE Workload API; trust bundle from same source; SVID rotates auto every 30min (50% of 1h TTL) | gRPC server creds `MTLSServerCredentials(src)` accepts only peer SVIDs from trust domain `kacho.cloud` AND matching app-layer SPIFFE-ID allowlist (api-gateway, vpc, compute) |
| **Cilium ingress allowlist for `:9091`** (`kacho-iam-ingress-allowlist.yaml`, NEW) | `CiliumNetworkPolicy` with `fromEndpoints` matching only allowed source SPIFFE-IDs (declarative L7/SPIFFE filter on top of Cilium-mTLS) | Belt-and-suspenders: random pod attempting to reach `:9091` is **dropped at L4 before even reaching the gRPC handshake** (visible in hubble flow logs as `policy-denied`) |
| **api-gateway / vpc / compute → kacho-iam internal dial** | `MTLSClientCredentials(src, expectedTD="kacho.cloud", expectedServerSPIFFEID="spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam")` | Server presents its SVID; client validates trust-bundle-signed and SPIFFE-ID matches expected → handshake succeeds; otherwise dial fails-closed |
| **SVID rotation** | Workload API push-notifies kacho-iam on rotation; in-process X509Source auto-swaps; existing TLS connections continue with old SVID until natural close; new connections use new SVID. **No restart needed** | — |
| **Observability** | 4 new metrics (`kacho_iam_spire_svid_expiry_seconds`, `kacho_iam_spire_svid_refresh_total{result=ok|fail}`, `kacho_iam_spire_handshake_total{result=ok|fail,peer_spiffe_id=...}`, `kacho_iam_cilium_ingress_denied_total{policy=...}` — last one from cilium hubble exporter, not iam binary) | Dashboard panel + alert if `svid_refresh_total{result=fail}` increases or `svid_expiry_seconds` < 600 (10min to expiry) for >5min |

### 0.3 Why both layers — SPIRE-app-mTLS AND Cilium-network-policy

**Question**: if Cilium-mTLS is already enforced on `:9091`, why also do in-app SVID-based mTLS?

**Answer** — defense-in-depth, three reasons:

1. **Cilium-mTLS is transparent — workload doesn't see the peer identity.** Cilium terminates the mTLS handshake in the eBPF data plane / kernel, and the app gets a plain TCP/HTTP/2 socket. The kacho-iam binary therefore cannot make **identity-aware decisions** at the app layer (e.g. "this is api-gateway calling — accept; this is bare-pod calling — reject"). With in-app SVID-based gRPC server creds, the app **sees** the peer's SPIFFE-ID in the gRPC context (via `peer.FromContext` + `peertls.PeerIDFromConn`), enabling per-RPC identity-aware authz (e.g. only api-gateway may push session-revocations; only vpc may call certain InternalIAM RPCs) — a logical extension, partially deferred to a follow-up but the **substrate is delivered here**.
2. **Cilium-mTLS depends on cluster networking; in-app mTLS doesn't.** If Cilium's mTLS pipeline degrades (eBPF map full, cilium-agent restart, kernel upgrade) the network-policy may temporarily fall back to plaintext (Cilium docs: depending on mode, default behaviour during ServiceMesh transitions). In-app mTLS continues to enforce even when Cilium is degraded. (Single-cluster v1: this is low-risk, but production-hardening warrants it.)
3. **Network policy != identity assertion at the app log/audit layer.** When kacho-iam writes an audit log entry "RPC X was called by peer Y", it must know **which workload** Y is. Cilium can tell us "the connection passed `from-endpoints: api-gateway`" but not from inside the app — the app needs to extract it from the TLS peer cert, which requires in-app TLS termination.

The two layers compose:
- **Cilium policy** = "is the source pod even **allowed to attempt** to reach :9091?" — L4 deny at packet-level; visible in hubble; no gRPC handshake even starts for denied peers; **policy enforcement metric**.
- **In-app mTLS** = "**which identity** does the source pod assert, and is the assertion cryptographically valid against the trust bundle?" — L7 deny at handshake-level; visible in iam binary logs; gRPC TLS handshake fails for invalid SVIDs; **identity attestation**.

Either alone leaves a gap; both together = production-grade hardening for the internal admin surface.

---

## 0.4 W3.3 НЕ включает

- **mTLS на kacho-vpc / kacho-compute / kacho-api-gateway internal listeners (their own server-side wiring)**. W3.3 wires kacho-iam **server-side** and the **client-side** of peers when **dialing kacho-iam**. Wiring vpc/compute/api-gateway own internal listeners with SPIRE = **separate epics per service** (see §10 «Out of scope»). The shape of work is identical, this acceptance doc serves as a template.
- **SPIRE federation cross-cluster**. Single-cluster scope here. Trust-domain bridging (multi-cluster Kachō prod) — future epic, depends on cross-cluster network model that's not yet decided.
- **Postgres TLS handshake** (kacho-iam → Postgres). Postgres connection currently runs `sslmode=disable` in dev/staging. mTLS to Postgres is a separate W3 sub-item (cert-manager-issued cert OR pg-spiffe-helper), distinct cert lifecycle, distinct trust chain. **Acknowledged as adjacent gap, not scoped here.**
- **mTLS on public listener `:9090`** (tenant-facing API). Tenants don't have SVIDs; mTLS here would require either: (a) per-tenant client certs (huge UX problem, no plan), (b) Web-PKI on the **edge** (Ingress/cert-manager — descoped per [[KAC-127]] "no external domain for v1"). Stays plaintext gRPC + JWT-bearer.
- **In-app per-RPC identity-aware authz** ("only api-gateway may push session-revocations"). The substrate (peer SPIFFE-ID accessible from gRPC context) is delivered; the **policy enforcement** decision per-RPC is a follow-up — see §10 «Future work» and OQ-W3.3-9.
- **Cosign supply-chain selector enforcement** beyond what existing `spire-registration/kacho-iam.yaml` already declares. The selector is already in the manifest; W3.3 doesn't add nor remove it, just verifies it works end-to-end.
- **JWT-SVID flow** for short-lived tokens between services. W3.3 uses X.509 SVID exclusively — JWT-SVIDs would be appropriate for HTTP/REST hops and async message authentication, neither of which is on the kacho-iam internal-listener path.
- **SPIRE Server / Agent chart changes**. Charts exist and are healthy per pre-condition. If chart bugs surface during impl, they get fixed via separate KAC tickets in deploy — out of W3.3 scope, blockers if discovered.
- **Removal of cluster-internal-only segregation** (запрет #6). mTLS does not replace network-segregation — both stay. Internal listener still binds on a separate port not advertised to external LB.
- **W3.2 dashboards / alert delivery**. Metrics emitted here, dashboards built there.
- **W3.4 freeze checklist** items beyond W3.3's own DoD.

### 0.5 Predecessor verification (must be checked at impl-start before any code)

| Task | Verifier | Pass criterion |
|---|---|---|
| **A1**: verify W2.B.10 (Enterprise SPIRE-mTLS protocol policy) has APPROVED acceptance doc + merged code. | Acceptance-author re-reads master plan, fetches W2 Block-B subtask state from YouTrack | If W2.B.10 not done — fork option: (i) **wait** (preferred — W3 is sequential after W2 per master plan dep graph) OR (ii) **carve out** kacho-iam-only subset and document trust-domain & SPIFFE-ID schema choices LOCALLY in W3.3 (OQ-W3.3-2). Acceptance-reviewer decides at review-time. |
| **A2**: verify SPIRE Server (2 replicas) + Agent DaemonSet are healthy on dev-kind. | `kubectl -n spire-system get pods` shows `Running 2/2 spire-server-*` + `Running` on each node for spire-agent | If unhealthy → BLOCKER; raise to deploy team. |
| **A3**: verify Cilium ServiceMesh is enabled + `cilium-mtls-enforce.yaml` applied + at least one existing pod (e.g. `kacho-api-gateway` from W2.B.10 cutover) has working SPIFFE auth | `cilium-cli connectivity test --hubble`; hubble shows mTLS-encrypted flows | If broken → BLOCKER. |
| **A4**: verify existing `helm/umbrella/spire-registration/kacho-iam.yaml` resolves to a valid `SpiffeID` CRD on the cluster and kacho-iam pod can read its SVID via `spire-agent api fetch x509 --socketPath /run/spire/sockets/agent.sock` (run inside the pod) | `kubectl exec -n kacho-system kacho-iam-<podid> -- spire-agent api fetch x509 …` returns a non-empty SVID | If fails: it's a chart/registration bug; fix in deploy first (block W3.3 impl). |
| **A5**: enumerate existing peer-services that dial kacho-iam internal `:9091` and grep for `insecure.NewCredentials()` in their `internal/clients/iam*.go`. Document the actual list in PR description. | `grep -rln "insecure.NewCredentials" project/kacho-*/internal/clients/` | Expected list: `kacho-api-gateway`, `kacho-vpc`, `kacho-compute`. If anything else surfaces — scope adjustment needed. |
| **A6**: trust domain confirmation — existing charts settle on `kacho.cloud` (default `values.yaml`) with per-env overrides `kacho.dev.cloud` / `kacho.staging.cloud`. The original W3.3 brief mentioned `kacho.local` — that is **not** the existing convention. Acceptance-reviewer ratifies `kacho.cloud` (OQ-W3.3-1). | Read `helm/umbrella/charts/spire-server/values.yaml:17` | OK to proceed with `kacho.cloud`. |

---

## 1. Связь с регламентом и запретами (нормативно)

| Регламент | Где соблюдаем |
|---|---|
| **Запрет #1** | gate данного doc; impl стартует только после APPROVED от `acceptance-reviewer`. |
| **Запрет #2** | в коде/комментариях/тестах не упоминается «yandex» — none of SPIRE/Cilium docs need that, but reviewer obligated to grep diff. |
| **Запрет #3** | no DB writes in W3.3 — no ORM concern. |
| **Запрет #4** | no cross-service DB cascade. SPIRE entries are k8s CRDs, not Postgres data. |
| **Запрет #5** | no DB migration. |
| **Запрет #6** | **THIS IS THE PRODUCTION HARDENING OF #6.** Запрет #6 prescribes that `Internal.*` lives on a separate listener and is not advertised externally — network segregation. W3.3 adds the **cryptographic identity attestation** layer on top: only known workload-SPIFFE-IDs may handshake on `:9091`. Запрет #6 stays in force (no Internal RPC moves to public listener); W3.3 strengthens it. |
| **Запрет #7** | no broker. |
| **Запрет #8** | DB-per-service unchanged. SPIRE Server has its own DB (k8s-managed); not a kacho data store. |
| **Запрет #9** | mutations unaffected — still return `*operation.Operation`. mTLS is transport, not contract. |
| **Запрет #10** (within-service refs DB-level) | N/A — no DB writes in W3.3. |
| **Запрет #11** (NO TODO / NO tech-debt) | **STRICT**. Current code says `// Production path: real mTLS. For now we still use insecure as a placeholder` — W3.3 **removes that placeholder**, no new TODO/`// TODO(KAC-X): switch to mTLS` may replace it. If a peer-service cutover slips out of scope, the PR for kacho-iam **does not merge** until **all** allowlisted peers have cutover PRs ready (see §5.5 sequencing — staged-rollout via dual-accept window, not via TODO).  |
| **Запрет #12** (test-first + tests-in-PR + RED→GREEN) | each of §6 scenarios is a RED test that drives a GREEN impl. **No integration test = no merge.** Integration tests run on `kind` cluster with real SPIRE — see §7. |
| **Запрет #13** (test-only PR ⇒ no product fix) | N/A — W3.3 is impl, not test-only. |
| **CLAUDE.md §«Инфра-чувствительные данные»** | **CRITICAL.** SVID, trust bundle, SPIRE Server URL, agent socket path = infra-credentials. NEVER expose via public proto/RPC. **All** SPIRE config lives in deployment YAML (`helm/umbrella/values.yaml`, k8s Secrets) and is read by the pod at startup via env / file. No SPIFFE-ID exposed in any tenant-facing API response. No trust-bundle PEM serialized in any RPC reply. Acceptance-reviewer obligated to grep diff for accidental exposure. |
| **CLAUDE.md §Within-service refs DB-level** | N/A. |
| **CLAUDE.md §«Принцип переиспользования через `kacho-corelib`»** | First iteration: helpers live in `internal/spire/` of kacho-iam (single consumer). When second service (vpc/compute) cuts over, **promote** to `kacho-corelib/spire/` (separate KAC ticket, ≤2hr work — see OQ-W3.3-5). Avoid corelib-promotion **on first use** (one consumer) per skill-evgeniy regulament D.3. |
| **CLAUDE.md §«API contract — flat resources + Operations»** | unchanged. |
| **Vault discipline** | NEW `obsidian/kacho/security/spire-spiffe-ids.md` (kacho-iam SPIFFE-IDs + selectors + trust domain); NEW `obsidian/kacho/security/cilium-mesh-policies.md` (cilium-mtls-enforce + kacho-iam-ingress-allowlist + interplay with SPIRE); UPDATE `obsidian/kacho/packages/iam-cmd.md` (workload-api source wiring); UPDATE `obsidian/kacho/edges/iam-internal-listener.md` (note: mTLS-protected via SVID; client-side allowlist for trust-domain + SPIFFE-ID); UPDATE `obsidian/kacho/architecture.md` (mesh diagram showing SPIRE Server / Agent / Workload-API socket / mTLS-protected internal listener). |
| **KAC-trail** | `obsidian/kacho/KAC/KAC-<W3.3-id>.md` created at branch-creation, updated on PR-merge per CLAUDE.md §«KAC-тикеты — обязательный trail». |

---

## 2. Глоссарий

- **SPIFFE** (Secure Production Identity Framework For Everyone) — vendor-neutral standard for workload identity in zero-trust networks. Defines a URI naming scheme (`spiffe://<trust-domain>/<path>`) and the format of identity documents (SVIDs).
- **SVID** (SPIFFE Verifiable Identity Document) — cryptographic identity issued to a workload. Two flavours:
  - **X.509 SVID**: an X.509 certificate with a single SAN URI of form `spiffe://<td>/<path>`; private key is the workload's; signed by trust domain CA. Used for **TLS handshake**. Lifetime typically 1h.
  - **JWT SVID**: a JWT with `sub: spiffe://<td>/<path>`; signed by trust domain CA. Used for **bearer-token auth**, HTTP, async messaging. **NOT used in W3.3.**
- **SPIRE Server** — central component that maintains trust-domain CA, issues SVIDs, holds registration entries (which selector matches which SPIFFE-ID). HA: ≥2 replicas with shared Postgres backend.
- **SPIRE Agent** — node-local daemon (DaemonSet) that: (a) attests the node to the Server via `k8s_psat` (k8s Projected Service Account Token), (b) attests each workload pod by selectors (k8s ns/sa/labels/cosign/etc), (c) fetches that workload's SVID from Server, (d) exposes the **Workload API** Unix socket on the node so workload pods can read their SVID.
- **Workload API** — gRPC-over-Unix-socket API (`unix:///run/spire/sockets/agent.sock`) that the agent exposes; workloads call `FetchX509SVID` / `WatchX509Context` to get their identity + trust bundle and receive push updates on rotation.
- **trust bundle** — set of CA certificates for a trust domain; used to validate peer SVIDs. Each SPIRE-aware workload has its own copy, refreshed via Workload API watch.
- **k8s_psat selector** — `(type: k8s_psat, value: …)` SPIRE selector type that attests a pod by its k8s identity: namespace, service account, pod labels, etc. Verified via API server PSAT projection.
- **X.509 SVID vs JWT SVID** — see above; W3.3 = X.509 (TLS handshake).
- **mTLS** (mutual TLS) — TLS where both client and server present certificates. Both sides verify the other's cert against a trust anchor; identity is asserted bidirectionally.
- **CiliumNetworkPolicy / CiliumClusterwideNetworkPolicy** — k8s-CRD network-policy resources from Cilium, supporting both standard k8s NetworkPolicy and SPIFFE-aware authentication (`authentication.mode: required` ⇒ enforce mTLS between matched endpoints).
- **hubble** — Cilium's network-flow observability layer; emits per-flow events visible via `hubble observe` CLI or `hubble-relay`-fed UI/exporter.
- **`go-spiffe/v2`** — official Go SDK for SPIFFE workload integration. Provides `workloadapi.X509Source` (long-running source with auto-refresh) + `tlsconfig.MTLSServerConfig`/`MTLSClientConfig` + `grpccredentials.MTLSServerCredentials`/`MTLSClientCredentials`.
- **trust domain** — string identifying a SPIRE deployment's identity boundary; here `kacho.cloud` per existing chart default (dev: `kacho.dev.cloud`, staging: `kacho.staging.cloud`).
- **SPIFFE-ID matcher** — at the gRPC creds layer, an `Authorizer` callback that decides whether a presented peer SVID is acceptable (e.g. `tlsconfig.AuthorizeID(expectedID)` or `AuthorizeMemberOf(td)`).
- **fail-closed-on-init** — policy: if SVID source cannot be established at process startup, the binary refuses to start (instead of falling back to plaintext). Configurable per environment via `spire.kacho_iam.required` flag — dev=`false` (rapid iteration without SPIRE), staging/prod=`true`.

---

## 3. Decisions (fixed; revisit only with explicit ratification)

| ID | Decision | Rationale |
|---|---|---|
| **D-W3.3-1** | **X.509 SVID** (not JWT SVID) for kacho-iam internal listener mTLS. | Internal listener is **gRPC over HTTP/2**; X.509 fits as `credentials.TransportCredentials` directly through go-spiffe SDK. JWT-SVIDs would require bearer-token interceptor + clock skew handling + key rotation logic at app layer — needless complexity for a TLS handshake. JWT-SVIDs reserved for HTTP/REST + async message paths (post-W3.3). |
| **D-W3.3-2** | **Trust domain `kacho.cloud`** (per existing chart defaults; per-env overrides `kacho.dev.cloud` / `kacho.staging.cloud`). | Existing infra has already chosen this; brief mentioned `kacho.local` but that's not the existing convention (verified in `helm/umbrella/charts/spire-server/values.yaml:17`). Switching trust domain now would require recursive update of all existing SpiffeRegistration manifests (`kacho-api-gateway`, `kacho-compute`, `kacho-vpc`, etc.) — needless churn. |
| **D-W3.3-3** | **SVID lifetime 1h, refresh at 50% (30min)**. | Standard SPIRE recommendation. Auto-refresh handled by `workloadapi.NewX509Source` — no app-layer scheduling needed. Refresh failures → alert (W3.2). Lifetime 1h = compromised-key blast radius bounded. |
| **D-W3.3-4** | **Cilium policy = explicit allow-list of source SPIFFE-IDs per ingress port; default deny**. | Per `CLAUDE.md` §«Запреты» #6 spirit + zero-trust default. Allowlist for `:9091` = `[api-gateway, vpc, compute]`. Anything else dropped. Allowlist for `:9090` deferred (public listener — tenants don't have SVIDs; no L7 SPIFFE filter). |
| **D-W3.3-5** | **fail-closed-on-init for staging/prod**, **fail-open-with-log for dev-kind** (`spire.kacho_iam.required: bool`). | Staging/prod: if SVID source cannot be established, refuse to start — prevents silently degrading to plaintext (запрет #6 spirit). Dev-kind: developers may not always run SPIRE locally — allow startup with plaintext but with `LOG.ERROR` and `kacho_iam_spire_init_failed_total` counter incremented. Reviewer obligated to ensure prod values.yaml sets `true`. |
| **D-W3.3-6** | **Server-side SPIFFE-ID matcher = `tlsconfig.AuthorizeMemberOf("kacho.cloud")`** (NOT per-peer-ID allowlist in server creds). | App-layer per-peer-ID enforcement is **delegated to the CiliumNetworkPolicy** (L4 filter — drop before handshake) AND optionally to per-RPC interceptor in a follow-up. Server-creds layer only validates "comes from a trusted trust-domain workload"; the allowlist of **which** workloads is enforced one layer up. Reason: easier to maintain single allowlist (in CiliumNetworkPolicy YAML) than two (here + creds.go). |
| **D-W3.3-7** | **Client-side SPIFFE-ID matcher = exact expected server ID `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam`**. | Client side knows exactly which server it's dialing → use `tlsconfig.AuthorizeID(expectedID)`. Defends against DNS-hijack / pod-spoof: even if a malicious pod somehow got the kacho-iam-service ClusterIP, it can't present the kacho-iam SPIFFE-ID. |
| **D-W3.3-8** | **In-process X509Source instance per binary** (NOT per-RPC re-fetch). | go-spiffe `workloadapi.NewX509Source` is designed for long-running use; it watches via Workload API and updates in-memory. Per-RPC fetch would re-establish unix socket connections needlessly. |
| **D-W3.3-9** | **Workload API socket = hostPath mount `unix:///run/spire/sockets/agent.sock`**. | Standard SPIRE deployment pattern. Agent DaemonSet exposes socket on hostPath; pods mount it read-only. **Security note**: this gives the pod's UID access to the Workload API for ANY workload registered on that node (the agent authenticates the workload by its own attestor — uid/gid/cgroup-based), so the socket alone isn't a privilege-escalation path; SPIRE attestor logic is the gate. |
| **D-W3.3-10** | **Operate metrics via prometheus client lib** (already used in iam binary per W3.2). | No new metrics framework. Naming: `kacho_iam_spire_*` prefix (consistent with `kacho_iam_*` namespace per existing observability). |

---

## 4. Open questions (DECISION-NEEDED) — must be resolved before impl-start

| ID | Question | Author recommendation |
|---|---|---|
| **OQ-W3.3-1** | Trust domain: brief said `kacho.local`; existing charts say `kacho.cloud` (default) with per-env overrides. Confirm `kacho.cloud`? | **Yes, ratify `kacho.cloud`.** Single source of truth = existing chart. Brief was approximation. |
| **OQ-W3.3-2** | Predecessor W2.B.10 status — is it done? If no, do we (a) wait, or (b) carve W3.3 as kacho-iam-only with placeholder allowlist for peers? | Verify at impl-start (§0.5 task A1). If not done → **wait** (master plan deps); if scheduling makes that infeasible, **carve out** with explicit annotation in PR description and follow-up KAC for full cross-service rollout. |
| **OQ-W3.3-3** | kacho-iam runs **one** Deployment? Or are there separate worker pods (e.g. `kacho-iam-worker` for outbox-drainer W1.1)? If separate, each needs its own SPIFFE registration entry. | Verify at impl-start via `kubectl get deploy -n kacho-system` on dev-kind. Current expectation: single Deployment `kacho-iam` runs both API + outbox-worker in same process (per existing CLAUDE.md §1 phasing). If split happens later, add second `SpiffeRegistration` then. |
| **OQ-W3.3-4** | Client-side SPIFFE-ID matcher: hardcoded constant `"spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam"` OR config-driven? | **Config-driven via env** `KACHO_IAM_INTERNAL_PEER_SPIFFE_ID` with sane default. Reason: per-env trust-domain (`kacho.dev.cloud` vs `kacho.cloud`) means hardcoded constant breaks per-env. Default = `spiffe://{{ trustDomain }}/ns/kacho-system/sa/kacho-iam` rendered at deploy-time by helm. |
| **OQ-W3.3-5** | Promote `internal/spire/` helpers to `kacho-corelib/spire/` immediately or wait until second consumer? | **Wait until second consumer** (per skill-evgeniy D.3 "DRY at the second use, not the first"). When vpc/compute internal-listener gets SPIRE'd (separate epic per §10), the second cutover PR promotes to corelib. W3.3 keeps it iam-local. |
| **OQ-W3.3-6** | Should the SVID-refresh-fail alert (W3.2) fire after 1 failure or 3 consecutive failures? Brief said 3 consecutive. | **3 consecutive** failures, evaluated over 5min. One transient fail (agent restart, network blip) shouldn't page; sustained fails do. Threshold tunable in W3.2 alert YAML. |
| **OQ-W3.3-7** | Trust-bundle rotation overlap window: how long does kacho-iam accept old-root-signed SVIDs while new root is rotating in? | **Honour SPIRE's bundle-update semantics** (Workload API push includes both old + new roots during overlap; `tlsconfig.MTLSServerConfig` validates against current bundle which contains both). No app-layer logic needed — go-spiffe handles it. Test: §6 W3.3-EDGE-04. |
| **OQ-W3.3-8** | Dev-kind: fail-open with log, OR fail-closed always (so dev hits failure early)? | **Fail-open with log** (D-W3.3-5). Dev-kind should not block contributors who don't have SPIRE running locally. Loud `slog.Error` + counter ensures the gap is visible. |
| **OQ-W3.3-9** | App-layer per-peer-ID authz interceptor (server side reads peer SVID from gRPC ctx, decides per-RPC) — in W3.3 or follow-up? | **Follow-up.** W3.3 delivers substrate (peer SPIFFE-ID extractable from `peer.FromContext(ctx)` + `peertls.PeerIDFromConn` — verify in integration test). Per-RPC policy decisions = separate KAC, after the catalog of "which workload may call which RPC" is reviewed (overlaps with [[KAC-127]] permission-catalog work). |
| **OQ-W3.3-10** | Hubble flow logs for denied flows — exported to where? VictoriaLogs (`vector.dev` per master-plan AUDIT decision)? | **Yes — VictoriaLogs**. Hubble-relay → vector.dev → VictoriaLogs. This is W3.2-adjacent — W3.3 documents the metric/log shape; W3.2 builds the dashboard panel. |

> **OQs are reviewer-blocking.** Impl does not start until OQ-W3.3-{1,2,3,4} are answered (these change PR shape directly). OQ-W3.3-{5..10} are implementation-detail with author recommendations — reviewer may accept recommendations without re-debate.

---

## 5. Implementation steps (impl spec, no code yet — code lives in PR commits)

### 5.0 Sequencing summary

```
A1-A6 (predecessor verification)
  ↓
Step 5.1: SPIRE registration YAMLs (deploy repo) — add kacho-iam (if missing fields) + verify it resolves
  ↓
Step 5.2: kacho-iam workload code — internal/spire/ helpers + main.go wiring (server-side ONLY first)
  ↓
Step 5.3: Cilium ingress policy YAML (deploy repo) — kacho-iam-ingress-allowlist.yaml
  ↓
Step 5.4: Helm chart kacho-iam updates — pod labels, env, volume mounts
  ↓
Step 5.5: Peer client cutover (api-gateway, vpc, compute) — STAGED, dual-accept window
  ↓
Step 5.6: Observability metric emit (kacho_iam_spire_*) + W3.2 dashboard handoff
  ↓
Step 5.7: Integration test in kind (real SPIRE) + scenarios from §6
  ↓
Step 5.8: Vault updates + KAC trail closure
```

### 5.1 SPIRE registration entries (deploy repo)

**File**: `kacho-deploy/helm/umbrella/spire-registration/kacho-iam.yaml` (already exists — see §0.1).

**Changes** (verify each at impl-start):

1. Confirm `spiffeId: "spiffe://{{ trustDomain }}/ns/kacho-system/sa/kacho-iam"` matches the SPIFFE-ID kacho-iam expects to receive. (Yes — verified.)
2. Confirm `selectors` include `(k8s, ns:kacho-system)` and `(k8s, sa:kacho-iam)`. (Yes — verified.)
3. Confirm `cosign` selector — `(cosign, image-signature:{{ cosignFingerprint }})` — is set with the actual fingerprint per env. If `cosignFingerprint` is unset/empty, **disable** the cosign selector for dev-kind (don't have signed images), keep it for staging/prod. Add commented-out alternative in YAML.
4. `dnsNames` — already declared (`kacho-iam.kacho-system.svc`, `…svc.cluster.local`). Confirm.
5. `ttl: 3600` — confirm (1h per D-W3.3-3).
6. **Add** `parentId` annotation comment explaining: `parentId` of `spire-agent` means the SPIRE Server delegates issuance to the agent on the node where this pod runs.
7. **No new file needed** unless OQ-W3.3-3 says there's a separate worker Deployment.

**Verification**: after `helm upgrade kacho-deploy`, `kubectl get spiffeid -n spire-system` shows entry; `kubectl exec -n kacho-system kacho-iam-<podid> -- spire-agent api fetch x509 …` returns SVID.

### 5.2 kacho-iam workload code

#### 5.2.1 NEW `internal/spire/source.go`

Pseudocode (signatures + library calls, not full impl):

```go
package spire

import (
    "context"
    "errors"
    "fmt"
    "log/slog"
    "os"
    "time"

    "github.com/spiffe/go-spiffe/v2/spiffeid"
    "github.com/spiffe/go-spiffe/v2/workloadapi"
)

// Source wraps workloadapi.X509Source with kacho-iam observability hooks
// and a fail-closed-on-init policy.
type Source struct {
    inner        *workloadapi.X509Source
    trustDomain  spiffeid.TrustDomain
    metrics      MetricsRecorder // injected; see internal/observability/spire_metrics.go
    log          *slog.Logger
}

// Config — read from env at startup; see helm chart values.yaml.
type Config struct {
    SocketPath    string        // KACHO_IAM_SPIRE_SOCKET (default: unix:///run/spire/sockets/agent.sock)
    TrustDomain   string        // KACHO_IAM_SPIRE_TRUST_DOMAIN (default: kacho.cloud)
    Required      bool          // KACHO_IAM_SPIRE_REQUIRED (default: true in staging/prod, false in dev)
    InitTimeout   time.Duration // KACHO_IAM_SPIRE_INIT_TIMEOUT (default: 10s)
}

func NewSource(ctx context.Context, cfg Config, metrics MetricsRecorder, log *slog.Logger) (*Source, error) {
    td, err := spiffeid.TrustDomainFromString(cfg.TrustDomain)
    if err != nil { return nil, fmt.Errorf("invalid trust domain: %w", err) }

    initCtx, cancel := context.WithTimeout(ctx, cfg.InitTimeout)
    defer cancel()

    src, err := workloadapi.NewX509Source(initCtx,
        workloadapi.WithClientOptions(workloadapi.WithAddr(cfg.SocketPath)),
    )
    if err != nil {
        metrics.RecordInitFailed()
        if cfg.Required {
            return nil, fmt.Errorf("spire init failed (required=true, fail-closed): %w", err)
        }
        log.Error("spire init failed; continuing with insecure (required=false, dev-only)",
            slog.String("error", err.Error()))
        return nil, nil // caller checks for nil and uses insecure creds
    }

    s := &Source{inner: src, trustDomain: td, metrics: metrics, log: log}

    // Background: emit svid_expiry metric every 30s.
    go s.observeLoop(ctx)

    return s, nil
}

// SVIDSource implements x509svid.Source interface for go-spiffe consumers.
func (s *Source) GetX509SVID() (*x509svid.SVID, error) {
    svid, err := s.inner.GetX509SVID()
    if err != nil {
        s.metrics.RecordRefreshFailed()
        return nil, err
    }
    return svid, nil
}

// TrustBundleSource — same.
func (s *Source) GetX509BundleForTrustDomain(td spiffeid.TrustDomain) (*x509bundle.Bundle, error) {
    return s.inner.GetX509BundleForTrustDomain(td)
}

// Close — flush + release Workload API socket.
func (s *Source) Close() error { return s.inner.Close() }

// observeLoop — emit svid_expiry_seconds metric every 30s.
func (s *Source) observeLoop(ctx context.Context) { /* … */ }
```

**Key library APIs used**:
- `workloadapi.NewX509Source(ctx, opts...)` — returns long-running source.
- `spiffeid.TrustDomainFromString(s)` — parse trust domain.
- `x509svid.Source`, `x509bundle.Source` — interfaces consumed by `tlsconfig.MTLSServerConfig` / `MTLSClientConfig`.

#### 5.2.2 NEW `internal/spire/grpc.go`

```go
package spire

import (
    "github.com/spiffe/go-spiffe/v2/spiffegrpc/grpccredentials"
    "github.com/spiffe/go-spiffe/v2/spiffetls/tlsconfig"
    "github.com/spiffe/go-spiffe/v2/spiffeid"
    "google.golang.org/grpc/credentials"
    "google.golang.org/grpc/credentials/insecure"
)

// ServerCreds — TLS creds for kacho-iam internal :9091 listener.
// Accepts only peer SVIDs from trust domain td.
// If src == nil (dev fail-open), returns insecure creds (with WARN log at caller).
func ServerCreds(src *Source) credentials.TransportCredentials {
    if src == nil {
        return insecure.NewCredentials()
    }
    return grpccredentials.MTLSServerCredentials(src, src, tlsconfig.AuthorizeMemberOf(src.trustDomain))
}

// ClientCreds — TLS creds for dialing kacho-iam internal :9091 from peer pods.
// Validates server SVID matches expectedID exactly.
func ClientCreds(src *Source, expectedID spiffeid.ID) credentials.TransportCredentials {
    if src == nil {
        return insecure.NewCredentials()
    }
    return grpccredentials.MTLSClientCredentials(src, src, tlsconfig.AuthorizeID(expectedID))
}
```

#### 5.2.3 `cmd/kacho-iam/main.go` — server-side wiring

**Before** (around `main.go:249`):

```go
internalSrv := grpcsrv.NewServer(
    grpc.ChainUnaryInterceptor(grpcsrv.UnaryPrincipalExtract()),
    grpc.ChainStreamInterceptor(grpcsrv.StreamPrincipalExtract()),
)
```

**After**:

```go
spireCfg := spire.ConfigFromEnv() // helper that reads KACHO_IAM_SPIRE_* env vars
spireSrc, err := spire.NewSource(ctx, spireCfg, spireMetrics, logger)
if err != nil { return err } // fail-closed if cfg.Required
defer spireSrc.Close()

internalSrv := grpcsrv.NewServer(
    grpc.Creds(spire.ServerCreds(spireSrc)),
    grpc.ChainUnaryInterceptor(grpcsrv.UnaryPrincipalExtract()),
    grpc.ChainStreamInterceptor(grpcsrv.StreamPrincipalExtract()),
)
```

Note: public listener (`grpcSrv` for `:9090`) is **unchanged** — stays plaintext + JWT-bearer.

#### 5.2.4 `cmd/kacho-iam/w1_2_wiring.go` — client-side wiring (dialing api-gateway internal mux)

**Before** (`w1_2_wiring.go:70-75`):

```go
dialOpts = append(dialOpts, grpc.WithTransportCredentials(insecure.NewCredentials()))
// Production path: real mTLS. For now we still use insecure as a placeholder
dialOpts = append(dialOpts, grpc.WithTransportCredentials(insecure.NewCredentials()))
```

**After**:

```go
gatewayID, err := spiffeid.FromString("spiffe://" + spireCfg.TrustDomain + "/ns/kacho-system/sa/kacho-api-gateway")
if err != nil { return err }
dialOpts = append(dialOpts, grpc.WithTransportCredentials(spire.ClientCreds(spireSrc, gatewayID)))
```

(Plus removal of the placeholder comment per запрет #11.)

#### 5.2.5 NEW `internal/observability/spire_metrics.go`

Prometheus collectors:

| Metric | Type | Labels | Description |
|---|---|---|---|
| `kacho_iam_spire_svid_expiry_seconds` | Gauge | none | Unix-time seconds until current SVID expires; <0 = expired |
| `kacho_iam_spire_svid_refresh_total` | Counter | `result=ok\|fail` | Workload API watch updates received |
| `kacho_iam_spire_handshake_total` | Counter | `result=ok\|fail`, `peer_spiffe_id` (label sanitised to k8s-style) | server-side: peer attempting mTLS handshake on `:9091` |
| `kacho_iam_spire_init_failed_total` | Counter | none | startup failures (dev fail-open scenario only) |

Wire into `MetricsRecorder` interface exposed to `internal/spire/source.go`.

### 5.3 Cilium ingress policy (deploy repo)

**NEW file**: `kacho-deploy/helm/umbrella/charts/cilium/templates/kacho-iam-ingress-allowlist.yaml`

```yaml
{{- if and .Values.enabled .Values.kachoIamIngressAllowlist.enabled }}
# W3.3 — explicit SPIFFE-ID allowlist for kacho-iam internal listener.
# Composes with cilium-mtls-enforce.yaml: that one enforces *any* SPIFFE mTLS
# on east-west kacho-* traffic; this one further restricts *which* SPIFFE-IDs
# may reach kacho-iam :9091 (the privileged internal admin surface).
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: kacho-iam-ingress-allowlist
  namespace: kacho-system
  labels:
    {{- include "cilium.labels" . | nindent 4 }}
spec:
  endpointSelector:
    matchLabels:
      app.kubernetes.io/name: kacho-iam
  ingress:
    # Public listener :9090 — open to mesh-enabled peers (tenant traffic
    # comes via Ingress, not via mesh policy; this rule covers UI/admin
    # paths that legitimately hit :9090 from in-cluster).
    - fromEndpoints:
        - matchLabels:
            kacho.cloud/mesh-enabled: "true"
      toPorts:
        - ports:
            - port: "9090"
              protocol: TCP
    # Internal listener :9091 — explicit SPIFFE-ID allowlist.
    - fromEndpoints:
        - matchLabels:
            kacho.cloud/mesh-enabled: "true"
            app.kubernetes.io/name: kacho-api-gateway
      toPorts:
        - ports:
            - port: "9091"
              protocol: TCP
      authentication:
        mode: "required"
    - fromEndpoints:
        - matchLabels:
            kacho.cloud/mesh-enabled: "true"
            app.kubernetes.io/name: kacho-vpc
      toPorts:
        - ports:
            - port: "9091"
              protocol: TCP
      authentication:
        mode: "required"
    - fromEndpoints:
        - matchLabels:
            kacho.cloud/mesh-enabled: "true"
            app.kubernetes.io/name: kacho-compute
      toPorts:
        - ports:
            - port: "9091"
              protocol: TCP
      authentication:
        mode: "required"
{{- end }}
```

**Values flag**: `helm/umbrella/values.yaml` adds `cilium.kachoIamIngressAllowlist.enabled: true` (default true for staging/prod; dev-kind override `false` until SPIRE wired for all peers).

### 5.4 Helm chart kacho-iam updates

**`helm/umbrella/charts/kacho-iam/templates/deployment.yaml`** — add to pod template:

```yaml
metadata:
  labels:
    app.kubernetes.io/name: kacho-iam
    kacho.cloud/mesh-enabled: "true"   # required for cilium-mtls-enforce match
spec:
  serviceAccountName: kacho-iam        # already exists; needed for k8s_psat selector
  volumes:
    - name: spire-agent-socket
      hostPath:
        path: /run/spire/sockets
        type: Directory
  containers:
    - name: kacho-iam
      env:
        - name: KACHO_IAM_SPIRE_SOCKET
          value: "unix:///run/spire/sockets/agent.sock"
        - name: KACHO_IAM_SPIRE_TRUST_DOMAIN
          value: {{ .Values.spire.trustDomain | quote }}
        - name: KACHO_IAM_SPIRE_REQUIRED
          value: {{ .Values.spire.required | quote }}
        - name: KACHO_IAM_INTERNAL_PEER_SPIFFE_ID
          value: "spiffe://{{ .Values.spire.trustDomain }}/ns/kacho-system/sa/kacho-api-gateway"
      volumeMounts:
        - name: spire-agent-socket
          mountPath: /run/spire/sockets
          readOnly: true
```

**`helm/umbrella/values.yaml`**:

```yaml
spire:
  trustDomain: kacho.cloud
  kacho_iam:
    required: true   # fail-closed in staging/prod; override to false in dev-kind values
```

Dev-kind override (`charts/kacho-iam/values-dev-kind.yaml`):

```yaml
spire:
  kacho_iam:
    required: false
```

### 5.5 Peer client cutover — STAGED, dual-accept window

**Sequencing problem**: if kacho-iam server-side cuts over to mTLS-only **before** all peers cut over their client-side, peers' RPC calls suddenly fail. If peers cut over first, they fail because server is still plaintext.

**Solution**: dual-accept window using config-flag staging — but per запрет #11 (no TODO / no tech-debt), this dual-accept must be **fully delivered in one PR**, not as a TODO.

**Approach**:

1. **PR-1 (kacho-iam)**: deliver server-side `spire.ServerCreds(src)` BUT default `spire.required=false` on dev-kind (fail-open + insecure creds when SVID source unavailable) AND ALSO default `spire.required=false` on a staging "shadow window" config flag. Server accepts EITHER mTLS-signed peers OR insecure peers during shadow window. **This `dual-accept` is the staged-cutover mechanism, NOT a TODO** — it's a documented, monitored, time-bounded state.
   - **Concretely**: server uses `tlsconfig.AuthorizeMemberOf(td)` mTLS creds when SVID present; falls back to insecure creds when src is nil. Internal listener can accept connections via either creds depending on what the client offers (Cilium-side TLS may or may not be enforced).
   - **Monitoring**: `kacho_iam_spire_handshake_total{result=plaintext_fallback}` counter increments per plaintext-accepted connection. Alert when count > 0 in staging/prod (immediate signal of mis-configured peer).
2. **PR-2..N (one per peer service)**: cut over client-side to `spire.ClientCreds(src, expectedID)`. Each peer PR: integration test in kind verifies handshake against staging kacho-iam works; merge.
3. **PR-FINAL (kacho-iam)**: flip `spire.required=true` in staging/prod; remove plaintext-fallback path from server creds (returning to strict mTLS-only on `:9091`). Verify `kacho_iam_spire_handshake_total{result=plaintext_fallback}` = 0 for ≥24h on staging before merging. **Removes the dual-accept code path entirely** (no dangling capability).

> **Запрет #11 satisfied**: the `dual_accept_window` mode is delivered as a complete, fully-tested config flag (not a TODO); PR-FINAL removes it; no "// TODO: remove dual-accept" comment ever exists. The total scope of W3.3 = PR-1 + PR-2..N + PR-FINAL, all committed in same KAC ticket, all merging in sequence with verifiable monitoring gate between each.

**Peer PR list** (verified at impl-start §0.5 task A5):

| Peer repo | File | KAC subtask |
|---|---|---|
| `kacho-api-gateway` | `internal/clients/iam_internal_client.go` | KAC-W3.3-AGW |
| `kacho-vpc` | `internal/clients/iam_client.go` | KAC-W3.3-VPC |
| `kacho-compute` | `internal/clients/iam_client.go` | KAC-W3.3-COMP |

### 5.6 Observability metric emission

**File**: `internal/observability/spire_metrics.go` (NEW). Registers 4 collectors per §5.2.5.

**W3.2 handoff doc**: append to `obsidian/kacho/security/spire-spiffe-ids.md` a section "Metrics emitted" listing the 4 metrics, alert thresholds (per D-W3.3-3 + OQ-W3.3-6), and dashboard panel sketch (timeseries svid_expiry, counter handshake-failures, counter refresh-failures).

### 5.7 Integration test in kind

See §7.

### 5.8 Vault updates + KAC trail closure

See DoD §8.

---

## 6. Scenarios (Given-When-Then) — основа интеграционных тестов

> All scenarios except W3.3-INIT-DEV use **real SPIRE** in a kind cluster. Setup: bring up kind via `kacho-deploy/Makefile dev-up` → wait for `spire-server` + `spire-agent` ready → register kacho-iam SPIFFE entry via existing `SpiffeRegistration` CRD → deploy kacho-iam with W3.3 changes → run scenarios via `kubectl exec` of a test-driver pod.

### 6.1 Server-side: kacho-iam exposes mTLS-protected :9091

#### Сценарий W3.3-POS-01 — kacho-iam pod starts and fetches SVID

**ID**: W3.3-POS-01 (closes "kacho-iam wires SVID")

**Given** SPIRE Server + Agent healthy on kind cluster
**And** `SpiffeRegistration` `kacho-iam` resolved to `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam`
**And** kacho-iam Deployment applied with W3.3 changes (env, volume, label)

**When** kacho-iam pod starts

**Then** within init-timeout (10s default), pod logs show `spire init success, trust_domain=kacho.cloud, svid_path=spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam`
**And** `kacho_iam_spire_svid_expiry_seconds` gauge reports ~3600 (1h SVID lifetime)
**And** `kacho_iam_spire_init_failed_total` = 0
**And** internal listener bound on `:9091` accepting TLS (verifiable via `openssl s_client -connect kacho-iam:9091` showing SPIFFE-ID in cert SAN)

---

#### Сценарий W3.3-POS-02 — allowed peer with valid SVID connects and RPC succeeds

**ID**: W3.3-POS-02 (closes "happy peer-to-iam mTLS")

**Given** W3.3-POS-01 GREEN
**And** a peer pod `test-api-gateway-driver` registered as `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-api-gateway` with same selectors pattern (via test SpiffeRegistration)
**And** test-driver pod runs a gRPC client with `spire.ClientCreds(src, expectedID="spiffe://kacho.cloud/ns/kacho-system/sa/kacho-iam")`

**When** test-driver calls `InternalIAMService.Check(...)` (or any internal RPC) on kacho-iam `:9091`

**Then** gRPC handshake completes (server presents kacho-iam SVID; client validates against trust bundle; trust-domain matches; SPIFFE-ID matches expected)
**And** RPC returns expected response (functional behaviour unchanged)
**And** `kacho_iam_spire_handshake_total{result=ok, peer_spiffe_id="spiffe___kacho_cloud_ns_kacho_system_sa_kacho_api_gateway"}` increments by 1
**And** hubble flow log shows `verdict=FORWARDED` with `auth-required=true` on the flow (mTLS authenticated at Cilium layer too)

---

#### Сценарий W3.3-POS-03 — SVID rotation mid-flight does not disrupt service

**ID**: W3.3-POS-03 (closes "SVID rotation is transparent")

**Given** W3.3-POS-02 GREEN
**And** kacho-iam pod has been running ≥35min (so it's past 50% refresh point)
**Or** force-rotate via `spire-server entry update --ttl 60 …` to shorten TTL and trigger refresh

**When** Workload API push delivers new SVID to kacho-iam

**Then** `kacho_iam_spire_svid_refresh_total{result=ok}` increments
**And** `kacho_iam_spire_svid_expiry_seconds` gauge jumps back up to ~3600 (or new TTL)
**And** any in-flight RPC continues to completion without disconnect (verified via long-streaming RPC in test-driver — Watch-style if available, OR multiple sequential unary RPCs over kept-alive connection)
**And** new connections after rotation use new SVID (verified by peer client picking up new server cert chain on next handshake)
**And** no `slog.Error` lines about rotation

---

### 6.2 Server-side negatives

#### Сценарий W3.3-NEG-01 — peer without SVID (insecure client) is rejected

**ID**: W3.3-NEG-01 (closes "no SVID → no entry")

**Given** W3.3-POS-01 GREEN (server fully strict, dual-accept window CLOSED — i.e. PR-FINAL applied; `spire.required=true` AND plaintext-fallback path removed)
**And** a malicious-test pod that does NOT have a SPIFFE registration entry
**And** that pod attempts to dial kacho-iam `:9091` with `insecure.NewCredentials()`

**When** dial attempt made

**Then** TLS handshake fails (server rejects plaintext)
**And** dial returns transport-level error visible to client (e.g. `connection error: tls: first record does not look like a TLS handshake` or `EOF`)
**And** `kacho_iam_spire_handshake_total{result=fail, peer_spiffe_id="unknown"}` increments by 1
**And** server log line: `mTLS handshake failed: peer presented no certificate` (or equivalent go-tls error)

---

#### Сценарий W3.3-NEG-02 — peer with wrong-trust-domain SVID is rejected

**ID**: W3.3-NEG-02 (closes "trust domain enforcement")

**Given** kacho-iam server-side config trust_domain=`kacho.cloud`
**And** a test-driver pod with SVID `spiffe://other.example.com/ns/X/sa/Y` (registered against an intentionally-different-trust-domain SPIRE instance OR via mocked X509 source)

**When** dial kacho-iam `:9091`

**Then** TLS handshake fails (server's `AuthorizeMemberOf(kacho.cloud)` rejects)
**And** `kacho_iam_spire_handshake_total{result=fail, peer_spiffe_id="spiffe___other_example_com_…"}` increments
**And** server log: `mTLS authorize failed: SPIFFE-ID trust domain "other.example.com" not in allowed set ["kacho.cloud"]`

> **Note**: setting up two trust domains in same kind cluster is non-trivial. Acceptable alternative: stub the X509 source with `fakesource` package from go-spiffe test utilities, run as unit-integration (`go test` with fakesource server-side and client-side).

---

#### Сценарий W3.3-NEG-03 — Cilium policy drops unauthorized source pod at L4

**ID**: W3.3-NEG-03 (closes "Cilium denial is enforced")

**Given** `kacho-iam-ingress-allowlist.yaml` applied
**And** a random test pod NOT labelled `kacho.cloud/mesh-enabled=true` AND not matching any of allowed peer labels (`kacho-api-gateway`, `kacho-vpc`, `kacho-compute`)
**And** the random pod has network reach to kacho-iam Service IP

**When** random pod attempts TCP connect to kacho-iam `:9091`

**Then** connect fails at L4 (no SYN-ACK, no TLS handshake even starts)
**And** **before** kacho-iam binary sees anything — drop is at eBPF layer
**And** hubble flow log: `verdict=DROPPED, reason=policy-denied, source=<random-pod>, destination=<kacho-iam-pod>, port=9091`
**And** `kacho_iam_spire_handshake_total` does NOT increment (handshake never started)
**And** `kacho_iam_cilium_ingress_denied_total{policy=kacho-iam-ingress-allowlist}` increments (collected by hubble-relay → vector → VictoriaLogs pipeline; metric exposed via cilium-agent's prometheus port or hubble-relay sidecar)

---

### 6.3 Edge cases

#### Сценарий W3.3-EDGE-01 — SPIRE Server temporarily unreachable mid-flight

**ID**: W3.3-EDGE-01 (closes "graceful degradation on SPIRE outage")

**Given** kacho-iam running with valid SVID, expiry in 45min
**When** SPIRE Server is scaled to 0 (`kubectl scale sts/spire-server --replicas=0`) at T+0
**And** kacho-iam attempts SVID refresh at T+30min (50% TTL)

**Then** refresh fails — Workload API call returns error
**And** `kacho_iam_spire_svid_refresh_total{result=fail}` increments
**And** kacho-iam **continues serving** with current SVID (doesn't restart, doesn't reject new connections)
**And** `kacho_iam_spire_svid_expiry_seconds` continues decreasing
**And** if SPIRE Server scaled back to ≥2 before SVID expiry — refresh recovers, `…refresh_total{result=ok}` increments
**And** alert (W3.2) fires after 3 consecutive `…refresh_total{result=fail}` increments in 5min window (per OQ-W3.3-6)

---

#### Сценарий W3.3-EDGE-02 — SVID expires before SPIRE recovery

**ID**: W3.3-EDGE-02 (closes "what if outage outlasts SVID")

**Given** W3.3-EDGE-01 state — SPIRE Server down for >1h
**When** SVID lifetime fully expires

**Then** existing connections continue (TLS sessions are long-lived; expiry only affects new handshakes)
**And** new connection attempts from peers fail TLS handshake (server presents expired cert; client's `tlsconfig.MTLSClientConfig` rejects)
**And** `kacho_iam_spire_svid_expiry_seconds` < 0 (negative)
**And** P0 alert fires (separate from refresh alert — `svid_expired` distinct metric or threshold rule)
**And** when SPIRE Server restored — kacho-iam pod must restart OR re-trigger SVID fetch (whichever is the SDK behaviour); test verifies recovery time

> **Mitigation note**: SVID expiry mid-outage is a known SPIRE limitation. Operational runbook (W3.2) should document: if SPIRE outage approaches 50min, pre-emptively drain kacho-iam traffic OR extend SVID TTL temporarily via `spire-server entry update`.

---

#### Сценарий W3.3-EDGE-03 — peer client cannot reach Workload API socket

**ID**: W3.3-EDGE-03 (closes "peer-side init failure during cutover")

**Given** PR-2 (api-gateway cutover) deployed
**And** api-gateway pod missing the `spire-agent-socket` volume mount (deployment misconfig)

**When** api-gateway pod attempts `spire.NewSource(...)` at startup

**Then** with `spire.required=true` (staging/prod) — pod fails to start with explicit log `spire init failed: dial unix:///run/spire/sockets/agent.sock: no such file or directory`
**And** with `spire.required=false` (dev-kind) — pod starts with WARN log + `kacho_iam_spire_init_failed_total` increments
**And** api-gateway → kacho-iam dials with `insecure.NewCredentials()` (fall-through)
**And** kacho-iam server-side rejects (per W3.3-NEG-01) because dual-accept window is closed in prod

> **Test value**: ensures helm chart misconfigurations are caught loudly, not silently.

---

#### Сценарий W3.3-EDGE-04 — trust-bundle (root CA) rotation overlap window

**ID**: W3.3-EDGE-04 (closes "root CA rotation is transparent")

**Given** SPIRE Server bundle (trust-bundle root CA) is rotated (e.g. via `spire-server bundle set --id … --path new-bundle.pem`)
**And** during overlap, bundle contains BOTH old-root and new-root certs

**When** Workload API pushes new bundle to kacho-iam pod
**And** a peer dials with SVID still signed by **old** root (rotation hasn't reached it yet)
**And** a different peer dials with SVID signed by **new** root

**Then** kacho-iam server accepts BOTH (because trust bundle now contains both roots; `tlsconfig.MTLSServerConfig` validates peer cert against current bundle)
**And** after overlap window closes (old root removed from bundle), only new-root SVIDs accepted
**And** no app-layer code in kacho-iam needs special handling — go-spiffe's `X509Source` + `tlsconfig` handle it

> **Test setup**: simulate via go-spiffe test-fakes if true root rotation on kind is too heavyweight.

---

#### Сценарий W3.3-EDGE-05 — config flag dev fail-open path actually fails open

**ID**: W3.3-INIT-DEV (closes D-W3.3-5 dev fallback)

**Given** dev-kind values: `spire.kacho_iam.required=false`
**And** SPIRE Server is intentionally NOT deployed (developer's local without SPIRE)

**When** kacho-iam pod starts

**Then** `NewSource` returns `nil, nil` after init-timeout
**And** `kacho_iam_spire_init_failed_total` = 1
**And** ERROR-level log: `spire init failed; continuing with insecure (required=false, dev-only)`
**And** internal listener `:9091` bound with `insecure.NewCredentials()`
**And** RPCs work (existing dev workflow unbroken)

> **Reviewer obligation**: verify staging/prod helm values set `required=true`; reject PR if any non-dev env has `false`.

---

#### Сценарий W3.3-EDGE-06 — staged dual-accept window (PR-1 to PR-FINAL transitional state)

**ID**: W3.3-EDGE-DUAL (closes §5.5 staged cutover)

**Given** PR-1 deployed (kacho-iam with dual-accept mode — accepts both mTLS-and-plaintext peers; `kacho_iam_spire_handshake_total{result=plaintext_fallback}` metric exposed)
**And** PR-2 (api-gateway) NOT yet deployed (still dialing with `insecure.NewCredentials()`)

**When** api-gateway dials kacho-iam `:9091`

**Then** connection succeeds (server falls back to insecure when peer offers no TLS)
**And** `kacho_iam_spire_handshake_total{result=plaintext_fallback}` increments
**And** alert fires in staging/prod (this is intentional during dual-accept; alert documents the in-flight cutover state in W3.2 runbook)

**When** PR-2 deploys (api-gateway upgrades to mTLS client)

**Then** subsequent dials use mTLS; `…{result=ok}` increments; `…{result=plaintext_fallback}` stops incrementing
**And** PR-FINAL gate: `kacho_iam_spire_handshake_total{result=plaintext_fallback}` flat for ≥24h → safe to merge PR-FINAL (remove fallback)

---

### 6.4 Substrate verification for follow-up

#### Сценарий W3.3-PROP-01 — peer SPIFFE-ID is extractable from gRPC context (substrate for OQ-W3.3-9)

**ID**: W3.3-PROP-01 (closes "substrate for per-RPC identity-aware authz")

**Given** W3.3-POS-02 GREEN
**And** a temporary debug interceptor on kacho-iam internal listener that logs the peer SPIFFE-ID from `peer.FromContext(ctx)` + `peertls.PeerIDFromConn` (or `grpccredentials.PeerIDFromContext` from go-spiffe SDK)

**When** test-driver pod calls any RPC

**Then** server log line shows extracted SPIFFE-ID == `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-api-gateway`
**And** this confirms the substrate is in place for follow-up KAC to implement per-RPC policy enforcement (e.g. only api-gateway may call `SessionRevocationsService.Push`)

> **Note**: the debug interceptor is **for the test only** and is removed before PR merge. The substrate (peer-ID extractability) is a property of the gRPC creds layer, not new code in iam.

---

## 7. Test plan

### 7.1 Integration test on kind cluster (REQUIRED)

**Location**: `kacho-deploy/tests/spire-iam-mtls/` (NEW test dir; not pure Go testcontainers — needs real SPIRE Server + Agent + Cilium running, so test driver = bash + kubectl + go-spiffe test-client binary).

**Phases**:

1. **Setup**: `make dev-up` (bring up kind + helm umbrella with SPIRE + Cilium + kacho-iam W3.3-enabled)
2. **Wait**: pods Ready (`kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=spire-server -n spire-system`, same for `spire-agent`, `kacho-iam`)
3. **Register test-driver SVID**: create `SpiffeRegistration` `test-driver-as-api-gateway` mapping to `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-api-gateway` with selectors matching a test-driver Deployment
4. **Deploy test-driver pod**: tiny Go binary using `go-spiffe` + kacho-iam-proto, calls `InternalIAMService.Check` against `kacho-iam:9091`
5. **Run scenarios** W3.3-POS-01..03, W3.3-NEG-01..03, W3.3-EDGE-01..06, W3.3-PROP-01
6. **Teardown**: `make dev-down`

**CI integration**: gate on `make spire-iam-mtls-test` Make target; runs in PR CI for kacho-iam, kacho-deploy, and peer-service PRs that touch `internal/clients/iam*.go`.

### 7.2 Unit tests (go test, fakesource-based)

Where kind-cluster setup is too heavyweight (W3.3-NEG-02 wrong-trust-domain, W3.3-EDGE-04 root rotation), use go-spiffe `internal/test/fakespiffe` package to stub the Workload API in-process. Faster, runs in normal `go test ./...`.

### 7.3 Manual smoke (post-deploy)

After production deploy, manual smoke checklist:

1. `kubectl exec -n kacho-system kacho-iam-<podid> -- ls -la /run/spire/sockets/agent.sock` — verify socket mounted
2. `kubectl logs -n kacho-system kacho-iam-<podid> | grep "spire init"` — verify success line
3. `kubectl exec -n kacho-system kacho-api-gateway-<podid> -- nc -zv kacho-iam 9091` — verify TCP reachability
4. `hubble observe --to-label=app.kubernetes.io/name=kacho-iam --port 9091 --verdict FORWARDED --output jsonpb` — verify mTLS flows
5. `curl http://kacho-iam-metrics:9091/metrics | grep kacho_iam_spire_` — verify metrics exposed
6. Trigger an actual `InternalIAMService.Check` from api-gateway via real authz path (RPC under normal load) — verify response succeeds

### 7.4 Newman test plan

**Not applicable** — Newman tests black-box API surface via REST; SPIRE-mTLS is on the cluster-internal gRPC layer between pods. Newman would not exercise it. (Newman pods themselves dial the public `:9090` listener, which is unchanged.)

### 7.5 Load test (optional, recommend for W3.2 follow-up)

mTLS handshake adds ~1-3ms latency per new connection (well-known TLS handshake cost). With connection-pooling (gRPC's default), this is amortized across many RPCs. Verify at staging: p95 RPC latency before vs after mTLS — should be flat. Defer formal load test to W3.2.

---

## 8. Definition of Done

### 8.1 Per-deliverable

- [ ] **SPIRE registration entries** (§5.1): `kacho-iam.yaml` verified to resolve correctly; cosign selector configured per env; no orphan entries.
- [ ] **kacho-iam workload code** (§5.2):
  - [ ] `internal/spire/source.go` implemented with `Source`, `Config`, `NewSource`, `Close`, fail-closed-on-init logic per D-W3.3-5
  - [ ] `internal/spire/grpc.go` implemented with `ServerCreds(src)` + `ClientCreds(src, expectedID)`
  - [ ] `cmd/kacho-iam/main.go` switches internal listener to `grpc.Creds(spire.ServerCreds(spireSrc))` — placeholder removed
  - [ ] `cmd/kacho-iam/w1_2_wiring.go` switches dial to `spire.ClientCreds(...)` — TWO instances of `// Production path: real mTLS. For now we still use insecure as a placeholder` comment + `insecure.NewCredentials()` REMOVED per запрет #11
  - [ ] `internal/observability/spire_metrics.go` implements 4 metrics
- [ ] **CiliumNetworkPolicy** (§5.3): `kacho-iam-ingress-allowlist.yaml` created in cilium chart templates; renders correctly via `helm template`; `kubectl apply --dry-run` GREEN
- [ ] **Peer-service updates** (§5.5): api-gateway/vpc/compute `internal/clients/iam*.go` switched to mTLS dial; per-repo PRs all merged before kacho-iam PR-FINAL flips strict mode
- [ ] **Helm chart updates** (§5.4): kacho-iam pod has `kacho.cloud/mesh-enabled=true` label, SPIRE env vars, agent-socket volume mount; values.yaml has `spire.required` flag per env

### 8.2 Test coverage

- [ ] All §6 scenarios implemented and GREEN in CI
- [ ] Integration test `make spire-iam-mtls-test` GREEN in kacho-deploy CI
- [ ] Unit tests (W3.3-NEG-02, W3.3-EDGE-04) GREEN in kacho-iam CI
- [ ] **RED phase commit evidence**: PR description shows for each scenario a "RED (before impl)" output (test name + failure message — e.g. `Test_SpireServerCreds_RejectsInsecurePeer FAIL: dial succeeded but expected TLS error`) + "GREEN (after impl)" success line. Per запрет #12.
- [ ] Coverage of new `internal/spire/` package ≥ 80% per `go test -cover`

### 8.3 Cutover safety gates

- [ ] PR-1 deployed to dev-kind → all existing iam-* newman + integration tests GREEN (no regression)
- [ ] PR-1 deployed to staging → `kacho_iam_spire_init_failed_total` = 0, `kacho_iam_spire_svid_expiry_seconds` ~ 3600
- [ ] Each peer-PR deployed in sequence; `kacho_iam_spire_handshake_total{result=plaintext_fallback}` decreases monotonically as peers cut over
- [ ] Pre-PR-FINAL gate: `…{result=plaintext_fallback}` = 0 for ≥24h in staging
- [ ] PR-FINAL deployed → dual-accept window closed; W3.3-NEG-01 GREEN on staging (insecure peer cannot connect)
- [ ] hubble flow logs verified: all mesh flows to `:9091` show `auth-required=true`, `verdict=FORWARDED`; no `verdict=DROPPED` from legitimate peers

### 8.4 Observability + W3.2 handoff

- [ ] 4 metrics emitted; visible in VictoriaMetrics (`{__name__=~"kacho_iam_spire_.*"}` query returns series)
- [ ] Hubble logs flowing to VictoriaLogs via vector.dev
- [ ] W3.2 dashboard PR (separate KAC, in W3.2 work) references the 4 metrics; alert rules drafted per OQ-W3.3-6 (3 consecutive refresh fails in 5min) + SVID expiry < 600s sustained 5min

### 8.5 Documentation + vault

- [ ] NEW `obsidian/kacho/security/spire-spiffe-ids.md` — table of SPIFFE-IDs per service (start with kacho-iam; future epics extend); trust domain naming; selector schema
- [ ] NEW `obsidian/kacho/security/cilium-mesh-policies.md` — cilium-mtls-enforce + kacho-iam-ingress-allowlist composition; SPIFFE-ID allowlist rationale
- [ ] UPDATE `obsidian/kacho/packages/iam-cmd.md` — note: workload-api source wired in main.go for internal :9091; reference §5.2.3
- [ ] UPDATE `obsidian/kacho/edges/iam-internal-listener.md` (create if missing) — mTLS-protected via SVID; client allowlist by SPIFFE-ID + trust domain; references CiliumNetworkPolicy
- [ ] UPDATE `obsidian/kacho/architecture.md` — add mesh-diagram section showing: SPIRE Server (HA) → SPIRE Agent (DaemonSet, per-node) → Workload API socket → kacho-iam-pod → mTLS-protected :9091 → peer pods (api-gateway/vpc/compute) with their own SVIDs
- [ ] CREATE `obsidian/kacho/KAC/KAC-<W3.3-id>.md` (per CLAUDE.md vault discipline) — status, repos, PRs, acceptance checklist
- [ ] UPDATE `kacho-iam/CLAUDE.md` §10 "Top-N gotchas" — note: internal listener requires SVID, dev-kind fail-open behaviour, peer-cutover sequencing

### 8.6 YouTrack + git hygiene

- [ ] `KAC-<W3.3-id>` issue created (parent: `KAC-iam-prod-ready` master epic, parent: Wave-W3 subtask)
- [ ] Issue moved To-do → In Progress on impl-start; → Test after PR-FINAL deploy to staging; → Done after 24h-clean window
- [ ] PR links in YT comment per repo (kacho-iam x2 — PR-1 + PR-FINAL; api-gateway, vpc, compute, kacho-deploy)
- [ ] Branches `KAC-<id>` deleted post-merge in each repo per CLAUDE.md §git-флоу
- [ ] Master plan `2026-05-23-iam-prod-ready-master.md` Wave-W3 row updated: "SPIRE+Cilium wiring kacho-iam за SVID" → ✅ done + date

### 8.7 Запреты parity

- [ ] No new TODO/FIXME in any diff (запрет #11 grep gate)
- [ ] No `yandex` mentions (запрет #2 grep gate)
- [ ] No new DB migration (запрет #5 — verified by no `*.sql` in any PR)
- [ ] Internal listener stays segregated from external (запрет #6 — verified by `:9090` plaintext unchanged, `:9091` not advertised on external LB)
- [ ] No broker introduced (запрет #7)
- [ ] No infra-credentials leak in proto/RPC surface (CLAUDE.md §«Инфра-чувствительные данные» grep gate: `git diff main -- '*.proto'` empty; `grep -r 'spiffe://\|SVID\|trust.bundle' kacho-proto/` returns no app-surface hits)
- [ ] Test-first evidence in PR description (запрет #12)

---

## 9. Vault entries — что создать / обновить

| Path | NEW or UPDATE | Content |
|---|---|---|
| `obsidian/kacho/security/spire-spiffe-ids.md` | NEW | SPIFFE-ID table; trust domain per-env; cosign selector policy; refresh interval; init policy |
| `obsidian/kacho/security/cilium-mesh-policies.md` | NEW | `cilium-mtls-enforce` (cluster-wide) + `kacho-iam-ingress-allowlist` (namespace); composition; how to add a new allowlisted peer; troubleshooting hubble |
| `obsidian/kacho/packages/iam-cmd.md` | UPDATE | Section "internal listener mTLS"; reference `internal/spire/` + `cmd/kacho-iam/main.go` wiring + env config |
| `obsidian/kacho/edges/iam-internal-listener.md` | UPDATE (or CREATE if missing) | mTLS-protected via SVID; trust-domain `kacho.cloud`; SPIFFE-ID allowlist; CiliumNetworkPolicy companion; history entry for this KAC |
| `obsidian/kacho/architecture.md` | UPDATE | Mesh diagram subsection; reference both new security/ notes |
| `obsidian/kacho/KAC/KAC-<W3.3-id>.md` | NEW | Per CLAUDE.md vault discipline — status, repos, PRs, acceptance trail, links to security/ + edges/ + packages/ entries |
| `obsidian/kacho/resources/iam-internal-service.md` | UPDATE if exists | Note: now mTLS-required for callers; client-side dial pattern updated |

---

## 10. Out of scope (explicit — for follow-up epics)

| Item | Where it lives |
|---|---|
| mTLS on **kacho-vpc** internal listener (server-side) | Separate epic per `CLAUDE.md` graph; template = this doc |
| mTLS on **kacho-compute** internal listener (server-side) | Same |
| mTLS on **kacho-api-gateway** internal mux (server-side) | Same |
| mTLS on **public** listeners (:9090 of any service) | Tenant-cert-management epic — descoped per [[KAC-127]] "no external domain for v1" |
| SPIRE cross-cluster federation | Multi-cluster Kachō epic — future |
| Postgres TLS handshake (mTLS to DB) | Separate W3 sub-item; pg-spiffe-helper or cert-manager |
| **Per-RPC identity-aware authz** ("only api-gateway may call X RPC") | Follow-up KAC, after W3.3 delivers substrate; overlap with [[KAC-127]] permission-catalog |
| **JWT-SVID flow** for HTTP/REST async messaging | Future when async messaging proliferates beyond outbox-LISTEN/NOTIFY |
| **Cosign supply-chain hardening beyond selector** | Belongs to supply-chain epic — W3.4 freeze checklist may reference but not deliver |
| W3.2 dashboards / alerts | W3.2 acceptance doc — references metrics emitted here |
| W3.4 freeze checklist | W3.4 acceptance doc |
| Removal of fail-open-with-log dev path (D-W3.3-5) | Stays as dev-kind convenience; revisit only if dev workflow changes |
| Hubble UI / hubble-relay productionisation | Cilium ops epic, separate |

---

## 11. Traceability — finding/decision ↔ scenario ↔ source-line

| Source | Scenarios | Code/config sites | Test name |
|---|---|---|---|
| W3.3 brief §"5. CiliumNetworkPolicy" | W3.3-NEG-03 | `kacho-deploy/helm/umbrella/charts/cilium/templates/kacho-iam-ingress-allowlist.yaml` | `Test_Cilium_DropsUnauthorizedSourcePod` (kind integration) |
| W3.3 brief §"3. kacho-iam workload code" | W3.3-POS-01, W3.3-POS-02, W3.3-POS-03, W3.3-INIT-DEV | `kacho-iam/internal/spire/{source.go,grpc.go}` + `cmd/kacho-iam/main.go` | `Test_Spire_SourceFetchesSVIDOnInit`, `Test_Spire_ServerCredsAcceptsValidPeer`, `Test_Spire_RotationTransparent`, `Test_Spire_DevFailOpen` |
| W3.3 brief §"5. gRPC client side" | W3.3-POS-02 (verifies client path), W3.3-EDGE-03 | `kacho-iam/cmd/kacho-iam/w1_2_wiring.go` + peer-repos `internal/clients/iam*.go` | `Test_Spire_ClientCredsValidatesServerSpiffeID`, `Test_Spire_ClientInitFailureFallback` |
| W3.3 brief §"6 Negative: peer without SVID" | W3.3-NEG-01 | `internal/spire/grpc.go::ServerCreds` + main.go strict-mode | `Test_Spire_ServerRejectsInsecurePeer` |
| W3.3 brief §"6 Negative: wrong-trust-domain SVID" | W3.3-NEG-02 | `tlsconfig.AuthorizeMemberOf(td)` in `ServerCreds` | `Test_Spire_ServerRejectsWrongTrustDomain` (fakesource unit-int) |
| W3.3 brief §"6 Edge: SPIRE temporarily unreachable" | W3.3-EDGE-01 | `workloadapi.NewX509Source` watch behaviour | `Test_Spire_GracefulRefreshFailures` (kind, scale spire-server to 0) |
| W3.3 brief §"6 Edge: trust-bundle rotation" | W3.3-EDGE-04 | go-spiffe `X509Source` automatic bundle update | `Test_Spire_RootCARotationOverlap` (fakesource unit-int) |
| §5.5 staged cutover | W3.3-EDGE-DUAL | `internal/spire/grpc.go` dual-accept mode + `kacho_iam_spire_handshake_total{result=plaintext_fallback}` | `Test_Spire_DualAcceptWindowTransition` (staging integration) |
| §6.4 substrate for follow-up | W3.3-PROP-01 | `peer.FromContext` + `peertls.PeerIDFromConn` | `Test_Spire_PeerSpiffeIDExtractableFromCtx` |
| §0.1 current placeholder | (verified by absence post-impl) | `w1_2_wiring.go:70-75` placeholder removed | (grep gate in CI: `grep -n "real mTLS. For now we still use insecure as a placeholder" project/kacho-iam/cmd/kacho-iam/*.go` must return 0 lines) |
| OQ-W3.3-1 (trust domain) | All scenarios use `kacho.cloud` | helm chart defaults `values.yaml:17` | n/a (verified at A6) |
| OQ-W3.3-3 (worker pod) | n/a if single Deployment | `kubectl get deploy -n kacho-system` | n/a (verified at A5) |
| OQ-W3.3-4 (config-driven peer ID) | W3.3-POS-02 verifies env-driven path | helm template env `KACHO_IAM_INTERNAL_PEER_SPIFFE_ID` | (config render test in helm CI) |
| OQ-W3.3-6 (alert threshold) | W3.3-EDGE-01 increments counter 3x | W3.2 alert YAML (separate epic) | n/a in W3.3 |

---

## 12. Ссылки

- Workspace правила: `../../CLAUDE.md` (запреты #1/#5/#6/#11/#12; §«Инфра-чувствительные данные»; vault discipline)
- IAM-specific: `../../project/kacho-iam/CLAUDE.md`
- Master plan: `../superpowers/plans/2026-05-23-iam-prod-ready-master.md` (W3 row; §Decisions «SPIRE: В scope»)
- Production launch plan: `../superpowers/plans/2026-05-21-production-launch-plan.md` (DECISION-MESH context — initially descoped, reintroduced in W3)
- Predecessor acceptance doc (format reference):
  - `sub-phase-W1.6-remediation-chunk2-in-service-authz-acceptance.md` (gold-standard structure)
  - `sub-phase-W1.4-principal-propagation-acceptance.md` (principal-propagation — composes with SVID for full caller-identity story)
- Existing SPIRE infra:
  - `../../project/kacho-deploy/helm/umbrella/charts/spire-server/values.yaml` (trust domain default)
  - `../../project/kacho-deploy/helm/umbrella/charts/spire-server/templates/registration-job.yaml` (entry-create logic)
  - `../../project/kacho-deploy/helm/umbrella/charts/spire-agent/templates/daemonset.yaml` (Workload API socket hostPath)
  - `../../project/kacho-deploy/helm/umbrella/spire-registration/kacho-iam.yaml` (existing SpiffeRegistration entry)
  - `../../project/kacho-deploy/helm/umbrella/charts/cilium/templates/cilium-mtls-enforce.yaml` (cluster-wide mTLS enforce policy)
- kacho-iam current state:
  - `../../project/kacho-iam/cmd/kacho-iam/main.go:240-260` (internal listener no-creds wiring — target of §5.2.3)
  - `../../project/kacho-iam/cmd/kacho-iam/w1_2_wiring.go:65-75` (placeholder insecure dial — target of §5.2.4)
- go-spiffe SDK reference: https://github.com/spiffe/go-spiffe (`workloadapi`, `spiffegrpc/grpccredentials`, `spiffetls/tlsconfig`)
- Cilium ServiceMesh authentication docs: https://docs.cilium.io/en/stable/network/servicemesh/mutual-authentication/ (referenced for `authentication.mode: required` semantics)
- Vault entries (to be created at impl):
  - `obsidian/kacho/security/spire-spiffe-ids.md` (NEW)
  - `obsidian/kacho/security/cilium-mesh-policies.md` (NEW)
  - `obsidian/kacho/edges/iam-internal-listener.md` (UPDATE or CREATE)
  - `obsidian/kacho/packages/iam-cmd.md` (UPDATE)
  - `obsidian/kacho/architecture.md` (UPDATE)
  - `obsidian/kacho/KAC/KAC-<W3.3-id>.md` (NEW per CLAUDE.md vault discipline)
