---
title: "kacho-compute/internal/check"
aliases:
  - compute check package
  - compute authz interceptor
category: packages
path: services/compute/internal/check
repo: kacho-compute
layer: composition
tags:
  - packages
  - kacho-compute
  - authz
  - composition-root
  - e3
status: stable
verified_against: "координаты пакета сверены с деревом продукта 1653387b (2026-08-06): имена переменных окружения authz/mTLS против кода и чарта; перечень файлов и семантика карты прав построчно не пересматривались"
---

# kacho-compute/internal/check

Composition-root пакет — обёртка corelib `authz`-interceptor под kacho-compute:
permission map + IAM client adapter + factory.

**Layer:** composition (импортирует corelib + proto-stubs).

## Файлы

- `doc.go` — overview.
- `permission_map.go` — `PermissionMap()` возвращает `authz.RPCMap` со всеми
  публичными RPC kacho-compute (40+ записей): Disk / Image / Snapshot /
  Instance (lifecycle-heavy: Start/Stop/Restart/Attach*/Detach*/AddOneToOneNat/…) /
  DiskType / Zone / Region + Operation.
- `check_client.go` — `IAMCheckClient` (gRPC adapter поверх
  `iamv1.InternalIAMServiceClient.Check`).
- `factory.go` — `NewInterceptor(Options) (*authz.Interceptor, error)`.
- `interceptor_test.go` — 11 unit-тестов (allow/deny/unavailable/no-principal/
  unmapped/internal-bypass/cache-hit/breakglass + system-catalog routing + factory).

## Семантика permission map

- `Create / List`               → `editor / viewer` на `project:<project_id>`.
- `Update / Delete / Start / Stop / Restart / Attach*/Detach*/<verb>`
                                → `editor` на `<resource_type>:<resource_id>`.
- `DiskType.Get/List`, `Zone.Get/List`, `Region.Get/List`
                                → `viewer` на `system:catalog` — отношение, выполнимое
  подстановочным tuple'ом, т.е. фактически «аутентифицирован», а не «авторизован».

  > [!warning] Эта полоса законна ТОЛЬКО для глобального справочника
  > `viewer` на кластерном объекте выполняется wildcard-tuple'ом, поэтому отвечает «да»
  > **каждому** аутентифицированному субъекту. Для типов дисков / зон / регионов это и
  > есть цель: admin-curated ось размещения, которую обязан читать любой тенант, иначе он
  > не сможет создать ни один размещаемый ресурс. Для всего остального такая запись —
  > гейт без содержания: форма проверки есть, сужения нет, и в диффе она неотличима от
  > настоящей. Перед тем как поставить cluster-scoped отношение новому RPC, спроси, какие
  > tuple его выполняют; если ответ «в том числе wildcard», а ответ RPC справочником не
  > является — авторизуй на уровне данных (страница курсором + batch-check её id),
  > а не одним вопросом. См. `security.md` §«Отношение, выполнимое подстановочным знаком».
- `OperationService.Get/Cancel` → `viewer / editor` на `compute_operation:<id>`.
- `Internal*` RPC — **тоже в карте**; пропуск Check выдаётся записью
  (`Public=false`/`ScopeFiltered`), а не выводится из имени метода. Незамапленный RPC
  отказывает (см. [[corelib-authz]] §Decision pipeline).

## Object types

`compute_disk`, `compute_image`, `compute_snapshot`, `compute_instance`,
`compute_operation`, `system`, `project`.

## Wiring

```go
// cmd/compute/main.go
authzIntr, err := check.NewInterceptor(check.Options{
    ServiceName: "kacho-compute",
    IAMConn:     authzConn,   // gRPC к kacho-iam:9091
    Breakglass:  cfg.AuthZBreakglass,
    Logger:      logger,
})
if authzIntr != nil {
    publicUnary = append(publicUnary, authzIntr.Unary())
    publicStream = append(publicStream, authzIntr.Stream())
}
```

Internal-листенер собирается **той же** цепочкой, что публичный: `authzIntr` навешивается
на ОБА.

> [!important] «Internal = trusted, mTLS достаточно» — запрещённое допущение
> mTLS доказывает ровно одно: пир предъявил сертификат нашего CA. Он не говорит, **кто**
> вызывающий и **на что** у него право, поэтому сам по себе не заменяет per-RPC Check.
> Ban #6 сужает **поверхность методов**, а не снимает проверку прав на внутреннем порту.
> См. `security.md` §«AuthN+AuthZ ВЕЗДЕ», п. 2 и 4, и [[corelib-authz]].

## Config

- `KACHO_COMPUTE_AUTHZ_IAM_GRPC_ADDR` (default `""` → graceful skip)
- `KACHO_COMPUTE_IAM_AUTHZ_MTLS_ENABLE` и его семья — `..._CERTFILE`, `..._KEYFILE`,
  `..._CAFILES`, `..._SERVERNAME`: client-creds ребра compute→iam для per-RPC Check.
  Приезжают из поля `IAMAuthzMTLS` (`envconfig:"IAM_AUTHZ_MTLS"` под префиксом сервиса),
  провязаны в чарте (`services/compute/deploy/templates/deployment.yaml`).
- `KACHO_COMPUTE_AUTHZ_BREAKGLASS` — аварийный обход Check целиком. В production-режимах
  `Config.Validate()` **отказывает в старте**: ручка, снимающая контроль, обязана быть
  недостижима на развёрнутом стенде, иначе «мы ею не пользуемся» нечем проверить.

> [!warning] Имя mTLS-ручки в прежней редакции не существовало — а по нему не видно, что она mTLS
> Записка называла одиночную переменную с порядком слов «AUTHZ_IAM» и хвостом «TLS». В
> дереве её нет ни в коде, ни в чарте (перепись по `*.go`/`*.yaml`/`*.tpl`/`*.sh`).
> Действующее имя переставляет половины — «IAM_AUTHZ» — и это **семья** из пяти
> переменных, а не одна, потому что взаимная аутентификация требует собственных
> сертификата и ключа, а не одного флага.
>
> Почему это не опечатка по последствиям: перепутанный порядок половин даёт имя, которое
> **выглядит** правдоподобно рядом с соседней строкой (адрес iam-а как раз «AUTHZ_IAM»),
> поэтому в профиле развёртывания такая переменная тихо не читается никем — окружение её
> просто не узнаёт. Проверять надо не «переменная задана», а «сервис при старте объявил
> ту посадку, которую мы задали»: посадка, объявленная процессом, и есть предмет гейта
> (`security.md` §«Production-mode обязателен ВЕЗДЕ», п. 2а).

## Scope-guard (KAC-108 MVP)

- LISTEN-invalidate `kacho_iam_subjects` НЕ wired; revoke ≤10s = TTL=5s + outbox-drain ≤2s.

## Imports

- `github.com/PRO-Robotech/kacho-corelib/authz`
- `github.com/PRO-Robotech/github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/iam/v1` (InternalIAMServiceClient).
- `github.com/PRO-Robotech/github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/compute/v1` (request stubs).
- `github.com/PRO-Robotech/github.com/PRO-Robotech/kacho/pkg/api/kacho/cloud/operation`.

## See also

[[corelib-authz]] [[vpc-apps-kacho-check]] [[../edges/compute-to-iam-check]] [[../KAC/KAC-108]]

#packages #kacho-compute #authz #composition-root #e3
