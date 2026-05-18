---
title: proto-compute
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - kacho-compute
---

# proto/compute

**Path**: `kacho-proto/proto/kacho/cloud/compute/v1/`
**Package**: `kacho.cloud.compute.v1`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/compute/v1`
**Owner service**: `kacho-compute` (вне scope этой 6-репо индексации, но proto тут)

## Resource protos (compute domain)

- `instance.proto` — Instance (VM)
- `disk.proto`, `disk_type.proto`, `disk_placement_group.proto`
- `image.proto`, `snapshot.proto`, `snapshot_schedule.proto`
- `filesystem.proto`, `gpu_cluster.proto`
- `host_group.proto`, `host_type.proto`, `placement_group.proto`
- `reserved_instance_pool.proto`
- `instance_group.proto` — Compute IG (autoscaling)
- `application.proto`, `hardware_generation.proto`, `kek.proto`, `maintenance.proto`

## Geography (после KAC-15 — owner = compute, не vpc)

- `region.proto` / `region_service.proto`
- `zone.proto` / `zone_service.proto`

Tenant read через api-gateway `/compute/v1/regions` + `/compute/v1/zones`; admin-мутации — `InternalCatalogService`. См. [[../edges/vpc-to-compute-zone-validate]].

## Internal services

- `internal_catalog_service.proto` — admin для Region/Zone/HostType (+ Hypervisor — internal-only ресурс, см. CLAUDE.md «Инфра-чувствительные данные»).
- `internal_watch_service.proto` — LISTEN/NOTIFY (deprecated с 1.0).

## Service protos

Полный per-resource: `<resource>_service.proto` для каждого ресурса (Get/List/Create/Update/Delete). NIC валидируется через vpc, см. [[../edges/compute-to-vpc-nic-validate]].

#proto #kacho-compute
