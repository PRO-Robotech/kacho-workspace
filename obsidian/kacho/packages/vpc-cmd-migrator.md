---
title: vpc-cmd-migrator
category: packages
repo: kacho-vpc
layer: cmd
tags:
  - packages
  - kacho-vpc
  - cmd
  - migrations
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/cmd/migrator

**Каталог**: `services/vpc/cmd/migrator/main.go` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/cmd/migrator/main.go`)

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

[[vpc-apps-migrator]] [[legacy/repo-kacho-deploy]]

#packages #kacho-vpc #cmd #migrations
