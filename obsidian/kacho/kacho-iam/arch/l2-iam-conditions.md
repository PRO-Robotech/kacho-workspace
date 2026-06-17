---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.ConditionsService/Create
  - rpc: kacho.cloud.iam.v1.ConditionsService/Delete
  - rpc: kacho.cloud.iam.v1.ConditionsService/Evaluate
  - rpc: kacho.cloud.iam.v1.ConditionsService/Get
  - rpc: kacho.cloud.iam.v1.ConditionsService/List
  - rpc: kacho.cloud.iam.v1.ConditionsService/Update
status: implemented
source_sha: ""
---

# IAM conditions

CRUD переиспользуемых CEL-условий + sandbox-`Evaluate`. `Condition` — именованное
выражение (CEL), которое накладывается на `AccessBinding` overlay'ем: доступ
действует, только если условие истинно в контексте запроса.

## Зачем

Conditions переводят статичный grant в attribute-based: «доступ только в рабочее
время», «только из корпоративной подсети», «только при свежем MFA». Условие
описывается один раз и переиспользуется на множестве bindings вместо дублирования
логики.

## Контракт

- `Get` / `List` — sync read; `List` фильтруется по `account_id` / `kind` /
  `enabled`.
- `Create` / `Update` / `Delete` — async (`Operation`).
- `Evaluate` — sync dry-run: `(condition_id, params, request_context) →
  allowed, trace[]` в sandboxed CEL-evaluator (без I/O) — для отладки и
  валидации перед привязкой.

## Lifecycle

- `Create` — INSERT `conditions`-row: `expression` (CEL-строка),
  `params_schema` (JSON Schema), `kind` (`time` / `ip` / `mfa` / `request_attr`
  / `resource_attr` / `composite`).
- `Update` — mutable: `description` / `expression` / `params_schema` /
  `enabled`; immutable: `kind`, `id`.
- `Delete` — RESTRICT, если на условие ссылаются per-binding-overlay-записи.

## Gotchas

- CEL-evaluator sandboxed: нет `net`, нет `os`, нет `time.Now()` вне переданного
  контекста — детерминированность и отсутствие side-channel.
- `expression` парс-валидируется на Create/Update; ошибка → `InvalidArgument`.
- Conditions глобальны (cluster-scope) либо account-scoped; per-binding overlay
  с конкретными CEL-params живёт отдельно (привязка binding ↔ condition).

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-iam-conditions]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
