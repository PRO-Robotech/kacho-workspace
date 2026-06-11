---
title: corelib-grpcclient
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - grpc
---

# corelib/grpcclient

**Path**: `kacho-corelib/grpcclient/`
**Imports**: `google.golang.org/grpc`, `.../keepalive`, `.../credentials`, `.../credentials/insecure`, `crypto/tls`, `crypto/x509`
**Imported by**: dial-сайты сервисов (compute→iam/vpc, vpc→iam/compute, iam drainer, api-gateway→backend); SEC-E/G подключат TLS client-creds

Горизонтальные helper'ы для client-side gRPC dial: keepalive (KAC-244) и SEC-B opt-in mTLS client-credentials.

## Exported functions

### Keepalive (KAC-244)

- `KeepaliveParams(permitWithoutStream bool) keepalive.ClientParameters` — Time 10s, Timeout ~3.3s.
- `KeepaliveDialOption(permitWithoutStream bool) grpc.DialOption`.

### SEC-B — opt-in mTLS client-creds (`tls.go`)

- `TLSClient{Enable, CertFile, KeyFile, CAFiles []string, ServerName}` — per-edge config (FD-3). `enable=false` ⇒ insecure dial (FD-1, backward-compat). Env-теги — `KACHO_<DOMAIN>_TLS_CLIENT_*` (полное имя через explicit-tag fallback envconfig).
- `TLSClientCreds(TLSClient) (grpc.DialOption, error)` — единая точка истины (FD-7). `enable=true` ⇒ client-cert + server-CA + проверка `server_name` против SAN серверного cert (FD-2). Пустая пара cert/key при `enable=true` ⇒ one-way TLS (без client-cert) — для теста require-and-verify reject (SEC-B-06/16). Misconfig (нечитаемый cert / пустой `ca_files` / пустой `server_name`) ⇒ error, НЕ silent insecure fallback (FD-6).

## Convention

- Helper'ы — единственный способ собрать TLS-creds для inter-service gRPC (гард SEC-B-19 в `grpcsrv/tls_guard_test.go` ловит прямой `credentials.NewTLS`/`tls.Config` вне `tls.go`).
- mTLS-сторона клиента согласуется с серверной (`grpcsrv.TLSServerCreds`): mismatch enable ⇒ `Unavailable` (per-edge, нет тихого downgrade).
- Включение per-edge — SEC-E (api-gateway→backend), SEC-D (vpc/compute→iam), SEC-G (operator→vpc). SEC-B мёржится с `enable=false`.

## See also

[[corelib-grpcsrv]] [[corelib-config]] [[corelib-auth]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#packages #kacho-corelib #grpc
