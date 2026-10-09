---
title: "corelib/journaltx — инициатор в журнале ресурсов модулей"
aliases:
  - journaltx
  - журнал ресурсов — инициатор
category: packages
repo: kacho-corelib
path: journaltx
layer: shared
status: test
related_tickets:
  - "[[KAC/issue-2918]]"
verified_against: "corelib @`9e358e61e28d` (голова `77-notify` — координата, не живая ссылка; 2026-10-05): прочитана шапка и экспорт `journaltx/journaltx.go`. kacho @`4517cc69c135` (голова `2914-notify`): прочитаны миграция `services/storage/internal/migrations/20261004170000_journal_initiator.sql`, шапка и таблица пар `internal/repohygiene/journaledwrites.go`, шапки `pkg/journalfault/journalfault.go` и `services/registry/internal/dataplane/initiator.go`; одноимённая миграция у пяти модулей снята `git ls-tree`. kaname @`db080041cd95` (голова `484-notify`): `internal/journalwrite/journalwrite.go` открывает транзакцию через `journaltx.Begin`. Миграции четырёх модулей, кроме storage, построчно не читались"
tags:
  - packages
  - kacho-corelib
  - migrations
  - go
---

# corelib/journaltx — инициатор в журнале ресурсов модулей

> [!warning] Предмет живёт в ветках эпиков, а не в стволе
> Пакет есть в corelib `77-notify`, его потребители — в kacho `2914-notify` и kaname
> `484-notify` (координаты, не живые ссылки). На `main` трёх репозиториев их нет, поэтому
> статус — `test`. Предикат снятия оговорки: `journaltx/journaltx.go` резолвится на
> `origin/main` corelib, а миграция `*_journal_initiator.sql` — на `origin/main` kacho.

Каждая строка журнала ресурсов модуля несёт **инициатора** изменения. Журнал — таблица
`<модуль>_outbox` у compute, nlb, storage, vpc и `registry_resource_journal` у registry. Строки без инициатора база
не принимает. Предмет введён задачей [[KAC/issue-2918]] (волна модули-1).

## Как значение попадает в строку

- **Производитель один — умолчание колонки.** Колонка `initiator text NOT NULL` с
  умолчанием из настройки транзакции `kacho_journal.initiator`. Оператор вставки колонку не
  называет — ни на Go, ни в функциях базы, пишущих журнал; поэтому эти функции миграцией не
  пересобираются.
- **Настройку выставляет только `journaltx.Begin`** — первым оператором транзакции,
  **локально** к ней (`set_config(…, true)`). Источник — принципал контекста, переведённый
  `auth.InitiatorOf`. Сессионная настройка запрещена: соединение вернётся в пул, и
  инициатор стал бы чужим.
- **Отсутствие — отказ, а не подстановка.** Без принципала либо с нулевыми `Options`
  транзакция не открывается; если строка всё же дошла до базы без настройки, `NOT NULL`
  откатывает изменение ресурса вместе с ней.
- **Форма — ограничение `<таблица>_initiator_form`**: три типа субъекта — `user:` с
  приставкой пользователя, `service_account:` с приставкой сервисного аккаунта, `system:` с
  именем компонента формы DNS-метки.
- **Время строки** — прежняя колонка `created_at`; новой колонки времени нет.

`journaltx` несёт ещё вторую локальную настройку — флаг ленты модуля
(`kacho_feed.enabled`), который читает функция базы resource-event.

## Кто пишет и под чьим именем

| путь | инициатор |
|---|---|
| запрос с принципалом (RPC модуля) | `user:…` либо `service_account:…` из контекста |
| фоновый путь модуля | `system:<служба>-<роль>` через `journaltx.AsComponent` — только пары таблицы `JournaledComponentPairs` (решение Д116): storage/reconciler, nlb/free-ip-runner, nlb/target-drain-runner, registry/orphan-sweep |
| запись data-plane registry (docker push) | `sub` **проверенного** токена реестра (Д115); нет проверенного `sub` — отказ, не `system` |
| посев стенда vpc (`deploy/scripts`) | `system:stand-seed` той же локальной настройкой |
| посев модулей kaname | `system:kaname-seed` (Д122) |

## Модули

В kacho — пять модулей с журналом: compute, nlb, registry, storage, vpc; у каждого
миграция `services/<модуль>/internal/migrations/20261004170000_journal_initiator.sql`.
Миграция на непустом журнале отказывает: стенды поднимаются заново (прода нет).

В kaname журнал службы доступа получил ту же колонку своей миграцией
(`20261004160000_resource_journal_carries_the_initiator.sql`); пишущие транзакции
открываются через `internal/journalwrite`, а тот — через `journaltx.Begin`.

## Что держит

- Гейт kacho `internal/repohygiene/journaledwrites.go` (УК3-27) — пять правил: транзакция
  записи мимо помощника; автокоммитная запись в журналируемую таблицу; вставка, называющая
  колонку `initiator`; сессионная установка настройки; вызов `AsComponent` вне таблицы пар
  либо пара без ровно одного вызова. Законный близнец —
  `TestJournaledWritesGateIsSilentOnTheLawfulStand`.
- Гейт kaname `internal/check/write_tx_opener.go` — тот же предмет для службы доступа.
- `pkg/journalfault` (kacho) — отказ базы по инициатору (`23502` по колонке, `23514` по
  ограничению формы) уходит наружу **внутренним** отказом: вызывающий значения не передаёт
  и виноват в нём быть не может.
- Пробы приёмки NTF-3: NTF3-57, NTF3-58, NTF3-62, NTF3-63 (kaname), УК3-28; инициатор привязки
  и отвязки тома storage и снятия машины compute — NTF3-160 (г), (з), УК3-32, УК3-39 (kacho #3119).

## Связи

- [[KAC/issue-2918]] — задача; состав волны и PR.
- [[packages/corelib-outbox]] — запись намерения той же транзакцией.
- [[packages/corelib-subscription]] — поток изменений, читающий журнал.
- [[packages/notify-service]] — шлюз уведомлений, конечный потребитель ленты.

## History

- 2026-10-05 — записка заведена после вливания волны модули-1 (#2918): kacho #3027
  (`4517cc69c135`), corelib #89 и #92 (`9e358e61e28d`), kaname #605 и #616
  (`db080041cd95`).
- 2026-10-09 — #2918: kacho #3119 (`e6075f09c261`, в `2914-notify`) добавил пробы инициатора
  привязки тома и снятия машины; механизм помощника не менялся (`git diff --stat` слияния —
  только тесты, шлюз и `go.mod`).

#packages #kacho-corelib #migrations #go
