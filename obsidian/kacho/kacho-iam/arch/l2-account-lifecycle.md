---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.AccountService/Create
  - rpc: kacho.cloud.iam.v1.AccountService/Delete
  - rpc: kacho.cloud.iam.v1.AccountService/Get
  - rpc: kacho.cloud.iam.v1.AccountService/List
  - rpc: kacho.cloud.iam.v1.AccountService/ListOperations
  - rpc: kacho.cloud.iam.v1.AccountService/Update
status: implemented
source_sha: ""
---

# Account lifecycle

CRUD биллинг-аккаунтов. `Account` — верхняя граница tenancy: единица биллинга и
владения, owner-пользователь (`owner_user_id`) задаётся при создании. Внутри
аккаунта живут `Project`, `ServiceAccount`, `Group` и custom-роли; Account
заменил упразднённый `Cloud` из `kacho-resource-manager` (KAC-124).

## Зачем

Аккаунт — корень дерева tenancy и scope для авторизации: REBAC-проверки
`viewer` / `editor` / `admin` адресуют объект `account:<id>`. Все дочерние
ресурсы account-scoped — Account определяет, кто их видит и кем управляет.

## Контракт

- `Get` / `List` / `ListOperations` — sync read; `List` фильтруется YC-style
  syntax + page_token; `ListOperations` отдаёт per-account историю операций.
- `Create` / `Update` / `Delete` — async, возвращают `Operation`
  (`CreateAccountMetadata{account_id}` в metadata).

## Lifecycle

- `Create` — INSERT + bootstrap owner-grant; `owner_user_id` обязан существовать
  (FK на `users` RESTRICT).
- `Update` — UpdateMask discipline; `owner_user_id` immutable после Create.
- `Delete` — async; `FailedPrecondition`, если у аккаунта остались projects /
  service-accounts / groups / custom-роли (нет cross-resource cascade — §Запрет 4).

## Gotchas

- `Account.name` уникален **глобально** (UNIQUE без partial), не в пределах
  родителя — конфликт имени между аккаунтами разных владельцев → `AlreadyExists`.
- Owner-FK RESTRICT работает в обе стороны: User-owner нельзя удалить, пока он
  владеет аккаунтами.

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-account-lifecycle]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
