---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.GroupService/AddMember
  - rpc: kacho.cloud.iam.v1.GroupService/Create
  - rpc: kacho.cloud.iam.v1.GroupService/Delete
  - rpc: kacho.cloud.iam.v1.GroupService/Get
  - rpc: kacho.cloud.iam.v1.GroupService/List
  - rpc: kacho.cloud.iam.v1.GroupService/ListMembers
  - rpc: kacho.cloud.iam.v1.GroupService/ListOperations
  - rpc: kacho.cloud.iam.v1.GroupService/RemoveMember
  - rpc: kacho.cloud.iam.v1.GroupService/Update
status: implemented
source_sha: ""
---

# Group management

CRUD групп и управление их членством. `Group` — account-scoped агрегация
subjects (users и service-accounts), на которую можно вешать access-bindings
вместо раздачи доступа поимённо.

## Зачем

Группа сокращает число bindings: вместо «N пользователей × роль» — «группа ×
роль». В REBAC-модели group-membership разворачивается в transitive-доступ:
binding на группу даёт доступ всем её членам.

## Контракт

- `Get` / `List` / `ListMembers` / `ListOperations` — sync read;
  `ListMembers` фильтруется по `member_type`.
- `Create` / `Update` / `Delete` / `AddMember` / `RemoveMember` — async
  (`Operation`). `AddMember` / `RemoveMember` — суффикс-actions.

## Lifecycle

- `Create` — `account_id` обязателен; `Update` — UpdateMask, `account_id`
  immutable.
- `Delete` — каскадит по `group_members` (same-DB FK CASCADE — разрешено,
  не cross-service).
- `AddMember` — идемпотентен: `PRIMARY KEY (group_id, member_type, member_id)`
  ловит повтор.
- `RemoveMember` — идемпотентен.

## Gotchas

- Существование добавляемого member'а проверяется BEFORE-INSERT триггером
  `group_members_member_exists`; несуществующий user/SA → `FailedPrecondition`.
- Auth-matrix (default-deny через REBAC Check на `account:<group.account_id>`):
  Create — `admin` на `req.account_id`; read — `viewer`; mutate/member-ops —
  `admin` на ассоциированном account; `List` без `account_id` → пустой ответ
  для не-system-admin.

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-group-management]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
