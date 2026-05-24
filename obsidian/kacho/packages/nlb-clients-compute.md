---
title: nlb-clients-compute
category: packages
repo: kacho-nlb
layer: clients
tags:
  - packages
  - kacho-nlb
  - clients
  - cross-service
  - compute
---

# kacho-nlb/internal/clients/compute

**Path**: `kacho-nlb/internal/clients/compute/`
**Imports**: `kacho-proto/gen/go/kacho/cloud/compute/v1`, [[corelib-retry]]
**Imported by**: [[nlb-apps-kacho-api-loadbalancer]] (Region check), [[nlb-apps-kacho-api-targetgroup]] (Region + Instance resolve)

Typed peer-service gRPC client adapters для kacho-compute.

## Files

| File | Содержание |
|---|---|
| `region_client.go` | wraps `computepb.RegionServiceClient` — `Exists(ctx, regionID)`, `Get(ctx, regionID)`; TTL+LRU 60s |
| `region_cache.go` | LRU cache impl |
| `instance_client.go` | wraps `computepb.InstanceServiceClient.Get` — для Target.instance_id resolve. NO cache (instance state может меняться quickly). |
| `*_test.go` | unit-tests (cache + retry + NotFound mapping) |

## Pattern

Port-interface в service-layer; adapter реализует через gRPC stub + retry.

## Region cache rationale

Regions — почти immutable (admin-domain). 60s TTL — safe. Positive-only.

## Instance — no cache

`InstanceService.Get` для Target resolve — каждый раз свежий ответ (status может меняться, primary IP может перевыделиться). Acceptable latency для async worker.

## Imports

- `kacho-proto/gen/go/kacho/cloud/compute/v1`
- `kacho-corelib/retry`

## See also

[[../edges/nlb-to-compute-region-validation]] [[../edges/nlb-to-compute-instance-resolve]] [[nlb-apps-kacho-api-loadbalancer]] [[nlb-apps-kacho-api-targetgroup]]

#packages #kacho-nlb #clients #cross-service #compute
