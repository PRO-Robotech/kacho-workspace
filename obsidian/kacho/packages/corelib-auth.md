---
title: "kacho-corelib/auth"
aliases:
  - corelib auth
  - principal propagation
category: packages
repo: kacho-corelib
layer: corelib
tags:
  - packages
  - kacho-corelib
  - auth
  - cross-service
---

# kacho-corelib/auth

Helper-пакет для **principal propagation сервис→сервис** через gRPC outgoing
metadata. Закрывает [[../KAC/KAC-127]] round-3 finding: cross-service Check видел
`user:bootstrap` вместо реального caller'а.

**Layer:** corelib (shared across kacho-vpc / kacho-compute; planned: kacho-iam /
kacho-loadbalancer для peer-calls).

## API

```go
// PropagateOutgoing создаёт outgoing-context, копируя x-kacho-principal-id /
// x-kacho-principal-type из incoming MD (или из operations.PrincipalFromContext).
// Если principal нет в ctx — passthrough, иначе attach MD.
func PropagateOutgoing(ctx context.Context) context.Context

// SystemPrincipalFor возвращает синтетический Principal для internal
// system-callers (workers, drainers). service: "kacho-iam", role: "drainer".
func SystemPrincipalFor(service, role string) operations.Principal

// MD-key constants — re-exported из corelib/grpcsrv для удобства callers,
// чтобы не импортировать grpcsrv ради 2 строк.
const (
    MDKeyPrincipalID   = grpcsrv.MDKeyPrincipalID
    MDKeyPrincipalType = grpcsrv.MDKeyPrincipalType
)
```

## Imports

- stdlib (`context`)
- `github.com/PRO-Robotech/kacho-corelib/grpcsrv` (re-export MD-keys)
- `github.com/PRO-Robotech/kacho-corelib/operations` (PrincipalFromContext)
- `google.golang.org/grpc/metadata`

> [!note] Decoupling
> corelib НЕ импортирует kacho-proto stubs — helper работает только с stdlib
> и grpc/metadata. Adapter, который читает Principal из incoming MD (server-side),
> живёт в `corelib/grpcsrv`.

> [!important] Инвариант доверия principal ⟺ mTLS (FD-4) — необходим, но НЕ достаточен
> principal-metadata (`x-kacho-principal-*`) доверяется **только если** peer прошёл mTLS
> client-cert verify (`grpcsrv.UnaryTrustedPrincipalExtract` / `TrustedPrincipalFromContext`).
> cert-identity (модуль, из SAN `spiffe://kacho.cloud/...`, `grpcsrv.CertIdentity`) и principal
> (пользователь, из MD) — **ортогональны**, оба логируются для аудита, не подменяют друг друга.
> Резолв cert-identity → ServiceAccount — SEC-C.
>
> **Одной этой проверки мало**: она отвечает «сертификат наш», а не «этому пиру можно говорить
> за пользователя». Ко второму вопросу нужен непустой allow-list форвардеров плюс boot-guard,
> отказывающий в старте без него — полный разбор и все четыре обязательные части живут в
> [[corelib-grpcsrv]] (владелец темы, здесь не дублируем). Insecure-транспорт (`enable=false`)
> — фикстурный режим, не эксплуатационный: на развёрнутом стенде posture всегда production
> (core rule #16).

## Imported by

- kacho-vpc — `internal/apps/kacho/check/check_client.go` (IAM Check),
  `internal/apps/kacho/iam/iam_client.go` (project lookup),
  `internal/apps/kacho/compute/compute_client.go` (zone lookup).
- kacho-compute — `internal/check/check_client.go` (IAM Check),
  `internal/clients/vpc_client.go` (14 peer-call sites: Subnet/SG/NIC/Address).

Planned: kacho-iam (self-check + role-resolver peer-calls), kacho-loadbalancer
(когда подключится к E3 authz, KAC-108 follow-up).

## Tests

`auth_test.go` — 6 unit tests:
- `PropagateOutgoing_NoPrincipal_PassthroughEmpty`
- `PropagateOutgoing_FromIncoming_AttachesBoth`
- `PropagateOutgoing_FromContextPrincipal_AttachesBoth`
- `PropagateOutgoing_PreservesExistingOutgoing`
- `SystemPrincipalFor_DefaultsType`
- `SystemPrincipalFor_PopulatesID`

## See also

[[../edges/vpc-to-iam-check]] [[../edges/compute-to-iam-check]] [[corelib-grpcsrv]] [[../KAC/KAC-140]] [[../KAC/KAC-127]]

#packages #kacho-corelib #auth #cross-service
