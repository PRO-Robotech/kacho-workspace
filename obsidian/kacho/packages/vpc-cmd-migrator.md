---
title: vpc-cmd-migrator
category: package
repo: kacho-vpc
layer: cmd
tags:
  - packages
  - kacho-vpc
  - cmd
  - migrations
---

# kacho-vpc/cmd/migrator

**Path**: `kacho-vpc/cmd/migrator/main.go`

Standalone binary для применения SQL миграций (goose-формат) — отдельный entrypoint от основного `vpc` (skill `evgeniy` правило «separate cmd для миграций»).

## Files

- `main.go` — argparse, выбор dialect (postgres / cockroach), вызов runner.
- `main_test.go` — smoke smoke.

Реальный runner — в [[vpc-apps-migrator]].

## CLI

```
./migrator --dsn=postgres://... --dialect=postgres up
./migrator --dsn=... down 1
```

## Why separate binary

- В CI/k8s — отдельный Job (init-container) запускается до основного сервиса.
- Отделяет миграции от runtime — main binary не несёт goose-зависимости в release.

## See also

[[vpc-apps-migrator]] [[../kacho-deploy/README]]

#packages #kacho-vpc #cmd #migrations
