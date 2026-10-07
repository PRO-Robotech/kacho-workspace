---
title: "kacho#2914: эпик «Сервис уведомлений» — единый почтовый шлюз"
aliases:
  - issue-2914
  - epic-notify
ticket_id: 2914
category: kac
status: in-progress
verified_against: "`gh` 2026-10-07: голова `2914-notify` = 4d5295f1ae96 (merge-коммит #3070); `gh pr list --base 2914-notify --state merged` — девять PR (#2960, #2977, #3019, #3021, #3027, #3039, #3041, #3042, #3070), открыты #3071 и #3072; голова `484-notify` kaname = 22b70ea5d0a7, `77-notify` corelib = 1e6ade53645a; эпик #2914 и задачи NTF-1…NTF-6, NS OPEN; в `main` из ветки эпика не влито ничего"
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

Открыты на 2026-10-07: #3071 (линия D, #2917), #3072 (линия E, #2919).

## DoD

- [ ] все линии закрыты по своим предикатам (trail каждой);
- [ ] PR эпика `2914-notify` → `main` влит, вместе с ветками эпиков corelib и kaname;
- [ ] ветки эпиков сняты при вливании.

## History

- 2026-10-07 — trail эпика заведён после вливания волны F1 (#3070, `4d5295f1ae96`).
  Статус `in-progress`.

## Затронутые сущности vault

- [[packages/notify-service]] — служба целиком.

#kac #epic
