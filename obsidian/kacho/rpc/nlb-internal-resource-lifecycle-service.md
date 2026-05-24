---
title: InternalResourceLifecycleService (nlb)
aliases:
  - InternalResourceLifecycleService (nlb)
  - nlb lifecycle stream
proto_file: kacho/cloud/loadbalancer/v1/internal_resource_lifecycle_service.proto
category: rpc
backend: kacho-nlb
backend_port: 9091
visibility: internal
domain: nlb
related_resource: "[[resources/nlb-load-balancer]]"
methods_count: 1
async_methods: 0
tags:
  - rpc
  - kacho-nlb
  - internal
  - lifecycle
---

# InternalResourceLifecycleService (nlb)

**Proto**: `kacho-proto/proto/kacho/cloud/loadbalancer/v1/internal_resource_lifecycle_service.proto`
**Backend**: `kacho-nlb:9091` (cluster-internal gRPC)
**Visibility**: **internal-only** (workspace CLAUDE.md запрет #6 — НЕ на external TLS listener)

## Methods (1 server-stream)

| Method | Request | Response | Note |
|---|---|---|---|
| Subscribe | SubscribeRequest | stream LifecycleEvent | server-stream; LISTEN `nlb_outbox` on dedicated pgx-conn |

### LifecycleEvent payload

```protobuf
message LifecycleEvent {
  int64 sequence_no = 1;
  string resource_type = 2;   // nlb_load_balancer | nlb_listener | nlb_target_group
  string resource_id = 3;
  string project_id = 4;
  string action = 5;          // CREATED | UPDATED | DELETED
  google.protobuf.Timestamp emitted_at = 6;
  bytes payload = 7;          // jsonb (полная row snapshot)
}
```

## D-13 lifecycle stream flow

1. Acquire per-stream semaphore (`KACHO_NLB_LIFECYCLE_MAX_STREAMS=32`)
2. Dedicated `pgx.Connect` → `LISTEN nlb_outbox`
3. **Catchup batch** (100 rows): SELECT FROM nlb_outbox WHERE sequence_no > $cursor ORDER BY sequence_no
4. `WaitForNotification` loop (timeout 30s)
5. Stream `LifecycleEvent` к client (типично kacho-iam — D-13 hierarchy tuple sync)
6. `nlb_watch_cursors` сохраняет subscriber position для resume

## Outbox channel

`pg_notify('nlb_outbox', sequence_no::text)` — triggered `nlb_outbox_notify_trg` на каждом INSERT в `nlb_outbox` table. Outbox events emit'ятся в той же TX, что и mutation (write-after-write atomicity via `RepositoryWriter.Outbox().Emit(...)`).

## REST mapping

Internal-only — НЕ на TLS endpoint (`api.kacho.local:443`). Может быть зарегистрирован через api-gateway REST mux на cluster-internal listener (но используется напрямую kacho-iam через gRPC stream).

## Consumers

- **kacho-iam** — D-13 lifecycle subscriber для maintenance FGA hierarchy tuples (`nlb_load_balancer:<id>#project@project:<project_id>`). См. [[../edges/iam-to-nlb-resource-lifecycle]].

## See also

[[../packages/nlb-apps-kacho-api-internal-lifecycle]] [[../resources/nlb-load-balancer]] [[../edges/iam-to-nlb-resource-lifecycle]]

#rpc #kacho-nlb #internal #lifecycle
