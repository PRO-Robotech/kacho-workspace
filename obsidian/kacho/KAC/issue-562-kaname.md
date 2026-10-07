---
title: "kaname#562: контракт: Update интерактивного клиента молча игнорирует поля"
aliases:
  - issue-562-kaname
  - kaname#562
ticket_id: 562
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/interactive_client
  - proto
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/562
opened: 2026-10-02
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#562: контракт: Update интерактивного клиента молча игнорирует поля

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Контракт `Update` интерактивного клиента больше не обещает «молча игнорировать» поля: неизменяемое поле в маске получает отказ (`TestUpdate_ImmutableInMask_*`). Под номером полосы влиты и #604, #563, #568.

## Затронутые каталоги

`internal/apps/kaname/api/interactive_client`, `proto` (PRO-Robotech/kaname).

Коммиты в составе волны: `d2fff9aa0`, `64fe51c6f`, `277088922`, `4375ca672`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/562#issuecomment-6009364689): `go test -race -count=1 -run TestUpdate_ImmutableInMask_` → pass, 2 / 8, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[resources/iam-interactive-client]] — контракт `Update` (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4
- [[KAC/issue-604-kaname]]
- [[KAC/issue-563-kaname]]
- [[KAC/issue-568-kaname]]

#kac #kacho-iam
