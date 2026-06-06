---
title: "kacho-proto — domains"
category: repo-doc
repo: kacho-proto
tags:
  - kacho-proto
  - proto
  - grpc
  - domains
---

# kacho-proto — domains

## VPC (22 proto-файла)

`proto/kacho/cloud/vpc/v1/`:
- `network.proto / network_service.proto`
- `subnet.proto / subnet_service.proto`
- `address.proto / address_service.proto`
- `route_table.proto / route_table_service.proto`
- `security_group.proto / security_group_service.proto`
- `gateway.proto / gateway_service.proto`
- `network_interface.proto / network_interface_service.proto`
- `privatelink/private_endpoint.proto` (под-пакет `kacho.cloud.vpc.v1.privatelink`)
- `internal_address_service.proto` — IPAM Allocate/Free
- `internal_address_pool_service.proto` — AddressPool admin
- `internal_network_service.proto` — Network admin (default-SG management)
- `internal_cloud_service.proto` — Cloud pool selector
- `internal_watch_service.proto` — outbox stream (LISTEN/NOTIFY)
- `internal_region_service.proto` / `internal_zone_service.proto` — Geography (до KAC-15 — была здесь).

## Compute (41 proto-файл)

`proto/kacho/cloud/compute/v1/`:
- `instance.proto / instance_service.proto`
- `disk.proto / disk_service.proto`
- `image.proto / image_service.proto`
- `snapshot.proto / snapshot_service.proto`
- `disk_type.proto / disk_type_service.proto`
- `region.proto / region_service.proto` (после KAC-15 — здесь)
- `zone.proto / zone_service.proto` (после KAC-15 — здесь)
- + reference resources, snapshot schedules, host groups, placement groups, attach RPCs, network_interfaces (compute-side adapter).

## ResourceManager (5 proto-файлов)

`proto/kacho/cloud/resourcemanager/v1/`:
- `cloud.proto / cloud_service.proto`
- `folder.proto / folder_service.proto`
- `transitions.proto`

## OrganizationManager (3 proto-файла)

`proto/kacho/cloud/organizationmanager/v1/`:
- `organization.proto / organization_service.proto`
- `user_account.proto / user_account_service.proto`

## Loadbalancer (6 proto-файлов)

`proto/kacho/cloud/loadbalancer/v1/`:
- `network_load_balancer.proto / network_load_balancer_service.proto`
- `target_group.proto / target_group_service.proto`
- *(frozen в 1.0 — backend ещё не переписан)*

## Operation (3 proto-файла)

`proto/kacho/cloud/operation/v1/`:
- `operation.proto` — message envelope (id, description, created_at, done, metadata, response/error).
- `operation_service.proto` — `Get(id)` only.

## Прочие (по 1 файлу)

- `access/access.proto` — AAA-stub.
- `api/api.proto` — api-listing.
- `maintenance/maintenance.proto` — maintenance windows.
- `reference/reference.proto` — shared Reference type.
- `validation.proto` (root) — buf.validate annotations.

## Common

- Нет content (зарезервирован под shared types).

## Подгенерация Go-stubs

`make gen` → `buf generate` → `gen/go/kacho/cloud/<domain>/v1/`:
- `*.pb.go` — messages + getters.
- `*_grpc.pb.go` — gRPC client + server interfaces.
- `*.pb.gw.go` — grpc-gateway REST handlers (где есть `google.api.http` annotation).

См. [[README]] для overview.

#kacho-proto #proto #grpc #domains
