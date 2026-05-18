---
title: proto-loadbalancer
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - kacho-loadbalancer
---

# proto/loadbalancer

**Path**: `kacho-proto/proto/kacho/cloud/loadbalancer/v1/`
**Package**: `kacho.cloud.loadbalancer.v1`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/loadbalancer/v1`
**Owner service**: `kacho-loadbalancer` (вне scope этой индексации, frozen в 1.0)

## Resource protos

- `network_load_balancer.proto` — NLB
- `target_group.proto` — TargetGroup (members → Instance via NIC)
- `health_check.proto` — HealthCheck spec (HTTP/TCP/HTTPS)

## Service protos

- `network_load_balancer_service.proto` — `NetworkLoadBalancerService`
- `target_group_service.proto` — `TargetGroupService`

## Status

В 1.0 — proto verbatim YC, backend ещё не переписан с YC-shim. Подключение в Kachō-stack по мере готовности `kacho-loadbalancer` сервиса.

#proto #kacho-loadbalancer
