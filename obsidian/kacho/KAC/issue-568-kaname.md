---
title: "kaname#568: iam: порядок захвата строк журнала прав в транзакциях записи прав"
aliases:
  - issue-568-kaname
  - kaname#568
ticket_id: 568
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/migrations
  - internal/repo/kaname/pg
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/568
opened: 2026-10-02
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
  - migrations
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#568: iam: порядок захвата строк журнала прав в транзакциях записи прав

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Порядок захвата строк журнала прав держит база (миграция `20261005040457_relation_fact_fold_takes_locks_in_one_order.sql`), а не эмиттер. Порядок между операторами одной транзакции — отдельная задача kaname#617.

## Затронутые каталоги

`internal/migrations`, `internal/repo/kaname/pg` (PRO-Robotech/kaname).

Коммиты в составе волны: `d2fff9aa0`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/568#issuecomment-6009366143): `go test -race -count=1 -run 'TestRawJournal.*Deadlock'` → pass, 2 / 2, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/kaname-migrations]] — миграция `20261005040457` (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4
- [[KAC/issue-562-kaname]]

#kac #kacho-iam #migrations
