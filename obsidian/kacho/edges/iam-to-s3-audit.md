---
title: "iam → s3-audit: archival sink + Glacier"
aliases:
  - iam to s3
  - audit s3
  - audit glacier
category: edge
caller_repo: kacho-iam
callee_repo: aws-s3
sync_async: async
protocol: AWS S3 API (HTTPS)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - s3
  - audit
  - retention
---

# iam → s3-audit: archival sink + Glacier

**Caller**: kacho-iam audit archiver (`internal/service/audit_archiver.go`).
**Callee**: AWS S3 bucket `kacho-audit-archive-{region}` + Glacier Deep Archive lifecycle.
**Protocol**: AWS S3 API (HTTPS, AWS SDK v2 Go).
**Sync/Async**: async (daily batch from Kafka).
**Status**: **Phase 9 planned**.

## Architecture (Phase 9)

```
kacho.iam.audit topic   →   S3 sink (Kafka Connect или custom worker)
                              ↓ 
                          s3://kacho-audit-archive-eu-west-1/
                            partitioned by YYYY/MM/DD/account_id/
                              ↓ lifecycle 30d
                          Glacier Deep Archive
                              ↓ retain 7 years
                          (long-term WORM)
```

## File format

NDJSON gzipped, batched 5min × account_id:
```
s3://kacho-audit-archive-eu-west-1/
  2026/05/19/
    acc_xxx/00-12.ndjson.gz
    acc_xxx/12-24.ndjson.gz
    acc_yyy/00-12.ndjson.gz
```

Each line = full SET (Security Event Token, RFC 8417) — same format как Kafka payload.

## S3 Object Lock + Versioning (Phase 9)

```yaml
ObjectLockEnabled: true
ObjectLockConfiguration:
  ObjectLockEnabled: Enabled
  Rule:
    DefaultRetention:
      Mode: COMPLIANCE   # WORM — even root cannot delete
      Years: 7
```

→ legally tamper-proof; aligns с GDPR Article 32, SOC 2, ISO 27001.

## Multi-region replication

```yaml
ReplicationConfiguration:
  Role: arn:aws:iam::xxx:role/kacho-audit-replication
  Rules:
  - Status: Enabled
    Destination:
      Bucket: arn:aws:s3:::kacho-audit-archive-us-east-1
      StorageClass: GLACIER_IR
```

→ EU primary + US replica → multi-region durability (Phase 11 active-active).

## Lifecycle policy

```yaml
Rules:
- Id: glacier-after-30d
  Status: Enabled
  Transitions:
  - Days: 30
    StorageClass: GLACIER_DEEP_ARCHIVE
  Expiration:
    Days: 2555  # 7 years
```

## Restore flow (for forensics)

1. Operator → kacho-iam admin endpoint `POST /iam/v1/internal/audit/restore` (range).
2. kacho-iam → S3 `RestoreObject` (Bulk tier — 12h delivery; or Standard — 5min for Deep Archive Acquisition Time).
3. After restore complete → restored copies returned via signed-URL CSV/JSONL.

## Notes

- Encryption at rest: SSE-KMS с CMK rotated annually.
- Encryption in transit: TLS 1.3.
- Pre-flight integrity: each batch SHA-256 hashed + matched к Merkle leaf [[../resources/iam-audit-signing-batch]].
- НЕ stores secrets / PII raw — payloads pre-redacted (GDPR Article 17 erasure pipeline marks redacted lines).

## See also

[[iam-to-kafka-audit]] [[iam-to-clickhouse-audit]] [[iam-to-hsm]] [[../resources/iam-audit-signing-batch]] [[../resources/iam-gdpr-erasure-request]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #s3 #audit #retention
