---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.ServiceAccountService/Create
  - rpc: kacho.cloud.iam.v1.ServiceAccountService/Delete
  - rpc: kacho.cloud.iam.v1.ServiceAccountService/Get
  - rpc: kacho.cloud.iam.v1.ServiceAccountService/List
  - rpc: kacho.cloud.iam.v1.ServiceAccountService/ListOperations
  - rpc: kacho.cloud.iam.v1.ServiceAccountService/Update
  - rpc: kacho.cloud.iam.v1.SAKeyService/Issue
  - rpc: kacho.cloud.iam.v1.SAKeyService/List
  - rpc: kacho.cloud.iam.v1.SAKeyService/Revoke
status: implemented
source_sha: ""
---

# Service accounts

Workload-identity: `ServiceAccount` (не-человеческий принципал для приложений,
CI-агентов, контроллеров) и его static-credentials (`SAKeyService`).

## Зачем

ServiceAccount даёт identity процессу, а не человеку: на него вешаются
access-bindings, его можно класть в группы. Сама по себе SA — identity-stub без
credentials; чтобы «логиниться», SA нужен OAuth-client / key, который выдаёт
`SAKeyService`. Это путь Class A (static client_credentials) — в отличие от
federation-exchange (динамические внешние токены).

## Контракт

- `ServiceAccountService` (public): `Get` / `List` / `ListOperations` — sync;
  `Create` / `Update` / `Delete` — async (`Operation`). `List` требует
  `account_id`-фильтр.
- `SAKeyService` (public): `Issue` — выдать credential (client_id +
  client_secret, secret показывается **один раз**); `List` — метаданные
  credential'ов (без secret); `Revoke` — отозвать.

## Lifecycle

- `Create` SA — `account_id` обязателен и immutable.
- `Issue` key — INSERT credential-row + регистрация OAuth-client во внешнем
  authorization-server; возвращает secret one-time.
- `Revoke` — отзыв credential'а; downstream-инвалидация активных токенов идёт
  через CAEP-push (см. break-glass / federation tracks).
- `Delete` SA — async; SA с активной GroupMember/AccessBinding блокируется
  sentinel'ом `FailedPrecondition` в service-слое.

## Gotchas

- 1:1 SA ↔ OAuth-client фиксируется UNIQUE на `service_account_id`.
- client_secret хранится только хэшем на стороне authorization-server; kacho-iam
  держит лишь метаданные.
- Rotation — soft: новый secret валиден сразу, старый доживает grace-период
  (для безшовного CI/CD).

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-service-accounts]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
