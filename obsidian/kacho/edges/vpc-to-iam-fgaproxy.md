---
title: "vpc → iam: FGA-proxy RegisterResource/UnregisterResource (SEC)"
aliases:
  - vpc to iam fgaproxy
  - vpc register resource
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: planned
related_tickets:
  - "[[../KAC/SEC-A-proto-fga-proxy]]"
  - "[[../KAC/SEC-C-iam-fga-proxy-sa-roles]]"
tags:
  - edge
  - kacho-vpc
  - kacho-iam
  - cross-service
  - security
  - internal
---

> [!note] Callee-сторона готова в SEC-C; caller-сторона — SEC-D
> `kacho-iam.InternalIAMService.RegisterResource/UnregisterResource` реализован
> ([[../KAC/SEC-C-iam-fga-proxy-sa-roles]]). kacho-vpc начнёт вызывать это ребро в
> SEC-D (удаление прямого OpenFGA-клиента → outbox-intent в writer-tx ресурса →
> drainer→IAM.RegisterResource по mTLS). Контракт «FGA за IAM» (эпик #6).

# vpc → iam: FGA-proxy owner-tuple write/delete

**Protocol**: gRPC cluster-internal :9091 (Internal-only, ban #6; нет на external).
**Direction**: усиление существующего `vpc → iam` (ацикличность: iam не зовёт vpc).

## Контракт

- `RegisterResource({subject_id, relation, object, trace_id})` → пустой response (sync).
  IAM эмитит owner-hierarchy tuple в `kacho_iam.fga_outbox` в одной writer-tx; drainer
  применяет к OpenFGA. **Идемпотентно**: повтор → OK (не AlreadyExists).
- `UnregisterResource(...)` — симметричный revoke; снятие отсутствующего → OK (не NotFound).
- **at-least-once**: vpc-сторона (SEC-D) пишет intent в свой outbox в той же tx, что и
  Insert ресурса (no dual-write); drainer ретраит при IAM `Unavailable` — tuple не теряется.

## Authz (least-priv, SEC-C)

mTLS client-cert SAN `spiffe://kacho.cloud/ns/kacho-system/sa/kacho-vpc` → `sva`-id vpc →
ReBAC `Check(service_account:<sva-vpc>, fga_writer, iam_fgaproxy:system)`. vpc-SA несёт этот
relation-tuple (seed `0009`). Нет relation → `PermissionDenied`.

## See also

[[../rpc/iam-internal-iam-service]] [[../resources/iam-service-account]] [[vpc-to-iam-check]] [[compute-to-iam-fgaproxy]] [[iam-to-openfga-grant-write]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#edge #kacho-vpc #kacho-iam #cross-service #security #internal
