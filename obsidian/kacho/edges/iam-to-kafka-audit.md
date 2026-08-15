---
title: "iam → kafka: audit event producer"
aliases:
  - iam to kafka
  - audit kafka
category: edge
caller_repo: kacho-iam
callee_repo: kafka
sync_async: async
protocol: Kafka (TCP)
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - edge
  - kacho-iam
  - cross-service
  - kafka
  - audit
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
---

> [!warning] Приёмника нет, и производитель это переживает молча (сверено 2026-08-05, дерево `96b2879a`)
> Слово `kafka` встречается во всём монорепо **один** раз — комментарием в
> `services/iam/internal/domain/audit_outbox_entry.go` («дренаж стримит это в audit-топик»).
> Самого дренажа нет: `audit_outbox` **пишется** (привязки, посевы, ключи, токены — эмиттеры
> провязаны в `cmd/kacho-iam/wiring.go`), но ни одна конфигурация дренажа на эту таблицу не
> ссылается (предикат: `grep -rn "Table:.*audit" services/` → пусто).
>
> То есть строки аудита копятся, и «аудит работает» неотличимо от «аудит никуда не уходит».
> Это ровно тот признак, который `data-integrity.md` требует делать заметным: «ноль
> доставленных строк за всю жизнь очереди» обязано быть видно. Ниже — замысел приёмника.

# iam → kafka: audit event producer

**Caller**: `kacho-iam` audit drainer (`internal/service/audit_drainer.go`, see [[../packages/iam-jobs]]).
**Callee**: Apache Kafka (`kafka-broker:9092` cluster-internal; multi-region MirrorMaker Phase 11).
**Protocol**: Kafka producer client (`segmentio/kafka-go`).
**Sync/Async**: async (outbox-pattern из `kacho_iam.audit_outbox` table).
**Status**: **Phase 9 planned**. См. также [[../resources/iam-audit-signing-batch]].

## Architecture (Phase 9)

```
service write-TX                kafka topic               consumers
─────────────────────────       ────────────              ──────────
iam.AuditOutbox INSERT  ───>    kacho.iam.audit ───>      ClickHouse sink
(atomic с business INSERT)      (partitioned key=         (real-time query)
                                 account_id)                 │
                                                              ↓
                                                          ────────────
                                                          S3 archive sink
                                                          (long-term)
                                                              │
                                                              ↓
                                                          ────────────
                                                          SIEM forwarder
                                                          (Datadog/Splunk)
```

## Topic layout (Phase 9)

| Topic | Partitions | Retention | Description |
|---|---|---|---|
| `kacho.iam.audit` | 16 | 7d (then S3) | Main audit stream (Merkle-signed batches) |
| `kacho.iam.caep` | 8 | 7d | CAEP outbound events (parallel to subscriber push) |
| `kacho.iam.error` | 4 | 30d | Producer failures / DLQ |

## Event format (SET-aligned, RFC 8417)

```json
{
  "iss": "https://api.kacho.cloud",
  "iat": 1734672000,
  "jti": "evt_01HW3X2C8R5M2N7P8Q9R0S1T2U",
  "aud": "kacho-audit-sink",
  "events": {
    "iam.access_binding.created": {
      "subject": { "format": "kacho.user", "id": "usr_xxx" },
      "context": { "ip": "1.2.3.4", "session_id": "ses_yyy" },
      "object": { "type": "project", "id": "prj_zzz" },
      "after": { ... },
      "actor": "usr_aaa"
    }
  },
  "merkle_root": "ba7816bf...",   // batch root, Phase 9
  "signature": "MEUCIQD..."        // HSM signature, Phase 9
}
```

## Outbox-drainer worker

```go
// pseudocode — see internal/service/audit_drainer.go (Phase 9)
for {
  select tickInterval:
    rows := repo.FetchPending(ctx, batchSize=500)
    for _, row := range rows {
      err := producer.WriteMessages(ctx, kafka.Message{
        Key: []byte(row.account_id),
        Value: row.payload_json,
      })
      if err == nil {
        repo.MarkProcessed(ctx, row.id)
      } else {
        repo.MarkFailed(ctx, row.id, err.Error())
      }
    }
}
```

## Notes

- Atomicity: business write + audit_outbox INSERT в **одной транзакции** (outbox-pattern). Drainer eventually drains.
- Idempotent producer (acks=all, retries=∞, max.in.flight=1, enable.idempotence=true) → exactly-once semantics.
- TLS + SASL/SCRAM от kacho-iam → Kafka (cluster-internal listener).
- Phase 9 Merkle batches — periodic (every 1000 events или 60s) → HSM signing → `audit_signing_batches` row.

## See also

[[iam-to-clickhouse-audit]] [[iam-to-s3-audit]] [[iam-to-hsm]] [[iam-to-siem-datadog]] [[iam-to-siem-splunk]] [[../resources/iam-audit-signing-batch]] [[../packages/iam-service-caep]] [[../KAC/KAC-127]]

#edge #kacho-iam #cross-service #kafka #audit
