---
level: functionality
repo: kacho-iam
anchors:
  - rpc: kacho.cloud.iam.v1.AccessReviewService/ApproveReviewItem
  - rpc: kacho.cloud.iam.v1.AccessReviewService/CancelAccessReviewCampaign
  - rpc: kacho.cloud.iam.v1.AccessReviewService/GetAccessReview
  - rpc: kacho.cloud.iam.v1.AccessReviewService/ListAccessReviewItems
  - rpc: kacho.cloud.iam.v1.AccessReviewService/ListAccessReviews
  - rpc: kacho.cloud.iam.v1.AccessReviewService/RevokeReviewItem
  - rpc: kacho.cloud.iam.v1.AccessReviewService/ScheduleAccessReview
status: implemented
source_sha: ""
---

# Access reviews

Периодическая рецертификация доступов — квартальная проверка, что все
access-bindings ещё нужны (compliance: SOC 2 CC6.2, ISO 27001 A.9.2.5).

## Зачем

Со временем bindings накапливаются и протухают. Access-review заставляет
назначенного reviewer'а явно подтвердить (keep) или отозвать (revoke) каждый
доступ — это документированный аудиторский след «доступ пересмотрен».

## Контракт

Три аггрегата: `AccessReviewCampaign` (повторяющийся шаблон-расписание),
`AccessReview` (один материализованный цикл кампании), `AccessReviewItem`
(per-binding строка-решение внутри review).

- `ScheduleAccessReview` — async; регистрирует recurring-кампанию.
- `CancelAccessReviewCampaign` — async; отключает кампанию.
- `ApproveReviewItem` / `RevokeReviewItem` — async; решение reviewer'а по
  конкретному item'у (keep / revoke binding).
- `GetAccessReview` / `ListAccessReviews` / `ListAccessReviewItems` — sync read.

## Lifecycle

- `ScheduleAccessReview` создаёт кампанию; scheduler-worker материализует
  `AccessReview` + items, когда кампания «подошла».
- Review проходит state machine `scheduled → in_progress → completed`
  (или `cancelled`); `completed_at` обязателен ⇔ `status=completed`.
- Reviewer проходит по items: `ApproveReviewItem` оставляет binding,
  `RevokeReviewItem` отзывает его.

## Gotchas

- `account_id` review — RESTRICT FK на `accounts`; `reviewer_user_id` —
  RESTRICT FK на `users`.
- `ScheduleAccessReview` требует повышенного ACR (step-up MFA) — операция
  чувствительная к compliance.
- Кампания и её материализованные циклы — разные сущности: отмена кампании не
  отменяет уже идущий review.

## Связанные заметки

<!-- archgraph:links -->
- ↑ Приклад: [[_l1-kacho-iam]]
- ↓ Функции (call-дерево, RPC contract): [[l3-l2-access-reviews]]
- Переменные: [[l4-kacho-iam]]
<!-- /archgraph:links -->
