# Sub-phase W1.4 — Principal propagation сервис→сервис — Acceptance

> **Status**: DRAFT (awaiting `acceptance-reviewer` per CLAUDE.md §Запреты #1).
> **Date**: 2026-05-23
> **YouTrack**: KAC-140 W1.4 (subtask of [KAC-136](https://prorobotech.youtrack.cloud/issue/KAC-136), child of epic [KAC-134](https://prorobotech.youtrack.cloud/issue/KAC-134) "kacho-iam → production-ready"). The KAC-140 issue itself is created by the controller after this doc reaches APPROVED.
> **Author agent**: `acceptance-author`
> **Reviewer agent**: `acceptance-reviewer` (gate per запрет #1, workspace `CLAUDE.md`).
> **Target repos**:
>   - **Primary**: `PRO-Robotech/kacho-vpc` — `internal/apps/kacho/check/check_client.go::IAMCheckClient.Check` is the missing-propagation site for VPC. Wrap the outgoing `c.cli.Check(ctx, ...)` call with the same `withPrincipalMD` helper that already exists in `internal/clients/iam_client.go` (KAC-127 Bug-2 wrapped ProjectService.Get but did not touch the authz Check path).
>   - **Primary**: `PRO-Robotech/kacho-compute` — symmetric fix in `internal/check/check_client.go::IAMCheckClient.Check`. `compute/internal/clients/iam_client.go` already has the identical `withPrincipalMD` helper (lines 26-44) and uses it for `ProjectService.Get` + every VPC peer-call; the per-RPC authz Check path does not.
>   - **Primary**: `PRO-Robotech/kacho-corelib` — extract the helper. `kacho-vpc/internal/clients/iam_client.go::withPrincipalMD` and `kacho-compute/internal/clients/iam_client.go::withPrincipalMD` are byte-for-byte identical. Move into new `kacho-corelib/auth/propagate.go` (`auth.PropagateOutgoing(ctx) context.Context`) so any future peer-client (loadbalancer, dns, future services) gets the helper by import without copy-paste. Keep `MDKeyPrincipal*` constants in their current home `corelib/grpcsrv/principal_extract.go` (server-side extract) and re-export from `auth/` for callers that only depend on the client side.
>   - **Touched (verification only)**: `PRO-Robotech/kacho-api-gateway` — the gateway path already injects `x-kacho-principal-*` onto outgoing metadata via `internal/middleware/auth.go::injectPrincipal` (lines 227-242). W1.4 confirms this still holds by reading the existing tests + the new e2e in §3 — no code change in the gateway.
>   - **Touched (verification only)**: `PRO-Robotech/kacho-iam` — the iam server already extracts principal via `corelib/grpcsrv.UnaryPrincipalExtract` (wired in `cmd/kacho-iam/main.go`). The fix is upstream from iam. W1.4 confirms iam's `InternalIAMService.Check` handler honours the propagated principal via the existing `corelib/grpcsrv.UnaryPrincipalExtract` interceptor — no handler-side change needed in `internal/apps/kacho/api/internal_iam/handler.go::Check`.
>   - **NOT touched**: `kacho-proto` — no new RPC, no new field; uses existing gRPC metadata header.
> **Branch (all repos)**: `KAC-140`.
> **Parent epic plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-master.md` Wave 1.
> **Wave plan**: `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` §W1.4.
> **Predecessors**:
>   - `sub-phase-W1.1-fga-outbox-drainer-acceptance.md` (APPROVED 2026-05-23) — bootstrap-admin grant tuples land in OpenFGA. Without the drainer the FGA model has no user-tuples to consult, and W1.4 would be a no-op (every Check still denies regardless of the propagated principal). W1.4 is the chunk that makes the propagated principal **actually useful** by giving iam something to evaluate against.
>   - `sub-phase-W1.2-subject-change-cache-invalidation-acceptance.md` (in-flight) — revoke→DENY within 1s. Independent of W1.4 but composed in the e2e of §3.6.
>   - `sub-phase-W1.3-gateway-authz-failclosed-acceptance.md` (in-flight) — gateway fail-closed. Independent; W1.4 fixes the **next hop** (vpc/compute → iam) where the same identity blindness occurs.

---

## 0. Преамбула — что эта sub-итерация (précis)

W1.4 — **четвёртый чанк Wave 1**. After W1.1 (drainer), W1.2 (cache invalidation), W1.3 (gateway fail-closed) the gateway-level authz path is correct end-to-end. The **next hop** is broken: when `kacho-vpc` (or `kacho-compute`) calls `kacho-iam.InternalIAMService.Check` from its per-RPC `check`-interceptor, the principal seen by iam is **always `user:bootstrap`** regardless of which tenant user actually issued the request.

Three observable failures W1.4 closes:

1. **Per-RPC authz Check is identity-blind on the cross-service path.** Reading `project/kacho-vpc/internal/apps/kacho/check/check_client.go:40-53` (`IAMCheckClient.Check`): the method calls `c.cli.Check(ctx, &iamv1.CheckRequest{SubjectId: ..., Relation: ..., Object: ...})` with no `metadata.AppendToOutgoingContext` wrapping. The `subjectID` argument **is the FGA subject** ("user:usr_xxx") resolved at the interceptor layer via `corelib/authz/subject_extract.go::defaultSubjectExtractor` and IS correct in the Check **payload**. But iam-server-side `corelib/grpcsrv.UnaryPrincipalExtract` (mounted in `kacho-iam/cmd/kacho-iam/main.go`) reads `x-kacho-principal-*` from **incoming metadata**, not from the request body. With no metadata on the wire, `extractPrincipal` returns ctx unchanged → `operations.PrincipalFromContext(ctx)` returns `SystemPrincipal()` = `{Type: "system", ID: "bootstrap"}` → any iam handler that later calls `operations.PrincipalFromContext` (e.g. for scope-filter / audit / OPA-overlay context-claims) sees `user:bootstrap`. The CheckRequest body still has the right `subject_id`, so the **FGA lookup itself is correct**, but every audit log, every scope-derived deny-reason, every OPA-overlay context.user.* field carries the bootstrap principal. This silently breaks (a) attribution in audit, (b) OPA-overlay rules that key on `input.user.id` (W2/W3 finding source), (c) any future iam Check pathway that wants to enforce "principal in metadata == subject in request" symmetry — exactly the spoofing check #35 in W1.6 Chunk 2 will need.

2. **`compute/internal/check/check_client.go:30-43` has the identical bug.** Confirmed by `git grep` — kacho-compute IAMCheckClient.Check is a byte-for-byte equivalent of the vpc version and similarly forwards `ctx` raw. Two repos, one missing wrap.

3. **Helper is copy-pasted in two repos but never reached the authz hot-path.** `project/kacho-vpc/internal/clients/iam_client.go:37-47::withPrincipalMD` and `project/kacho-compute/internal/clients/iam_client.go:35-44::withPrincipalMD` are identical 12-line helpers. Both were added by KAC-127 Bug-2 to fix `ProjectService.Get` (peer existence-validation in Network.Create worker) and both are correctly used by `Exists` / `GetCloudIDFromProject` / vpc-subnet-get etc. **Neither is imported by `apps/kacho/check/`**. The fix is a 1-line wrap per repo PLUS the corelib-extract to prevent the next service (loadbalancer / dns) from rediscovering the bug. The corelib package is the durable artefact; the wraps are the immediate fix.

W1.4 is largely a **lift-and-shift + 1-line wrap × 2** chunk. The plumbing already exists end-to-end (gateway injects MD, corelib interceptor extracts MD, ctx round-trips Principal). The one missing wire is the outgoing-MD wrap on the authz Check call inside vpc-check and compute-check adapters.

### 0.1 W1.4 НЕ включает

- **New principal types** — service-account / API-token principals are already produced by the gateway (`auth.go:196-202` handles `kacho_principal_type=service_account`); W1.4 propagates them as-is. The W1.5 / Block F (API tokens) work is what **mints** richer principals; W1.4 is purely the wire-format propagation layer.
- **mTLS / SPIRE service identity** — defer to W3 (federation/observability wave). W1.4 propagates the **inbound** principal as-is via gRPC metadata; SPIRE adds an additional **outbound** identity layer (vpc identifies AS vpc to iam, separately from forwarding the end-user). Out of scope.
- **Strip-on-entry symmetry to the gateway's `x-kacho-principal-*` stripping** (auth.go:138-155). vpc/compute server-side interceptors do **not** currently strip incoming `x-kacho-principal-*` headers because the cluster-internal listener is mTLS-only and not reachable from outside the cluster (запрет #6). W1.4 documents this in a code comment but does not add stripping. If a tenant manages to inject MD on a gateway-proxied request, the gateway strips it at edge (already enforced, lines 138-155 + 313-319). Adding a second strip in vpc/compute would be defense-in-depth and is left as a follow-up — see §8 OQ-W1.4-2.
- **Reconciler / worker principal labelling** — workers that run **without** a user-driven ctx (e.g. `BreakGlassExpirerWorker.Tick` in iam, future compute-reconciler workers) currently use `operations.SystemPrincipal()` = `user:bootstrap`. W1.4 defines the **convention** for naming system principals (`user:system:<service>-<role>`, e.g. `user:system:compute-reconciler`) and adds the helper `auth.SystemPrincipal(service, role) Principal` but does **not** rewrite every worker; per-worker conversion is a follow-up tracked in the same KAC-140 follow-up issue (see §8 OQ-W1.4-3). The convention is normative for any new worker after merge.
- **Anonymous-request semantics on cross-service path** — if the gateway forwarded an anonymous request (e.g. `KACHO_API_GATEWAY_AUTHN_MODE=dev` + missing Bearer), `x-kacho-principal-id=anonymous` arrives at vpc. The vpc-side interceptor already DENIES via `corelib/authz/subject_extract.go::isAnonymousSubject` (CRIT-6/7 fix in KAC-122) — vpc never calls iam Check for anonymous principals. W1.4 confirms anonymous flow is unchanged: the propagation logic only fires when `Principal{Type, ID}` are both non-empty (`auth/propagate.go:14-19` short-circuits on empty), which preserves the existing path. Negative test in §3.4.
- **Newman coverage beyond §3.8** — one new case (`AUTHZ-PRINCIPAL-PROPAGATED-A`) is sufficient. Wave 2 Поток D will sweep additional principal-related cases (cross-tenant deny via principal-mismatch, etc.). W1.4 is not a newman coverage chunk.

### 0.2 Зависимости

- **W1.1 APPROVED + merged** — bootstrap-admin tuples in OpenFGA. Without it the FGA Check never returns ALLOW, and W1.4's "principal propagated → FGA passes" e2e would be impossible to assert positively.
- **W1.3 APPROVED + merged is NOT a hard prerequisite** but is recommended landed first — on a fail-open gateway a regression in W1.4 propagation could be masked by ALLOW-on-Check-error. With W1.3 fail-closed, any propagation regression surfaces as 503/PermissionDenied immediately.
- **No proto change.** Uses existing `x-kacho-principal-type` / `-id` / `-display-name` gRPC metadata headers established by KAC-107.
- **No migration.** No DB schema touched.

---

## 1. Current state (discovered 2026-05-23)

Exact paths/lines pulled from the repo at `KAC-132` HEAD (this branch). Sources cited inline so reviewer can spot drift.

### 1.1 corelib — principal context (server side, already correct)

- `project/kacho-corelib/grpcsrv/principal_extract.go:38-42` — exports three constants used by both sides:
  - `MDKeyPrincipalType    = "x-kacho-principal-type"`
  - `MDKeyPrincipalID      = "x-kacho-principal-id"`
  - `MDKeyPrincipalDisplay = "x-kacho-principal-display-name"`
- `project/kacho-corelib/grpcsrv/principal_extract.go:46-101` — `UnaryPrincipalExtract` + `StreamPrincipalExtract`: read incoming metadata, populate `operations.Principal` on ctx via `operations.WithPrincipal`. Fallback when MD absent → returns ctx unchanged (so downstream `operations.PrincipalFromContext` produces `SystemPrincipal()` per `corelib/operations/types.go:30-33`).
- `project/kacho-corelib/operations/principal_ctx.go:15-35` — `WithPrincipal(ctx, p) ctx` / `PrincipalFromContext(ctx) Principal`. The latter returns `SystemPrincipal() = {Type: "system", ID: "bootstrap", DisplayName: "System"}` on empty ctx. This is the source of the `user:bootstrap` observation in W1.4 problem statement: a server that received no MD sees SystemPrincipal everywhere.

**No corelib code change** for the server side — the extraction layer is complete. W1.4 adds a **client-side outgoing-MD helper** that complements this.

### 1.2 corelib — no current outgoing-MD helper (the gap to close)

- `git grep "AppendToOutgoingContext" project/kacho-corelib/` returns nothing in the auth/principal area (only `outbox/` and `retry/` unrelated). The outgoing-MD wrap lives twice as copy-pasted code in the two service repos (see §1.4 below).

### 1.3 api-gateway — already propagates (no code change in W1.4)

- `project/kacho-api-gateway/internal/middleware/auth.go:227-242::injectPrincipal` — after subject lookup (or anonymous-fallback), sets `operations.WithPrincipal(ctx, p)` AND appends `x-kacho-principal-{type,id,display-name}` to `metadata.NewOutgoingContext` on the same ctx. The outgoing ctx is what the gRPC proxy / grpc-gateway forwards to the backend.
- `project/kacho-api-gateway/internal/middleware/auth.go:374-432` — REST→backend equivalent for the HTTP-mux path (sets headers on the inbound `*http.Request`, which `restmux.NewMux WithMetadata` callback converts back to outgoing gRPC metadata).
- `project/kacho-api-gateway/internal/middleware/auth.go:138-155` + `:307-319` — gateway STRIPS any client-supplied `x-kacho-principal-*` / `X-Kacho-Principal-*` headers before its own auth flow runs (KAC-122 CRIT-8). Important defense-in-depth: a tenant cannot inject a principal header to impersonate another user via the gateway.

**Verification** in W1.4 §3.3: an integration test confirms gateway-proxied gRPC carries the headers, and a separate test confirms a client-supplied header is stripped before auth fires.

### 1.4 vpc / compute — peer-clients (the byte-identical fix sites)

- `project/kacho-vpc/internal/clients/iam_client.go:37-47::withPrincipalMD` —
  ```go
  func withPrincipalMD(ctx context.Context) context.Context {
      p := operations.PrincipalFromContext(ctx)
      if p.ID == "" || p.Type == "" {
          return ctx
      }
      return metadata.AppendToOutgoingContext(ctx,
          grpcsrv.MDKeyPrincipalType, p.Type,
          grpcsrv.MDKeyPrincipalID, p.ID,
          grpcsrv.MDKeyPrincipalDisplay, p.DisplayName,
      )
  }
  ```
  Used by `ProjectClient.Exists` (line 102) and `ProjectClient.GetCloudIDFromProject` (line 146). KAC-127 Bug-2 docstring explains the motivation in detail (lines 19-36).

- `project/kacho-compute/internal/clients/iam_client.go:35-44::withPrincipalMD` — identical implementation. Used by `ProjectClient.Exists`, `GetCloudIDFromProject`, and `compute/internal/clients/vpc_client.go:70/92/121/142/158` for all subnet/SG/address peer-calls. **Total: 6 usage sites across the two repos, all in non-authz-Check code paths.**

- `project/kacho-vpc/internal/apps/kacho/check/check_client.go:40-53::IAMCheckClient.Check` — **missing wrap**:
  ```go
  func (c *IAMCheckClient) Check(ctx context.Context, subjectID, relation, object string) (bool, error) {
      resp, err := c.cli.Check(ctx, &iamv1.CheckRequest{   // ← raw ctx, no MD
          SubjectId: subjectID,
          Relation:  relation,
          Object:    object,
      })
      ...
  }
  ```
  This is the only call site of `kacho-iam.InternalIAMServiceClient.Check` from vpc. Reached on every public VPC RPC by the `check`-interceptor (NetworkService, SubnetService, AddressService, RouteTableService, SecurityGroupService, GatewayService, PrivateEndpointService, NetworkInterfaceService, OperationService — ≥60 RPCs per vault `edges/vpc-to-iam-check.md`).

- `project/kacho-compute/internal/check/check_client.go:30-43::IAMCheckClient.Check` — identical bug; same call frequency on the compute side (DiskService, ImageService, SnapshotService, InstanceService, DiskTypeService, ZoneService, RegionService, OperationService — ≥40 RPCs per vault `edges/compute-to-iam-check.md`).

### 1.5 corelib/authz — interceptor (server side of vpc/compute, already correct)

- `project/kacho-corelib/authz/interceptor.go` — the unary/stream interceptor that vpc/compute mount on public RPCs. Lines (full file scan) show it (a) extracts the subject via injected `SubjectExtractor` (defaults to `defaultSubjectExtractor`), (b) maps RPC → relation+object, (c) calls `CheckClient.Check(ctx, subject, relation, object)`. The ctx threaded into the CheckClient is the inbound request ctx — already populated with `operations.Principal` by the upstream `corelib/grpcsrv.UnaryPrincipalExtract` interceptor (mounted by `cmd/vpc/main.go` + `cmd/compute/main.go`). So the **ctx-side principal is already correct in the adapter** — it is the **outgoing gRPC MD** that loses it.

- `project/kacho-corelib/authz/subject_extract.go:11-26::defaultSubjectExtractor` — reads `operations.PrincipalFromContext(ctx)` to form the FGA subject. Comment at lines 16-19 explicitly notes: "On system-principal (without `AllowSystemPrincipal=true`) — returns ok=true, subjectFGA='user:bootstrap'. Interceptor.authorize then rejects (subject 'user:bootstrap' has no tuples in FGA)." This is the **first** principal-related identity blindness, but on vpc's local side: the subject sent in the CheckRequest body is `user:bootstrap` when ctx is empty.

  **Why this is not the bug W1.4 fixes**: between gateway and vpc, propagation already works (gateway injects MD, vpc grpcsrv extracts it, ctx has the real principal). So `defaultSubjectExtractor` sees the real user and puts the real subject **in the CheckRequest body**. The bug is between vpc and iam: vpc never forwards the outgoing MD, so iam-side `defaultSubjectExtractor` / `operations.PrincipalFromContext` (used by anything iam-internal that wants to know the caller) sees `user:bootstrap`.

### 1.6 kacho-iam — server side, already correct

- `project/kacho-iam/cmd/kacho-iam/main.go` — mounts `grpcsrv.UnaryPrincipalExtract()` + `grpcsrv.StreamPrincipalExtract()` in the public AND internal (port 9091) interceptor chain. So **incoming MD → ctx-Principal** works on both listeners. The only missing piece is the outgoing-MD on the vpc/compute side (§1.4).
- `project/kacho-iam/internal/apps/kacho/api/internal_iam/handler.go:81-119::Check` — does not call `operations.PrincipalFromContext` directly; the authz/FGA evaluation runs against the request-body `SubjectId`. **W1.4 does not change this handler**; the value of W1.4 to iam is that all OTHER iam handlers (`access_binding/helpers.go:150`, `account/list.go:34`, `project/list.go:30`, `user/invite.go:126`, `user/list.go:48`, `compliance_report/handler.go:100/118`, `jit_pending/handler.go:58` — all listed by `grep` in §1.0) that ARE called from vpc/compute on cross-service flows will see the correct principal once propagation is in place.

### 1.7 No tests today cover the propagation gap

- `project/kacho-vpc/internal/apps/kacho/check/interceptor_test.go` — exists; mocks `authz.CheckClient` and asserts allow/deny outcomes per RPC. Does **not** assert outgoing-MD content (the mock receives ctx but does not inspect MD).
- `project/kacho-compute/internal/check/interceptor_test.go` — symmetric, same gap.
- `project/kacho-corelib/authz/interceptor_test.go:218` — line confirms the test wires `AllowSystemPrincipal=false` and asserts the system principal hits Check (the call-side subject), but does not assert that outgoing MD carries the principal.
- No newman case today loops back to "iam saw the right principal". The closest is `kacho-iam/tests/newman/cases/authz-deny.py` which asserts DENY based on subject in the CheckRequest body, blind to MD.

**Net**: W1.4 adds (a) a corelib unit test for the new helper, (b) an integration test per service repo that captures outgoing-MD via a recording-stub iam client, (c) one newman case that triggers a cross-service flow and inspects an iam audit/log line (or — simpler — relies on the iam handler returning a different result depending on the principal seen via metadata). Newman approach is decided in §8 OQ-W1.4-4.

---

## 2. What ships (changes by file)

### 2.1 `kacho-corelib` — new package `auth/`

New file `project/kacho-corelib/auth/propagate.go`:

```go
// Package auth — outgoing-side helpers for principal propagation across
// service→service gRPC calls. Server-side extraction lives in
// `corelib/grpcsrv/principal_extract.go` (UnaryPrincipalExtract /
// StreamPrincipalExtract) and is unchanged.
//
// Why this helper exists
//
// vpc/compute per-RPC authz interceptor calls
// `kacho-iam.InternalIAMService.Check` from `clients/check_client.go` adapter.
// Without this wrap, outgoing gRPC carries no `x-kacho-principal-*` MD →
// iam-server-side `grpcsrv.UnaryPrincipalExtract` falls back to
// `operations.SystemPrincipal() = user:bootstrap` → every iam handler that
// later calls `operations.PrincipalFromContext` (audit, scope-filter,
// OPA-overlay context.user.*) sees the wrong identity.
//
// KAC-127 Bug-2 fixed the ProjectService.Get peer-call but did not touch
// the authz Check path. W1.4 extracts the helper here so any future
// peer-client (loadbalancer, dns) gets correct propagation by import.
package auth

import (
    "context"

    "google.golang.org/grpc/metadata"

    "github.com/PRO-Robotech/kacho-corelib/grpcsrv"
    "github.com/PRO-Robotech/kacho-corelib/operations"
)

// PropagateOutgoing forwards the caller's Principal onto outgoing gRPC
// metadata (`x-kacho-principal-type` / `-id` / `-display-name`). A ctx
// without a Principal (empty Type AND empty ID) is returned unchanged —
// this preserves anonymous semantics (gateway has its own anonymous path
// that injects "system:anonymous" explicitly; we do not invent a principal
// here).
//
// On a ctx that already has outgoing MD with these keys (rare; only when a
// caller has manually wrapped), this APPENDS — peer receives the first
// non-empty value per gRPC metadata semantics; explicit wraps win.
func PropagateOutgoing(ctx context.Context) context.Context {
    p := operations.PrincipalFromContext(ctx)
    if p.ID == "" && p.Type == "" {
        return ctx
    }
    return metadata.AppendToOutgoingContext(ctx,
        grpcsrv.MDKeyPrincipalType, p.Type,
        grpcsrv.MDKeyPrincipalID, p.ID,
        grpcsrv.MDKeyPrincipalDisplay, p.DisplayName,
    )
}

// SystemPrincipalFor returns a typed system principal for worker / reconciler
// contexts that have no user identity (cron jobs, expirer workers, etc.).
// Use INSTEAD of operations.SystemPrincipal() for any cross-service call
// originating from such a worker — bootstrap is reserved for the
// kacho-iam bootstrap-admin seed and should not appear on the wire in
// normal operation.
//
//   - service: "vpc" | "compute" | "iam" | ...
//   - role:    "reconciler" | "expirer" | "drainer" | ...
//
// Produces Principal{Type: "user", ID: "system:<service>-<role>", DisplayName: "<service>-<role>"}.
// "user" type (not "system") because FGA tuples and audit fields key on user-typed subjects.
func SystemPrincipalFor(service, role string) operations.Principal {
    return operations.Principal{
        Type:        "user",
        ID:          "system:" + service + "-" + role,
        DisplayName: service + "-" + role,
    }
}
```

New file `project/kacho-corelib/auth/propagate_test.go` (unit tests — RED first per CLAUDE.md §Запреты #11):

- `TestPropagateOutgoing_WithPrincipal_AppendsMD` — populate ctx with `operations.WithPrincipal(ctx, Principal{Type:"user", ID:"usr_alice", DisplayName:"alice"})`, call `PropagateOutgoing(ctx)`, inspect outgoing MD via `metadata.FromOutgoingContext`, assert three keys present with expected values.
- `TestPropagateOutgoing_EmptyPrincipal_PassThroughUnchanged` — empty ctx, call helper, assert outgoing MD is nil OR empty (no spurious headers).
- `TestPropagateOutgoing_AnonymousPrincipal_StillForwards` — ctx with `Principal{Type:"system", ID:"anonymous", DisplayName:""}` (gateway injects this in dev-mode without Bearer), call helper, assert all three headers present (including empty DisplayName) — anonymous is a real principal value, not absence.
- `TestSystemPrincipalFor_FormatsCorrectly` — call `SystemPrincipalFor("vpc", "reconciler")`, assert `{Type:"user", ID:"system:vpc-reconciler", DisplayName:"vpc-reconciler"}`.
- `TestPropagateOutgoing_DoubleWrap_PreservesFirst` — wrap ctx twice with different principals; per gRPC metadata semantics first wrap wins on `metadata.AppendToOutgoingContext`. Asserts that re-wrapping (e.g. nested peer-call) does not silently overwrite identity.

### 2.2 `kacho-vpc` — wrap the Check call

Edit `project/kacho-vpc/internal/apps/kacho/check/check_client.go::IAMCheckClient.Check`:

```go
// W1.4 (KAC-140): propagate the caller's Principal onto outgoing MD so
// kacho-iam's grpcsrv.UnaryPrincipalExtract sees the real user, not
// SystemPrincipal()=user:bootstrap. Prior to W1.4, every per-RPC authz
// Check from vpc-check-interceptor → iam landed with no MD → iam handlers
// that called operations.PrincipalFromContext (audit, scope-filter,
// OPA-overlay) saw bootstrap regardless of the actual caller. See
// `docs/specs/sub-phase-W1.4-principal-propagation-acceptance.md`.
func (c *IAMCheckClient) Check(ctx context.Context, subjectID, relation, object string) (bool, error) {
    resp, err := c.cli.Check(auth.PropagateOutgoing(ctx), &iamv1.CheckRequest{
        SubjectId: subjectID,
        Relation:  relation,
        Object:    object,
    })
    ...
}
```

Import added: `"github.com/PRO-Robotech/kacho-corelib/auth"`. No other change in vpc.

**Note**: `internal/clients/iam_client.go::withPrincipalMD` (the pre-existing local copy) MUST be **deleted** as part of this PR — its callers (`Exists`, `GetCloudIDFromProject`) switch to `auth.PropagateOutgoing(ctx)`. Net deletion: 11 lines (signature + body). This is the lift-and-shift to corelib. Equivalent change in compute (§2.3) deletes the symmetric copy there.

### 2.3 `kacho-compute` — wrap the Check call (symmetric to §2.2)

Edit `project/kacho-compute/internal/check/check_client.go::IAMCheckClient.Check` — identical wrap with `auth.PropagateOutgoing(ctx)`. Delete `internal/clients/iam_client.go::withPrincipalMD` local copy, switch all 6 call sites in `internal/clients/iam_client.go` + `internal/clients/vpc_client.go` to `auth.PropagateOutgoing(ctx)`.

### 2.4 `kacho-vpc` / `kacho-compute` — integration test (RED first)

New file `project/kacho-vpc/internal/apps/kacho/check/check_client_propagation_test.go`:

- Spin up a recording-stub `iamv1.InternalIAMServiceServer` that captures incoming metadata via `metadata.FromIncomingContext(ctx)` on each Check call.
- Build a real `IAMCheckClient` pointed at the stub via `bufconn` (`google.golang.org/grpc/test/bufconn`) — no docker, no testcontainers; in-memory only.
- `TestIAMCheckClient_Check_PropagatesPrincipal` — populate ctx with `operations.WithPrincipal(ctx, Principal{Type:"user", ID:"usr_alice", DisplayName:"alice"})`, call `IAMCheckClient.Check(ctx, "user:usr_alice", "viewer", "vpc_network:enp_xxx")`, assert stub recorded `x-kacho-principal-type=user`, `x-kacho-principal-id=usr_alice`, `x-kacho-principal-display-name=alice`.
- `TestIAMCheckClient_Check_NoPrincipal_NoMD` — empty ctx, assert stub received NO `x-kacho-principal-*` headers.
- `TestIAMCheckClient_Check_AnonymousPrincipal_ForwardedExplicitly` — ctx with `{Type:"system", ID:"anonymous"}`, assert headers present with anonymous values (do not invent a system principal here; preserve gateway-given anonymity downstream so iam's own authzguard can deny it explicitly).

Symmetric new file `project/kacho-compute/internal/check/check_client_propagation_test.go`.

### 2.5 `kacho-iam` — integration test (RED first), no production code change

New file `project/kacho-iam/internal/apps/kacho/api/internal_iam/check_principal_test.go`:

- Spin up `InternalIAMService` Handler with real `corelib/grpcsrv.UnaryPrincipalExtract` mounted via in-memory gRPC server (bufconn).
- Inject ctx with `x-kacho-principal-*` metadata via `metadata.AppendToOutgoingContext`.
- Call `InternalIAMServiceClient.Check(ctx, ...)` and have the handler ALSO call `operations.PrincipalFromContext(handlerCtx)` (add a test hook OR inspect `slog` audit log line via test-`slog.Handler`).
- `TestCheck_PrincipalAvailableInHandler` — assert the principal extracted in the handler's ctx matches the metadata sent (NOT bootstrap).
- `TestCheck_NoMetadata_FallsBackToSystem` — no MD → handler sees SystemPrincipal — documents the current behaviour as the **intended fallback** for off-cluster admin tooling that legitimately runs as bootstrap. (W1.6 Chunk 2's anti-anonymous interceptor on mutating RPCs is what tightens this for the user-facing surface; W1.4 only fixes propagation.)

### 2.6 Newman — one new case (RED first)

New case in `project/kacho-iam/tests/newman/cases/authz-deny.py` (or new file `authz-principal.py` — decided in §8 OQ-W1.4-4) ID `AUTHZ-PRINCIPAL-PROPAGATED-A`:

Scenario:
1. Seed account A with user `usr_alice`, project `prj_a` owned by alice.
2. Seed account B with user `usr_bob`, project `prj_b` owned by bob.
3. As alice (Bearer for alice), request `GET /vpc/v1/networks?folderId=prj_b`.
4. Expected: 403 PermissionDenied (alice has no role on prj_b).
5. **Critical assertion** (the W1.4 distinction): inspect `iam.audit` log line / iam Prometheus counter `iam_check_subject_total{subject="user:usr_alice"}` — it must have incremented. Pre-W1.4, the counter would increment under `subject="user:bootstrap"` instead. (If counter / log-line is not accessible from newman: introduce a new debug RPC `InternalIAMService.LastSeenPrincipal` for tests only — see §8 OQ-W1.4-4.)

This case is structurally identical to existing `authz-deny.py::AUTHZ-DENY-LIST-CROSS-A` but adds the **principal-attribution** assertion that did not previously exist.

### 2.7 Docs — vault notes

- `obsidian/kacho/edges/vpc-to-iam-check.md` — add a "History" entry: "2026-05-23 W1.4 (KAC-140) — outgoing MD now carries x-kacho-principal-* via `corelib/auth.PropagateOutgoing`; previously iam-side principal extraction fell back to SystemPrincipal=user:bootstrap."
- `obsidian/kacho/edges/compute-to-iam-check.md` — symmetric entry.
- `obsidian/kacho/packages/corelib-auth.md` — NEW narrow note (1-2 KB) documenting the new `corelib/auth` package: `PropagateOutgoing`, `SystemPrincipalFor`, intent, complement of `corelib/grpcsrv.UnaryPrincipalExtract`.
- `obsidian/kacho/KAC/KAC-140.md` — NEW trail note (template per workspace CLAUDE.md §«Obsidian vault — обязательный context-источник и trail»).

### 2.8 `kacho-api-gateway` — verification only, no code change

The gateway is the upstream half of propagation and is already correct (see §1.3). W1.4 adds **one** integration test to `project/kacho-api-gateway/internal/middleware/auth_propagation_test.go` (or extends `auth_test.go`):

- `TestAuth_RESTRequest_PropagatesPrincipalToBackend` — drive a fake REST request with a valid Bearer through the auth middleware, capture outgoing gRPC ctx (or http.Request.Header for grpc-gateway path), assert `x-kacho-principal-*` headers present with expected values.

This test seals the gateway side of the propagation contract; in combination with §2.4-2.5 it pins both halves.

### 2.9 `kacho-deploy` — no change

No values overlay touched. No new env-var. No chart bump.

---

## 3. Acceptance scenarios (GWT)

> Coverage map: §3.1-§3.2 corelib helper unit; §3.3 gateway→backend (existing path, verified); §3.4-§3.5 vpc/compute → iam (the fix); §3.6 e2e through gateway; §3.7 system-principal workers; §3.8 newman.

### 3.1 Scenario PROP-CORELIB-01 — corelib helper propagates a user principal

**ID**: W1.4-PROP-CORELIB-01

**Given**
- `corelib/auth` package exists with `PropagateOutgoing(ctx) context.Context`.
- ctx is populated via `operations.WithPrincipal(ctx, operations.Principal{Type:"user", ID:"usr_alice", DisplayName:"alice@example.com"})`.

**When** caller invokes `auth.PropagateOutgoing(ctx)`.

**Then** the returned ctx has outgoing gRPC metadata containing all three headers:
- `x-kacho-principal-type` = `"user"`
- `x-kacho-principal-id` = `"usr_alice"`
- `x-kacho-principal-display-name` = `"alice@example.com"`

**And** inspecting via `metadata.FromOutgoingContext(returnedCtx)` returns the expected `metadata.MD` with these three keys (case-insensitive per gRPC spec).

**And** the original ctx (input) is unchanged (no mutation).

### 3.2 Scenario PROP-CORELIB-02 — empty ctx is pass-through

**ID**: W1.4-PROP-CORELIB-02

**Given** ctx has no `operations.Principal` set (e.g. fresh `context.Background()`).

**When** caller invokes `auth.PropagateOutgoing(ctx)`.

**Then** the returned ctx is identical to input (no MD added) — verified by `metadata.FromOutgoingContext` returning `nil`/empty MD.

**And** the helper does NOT panic on `nil` ctx (defensive).

### 3.3 Scenario PROP-GATEWAY-01 — gateway already propagates (verification)

**ID**: W1.4-PROP-GATEWAY-01

**Given**
- api-gateway with `AuthN.Mode=dev` and a valid HMAC-dev Bearer for `usr_alice`.
- backend-stub gRPC server registered behind the gateway capturing incoming `x-kacho-principal-*`.

**When** a REST request `GET /vpc/v1/networks/enp_xxx` arrives at the gateway with `Authorization: Bearer <usr_alice token>`.

**Then** the backend-stub records incoming metadata with:
- `x-kacho-principal-type` = `"user"`
- `x-kacho-principal-id` = `"usr_alice"`

**And** if the test repeats without Bearer (anonymous in dev mode), the backend records `x-kacho-principal-type="system"`, `x-kacho-principal-id="anonymous"` (this is the existing gateway anonymous-injection behaviour from `auth.go:223-225`; W1.4 preserves it).

### 3.4 Scenario PROP-VPC-CHECK-01 — vpc Check propagates the user principal

**ID**: W1.4-PROP-VPC-CHECK-01

**Given**
- vpc `IAMCheckClient` constructed against a recording-stub iam server (bufconn).
- ctx is populated by `operations.WithPrincipal(ctx, Principal{Type:"user", ID:"usr_alice", DisplayName:"alice"})`.

**When** the vpc per-RPC interceptor invokes `IAMCheckClient.Check(ctx, "user:usr_alice", "vpc.networks.get", "vpc_network:enp_xxx")`.

**Then** the recording-stub iam server captures incoming MD containing exactly:
- `x-kacho-principal-type=user`
- `x-kacho-principal-id=usr_alice`
- `x-kacho-principal-display-name=alice`

**And** the `iamv1.CheckRequest` body still carries `subject_id="user:usr_alice"` (the in-payload subject is unchanged).

**And** the call returns the stub's `CheckResponse` unchanged (the wrap is transparent to error semantics: `allowed=true` → nil, `allowed=false` → nil + `false`, transport err → err).

### 3.5 Scenario PROP-VPC-CHECK-02 — empty ctx does not invent a principal

**ID**: W1.4-PROP-VPC-CHECK-02

**Given**
- vpc `IAMCheckClient` constructed against the recording-stub.
- ctx has no `operations.Principal` (e.g. a buggy test harness or pre-W1.4 worker that bypassed grpcsrv.UnaryPrincipalExtract).

**When** caller invokes `IAMCheckClient.Check(ctx, "user:usr_bootstrap_legacy", "viewer", "vpc_network:enp_xxx")`.

**Then** the stub records NO `x-kacho-principal-*` headers on the wire.

**And** the iam-side (in real prod, not the test stub) would fall back to `operations.SystemPrincipal()` = `user:bootstrap` — this is the **documented legitimate path** for off-cluster admin tooling running directly against iam:9091, and W1.4 preserves it. The test asserts the wire-format absence; the fallback is iam-side behaviour already covered by existing iam tests.

### 3.6 Scenario PROP-COMPUTE-CHECK-01 — symmetric, compute side

**ID**: W1.4-PROP-COMPUTE-CHECK-01

**Given** identical setup to §3.4 but using `kacho-compute/internal/check/check_client.go`.

**When** the compute per-RPC interceptor invokes Check with usr_alice's ctx.

**Then** identical MD-on-wire assertions.

(Mirror scenario PROP-COMPUTE-CHECK-02 — empty ctx, symmetric to §3.5 — is also written; abbreviated here.)

### 3.7 Scenario PROP-E2E-01 — end-to-end through gateway → vpc → iam

**ID**: W1.4-PROP-E2E-01

**Given**
- Full stand running: api-gateway + kacho-vpc + kacho-iam + OpenFGA + Postgres.
- Bootstrap completed (W1.1 drainer applied bootstrap-admin tuples to FGA).
- User `usr_alice` has been granted `vpc.networks.get` on `prj_a` via AccessBinding (drainer wrote the FGA tuple).
- A Network `enp_alice_net_01` exists in `prj_a`.

**When** alice issues a REST request `GET /vpc/v1/networks/enp_alice_net_01` with her Bearer.

**Then** response is `200 OK` with the Network body.

**And** kacho-iam audit/log records show the Check call originated from `subject=user:usr_alice` (NOT `user:bootstrap`). Verified via `slog` capture in the integration test OR via Prometheus counter `iam_check_total{subject="user:usr_alice"}` incrementing.

**And** when alice attempts `GET /vpc/v1/networks/enp_bob_net_01` (a network in bob's project), response is `403 PermissionDenied` and iam audit shows `subject=user:usr_alice` was denied (correct attribution, pre-W1.4 would show `subject=user:bootstrap`).

### 3.8 Scenario PROP-NEWMAN-01 — newman case AUTHZ-PRINCIPAL-PROPAGATED-A

**ID**: W1.4-PROP-NEWMAN-01

**Given**
- Newman runs against the stand with W1.4 merged.
- Seed: `usr_alice` in account A, `usr_bob` in account B; `prj_a` (owner alice), `prj_b` (owner bob).
- Alice has `vpc.networks.list` on `prj_a` only.

**When** newman executes the `AUTHZ-PRINCIPAL-PROPAGATED-A` case which:
1. As alice: `GET /vpc/v1/networks?folderId=prj_b` → expect 403.
2. As alice: `GET /vpc/v1/networks?folderId=prj_a` → expect 200.
3. (Optional debug step — if §8 OQ-W1.4-4 picks the LastSeenPrincipal debug RPC) Call `InternalIAMService.LastSeenPrincipal(for_subject="user:usr_alice")` → expect non-empty list with at least one entry from the Check just executed.

**Then** all three steps pass. Pre-W1.4 step 3 would fail (the LastSeen lookup would return bootstrap, not alice).

**And** newman summary line `AUTHZ-PRINCIPAL-PROPAGATED-A: PASS`.

### 3.9 Scenario PROP-SYS-PRINCIPAL-01 — system principal helper convention

**ID**: W1.4-PROP-SYS-PRINCIPAL-01

**Given** a worker context with no user principal (e.g. a future compute-reconciler goroutine launched from `cmd/compute/main.go`).

**When** worker code constructs `ctx = operations.WithPrincipal(ctx, auth.SystemPrincipalFor("compute", "reconciler"))` before peer-calling iam.

**Then** `operations.PrincipalFromContext(ctx).ID` returns `"system:compute-reconciler"`.

**And** after `auth.PropagateOutgoing(ctx)` outgoing MD carries `x-kacho-principal-id=system:compute-reconciler`.

**And** iam audit records the worker call under `subject=user:system:compute-reconciler` (NOT `user:bootstrap`).

(This scenario documents the **convention**. W1.4 does not migrate existing workers to it; the convention applies to NEW workers landing after W1.4 merge.)

### 3.10 Scenario PROP-NEG-CLIENT-INJECT — client cannot spoof via header (verification)

**ID**: W1.4-PROP-NEG-CLIENT-INJECT

**Given** a malicious REST client crafts a request:
```
GET /vpc/v1/networks/enp_xxx
Authorization: Bearer <usr_alice_token>
X-Kacho-Principal-Id: usr_admin   ← attempted spoof
X-Kacho-Principal-Type: user
```

**When** the gateway processes this request.

**Then** the gateway STRIPS the client-supplied `X-Kacho-Principal-*` headers (auth.go:307-319 + auth.go:138-155 for the gRPC path), runs its own auth flow on the Bearer, resolves to `usr_alice`, and injects `x-kacho-principal-id=usr_alice` (not `usr_admin`) onto the outgoing MD.

**And** the backend receives `x-kacho-principal-id=usr_alice`.

(This scenario is the **defense-in-depth** verification — already enforced by KAC-122 CRIT-8 fix; W1.4 reaffirms it cannot regress because the new corelib helper does not provide any "trust client header" knob.)

---

## 4. Definition of Done

- [ ] **corelib `auth/` package** lands with `PropagateOutgoing` + `SystemPrincipalFor` + unit tests covering §3.1, §3.2, §3.9 (RED → GREEN pair shown in PR description).
- [ ] **vpc Check wrapped** — `internal/apps/kacho/check/check_client.go::IAMCheckClient.Check` calls `auth.PropagateOutgoing(ctx)`. Local `withPrincipalMD` deleted; `clients/iam_client.go` switched to the corelib helper. Integration test §3.4, §3.5 GREEN.
- [ ] **compute Check wrapped** — symmetric, integration test §3.6 GREEN.
- [ ] **iam handler verification test** — §2.5 integration test asserts handler ctx sees the propagated principal.
- [ ] **api-gateway verification test** — §2.8 integration test asserts outgoing MD has `x-kacho-principal-*` after auth-middleware fires (test PR may be skipped if equivalent assertion already exists in `auth_test.go` — reviewer to confirm).
- [ ] **Newman AUTHZ-PRINCIPAL-PROPAGATED-A** GREEN on the dev stand. Case added to `tests/newman/cases/`, regenerated collection committed, run.sh shows PASS.
- [ ] **E2E §3.7** verified manually on the dev stand: deploy W1.4-merged images of vpc + compute + corelib, run a cross-tenant request as alice against bob's project, confirm iam-side Prometheus counter / log shows `subject=user:usr_alice` not `user:bootstrap`.
- [ ] **RED→GREEN evidence** per CLAUDE.md §Запреты #11 — PR description / commit message links to the failing test commit (RED) and the fix commit (GREEN) for each of: corelib unit, vpc integration, compute integration, newman case.
- [ ] **Vault trail** — `obsidian/kacho/KAC/KAC-140.md` created with PR links + DoD checklist; `obsidian/kacho/edges/vpc-to-iam-check.md` + `obsidian/kacho/edges/compute-to-iam-check.md` History updated; `obsidian/kacho/packages/corelib-auth.md` created.
- [ ] **Plan tracker updated** — `docs/superpowers/plans/2026-05-23-iam-prod-ready-wave1.md` W1.4 row flipped to ✅ DONE with link to merged PRs.
- [ ] **No regressions** — full newman suite still 1057/1144 GREEN minimum (the 87 known failures from baseline are NOT W1.4's responsibility; W1.6 Chunk 2 closes those). Specifically: `authz-deny.py` suite still GREEN; `iam-internal-only-check.py` suite still RED (no change expected — W1.6 closes it).
- [ ] **Two-stage review** — code-reviewer subagent approval + acceptance-reviewer reconfirm on this doc after PR-set is open.

---

## 5. Out of scope (re-stated for emphasis)

- API-token / service-account principal **minting** (Block F / W1.5) — propagation works for SA principals already once a service-account-issued JWT is processed by the gateway (gateway sets `x-kacho-principal-type=service_account` per auth.go:196-202). W1.4 does not add SA minting.
- mTLS / SPIRE / workload identity (W3).
- Per-worker migration to `SystemPrincipalFor` — only the new helper + convention. Existing `BreakGlassExpirerWorker.Tick` etc. keep their current `SystemPrincipal()`-via-empty-ctx fallback until a follow-up KAC tracked from W1.4 closure note.
- vpc/compute server-side strip of `x-kacho-principal-*` (defense-in-depth duplication of the gateway strip). See §8 OQ-W1.4-2.
- Newman expansion beyond the one new case. W2 Поток D.

---

## 6. Risk assessment

| Risk | Severity | Mitigation |
|---|---|---|
| Outgoing MD wrap regresses an existing call path that depended on absent MD (e.g. a test stub keyed on "no metadata" → would now match by-mistake) | **Low** | All non-Check call paths in vpc/compute already use the local `withPrincipalMD` helper (KAC-127 Bug-2). Switching them to `auth.PropagateOutgoing` is a byte-for-byte equivalent (same MD keys, same fallback for empty ctx). Integration tests §3.4, §3.5 + existing KAC-127 integration tests cover both paths. |
| `metadata.AppendToOutgoingContext` semantics surprise — re-wrapping appends, does not overwrite | **Low** | `PropagateOutgoing` is a one-shot call on the outermost adapter (CheckClient.Check). Worker → CheckClient → grpc.Client chain has one wrap. Unit test §3.1 + scenario PROP-CORELIB-01 PROP-CORELIB-02 PROP-CORELIB-02-Double pin the contract. |
| Newman case requires iam-side observability (`LastSeenPrincipal` debug RPC) and we don't want a debug RPC in prod proto | **Medium** | Decide in §8 OQ-W1.4-4: either (a) add Prometheus counter `iam_check_subject_total{subject="..."}` and assert via scrape from newman, (b) inspect iam pod logs from newman (fragile), (c) add a kacho-only `Internal*` debug RPC gated behind dev-mode flag. Recommendation: counter — already on the standard observability path. |
| Anonymous propagation: gateway sets `system:anonymous`, vpc propagates it forward, iam sees `system:anonymous` instead of nothing — could behave differently from the no-MD fallback | **Low** | `corelib/authz/subject_extract.go:40-52::isAnonymousSubject` already maps both `subject="system:anonymous"` and absent-MD-→-bootstrap to the same anonymous-deny outcome (KAC-122 CRIT-6/7). Negative test §3.10 + existing `authz-deny` suite covers it. |
| System workers post-W1.4 keep using bootstrap until follow-up — incomplete attribution in audit | **Medium** | Acceptable for W1.4 scope (which is propagation, not worker migration). Follow-up issue tracked in §8 OQ-W1.4-3 with explicit "no SLA on completion" — workers run in trusted contexts where bootstrap-attribution is currently acceptable. |

---

## 7. Traceability

- **production-launch-plan WS-2.5** — "principal propagation сервис→сервис через gateway (`vpc#104` — vpc видит `user:bootstrap` для всех cross-service вызовов)". W1.4 closes the part that lives in the kacho-iam epic (KAC-134); the gateway side is W1.3 (fail-closed) + already-existing `auth.injectPrincipal`. The `vpc#104` reference is to the legacy GH issue that became KAC-140.
- **product-completion-freeze-plan §D.5** — "principal propagation сервис→сервис (`vpc#104`)". Same issue; same closure path.
- **No remediation finding ID closes here** — W1.4 is structural plumbing, not a finding-traced fix. The W1.5 / W1.6 chunks close specific findings (#8, #16, #47, #48, #50, #51, #52 for W1.5; #9, #11, #12, #13, #35, #36, #37, #39, #43, #53 for W1.6); W1.4 is the prerequisite for finding #35 (AccessReview reviewer spoofing — depends on iam knowing the real principal) and finding #43 (anti-anonymous interceptor — depends on iam not falling back to bootstrap on real user traffic).
- **KAC-127 Bug-2** — original principal-propagation fix landed `withPrincipalMD` in vpc/compute but only wrapped ProjectService.Get. W1.4 finishes the work for the authz Check path AND lifts the helper to corelib.
- **KAC-107 (E2)** — established the `x-kacho-principal-*` MD convention + `corelib/grpcsrv.UnaryPrincipalExtract`. W1.4 sits on top of E2's plumbing.
- **KAC-122 CRIT-6/7/8** — anonymous-deny semantics + client-spoof strip. W1.4 verifies neither regresses.

---

## 8. Open questions

| ID | Question | Recommendation |
|---|---|---|
| OQ-W1.4-1 | Location of `MDKeyPrincipal*` constants: keep them in `corelib/grpcsrv/` (current home) or move to `corelib/auth/`? | **Keep in `corelib/grpcsrv/`** and re-export via `auth/`. Reason: the constants belong to the server-side extraction package (they describe wire-format headers used both ways). Moving them creates an import-cycle risk if `auth/` ever wants to use `grpcsrv` helpers later. Re-export pattern: `var (MDKeyPrincipalType = grpcsrv.MDKeyPrincipalType; ...)`.  |
| OQ-W1.4-2 | Add server-side `strip-incoming-principal-headers` to vpc/compute as defense-in-depth (mirror of gateway's KAC-122 CRIT-8 strip)? | **No, defer to a follow-up**. The cluster-internal listener (9090/9091) is mTLS-only (per workspace CLAUDE.md §запрет #6 and the helm chart's NetworkPolicy / Service-of-type-ClusterIP); a tenant cannot reach it directly. If anti-defense-in-depth becomes a real concern (e.g. compromised peer pod), add the strip in a separate KAC ticket under W3 (observability/hardening wave). W1.4 documents this in a comment in `corelib/auth/propagate.go` header. |
| OQ-W1.4-3 | Should W1.4 also migrate existing workers (`BreakGlassExpirerWorker.Tick`, future compute reconcilers, fga_outbox drainer) to `SystemPrincipalFor` instead of bootstrap? | **No, the helper is sufficient for now**. Migration of N existing workers is per-worker risk (each may have implicit assumptions about ctx state, especially `BreakGlassExpirerWorker` which calls iam from inside iam — same-process). Track as `KAC-140-followup` issue. The convention is normative for any NEW worker landing after W1.4 merge. |
| OQ-W1.4-4 | How does the newman case `AUTHZ-PRINCIPAL-PROPAGATED-A` verify the principal-attribution claim? | **Option (a) — Prometheus counter**. Add `iam_check_subject_total{subject="..."}` Counter to iam's existing Prometheus metrics (one extra line in `internal/apps/kacho/api/internal_iam/handler.go::Check`). Newman scrapes the counter pre/post and asserts the delta on the `subject="user:usr_alice"` bucket. Reasons over the alternatives: (b) log-scraping is fragile (multi-pod, log-rotation); (c) a dev-only RPC is a proto-surface change for test-only data. Counter is on the standard observability path and useful for ops anyway. |
| OQ-W1.4-5 | Does W1.4 unblock W1.6 finding #35 (AccessReview reviewer spoofing) or is more work needed? | **Necessary but not sufficient**. W1.6 #35 needs (a) the propagated principal (W1.4) AND (b) handler-side enforcement that `request.ReviewerId == ctx.Principal.ID` (W1.6 Chunk 2 work). W1.4 is the prerequisite. Documented in W1.6 acceptance-doc to be written. |
| OQ-W1.4-6 | The corelib new package — naming: `corelib/auth/` vs `corelib/principal/` vs `corelib/identity/`? | **`corelib/auth/`** — generic enough to absorb future helpers (token validation utilities, principal builders, etc.) without being too specific (`/principal/` suggests data-only) or too broad (`/identity/` collides with Zitadel identity terminology). Workspace CLAUDE.md does not pre-allocate this name. |
