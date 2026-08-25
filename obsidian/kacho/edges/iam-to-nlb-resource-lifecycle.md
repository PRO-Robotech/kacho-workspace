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
status: superseded
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
  - deprecated
verified_against: "пересверено с деревом продукта 16f3313f (2026-08-24, вровень с origin/main): сервера этой подписки в дереве НЕТ (снят), клиента у iam не было никогда — ребро мертво с обеих сторон"
---

> [!warning] Ребро МЕРТВО С ОБЕИХ СТОРОН — записка описывает прошлое (перемерено 16f3313f, 2026-08-24)
> Прежняя редакция фиксировала ребро наполовину построенным: сервер у nlb жив, клиента
> в iam нет ни одного. **Сегодня нет и сервера** — он снят вместе со своим контрактом
> задачей [`kacho#1043`](https://github.com/PRO-Robotech/kacho/issues/1043) (в ствол
> через MR #1151). То есть половина, которая была, исчезла; половина, которой не было,
> так и не появилась.
>
> Предикаты (оба ожидают пусто):
> ```sh
> git ls-tree -r origin/main --name-only | grep -i internal_lifecycle
> git grep -n 'ResourceLifecycle' origin/main -- 'services/iam/**' ':!*_test.go'
> ```
>
> **Функцию, ради которой ребро задумывалось, несёт другое, живое ребро** —
> [[edges/nlb-to-iam-fga-register]]: durable-намерение в writer-транзакции ресурса плюс
> дренаж, направление обратное (nlb → iam). Поэтому снятие подписки ничего не отняло:
> предмет уже был закрыт другим механизмом, и ацикличность от этого ребра не зависела.
>
> **Подписка как таковая не отменена — она стала общей.** Формат один на платформу:
> контракт [[rpc/subscription-service]], механизм [[packages/corelib-subscription]],
> линия работ [[KAC/watch-unified-change-stream-2026-08]]. Если iam когда-нибудь
> понадобится поток изменений nlb, он строится **на общем сервере**, а не восстановлением
> описанного ниже.
>
> Всё, что ниже, — **замысел 2026 года**, сохранённый как история: ни одна его строка
> сегодня не описывает дерево.

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

## Что было на стороне nlb (снято #1043 — координат в дереве не осталось)

- Ограничение числа одновременных стримов — ключ конфигурации домена
  (не переменная окружения; страж старта требовал значения больше нуля).
  Слот не выдан → `RESOURCE_EXHAUSTED`.
- Выделенное соединение (вне пула) → подписка на канал уведомлений журнала → цикл ожидания с
  периодическим перечитыванием (30 с) на случай пропущенного уведомления.
- Догоняющее чтение батчами при подключении; позиция подписчика хранилась **на сервере**
  — именно это решение общий сервер и отменил: позиция принадлежит клиенту.
- Допустимые виды ресурса ограничены белым списком (`nlb_load_balancer`, `nlb_listener`,
  `nlb_target_group`); неизвестный вид → `INVALID_ARGUMENT`.

Стороны iam (подписчика, курсора, применения событий) в дереве не было **никогда**.
Всё, что ниже про поведение iam, — замысел, а не описание.

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

[[rpc/subscription-service]] · [[packages/corelib-subscription]] · [[KAC/watch-unified-change-stream-2026-08]] ·
[[rpc/nlb-internal-resource-lifecycle-service]] · [[packages/nlb-apps-kacho-api-internal-lifecycle]] ·
[[edges/nlb-to-iam-fga-register]] · [[edges/nlb-to-iam-creator-tuple]] · [[KAC/KAC-108]] · [[KAC/KAC-141]]

#edge #kacho-iam #kacho-nlb #cross-service #lifecycle #d13 #deprecated
