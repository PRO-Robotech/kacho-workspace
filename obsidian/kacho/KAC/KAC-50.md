---
title: "KAC-50: api-gateway listener split (public/TLS vs cluster-internal)"
aliases:
  - KAC-50
ticket_id: KAC-50
category: kac
status: done
type: feature
repos:
  - kacho-api-gateway
  - kacho-deploy
yt_url: https://prorobotech.youtrack.cloud/issue/KAC-50
tags:
  - kac
  - done
  - kacho-apigw
  - security
---

# KAC-50: api-gateway listener split

> [!note] Stub
> Полный trail в YouTrack.

Разделил api-gateway на два listener: public TLS edge (`api.kacho.local:443`, tenant-facing) и cluster-internal (порт 80/8080, admin-UI + impl-controllers). Internal* RPCs регистрируются **только** на internal-listener — никогда не публикуются на TLS edge.

## See also

- [[edges/apigw-internal-vs-tls]]
- [[packages/apigw-restmux]]
- [[packages/apigw-proxy]]

#kac #done #kacho-apigw #security
