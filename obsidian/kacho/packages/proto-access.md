---
title: proto-access
category: package
repo: kacho-proto
layer: proto
tags:
  - proto
  - access
  - iam
---

# proto/access

**Path**: `kacho-proto/proto/kacho/cloud/access/access.proto`
**Package**: `kacho.cloud.access`
**Go import**: `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/access`

Shared types для IAM-binding messages (`AccessBinding`, `Subject`, `RoleId`). Используются протоколами разных доменов, когда добавляется IAM-инвокация (`SetAccessBindings`/`ListAccessBindings`).

## Status

Скелет; реальная IAM-логика появится в `kacho-iam` (вне scope). Сейчас файл нужен только для compile-completeness тех файлов, которые могут добавлять `.access`-rpc'ы (например, `Folder.SetAccessBindings`).

## See also

[[../README#blocked-iam|blocked:kacho-iam labels в GitHub Issues]]

#proto #access #iam
