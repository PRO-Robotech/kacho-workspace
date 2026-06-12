---
title: "compute → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)"
aliases:
  - compute to iam fgaproxy
  - compute register resource
category: edge
caller_repo: kacho-compute
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: done
related_tickets:
  - "[[../KAC/SEC-A-proto-fga-proxy]]"
  - "[[../KAC/SEC-C-iam-fga-proxy-sa-roles]]"
  - "[[../KAC/SEC-D-services-fga-via-iam-mtls]]"
tags:
  - edge
  - kacho-compute
  - kacho-iam
  - cross-service
  - security
  - internal
---

> [!note] Реализовано в SEC-D (caller); callee — SEC-C
> `kacho-iam.InternalIAMService.RegisterResource/UnregisterResource` реализован
> ([[../KAC/SEC-C-iam-fga-proxy-sa-roles]]). kacho-compute вызывает это ребро с SEC-D:
> прямой OpenFGA-клиент удалён, owner-tuple intent пишется в `compute_fga_register_outbox`
> в writer-tx ресурса, register-drainer → IAM.RegisterResource по (opt-in) mTLS.
> Контракт «FGA за IAM» (эпик #6); dual-write баг N5 устранён.

# compute → iam: FGA-proxy owner-tuple write/delete

**Protocol**: gRPC cluster-internal :9091 (Internal-only, ban #6; нет на external).
**Direction**: усиление существующего `compute → iam` (ацикличность сохранена).

## Контракт

Идентичен [[vpc-to-iam-fgaproxy]]: `RegisterResource`/`UnregisterResource` с
`{subject_id, relation, object, trace_id}`, идемпотентность как контракт (write
`already_exists`→OK, delete absent→OK), at-least-once через transactional-outbox (SEC-D).
IAM эмитит owner-tuple в `kacho_iam.fga_outbox`+drainer для compute-ресурсов
(`compute_instance:<...>` и т.п.).

## Authz (least-priv, SEC-C)

mTLS client-cert SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-compute` → `sva`-id compute
→ ReBAC `Check(service_account:<sva-compute>, fga_writer, iam_fgaproxy:system)`. compute-SA
несёт relation-tuple (seed `0009`). Нет relation → `PermissionDenied`.

## Caller-side mechanics (SEC-D, kacho-compute)

- **Intent в writer-tx**: `internal/repo/outbox.go::emitFGARegisterIntent` пишет строку в
  `compute_fga_register_outbox` (миграция `0010`) В ТОЙ ЖЕ tx, что Insert/Delete ресурса
  (Instance/Disk/Image/Snapshot + inline boot/secondary disks). `event_type ∈
  {fga.register, fga.unregister}`; payload — set из `fgaintent.Tuple`
  (`project:<projectId> #project @compute_<kind>:<id>`). Tx abort → intent откатывается (no orphan).
- **Drainer**: corelib `outbox/drainer` (`cmd/compute/main.go::startRegisterDrainer`,
  default-on `KACHO_COMPUTE_FGA_REGISTER_DRAINER_ENABLED`), channel/table
  `compute_fga_register_outbox`. Applier — `internal/clients/iam_register_applier.go`
  (`RegisterResource`/`UnregisterResource`). CAS-claim/advisory-lock → exactly-once across replicas.
- **Error-маппинг**: `InvalidArgument` → poison (no retry); прочее (Unavailable/mTLS-mismatch)
  → transient retry с backoff. IAM down → intent durable, Operation не падает (tuple не теряется).
- **mTLS (opt-in)**: `cfg.IAMRegisterMTLS` (`grpcclient.TLSClient`, env
  `KACHO_COMPUTE_IAM_REGISTER_MTLS_*`); `enable=false` → insecure (dev). Server-listener creds —
  `PUBLIC_SERVER_MTLS`/`INTERNAL_SERVER_MTLS` (`grpcsrv.TLSServer`).
- **Удалено**: `internal/clients/openfga_write_client.go`, `internal/fgawrite/` (прямой HTTP-write FGA).

## History

- **SEC-D** ([[../KAC/SEC-D-services-fga-via-iam-mtls]]): caller-сторона реализована — прямой FGA
  удалён, transactional-outbox + register-drainer + opt-in mTLS. Закрыт dual-write баг N5.

## See also

[[../rpc/iam-internal-iam-service]] [[../resources/iam-service-account]] [[compute-to-iam-check]] [[vpc-to-iam-fgaproxy]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#edge #kacho-compute #kacho-iam #cross-service #security #internal
