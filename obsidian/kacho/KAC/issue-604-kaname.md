---
title: "kaname#604: три списка применяют умолчание страницы 100 вместо 50"
aliases:
  - issue-604-kaname
  - kaname#604
ticket_id: 604
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/repo/kaname/pg
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/604
opened: 2026-10-04
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#604: три списка применяют умолчание страницы 100 вместо 50

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Три списка применяли умолчание страницы 100 вместо объявленных 50; приведены к 50.

## Затронутые каталоги

`internal/repo/kaname/pg` (PRO-Robotech/kaname).

Коммиты в составе волны: `4375ca672`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/604#issuecomment-6009363842): `git grep -n pageSize=100` по коду списков → rc 1, пусто; `go test -race -count=1 -run TestListDefaultPageSize` → pass, 3 / 3, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4
- [[KAC/issue-562-kaname]]

#kac #kacho-iam
