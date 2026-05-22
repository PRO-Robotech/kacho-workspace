---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.GdprErasureService/CancelErasureRequest
  - rpc: kacho.cloud.iam.v1.GdprErasureService/GetErasureRequest
  - rpc: kacho.cloud.iam.v1.GdprErasureService/ListErasureRequests
  - rpc: kacho.cloud.iam.v1.GdprErasureService/RequestErasure
status: implemented
source_sha: ""
---

# GDPR erasure

Pipeline «права на забвение» (GDPR Art. 17): запрос на удаление персональных
данных пользователя с обязательным 30-дневным cool-off.

## Зачем

GDPR обязывает по запросу удалить персональные данные субъекта. Прямое
немедленное удаление опасно (ошибка, злоупотребление), поэтому запрос проходит
cool-off-окно, в течение которого его можно отменить, и только потом
исполняется.

## Контракт

- `RequestErasure` — async (`Operation`); регистрирует erasure-request,
  результат — `GdprErasureRequest`.
- `CancelErasureRequest` — async; отменяет запрос, пока он в cool-off
  (результат — `Empty`).
- `GetErasureRequest` / `ListErasureRequests` — sync read.

## Lifecycle

State machine: `cool_off → in_progress → completed` (или `cancelled`).

- `RequestErasure` создаёт row в состоянии `cool_off`; `cool_off_until` —
  обычно `requested_at + 30d`, строго `> requested_at`.
- `CancelErasureRequest` валиден только пока `cool_off` → переводит в
  `cancelled`.
- Worker по истечении cool-off переводит `cool_off → in_progress` и исполняет
  стирание; затем `completed`. `completed` / `cancelled` — терминальны.

## Gotchas

- `user_id` (цель стирания) и `requested_by_user_id` (инициатор — сам субъект
  или admin) — оба RESTRICT FK на `users`.
- Запрос можно отменить **только** в окне cool-off; после `in_progress` —
  поздно.
- Стирание затрагивает данные только в пределах БД kacho-iam; cross-service
  персональные данные — отдельная забота владельцев тех данных (нет cross-service
  cascade).
