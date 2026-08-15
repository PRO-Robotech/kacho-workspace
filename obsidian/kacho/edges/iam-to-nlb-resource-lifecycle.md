---
title: "iam → nlb: D-13 lifecycle subscribe (outbox stream)"
aliases:
  - iam subscribes nlb
  - nlb lifecycle stream
category: edge
caller_repo: kacho-iam
callee_repo: kacho-nlb
sync_async: async
protocol: grpc-cluster-internal-stream
status: planned
related_tickets:
  - "[[KAC-141]]"
  - "[[KAC-157]]"
  - "[[KAC-108]]"
tags:
  - edge
  - kacho-iam
  - kacho-nlb
  - cross-service
  - lifecycle
  - d13
verified_against: "отметка сверки с деревом продукта стоит в тексте записки (96b2879a, 2026-08-05)"
---

> [!warning] Сервер есть, ПОДПИСЧИКА НЕТ — ребро наполовину построено (замер 2026-08-05)
> Записка объявляла ребро активным: «kacho-iam подписывается…». В дереве `96b2879a`:
>
> - **сервер жив** — `services/nlb/internal/apps/kacho/api/internal_lifecycle/handler.go`
>   реализует `Subscribe`, включая семафор слотов, выделенное соединение под LISTEN и
>   догоняющее чтение; его godoc прямо называет потребителем kacho-iam;
> - **клиента нет** — в `services/iam` **ноль** упоминаний lifecycle-подписки (предикат:
>   `grep -rn "ResourceLifecycle" services/iam` → 0 не-тестовых вхождений; единственный
>   вызывающий `Subscribe(` во всём дереве — сам обработчик nlb).
>
> То есть поток событий производится и **никем не потребляется**. Ошибиться тут легко в
> обе стороны: «ребро работает» неверно, но и «этого нет» неверно — половина построена,
> оплачивается ресурсами (соединение, семафор, курсоры) и проходит гейты старта.
>
> **Функцию, ради которой ребро задумывалось, сегодня несёт другое ребро**:
> синхронизацию владельческих кортежей делает [[nlb-to-iam-fga-register]] — durable-намерение
> в writer-транзакции ресурса + дренаж + периодический переигрыш отравленных строк, — и
> направление там обратное (nlb → iam), то есть ацикличность не зависит от того, поднимется
> ли эта подписка. Прежде чем достраивать подписчика, надо ответить, что он добавит
> сверх регистрации; иначе появятся два механизма об одном предмете.

# iam → nlb: D-13 lifecycle subscribe

**Caller**: `kacho-iam` (lifecycle subscriber pool; iam-side reads nlb outbox)
**Callee**: `kacho-nlb.InternalResourceLifecycleService.Subscribe` (port 9091, server-stream)
**Protocol**: gRPC cluster-internal (server-streaming)
**Sync/Async**: **async** (long-lived stream, semaphore-bounded)

## When invoked

- На старте kacho-iam — открывается long-lived `Subscribe` stream к каждому resource-owner backend'у (nlb, vpc, compute) для D-13 hierarchy tuple sync.
- Stream consumes `LifecycleEvent` (см. [[../rpc/nlb-internal-resource-lifecycle-service]]):
  - `CREATED` → ensure parent-tuple существует в OpenFGA (race-safe backstop для [[nlb-to-iam-creator-tuple]]).
  - `UPDATED` → no-op (relationship tuples не меняются; FGA не индексирует атрибуты).
  - `DELETED` → cleanup всех tuples для `<object_type>:<resource_id>` (idempotent).

## Implementation — что РЕАЛЬНО есть (сторона nlb)

- Ограничение числа одновременных стримов — настройка `internal-lifecycle.max-streams`
  (в дереве это ключ конфигурации, а не переменная окружения; boot-guard требует `> 0`).
  Слот не выдан → `RESOURCE_EXHAUSTED`.
- Выделенное соединение (вне пула) → `LISTEN` на канал `nlb_outbox` → цикл ожидания с
  периодическим перечитыванием (30 с) на случай пропущенного уведомления.
- Догоняющее чтение батчами при подключении; позиция подписчика — `nlb_watch_cursors`.
- Допустимые виды ресурса ограничены белым списком (`nlb_load_balancer`, `nlb_listener`,
  `nlb_target_group`); неизвестный вид → `INVALID_ARGUMENT`.

Стороны iam (подписчика, курсора, применения событий) в дереве **нет** — см. предупреждение
выше. Всё, что ниже про поведение iam, — замысел, а не описание.

## At-least-once semantics

Subscriber должен быть idempotent — duplicate `CREATED` после reconnect/catchup → no-op (FGA `Write` идемпотентен через `WriteIfNotExist` pattern).

## Why both D-11 + D-13

- **D-11** (sync creator-tuple в Create worker, см. [[nlb-to-iam-creator-tuple]]) — closes ErrNoPath race-window для immediate read after Create.
- **D-13** (async outbox subscribe, эта edge) — long-running cleanup + reconciliation guarantee. Если D-11 failed (iam temporarily down) → D-13 catches up на reconnect.

## Error handling

| Result | Behavior |
|---|---|
| Event consumed | advance cursor; FGA Write applied |
| FGA Write failed | log ERR + alert; retry next event loop tick |
| Stream broken | iam reconnects with cursor resume |
| nlb недоступен | iam log WARN, exponential backoff reconnect |

## See also

[[../rpc/nlb-internal-resource-lifecycle-service]] [[../packages/nlb-apps-kacho-api-internal-lifecycle]] [[nlb-to-iam-creator-tuple]] [[../KAC/KAC-108]] [[../KAC/KAC-141]]

#edge #kacho-iam #kacho-nlb #cross-service #lifecycle #d13
