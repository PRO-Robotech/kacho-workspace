---
title: corelib-outbox
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - outbox
  - postgres
---

# corelib/outbox

**Path**: `kacho-corelib/outbox/`
**Imports**: `context`, `encoding/json`, `fmt`, `pgx/v5`, `pgxpool`
**Imported by**: `kacho-vpc` (4 files)

Atomic outbox-в-TX: события пишутся в таблицу `outbox` той же транзакцией, что и domain-изменение → consumer-у транслируется через LISTEN/NOTIFY.

## Exported

- `Emit(ctx, tx pgx.Tx, table, kind, id, eventType string, payload any) error` — INSERT в `<schema>.outbox(table,kind,id,event_type,payload)`. **Требует** `tx` (атомарность — точка дизайна).
- `Event struct{ ID, Table, Kind, ResourceID, EventType string; Payload json.RawMessage; CreatedAt time.Time }` — read-out при поллинге.
- `Writer struct{ ... }` — listener на `LISTEN <channel>` + поллер outbox (catch-up если NOTIFY потерян).
  - `NewWriter(channel string) *Writer`
  - `(*Writer).Run(ctx, pool, handler func(Event) error) error`

## Atomicity rule

```go
err := tx.Do(ctx, func(ctx context.Context) error {
    repo.UpdateNetwork(ctx, n)  // domain change
    outbox.Emit(ctx, tx, "networks", "network", n.ID, "network.updated", n)
    return nil
})
// Either both committed or both rolled back. NOTIFY is async after commit.
```

## See also

[[corelib-db]] [[vpc-apps-kacho-api-network]] (writer wiring)

#packages #kacho-corelib #outbox #postgres
