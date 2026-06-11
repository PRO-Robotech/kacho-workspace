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
status: planned
related_tickets:
  - "[[../KAC/SEC-A-proto-fga-proxy]]"
  - "[[../KAC/SEC-C-iam-fga-proxy-sa-roles]]"
tags:
  - edge
  - kacho-compute
  - kacho-iam
  - cross-service
  - security
  - internal
---

> [!note] Callee-сторона готова в SEC-C; caller-сторона — SEC-D
> `kacho-iam.InternalIAMService.RegisterResource/UnregisterResource` реализован
> ([[../KAC/SEC-C-iam-fga-proxy-sa-roles]]). kacho-compute начнёт вызывать это ребро в
> SEC-D (удаление прямого OpenFGA-клиента → outbox-intent в writer-tx ресурса →
> drainer→IAM.RegisterResource по mTLS). Контракт «FGA за IAM» (эпик #6).

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

## See also

[[../rpc/iam-internal-iam-service]] [[../resources/iam-service-account]] [[compute-to-iam-check]] [[vpc-to-iam-fgaproxy]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#edge #kacho-compute #kacho-iam #cross-service #security #internal
