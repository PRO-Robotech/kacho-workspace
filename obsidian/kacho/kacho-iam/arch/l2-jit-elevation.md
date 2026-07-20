---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.JITEligibilityService/Create
  - rpc: kacho.cloud.iam.v1.JITEligibilityService/Delete
  - rpc: kacho.cloud.iam.v1.JITEligibilityService/Get
  - rpc: kacho.cloud.iam.v1.JITEligibilityService/List
  - rpc: kacho.cloud.iam.v1.JITEligibilityService/Update
  - rpc: kacho.cloud.iam.v1.JitPendingService/ApproveJITActivation
  - rpc: kacho.cloud.iam.v1.JitPendingService/DenyJITActivation
  - rpc: kacho.cloud.iam.v1.JitPendingService/GetJitPending
  - rpc: kacho.cloud.iam.v1.JitPendingService/ListJitPending
status: implemented
source_sha: ""
---

# JIT elevation

Just-in-time / PIM-elevation: пользователь не держит привилегированную роль
постоянно, а **активирует** её на ограниченное время. Два сервиса —
`JITEligibilityService` (кто что может активировать) и `JitPendingService`
(approve/deny ожидающих активаций).

## Зачем

Standing privileged access — основной риск. JIT/PIM сводит его к минимуму:
привилегия выдаётся только на время задачи, под TTL, при необходимости — после
одобрения approver'ом. Каждая активация оставляет аудиторский след.

## Контракт

**`JITEligibilityService`** — CRUD правил eligibility:
- `Create` / `Update` / `Delete` — async; `Get` / `List` — sync.
- Правило: `user_id` × `role_id` × `resource_type`/`resource_id`, `max_duration`
  (CHECK `(0s, 8h]`), `approval_required`, `approver_user_id`, `enabled`,
  опц. `expires_at`.

**`JitPendingService`** — обработка активаций, ждущих одобрения:
- `ApproveJITActivation` / `DenyJITActivation` — async (`Operation`);
  суффикс-actions `:approve` / `:deny`.
- `GetJitPending` / `ListJitPending` — sync read.

## Lifecycle

- Eligibility-правило задаёт «кто может self-activate какую роль, как долго,
  нужен ли approver».
- Активация при `approval_required=false` — авто-апрув; при `true` — создаётся
  pending-запись, approver вызывает `ApproveJITActivation` / `DenyJITActivation`.
- Approved-активация даёт временный binding на `max_duration`; по истечении —
  снимается.

## Gotchas

- `max_duration` DB-CHECK `(0s, 8h]` — потолок длительности привилегии.
- `approval_required=true` ⇒ `approver_user_id` обязан быть задан;
  `false` ⇒ approver может быть NULL (auto-approve).
- Все FK (`user_id` / `role_id` / `approver_user_id`) — RESTRICT.

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-jit-elevation]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
