---
title: corelib-grpcsrv
category: package
repo: kacho-corelib
layer: shared
tags:
  - packages
  - kacho-corelib
  - grpc
---

# corelib/grpcsrv

**Path**: `kacho-corelib/grpcsrv/`
**Imports**: `google.golang.org/grpc`, `.../health`, `.../health/grpc_health_v1`, `.../reflection`, `.../credentials`, `.../credentials/insecure`, `.../peer`, `crypto/tls`, `crypto/x509`, `github.com/PRO-Robotech/kacho-corelib/operations`
**Imported by**: `kacho-vpc/cmd/vpc`, `kacho-iam/cmd/*`, `kacho-api-gateway` (NewServer); SEC-D/E/G подключат TLS-creds + cert-identity interceptors

Bootstrap-helper для gRPC-server с дефолтным набором: health-service (`grpc.health.v1.Health`), server reflection, recovery interceptor.

## Exported functions

- `NewServer(opts ...grpc.ServerOption) *grpc.Server` — создаёт `*grpc.Server`, регистрирует health-svc (`SERVING`) и reflection. Принимает доп. `ServerOption` (TLS creds, interceptor chains).

### SEC-B — opt-in mTLS server-creds (`tls.go`)

- `TLSServer{Enable, CertFile, KeyFile, ClientCAFiles []string}` — per-edge config (FD-3, нет глобального TLS-синглтона). `enable=false` ⇒ insecure (FD-1, backward-compat).
- `TLSServerCreds(TLSServer) (grpc.ServerOption, error)` — единая точка истины (FD-7). `enable=true` ⇒ server-cert + client-CA + `RequireAndVerifyClientCert` (FD-2). Misconfig (нечитаемый cert / пустой client-CA) ⇒ error, НЕ silent insecure fallback (FD-6). Гард SEC-B-19 (`tls_guard_test.go`): прямой `credentials.NewTLS`/`tls.Config` вне helper'а — RED.

### SEC-B — cert-identity extractor + trust-invariant (`cert_identity.go`)

- `CertIdentity(*x509.Certificate) string` — verbatim opaque SAN `spiffe://kacho.cloud/...` из verified client-cert (FD-5; без parse/resolve в SA — это SEC-C). nil/no-SAN/чужой trust-domain ⇒ `""` (детерминированно); multi-SAN ⇒ первый kacho-spiffe.
- `WithCertIdentity` / `CertIdentityFromContext(ctx) (id string, verified bool)` — носитель cert-identity + mTLS-verified флага.
- `UnaryCertIdentityExtract()` / `StreamCertIdentityExtract()` — классифицируют peer (insecure / TLS-no-verified-cert / mTLS-verified) и кладут cert-identity в ctx. Ставить ПЕРЕД principal-extract.
- `UnaryTrustedPrincipalExtract()` / `StreamTrustedPrincipalExtract()` + `TrustedPrincipalFromContext(ctx) (operations.Principal, bool)` — инвариант доверия (FD-4): principal-metadata доверяется ⟺ peer mTLS-verified; insecure-listener ⇒ dev backward-compat; TLS-без-verified-cert ⇒ principal отбрасывается. cert-identity (модуль) и principal (пользователь) — ортогональны, оба доступны downstream для аудита.

### sub-phase 5.4 — acr carrier (`acr.go` + `cert_identity.go`)

- `MDKeyTokenACR = "x-kacho-token-acr"` — trusted metadata-ключ с validated JWT `acr` (api-gateway forwards на mTLS-verified gateway→iam re-dial, рядом с `x-kacho-principal-*`).
- `UnaryTrustedPrincipalExtract` доп. читает `acr` и кладёт в trusted-carrier **только когда trusted** (тот же FD-4 boundary): на untrusted/unverified peer `acr` отбрасывается вместе с principal (anti-spoof). insecure dev-listener ⇒ принимается как сегодня.
- `TrustedACRFromContext(ctx) (acr string, trusted bool)` — accessor. `WithTrustedACR(ctx, acr, trusted)` — test-support helper (mirror `WithCertIdentity`).
- `ACRRank(acr) int` (`""/"0"<"1"<"2"<"3"`, unknown ⇒ 0) + `ACRSatisfies(presented, required) bool` (`required==""/"0"` ⇒ no-op) — **единая** ranking-точка, общая для api-gateway StepUpGate и iam ACRFloor (no drift). Imported-by: `kacho-iam/internal/authzguard` (ACRFloor), `kacho-api-gateway/internal/restmux` (forwards acr).

## Convention

- Каждый сервис в `cmd/<svc>/main.go` зовёт `grpcsrv.NewServer(...)` для public-listener (9090) и отдельно для internal-listener (9091).
- Interceptor chain (UnaryInterceptor) дополняется в самом сервисе: `recovery`, `logging`, `validate`, `auth` (если есть). На mTLS internal-listener'е (SEC-D/E/G): `UnaryCertIdentityExtract` → `UnaryTrustedPrincipalExtract` → бизнес.
- mTLS включается per-edge флагом в SEC-D/E/G; SEC-B мёржится с `enable=false` повсеместно (транспорт не меняется).

## See also

[[corelib-grpcclient]] [[corelib-config]] [[corelib-auth]] [[vpc-cmd-vpc]] [[rm-cmd]] [[../KAC/EPIC-SEC-mtls-iam-authz]]

#packages #kacho-corelib #grpc
