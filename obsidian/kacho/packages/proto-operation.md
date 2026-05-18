---
title: proto-operation
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - operation
  - lro
---

# proto/operation

**Path**: `kacho-proto/proto/kacho/cloud/operation/`
**Package**: `kacho.cloud.operation.v1`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/operation/v1`

Long-Running Operations (LRO) envelope — возвращается каждой мутацией Kachō.

## Files

- `operation.proto` — `Operation` message:
  ```
  string id = 1;
  string description = 2;
  google.protobuf.Timestamp created_at = 3;
  string created_by = 4;  // optional
  google.protobuf.Timestamp modified_at = 5;
  bool done = 6;
  google.protobuf.Any metadata = 7;  // {ResourceId} per-RPC
  oneof result {
    google.rpc.Status error = 8;
    google.protobuf.Any response = 9;  // resulting resource snapshot
  }
  ```
- `operation_service.proto` — [[../rpc/operation-service|OperationService]] (Get, List, Cancel где применимо).
- `package_options.proto` — go_package option.

## Per-service таблица operations

Каждый сервис ведёт собственную таблицу `operations` (см. [[corelib-operations]]); api-gateway проксирует `operation.OperationService` за каждым сервисом → у клиента **один** `OperationService` per-domain (`/operations/v1/...` префиксы или per-resource sub-paths).

## See also

[[corelib-operations]] [[../resources/operation]] [[../rpc/operation-service]]

#proto #operation #lro
