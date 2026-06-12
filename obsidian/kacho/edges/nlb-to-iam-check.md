---
title: "nlb → iam: per-RPC OpenFGA Check (E3)"
aliases:
  - nlb to iam check
  - nlb authz check
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-156]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-nlb
  - kacho-iam
  - cross-service
  - authz
  - e3
---

> [!success] Active since 2026-05-24 (KAC-141, kacho-nlb PR#13)
> Edge активен; kacho-nlb на КАЖДОМ публичном RPC синхронно вызывает
> `kacho-iam.InternalIAMService.Check(subject, relation, object)` через
> `internal/check/`-interceptor. Adopts pattern из vpc/compute (corelib/authz).

# nlb → iam: per-RPC Check (E3)

**Caller**: `kacho-nlb` (`internal/check/` — gRPC unary+stream interceptor поверх corelib `authz`)
**Callee**: `kacho-iam.InternalIAMService.Check` (port 9091)
**Protocol**: gRPC cluster-internal (direct dial; не через api-gateway)
**Sync/Async**: **sync** (на каждом public RPC, до вызова handler'а)

## When invoked

- На каждом публичном RPC kacho-nlb: NetworkLoadBalancerService (12), ListenerService (6), TargetGroupService (9), OperationService (3) — ~30+ RPC.
- `Internal*` RPC (InternalResourceLifecycleService) — **bypass** (admin :9091 listener, workspace CLAUDE.md #6).

## Object types

`nlb_load_balancer`, `nlb_listener`, `nlb_target_group`, `nlb_operation`, `project`.

## Permission semantics (permission_map)

См. [[../packages/nlb-internal-check]]:
- `Get` / `List` → `viewer` (на ресурсе или parent `project`)
- `Create` → `editor` на `project:<project_id>`
- `Update` / `Delete` / `<verb>` (Start/Stop/Move/Attach/Detach/AddTargets/RemoveTargets) → `editor` на конкретном resource
- `OperationService.Get/Cancel` → `viewer`/`editor` на `nlb_operation:<id>`

## Cache

- Positive-only TTL 5s (corelib/authz `Cache`).
- `pg_notify('kacho_iam_subjects', subject_id)` → `InvalidateBySubject` (LISTEN-invalidate; KAC-140 W1.4 — principal propagated в Check).
- Worst-case revoke: TTL=5s + NOTIFY≤1s + outbox-drain≤2s ≤ 10s (NFR-5).

## ErrNoPath passthrough (KAC-133 pattern)

Если iam Check возвращает `ErrNoPath` (FGA hierarchy tuple ещё не записан, типично сразу после Create) → corelib/authz возвращает `DecisionNoPath` → interceptor пропускает к handler'у, который вернёт `NOT_FOUND` из БД (вместо masking как 403). Adopt'аем pattern из vpc/compute.

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| allowed=true | (continue handler) | cache positive 5s |
| allowed=false | `PermissionDenied "permission denied"` | not cached |
| iam недоступен | `PermissionDenied "authorization service unavailable"` | **fail-closed** |
| no Principal в ctx | `PermissionDenied` | защита от misconfig auth-interceptor (E2) |
| Unmapped RPC | `PermissionDenied "permission denied (rpc not mapped)"` | drift-guard |
| ErrNoPath | (passthrough → handler → DB) | KAC-133 pattern |
| Internal* RPC | bypass | heuristic |

## Break-glass

`KACHO_NLB_AUTHZ__BREAKGLASS=true` → bypass + WARN-метрика. Dev/emergency only.

## Transport mTLS (SEC-I)

Check идёт по **internal** iam-conn'у (`iamInternalConn`, :9091), общему с
register-drainer. SEC-D дал ему client-cert (`cfg.MTLS.IAMRegister`,
ServerName=`kacho-iam-internal.*`). SEC-I **подтверждает**, что authz/Check-ребро
покрыто этим же conn'ом (отдельного list-filter-conn у nlb нет — Check для List
идёт через тот же `iamInternalConn`). Read-ребро ProjectService.Get (:9090,
[[nlb-to-iam-creator-tuple|public iam-conn]]) получило **отдельное** поле
`cfg.MTLS.IAMProject` (ServerName=`kacho-iam.*`) — per-listener split (I6), т.к.
единый ServerName не покрывает оба listener'а под SEC-H. `enable=false` → insecure
(dev). Completeness (SEC-I-07): оба iam-conn'а nlb предъявляют `kacho-nlb-client-tls`.

## See also

[[../packages/nlb-internal-check]] [[../packages/corelib-authz]] [[vpc-to-iam-check]] [[compute-to-iam-check]] [[../KAC/KAC-108]] [[../KAC/KAC-141]]

#edge #kacho-nlb #kacho-iam #cross-service #authz #e3
