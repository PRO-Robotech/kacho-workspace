---
title: "vpc → iam: per-RPC OpenFGA Check (E3)"
aliases:
  - vpc to iam check
  - vpc authz check
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-vpc
  - kacho-iam
  - cross-service
  - authz
  - e3
---

> [!success] Active since 2026-05-17 (KAC-108 E3, kacho-vpc PR#101)
> Edge активен; kacho-vpc на КАЖДОМ публичном RPC синхронно вызывает
> `kacho-iam.InternalIAMService.Check(subject, relation, object)` через
> `internal/apps/kacho/check/`-interceptor. Кеш positive=5s; revoke ≤10s
> через TTL + outbox-drain.

# vpc → iam: per-RPC Check (E3)

**Caller:** `kacho-vpc` (`internal/apps/kacho/check/` — gRPC unary+stream interceptor поверх corelib `authz`).
**Callee:** `kacho-iam.InternalIAMService.Check` (port 9091).
**Protocol:** gRPC cluster-internal (direct dial; не через api-gateway).
**Sync/Async:** **sync** (на каждом public RPC, до вызова handler'а).

## When invoked

- На каждом публичном RPC kacho-vpc: NetworkService, SubnetService,
  AddressService, RouteTableService, SecurityGroupService, GatewayService,
  PrivateEndpointService, NetworkInterfaceService, OperationService.Get/Cancel
  (60+ RPC, см. [[../packages/vpc-apps-kacho-check]] permission_map).
- На каждый stream RPC (Watch / Subscribe) — auth-decision до открытия stream.
- `Internal*` RPC — bypass (admin :9091 listener, запрет workspace #6).

## Object types

`vpc_network`, `vpc_subnet`, `vpc_address`, `vpc_route_table`,
`vpc_security_group`, `vpc_gateway`, `vpc_private_endpoint`,
`vpc_network_interface`, `vpc_operation`, `project`.

## Cache

- Positive-only TTL 5s (corelib/authz `Cache`).
- `pg_notify('kacho_iam_subjects', subject_id)` → `InvalidateBySubject`
  (НЕ wired в текущем MVP — KAC-108 follow-up).
- Worst-case revoke: TTL=5s + NOTIFY≤1s + outbox-drain≤2s ≤ 10s (acceptance NFR-5).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| allowed=true | (continue handler) | cache positive 5s |
| allowed=false | `PermissionDenied "permission denied"` | not cached |
| iam недоступен | `PermissionDenied "authorization service unavailable"` | **fail-closed** (acceptance D-6) |
| no Principal в ctx | `PermissionDenied` | защита от misconfig auth-interceptor (E2) |
| Unmapped RPC | `PermissionDenied "permission denied (rpc not mapped)"` | drift-guard |
| Internal* RPC | bypass | heuristic — public listener не маршрутизирует Internal'ы |

## Break-glass

`KACHO_VPC_AUTHZ__BREAKGLASS=true` → bypass + WARN-метрика. Dev/emergency only.

## Configuration

```yaml
# values.yaml (kacho-vpc)
authz:
  iam-endpoint: kacho-iam.kacho.svc.cluster.local:9091
  iam-tls:
    enable: false
  breakglass: false
  cache-ttl: 5s
  check-timeout: 2s
  deny-rate-limit-per-sec: 100
```

Если `iam-endpoint` пуст и `breakglass=false` → interceptor НЕ навешивается
(graceful start без kacho-iam в dev). В production это ошибка — fail на старте.

## History

- **2026-05-24** (W1.4, [[../KAC/KAC-140]]): principal propagated через
  `auth.PropagateOutgoing` — iam Check теперь видит caller Principal, не
  `user:bootstrap`. Closes round-3 finding из [[../KAC/KAC-127]].
- 2026-05-17 (E3, [[../KAC/KAC-108]]): edge initial, kacho-vpc PR#101.

## See also

[[../packages/vpc-apps-kacho-check]] [[../packages/corelib-authz]] [[../packages/corelib-auth]] [[iam-to-openfga-check]] [[compute-to-iam-check]] [[../KAC/KAC-108]] [[../KAC/KAC-122]] (authz-deny newman suite) [[../KAC/KAC-140]]

#edge #kacho-vpc #kacho-iam #cross-service #authz #e3
