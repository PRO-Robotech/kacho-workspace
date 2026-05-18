---
title: rm-domain
category: package
repo: kacho-resource-manager
layer: domain
tags:
  - packages
  - kacho-rm
  - domain
---

# kacho-resource-manager/internal/domain

**Path**: `kacho-resource-manager/internal/domain/`

Чистые domain-entities для resource-manager.

## Files

| File | Entity |
|---|---|
| `organization.go` | `Organization` struct + ctor + Equal |
| `cloud.go` | `Cloud` struct + ctor + Equal |
| `folder.go` | `Folder` struct + ctor + Equal |

## Convention

Аналогично [[vpc-domain]] — self-validating ctors, `.Equal()` для diff, no proto-imports.

## See also

[[../resources/rm-organization]] [[../resources/rm-cloud]] [[../resources/rm-folder]] [[vpc-domain]]

#packages #kacho-rm #domain
