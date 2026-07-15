---
title: "registry → iam: JWKS-fetch (data-plane Bearer verify via iam proxy)"
aliases:
  - registry to iam jwks
  - registry jwks via iam
category: edge
caller_repo: kacho-registry
callee_repo: kacho-iam
sync_async: sync
protocol: HTTPS GET (OIDC well-known JWKS)
status: in-progress
related_tickets:
  - "[[KAC-registry-iam-jwks-unify]]"
tags:
  - edge
  - cross-service
  - kacho-registry
  - kacho-iam
  - security
---

> [!note] Изменение — только распределение ключей верификации
> data-plane скачивает JWKS **из iam**, а НЕ из Hydra напрямую. **Hydra остаётся issuer'ом и
> подписантом** registry-Bearer'а; iam ключи не пере-чеканит — отдаёт байт-в-байт зеркало
> публичного JWKS Hydra. JWKS-URL и issuer-pin — **раздельные** knob'ы.

# registry → iam: JWKS-fetch

**Caller**: `kacho-registry` data-plane (`jwks/verifier.go` — origin-agnostic `http.Client`,
kid-keyed cache, on-miss single-refetch). Registry-side изменение — **только config**
(`HydraJWKSURL`→`IAMJWKSURL`, env `KACHO_REGISTRY_HYDRA_JWKS_URL`→`KACHO_REGISTRY_IAM_JWKS_URL`);
`verifier.go` не тронут.
**Callee**: `kacho-iam` — 4-й cluster-internal HTTPS-листенер `:9097` `GET /.well-known/jwks.json`
(short-TTL кэширующий reverse-proxy публичного JWKS Hydra). Выставлен **только** на Service
`kacho-iam-internal`; upstream env `KACHO_IAM_HYDRA_JWKS_URL`.
**Protocol**: HTTPS GET (standard OIDC well-known). **server-TLS** (one-way, internal-CA leaf) —
**не** mTLS; registry-под доверяет internal-CA.
**Sync/Async**: **sync** на request-path (verify docker-Bearer при push/pull).
**URL (prod)**: `https://kacho-iam-internal.kacho.svc.cluster.local:9097/.well-known/jwks.json`.

## Почему PROXY, а не serve-from-store

iam НЕ отдаёт свои `oidc_jwks_keys` (их `kid` = `kacho-<alg>-<unixnano>`), т.к. токен несёт
**Hydra'шный `kid`** → отдача `kacho-*`-ключей = гарантированный kid-miss = fail-closed отказ
**каждого** pull. Зеркалируется та же Hydra well-known JWKS-URL, что уже верифицирует живые
pull'ы → kid/alg-паритет без гадания о keyset'е. Стор `oidc_jwks_keys` / jwks-rotator /
`HydraPublisher` — рудимент, вне verify-пути, не тронут.

## Почему через iam (unify identity)

Единый путь распределения ключей через iam: **data-plane никогда не звонит в Hydra** напрямую
(нет сетевого хопа registry→Hydra) — Hydra прячется за iam. iam остаётся единой точкой
identity-плоскости; issuer-pin (`KACHO_REGISTRY_HYDRA_ISSUER`) по-прежнему форсит Hydra-issuer.

## Fail-closed / кэш

| Ситуация | Поведение |
|---|---|
| iam cold-cache + Hydra down | iam → `502`/`503` (никогда empty-`200`, никогда `kacho-*`-kid) |
| iam warm-cache + Hydra blip | bounded-stale `200` из кэша (в пределах short TTL), затем деградация в fail-closed |
| verifier без кэш-ключа + iam 5xx | docker-клиенту `401 invalid_token` (fail-closed, **никогда** allow) |
| verifier within-TTL кэш + iam blip | verify успешен из кэша |
| ротация Hydra (new kid) | iam refetch → verifier on-miss refetch → verify OK |

## AuthN — задокументированное исключение

JWKS-route **internal-only + unauthenticated-by-design** (публичные ключи, standard OIDC) поверх
server-TLS — осознанное исключение из `security.md` «authN на каждом листенере». Не на external
:9096, не на gRPC :9091, **не** в api-gateway restmux (ban #6) — прямой svc-to-svc fetch.

## History

- **2026-07-15** ([[KAC-registry-iam-jwks-unify]]): edge introduced. S1 iam internal JWKS-proxy
  `:9097` (kacho-iam PR#323); S2 registry config-flip на iam-URL, `verifier.go` untouched
  (kacho-registry PR#42); S3 deploy (port/Service + CA-trust + iam-first sequence) pending; S4
  docs+vault (kacho-workspace, this edge). Замещает прямой Hydra-public JWKS fetch data-plane'а.

## See also

[[iam-to-hydra-admin]] [[SEC-J-gateway-hydra-jwks-authn]] [[compute-to-iam-check]]

#edge #cross-service #kacho-registry #kacho-iam #security
