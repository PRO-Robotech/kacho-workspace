---
title: vpc-apps-kacho-shared-serviceerr
category: package
repo: kacho-vpc
layer: service
tags:
  - packages
  - kacho-vpc
  - shared
  - errors
---

# kacho-vpc/internal/apps/kacho/shared/serviceerr

**Path**: `kacho-vpc/internal/apps/kacho/shared/serviceerr/`

VPC-specific error helpers поверх [[corelib-errors]]. Pre-formatted error-builders для типичных VPC-кейсов (`NetworkNotFound(id)`, `SubnetOverlap(cidr)`, `NICAlreadyAttached(ni_id, used_by)`, …).

## Pattern

```go
return serviceerr.NetworkNotFound(id)
// equivalent to:
// errors.NotFound("Network", id).Build()
```

Шорткаты, чтобы handler-код был чище + единый текст сообщений (YC parity style).

## See also

[[corelib-errors]] [[vpc-repo-helpers]]

#packages #kacho-vpc #shared #errors
