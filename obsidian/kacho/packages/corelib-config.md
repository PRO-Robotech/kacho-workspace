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
**Imported by**: `kacho-vpc/internal/config`, `kacho-iam/internal/config`, `kacho-api-gateway/internal/config` (`kacho-resource-manager` удалён в KAC-124)

Загрузка config struct из env-переменных через `envconfig` (KACHO_<DOMAIN>_<NAME> формат).

## Exported functions

- `Load(c any) error` — заполняет переданную struct из env. Tag `envconfig:"NAME"` либо derive из field-name. Возвращает ошибку с указанием пропущенного required-поля.

## Convention

- Env-префикс не вшит в Load — каждый сервис сам префиксует tag-имена (`KACHO_VPC_*`, `KACHO_RM_*`).
- Skill `evgeniy` правило: env-config в struct-tags **разрешён только для top-level config**; домен-логика читает уже распарсенную struct. Для бóльших конфигов план — миграция на viper/koanf + YAML (см. skill `evgeniy` план KAC-94).

## SEC-B — TLS config-структуры (corelib)

- `grpcsrv.TLSServer{Enable, CertFile, KeyFile, ClientCAFiles []string}` (env `KACHO_VPC_TLS_SERVER_*`) и `grpcclient.TLSClient{Enable, CertFile, KeyFile, CAFiles []string, ServerName}` (env `KACHO_COMPUTE_TLS_CLIENT_*`) — загружаемы через `config.Load` (envconfig explicit-tag fallback при nested-struct). Per-instance/per-edge, без глобального TLS-синглтона (FD-3). `enable=false` (zero-value) ⇒ insecure (FD-1). Полная семантика — [[corelib-grpcsrv]] / [[corelib-grpcclient]].

## See also

[[vpc-apps-kacho-config]] [[rm-config]] [[apigw-config]]

#packages #kacho-corelib #config
