---
title: "vpc → iam: project existence check (replaces folder_id check)"
aliases:
  - vpc to iam project check
  - project_id validate
category: edge
caller_repo: kacho-vpc
callee_repo: kacho-iam
sync_async: async
protocol: grpc-cluster-internal
status: active
related_tickets:
  - "[[KAC-104]]"
  - "[[KAC-106]]"
tags:
  - edge
  - kacho-vpc
  - kacho-iam
  - cross-service
---

> [!success] Active since 2026-05-17 (KAC-106 E1)
> Edge активен; kacho-vpc зовёт `kacho-iam.ProjectService.Get` для валидации `project_id` на request-path. Replaces deprecated [[vpc-to-rm-folder-exists]]. См. [[KAC/KAC-106]].

# vpc → iam: project existence check

**Caller**: `kacho-vpc` (`internal/clients/iam_client.go` — переименован из клиента снятого домена управления ресурсами в KAC-106)
**Callee**: `kacho-iam.ProjectService.Get` (mapped к "Exists" сценарию через NotFound)
**Protocol**: gRPC service→service (:9090, не через api-gateway)
**Sync/Async**: сам вызов **синхронный**, но исполняется внутри Operation-worker'а, поэтому
снаружи мутация остаётся асинхронной. «async» в шапке означает именно это, а не отложенную
проверку: попытка создать ресурс в несуществующем проекте завершается ошибкой операции, а не
успехом с последующей уборкой.

## When invoked

- На request-path: `Network.Create`, `Subnet.Create`, `Address.Create`, любая мутация, принимающая `project_id` — внутри Operation worker'а, после возврата proto-`Operation`.
- При `Move` (cross-project).

## Как устроено (сверено с деревом 2026-08-05)

- Клиент — `services/vpc/internal/clients/iam_client.go`, тип `ProjectClient` поверх
  `iamv1.ProjectServiceClient`. Импорт идёт из **`pkg/api/kacho/cloud/iam/v1`** одного
  монорепо; прежний пример показывал путь полирепо-эпохи (`kacho-proto/gen/go/...`), который
  не резолвится и вводит в заблуждение при копировании.
- **Кэш живёт в декораторе**, а не в клиенте: `project_cache.go` (`CachedProjectClient`,
  ограниченный TTL+LRU) оборачивает голый клиент в композиционном корне. Сам `ProjectClient` —
  чистый проброс с per-call дедлайном и `retry.OnUnavailable`.
- **Личность вызывающего пробрасывается обязательно** (`auth.PropagateOutgoing`). Публичный
  `ProjectService.Get` у iam несёт tenant-фильтр и отвечает «нет такого» тому, кто проектом
  не владеет; без проброса пир увидел бы анонимный вызов и проверка существования падала бы
  на **законном** проекте.
- **`INVALID_ARGUMENT` от iam трактуется как «нет»**: iam валидирует форму id, и мусорный id
  иначе вернулся бы вызывающему транспортным текстом вместо конвенционного отказа.

> [!warning] Текст отказа переписан — прежний называл чужой продукт и снятую сущность
> Здесь стояло: `NotFound "Folder with id <id> not found"` с обоснованием «оставлен для
> verbatim YC parity». Оба довода мертвы: сущности `Folder` в продукте нет (её место занял
> `Project`), а сравнение с чужим облаком как обоснование — прямой запрет ядра (#2).
> В дереве текст — `NotFound "Project %s not found"` (`api/*/create.go`, семь мест).

## Что происходит при отказе

| Исход | Что видит вызывающий | Замечание |
|---|---|---|
| проект есть | продолжение мутации | положительный ответ кэшируется на короткий срок |
| проекта нет / id мусорный | `NOT_FOUND "Project %s not found"` | текст — часть контракта |
| iam недоступен | `UNAVAILABLE "project check: <err>"` | fail-closed на мутации; повтор через `retry.OnUnavailable` |

> [!note] Расхождение с by-lane split — названо как наблюдение, а не выдано за норму
> По `api-conventions.md` промах **чужого** ресурса на полосе peer-validate должен отвечать
> `FAILED_PRECONDITION` с машинным токеном `PEER_RESOURCE_MISSING`, а `NOT_FOUND` остаётся за
> собственной полосой. vpc отвечает `NOT_FOUND`. Машинный дискриминатор полосы в дереве
> реализован **только у nlb** (`internal/apps/kacho/api/loadbalancer/peer_errors.go`; предикат:
> `git grep -l PEER_RESOURCE_MISSING` по не-тестовому Go → 1 файл). Клиенту, которому надо
> различать полосы у vpc, сегодня опереться не на что — кроме текста сообщения, а текст
> парсить нельзя.

## Configuration

```yaml
# kacho-vpc deploy/values.yaml — посадка показана production-ной намеренно
extapi:
  iam:
    endpoint: "kacho-iam.kacho.svc.cluster.local:9090"   # задаётся ЯВНО в каждом профиле
    tls:
      enable: true    # на любом развёрнутом стенде — обязательно
```

> [!note] Почему пример показан с включённым транспортом
> Пример конфигурации — это то, что копируют. Прежняя редакция показывала `enable: false`;
> образец с выключенным транспортом учит небезопасной посадке там, где человек не выбирает,
> а берёт готовое (`security.md` §«Production-mode ОБЯЗАТЕЛЕН ВЕЗДЕ»). Тот же довод уже
> применён к соседнему ребру [[vpc-to-iam-check]].
>
> Отдельно снято: абзац про `GetCloudIDFromProject` («read `Project.account_id`, используется
> в IPAM cascade»). Такой функции у клиента нет (`grep GetCloudIDFromProject
> services/vpc/internal/clients/iam_client.go` → пусто), и «cloud_id» — словарь снятого
> домена.

**CLIENT mTLS (SEC-I)**: `iamConn` (this ProjectService.Get edge, :9090) presents the
`kacho-vpc-client-tls` client-cert when `KACHO_VPC_IAM_PROJECT_MTLS_ENABLE=true` —
config field `MTLSConfig.IAMProjectMTLS` + helper `IAMProjectClientCreds()` (mirror of
the register-drainer `IAMRegisterMTLS`). `enable=false` → insecure (dev, zero regression).
ServerName = `kacho-iam.kacho.svc.cluster.local` (:9090 SAN, **distinct** from the :9091
Check/Register dial-host — I6). Helm: `mtls.edges.iamProject` reuses the already-mounted
`kacho-vpc-client-tls` volume (no new secret). Required before kacho-iam runs
`RequireAndVerifyClientCert` (SEC-H), else the TLS handshake fails → `Unavailable`.

## History

- **2026-05-17 (KAC-106 E1)**: edge created; replaces vpc→rm folder check ([[vpc-to-rm-folder-exists]] deprecated).
- Клиент снятого домена управления ресурсами переименован в `iam_client.go`, тип владельца
  области — в `ProjectClient`; форма кэша (ограниченный TTL+LRU) сохранена. Прежнее имя файла
  здесь не воспроизводится в кавычках — в дереве его нет.
- **2026-06-12 (SEC-I)**: `iamConn` dial gained CLIENT mTLS — `MTLSConfig.IAMProjectMTLS` (env `KACHO_VPC_IAM_PROJECT_MTLS_*`) + helper `IAMProjectClientCreds()`, wired in `cmd/vpc/main.go` (enable=true → `grpc.NewClient` with client-cert; enable=false → insecure clients.Build). Helm `mtls.edges.iamProject` reuses `kacho-vpc-client-tls`. Transport-only; contract unchanged.

## See also

[[../rpc/iam-project-service]] [[../resources/iam-project]] [[vpc-to-rm-folder-exists]] [[../KAC/KAC-104]] [[../KAC/KAC-106|KAC-106 (E1)]]

#edge #kacho-vpc #kacho-iam #cross-service
