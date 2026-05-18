---
title: vpc-dto
category: package
repo: kacho-vpc
layer: dto
tags:
  - packages
  - kacho-vpc
  - dto
---

# kacho-vpc/internal/dto

**Path**: `kacho-vpc/internal/dto/`
**Imported by**: handler-layer + service-layer как table-driven маппинги

`Transferrable` table — мост между proto-stubs и [[vpc-domain]] entity. Skill `evgeniy` rule: «table-driven DTO, не ручные `assign field by field`».

## Files

- `base.go` — `Transferrable interface { ToDomain() (Domain, error); FromDomain(Domain) Proto }` + helpers для каждой entity-пары.
- `toproto/` — обратное направление (domain → proto), см. [[vpc-dto-toproto]].

## Pattern

```go
var networkTable = []dto.Field[*pb.Network, *domain.Network]{
    {Proto: "id", To: func(p, d) { d.ID = p.Id }, From: func(d, p) { p.Id = d.ID }},
    {Proto: "name", To: ..., From: ..., Validate: validate.NameVPC},
    ...
}
```

## See also

[[vpc-dto-toproto]] [[vpc-domain]]

#packages #kacho-vpc #dto
