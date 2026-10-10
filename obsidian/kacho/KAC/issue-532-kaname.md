---
title: "kaname#532: конфиг: адрес базы — у службы без старшинства, у мигратора с ним"
aliases:
  - issue-532-kaname
  - kaname#532
ticket_id: 532
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - cmd/migrator
  - deploy
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/532
opened: 2026-10-01
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
  - config
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#532: конфиг: адрес базы — у службы без старшинства, у мигратора с ним

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Мигратор берёт правило службы: адрес базы объявляется ровно одним источником, объявление двумя формами сразу — отказ (`cmd/migrator`, проба `DeclaredTwice`). Профиль развёртывания больше не ссылается на снятый держатель пары профилей.

## Затронутые каталоги

`cmd/migrator`, `deploy` (PRO-Robotech/kaname).

Коммиты в составе волны: `a5b133e14`, `b6cf89c06`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/532#issuecomment-6009357667): `go test -race -count=1 -run DeclaredTwice ./cmd/migrator` → pass, 2 / 6, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4

#kac #kacho-iam #config
