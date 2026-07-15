---
title: "registry-iam-jwks-unify: registry verifies via iam INTERNAL Hydra-JWKS proxy"
aliases:
  - registry iam jwks unify
  - KAC-registry-iam-jwks-unify
ticket_id: TBD
category: kac
status: in-progress
type: feat
repos:
  - kacho-iam
  - kacho-registry
  - kacho-deploy
  - kacho-workspace
prs:
  - "PRO-Robotech/kacho-iam#323"
  - "PRO-Robotech/kacho-registry#42"
  - "PRO-Robotech/kacho-workspace#131"
yt_url: TBD
opened: 2026-07-15
tags:
  - kac
  - feature
  - kacho-iam
  - kacho-registry
  - kacho-deploy
  - kacho-workspace
  - security
  - cross-service
---

# registry-iam-jwks-unify

**Status**: in-progress (S1 iam + S2 registry PR-open; S3 deploy pending; S4 docs/vault — this PR)
**Type**: feat + config (новый internal HTTPS-листенер iam + registry config-rename; authN
key-distribution wiring) — **не** новый ресурс/RPC/proto/схема-БД
**Repos**: kacho-iam (code+chart) · kacho-registry (config+tests) · kacho-deploy (helm/env) ·
kacho-workspace (docs+vault)
**YT**: TBD (тикет ещё не заведён)
**Acceptance**: `docs/specs/sub-phase-registry-iam-jwks-unify-acceptance.md` (APPROVED, RJU-01..24)

## Что и зачем

Сегодня registry data-plane верифицирует подпись docker-Bearer'а, скачивая JWKS **напрямую с
Hydra**. Фаза разворачивает единый путь: **iam публикует cluster-INTERNAL HTTPS
`GET /.well-known/jwks.json` (`:9097`)** — short-TTL кэширующий reverse-proxy публичного JWKS
Hydra, а data-plane скачивает JWKS **из iam и НИКОГДА не звонит в Hydra напрямую**.

- **Hydra остаётся issuer'ом/подписантом** — iam отдаёт байт-в-байт зеркало, `kid`/`alg` совпадают
  с реально подписанными Hydra токенами. iam ключи **не** чеканит (proxy, не minting); стор
  `oidc_jwks_keys`/jwks-rotator/`HydraPublisher` — рудимент, вне verify-пути, не тронут.
- **Раздельные knob'ы**: JWKS-URL → iam; issuer-pin (`KACHO_REGISTRY_HYDRA_ISSUER`) остаётся на Hydra.
- **registry-side — только config** (`HydraJWKSURL`→`IAMJWKSURL`); `jwks/verifier.go` origin-agnostic,
  **не тронут**.
- **Fail-closed** на всех путях: iam cold+down → 502/503; verifier без кэш-ключа → docker `401
  invalid_token`; никогда allow, никогда empty-200.
- **AuthN-исключение**: JWKS-route internal-only + unauthenticated-by-design (публичные ключи,
  server-TLS) — задокументировано в `security.md`.

## Кросс-репо порядок (граф iam → registry → deploy → docs)

| Стадия | Репо | PR | Статус |
|---|---|---|---|
| S1 | kacho-iam — internal JWKS-proxy `:9097` | [#323](https://github.com/PRO-Robotech/kacho-iam/pull/323) | open |
| S2 | kacho-registry — config-flip на iam-URL, verifier untouched | [#42](https://github.com/PRO-Robotech/kacho-registry/pull/42) | open |
| S3 | kacho-deploy — port/Service + CA-trust + iam-first sequence | — | pending |
| S4 | kacho-workspace — polyrepo/security/edge/KAC-trail | [#131](https://github.com/PRO-Robotech/kacho-workspace/pull/131) | open |

## Затронутые сущности vault

- [[registry-to-iam-jwks-fetch]] — новое runtime-ребро (HTTPS GET JWKS, sync, fail-closed, internal-CA).
- [[iam-to-hydra-admin]] — Hydra остаётся issuer/подписантом (iam proxy'ит его public JWKS).
- [[SEC-J-gateway-hydra-jwks-authn]] — смежный JWKS/authN путь (gateway валидирует Hydra RS256 JWT).

## DoD

- [x] APPROVED `acceptance-reviewer` (RJU-01..24) до кода (ban #1).
- [x] S1 kacho-iam: internal Hydra-JWKS proxy `:9097` live (PR#323); vestige `oidc_jwks_keys` не тронут.
- [x] S2 kacho-registry: config-only, `verifier.go` untouched; issuer-pin остаётся на Hydra (PR#42).
- [ ] S3 kacho-deploy: `jwksProxy=9097` на `kacho-iam-internal` + registry env-flip + internal-CA-trust.
- [ ] **Deploy iam-first + smoke-before-flip** (RJU-17/I11): iam-эндпоинт verified serving
      (`GET /.well-known/jwks.json` → 200 с Hydra-kid'ами) **до** флипа `registry.iam.jwksUrl`
      (преждевременный флип = 401-storm на всех pull'ах).
- [x] S4 kacho-workspace: polyrepo runtime-edge + security.md internal-only note + vault edge + KAC-trail.
- [ ] doc-truthfulness: стейл-docstring'и registry, отрицающие JWKS-эндпоинт, исправлены (RJU-22, в S1/S2).
- [ ] `go test ./... -race` + `golangci-lint` + `govulncheck` + newman green в iam и registry.
- [ ] e2e push+pull на стенде (RJU-23) + fail-closed pull-401 (RJU-24); тикет → Test → Done с артефактами.

## Связанные

- Смежные authN/JWKS: [[SEC-J-gateway-hydra-jwks-authn]] · Hydra lifecycle: [[iam-to-hydra-admin]].

#kac #feature #kacho-iam #kacho-registry #kacho-deploy #kacho-workspace #security #cross-service
