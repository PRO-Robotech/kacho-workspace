---
title: apigw-health
category: package
repo: kacho-api-gateway
layer: handler
tags:
  - packages
  - kacho-apigw
  - health
  - k8s
---

# kacho-api-gateway/internal/health

**Path**: `kacho-api-gateway/internal/health/`

Healthcheck handler (k8s readiness/liveness).

## Files

- `health.go` — HTTP handler `/healthz` + `/readyz` (последний проверяет upstream-connectivity к каждому backend).
- `health_test.go`.

## Probes (k8s)

- `/healthz` — liveness; всегда 200, пока процесс жив.
- `/readyz` — readiness; 200 только если gw может dial к **всем** активным backend'ам (rm/vpc/compute).

## See also

[[apigw-cmd]] [[../kacho-deploy/README]]

#packages #kacho-apigw #health #k8s
