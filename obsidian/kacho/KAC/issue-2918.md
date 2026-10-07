---
title: "kacho#2918: notify NTF-3 — модули kacho, уведомления о событиях ресурсов"
aliases:
  - issue-2918
  - NTF-3
ticket_id: 2918
category: kac
status: in-progress
verified_against: "`gh` 2026-10-07: kacho PR #3042 MERGED в `2914-notify` 2026-10-06T01:44Z merge-коммитом 829e1a26cb18 (голова ветки `2918-kinds-flag` a799636c82c); kaname PR #632 MERGED в `484-notify` 2026-10-07T02:15Z (22b70ea5d0a7, голова волны 6e32861e021a), голова `484-notify` = 22b70ea5d0a7; corelib #95 (e7d6197fc5dc) и #96 (bdb379942934) MERGED в `77-notify`, голова = 1e6ade53645a; голова `2914-notify` = 4d5295f1ae96; задача #2918 и эпик #2914 OPEN; путь приёмки снят `git ls-tree origin/issue-880 docs/specs/` воркспейса; состав — со слов описаний PR, прогоны мной не перезапускались. `gh` 2026-10-05: kacho PR #3027 MERGED в `2914-notify` merge-коммитом 4517cc69c135 (голова волны 53c14dec394d), голова `2914-notify` = 4517cc69c135; corelib #89 MERGED в `77-notify` (fd6d603b52ca), запись реестра исключений снята #92, голова `77-notify` = 9e358e61e28d; kaname #605 (745640d6c296), #611 (c1b397b735d5), #616 (db080041cd95) MERGED в `484-notify`, голова = db080041cd95; задача #2918 и эпик #2914 OPEN. Пути журнала и справочника сняты `git ls-tree` на 4517cc69c135 и db080041cd95; прогоны мной не перезапускались"
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
  - https://github.com/PRO-Robotech/kacho/pull/3042
  - https://github.com/PRO-Robotech/corelib/pull/89
  - https://github.com/PRO-Robotech/corelib/pull/92
  - https://github.com/PRO-Robotech/corelib/pull/95
  - https://github.com/PRO-Robotech/corelib/pull/96
  - https://github.com/PRO-Robotech/kaname/pull/605
  - https://github.com/PRO-Robotech/kaname/pull/611
  - https://github.com/PRO-Robotech/kaname/pull/616
  - https://github.com/PRO-Robotech/kaname/pull/632
issue_url: https://github.com/PRO-Robotech/kacho/issues/2918
opened: 2026-09-29
closed:
tags:
  - kac
  - feature
---

# kacho#2918: notify NTF-3 — модули kacho, уведомления о событиях ресурсов

**Состояние на момент записи**: `in-progress`. Две волны задачи (модули-1 и модули-2) и
волна ограды аудитории kaname влиты в ветки эпиков трёх репозиториев; в `main` не влито
ничего. Задача открыта: влит фундамент (инициатор в журнале, справочник адресов, виды
журналов, флаг ленты модуля, ограда аудитории), сами уведомления модулей и перепись
«подключается / не подключается» ещё впереди. Статус `done` записке не положен
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
  2026-10-07 нет ни одного из двух путей; в ветке `docs-ntf-approved` (координата, не
  живая ссылка) приёмки NTF-3 тоже нет. Второе имя лежит в ветке `issue-880` (координата,
  не живая ссылка) — сверено 2026-10-07. Предикат снятия оговорки: путь приёмки резолвится
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

## Волна модули-2 и предметы рядом

| репозиторий | ветка эпика | PR | merge-коммит | состав |
|---|---|---|---|---|
| corelib | `77-notify` | [#95](https://github.com/PRO-Robotech/corelib/pull/95) | `e7d6197fc5dc` | флаг ленты в самоотчёте (`notifications_enabled`), серия `kacho_notifications_enabled{module}` и при 0 |
| corelib | `77-notify` | [#96](https://github.com/PRO-Robotech/corelib/pull/96) | `bdb379942934` | Д120: запись resource-event реестра исключений возвращена — полоса kacho с функциями resource-event садится после неё |
| kacho | `2914-notify` | [#3042](https://github.com/PRO-Robotech/kacho/pull/3042) | `829e1a26cb18` | модули-2: S1-A3, S1-A4, S1-A7 (ниже) |
| kaname | `484-notify` | [#632](https://github.com/PRO-Robotech/kaname/pull/632) | `22b70ea5d0a7` | волна fence: K1 — версия прав `authz_rev` на путевых таблицах, токен `CurrentAuthzRevision`, ограда аудитории в гигиене репозитория (Д133/Д134) |

Состав kacho #3042 (влит 2026-10-06T01:44Z), из описания PR:

- **S1-A3** — новые виды журналов, `NameForm` и `Scope` видов; снятие балансировщика и
  группы целей nlb несёт имя из `RETURNING`; страница подписки называет четыре новых вида
  (Д127).
- **S1-A4** — флаг модуля `KACHO_<MODULE>_NOTIFICATIONS_ENABLED`: загрузчик без умолчания,
  самоотчёт посадки и серия флага — через corelib; флаг ленты пяти модулей подаётся
  зонтиком из одного объявления.
- **S1-A7** — эмиттер nlb через функцию фундамента с дескриптором, личность компонента на
  проводе.
- Прямые коммиты ветки: сужатель потока модулей спрашивает о строке ленты отношение
  `reader`; пин corelib `e7d6197f`, kaname `cbd729cf`; догон `2914-notify` после #3041.

## DoD (из тела задачи)

Предикат задачи — сценарии приёмки NTF-3 зелёные; перепись модулей в приёмке сходится с
деревом. Артефакт — PR в ветку эпика.

- [x] волна модули-1 — фундамент журнала и справочника — влита в ветки эпиков corelib,
  kaname, kacho (#89, #92, #605, #611, #616, #3027);
- [x] волна модули-2 — виды журналов, флаг модуля, эмиттер nlb — влита в `2914-notify`
  (#3042); ограда аудитории K1 — в `484-notify` (kaname #632);
- [ ] модули, которые шлют уведомления, ставят их в свою ленту; шаблоны и строки права;
- [ ] модули без уведомлений помечены «не подключается»;
- [ ] отложенные в приёмках уведомления получили предмет либо сняты;
- [ ] сценарии приёмки NTF-3 зелёные исполненными пробами;
- [ ] эпик #2914 посажен в `main` (только после этого статус записки — `done`).

## Связанные задачи

- [[KAC/issue-2915]] — NTF-1, ядро шлюза уведомлений; блокер из тела.
- [[KAC/issue-2914]] — эпик «Сервис уведомлений».
- https://github.com/PRO-Robotech/corelib/issues/77 — линия corelib эпика: лента, формат шаблона, `notifygen`. Trail — [[KAC/issue-77-corelib]].
- https://github.com/PRO-Robotech/kaname/issues/484 — линия kaname эпика: нотификации kaname в ленту, снятие SMTP. Trail — [[KAC/issue-484-kaname]].
- https://github.com/PRO-Robotech/kacho-workspace/issues/880 — блокер из тела.

## History

- 2026-10-05 — trail заведён после вливания волны модули-1: kacho #3027 (`4517cc69c135`)
  в `2914-notify`, corelib #89 и #92 в `77-notify`, kaname #605, #611, #616 в
  `484-notify`. Статус `in-progress`.
- 2026-10-07 — внесены волна модули-2 (#3042, `829e1a26cb18`, влита 2026-10-06), corelib
  #95 и #96, kaname #632 (K1, `22b70ea5d0a7`); место приёмки уточнено. Статус
  `in-progress`.

## Затронутые сущности vault

- [[packages/corelib-journaltx]] — инициатор в журнале ресурсов модулей kacho: помощник
  транзакции, колонка, гейт, таблица фоновых путей.
- [[rpc/kaname-internal-notification-recipient-service]] — справочник адресов kaname.
- Ребра notify → kaname (справочник) в vault нет: на `4517cc69c135` контракт справочника
  в kacho называют только каталог прав края и гейты, вызывающего кода в `services/notify`
  нет. Запись ребра заводится вместе с первым вызовом.

#kac #feature
