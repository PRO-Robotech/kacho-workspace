---
title: rm-bootstrap
category: package
repo: kacho-resource-manager
layer: bootstrap
tags:
  - packages
  - kacho-rm
  - bootstrap
  - seed
---

# kacho-resource-manager/internal/bootstrap

**Path**: `kacho-resource-manager/internal/bootstrap/`

Seed defaults для dev/test-стенда — создать дефолтные Organization/Cloud/Folder, если БД пустая.

## Files

- `defaults.go` — `EnsureDefaults(ctx, repo) error`; idempotent (если уже есть — skip).

## Used by

[[rm-cmd]] на startup (dev mode); в prod — может быть disabled через `rm-config` flag.

## See also

[[rm-cmd]] [[rm-repo]]

#packages #kacho-rm #bootstrap #seed
