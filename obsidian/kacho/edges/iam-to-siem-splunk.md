---
title: "iam → siem-splunk: HEC forwarder"
aliases:
  - splunk siem
  - iam splunk
  - splunk HEC
category: edge
caller_repo: kacho-iam
callee_repo: splunk
sync_async: async
protocol: HTTPS (Splunk HEC)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - siem
  - audit
---

# iam → siem-splunk: HEC forwarder

**Caller**: kacho-iam SIEM forwarder (alternative to / paired with [[iam-to-siem-datadog]]).
**Callee**: Splunk HTTP Event Collector (`https://splunk.example.com:8088/services/collector/event`).
**Protocol**: HTTPS Splunk HEC.
**Sync/Async**: async (batch send).
**Status**: **Phase 9 planned**.

## Auth

- HEC token per-source (kacho-iam = unique token).
- Header: `Authorization: Splunk {token}`.
- Rotated quarterly ([[../runbooks/README|runbooks/key-rotation-procedure]]).

## Event format

```json
{
  "event": { ... full SET payload ... },
  "sourcetype": "kacho:iam:audit",
  "source": "kacho-iam-eu-west-1",
  "host": "kacho-iam-7d8b9c-x4r5q",
  "index": "kacho_security",
  "time": 1734672000.123,
  "fields": {
    "account_id": "acc_xxx",
    "event_type": "iam.access_binding.created",
    "actor": "usr_aaa"
  }
}
```

## Detection rules (committed Splunk Enterprise Security, Phase 9)

- `(iam.break_glass.activated) | stats count by account_id` real-time alert.
- Behavioral baseline: high-impact mutations (`iam.role.changed`, `iam.access_binding.created`) hourly count vs baseline.
- Lateral movement: same user creates AccessBinding across N projects in M minutes.
- Outlier: federation Exchange usage from unrecognized issuer (`federation.policy.issued`).

## Error handling

- HEC HTTP 200 with `{"text":"Success","code":0}` → drained.
- HEC 4xx (token invalid) → halt + ops alert (token rotation needed).
- 5xx / timeout → retry exp-backoff + DLQ.
- Failover: if Splunk indexer down >10min → switch к Datadog ([[iam-to-siem-datadog]]).

## Notes

- Splunk Index `kacho_security` — restricted role-based (Splunk RBAC).
- Retention 90d hot, 7 years frozen (S3-archived; aligned с `audit_retention_policy`).
- Phase 9 / 11 — Splunk **optional**, configurable env `KACHO_IAM_SIEM_SPLUNK_ENABLED=true`.

## See also

[[iam-to-siem-datadog]] [[iam-to-kafka-audit]] [[iam-to-clickhouse-audit]] [[iam-to-s3-audit]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #siem #audit
