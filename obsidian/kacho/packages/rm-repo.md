---
title: rm-repo
category: package
repo: kacho-resource-manager
layer: repo
tags:
  - packages
  - kacho-rm
  - repo
  - pg
---

# kacho-resource-manager/internal/repo

**Path**: `kacho-resource-manager/internal/repo/`
**Implements**: ports из [[rm-service]]

pgxpool-реализация repo'шек + sqlc-generated queries.

## Files

| File | Содержание |
|---|---|
| `organization_repo.go` | `OrganizationRepo` impl |
| `cloud_repo.go` | `CloudRepo` impl |
| `folder_repo.go` | `FolderRepo` impl |
| `helpers.go` | error mapping (SQLSTATE→gRPC), shared scanners |
| `queries/` | sqlc-input SQL queries (если используется sqlc; иначе .gitkeep'd плейсхолдер) |

## sqlc

Каталог `queries/` намекает на sqlc-based query generation. `sqlc.yaml` в корне `kacho-resource-manager/` определяет схему + plugin.

## See also

[[rm-service]] [[corelib-db]] [[corelib-errors]]

#packages #kacho-rm #repo #pg
