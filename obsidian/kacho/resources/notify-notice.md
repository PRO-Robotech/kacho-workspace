---
title: Notice (notify) — извещение оператора
aliases:
  - Notice (notify)
  - извещение оператора
  - notices
category: resource
domain: notify
id_prefix: ntc
owner_table: kacho_notify.notices
owner_db: kacho_notify
project_level: false
status: test
related_rpc: []
related_packages:
  - "[[packages/notify-service]]"
related_tickets:
  - "[[KAC/issue-2924]]"
tags:
  - resource
  - kacho
verified_against: "kacho @`515e017c873a` (голова `2914-notify` — координата, не живая ссылка; merge-коммит PR #3099, 2026-10-08), чтением через `gh api contents`: `proto/kacho/cloud/notify/v1/notice.proto` (шапка, перечни, поля `Notice`, `NoticeAudience`), `notice_service.proto` и `internal_notice_service.proto` (методы и REST-привязки), `services/notify/servesurface_ledger.go`, `gateway/internal/restmux/mux.go` (регистрация обеих служб) и `gateway/internal/allowlist/list.go` (строки `NoticeService`); каталог use-case `services/notify/internal/apps/kacho/api/` снят `git/trees`. Тела use-case построчно не читались; прогоны мной не перезапускались"
---

# Notice (notify) — извещение оператора

> [!warning] Предмет живёт в ветке эпика, а не в стволе
> Контракт есть в `2914-notify` (координата, не живая ссылка) с merge-коммита
> `515e017c873a` (#3099). На `main` его нет, поэтому статус — `test`. Предикат снятия
> оговорки: `proto/kacho/cloud/notify/v1/notice.proto` резолвится на `origin/main`.

Извещение — запись обязательства оператора перед арендаторами о событии, которое меняет их
ресурсы или отношения с оператором без их участия. Создаёт и ведёт его только оператор;
арендатор читает извещения своих аккаунтов и проектов. Удаления нет: завершённое или
отменённое извещение снимается по сроку хранения. Введено задачей [[KAC/issue-2924]]
(NTF-5): схема — #3070, контракт и служба — #3099.

## Ресурс

- `id` — `ntc-` и 17 символов crockford base32, неизменяем.
- `kind` — закрытый перечень: `MAINTENANCE`, `OUTAGE`, `DECOMMISSION`, `SUSPENSION`,
  `SECURITY_INCIDENT`, `TERMS_CHANGE`. Вид задаёт обязательные поля и начальное
  состояние и после создания не меняется.
- `category` — только выход, выводится из вида: `OPERATIONS`, `ACCOUNT_LEGAL` либо
  `SECURITY`.
- `state` — `SCHEDULED → IN_PROGRESS → COMPLETED` и `SCHEDULED → CANCELLED`; иных переходов
  нет.
- Аудитория — ровно одна форма из трёх: все аккаунты, перечень аккаунтов или перечень
  проектов (1…100). После создания не меняется; форма «все аккаунты» для `SUSPENSION`
  запрещена.

Две проекции — два сообщения. Публичная `Notice` не несёт аудитории, автора, напоминаний и
счётчиков доставки. Внутренняя `InternalNotice` несёт их.

## Службы

| служба | методы | REST | край |
|---|---|---|---|
| `NoticeService` | `List`, `ListByAccount`, `Get`, `GetByAccount` — sync, чтение | `/notify/v1/notices…` | внешний и внутренний mux |
| `InternalNoticeService` | `Create`, `Update`, `Start`, `Complete`, `Cancel` → `Operation`; `Get`, `List` — sync | `/notify/v1/internal/notices…` | только внутренний mux |

Обе службы обслуживает один корень — `cmd/notify-api` ([[packages/notify-service]]); там же
`corelib.operation.OperationService`. Край ходит к обеим по одному внутреннему адресу
notify; если адрес в установке не объявлен, маршрута нет вовсе. Право на чтение
`NoticeService` судит use-case службы, а не край. Отдельных записок в `rpc/` о двух службах
нет — методы описаны здесь.

## Хранение

Таблица `notices` и шесть соседних таблиц стадии S1 — цепочка `kacho_notify`, миграция
`20261006232858_operator_notices.sql` (#3070); операции — `20261007120000_operations.sql`
(#3099). Состав схемы — в [[packages/notify-service]], раздел «Схема извещений оператора
(S1)».

## Чего на этой ревизии нет

Стадии S2 (адресаты, исходы областей, окно OB) и доставки извещения письмом и в ленту
консоли на `515e017c873a` нет — DoD задачи, [[KAC/issue-2924]].

## History

- 2026-10-08 — #2924: записка заведена по merge-коммиту `515e017c873a` (PR #3099 в
  `2914-notify`).

#resource #kacho
