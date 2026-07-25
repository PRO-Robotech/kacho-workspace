---
title: "compute → storage: boot/volume Referrer resolve (COMP-1/STOR-1 split)"
aliases:
  - compute to storage volume resolve
category: edge
caller_repo: kacho-compute
callee_repo: kacho-storage
sync_async: sync
protocol: grpc-cluster-internal
status: in-progress
related_tickets:
  - "[[KAC/redesign-2026]]"
tags:
  - edge
  - cross-service
  - kacho-compute
  - kacho-storage
---

> [!note] New edge (compute↔storage split, redesign-2026)
> Раскол compute → compute + storage: storage владеет Volume/Image/Snapshot; compute ссылается на них
> через **Referrers** (`bootSource`→storage.image, `bootVolume°`/`secondaryVolumes°`→storage.volume) и
> резолвит/аттачит **через owner** (attach-via-owner, не re-implement storage). См. [[compute-storage-split-concept]].

# compute → storage: boot/volume resolve (split)

**Caller**: `kacho-compute` (`internal/clients/storage_client.go`).
**Callee**: `kacho-storage` (`InternalVolumeService` :9091 + Volume/Image resolve).
**Protocol**: gRPC cluster-internal :9091 (**mTLS** — `kacho-compute-client-tls` leaf, ServerName
`kacho-storage` ∈ storage server-cert SAN; per-edge `enable`).
**Sync/Async**: sync на request-path (`Instance.Create.launch` резолвит boot-source/volumes).

## When invoked

- `Instance.Create` — резолвить `bootSource` (storage.image/registry.image), аттачить `bootVolume°`/
  `secondaryVolumes°` (storage.volume) через owner (attach-via-owner CAS на storage-стороне).
- placement-coherence: Instance ↔ Volume та же зона (peer-validate).

## Error handling (peer-validate, fail-closed)

| Result | gRPC code |
|---|---|
| volume/image существует, зона совпадает | OK |
| не найден | `FAILED_PRECONDITION` (peer-miss) |
| зона не совпадает | `FAILED_PRECONDITION` (placement-coherence) |
| storage недоступен | `UNAVAILABLE` (fail-closed мутации) |

## Saga-compensation

Instance.Create.launch — one-shot saga (vpc IPAM/NIC + storage boot-Volume). Partial-fail →
compensation-outbox инициатора (compute) эмитит обратные `Delete`/`ClearReference` до пометки
Operation error (см. `data-integrity.md` saga-compensation B12). storage/vpc sweeper — backstop.

## Ацикличность

storage не зовёт compute обратно (одностороннее). Цикла нет.

## Deploy

compute chart: `storageInternalAddr` (default `kacho-storage…:9091`) + `mtls.edges.storage` +
`mtls.serverName.storage` (first-class edge, commit `a91d9cc`). storage-chart: `fullnameOverride:
kacho-storage` + Certificate SAN `kacho-storage` (commit `fc56e99`).

## History

- **2026-07-20** (redesign-2026, COMP-1/STOR-1): ребро введено split'ом. Backend compute COMP-1 +
  storage STOR-1; deploy first-class wiring. [[storage-to-iam-fgaproxy]] (owner-tuple для scope_extractor).
