---
title: "api-gateway backend-dial mTLS (per-edge creds selection)"
aliases:
  - apigw backend dial mtls
  - api-gateway per-edge dial creds
category: packages
repo: kacho-api-gateway
layer: cmd
tags:
  - packages
  - kacho-api-gateway
  - security
  - cmd
  - composition-root
---

# api-gateway backend-dial mTLS (per-edge)

**Where**: `cmd/api-gateway/mtls_config.go` + `internal/config/config.go` (SEC-E).
**Layer**: composition-root (cmd) + config. Transport creds only — orthogonal to
JWT/principal/Check (epic invariant I2: client-cert = модуль, principal = пользователь).

## Per-edge model

Один shared «api-gateway» client-cert/key/CA для всех рёбер (одна модульная
identity, OQ-SEC-E-3). Независимый **enable** + **server-name** per edge даёт
rollback per-edge (SEC-E-09).

| Edge | backend keys | env enable | server-name override |
|---|---|---|---|
| vpc | `vpc`, `vpcInternal` | `KACHO_API_GATEWAY_MTLS_VPC_ENABLE` | `..._VPC_SERVER_NAME` |
| compute | `compute`, `computeInternal` | `..._COMPUTE_ENABLE` | `..._COMPUTE_SERVER_NAME` |
| iam | `iam`, `iamInternal`, iam-subject(:9091), iam-authorize | `..._IAM_ENABLE` | `..._IAM_SERVER_NAME` |
| nlb | `loadbalancer`, `loadbalancerInternal` | `..._NLB_ENABLE` | `..._NLB_SERVER_NAME` |

Shared material: `KACHO_API_GATEWAY_MTLS_CLIENT_CERT_FILE` / `_KEY_FILE` / `_CA_FILE`.

## Exported / key funcs

- `config.EdgeTLSClient(edge, dialAddr) (grpcclient.TLSClient, error)` — собирает
  per-edge value-struct; **fail-fast** при enable без cert-материала (SEC-E-03);
  server-name = override или derive из dial-host.
- `backendEdge(backendKey) string` — backend-domain key → edge name.
- `buildBackendDialCreds(cfg) (map[key]grpc.DialOption, error)` — per-edge creds-map.
- `loopbackDialCreds() grpc.DialOption` — **всегда insecure** (operation self-loopback,
  in-process, не cross-pod — SEC-E-07).
- `iamEdgeDialCreds(cfg, addr)` — для двух standalone iam-dial (subject + authorize).
- `dialBackends(cfg) (proxy.Backends, cleanup, error)` — открывает ClientConn per-edge
  (+ keepalive 10s/3s + round-robin, сохранены) + opsLoopback insecure.

## Contract / invariants

- `enable=false` (default) ⇒ `insecure.NewCredentials()`, идентично pre-SEC-E (dev backward-compat).
- `enable=true` без cert/key/ca ⇒ ошибка → `log.Fatalf` в main (НЕ тихий insecure-fallback, epic §6.7).
- mTLS-client vs insecure-server / untrusted-CA ⇒ handshake fail → `Unavailable` (fail-closed, §3.9/§3.11).
- opsLoopback (`operation` domain) — никогда не mTLS.
- creds-слой ⊥ principal-metadata: `x-kacho-principal-*` пробрасывается director'ом поверх mTLS.

## Imports

- `github.com/PRO-Robotech/kacho-corelib/grpcclient` — `TLSClient` + `TLSClientCreds` (SEC-B).
- `internal/config` (EdgeTLSClient), `internal/proxy` (Backends).

## See also

[[../KAC/SEC-E-gateway-mtls]] [[../edges/api-gateway-to-iam-authorize]] [[../edges/api-gateway-to-iam-subject-change]] [[corelib-grpcclient]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#packages #kacho-api-gateway #security #cmd #composition-root
