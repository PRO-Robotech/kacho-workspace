---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.AccessBindingService/Create
  - rpc: kacho.cloud.iam.v1.AccessBindingService/Delete
  - rpc: kacho.cloud.iam.v1.AccessBindingService/Get
  - rpc: kacho.cloud.iam.v1.AccessBindingService/ListByResource
  - rpc: kacho.cloud.iam.v1.AccessBindingService/ListBySubject
status: implemented
source_sha: ""
---

# Access bindings

Grant/revoke доступа. `AccessBinding` — тройка **subject × role × resource**:
«этот subject имеет эту роль на этом ресурсе». Это write-модель авторизации;
read-модель (фактическая проверка) — `l2-authorization`.

## Зачем

Binding — единственный санкционированный способ выдать доступ. Каждый
Create/Delete синхронизирует соответствующий relation-tuple в REBAC-store
(OpenFGA), откуда его читает `AuthorizeService.Check`.

## Контракт

- `Create` / `Delete` — async (`Operation`); пишут/удаляют FGA grant-tuple.
- `Get` — sync read по id.
- `ListByResource` / `ListBySubject` — sync read; суффикс-actions
  (`:listByResource` / `:listBySubject`), фильтр по
  (resource_type, resource_id) или (subject_type, subject_id).

## Lifecycle

- `Create` — INSERT + запись relation-tuple (и project-hierarchy-tuple) в
  OpenFGA. UNIQUE `(subject_type, subject_id, role_id, resource_type,
  resource_id)` делает повторный Create идемпотентным.
- `Delete` — удаляет DB-row **и** те же FGA-tuple'ы, что записал Create
  (иначе доступ остался бы в OpenFGA).

## Gotchas

- `subject_id` / `resource_id` хранятся **без FK** — полиморфные,
  потенциально cross-DB ссылки; целостность держится через REBAC-tuple-sync, не
  через БД.
- Удаление `Role` с активным binding → `FailedPrecondition` (FK RESTRICT).
- Authority: и Create, и Delete авторизуются через общий `requireGrantAuthority`
  — caller обязан быть owner владеющего Account/Project либо держать FGA `admin`
  на scope. Delete — **не** self-only: account-owner может отзывать чужие grants.
