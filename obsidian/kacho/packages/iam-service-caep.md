---
title: "iam internal/service/caep"
aliases:
  - iam caep
  - caep drainer
  - dlq
category: packages
repo: kacho-iam
layer: service
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - packages
  - kacho-iam
  - service
  - caep
  - outbox
---

# iam `internal/service/caep`

Phase 8 — Continuous Access Evaluation Profile (OpenID CAEP draft) push pipeline. Outbox-pattern + drainer + SET signer + DLQ.

## Sub-packages / responsibilities

- `drainer/` — fetch caep_outbox rows, fan-out to subscribers, mark processed.
- `signer/` — HSM-backed SET (RFC 8417) JWT signing.
- `subscriber_client/` — HTTPS POST к subscriber endpoint (with mTLS / OAuth / bearer).
- `dlq/` — failed events to Kafka topic `kacho.iam.caep.dlq` + alert.
- `replay/` — manual replay use-case ([[../rpc/iam-caep-subscriber-service]] ReplayEvent).

## Drainer architecture

```go
type CAEPDrainer struct {
    Outbox          CAEPOutboxRepo
    Subscribers     CAEPSubscriberReader
    Signer          SETSigner             // → HSM PKCS#11 [[iam-clients-hsm-pkcs11]]
    HTTPClient      *http.Client          // mTLS + OAuth2 bearer dispatch
    DLQ             KafkaProducer
    Metrics         *prometheus.CounterVec
}

func (d *CAEPDrainer) Run(ctx) error {
    notify := postgres.NewListener("kacho_iam_caep_outbox")
    ticker := time.NewTicker(100 * time.Millisecond)
    for {
        select {
        case <-ctx.Done(): return ctx.Err()
        case <-notify.Wake():
        case <-ticker.C:
        }
        rows := d.Outbox.FetchPending(ctx, 50)
        for _, row := range rows {
            d.process(ctx, row)
        }
    }
}

func (d *CAEPDrainer) process(ctx, row CAEPOutboxRow) {
    set := d.Signer.Sign(buildSET(row))   // EdDSA via HSM
    for _, subscriber := range d.Subscribers.FilterByEvent(row.EventType, row.AccountID) {
        if !d.deliver(ctx, subscriber, set) {
            d.Outbox.IncrementFailure(ctx, row.ID, subscriber.ID)
            if row.Attempts >= 5 {
                d.DLQ.Send(ctx, row)
            }
        }
    }
    d.Outbox.MarkProcessed(ctx, row.ID)
}
```

## SLO (Phase 8 DoD)

- p99 propagation ≤5s (kacho commit → subscriber 2xx ack).
- Retry exp-backoff: 5 immediate (1s/2s/4s/8s/16s) + 24h tail (every 1h).
- After 24h → DLQ + PagerDuty alert.

## Imports

- `internal/repo/kacho/pg` — CAEPOutboxRepo, CAEPSubscriberReader
- `internal/clients/hsm_pkcs11`
- `segmentio/kafka-go` — DLQ producer
- `prometheus/client_golang`

## Imported by

- `cmd/kacho-iam/main.go` — composition root (parallel worker)
- `internal/handler/grpc/caep_subscriber_handler.go` — ReplayEvent dispatch

## Metrics

- `kacho_iam_caep_events_emitted_total{event_type, subscriber_id, outcome}`
- `kacho_iam_caep_propagation_seconds{event_type, percentile}`
- `kacho_iam_caep_dlq_total{event_type, reason}`

## Tests

- Unit: mocked subscribers, drift scenarios.
- Integration: testcontainers Postgres + httptest subscriber.
- Load: k6 — sustain 100 events/s with p99 ≤5s ([[../KAC/KAC-127]] Phase 8 DoD).

## See also

[[iam-clients-hsm-pkcs11]] [[../rpc/iam-caep-subscriber-service]] [[../resources/iam-caep-subscriber]] [[../edges/iam-caep-to-subscriber]] [[../edges/iam-to-hsm]] [[../KAC/KAC-127]]

#packages #kacho-iam #service #caep #outbox
