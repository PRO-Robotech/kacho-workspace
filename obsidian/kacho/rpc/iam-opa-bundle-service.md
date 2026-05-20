---
title: OPABundleService
aliases:
  - OPA Bundle (iam, internal)
proto_file: (none — REST endpoint OPA bundle-protocol)
category: rpc
backend: kacho-iam
backend_port: 9091
visibility: internal
domain: iam
related_resource: "[[resources/iam-cluster]]"
methods_count: 3
async_methods: 0
status: planned
related_tickets:
  - "[[KAC-127]]"
tags:
  - rpc
  - kacho-iam
  - iam
  - internal
  - opa
---

# OPABundleService (iam, internal)

**Spec**: OPA Bundle API (https://www.openpolicyagent.org/docs/management-bundles). REST/JSON polling.
**Backend**: `kacho-iam:9091` — cluster-internal. NOT gRPC — REST для OPA agent compatibility.
**Visibility**: **Internal** — OPA sidecar в каждом сервисе (vpc / compute / api-gateway) полл'ит этот endpoint.
**Status**: **Phase 3 planned**. Bundle-сервер для централизованной OPA policy distribution.

## Endpoints (OPA bundle-protocol)

| HTTP | Description |
|---|---|
| `GET /iam/v1/internal/opa/bundles/{bundle_name}.tar.gz` | OPA agent polls; ETag-based caching. Returns gzipped tarball: `.manifest`, `*.rego`, `data.json`. |
| `GET /iam/v1/internal/opa/bundles/{bundle_name}/signature` | cosign signature payload (Phase 11 supply-chain). |
| `POST /iam/v1/internal/opa/bundles:reload` | admin trigger — invalidate cache + bump revision. |

## Bundles distributed (Phase 3 catalog)

- `cluster-deny` — org-wide deny rules (break-glass override, GDPR-locked data, regional residency).
- `step-up-policy` — when MFA fresh + ACR required (per-RPC sensitivity).
- `quota-guard` — rate limits / per-account spend ceilings.
- `data-classification` — PII / financial / health resource categorization → deny export по политике.
- `iam-bootstrap` — kacho-iam own self-rules (RFC 7234 § Bundle Signing).

## Bundle format

```
bundle.tar.gz/
├── .manifest         # roots[] = ["kacho.cluster", "kacho.stepup"]; revision = "2026-05-19-T13"; rego-version = "v1"
├── policies/
│   ├── cluster_deny.rego
│   ├── step_up.rego
│   └── ...
└── data.json         # cached cluster state snapshot (org list, condition catalog)
```

## Signing & verification

1. CI bundles → cosign sign-blob → `.signature`.
2. OPA agent config: `verification.public_keys.kacho_root.key` (committed в OPA chart).
3. OPA fail-closed если signature verify fail.

## Notes

- Phase 3 production-ready: ВСЕ OPA decisions signed-bundle distributed. НИКАКИХ unsigned inline policies.
- Revision bump на каждый ReloadModel — OPA agent eventually-consistent polling interval 30s (configurable).
- Кэш ETag в-memory; bundle артефакт также S3-mirrored для multi-region replay (Phase 11).

## See also

[[iam-internal-authorize-service]] [[iam-authorize-service]] [[../resources/iam-cluster]] [[../edges/iam-to-opa]] [[../KAC/KAC-127]]

#rpc #kacho-iam #iam #internal #opa
