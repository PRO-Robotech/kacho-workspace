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
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-nlb/internal/clients/compute

**Каталог**: `services/nlb/internal/clients/compute/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-nlb/internal/clients/compute/`)
**Imports**: `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/compute/v1`, [[corelib-retry]]
**Imported by**: [[nlb-apps-kacho-api-targetgroup]] (Instance resolve)

Typed peer-service gRPC client adapters для kacho-compute.

> [!note] Region-валидация ушла в geo (эпик #82)
> `region_client.go`/`region_cache.go` удалены — region-валидация теперь `nlb → geo` через
> `internal/clients/geo/region_client.go` (без кэша). См. [[../edges/nlb-to-geo-region-validate]].
> Этот пакет остаётся **только** для Instance-таргет-resolve ([[../edges/nlb-to-compute-instance-resolve]]).

## Files

| File | Содержание |
|---|---|
| `instance_client.go` | wraps `computepb.InstanceServiceClient.Get` — для Target.instance_id resolve. NO cache (instance state может меняться quickly). |
| `*_test.go` | unit-tests (retry + NotFound mapping) |

## Pattern

Port-interface в service-layer; adapter реализует через gRPC stub + retry.

## Instance — no cache

`InstanceService.Get` для Target resolve — каждый раз свежий ответ (status может меняться, primary IP может перевыделиться). Acceptable latency для async worker.

## Imports

- `github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/compute/v1`
- `kacho-corelib/retry`

## See also

[[../edges/nlb-to-compute-instance-resolve]] [[../edges/nlb-to-geo-region-validate]] [[nlb-clients-geo]] [[nlb-apps-kacho-api-targetgroup]]

#packages #kacho-nlb #clients #cross-service #compute
