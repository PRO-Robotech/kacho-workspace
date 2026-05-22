---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.ProjectService/Create
  - rpc: kacho.cloud.iam.v1.ProjectService/Delete
  - rpc: kacho.cloud.iam.v1.ProjectService/Get
  - rpc: kacho.cloud.iam.v1.ProjectService/List
  - rpc: kacho.cloud.iam.v1.ProjectService/ListOperations
  - rpc: kacho.cloud.iam.v1.ProjectService/Move
  - rpc: kacho.cloud.iam.v1.ProjectService/Update
status: implemented
source_sha: ""
---

# Project lifecycle

CRUD проектов плюс cross-account `Move`. `Project` — рабочая область внутри
`Account`; на неё (через `project_id`) ссылаются ресурсы `kacho-vpc` и
`kacho-compute` — `Project` заменил старый `Folder` упразднённого
`kacho-resource-manager` (KAC-124).

## Зачем

Проект — единица изоляции и scope большинства tenant-ресурсов: сети, инстансы,
диски создаются «в проекте». Consumer-сервисы (vpc/compute) валидируют
`project_id` вызовом `ProjectService.Get` на request-path — это рабочее
runtime-ребро в графе.

## Контракт

- `Get` / `List` / `ListOperations` — sync read.
- `Create` / `Update` / `Delete` / `Move` — async, возвращают `Operation`.
- `Move` — суффикс-action `:move` (`POST /iam/v1/projects/{id}:move`),
  переносит проект между аккаунтами.

## Lifecycle

- `Create` — `account_id` обязателен; уникальность имени — в пределах account
  (`UNIQUE (account_id, name)`).
- `Update` — UpdateMask; `account_id` через `Update` **immutable** (менять —
  только через `Move`).
- `Delete` — async; ссылки от vpc/compute через границу сервиса (cross-DB, FK
  невозможен) — consumer должен грациозно переживать dangling-ref.

## Gotchas

- `Move` — атомарный CAS: `UPDATE projects SET account_id=$new WHERE id=$id AND
  account_id=$expected RETURNING …` (§Запрет 10). 0 rows → `FailedPrecondition`.
  `UNIQUE (account_id, name)` дополнительно ловит конфликт имени в целевом
  аккаунте → `AlreadyExists`.
- Project-deletion не каскадит в vpc/compute — оставшиеся там ресурсы становятся
  dangling, это by-design (database-per-service).
