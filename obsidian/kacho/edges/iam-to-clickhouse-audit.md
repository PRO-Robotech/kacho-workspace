---
title: "iam ↔ clickhouse: audit query interface"
aliases:
  - iam to clickhouse
  - audit clickhouse
category: edge
caller_repo: kacho-iam
callee_repo: clickhouse
sync_async: mixed
protocol: HTTP (ClickHouse REST) + Kafka Engine
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - clickhouse
  - audit
---

# iam ↔ clickhouse: audit query interface

**Producer-side**: ClickHouse Kafka Engine consumes from `kacho.iam.audit` topic (см. [[iam-to-kafka-audit]]).
**Consumer-side**: kacho-iam admin UI + kacho-test query historic audit events.
**Protocol**: HTTP REST (ClickHouse `/?query=...&FORMAT=JSON`).
**Status**: **Phase 9 planned**.

## Architecture (Phase 9)

```
kacho.iam.audit topic
  ↓ (Kafka Engine table)
audit_events_raw (MergeTree, materialized view → audit_events)
  ↓ TTL 90d
audit_events_cold (compressed, ZSTD level 22)
```

## Table schema (Phase 9)

```sql
CREATE TABLE kacho_audit.audit_events (
    event_time         DateTime64(3, 'UTC'),
    event_id           String,                 -- jti
    event_type         LowCardinality(String), -- iam.access_binding.created etc.
    account_id         LowCardinality(String),
    subject_id         String,
    object_type        LowCardinality(String),
    object_id          String,
    actor              String,
    ip                 IPv6,
    session_id         String,
    payload            String,                 -- full JSON
    merkle_root        FixedString(32),
    signature          String                  -- base64
) ENGINE = ReplicatedMergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (account_id, event_time, event_id)
TTL event_time + INTERVAL 90 DAY TO VOLUME 'cold',
    event_time + INTERVAL 7 YEAR DELETE;
```

## Query interface (kacho-iam admin)

| Endpoint | Description |
|---|---|
| `GET /iam/v1/internal/audit/events?account_id=&from=&to=&event_type=` | filter + pagination |
| `GET /iam/v1/internal/audit/events/{event_id}` | fetch + verify signature |
| `GET /iam/v1/internal/audit/integrity?from=&to=` | recompute Merkle root, compare к stored batches |
| `GET /iam/v1/internal/audit/aggregations?...` | counts / time-series для dashboards |

## Integrity verification

1. UI запрашивает range.
2. Backend читает ClickHouse + stored Merkle roots из Postgres (audit_signing_batches).
3. Recompute Merkle root on-the-fly.
4. Compare → return tampered=true/false + diff list.

## Access control

- ClickHouse cluster-internal (`clickhouse:8123`, `clickhouse:9000` TCP).
- kacho-iam — only producer / queryer with `audit_read` role.
- HSM signing keys — НЕ в ClickHouse (Postgres `audit_signing_batches` + HSM PKCS#11).

## Notes

- ClickHouse Replicated → multi-region (3-region replication Phase 11).
- Cold partitions S3-archived (RFC 6962-aligned with [[iam-to-s3-audit]]).
- Independent daily verifier — Phase 9 (separate Go binary) — re-signs Merkle batches and compares к ClickHouse + S3.

## See also

[[iam-to-kafka-audit]] [[iam-to-s3-audit]] [[iam-to-hsm]] [[../resources/iam-audit-signing-batch]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #clickhouse #audit
