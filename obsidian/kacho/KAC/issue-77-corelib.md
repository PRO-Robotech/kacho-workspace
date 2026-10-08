---
title: "corelib#77: линия corelib эпика notify — лента, формат шаблона, notifygen"
aliases:
  - issue-77-corelib
ticket_id: 77
category: kac
status: in-progress
verified_against: "`gh` 2026-10-08: пин kacho на голове `2914-notify` 504bc7acdc51 прочитан в `go.mod`, отставание головы ветки посчитано `gh api compare`. `gh` 2026-10-07: `gh pr list -R PRO-Robotech/corelib --base 77-notify --state all` — 13 PR MERGED (#82…#102), открытых 0; голова `77-notify` = 117749095814 (merge-коммит #102, родители 1e6ade53645a и 18d105d0f50a); `git diff 18d105d0f50a origin/77-notify` пуст; задача corelib#77 и эпик kacho#2914 OPEN; в `main` corelib из ветки эпика не влито ничего. Состав PR — со слов их заголовков и описаний; прогоны мной не перезапускались"
type: feature
repos:
  - corelib
areas:
  - notify/feed
  - notify/spec
  - cmd/notifygen
prs:
  - https://github.com/PRO-Robotech/corelib/pull/82
  - https://github.com/PRO-Robotech/corelib/pull/83
  - https://github.com/PRO-Robotech/corelib/pull/87
  - https://github.com/PRO-Robotech/corelib/pull/88
  - https://github.com/PRO-Robotech/corelib/pull/89
  - https://github.com/PRO-Robotech/corelib/pull/92
  - https://github.com/PRO-Robotech/corelib/pull/93
  - https://github.com/PRO-Robotech/corelib/pull/95
  - https://github.com/PRO-Robotech/corelib/pull/96
  - https://github.com/PRO-Robotech/corelib/pull/98
  - https://github.com/PRO-Robotech/corelib/pull/99
  - https://github.com/PRO-Robotech/corelib/pull/100
  - https://github.com/PRO-Robotech/corelib/pull/102
issue_url: https://github.com/PRO-Robotech/corelib/issues/77
opened: 2026-09-29
closed:
tags:
  - kac
  - kacho-corelib
  - feature
---

# corelib#77: линия corelib эпика notify

**Состояние на момент записи**: `in-progress`. Все PR линии идут в ветку эпика corelib
`77-notify` (координата, не живая ссылка), а не в `main`; задача открыта — PR несут `Refs`,
не `Closes`. По каскаду «задача → волна → эпик → main» `done` записке не положен до посадки
эпика в `main`.

**Эпик:** [[KAC/issue-2914]]. **Блокер из тела:** PRO-Robotech/kacho-workspace#880.
**Роль исполнителя:** `go-implementer`.

> [!note] Осей меток в этом трекере нет
> Приоритет, размер и релизная линия у задач фундамента проставить нечем.

## Что и зачем

Общий фундамент постановки письма для всех отправителей: запись в ленту в транзакции
источника, формат шаблона с единым валидатором и генератор `notifygen`. Предикат из тела —
сценарии раздела «corelib» приёмки NTF-1 зелёные и выпущен тег corelib, на который встают kacho
и kaname. Подробности требований — в теле задачи, здесь не пересказываются.

## PR в `77-notify`

| PR | merge-коммит | влит (UTC) | предмет (по заголовку) | линия kacho |
|---|---|---|---|---|
| [#82](https://github.com/PRO-Robotech/corelib/pull/82) | `1a37f81d0e94` | 2026-10-01 | platformmodules: служба notify | — |
| [#83](https://github.com/PRO-Robotech/corelib/pull/83) | `fe0dccf1794e` | 2026-10-02 | platformmodules и окно отзыва (C13a) | [[KAC/issue-2915]] |
| [#87](https://github.com/PRO-Robotech/corelib/pull/87) | `f8aa88d1998d` | 2026-10-03 | догон `main` после посадки Ory | [[KAC/issue-2915]] |
| [#88](https://github.com/PRO-Robotech/corelib/pull/88) | `21c784a9b1dc` | 2026-10-04 | запись в ленту возвращает идентификатор строки (Д109) | — |
| [#89](https://github.com/PRO-Robotech/corelib/pull/89) | `fd6d603b52ca` | 2026-10-04 | волна модули-1: X2, X2F | [[KAC/issue-2918]] |
| [#92](https://github.com/PRO-Robotech/corelib/pull/92) | `9e358e61e28d` | 2026-10-04 | реестр исключений: запись resource-event (Д120) | [[KAC/issue-2918]] |
| [#93](https://github.com/PRO-Robotech/corelib/pull/93) | `103560afe541` | 2026-10-05 | servicehost: форма «только внутренний слушатель» (волна F) | — |
| [#95](https://github.com/PRO-Robotech/corelib/pull/95) | `e7d6197fc5dc` | 2026-10-05 | флаг ленты в самоотчёте, серия при 0 | [[KAC/issue-2915]], [[KAC/issue-2918]] |
| [#96](https://github.com/PRO-Robotech/corelib/pull/96) | `bdb379942934` | 2026-10-06 | реестр исключений: возврат записи resource-event (Д120) | [[KAC/issue-2918]] |
| [#98](https://github.com/PRO-Robotech/corelib/pull/98) | `d3c964ae6fa7` | 2026-10-06 | волна def2: E-X3 исход SUPPRESSED, F-C5 obligation ленты | [[KAC/issue-2919]], [[KAC/issue-2924]] |
| [#99](https://github.com/PRO-Robotech/corelib/pull/99) | `67ba3443c149` | 2026-10-06 | `feed.TablesOf`: способ узнать таблицы ленты | [[KAC/issue-2917]] |
| [#100](https://github.com/PRO-Robotech/corelib/pull/100) | `1e6ade53645a` | 2026-10-07 | манифест модуля доставляется только включившим цепочкам | [[KAC/issue-2915]] |
| [#102](https://github.com/PRO-Robotech/corelib/pull/102) | `117749095814` | 2026-10-07 | окна прав и самогейт службы notify | — |

Столбец «линия kacho» заполнен там, где связь названа в trail линии либо в комментарии задачи
kacho; «—» — связь нигде не названа, и выводом по предмету она не дописывается.

### #102 — окна прав и самогейт notify

Со слов описания PR (один коммит `18d105d`, 8 файлов): окна прав службы notify заведены в
`authz.RevocationPolicy` под общим потолком; notify гейтит свой поставщик модуля
(`moduleselfgating`) прод-кодом; процесс без опт-ина пересыльщика объявляет это причиной и
ручки не заводит (`ForwarderKnobs.NoOptInBecause`, `ForwarderGate.NoOptIn`). Влит слиянием
без схлопывания; дерево головы ветки совпадает с деревом `18d105d`
(`git diff 18d105d0f50a origin/77-notify` пуст), поэтому пин на `18d105d` — тот же фундамент,
что голова ветки.

## Потребители

- kaname — [[KAC/issue-484-kaname]]: пин поднят на `18d105d` PR kaname #657.
- kacho `2914-notify` на `504bc7acdc51` (2026-10-08, после kacho #3098) — пин corelib
  `67ba3443c149` (#99; прочитано в `go.mod`); голова `77-notify` впереди на 5 коммитов
  (`gh api compare`), #100 и #102 потребителем kacho не взяты.

## DoD (из тела задачи)

- [ ] сценарии раздела «corelib» приёмки NTF-1 зелёные;
- [ ] выпущен тег corelib, на который встают kacho и kaname;
- [ ] ветка `77-notify` влита в `main` corelib и снята при вливании.

## Связанные задачи

- https://github.com/PRO-Robotech/kacho/issues/2914 — эпик.
- https://github.com/PRO-Robotech/kaname/issues/484 — линия kaname, блокирована этой.

## History

- 2026-10-07 — trail заведён после вливания #102 (`117749095814`) в `77-notify`; внесены все
  13 PR ветки. Статус `in-progress`.
- 2026-10-08 — потребитель: kacho #3098 поднял пин до `67ba3443c149`. Статус `in-progress`.

## Затронутые сущности vault

- Узких записок не тронуто: записки о пакетах `notify/feed`, `notify/spec` и `notifygen` в
  vault нет, а заводить их по ветке эпика, не влитой в `main`, — описывать непосаженное.

#kac #kacho-corelib #feature
