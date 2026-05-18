---
title: vpc-apps-kacho-shared-macutil
category: package
repo: kacho-vpc
layer: shared
tags:
  - packages
  - kacho-vpc
  - shared
  - mac
---

# kacho-vpc/internal/apps/kacho/shared/macutil

**Path**: `kacho-vpc/internal/apps/kacho/shared/macutil/`

MAC-address utilities — генерация / валидация / canonical-form.

## Used by

- NIC.Create (auto-generate MAC если не задан — миграция 0014).
- NIC.Update (validate MAC change).
- [[vpc-repo-helpers]] `nic.go` (низкоуровневые SQL helpers).

## See also

[[vpc-apps-kacho-api-networkinterface]] [[../resources/vpc-networkinterface]]

#packages #kacho-vpc #shared #mac
