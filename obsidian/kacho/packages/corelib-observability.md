---
title: corelib-observability
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - observability
  - otel
---

# corelib/observability

**Path**: `kacho-corelib/observability/`
**Imports**: `context`, `io`, `log/slog`, `os`
**Imported by**: `kacho-vpc` (2), `kacho-resource-manager` (1)

`slog`-logger + OpenTelemetry init helper.

## Exported

- `NewSlogger(w io.Writer) *slog.Logger` — JSON-handler с дефолтными атрибутами (`service`, level, ts), пишет в `w` (обычно `os.Stdout`).
- `ShutdownFn func(context.Context) error` — type alias для graceful shutdown OTEL.
- `InitOtel(ctx context.Context, serviceName string) (ShutdownFn, error)` — устанавливает global tracer + meter providers, OTLP-exporter (env `OTEL_EXPORTER_OTLP_ENDPOINT`); вернёт `ShutdownFn` — вызвать в [[corelib-shutdown]] на SIGTERM.

## Usage

```go
log := observability.NewSlogger(os.Stdout)
otelShut, _ := observability.InitOtel(ctx, "kacho-vpc")
defer otelShut(ctx)
```

## See also

[[corelib-shutdown]] [[vpc-cmd-vpc]]

#packages #kacho-corelib #observability #otel
