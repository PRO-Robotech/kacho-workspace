---
title: "iam → siem-datadog: log forwarder"
aliases:
  - datadog siem
  - iam datadog
category: edge
caller_repo: kacho-iam
callee_repo: datadog
sync_async: async
protocol: HTTPS (Datadog Logs API)
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

# iam → siem-datadog: log forwarder

**Caller**: kacho-iam SIEM forwarder (`internal/service/siem_forwarder.go`).
**Callee**: Datadog Logs Intake (`https://http-intake.logs.datadoghq.com/api/v2/logs`).
**Protocol**: HTTPS Datadog Logs API.
**Sync/Async**: async (batch send).
**Status**: **Phase 9 planned**.

## Architecture (Phase 9)

```
Kafka topic kacho.iam.audit
  ↓ (consumer group: siem-forwarder)
SIEM-forwarder worker (kacho-iam)
  ↓ batch every 5s или 100 messages
HTTPS POST → Datadog Logs Intake
  + Datadog Tags: service=kacho-iam, env=prod, region=eu-west-1, account_id=acc_xxx
```

## Auth

- API key per-region (Datadog DD_API_KEY env, stored Kubernetes Secret).
- Mutated quarterly через runbook ([[../runbooks/README|runbooks/key-rotation-procedure]]).

## Event format (Datadog-flavoured)

```json
{
  "ddsource": "kacho-iam",
  "ddtags": "env:prod,region:eu-west-1,event:iam.access_binding.created,account:acc_xxx",
  "hostname": "kacho-iam-7d8b9c-x4r5q",
  "message": "{...full SET payload as JSON string...}",
  "service": "kacho-iam"
}
```

## Detection rules (Datadog Cloud SIEM, Phase 9)

Examples (committed-as-code in kacho-deploy):
- `iam.break_glass.activated` count > 0 за 1h → PagerDuty page.
- `iam.session.revoked` count > 10 за 5min от одной session_id → alert (potential token-replay attack).
- Failed Hydra `token_introspect` rate > 50/min от одного IP → alert (auth brute-force).
- `iam.fga.model.changed` outside of CI-pipeline source IP → critical alert.
- Anomaly: SCIM provisioning spike >10x baseline → review.

## Error handling

- Datadog HTTP 4xx → log + DLQ (don't drop).
- HTTP 5xx → retry exp-backoff (Datadog supports up to 3min retry per RFC).
- > 5min unreachable → switch к failover SIEM ([[iam-to-siem-splunk]] sometimes paired). DLQ Kafka topic `kacho.iam.audit.error`.

## Notes

- Datadog retention 15 months hot, 90d archive (configurable).
- Per-org separation NOT enforced (all events ingested to single Datadog org); tagging-based access in Datadog Site.
- Phase 9 / 11 — Datadog **optional**, configurable env switch `KACHO_IAM_SIEM_DATADOG_ENABLED=true`; alternative — Splunk [[iam-to-siem-splunk]].

## See also

[[iam-to-siem-splunk]] [[iam-to-kafka-audit]] [[iam-to-clickhouse-audit]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #siem #audit
