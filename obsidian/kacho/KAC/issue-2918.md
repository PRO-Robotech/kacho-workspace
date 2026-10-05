---
title: "kacho#2918: notify NTF-3 — модули kacho, уведомления о событиях ресурсов"
aliases:
  - issue-2918
  - NTF-3
ticket_id: 2918
category: kac
status: in-progress
verified_against: "`gh` 2026-10-05: kacho PR #3027 MERGED в `2914-notify` merge-коммитом 4517cc69c135 (голова волны 53c14dec394d), голова `2914-notify` = 4517cc69c135; corelib #89 MERGED в `77-notify` (fd6d603b52ca), запись реестра исключений снята #92, голова `77-notify` = 9e358e61e28d; kaname #605 (745640d6c296), #611 (c1b397b735d5), #616 (db080041cd95) MERGED в `484-notify`, голова = db080041cd95; задача #2918 и эпик #2914 OPEN. Пути журнала и справочника сняты `git ls-tree` на 4517cc69c135 и db080041cd95; прогоны мной не перезапускались"
type: feature
repos:
  - kacho
  - corelib
  - kaname
areas:
  - services/compute
  - services/nlb
  - services/registry
  - services/storage
  - services/vpc
  - internal/repohygiene
  - pkg/journalfault
  - deploy/scripts
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3027
  - https://github.com/PRO-Robotech/corelib/pull/89
  - https://github.com/PRO-Robotech/corelib/pull/92
  - https://github.com/PRO-Robotech/kaname/pull/605
  - https://github.com/PRO-Robotech/kaname/pull/611
  - https://github.com/PRO-Robotech/kaname/pull/616
issue_url: https://github.com/PRO-Robotech/kacho/issues/2918
opened: 2026-09-29
closed:
tags:
  - kac
  - feature
---

# kacho#2918: notify NTF-3 — модули kacho, уведомления о событиях ресурсов

**Состояние на момент записи**: `in-progress`. Первая волна задачи (модули-1, пилот Д114)
влита в ветки эпиков трёх репозиториев; в `main` не влито ничего. Задача открыта: волна
модули-1 — фундамент (инициатор в журнале, справочник адресов), сами уведомления модулей
и перепись «подключается / не подключается» ещё впереди. Статус `done` записке не положен
до посадки эпика в `main`.

**Эпик:** https://github.com/PRO-Robotech/kacho/issues/2914. **Блокеры из тела:** #2915,
PRO-Robotech/kacho-workspace#880. **Роль исполнителя:** `go-implementer`.

## Что и зачем

Ни одна служба kacho уведомлений не шлёт, а приёмки воркспейса откладывают их до появления
канала. Предмет — перепись модулей kacho: модуль с нотификациями ставит их в свою ленту
(`corelib notify/feed`, адресат — субъект, адрес — из справочника kaname), шаблоны лежат в
`<owner>/notifications/`, право — строкой манифеста; модуль без нотификаций помечен «не
подключается», без заглушек. Полный объём — в теле задачи.

## Документы

- Приёмка: `docs/specs/sub-phase-NTF-3-kacho-modules-acceptance.md` (воркспейс; так её
  называет тело задачи, шапки миграций волны пишут
  `sub-phase-NTF-3-kacho-modules-notifications-acceptance.md`). На `origin/main` воркспейса
  2026-10-05 нет ни одного из двух путей; в ветке `docs-ntf-approved` (координата, не
  живая ссылка) приёмки NTF-3 тоже нет. Предикат снятия оговорки: путь приёмки резолвится
  на `origin/main` воркспейса — тогда здесь остаётся одно имя.
- Одобренная редакция, по которой шла волна corelib, — отпечаток `ac1f9fc9…` (со слов
  описания corelib #89).

## Волна модули-1 (пилот Д114)

| репозиторий | ветка эпика | PR | merge-коммит | состав |
|---|---|---|---|---|
| corelib | `77-notify` | [#89](https://github.com/PRO-Robotech/corelib/pull/89) | `fd6d603b52ca` | X2 (формы адресата ленты), X2-F (функция resource-event формы fanout) |
| corelib | `77-notify` | [#92](https://github.com/PRO-Robotech/corelib/pull/92) | `9e358e61e28d` | Д120: запись реестра исключений resource-event снята до появления предмета |
| kaname | `484-notify` | [#605](https://github.com/PRO-Robotech/kaname/pull/605) | `745640d6c296` | X4J (журнал несёт инициатора и время, NTF3-63), X4D (справочник адресов) |
| kaname | `484-notify` | [#611](https://github.com/PRO-Robotech/kaname/pull/611) | `c1b397b735d5` | Д121: чтения справочника — полоса acr «1»; перепин corelib `9e358e61e28d` |
| kaname | `484-notify` | [#616](https://github.com/PRO-Robotech/kaname/pull/616) | `db080041cd95` | Д122: посев модулей пишет журнал под `system:kaname-seed` |
| kacho | `2914-notify` | [#3027](https://github.com/PRO-Robotech/kacho/pull/3027) | `4517cc69c135` | S1-A1, S1-A8, S1-A2 (ниже) |

Ветки эпиков — координаты, не живые ссылки.

Состав kacho #3027 (голова волны `53c14dec394d`, влита 2026-10-05T06:13Z), из описания PR:

- **S1-A1** — журнал пяти модулей (compute, nlb, registry, storage, vpc) несёт инициатора:
  колонка `initiator` миграцией `20261004170000_journal_initiator.sql` каждого модуля;
  пробы NTF3-62 и УК3-28.
- **S1-A8** — посев стенда пишет журнал vpc под инициатором `system:stand-seed`.
- **S1-A2** — пишущие транзакции пяти модулей открываются помощником `corelib/journaltx`;
  фоновые пути — личностью компонента по таблице пар (Д116); инициатор записи docker push
  в registry берётся из проверенного токена (Д115); пробы NTF3-57, NTF3-58, гейт УК3-27.
- Прямые коммиты ветки волны: перепины corelib и kaname (последний — kaname
  `db080041cd95`, образ `484-notify-db080041`), отказ журнала по инициатору как внутренний
  отказ (`pkg/journalfault`), близнец гейта писателей ленты под Д120.
- Дельта к `2914-notify`: 302 файла, +9812 / −1084 (`git diff --stat 230c0812425
  4517cc69c135` — совпадает с описанием). Вердикт посадки: merge-readiness код 0, 42 из 42
  обязательных контекстов зелёные — со слов комментария вливания в задаче; мной не
  перепрогонялось.

Механизм — в узких записках, здесь не пересказывается: [[packages/corelib-journaltx]] и
[[rpc/kaname-internal-notification-recipient-service]].

## DoD (из тела задачи)

Предикат задачи — сценарии приёмки NTF-3 зелёные; перепись модулей в приёмке сходится с
деревом. Артефакт — PR в ветку эпика.

- [x] волна модули-1 — фундамент журнала и справочника — влита в ветки эпиков corelib,
  kaname, kacho (#89, #92, #605, #611, #616, #3027);
- [ ] модули, которые шлют уведомления, ставят их в свою ленту; шаблоны и строки права;
- [ ] модули без уведомлений помечены «не подключается»;
- [ ] отложенные в приёмках уведомления получили предмет либо сняты;
- [ ] сценарии приёмки NTF-3 зелёные исполненными пробами;
- [ ] эпик #2914 посажен в `main` (только после этого статус записки — `done`).

## Связанные задачи

- [[KAC/issue-2915]] — NTF-1, ядро шлюза уведомлений; блокер из тела.
- https://github.com/PRO-Robotech/kacho/issues/2914 — эпик «Сервис уведомлений».
- https://github.com/PRO-Robotech/corelib/issues/77 — линия corelib эпика: лента, формат шаблона, `notifygen`.
- https://github.com/PRO-Robotech/kaname/issues/484 — линия kaname эпика: нотификации kaname в ленту, снятие SMTP.
- https://github.com/PRO-Robotech/kacho-workspace/issues/880 — блокер из тела.

## History

- 2026-10-05 — trail заведён после вливания волны модули-1: kacho #3027 (`4517cc69c135`)
  в `2914-notify`, corelib #89 и #92 в `77-notify`, kaname #605, #611, #616 в
  `484-notify`. Статус `in-progress`.

## Затронутые сущности vault

- [[packages/corelib-journaltx]] — инициатор в журнале ресурсов модулей kacho: помощник
  транзакции, колонка, гейт, таблица фоновых путей.
- [[rpc/kaname-internal-notification-recipient-service]] — справочник адресов kaname.
- Ребра notify → kaname (справочник) в vault нет: на `4517cc69c135` контракт справочника
  в kacho называют только каталог прав края и гейты, вызывающего кода в `services/notify`
  нет. Запись ребра заводится вместе с первым вызовом.

#kac #feature
