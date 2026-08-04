---
title: InternalWatchService (vpc — снят; у compute живёт)
aliases:
  - InternalWatchService (vpc)
proto_file: "нет для vpc; у compute — kacho/cloud/compute/v1/internal_watch_service.proto"
category: rpc
backend: kacho-vpc
backend_port: 9091
visibility: internal
domain: vpc
status: deprecated
verified_against: "ствол redesign/integration, сверено 2026-08-05"
methods_count: 0
async_methods: 0
tags:
  - rpc
  - kacho-vpc
  - internal
  - deprecated
---

# InternalWatchService (vpc) — снят целиком

> [!warning] У vpc не осталось ни реализации, ни контракта
> Сверено по стволу 2026-08-05, два предиката:
>
> - **Контракт**: файла `proto/kacho/cloud/vpc/v1/internal_watch_service.proto` **нет**.
>   Прежняя редакция утверждала, что «proto-файл остался для backward-compat» — на этом
>   дереве это уже неверно: он снят вместе с реализацией.
> - **Код**: в `services/vpc/` вне тестов нет ни одного упоминания `WatchService`;
>   в `services/vpc/internal/handler/` обработчика watch нет.
>
> **Одноимённый сервис ЖИВ у другого домена**: `InternalWatchService` объявлен в
> `proto/kacho/cloud/compute/v1/internal_watch_service.proto` (`rpc Watch` →
> `stream Event`). Это **другой** предмет — совпадение имени, а не выживание vpc-шного.
> Из-за этого совпадения записку и стоит держать: без неё следующий читатель, увидев
> живой compute-watch, решит, что и vpc-шный на месте.

## Почему Watch у vpc нет — это дизайн, а не недоделка

Kachō не выставляет Watch как способ следить за ресурсами: чтение — синхронное
`List`/`Get`, in-flight мутация — поллинг `OperationService.Get(id)` до `done=true`
(`api-conventions.md`: «Watch RPC не существует»). UI опрашивает список раз в 2–5 секунд.

## Что от эпохи Watch осталось живым — и это не сервис

Таблица `kacho_vpc.vpc_outbox` и записи в неё **живы**: каждая мутация эмитит событие в
outbox в той же writer-транзакции. Живёт и `kacho_vpc.vpc_watch_cursors`. Это транспорт
дренажа/реконсиляции, а не поверхность API — по нему никто не «смотрит» снаружи. Не
принимать существование этих таблиц за доказательство существования RPC: тот же класс
вывода, из-за которого живой префикс идентификатора когда-то приняли за живой домен.

## См. также

[[operation-service]] · [[../packages/corelib-operations]] · [[compute-instance-service]]

#rpc #kacho-vpc #internal #deprecated
