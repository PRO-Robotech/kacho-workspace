---
title: vpc-repo-cqrsadapter
category: package
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - cqrs
  - legacy
---

# kacho-vpc/internal/repo/cqrsadapter

**Path**: `kacho-vpc/internal/repo/cqrsadapter/`
**Imported by**: legacy adapter — service-layer постепенно переходит на CQRS-разделённые порты [[vpc-repo-kacho]].

Адаптер, разворачивающий aggregate `Repository` interface в отдельные Reader/Writer'ы (CQRS-split). Используется как мост, когда часть кода ещё на старом aggregate-репо, а часть — уже на CQRS.

## Files

- `cqrsadapter.go` — единственный файл (~150 LOC).

## Status

Промежуточный adapter — будет удалён, когда все handler-ы переведены на per-entity Reader/Writer ports напрямую (KAC-94 skill `evgeniy`).

## See also

[[vpc-repo-kacho]] [[vpc-repo-repomock]]

#packages #kacho-vpc #repo #cqrs #legacy
