---
title: "kaname#262: iam: выдача по приглашению не несёт выдавшего"
aliases:
  - issue-262-kaname
  - kaname#262
ticket_id: 262
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/user
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/262
opened: 2026-09-17
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#262: iam: выдача по приглашению не несёт выдавшего

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Выдача прав по приглашению несёт выдавшего (`GrantedBy`) тем же правилом, что `AccessBinding.Create`.

## Затронутые каталоги

`internal/apps/kaname/api/user` (PRO-Robotech/kaname).

Коммиты в составе волны: `9990a6e64`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/262#issuecomment-6009355037): `git grep -c GrantedBy -- internal/apps/kaname/api/user/invite.go` → 1; `go test -race -count=1 -run ProjectGrantCarriesTheGranter` → pass, тестов 1 верхнего уровня / 3 всего, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4

#kac #kacho-iam
