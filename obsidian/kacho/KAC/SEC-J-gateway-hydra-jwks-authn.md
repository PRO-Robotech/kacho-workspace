---
title: "SEC-J: api-gateway validates real Hydra RS256 access JWTs in the principal path"
aliases:
  - SEC-J
  - SEC-J-gateway-hydra-jwks-authn
ticket_id: SEC-J
category: kac
status: test
type: bugfix
repos:
  - kacho-api-gateway
  - kacho-deploy
prs: []
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-12
tags:
  - kac
  - bugfix
  - kacho-api-gateway
  - kacho-deploy
  - security
  - cross-service
---

# SEC-J: gateway Hydra-JWKS authN (principal path)

**Status**: test (код готов, Go-тесты + helm render-тест зелёные; ждёт ревью + merge)
**Type**: bugfix + config (authN wiring, не новый ресурс/RPC)
**Repos**: kacho-api-gateway (код), kacho-deploy (helm env)
**Branch**: `SEC-J-gateway-hydra-jwks-authn`
**Acceptance**: `docs/specs/sub-phase-SEC-J-gateway-hydra-jwks-authn-acceptance.md` (APPROVED)

## Что и зачем

После реального Hydra-логина (register+login через Kratos/Hydra) SPA держит
**Hydra-issued RS256 access JWT**. Вызов `AuthorizeService/WhoAmI` (и Account/Project)
возвращал code 16 `AUTHN_REQUIRED` «subject: unauthenticated request».

**Причина**: principal-устанавливающий `AuthInterceptor`
(`internal/middleware/auth.go`) валидировал **только HMAC-dev JWT**; Hydra RS256
токены не валидировались → запрос доходил до iam анонимным → authz-gate reject.

**Фикс (это WIRE, не build с нуля)** — verifier уже существовал
(`jwt_verifier.go`/`jwk.go`, RFC 8725, RS256, JWKS-cache), сконструирован в
`cmd/main.go` для DPoP, но **не** подключён в `NewAuthInterceptor`:

1. `AuthInterceptor.WithVerifier(TokenVerifier)` — вторая стратегия рядом с HMAC.
2. `authorize` (gRPC) + `HTTP` (REST): детект `alg` в JWT-хедере — RS256/ES256/EdDSA →
   JWKS-verify; HMAC → существующий dev-path (нулевая регрессия).
3. Principal строится из **верифицированных** `kacho_principal_type` +
   `kacho_principal_id` (+ display) — top-level ИЛИ `ext_claims` (robust placement);
   SubjectLookuper — fallback только при отсутствии claims.
4. Bad token (sig/exp/iss/alg/malformed/no-sub) **или** JWKS unreachable →
   reject Unauthenticated (fail-closed), **никогда** anonymous, во всех режимах.
5. `cmd/main.go`: verifier строится **независимо** от DPoP feature-flag, подаётся
   в AuthInterceptor; DPoP переиспользует тот же инстанс (один JWKS-cache).
6. **deploy** (Scenario F): umbrella `values.dev.yaml` api-gateway `hydra.issuer`
   = `http://localhost:28080/.ory/hydra/public/` (== Hydra dev `self.issuer`).
   `jwksUrl` уже указывал на `kacho-umbrella-hydra-public:4444`. Issuer был
   пропущен → verifier делает exact-match `iss` → derived default ломал бы каждый
   реальный токен. prod уже имел оба значения.

## RED→GREEN

- Go: `internal/middleware/auth_jwks_test.go` (RED: `WithVerifier` не существовал →
  compile-fail) → GREEN после wiring. Покрыты A/A2/A3/A4, B2 coexistence, D d1-d7,
  E fail-closed, REST parity.
- Helm: `tests/helm/hydra-jwks-url-test.sh` +1 assertion (dev `KACHO_HYDRA_ISSUER`).
  RED без `issuer:` в `values.dev.yaml` → GREEN после.

## Затронутые сущности vault

- [[apigw-middleware]] — AuthInterceptor теперь держит JWKS-verifier стратегию (TokenVerifier port).
- [[api-gateway-to-iam-authorize]] — RS256 principal-path активен (WhoAmI/Account/Project аутентятся).
- [[apigw-cmd]] — verifier строится независимо от DPoP-флага, подаётся в AuthInterceptor + DPoP.

## DoD

- [x] RED-first Go-тест (compile-fail) → GREEN.
- [x] `WithVerifier` + JWKS-path в gRPC `authorize` и REST `HTTP` (parity).
- [x] Principal из `kacho_principal_*` (top-level/ext_claims); lookup fallback.
- [x] HMAC-dev path без изменений; no-Bearer per-mode без изменений.
- [x] Bad token / JWKS unreachable → reject, никогда anonymous (все режимы).
- [x] cmd wiring (reuse instance с DPoP).
- [x] deploy: dev issuer == Hydra self.issuer; helm render-тест зелёный (RED→GREEN).
- [x] `go build ./...` + `go test ./...` зелёные (gateway-модуль).
- [ ] Manual dev-stand: register+login → WhoAmI 200 (исходный баг ушёл) — на оркестраторе.
- [ ] Newman happy/negative против живого Hydra-токена (live-stand e2e).

## Связанные

- Эпик: [[EPIC-SEC-mtls-iam-authz]] · смежные authN: [[SEC-E-gateway-mtls]]
