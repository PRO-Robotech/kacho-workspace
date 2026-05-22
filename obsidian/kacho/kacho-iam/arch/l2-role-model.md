---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.RoleService/Create
  - rpc: kacho.cloud.iam.v1.RoleService/Delete
  - rpc: kacho.cloud.iam.v1.RoleService/Get
  - rpc: kacho.cloud.iam.v1.RoleService/List
  - rpc: kacho.cloud.iam.v1.RoleService/ListOperations
  - rpc: kacho.cloud.iam.v1.RoleService/Update
status: implemented
source_sha: ""
---

# Role model

CRUD ролей. `Role` — именованный набор permission'ов. Роли делятся на
**system** (предопределённые платформой, immutable) и **custom**
(account-scoped, создаются клиентом).

## Зачем

Роль — единица, которую `AccessBinding` связывает с subject'ом и ресурсом.
Permission-каталог фиксирован платформой; роль группирует permission'ы в удобный
для выдачи набор (`viewer` / `editor` / `admin` и доменные роли).

## Контракт

- `Get` / `List` / `ListOperations` — sync read; `List` фильтруется
  `is_system=true|false` и `account_id`.
- `Create` / `Update` / `Delete` — async (`Operation`). `Create` — **только
  custom**-роли, `account_id` обязателен.

## Lifecycle

- System-роли сидятся миграцией (initial); добавление новой system-роли —
  только новой миграцией (§Запрет 5 — applied-миграции не редактируются).
- `Update` / `Delete` для роли с `is_system=true` → `FailedPrecondition`.
- `Delete` custom-роли — заблокирован FK RESTRICT, если на роль есть активные
  access-bindings.

## Gotchas

- System-role immutability — sentinel в service-слое (плюс DB-CHECK на
  `is_system`-rows).
- Wildcard-permission'ы хранятся as-is, не разворачиваются на уровне Role —
  expansion происходит в REBAC Check (см. `l2-authorization`).
