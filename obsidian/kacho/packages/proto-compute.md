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

## Geography — ВЫНЕСЕНА в `kacho-geo` (эпик #82)

> [!warning] Region/Zone больше не в `compute.v1`
> Geography (Region/Zone + RegionService/ZoneService + InternalRegion/ZoneService) вынесена в новый
> leaf-домен `kacho.cloud.geo.v1` (см. [[proto-geo]]). На S7 эпика #82 эти proto удаляются из `compute.v1`
> (намеренный `buf breaking`, ПОСЛЕ перевода всех consumer'ов). REST `/compute/v1/regions`/`/compute/v1/zones`
> → `/geo/v1/regions`/`/geo/v1/zones`. zone-валидация compute теперь [[../edges/compute-to-geo-zone-validate]].

## Internal services

- `internal_catalog_service.proto` — admin для DiskType/HostType. (Region/Zone-ветки вынесены в geo, эпик #82;
  прежний internal-only `Hypervisor`-ресурс удалён в KAC-36/79/80.)
- `internal_watch_service.proto` — LISTEN/NOTIFY (deprecated с 1.0).

## Service protos

Полный per-resource: `<resource>_service.proto` для каждого ресурса (Get/List/Create/Update/Delete). NIC валидируется через vpc, см. [[../edges/compute-to-vpc-nic-validate]].

#proto #kacho-compute
