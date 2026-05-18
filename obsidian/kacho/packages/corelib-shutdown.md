---
title: corelib-shutdown
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - shutdown
---

# corelib/shutdown

**Path**: `kacho-corelib/shutdown/`
**Imports**: `context`, `errors`, `os`, `os/signal`, `sync`, `syscall`
**Imported by**: `kacho-resource-manager` (1)

Graceful shutdown coordinator: ловит SIGTERM/SIGINT, вызывает зарегистрированные handler-ы по LIFO с timeout-budget.

## Exported

- `Manager struct{ ... }`
  - `New() *Manager`
  - `(*Manager).Register(h Handler)` — push на стек.
  - `(*Manager).Wait(ctx context.Context) error` — блокирует до signal-а или ctx.Done; затем поочерёдно зовёт handler-ы (последний-первый), каждый со своим sub-context.
- `Handler func() error` — handler-функция.
- `var ErrAlreadyClosed = errors.New("shutdown manager already closed")`.

## Order

Регистрируй в `cmd/<svc>/main.go` так, чтобы LIFO дал нужный порядок:
1. `pool.Close` (последний — DB закрываем последним).
2. `grpcServer.GracefulStop`.
3. `operationsWorker.Wait`.
4. `otelShutdown`.

## See also

[[corelib-operations]] [[corelib-observability]] [[rm-cmd]]

#packages #kacho-corelib #shutdown
