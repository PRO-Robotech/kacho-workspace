---
title: vpc-dto-toproto
category: packages
repo: kacho-vpc
layer: dto
tags:
  - packages
  - kacho-vpc
  - dto
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# kacho-vpc/internal/dto/toproto

**Каталог**: `services/vpc/internal/dto/toproto/` — монорепо `PRO-Robotech/kacho` (прежде, в полирепо: `kacho-vpc/internal/dto/toproto/`)
**Imported by**: handler-layer (build proto-ответы)

Domain entity → proto-stub конвертеры. Отдельный sub-пакет, чтобы service-слой не зависел от proto (Clean Architecture — domain free of proto).

## Pattern

```go
func Network(d *domain.Network) *pb.Network {
    return &pb.Network{
        Id: string(d.ID),
        Name: string(d.Name),
        FolderId: d.FolderID,
        CreatedAt: timestamppb.New(d.CreatedAt.Truncate(time.Second)),
        Labels: d.Labels.Map(),
        // ...
    }
}
```

## Constraints

- Public projection — БЕЗ инфра-полей (см. CLAUDE.md «Инфра-чувствительные данные»).
- Timestamp всегда truncate-to-seconds (контрактное требование конвенций).
- Internal projection — отдельные функции (`InternalNetwork(...)`), вызываются только в internal-handler'ах.

## See also

[[vpc-dto]] [[vpc-domain]] [[vpc-handler]]

#packages #kacho-vpc #dto
