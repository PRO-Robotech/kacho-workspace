---
title: "kaname#343: сессия: уровень уверенности пишут пятеро, условия на прежний нет"
aliases:
  - issue-343-kaname
  - kaname#343
ticket_id: 343
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/humansession
  - internal/migrations
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/343
opened: 2026-09-21
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#343: сессия: уровень уверенности пишут пятеро, условия на прежний нет

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Уровень уверенности сессии пишет один вызов (`TestSessionLevelHasOneWriterCallSite`), а не пятеро без условия на прежнее значение. Ветка полосы несёт и вход ключом доступа Ф13 ([[KAC/issue-613-kaname]]) и копию уровня в ответе смены пароля ([[KAC/issue-208-kaname]]).

## Затронутые каталоги

`internal/apps/kaname/api/humansession`, `internal/migrations` (PRO-Robotech/kaname).

Коммиты в составе волны: `71892013f`, `d46577d5d`, `374cd6c6e`, `6108c49d5`, `7ce1975ce`, `f1eaf8281`, `07a42550e`, `caf7c0e77`, `c4a3d3810`, `691efc24a`, `1640efcf8`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/343#issuecomment-6009360595): `go test -race -count=1 -run TestSessionLevelHasOneWriterCallSite` → pass, 1 / 1, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[resources/iam-human-session]] — один писатель уровня (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4
- [[KAC/issue-613-kaname]]
- [[KAC/issue-208-kaname]]

#kac #kacho-iam
