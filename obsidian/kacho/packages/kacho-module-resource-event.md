---
title: "resource-event модулей kacho — строка ленты из журнала функцией базы"
aliases:
  - resource-event
  - journal.yaml модуля
category: packages
status: test
repo: kacho
layer: shared
path: pkg/feedjournal
related_tickets:
  - "[[KAC/issue-2918]]"
verified_against: "`project/kacho` @`504bc7acdc51` (голова `2914-notify`, merge-коммит PR #3098; 2026-10-08): прочитаны `services/compute/journal.yaml`, `services/compute/notifications/resource-event/notification.yaml`, `services/compute/doc.go`, шапка миграции `services/compute/internal/migrations/20261007154007_notify_feed_resource_event.sql`; у registry и storage одноимённые файлы сняты `git diff --stat dc95c1d5dc9e 504bc7acdc51`, построчно не читались; отсутствие `services/vpc/journal.yaml` снято `git ls-tree`. На `origin/main` предмета нет"
tags:
  - packages
  - kacho
  - migrations
  - go
---

# resource-event модулей kacho — строка ленты из журнала функцией базы

> [!warning] Предмет живёт в ветке эпика, а не в стволе
> Есть в kacho `2914-notify` (координата, не живая ссылка) с merge-коммита `504bc7acdc51`
> (PR [#3098](https://github.com/PRO-Robotech/kacho/pull/3098)). На `main` его нет.
> Предикат снятия врезки: `services/compute/journal.yaml` резолвится на `origin/main`.

## Что это

Уведомление о создании, правке и снятии ресурса модуля. Строку ленты модуля ставит **не
Go-код**, а функция базы с триггером на таблице журнала модуля: одна транзакция с записью
журнала, отдельного пути постановки нет. Модули с функцией на `504bc7acdc51`: compute,
registry, storage. vpc — нет (выходит одним изменением с посевом стенда, задача
[[KAC/issue-2918]]).

## Из чего собрано у модуля

| файл | роль |
|---|---|
| `services/<m>/journal.yaml` | объявление журнала: таблица, колонки, виды (`name_form`, `scope`), словарь изменений |
| `services/<m>/notifications/resource-event/` | шаблон: форма `fanout` (адресата нет), класс `notice`, закрытый список атрибутов, тела двух локалей |
| `services/<m>/internal/migrations/*_notify_feed_resource_event.sql` | функция и триггер — порождены `notifygen init -journal`, руками не правятся |
| `services/<m>/notifications_resource-event.gen.go` | Go-половина шаблона, с которой `notifygen -check` сверяет SQL-половину |
| `services/<m>/doc.go` | держит объявление пакета-владельца каталога `notifications/` |

Генератор `notifygen` — из corelib ([[KAC/issue-77-corelib]]). Функция пишет строку
только при включённом флаге ленты модуля (настройка сеанса базы, флаг —
`KACHO_<MODULE>_NOTIFICATIONS_ENABLED`, см. [[KAC/issue-2918]] S1-A4).

## Чем держится

- Объявление против Go-журнала модуля — проба `TestJournalDeclaration_AgreesWithTheJournal`
  пакета `subscriptionjournal` модуля.
- Тело функции против объявления — `notifygen -check` (отставшее тело — красный).
- Общие пробы resource-event — `pkg/feedjournal/feedjournaltest`.
- Инициатор строки берётся из колонки журнала — [[packages/corelib-journaltx]].

## History

- 2026-10-08 — #2918: записка заведена по merge-коммиту `504bc7acdc51` (PR #3098, полоса B1).

#packages #kacho #migrations #go
