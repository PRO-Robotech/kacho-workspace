---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.UserService/Delete
  - rpc: kacho.cloud.iam.v1.UserService/Get
  - rpc: kacho.cloud.iam.v1.UserService/Invite
  - rpc: kacho.cloud.iam.v1.UserService/List
  - rpc: kacho.cloud.iam.v1.InternalUserService/Get
  - rpc: kacho.cloud.iam.v1.InternalUserService/OnRecoveryCompleted
  - rpc: kacho.cloud.iam.v1.InternalUserService/UpsertFromIdentity
status: implemented
source_sha: ""
---

# User management

Управление человеческими identity. `User` — **зеркало** внешнего IdP: запись
создаётся/обновляется только через `InternalUserService` (OIDC-callback), а
публичный `UserService` отдаёт read-only справочник и приглашения.

## Зачем

Источник истины для пользователя — внешний IdP (OIDC `sub`). kacho-iam держит
локальную проекцию (`external_id` UNIQUE), чтобы ссылаться на пользователя из
account-owner / group-member / access-binding. Локальный edit `email` /
`displayName` не предусмотрен — атрибуты приходят из IdP.

## Контракт

- `UserService` (public, 9090): `Get` / `List` — sync read; `Invite` —
  приглашение нового пользователя; `Delete` — async (`Operation`).
- `InternalUserService` (internal, 9091 — §Запрет #6): `Get` — sync;
  `UpsertFromIdentity` — async upsert из identity-claims (вызывается
  OIDC-callback handler'ом api-gateway); `OnRecoveryCompleted` — хук завершения
  account-recovery flow.

## Lifecycle

- Создание User — **только** `UpsertFromIdentity`: key `external_id` (IdP `sub`),
  есть row → UPDATE `email`/`display_name`, нет → INSERT с `ids.NewID("usr")`.
  Upsert атомарен по UNIQUE `external_id` — CAS не нужен.
- `Invite` — публичный путь приглашения; материализация User по-прежнему через
  upsert после первого логина.
- `Delete` — async; admin-only; заблокирован `FailedPrecondition`, если user
  владеет аккаунтами (`accounts_owner_fk` RESTRICT).

## Gotchas

- Нет `Create` / `Update` в public `UserService` — by-design: write-path только
  internal.
- GroupMember и AccessBinding на user — soft-ref (cross-DB, без FK), delete
  блокируется sentinel'ом в service-слое, не БД.
- `InternalUserService` не должен светиться на external TLS (newman-кейс
  `iam-internal-only-check` это проверяет).

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-user-management]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
