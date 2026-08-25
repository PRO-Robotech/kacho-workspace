---
title: InternalWatchService (снят и у vpc, и у compute — заменён общей подпиской)
aliases:
  - InternalWatchService (vpc)
proto_file: "нет ни у vpc, ни у compute — контракт снят в обоих доменах; общая подписка живёт в kacho/cloud/subscription"
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
status: deprecated
verified_against: "пересверено с деревом продукта 16f3313f (2026-08-24, вровень с origin/main): служб у домена compute восемь, InternalWatchService среди них НЕТ; у vpc контракта нет по-прежнему"
methods_count: 0
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - deprecated
---

# InternalWatchService — снят у ОБОИХ доменов

> [!warning] У vpc не осталось ни реализации, ни контракта
> Сверено по стволу 2026-08-05, два предиката:
>
> - **Контракт**: файла службы в каталоге контрактов домена vpc **нет** (мёртвый адрес
>   здесь намеренно не пишется координатой: цитата в обратных кавычках читается проверкой
>   свежести как живое утверждение о дереве). Прежняя редакция утверждала, что «proto-файл
>   остался для backward-compat» — уже на том дереве это было неверно: он снят вместе с
>   реализацией.
> - **Код**: в `services/vpc/` вне тестов нет ни одного упоминания `WatchService`;
>   в `services/vpc/internal/handler/` обработчика watch нет.
>
> [!warning] «У compute одноимённый сервис ЖИВ» — БОЛЬШЕ НЕВЕРНО (перемерено 16f3313f, 2026-08-24)
> Здесь стояло, что тот же `InternalWatchService` объявлен у домена compute, и записку
> предлагалось держать именно ради этого различения. Предмет различения исчез: контракт
> снят и там — задачей [`kacho#813`](https://github.com/PRO-Robotech/kacho/issues/813),
> чей заголовок прямо называет исход — служба **переводится на общую форму подписки, а не
> снимается**.
>
> Предикат (служб у домена восемь, этой среди них нет):
> ```sh
> for f in $(git ls-tree -r origin/main --name-only proto/kacho/cloud/compute/v1/); do
>   git show "origin/main:$f" | grep -oE '^service [A-Za-z]+'; done | sort
> ```
>
> **Чем заменено у обоих**: общий формат подписки на изменения — контракт
> [[rpc/subscription-service]], механизм [[packages/corelib-subscription]], линия работ
> [[KAC/watch-unified-change-stream-2026-08]]. Прежние объявления обоих доменов занесены
> в надгробие снятых поверхностей (`internal/repohygiene/retiredrpcsurface_test.go`) —
> то есть их возвращение ловится гейтом, а не памятью.
>
> Записку стоит держать по прежней причине, но уже в другую сторону: имя `Watch` живёт в
> исторических приёмках и планах, и без этой записки следующий читатель примет их за
> описание дерева.

## Почему Watch не был поверхностью ресурса — это дизайн, а не недоделка

Kachō не выставляет Watch как способ следить за ресурсами: чтение — синхронное
`List`/`Get`, in-flight мутация — поллинг `OperationService.Get(id)` до `done=true`
(`api-conventions.md`: «Watch RPC не существует»). UI опрашивает список раз в 2–5 секунд.

Общая подписка этого **не отменяет**: она внутренняя (:9091), и её собственный контракт
прямо говорит, что полл операции она не заменяет — событие, не попавшее в журнал, для
подписки не существует.

## Что от эпохи Watch осталось живым — и это не сервис

Таблица `kacho_vpc.vpc_outbox` и записи в неё **живы**: каждая мутация эмитит событие в
outbox в той же writer-транзакции. Живёт и `kacho_vpc.vpc_watch_cursors` — таблица серверных курсоров, пережившая
своего читателя; её снятие заведено задачей [`kacho#1148`](https://github.com/PRO-Robotech/kacho/issues/1148)
(таких таблиц в дереве было четыре, снята пока одна — у compute). Это транспорт
дренажа/реконсиляции, а не поверхность API — по нему никто не «смотрит» снаружи. Не
принимать существование этих таблиц за доказательство существования RPC: тот же класс
вывода, из-за которого живой префикс идентификатора когда-то приняли за живой домен.

## См. также

[[rpc/subscription-service]] · [[packages/corelib-subscription]] ·
[[KAC/watch-unified-change-stream-2026-08]] · [[rpc/nlb-internal-resource-lifecycle-service]] ·
[[rpc/operation-service]] · [[packages/corelib-operations]] · [[rpc/compute-instance-service]]

#rpc #kacho-vpc #internal #deprecated
