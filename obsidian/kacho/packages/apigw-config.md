---
title: apigw-config
category: package
repo: kacho-api-gateway
layer: config
tags:
  - packages
  - kacho-apigw
  - config
---

# kacho-api-gateway/internal/config

**Path**: `kacho-api-gateway/internal/config/`
**Imports**: [[corelib-config]]

api-gateway config.

## Env vars (selected)

- `KACHO_APIGW_LISTEN_TLS` / `KACHO_APIGW_LISTEN_INTERNAL` — два endpoint'а
- `KACHO_APIGW_TLS_CERT_FILE` / `KEY_FILE`
- `KACHO_APIGW_BACKEND_RM_ADDR`
- `KACHO_APIGW_BACKEND_VPC_ADDR`
- `KACHO_APIGW_BACKEND_VPC_INTERNAL_ADDR`
- `KACHO_APIGW_BACKEND_COMPUTE_ADDR`
- `KACHO_APIGW_BACKEND_COMPUTE_INTERNAL_ADDR`

## Files

- `config.go`

## See also

[[corelib-config]] [[apigw-cmd]] [[../edges/apigw-internal-vs-tls]]

#packages #kacho-apigw #config
