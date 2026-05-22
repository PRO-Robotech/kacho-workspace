---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.InternalBreakGlassService/ApproveBreakGlassA
  - rpc: kacho.cloud.iam.v1.InternalBreakGlassService/ApproveBreakGlassB
  - rpc: kacho.cloud.iam.v1.InternalBreakGlassService/DenyBreakGlass
  - rpc: kacho.cloud.iam.v1.InternalBreakGlassService/GetBreakGlassRequest
  - rpc: kacho.cloud.iam.v1.InternalBreakGlassService/ListPendingBreakGlassRequests
  - rpc: kacho.cloud.iam.v1.InternalBreakGlassService/RequestBreakGlass
status: implemented
source_sha: ""
---

# Break-glass

Аварийный доступ под обязательным two-person approve. `InternalBreakGlassService`
выдаёт временный cluster-grant, когда штатные пути авторизации недоступны или
требуется экстренное вмешательство.

## Зачем

В инциденте может потребоваться доступ, которого нет ни у кого «по умолчанию»
(по принципу least-privilege). Break-glass даёт его — но под жёстким контролем:
два независимых одобряющих, обязательный TTL, полный аудит. Сервис — `Internal*`,
живёт на internal-listener (§Запрет #6).

## Контракт

- `RequestBreakGlass` — async (`Operation`); создаёт запрос на аварийный grant
  (`ClusterBreakGlassGrant`).
- `ApproveBreakGlassA` / `ApproveBreakGlassB` — async; два **разных**
  одобряющих; grant активируется только после обоих.
- `DenyBreakGlass` — async; отклонение запроса.
- `GetBreakGlassRequest` / `ListPendingBreakGlassRequests` — sync read.

## Lifecycle

State machine grant'а (6 состояний): запрос → одобрение A → одобрение B →
активный grant → истечение/отзыв; ветка denied — терминальна.

- `RequestBreakGlass` фиксирует `requested_by_user_id`, scope (`cluster_id`),
  subject (individual `user` / `service_account` — **не** группа).
- `ApproveBreakGlassA` и `ApproveBreakGlassB` — обязаны быть разными
  пользователями; одобряющий ≠ инициатор.
- Активный grant имеет обязательный TTL — по истечении снимается автоматически.

## Gotchas

- Two-person rule — инвариант: один и тот же approver не может закрыть обе
  стороны; инициатор не может быть approver'ом.
- Subject — только individual identity, не группа (нельзя «аварийно» поднять
  целую группу).
- Все операции — internal-listener; на external TLS не публикуются.
- `RequestBreakGlass` / `Get` / `List` помечены authz-exempt — break-glass
  работает, когда обычный authz-путь недоступен.
