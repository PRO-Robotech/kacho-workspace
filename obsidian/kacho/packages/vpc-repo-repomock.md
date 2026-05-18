---
title: vpc-repo-repomock
category: package
repo: kacho-vpc
layer: repo
tags:
  - packages
  - kacho-vpc
  - repo
  - mock
  - legacy
---

# kacho-vpc/internal/repo/repomock

**Path**: `kacho-vpc/internal/repo/repomock/`
**Imported by**: тесты, использующие старый aggregate `Repository`-mock (до миграции на kachomock).

Legacy mock — single file `repomock.go`. Постепенно заменяется на [[vpc-repo-kacho-kachomock]] (per-entity моки с handwritten DSL).

## See also

[[vpc-repo-kacho-kachomock]] [[vpc-repo-cqrsadapter]]

#packages #kacho-vpc #repo #mock #legacy
