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
status: stable
verified_against: "каталог пакета есть в дереве продукта b4edc5d5 (2026-08-05); текст записки построчно не пересматривался"
---

# pkg/auth — передача личности вызывающего соседнему сервису

**Каталог**: `pkg/auth/` · импорт `github.com/PRO-Robotech/kacho/pkg/auth`
**Прежде** (полирепо): `kacho-corelib/auth`.
**Импортирует**: `context`, `google.golang.org/grpc/metadata`, `pkg/grpcsrv`
(реэкспорт ключей метаданных), `pkg/operations` (тип личности).
**Импортируют** (`go list` на `96b2879a`, non-test) — **17 пакетов в шести
сервисах**: nlb 5 (клиенты к compute/geo/iam/vpc + фильтр видимости) · storage 3 ·
registry 3 · compute 3 · vpc 2 · geo 1. Прежняя редакция называла vpc и compute
живыми, а iam и nlb — «планируемыми»; nlb сегодня крупнейший потребитель.

Пакет закрывает находку из [[../KAC/KAC-127]]: межсервисная проверка прав видела
служебного субъекта вместо настоящего вызывающего.

## Экспортируемое API (снято с дерева) — две функции и три константы

```go
func PropagateOutgoing(ctx context.Context) context.Context
func SystemPrincipalFor(service, role string) operations.Principal

const (
    MDKeyPrincipalType    = grpcsrv.MDKeyPrincipalType
    MDKeyPrincipalID      = grpcsrv.MDKeyPrincipalID
    MDKeyPrincipalDisplay = grpcsrv.MDKeyPrincipalDisplay   // третья, о ней записка молчала
)
```

`PropagateOutgoing` собирает исходящий контекст, копируя личность из входящих
метаданных либо из контекста; если личности нет — проходит насквозь.
`SystemPrincipalFor` даёт синтетическую личность внутреннего вызывающего (воркер,
дренаж), и её форма подобрана так, чтобы пережить нормализацию субъекта на стороне
модели прав, — это проверяется отдельной пробой, а не подразумевается.

> [!note] Фундамент не импортирует сгенерённые стабы
> Пакет работает со стандартной библиотекой и метаданными gRPC. Серверная сторона —
> чтение личности из входящих метаданных — живёт в [[corelib-grpcsrv]].

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

## Где подключён (по дереву, `96b2879a`)

Два устойчивых места на сервис, и это ровно те два, где личность обязана доехать:

- **слой проверки прав** — `internal/check` (compute, geo, registry, storage, nlb)
  и одноимённый пакет у vpc: адаптер к внутреннему RPC проверки;
- **клиенты к соседям** — `internal/clients` (compute, storage, vpc) и пофасадные
  клиенты nlb (к compute, geo, iam, vpc) и registry (к geo, iam);
- **фильтр видимости** (`internal/authzfilter` у compute, nlb, storage) — страница
  проверяется под личностью вызывающего, а не под служебной.

> [!warning] Здесь стояли три пути к файлам, которых нет
> Прежняя редакция называла поимённо файлы клиентов vpc и compute, включая клиент к
> compute «за зоной». Такого ребра больше нет вовсе: зону валидирует geo
> (`polyrepo.md` §runtime-edges), а раскладка клиентов сменилась. Мёртвые пути здесь
> не воспроизводятся: цитата пути читается как живое утверждение о дереве. Перечень
> выше — по свойству (какой слой), а не по строке файла, поэтому он переживает
> переименование.

## Инвариант доверия: личность едет только от того, кому позволено за неё говорить

См. предупреждение выше в этой записке и — как канон — `security.md`
§«AuthN+AuthZ ВЕЗДЕ», п. 5. Здесь важно одно следствие для **клиентской** стороны:
`PropagateOutgoing` прикрепляет личность к **любому** исходящему вызову, а решение
о том, принимать ли её, целиком на принимающей стороне. То есть безопасность этого
механизма держится не здесь, а на паре извлечения и непустом круге отправителей у
адресата.

## См. также

[[../edges/vpc-to-iam-check]] [[../edges/compute-to-iam-check]] [[corelib-grpcsrv]]
[[corelib-operations]] [[../KAC/KAC-140]] [[../KAC/KAC-127]]

#packages #kacho-corelib #auth #cross-service
