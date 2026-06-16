---
title: api-gateway → iam — acr-on-internal step-up floor
category: edge
caller_repo: kacho-api-gateway
callee_repo: kacho-iam
sync_async: sync
protocol: grpc
status: stable
related_tickets:
  - kacho-iam#122
tags:
  - edge
  - kacho-api-gateway
  - kacho-iam
  - internal
  - cross-service
---

# api-gateway → iam — `required_acr_min` step-up on :9091 (sub-phase 5.4)

**Edge**: api-gateway internal-mux re-dial → kacho-iam :9091 (gateway-fronted privileged RPCs).
**Protocol**: gRPC over mTLS (SEC-K gateway client-cert SAN `…/sa/kacho-api-gateway`). Sync.

## Что

`required_acr_min` (step-up / MFA-freshness floor) энфорсился **только** на публичном пути
(gateway `StepUpGate`), но gateway **ронял** acr при re-dial на :9091 → gateway-fronted privileged
RPC (`InternalClusterService/{Get,GrantAdmin,RevokeAdmin,ListAdmins}`, уже с `acr_min=2`) **не**
acr-энфорсился внутри. Sub-phase 5.4 замыкает плечо end-to-end:

1. **gateway** (`restmux/mux.go` `buildPrincipalMetadata`) — пробрасывает validated acr
   (`X-Kacho-Token-Acr`, который public DPoP-middleware уже выставляет) как `x-kacho-token-acr`
   metadata, рядом с `x-kacho-principal-*`. absent acr ⇒ ключ не добавляется.
2. **corelib** (`grpcsrv.UnaryTrustedPrincipalExtract`) — вносит acr в trusted-carrier **только**
   когда trusted (FD-4: peer mTLS-verified); на unverified peer acr dropped (anti-spoof).
   `TrustedACRFromContext` + shared `ACRRank`/`ACRSatisfies`.
3. **iam** (`authzguard.ACRFloor`) — interceptor на :9091 **после** `UnaryTrustedPrincipalExtract`
   + `internalCallerPolicy`: для gateway-fronted RPC с catalog `acr_min>0` энфорсит
   `acr >= acr_min` → иначе `PermissionDenied` + step-up signal (`PreconditionFailure`,
   `authz.step_up`, `acr_values:<min>`) для RFC-9470 challenge. FQN→acr_min из embedded
   permission-каталога (`seed.PermissionRegistry.RequiredACRMin`).

## Trust / scope

- acr доверяем **только** на mTLS-verified gateway-ребре (FD-4). Спуфнутый acr с non-gateway peer
  → dropped (rank 0) + `internalCallerPolicy` отклоняет non-gateway SAN на gateway-fronted RPC
  **раньше** floor'а (5.4-06).
- Module-SA (vpc/compute fgaproxy) — **acr-exempt** (не user-principal, нет MFA); floor трогает
  только gateway-fronted set.
- Default-OFF: dev/newman (prod=false) ⇒ NO-OP pass-through (byte-identical). Prod fail-closed:
  absent acr на acr-требующем RPC ⇒ denied.
- Latent-until-policy: прочие gateway-fronted admin-RPC сегодня `acr_min=0` ⇒ floor inert до
  policy-изменения (механизм generic по FQN→acr_min — доказано фикстурой 5.4-08).

## History

- **2026-06-16** (sub-phase 5.4, kacho-iam#122): edge создан. corelib `feat/acr-on-internal`
  (grpcsrv acr carrier) → iam (ACRFloor) → api-gateway (forward acr). Merge order
  corelib → iam → gateway. PRs: kacho-corelib#23, kacho-iam#149, kacho-api-gateway#80.

## See also

[[../packages/corelib-grpcsrv]] [[api-gateway-to-iam-authorize]] [[../KAC/KAC-122]]

#edge #kacho-api-gateway #kacho-iam #internal #cross-service
