---
title: corelib-config
category: package
repo: kacho-corelib
layer: config
tags:
  - packages
  - kacho-corelib
  - config
---

# corelib/config

**Path**: `kacho-corelib/config/`
**Imports**: `github.com/kelseyhightower/envconfig`
**Imported by**: `kacho-vpc/internal/config`, `kacho-resource-manager/internal/config`, `kacho-api-gateway/internal/config`

Загрузка config struct из env-переменных через `envconfig` (KACHO_<DOMAIN>_<NAME> формат).

## Exported functions

- `Load(c any) error` — заполняет переданную struct из env. Tag `envconfig:"NAME"` либо derive из field-name. Возвращает ошибку с указанием пропущенного required-поля.

## Convention

- Env-префикс не вшит в Load — каждый сервис сам префиксует tag-имена (`KACHO_VPC_*`, `KACHO_RM_*`).
- Skill `evgeniy` правило: env-config в struct-tags **разрешён только для top-level config**; домен-логика читает уже распарсенную struct. Для бóльших конфигов план — миграция на viper/koanf + YAML (см. skill `evgeniy` план KAC-94).

## See also

[[vpc-apps-kacho-config]] [[rm-config]] [[apigw-config]]

#packages #kacho-corelib #config
