---
title: "nlb → iam: сужение страницы списка пакетной проверкой"
aliases:
  - nlb listobjects
  - nlb fga listobjects
  - nlb list-filter
  - nlb batchcheck
category: edge
caller_repo: kacho-nlb
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: active
related_tickets:
  - "[[rbac-rules-model-2026-subphase-D-nlb-consumer]]"
tags:
  - edge
  - kacho-nlb
  - cross-service
  - authz
  - fga
---

# nlb → iam: сужение страницы списка пакетной проверкой

> [!info] Имя файла — координата, а не описание
> Файл называется `…-listobjects` ради стабильности ссылок; перечислением ребро
> больше не пользуется. Та же оговорка — в [[vpc-to-iam-listobjects]].

**Caller**: `kacho-nlb` — 6 списочных методов в 3 ресурсах: `loadbalancer.List`,
`loadbalancer.ListOperations`, `listener.List`, `listener.ListOperations`,
`targetgroup.List`, `targetgroup.ListOperations`. Cluster-scoped среди них нет —
все шесть тенантские.
**Callee**: `kacho-iam` `AuthorizeService.BatchCheck` ([[../rpc/iam-authorize-service]]),
по тому же соединению, которым nlb зовёт `ProjectService.Get`.
**Protocol**: gRPC, sync, request-path.
**Реализация**: `services/nlb/internal/authzfilter/`.

## Типы объектов

FGA-префикс типов — **`lb_`**, не `nlb_`: `lb_network_load_balancer`,
`lb_listener`, `lb_target_group`. Совпадает с моделью прав.

## Механика

Страница читается курсором из своей БД, затем `BatchCheck` батчами ≤100 на
предикат `viewer ∪ v_list` — тот же, которым гейтится `Get`, поэтому
**read == enforce**: видимый набор равен Check-allow набору.

- **Пустой субъект отсекается безусловно** — не «когда фильтр подключён».
- **Ошибка резолва** — `UNAVAILABLE` (fail-closed), не пустая и не полная страница.
- **`Get` вне гранта** → `NOT_FOUND` (hide-existence), и это обеспечивает
  per-RPC Check ([[nlb-to-iam-check]]), а не это ребро.

> [!warning] У этого List фильтр — ЕДИНСТВЕННЫЙ носитель авторизации
> Per-RPC Check остаётся на `Get`, но за `List` его нет: отката, который
> «подстрахует», не существует. Три следствия, и они не взаимозаменяемы:
> (а) пустой субъект отсекается **безусловно**; (б) ошибка резолва — **fail-closed**
> `UNAVAILABLE`, никогда не нефильтрованный список и не молча пустой; (в) состояние
> «фильтр выключен» — **долг**: метод помечается `ScopeFiltered`, production
> boot-guard отказывается стартовать без рабочего фильтра.
>
> Отдельно: любая ветка «широкий грант ⇒ отдать все строки» обязана опираться на
> отношение, которое **нельзя выполнить подстановочным субъектом**. Отношение
> уровня кластера, выполнимое `user:*`, означает «аутентифицирован», а не
> «уполномочен», и в роли выключателя фильтрации открыло бы список любому —
> `security.md` §«Отношение, выполнимое подстановочным знаком, не сужает НИЧЕГО».
> Проверять надо не наличие ветки, а то, какие tuple её выполняют.

## History

- **2026-08-02** — механизм переведён с перечисления на пакетную проверку
  страницы; число списочных методов приведено к дереву `a373c599` (6, не 3 —
  единица счёта сменилась вместе с предметом: судятся все списочные методы, а не
  только названные ровно `List`).
- Sub-phase D-consumer — первая посадка per-object фильтрации (перечислением).

## Notes

- **НЕ новое cross-service ребро**: `nlb → iam` уже существует
  ([[nlb-to-iam-check]] / [[nlb-to-iam-fga-register]]); это то же соединение.
  Цикла нет — iam не зовёт nlb обратно по этому пути.

## See also

[[compute-to-iam-listobjects]] [[vpc-to-iam-listobjects]] [[nlb-to-iam-check]]
[[api-gateway-to-iam-authorize]] [[../rpc/iam-authorize-service]]
[[../rpc/nlb-network-load-balancer-service]]
[[../KAC/rbac-rules-model-2026-subphase-D-nlb-consumer]]

#edge #kacho-nlb #cross-service #authz #fga
