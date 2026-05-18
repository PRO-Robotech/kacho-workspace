---
title: rm-service
category: package
repo: kacho-resource-manager
layer: service
tags:
  - packages
  - kacho-rm
  - service
  - usecase
---

# kacho-resource-manager/internal/service

**Path**: `kacho-resource-manager/internal/service/`
**Imports**: [[rm-domain]], [[corelib-errors]], [[corelib-validate]], [[corelib-operations]]
**Imported by**: [[rm-handler]]

Use-cases — бизнес-логика. Port-интерфейсы для Repo определены здесь.

## Files

| File | Содержание |
|---|---|
| `organization.go` | `OrganizationUseCase` (Create/Update/Delete/Get/List) |
| `cloud.go` | `CloudUseCase` |
| `folder.go` | `FolderUseCase` |
| `ports.go` | `Port`-интерфейсы `OrganizationRepo`, `CloudRepo`, `FolderRepo` (Reader+Writer, CQRS) |
| `validate.go` | rm-specific validation helpers |
| `organization_test.go` / `cloud_test.go` / `folder_test.go` | unit-тесты с mock-репо |
| `helpers_test.go` | |
| `async_test.go` | LRO testing helpers |
| `integration_test.go` | end-to-end use-case через real repo |
| `organization_cloud_delete_race_integration_test.go` | concurrent Delete race coverage |

## Pattern

```go
type FolderRepo interface { Get(ctx, id) (*Folder, error); Create(...); ... }
type FolderUseCase struct { repo FolderRepo; tx *db.Transactor; opsRepo operations.Repo; ... }
func (u *FolderUseCase) Create(ctx, ...) (*operations.Operation, error) { ... }
```

## See also

[[rm-repo]] [[rm-handler]] [[corelib-operations]]

#packages #kacho-rm #service #usecase
