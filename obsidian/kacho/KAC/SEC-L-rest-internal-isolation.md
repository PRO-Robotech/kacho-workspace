---
title: "SEC-L: isolate Internal* REST from the external listener + drop Internal* FQNs from public allowlist"
aliases:
  - SEC-L
  - SEC-L-rest-internal-isolation
ticket_id: SEC-L
category: kac
status: test
type: fix
repos:
  - kacho-api-gateway
prs:
  - https://github.com/PRO-Robotech/kacho-api-gateway/pull/78
yt_url: https://prorobotech.youtrack.cloud/issue/EPIC-SEC
opened: 2026-06-16
tags:
  - kac
  - fix
  - kacho-api-gateway
  - security
  - internal
---

# SEC-L: REST Internal* external-isolation + allowlist priv-esc

**Status**: test (код готов, Go-тесты RED→GREEN зелёные, gosec=0 на changed pkgs; ждёт ревью + CI + merge)
**Type**: fix (P0 security — без нового ресурса/RPC/поля)
**Repos**: kacho-api-gateway
**Branch**: `fix/rest-internal-isolation`
**PR**: https://github.com/PRO-Robotech/kacho-api-gateway/pull/78

## Что и зачем (две дыры, найдены аудитом)

`Internal*` RPC были достижимы / авторизованы с advertised **external TLS edge**
(workspace CLAUDE.md §запрет #6, security.md §AuthN+AuthZ).

- **(A) REST**: один `httpSrv` обслуживает оба listener'а (plaintext internal `:8080`
  + external TLS). `isInternalPath` выбирал только JSON-marshaller — не отклонял по
  listener'у. → `/iam/v1/internal/*`, `/vpc/v1/addressPools`,
  `/vpc/v1/networks/{id}:internal`, `InternalClusterService` и т.д. были externally
  REST-достижимы. gRPC-director блокировал `Internal*` (`HasInternalSuffix`); REST — нет.
- **(B) authz**: `DefaultPublicAllowlist()` содержал 4 `Internal*` FQN
  (`InternalIAMService/{Check,ListPermissions,LookupSubject}`,
  `InternalUserService/UpsertFromIdentity`). `decide()` step-1 short-circuit'ил в
  ALLOW **до** authN → unauthenticated authz-oracle / user-enumeration /
  user-mutation с edge (в связке с A).

## Fix (зеркалит gRPC-director для REST; origin различается по listener)

- new `internal/listenerorigin`: per-listener marker. Wrap external TLS HTTP
  sub-listener (`ExternalListener`) + `httpSrv.ConnContext` кладёт тег в request-ctx;
  internal listener остаётся unmarked.
- restmux dispatcher: `Internal*`-путь (`isInternalPath`) с external origin → **404**.
  Плюс `isInternalPath` теперь ловит `:internal` verb-suffix
  (`InternalNetworkService.GetNetwork` = `/vpc/v1/networks/{id}:internal`), который
  раньше уходил на public mux.
- authz: убраны 4 `Internal*` FQN из `DefaultPublicAllowlist()`; вместо них
  internal-origin gate в `decide()` — bypass authN для `<exempt>` `Internal*` RPC
  **только** на internal listener. Gated `Internal*` (реальный `required_relation`,
  напр. `InternalClusterService` D-11) по-прежнему проходят полный FGA Check даже
  внутри; external caller'ы → authN-required / 404.

## Internal callers сохранены (newman не ломается)

UI / admin / port-forward + service self-calls идут на plaintext internal listener
(newman `baseUrl` `http://localhost:18080` → `:8080`), unmarked → served.
newman `externalBaseUrl` (`api.kacho.local:443`) → 404 — ровно то, что ждёт
`iam-internal-only-check.py` (negatives). `cluster_admin.py` гоняется по `baseUrl`
(internal) и сохраняет FGA-гейт.

## TDD RED→GREEN

- restmux `external_isolation_test.go`: `Internal*` на external → 404 (было 503/routed);
  internal → reachable; public на external → не затронут.
- middleware `authz_internal_origin_test.go`: 4 FQN отсутствуют в allowlist; external
  unauth exempt `Internal*` → 401; internal-origin exempt → allow (без FGA Check);
  gated `Internal*` (`InternalClusterService`) на internal origin всё ещё FGA-Checked → 403.
- cmd `external_isolation_wiring_test.go`: e2e listener wiring (tls+cmux) — external
  marker доходит до handler; internal остаётся internal.

## Затронутые сущности vault

- [[../edges/apigw-internal-vs-tls]] (обновлён: enforcement, не только marshaller)
- [[../packages/apigw-restmux]] · [[../packages/apigw-allowlist]] ·
  [[../packages/api-gateway-middleware-authz]]

## DoD

- [x] RED→GREEN на всех трёх поверхностях
- [x] go build / vet / `go test -short ./...` 0 FAIL / `-race` changed pkgs green
- [x] gosec -severity high = 0 на changed packages (2 pre-existing — в нетронутом `jwt_verifier.go`)
- [x] PR #78 открыт
- [ ] CI зелёный (gosec / govulncheck / newman E2E) — pending
- [ ] ревью + merge → status `done`, ветка удалена

## Связанные

[[EPIC-SEC-mtls-iam-authz]] · [[SEC-K-restmux-mtls]] · [[SEC-J-gateway-hydra-jwks-authn]]

#kac #fix #kacho-api-gateway #security #internal
