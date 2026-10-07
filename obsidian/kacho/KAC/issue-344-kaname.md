---
title: "kaname#344: миграции: четвёртый носитель обещания о рукоятке — без дома в обоих документах"
aliases:
  - issue-344-kaname
  - kaname#344
ticket_id: 344
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/migrations
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/344
opened: 2026-09-21
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
  - migrations
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#344: миграции: четвёртый носитель обещания о рукоятке — без дома в обоих документах

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Описание рукоятки ключа доступа получило дом новой миграцией `20261005024608_access_key_handle_comment_names_both_generations.sql`, называющей оба поколения строк.

## Затронутые каталоги

`internal/migrations` (PRO-Robotech/kaname).

Коммиты в составе волны: `ee6f76862`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/344#issuecomment-6009358585): `go test -race -count=1 -run TestNewMigrationOutranksEveryAppliedOne` → pass, 1 / 1, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/kaname-migrations]] — миграция `20261005024608` (History 2026-10-06)
- [[resources/kaname-access-key]] — описание рукоятки (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4

#kac #kacho-iam #migrations
