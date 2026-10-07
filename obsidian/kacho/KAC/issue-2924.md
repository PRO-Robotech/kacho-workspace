---
title: "kacho#2924: notify NTF-5 — извещения оператора"
aliases:
  - issue-2924
  - NTF-5
ticket_id: 2924
category: kac
status: in-progress
verified_against: "`gh` 2026-10-07: kacho PR #3070 MERGED в `2914-notify` 2026-10-07T12:38Z merge-коммитом 4d5295f1ae96 (голова волны `2924-wave-f1` e3f4cb0949f9, база 829e1a26cb18), голова `2914-notify` = 4d5295f1ae96; ветки `2924-wave-f1` и `2924-n1-notice-schema` на origin сняты (`git ls-remote` пусто); corelib PR #98 MERGED в `77-notify` (d3c964ae6fa7); задача #2924 и эпик #2914 OPEN. Состав миграции снят `git show 4d5295f1ae96:services/notify/internal/migrations/20261006232858_operator_notices.sql`; прогоны мной не перезапускались"
type: feature
repos:
  - kacho
  - corelib
areas:
  - services/notify
  - internal/repohygiene
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3070
  - https://github.com/PRO-Robotech/corelib/pull/98
issue_url: https://github.com/PRO-Robotech/kacho/issues/2924
opened: 2026-09-29
closed:
tags:
  - kac
  - feature
---

# kacho#2924: notify NTF-5 — извещения оператора

**Состояние на момент записи**: `in-progress`. Первая волна линии F (стадия S1, схема)
влита в ветку эпика `2914-notify` (координата, не живая ссылка); в `main` не влито ничего.
Статус `done` записке не положен до посадки эпика в `main`.

**Эпик:** [[KAC/issue-2914]]. **Блокеры из тела:** #2915,
PRO-Robotech/kacho-workspace#880. **Роль исполнителя:** `go-implementer`.

## Что и зачем

Ресурса «извещение оператора» в контракте нет, и оператору нечем известить аккаунты о
работах, авариях и выводе из эксплуатации. Предмет — ресурс «извещение» с жизненным
циклом «запланировано → идёт → завершено», класс OB (обязательный, не отключается).
Создаёт и ведёт извещение только оператор, арендатор читает извещения своих аккаунтов.
Доставка — лента консоли и почта через notify. Полный объём — в теле задачи.

## Документы

- Приёмка: `docs/specs/sub-phase-NTF-5-operator-notices-acceptance.md` (воркспейс). На
  `origin/main` воркспейса 2026-10-07 её нет; она лежит в ветке `issue-880` (координата,
  не живая ссылка). Шапка миграции волны ссылается на редакцию 20. Предикат снятия
  оговорки: путь резолвится на `origin/main` воркспейса.

## Волна F1 (стадия S1, схема)

| репозиторий | ветка эпика | PR | merge-коммит | состав |
|---|---|---|---|---|
| corelib | `77-notify` | [#98](https://github.com/PRO-Robotech/corelib/pull/98) | `d3c964ae6fa7` | F-C5: obligation в `notify/spec`, лента V3, ядро взятия и исхода (в одной волне def2 с E-X3 задачи [[KAC/issue-2919]]) |
| kacho | `2914-notify` | [#3070](https://github.com/PRO-Robotech/kacho/pull/3070) | `4d5295f1ae96` | F-N1 и подъём lock-файлов сайтов документации (#3044) |

Состав kacho #3070 (влит 2026-10-07T12:38Z), из описания PR и `git diff --stat
829e1a26cb18 4d5295f1ae96` (21 файл, +1146 / −126):

- **F-N1** — миграция `20261006232858_operator_notices.sql` цепочки `kacho_notify`: семь
  таблиц стадии S1 (заявки создания, извещения, аудитория, затронутые ресурсы,
  напоминания, события этапа, счётчики исходов). Инварианты — на уровне базы, ограничения
  названы. Пробы схемы — `notices_schema_integration_test.go`; пакет миграций внесён в
  отбор шага `test-pg-outside-selection`, строка в `docs/acceptance-ledger.yaml`.
- **#3044** — подъём lock-файлов семи сайтов документации, перенесённый с ветки
  эпика-источника.

Чего в волне нет, по шапке миграции: строк адресатов, кандидатов, исходов областей и окна
OB (стадия S2, отдельная миграция), API извещений и края. Схема — в
[[packages/notify-service]].

## DoD (из тела задачи)

Предикат задачи — сценарии приёмки NTF-5 зелёные исполненными пробами. Артефакт — PR в
ветку эпика.

- [x] стадия S1, схема извещений, влита в `2914-notify` (#3070), ядро ленты F-C5 — в
  `77-notify` (corelib #98);
- [ ] стадия S2: адресаты, исходы областей, окно OB;
- [ ] ресурс в контракте `proto/kacho/cloud/`, край в `gateway/`, доставка через notify;
- [ ] сценарии приёмки NTF-5 зелёные исполненными пробами;
- [ ] эпик #2914 посажен в `main` (только после этого статус записки — `done`).

## Связанные задачи

- [[KAC/issue-2914]] — эпик «Сервис уведомлений».
- [[KAC/issue-2915]] — NTF-1, ядро шлюза; блокер из тела.
- https://github.com/PRO-Robotech/kacho/issues/3044 — подъём lock-файлов сайтов
  документации (CLOSED), ушёл в эту же волну.
- https://github.com/PRO-Robotech/corelib/issues/77 — линия corelib эпика. Trail — [[KAC/issue-77-corelib]].
- https://github.com/PRO-Robotech/kacho-workspace/issues/880 — блокер из тела.

## History

- 2026-10-07 — trail заведён после вливания волны F1: kacho #3070 (`4d5295f1ae96`) в
  `2914-notify`, corelib #98 (F-C5, `d3c964ae6fa7`) в `77-notify`. Статус `in-progress`.

## Затронутые сущности vault

- [[packages/notify-service]] — раздел «Схема извещений оператора (S1)», вторая строка
  таблицы цепочек.
- Записки ресурса «извещение» в `resources/` нет: на `4d5295f1ae96` ресурса в контракте
  `proto/` нет, есть только схема. Записка заводится вместе с контрактом.

#kac #feature
