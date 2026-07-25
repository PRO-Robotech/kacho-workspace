---
title: "owner-tuple confirm-read → OpenFGA HIGHER_CONSISTENCY"
category: edges
caller_repo: kacho-iam
callee_repo: openfga
sync_async: sync
protocol: http
status: experimental
related_tickets:
  - "[[../KAC/sub-phase-1.4-tuple-resource-guarantee]]"
tags:
  - edge
  - kacho-iam
  - kacho-vpc
  - kacho-compute
  - kacho-storage
  - kacho-nlb
---

# owner-tuple confirm-read → OpenFGA HIGHER_CONSISTENCY (Koren-1)

Read-consistency of the owner-tuple **confirm-gate** probe. Distinct from the
grant/revoke *write* edge (`iam-to-openfga-grant-write`) and the *enforcement*
per-RPC gate — this is the read-after-**OWN**-write confirm the async Create-op
worker gates `done=success` on.

## Root cause (systematic-debugging, confirmed)

The owner-tuple is written SYNCHRONOUSLY to OpenFGA on the create path
(reconcile `WithSyncFGA`, iam wiring), but the confirm-probe read it back through
`InternalIAMService.Check` with the OpenFGA **default** consistency
(`MINIMIZE_LATENCY`). Under the deployed **multi-replica** OpenFGA
(`openfga.replicaCount=2`, shared Postgres, ClusterIP) the confirm read can land
on a **different** replica than the sync write and be served a stale-negative
from that replica's cache → confirm retries until it clears. Measured op tail:
p50=14ms, **p95=3.1s, max~10s** — saturated the newman poll window (~85% of
e2e gate failures). NOT a materialization stall (grant materializes fast).

## Fix

- Additive `iam.v1.CheckRequest.consistency` enum (`HIGHER_CONSISTENCY`; field 5,
  internal-only msg → buf breaking=0). iam Check handler forwards it to the
  OpenFGA `Check` wire (`consistency` field).
- Confirm probes (read-after-own-write) send `HIGHER_CONSISTENCY` → OpenFGA
  bypasses cache/replica lag → ALLOW on the **first** attempt:
  - vpc `check.OwnerConfirmer` (Network/SG/Subnet **+ Address/RouteTable/Gateway/
    NetworkInterface**, opgate coverage-completion 2026-07-17) — `IAMCheckClient.CheckConsistent`
  - nlb `check.OwnerConfirmer` (LoadBalancer/Listener/TargetGroup, 2026-07-17) —
    `iamclient.checkClient.CheckConsistent` (added; nlb registers owner-tuples via
    NOTIFY-driven `fga_register_outbox` drainer, no sync-registrar — confirm still
    strong-consistent, gate `peers.Check!=nil && FGA.RegisterDrainer.Enable`)
  - compute `ports.OwnerConfirmer` (Instance/Disk) — `CheckConsistent`
  - storage `check.VolumeOwnerConfirmer` (Volume) — `CheckConsistent`
  - iam in-process `CreateAccessBindingUseCase.ownerTupleConfirm` — `RelationStore.CheckConsistent`
- worker confirm-backoff first retry 50ms→25ms.
- newman Operation-poll cap raised (storage 8→30, compute/vpc 20→30) as p99 margin.

## Invariants

- The hot per-RPC **enforcement** gate is UNTOUCHED (unset consistency →
  MINIMIZE_LATENCY, cache-eligible, low-latency). Only confirm reads force strong.
- No new cross-service edge (reuses the existing `<svc>→iam InternalIAMService.Check`).
- Fail-closed / deny-mapping / existence-hiding semantics unchanged.
