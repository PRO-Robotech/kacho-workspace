---
title: "kacho-vpc/internal/apps/kacho/check"
aliases:
  - vpc check package
  - vpc authz interceptor
category: packages
repo: kacho-vpc
layer: composition
tags:
  - packages
  - kacho-vpc
  - authz
  - composition-root
  - e3
---

# kacho-vpc/internal/apps/kacho/check

Composition-root пакет, который превращает corelib `authz`-interceptor в готовую
сборку для kacho-vpc: permission map + IAM client adapter + factory.

**Layer:** composition (как `cmd/vpc/main.go` wiring; импортирует service + corelib + proto-stubs).

## Файлы

- `doc.go` — overview.
- `permission_map.go` — `PermissionMap()` возвращает `authz.RPCMap` со всеми
  публичными RPC kacho-vpc (60+ записей): Network / Subnet / Address /
  RouteTable / SecurityGroup / Gateway / PrivateEndpoint / NetworkInterface +
  Operation.
- `check_client.go` — `IAMCheckClient` (gRPC adapter поверх
  `iamv1.InternalIAMServiceClient.Check`), реализует port `authz.CheckClient`.
- `factory.go` — `NewInterceptor(Options) (*authz.Interceptor, error)` +
  sentinel `ErrIAMConnNotConfigured`.
- `interceptor_test.go` — 10 unit-тестов (allow/deny/unavailable/no-principal/
  unmapped/internal-bypass/cache-hit/breakglass + factory + coverage snapshot).

## Семантика permission map

- `Create / List`              → `editor / viewer` на `project:<project_id>`.
- `Update / Delete / Move / <verb>` → `editor` на `<resource_type>:<resource_id>`.
- `OperationService.Get/Cancel` → `viewer / editor` на `vpc_operation:<id>`.
- `GetAddressByValue` со `scope.subnet_id`  → `viewer` на subnet'е;
  no-scope path → fail-closed (KAC-108 follow-up).
- `Internal*` RPC — **тоже в карте**; пропуск Check выдаётся записью
  (`Public=false`/`ScopeFiltered`), а не выводится из имени метода. Незамапленный RPC
  отказывает (см. [[corelib-authz]] §Decision pipeline).

## Wiring

```go
// cmd/vpc/main.go
authzIntr, err := check.NewInterceptor(check.Options{
    ServiceName: "kacho-vpc",
    IAMConn:     authzConn,   // gRPC к kacho-iam:9091
    Breakglass:  cfg.AuthZ.Breakglass,
    Logger:      logger,
})
if authzIntr != nil {
    publicUnary = append(publicUnary, authzIntr.Unary())
    publicStream = append(publicStream, authzIntr.Stream())
}
```

Internal-листенер собирается **той же** цепочкой, что публичный: `authzIntr` навешивается
на ОБА (`internalUnary`/`internalStream` в `cmd/vpc/main.go`), плюс cert-identity и
trusted-principal extract.

> [!important] «Internal = trusted, mTLS достаточно» — запрещённое допущение
> mTLS доказывает ровно одно: пир предъявил сертификат нашего CA. Он не говорит, **кто**
> вызывающий и **на что** у него право, поэтому сам по себе не заменяет per-RPC Check.
> Внутренний периметр не доверенный — это defense-in-depth против бокового движения:
> один скомпрометированный сосед иначе получает всё, что выставлено на :9091.
> Ban #6 сужает **поверхность методов** (что вообще опубликовано наружу) и никогда не
> означал «на internal можно без проверки прав» — это разные вопросы, и их смешение
> держало дыру, пока выглядело как ссылка на правило. См. `security.md`
> §«AuthN+AuthZ ВЕЗДЕ», п. 2 и 4.

## Scope-guard (KAC-108 MVP)

- LISTEN-invalidate (`kacho_iam_subjects`) НЕ wired; revoke ≤10s достигается
  за счёт TTL=5s + outbox-drain ≤2s.
- Для `Update/Delete/<verb>` НЕ резолвим `project_id` через secondary DB-lookup
  — checking на `vpc_network:<id>` напрямую через FGA-cascade `editor on
  vpc_network ← editor on project`.

## Imports

- `github.com/PRO-Robotech/kacho-corelib/authz` — port `CheckClient`,
  `Interceptor`, `RPCMap`, `Cache`, `StaticExtractor`.
- `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/iam/v1` —
  `InternalIAMServiceClient`, `CheckRequest`.
- `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/vpc/v1` (+ `privatelink`) — request stubs для extractor'ов.
- `github.com/PRO-Robotech/kacho-proto/gen/go/kacho/cloud/operation` — `OperationService` request stubs.

## See also

[[corelib-authz]] [[../edges/vpc-to-iam-check]] [[../KAC/KAC-108]]

#packages #kacho-vpc #authz #composition-root #e3
