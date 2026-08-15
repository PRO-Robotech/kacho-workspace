---
title: "compute → iam: сужение страницы списка пакетной проверкой"
aliases:
  - compute listobjects
  - compute fga listobjects
  - compute batchcheck
category: edge
caller_repo: kacho-compute
callee_repo: kacho-iam
sync_async: sync
protocol: gRPC
status: active
related_tickets:
  - "[[KAC-127]]"
  - "[[compute-list-leak-fix]]"
tags:
  - edge
  - kacho-compute
  - cross-service
  - authz
  - fga
---

# compute → iam: сужение страницы списка пакетной проверкой

> [!info] Имя файла — координата, а не описание
> Файл называется `…-listobjects` ради стабильности ссылок; перечислением ребро
> больше не пользуется. Та же оговорка — в [[vpc-to-iam-listobjects]].

**Caller**: `kacho-compute` — 3 списочных метода в 2 ресурсах: `instance.List`,
`instance.ListOperations`, `machine_type.List`. Последний объявлен
**cluster-scoped** (глобальный справочник типов машин).
**Callee**: `kacho-iam` `AuthorizeService.BatchCheck` ([[../rpc/iam-authorize-service]]).
**Protocol**: gRPC, sync, per-request.
**Реализация**: `services/compute/internal/authzfilter/` + `internal/handler/list_filter.go`.

> [!warning] Блочное хранение здесь БОЛЬШЕ НЕ ЛЕЖИТ
> Прежняя редакция описывала четыре публичных списка — Instance, Disk, Image,
> Snapshot — и таблицу типов `compute.disk` / `compute.image` / `compute.snapshot`.
> В дереве этого нет: у compute остались **Instance и MachineType**, а в словаре
> типов прав iam от компьюта остался единственный `compute_instance`. Владелец
> блочного хранения — `kacho-storage` ([[storage-to-iam-fgaproxy]]), его списки
> сужает свой анализатор. Дублирование, о котором предупреждала карта владельцев,
> по этой оси закрыто.

## Механика

Та же, что у [[vpc-to-iam-listobjects]], и это не «см. там» ради краткости —
контракт действительно один: страница читается курсором из своей БД, затем
`BatchCheck` батчами ≤100 на предикат `viewer ∪ v_list`. Стоимость — от страницы,
не от популяции типа.

- **Личность субъекта** берётся из принципала запроса, а не из метаданных.
- **Пустой субъект — fail-closed**, безусловно (см. History: именно здесь этот
  класс и стоил утечки).
- **Ошибка резолва** — `UNAVAILABLE`, не пустая и не полная страница.

> [!warning] Отключённый фильтр — это ДОЛГ, а не «осознанный bypass»
> У этого RPC фильтр — **единственный** носитель авторизации, его отсутствие
> ничем не компенсируется. Правильная посадка: метод помечается `ScopeFiltered`,
> production boot-guard **отказывается стартовать** без рабочего фильтра (эталон —
> [[../rpc/vpc-internal-network-interface-service]]).

## History

- **2026-08-02** — механизм переведён с перечисления на пакетную проверку
  страницы; из записки снята поверхность блочного хранения, которую compute не
  обслуживает. Дерево `a373c599`.
- **2026-06-25 — источник личности читался не оттуда, и «никто» означало «всё»**
  ([[../KAC/compute-list-leak-fix]]). Фильтр брал субъекта из метаданных, которых
  **никто не отправлял**, поэтому субъект был пуст всегда — а пустой субъект
  трактовался как «фильтровать не по чему» и снимал фильтрацию целиком. Фикс:
  субъект из принципала, пустой — fail-closed.

  **Класс (повторялся, не единичный):** «отсутствие личности» нельзя трактовать
  как «ограничивать нечего». Два признака, ловящие это заранее: (1) поле
  личности, которое **никто не производит** — у входа проверки обязан быть
  производитель, иначе проверка измеряет пустоту; (2) ветка «данных нет ⇒
  пропустить» в коде авторизации — при полной поломке она зеленеет сильнее всего.

## See also

[[vpc-to-iam-listobjects]] [[nlb-to-iam-listobjects]] [[compute-to-iam-check]]
[[compute-to-storage-volume-resolve]] [[../rpc/iam-authorize-service]]
[[../packages/corelib-authz-listobjects]] [[../KAC/KAC-127]]

#edge #kacho-compute #cross-service #authz #fga
