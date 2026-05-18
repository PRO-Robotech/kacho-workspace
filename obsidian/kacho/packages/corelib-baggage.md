---
title: corelib-baggage
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - async
---

# corelib/baggage

**Path**: `kacho-corelib/baggage/`
**Imports**: `context`
**Imported by**: `kacho-corelib/operations`

«Baggage» — извлечение subset значений из `callerCtx` и проброс их в worker-context, который продолжает жить **после** возврата RPC-ответа клиенту (long-running operations).

## Exported functions

- `Extract(callerCtx context.Context) context.Context` — копирует request-scope ключи (auth, trace, request-id) в свежий `context.Background()` для async-worker'а; **отбрасывает** deadline/cancel caller'а (worker не должен умереть после `OK`-ответа клиенту). См. [[corelib-operations]].

## Why

Каждый `Operation`-mutation (Create/Update/Delete) запускает worker (горутина) — он должен пережить grpc-context. `Extract` — единая точка, где правила «что переносим» зафиксированы.

## See also

[[corelib-operations]] [[../resources/operation]]

#packages #kacho-corelib #async
