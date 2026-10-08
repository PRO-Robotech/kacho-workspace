---
title: "kacho#2914: эпик «Сервис уведомлений» — единый почтовый шлюз"
aliases:
  - issue-2914
  - epic-notify
ticket_id: 2914
category: kac
status: in-progress
verified_against: "`gh` 2026-10-08 (после вливания #3099): голова `2914-notify` = 515e017c873a (merge-коммит #3099, родители cd20a05cfa72 и fc51651d5c83); пины в `go.mod` на ней — corelib 18d105d0f50a, kaname 33010d434767; `gh api compare` — `18d105d0f50a...117749095814` впереди на 1 коммит при 0 файлов (голова `77-notify` — merge-коммит с деревом пина), `33010d434767...33010d434767` identical (голова `484-notify` = пин); `gh pr list --base 2914-notify` — тринадцать MERGED, открытых нет; ветки `2924-*` сняты (`git ls-remote`); kaname PR #673 OPEN в `484-notify`; эпик и задачи OPEN. `gh` 2026-10-08 (после вливания #3072): голова `2914-notify` = cd20a05cfa72 (merge-коммит #3072, родители 504bc7acdc51 и db85f0174807); пины в `go.mod` на ней не менялись — corelib 67ba3443c149, kaname 56bcb3036d71; `gh pr list --base 2914-notify` — двенадцать MERGED, открытых нет; ветки `2919-*` сняты (`git ls-remote`); эпик и задачи OPEN. `gh` 2026-10-08 (после вливаний #3071 и #3098): голова `2914-notify` = 504bc7acdc51 (merge-коммит #3098), пины на ней прочитаны в `go.mod` — corelib 67ba3443c149, kaname 56bcb3036d71; `gh api compare` — голова `77-notify` 117749095814 впереди пина на 5 коммитов, `484-notify` 33010d434767 — на 13; `gh pr list --base 2914-notify` — одиннадцать MERGED, открыт #3072; ветки `2917-wave-d1` и `2918-b1-resource-event` сняты (`git ls-remote`); эпик и задачи OPEN. `gh` 2026-10-07 (после вливаний corelib #102 и kaname #657): голова `2914-notify` = 4d5295f1ae96 (merge-коммит #3070), пины corelib e7d6197fc5dc и kaname cbd729cfa9b1 прочитаны в `go.mod` на ней и на головах открытых #3071 и #3072; голова `77-notify` corelib = 117749095814 (#102), `484-notify` kaname = 33010d434767 (#657); `gh pr list --base 2914-notify --state merged` — девять PR (#2960, #2977, #3019, #3021, #3027, #3039, #3041, #3042, #3070), открыты #3071 и #3072; эпик #2914, задачи NTF-1…NTF-6, NS, corelib#77, kaname#484 OPEN; в `main` из веток эпиков не влито ничего"
type: epic
repos:
  - kacho
  - corelib
  - kaname
areas:
  - services/notify
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2977
issue_url: https://github.com/PRO-Robotech/kacho/issues/2914
opened: 2026-09-29
closed:
tags:
  - kac
  - epic
---

# kacho#2914: эпик «Сервис уведомлений»

**Состояние на момент записи**: `in-progress`. Работа идёт в трёх ветках эпиков (координаты,
не живые ссылки): `2914-notify` (kacho), `77-notify` (corelib), `484-notify` (kaname). В
`main` ни одного репозитория не влито ничего. По каскаду «задача → волна → эпик → main»
эпик закрывается посадкой в `main`; до неё статус записки — не `done`.

## Что и зачем

Единый почтовый шлюз платформы: служба `services/notify` — единственный держатель кредов
почты. Остальные модули и kaname ставят нотификацию в свою ленту и не знают ни пароля, ни
ретранслятора; notify забирает письма сам и спрашивает kaname о праве на каждое. Требования
владельца и решения — в теле эпика, здесь не пересказываются.

## Линии эпика

| задача | предмет | trail |
|---|---|---|
| #2915 | NTF-1, ядро шлюза | [[KAC/issue-2915]] |
| #2916 | NS, политика выпуска сертификатов служб | — |
| #2917 | NTF-2, почта личности | [[KAC/issue-2917]] |
| #2918 | NTF-3, модули kacho | [[KAC/issue-2918]] |
| #2919 | NTF-4, возвраты и репутация | [[KAC/issue-2919]] |
| #2924 | NTF-5, извещения оператора | [[KAC/issue-2924]] |
| #2925 | NTF-6, центр уведомлений консоли | — |
| corelib#77 | линия corelib: лента, шаблон, `notifygen` | [[KAC/issue-77-corelib]] |
| kaname#484 | линия kaname: нотификации в ленту, снятие SMTP | [[KAC/issue-484-kaname]] |

Состав каждой волны — в trail её задачи. Волна, не принадлежащая ни одной линии, —
#2977 (`9c15ae851c41`, 2026-10-01): починка базы эпика (скан документации, линт shared,
скан IaC, форма id на крае, гейт публикации).

## Волны в `2914-notify`

| PR | merge-коммит | влит | задача |
|---|---|---|---|
| [#2977](https://github.com/PRO-Robotech/kacho/pull/2977) | `9c15ae851c41` | 2026-10-01 | эпик |
| [#2960](https://github.com/PRO-Robotech/kacho/pull/2960) | `e415e59a225b` | 2026-10-01 | #2915 |
| [#3019](https://github.com/PRO-Robotech/kacho/pull/3019) | `2c283f99f4bc` | 2026-10-04 | #2915 |
| [#3021](https://github.com/PRO-Robotech/kacho/pull/3021) | `230c08124259` | 2026-10-04 | #2915 |
| [#3027](https://github.com/PRO-Robotech/kacho/pull/3027) | `4517cc69c135` | 2026-10-05 | #2918 |
| [#3039](https://github.com/PRO-Robotech/kacho/pull/3039) | `58248816f540` | 2026-10-05 | #2915 |
| [#3041](https://github.com/PRO-Robotech/kacho/pull/3041) | `bc3192f9ca13` | 2026-10-05 | #2915 |
| [#3042](https://github.com/PRO-Robotech/kacho/pull/3042) | `829e1a26cb18` | 2026-10-06 | #2918 |
| [#3070](https://github.com/PRO-Robotech/kacho/pull/3070) | `4d5295f1ae96` | 2026-10-07 | #2924 |
| [#3071](https://github.com/PRO-Robotech/kacho/pull/3071) | `dc95c1d5dc9e` | 2026-10-07 | #2917 |
| [#3098](https://github.com/PRO-Robotech/kacho/pull/3098) | `504bc7acdc51` | 2026-10-08 | #2918 |
| [#3072](https://github.com/PRO-Robotech/kacho/pull/3072) | `cd20a05cfa72` | 2026-10-08 | #2919 |
| [#3099](https://github.com/PRO-Robotech/kacho/pull/3099) | `515e017c873a` | 2026-10-08 | #2924 |

Открытых запросов в `2914-notify` на 2026-10-08 после вливания #3099 нет.

## Ветки эпиков фундамента

| ветка | голова | последний влитый | пин kacho на `515e017c873a` |
|---|---|---|---|
| `77-notify` (corelib) | `117749095814` | [#102](https://github.com/PRO-Robotech/corelib/pull/102), 2026-10-07 — окна прав и самогейт notify | `18d105d0f50a` — дерево головы (голова — merge-коммит #102 без отличий по файлам) |
| `484-notify` (kaname) | `33010d434767` | [#657](https://github.com/PRO-Robotech/kaname/pull/657), 2026-10-07 — пин corelib `18d105d` | `33010d434767` — голова |

Пины подняты #3099 (#2924) до голов обеих веток; kaname на пине сама пинит corelib
`18d105d0f50a` — пары согласованы. В `484-notify` открыт kaname
[#673](https://github.com/PRO-Robotech/kaname/pull/673) (волна ограды NTF-3, kaname#636 и
kaname#667): после его вливания голова снова уйдёт вперёд пина. Составы — в trail линий.

## DoD

- [ ] все линии закрыты по своим предикатам (trail каждой);
- [ ] PR эпика `2914-notify` → `main` влит, вместе с ветками эпиков corelib и kaname;
- [ ] ветки эпиков сняты при вливании.

## History

- 2026-10-07 — trail эпика заведён после вливания волны F1 (#3070, `4d5295f1ae96`).
  Статус `in-progress`.
- 2026-10-07 — после вливаний corelib #102 (`117749095814`) в `77-notify` и kaname #657
  (`33010d434767`) в `484-notify` заведены trail линий фундамента; пины kacho не менялись.
  Статус `in-progress`.
- 2026-10-08 — внесены #3071 (`dc95c1d5dc9e`, линия D, #2917) и #3098 (`504bc7acdc51`,
  B1, #2918); пины kacho подняты до corelib `67ba3443c149` и kaname `56bcb3036d71`.
  Статус `in-progress`.
- 2026-10-08 — внесён #3072 (`cd20a05cfa72`, волна E1, #2919): исход `SUPPRESSED` в
  контракте ленты и ручки NTF-4 стадии S1; пины не менялись. Статус `in-progress`.
- 2026-10-08 — внесён #3099 (`515e017c873a`, волна S1, #2924): контракт извещений,
  notify-api, край; пины подняты до голов фундамента — corelib `18d105d0f50a`, kaname
  `33010d434767`. Статус `in-progress`.

## Затронутые сущности vault

- [[packages/notify-service]] — служба целиком.
- [[packages/gateway-anonmail]] — ограничитель анонимной почты края (#3071).
- [[packages/kacho-module-resource-event]] — resource-event модулей (#3098).
- [[resources/notify-notice]] — ресурс «извещение оператора» (#3099).

#kac #epic
