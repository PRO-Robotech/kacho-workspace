---
title: "vpc → iam: per-RPC OpenFGA Check (E3)"
aliases:
  - vpc to iam check
  - vpc authz check
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: sync
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-vpc
  - kacho-iam
  - cross-service
  - authz
  - e3
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
---

> [!success] Active since 2026-05-17 (KAC-108 E3, kacho-vpc PR#101)
> Edge активен; kacho-vpc на КАЖДОМ публичном RPC синхронно вызывает
> `kacho-iam.InternalIAMService.Check(subject, relation, object)` через
> `internal/apps/kacho/check/`-interceptor. Кеш positive=5s; revoke ≤10s
> через TTL + outbox-drain.

# vpc → iam: per-RPC Check (E3)

**Caller:** `kacho-vpc` (`internal/apps/kacho/check/` — gRPC unary+stream interceptor поверх corelib `authz`).
**Callee:** `kacho-iam.InternalIAMService.Check` (port 9091).
**Protocol:** gRPC cluster-internal (direct dial; не через api-gateway).
**Sync/Async:** **sync** (на каждом public RPC, до вызова handler'а).

## When invoked

- На каждом публичном RPC kacho-vpc: NetworkService, SubnetService,
  AddressService, RouteTableService, SecurityGroupService, GatewayService,
  NetworkInterfaceService, OperationService.Get/Cancel
  (см. [[../packages/vpc-apps-kacho-check]] permission_map).
- `Internal*` RPC — **не** bypass: внутренний листенер несёт свой гейт
  (`security.md` §AuthN+AuthZ ВЕЗДЕ п.2 — «internal = trusted» запрещённое допущение).
  Прежняя редакция называла это bypass'ом со ссылкой на ban #6; ban #6 — про **поверхность
  методов** (Internal не публикуется наружу), а не про освобождение от проверки.

> [!note] Снято две вещи, которых нет в дереве (сверено 2026-08-05)
> — **`PrivateEndpointService` / тип `vpc_private_endpoint`**: во всём монорепо ноль
> вхождений `private_endpoint` (предикат: `git grep -il private_endpoint` → 0). Ресурса нет.
> — **«На каждый stream RPC (Watch / Subscribe)»**: у vpc нет ни одного стримового RPC
> (`grep "stream " proto/kacho/cloud/vpc/v1/*.proto` → пусто), и Watch как механизм в
> продукте не существует вовсе (`api-conventions.md`: полл списка либо `Operation.Get`).
> Строка описывала защиту поверхности, которой нет, — то есть выглядела как покрытие.

## Object types

`vpc_network`, `vpc_subnet`, `vpc_address`, `vpc_route_table`,
`vpc_security_group`, `vpc_gateway`, `vpc_network_interface`, `vpc_operation`, `project`
(источник — константы `objectType*` в `internal/apps/kacho/check/permission_map.go`).

## Cache

- Positive-only TTL 5s (corelib/authz `Cache`).
- `pg_notify('kacho_iam_subjects', subject_id)` → `InvalidateBySubject`
  (НЕ wired в текущем MVP — KAC-108 follow-up).
- Worst-case revoke: TTL=5s + NOTIFY≤1s + outbox-drain≤2s ≤ 10s (acceptance NFR-5).

## Error handling

| Result | gRPC code | Note |
|---|---|---|
| allowed=true | (continue handler) | cache positive 5s |
| allowed=false | `PermissionDenied "permission denied"` | not cached |
| iam недоступен | `PermissionDenied "authorization service unavailable"` | **fail-closed** (acceptance D-6) |
| no Principal в ctx | `PermissionDenied` | защита от misconfig auth-interceptor (E2) |
| Unmapped RPC | `PermissionDenied "permission denied (rpc not mapped)"` | drift-guard |
| Internal* RPC | bypass | heuristic — public listener не маршрутизирует Internal'ы |

## Break-glass

В группе `authz.*` есть аварийный override, снимающий per-RPC Check со **всех** RPC сразу
(сопровождается WARN-метрикой). Он существует ради восстановления, когда iam недоступен, и
на этом его область заканчивается.

> [!warning] Включённый override — не «режим», а отказ в старте
> Это ручка, отключающая авторизацию целиком, поэтому она подпадает под
> `security.md` §Production-mode п.1 наравне с `sslmode=disable` и снятым mTLS: на любом
> РАЗВЁРНУТОМ стенде (kind/CI/local/prod) production boot-guard обязан **отказывать в
> старте**, пока она включена, а не ограничиваться предупреждением. Причина ровно та, из-за
> которой этот класс вообще ловят: предупреждение в логе никого не будит, а «WARN есть,
> сервис работает» неотличимо от нормы. Допустимая область — только in-process
> unit/integration-фикстуры. Сообщение отказа при старте обязано называть ручку и причину
> (это рантайм-диагностика оператору, а не публичный артефакт).

## Configuration

```yaml
# values.yaml (kacho-vpc) — форма ключей; посадка показана production-ной намеренно
authz:
  iam-endpoint: kacho-iam-internal.kacho.svc.cluster.local:9091  # задаётся ЯВНО в каждом профиле
  iam-tls:
    enable: true        # mTLS обязателен на любом развёрнутом стенде
  breakglass: false     # включённый override ⇒ отказ в старте (см. §Break-glass)
  cache-ttl: 5s
  check-timeout: 2s
  deny-rate-limit-per-sec: 100
```

> [!note] Почему пример показан в production-посадке
> Пример конфигурации — это то, что копируют. Образец с выключенным транспортом и
> подразумеваемым адресом учит небезопасной посадке ровно там, где человек не выбирает
> осознанно, а берёт готовое. Инвариант — `security.md` §«Production-mode ОБЯЗАТЕЛЕН ВЕЗДЕ,
> включая dev/локальный стенд».

> [!warning] Незаданный адрес iam снимает интерцептор — это НЕ «мягкая деградация»
> Если адрес iam пуст, интерцептор не навешивается вовсе: сервис поднимается **без**
> per-RPC Check. Опасность здесь не в самом послаблении, а в том, что его причина —
> **отсутствие настройки**, то есть состояние, которое ни один профиль не обязан задавать,
> чтобы получить. Контроль при этом выглядит существующим (код есть, ветка есть), но не
> отказывает ни разу за всю жизнь стенда. Это `security.md` §9 («адрес зависимости, от
> которой зависит решение о доступе, не выводится и не подразумевается») и §8 («мягкий проход
> обязан отличать настройку от сбоя»).
>
> Требование: адрес задаётся **явно** в каждом профиле, где сервис поднимается, а production
> boot-guard **отказывает в старте**, когда гейт объявлен, но его зависимость не
> сконфигурирована. Проверяется декларативным тестом, читающим файлы значений (а не
> отрендеренный шаблон — иначе тест пропускается вместе с шаблоном). Ноль срабатываний гейта
> за всю жизнь — повод для разбора, а не признак здоровья.
>
> **Требование выполнено (сверено 2026-08-05):** `internal/apps/kacho/config/validate.go`
> держит отказы старта в production-режиме на всех трёх ручках — пустой адрес iam, пустой
> адрес фильтра списков, включённый аварийный обход, и отдельно на неверифицированном
> транспорте ребра. Тексты отказов называют ручку и причину — это рантайм-диагностика
> оператору, и она намеренно не выхолащивается.

**CLIENT mTLS (SEC-I)**: the `authzConn` dial (this Check edge, :9091) — **shared** by
the per-RPC gate AND the project-level list-filter ([[vpc-to-iam-listobjects]] /
`newListAuthz`, ONE conn) — presents the `kacho-vpc-client-tls` client-cert when
`KACHO_VPC_IAM_AUTHZ_MTLS_ENABLE=true`. Config field `MTLSConfig.IAMAuthzMTLS` + helper
`IAMAuthzClientCreds()` (mirror of register-drainer). ServerName =
`kacho-iam-internal.kacho.svc.cluster.local` (:9091 SAN, I6). Helm: `mtls.edges.iamAuthz`
reuses the mounted client secret. Required before kacho-iam runs `RequireAndVerifyClientCert`
(SEC-H), else the handshake fails → `Check` returns `Unavailable`/fail-closed
(B-05 completeness — **no iam read/authz edge may stay plaintext**).

> [!warning] По этому ребру ходят РЕШЕНИЯ О ДОСТУПЕ — включатель здесь переходный
> Тот же conn несёт и per-RPC gate, и list-filter, поэтому неаутентифицированный собеседник
> на нём — это не «незашифрованный транспорт», а возможность влиять на исход авторизации.
> Per-edge включатель введён ради поэтапной раскатки PKI и остаётся **переходной формой**:
> на любом развёрнутом стенде mTLS обязателен, а production boot-guard обязан отказывать в
> старте, если ребро живое и не защищено (`security.md` §AuthN+AuthZ ВЕЗДЕ п.1 +
> §Production-mode п.1). «Internal = trusted, сеть закрытая» — прямо запрещённое допущение.

## History

- **2026-06-12 (SEC-I)**: `authzConn` dial gained CLIENT mTLS — `MTLSConfig.IAMAuthzMTLS`
  (env `KACHO_VPC_IAM_AUTHZ_MTLS_*`) + helper `IAMAuthzClientCreds()`, wired in
  `cmd/vpc/main.go`. ONE conn covers per-RPC Check + list-filter (OQ-2). Helm
  `mtls.edges.iamAuthz` reuses `kacho-vpc-client-tls`; ServerName=`kacho-iam-internal`
  (:9091). Transport-only; contract / FGA logic unchanged.
- **2026-05-24** (W1.4, [[../KAC/KAC-140]]): principal propagated через
  `auth.PropagateOutgoing` — iam Check теперь видит caller Principal, не
  `user:bootstrap`. Closes round-3 finding из [[../KAC/KAC-127]].
- 2026-05-17 (E3, [[../KAC/KAC-108]]): edge initial, kacho-vpc PR#101.

## See also

[[../packages/vpc-apps-kacho-check]] [[../packages/corelib-authz]] [[../packages/corelib-auth]] [[iam-to-openfga-check]] [[compute-to-iam-check]] [[../KAC/KAC-108]] [[../KAC/KAC-122]] (authz-deny newman suite) [[../KAC/KAC-140]]

#edge #kacho-vpc #kacho-iam #cross-service #authz #e3
