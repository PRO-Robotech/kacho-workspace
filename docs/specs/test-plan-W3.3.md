# Test Plan — W3.3: SPIRE + Cilium mTLS wiring

> **Source**: [docs/specs/sub-phase-W3.3-spire-cilium-mtls-wiring-acceptance.md](sub-phase-W3.3-spire-cilium-mtls-wiring-acceptance.md) (APPROVED 2026-05-24)
> **Status**: PLAN (no code yet — code lives in feature-impl PRs)
> **Branch (eventual impl)**: `KAC-XXX-w3-3-spire-cilium` (kacho-iam workload + kacho-deploy SPIRE registration + Cilium policy)
> **Parent KAC**: KAC-170 (epic bundle); follow-up to W2.B B.10 (unit-tests only) — W3.3 adds cluster-side proof

## 1. Per-GWT mapping

### 6.1 Server-side: kacho-iam exposes mTLS-protected :9091

| GWT id | Scenario summary | Integration test (Go, kind) | Newman case | Manual / e2e |
|---|---|---|---|---|
| W3.3-POS-01 | Pod starts and fetches SVID | `tests/spiffe/svid_fetch_integration_test.go::Test_KachoIAM_FetchesSVID_OnStartup` (kind cluster + SPIRE + verify SVID material via Workload API mock) | — | `kubectl exec kacho-iam -- /tools/check-svid` |
| W3.3-POS-02 | Allowed peer with valid SVID connects and RPC succeeds | `tests/spiffe/peer_connect_integration_test.go::Test_AllowedPeer_ValidSVID_RPCSucceeds` (kind: peer pod with SVID dials :9091, calls `InternalIAMService.Check`) | `iam-internal-only-check.py::INT-IAM-CHECK-VIA-MTLS-OK` (extended with mTLS context) | `kubectl exec kacho-api-gateway -- /tools/test-peer-call kacho-iam:9091` |
| W3.3-POS-03 | SVID rotation mid-flight does not disrupt service | `tests/spiffe/rotation_integration_test.go::Test_SVIDRotation_NoDisruption` (force SPIRE rotation via API, verify in-flight RPC succeeds + new connections also succeed) | — | — |

### 6.2 Server-side negatives

| GWT id | Scenario summary | Integration test (Go, kind) | Newman case |
|---|---|---|---|
| W3.3-NEG-01 | Peer without SVID (insecure client) rejected | `tests/spiffe/peer_connect_integration_test.go::Test_PeerWithoutSVID_TLSReject` (plain HTTPS client → TLS handshake failure) | `iam-internal-only-check.py::INT-IAM-CHECK-NO-SVID-DENY` (newman runs via mTLS-stripped client) |
| W3.3-NEG-02 | Peer with wrong-trust-domain SVID rejected | `tests/spiffe/peer_connect_integration_test.go::Test_PeerWrongTrustDomain_Rejected` | — |
| W3.3-NEG-03 | Cilium policy drops unauthorized source pod at L4 | `tests/spiffe/cilium_policy_integration_test.go::Test_Cilium_UnauthorizedSourcePod_DroppedL4` (kind + Cilium installed; deploy unauthorized pod, attempt TCP connect to :9091, verify drop via `cilium monitor` or netpol-denied event) | — |

### 6.3 Edge cases

| GWT id | Scenario summary | Integration test (Go, kind) | Newman case |
|---|---|---|---|
| W3.3-EDGE-01 | SPIRE Server temporarily unreachable mid-flight | `tests/spiffe/spire_outage_integration_test.go::Test_SPIRE_TempUnreachable_KeepsServing` (scale SPIRE Server to 0, verify kacho-iam pod keeps serving with cached SVID until expiry) | — |
| W3.3-EDGE-02 | SVID expires before SPIRE recovery → server fails-closed | `tests/spiffe/spire_outage_integration_test.go::Test_SVIDExpiredDuringOutage_FailsClosed` (sustained outage > SVID TTL, verify pod refuses connections — does NOT degrade-open) | — |
| W3.3-EDGE-03 | Peer client cannot reach Workload API socket | `tests/spiffe/socket_unreachable_integration_test.go::Test_WorkloadAPISocketUnreachable_PeerErrors` (remove socket bind, peer should error explicitly, not degrade-open) | — |
| W3.3-EDGE-04 | Trust-bundle (root CA) rotation overlap window | `tests/spiffe/trust_bundle_rotation_integration_test.go::Test_TrustBundleRotation_OverlapWindow` (rotate SPIRE root CA, verify connections during overlap window accept both old + new) | — |
| W3.3-EDGE-05 | Config flag dev fail-open path actually fails open | `tests/spiffe/dev_failopen_integration_test.go::Test_DevFlag_FailOpen_AcceptsInsecure` (set `KACHO_IAM_MTLS_DEV_FAILOPEN=true`, verify insecure client accepted with warning log; PROD-FLAG must default false + refuse via env-validator) | — |
| W3.3-EDGE-06 | Staged dual-accept window (PR-1 to PR-FINAL transitional) | `tests/spiffe/dual_accept_integration_test.go::Test_StagedDualAccept_BothInsecureAndMtls` (verify PR-1 transitional state: server accepts BOTH insecure AND mTLS; PR-FINAL state: only mTLS) | — |

### 6.4 Substrate verification for follow-up

| GWT id | Scenario summary | Integration test (Go) | Newman case |
|---|---|---|---|
| W3.3-PROP-01 | Peer SPIFFE-ID extractable from gRPC context (substrate for OQ-W3.3-9 future authz-via-SPIFFE) | `tests/spiffe/spiffe_id_ctx_extract_integration_test.go::Test_PeerSPIFFEID_ExtractableFromContext` (verify server-side interceptor populates `ctx.Value("peer_spiffe_id")` correctly) | — |

## 2. Test infrastructure required

- **kind cluster** with:
  - SPIRE Server + SPIRE Agent (deployed via spiffe-csi-driver helm chart or spire-helm-charts)
  - Cilium (installed with eBPF datapath; helm chart `cilium/cilium`)
  - kacho-iam pod with W3.3 PR-applied (SVID-aware listener on :9091)
  - kacho-api-gateway pod (peer client, dials kacho-iam:9091 via mTLS)
  - Test pods: `peer-allowed` (with SPIRE registration entry), `peer-unauthorized` (no entry), `peer-wrong-domain` (different trust domain)
- **SPIRE registration entries** (`tests/spiffe/fixtures/spire-entries.yaml`):
  - `spiffe://kacho.local/sa/kacho-iam` → kacho-iam pod selector
  - `spiffe://kacho.local/sa/kacho-api-gateway` → gateway selector
  - `spiffe://kacho.local/sa/peer-allowed` → peer-allowed selector
  - **NO entry** for peer-unauthorized
  - `spiffe://other.domain/sa/peer` → peer-wrong-domain (different SPIRE trust domain)
- **Cilium ingress policy** (`tests/spiffe/fixtures/cilium-ingress.yaml`):
  - Allow kacho-iam :9091 from `kacho-api-gateway`, `peer-allowed` only
  - Drop all else at L4
- **Helpers**:
  - `pkg/spiffe/fakesource/` — fake `workloadapi.Source` for unit tests (W2.B B.10 unit tests reuse this)
  - `tests/spiffe/scripts/rotate_spire_root.sh` — wraps SPIRE CLI for EDGE-04 rotation
  - `tests/spiffe/scripts/scale_spire_to_zero.sh` — for EDGE-01/02 outage simulation
  - `tools/check-svid/main.go` — helper binary that fetches SVID + prints subject, used by W3.3-POS-01 manual smoke
  - `tools/test-peer-call/main.go` — minimal client that dials kacho-iam:9091 via mTLS + calls InternalIAM.Check
- **External services**: SPIRE + Cilium (only); no OpenFGA / no Postgres for W3.3 integration tests (kacho-iam runs minimal config without those, focus on listener/handshake)
- **CI requirement**: kind cluster boot + SPIRE+Cilium install ~3min; test suite runtime ~10min

## 3. Coverage gates (DoD on impl-PR)

- **All §6.1-6.3 scenarios green** (W3.3-POS-01..03, NEG-01..03, EDGE-01..06)
- **W3.3-PROP-01 green** (substrate for follow-up — must verify SPIFFE-ID extraction works for future authz)
- **§Запрет #6 regression** (per acceptance §0.3, §1, §5.4): cluster-internal listener stays internal even under SPIRE outage (W3.3-EDGE-02 verifies fail-closed)
- **Cilium policy DROPS verified at L4** (W3.3-NEG-03 must observe drop via cilium monitor — not just TCP timeout)
- **Trust-bundle rotation overlap window** (W3.3-EDGE-04) — must verify both old and new accepted during window, then only new after
- **Dev fail-open flag PROD-OFF**: env-validator at startup MUST refuse to start if `KACHO_IAM_MTLS_DEV_FAILOPEN=true` while `KACHO_ENV=production` (W3.3-EDGE-05 must include this PROD-guard test)
- **Coverage gate `coverage.py --min 100`**: per-RPC `InternalIAMService.*` test now adds `mTLS context` variant — newman suite extends

## 4. Test sequencing for TDD (RED-before-GREEN per workspace §12)

Per acceptance §5.5 «STAGED, dual-accept window»:

1. **RED phase — Stage 0 (current state)**: write all §6 integration tests + fixtures first. CI red:
   - POS-01 red: SVID fetch logic not in main.go
   - POS-02 red: mTLS listener not wired
   - NEG-01..02 red: insecure clients still accepted
   - EDGE-* red: outage logic / rotation logic / dev-flag not present
2. **GREEN phase Stage 1 — PR-1 dual-accept transitional**:
   - SPIRE registration entries deployed (kacho-deploy)
   - kacho-iam workload code: fetch SVID, add mTLS listener BESIDE existing insecure listener
   - Cilium ingress policy deployed (allow + drop at L4)
   - POS-01 GREEN; POS-02 GREEN (mTLS peer succeeds); NEG-03 GREEN (Cilium drops unauthorized at L4)
   - EDGE-06 GREEN (dual-accept verified)
3. **GREEN phase Stage 2 — peer cutover**:
   - kacho-api-gateway dials kacho-iam via mTLS (peer client cutover §5.5)
   - All known peers cut over to mTLS
4. **GREEN phase Stage 3 — PR-FINAL only-mTLS**:
   - Insecure listener removed
   - NEG-01 GREEN (insecure client rejected)
   - EDGE-02 GREEN (fail-closed on SVID expiry)
   - EDGE-05 GREEN (dev fail-open works in dev, refuses in prod)
5. **Continuous**: rotation tests (POS-03, EDGE-04) green throughout
6. **Cross-finding/cross-feature regression**: re-run W2.A `INTERNAL-BREAKGLASS-NOT-ON-PUBLIC-LISTENER` etc. — verify mTLS doesn't accidentally expose internal RPC on public listener
7. **RED→GREEN evidence per stage** in PR description

## 5. Out-of-scope tests (boundary, not omission)

- **SPIFFE-based authorization (not authentication)** — OQ-W3.3-9 future feature; W3.3 only establishes mTLS handshake + peer-identity propagation. Authorization via SPIFFE-ID is W4+
- **Cross-cluster federation of SPIRE trust domains** — out of W3.3
- **Hardware-attested workload identity (TPM/Nitro)** — out of scope
- **kacho-vpc / kacho-compute mTLS** — separate per-service epics; W3.3 is iam-only proof-of-concept
- **mTLS for external listener (api.kacho.local:443)** — out of scope; external uses TLS (server-auth only) + JWT/Bearer
- **Connection pooling perf measurement** — separate k6 load epic
- **OQ-W3.3-9 follow-up** (authz via SPIFFE-ID matrix) — separate KAC for follow-up; W3.3 substrate (PROP-01) verified
- **Live attestor plugin tuning (k8s_sat / docker / TPM)** — uses default k8s_sat plugin; tuning is deploy-config

## 6. Coverage gaps observed in acceptance doc

- **OQ-W3.3-1..-8** (acceptance §4) — implementer decisions on SPIRE/Cilium specifics (k8s_sat selector format, trust-domain name, dual-accept window duration, policy strictness). All have recommendations; implementer picks. Not gaps.
- **Acceptance §5.4 (Helm chart kacho-iam updates)** — enumerates env-vars but doesn't enumerate Helm values schema. Implementer adds `values.yaml` schema with `iam.mtls.enabled`, `iam.mtls.devFailopen`, `iam.spire.trustDomain` etc.
- **Acceptance §5.7 (Integration test in kind)** — declares «integration test in kind» without enumerating the full §6 mapping. This test plan §1 fills the gap by enumerating each scenario → test name.
- **EDGE-05 PROD-guard** — acceptance §6.3 enumerates dev fail-open but doesn't explicitly require PROD-validator refusal. Added in §3 here as a critical safety gate (per workspace §«Запреты» pattern: fail-closed in prod).
- **PROP-01 substrate for OQ-W3.3-9** — acceptance §6.4 marks as «substrate verification for follow-up», but doesn't gate W3.3 DoD on it. This test plan §3 includes it in DoD because the substrate must work *now* to unblock future authz work — otherwise W3.3 ships incomplete substrate.

These are **clarifications/refinements**, not doc omissions.

## 7. Cross-reference

- Acceptance source: [docs/specs/sub-phase-W3.3-spire-cilium-mtls-wiring-acceptance.md](sub-phase-W3.3-spire-cilium-mtls-wiring-acceptance.md)
- Companion plans: [test-plan-W2.B.md](test-plan-W2.B.md) (B.10 SPIRE/Cilium unit-tests — fakesource-based, W3.3 adds kind cluster proof), [test-plan-W3.2.md](test-plan-W3.2.md) (mTLS handshake metric `kacho_iam_mtls_handshake_total` surfaces in observability dashboards), [test-plan-W3.1.md](test-plan-W3.1.md) (#40/#42 IdP JWKS fetch may use mTLS — adjacent infra)
- Workspace rules: `CLAUDE.md` §«Запреты» #6 (Internal listener stays internal under all conditions); §«Инфра-чувствительные данные» (peer SPIFFE-ID/trust-bundle are infra-sensitive — never on public listener)
- Naming conventions: integration tests in `tests/spiffe/<area>_integration_test.go::Test_<Area>_<Scenario>` (NOT inside `internal/` — cluster-side tests deserve a separate `tests/spiffe/` layout)
