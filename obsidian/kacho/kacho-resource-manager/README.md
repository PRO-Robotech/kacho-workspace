---
title: kacho-resource-manager
aliases:
  - kacho-rm
  - kacho-resource-manager
category: repo
repo: kacho-resource-manager
go_module: github.com/PRO-Robotech/kacho-resource-manager
service_type: control-plane
domain: resourcemanager
status: removed
related_packages:
  - "[[packages/rm-domain]]"
  - "[[packages/rm-service]]"
tags:
  - kacho
  - kacho-rm
  - organization
  - folder
  - control-plane
  - deprecated
---

> [!warning] Removed by KAC-124 (E5 sub-phase 2.0) — historical tombstone
> `kacho-resource-manager` **упразднён**: backend, Postgres-инстанс и proto-пакеты `resourcemanager.v1` / `organizationmanager.v1` удалены полностью. Organization / Cloud / Folder заменены на **Account / Project** в `kacho-iam` ([[../resources/iam-account]], [[../resources/iam-project]]). Peer-валидация owner-scope теперь через `kacho-iam.ProjectService.Get` ([[../edges/vpc-to-iam-project-exists]]). Эта заметка оставлена как исторический след. Остальное ниже — описание **бывшего** сервиса.

# kacho-resource-manager (REMOVED — KAC-124)

Top-level tenant hierarchy сервис Kachō: **Organization → Cloud → Folder** (исторически).

- Repo: `github.com/PRO-Robotech/kacho-resource-manager` (удалён)
- Тип: control-plane.
- Был leaf-owner всей иерархии — другие сервисы только **читали** (`FolderService.Get`). Теперь эту роль выполняет `kacho-iam` (`ProjectService.Get`).

## Ресурсы (3)

| Resource | ID prefix | Note |
|---|---|---|
| **Organization** | `bpf` | Top-level (proto: `organizationmanager.v1`). Bootstrap-default создаётся автоматически при первом старте через `internal/bootstrap/EnsureDefaults`. |
| **Cloud** | `b1g` | Belongs to Organization (proto: `resourcemanager.v1`). |
| **Folder** | `b1g` | Belongs to Cloud. Все остальные ресурсы Kachō (VPC, Compute) folder-level. |

## Структура пакетов

```
cmd/
└── resource-manager/main.go    — gRPC API server

internal/
├── domain/                  — Organization, Cloud, Folder entities + Validate.
├── repo/                    — pgxpool + sqlc-generated queries.
│   └── queries/                .sql files (sqlc).
├── service/                 — business logic (legacy structure; не на CQRS pattern).
├── handler/                 — gRPC handlers.
├── bootstrap/               — EnsureDefaults() — создаёт default Organization/Cloud/Folder на старте если их нет.
├── config/                  — envconfig (legacy; ещё НЕ на viper/YAML — не migrated to skill evgeniy).
└── migrations/              — goose-миграции.
```

## RPC

- `OrganizationService.{Get,List,Create,Update,Delete,ListAccessBindings,...}`
- `CloudService.{Get,List,Create,Update,Delete}`
- `FolderService.{Get,List,Create,Update,Delete,Exists}` — `Exists` важен для peer-сервисов.

## Cross-repo runtime edges

- **Leaf — никого не зовёт.** Только in-bound: vpc/compute/... → `FolderService.Get`/`Exists` для validation.
- folder.Exists race-prone — skill evgeniy I.4 запретил sync precheck; теперь only async (closes [[../kacho-vpc/README|kacho-vpc]] PR #78).

## Известные расхождения от skill evgeniy

- **НЕ на CQRS pattern** (использует legacy repo pattern).
- **НЕ на viper YAML config** (использует envconfig).
- **service-слой** не разбит на use-case-пакеты.

> [!warning] Известные расхождения
> Replicate skill evgeniy на kacho-resource-manager — **не сделано** (per user decision в Wave 5).

## Build-зависимости

- `kacho-proto` — Organization/Cloud/Folder proto-stubs.
- `kacho-corelib` — `ids`, `operations`, `db`, `validate`, `grpcsrv`.

См. [[../architecture]] для cross-repo графа.

#kacho #kacho-rm #organization #folder #control-plane
