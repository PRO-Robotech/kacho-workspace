---
title: "kaname#208: iam: копия уровня в ответе смены пароля считается по именам способов — «3» назовётся «2»"
aliases:
  - issue-208-kaname
  - kaname#208
ticket_id: 208
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/humansession
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/208
opened: 2026-09-17
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#208: iam: копия уровня в ответе смены пароля считается по именам способов — «3» назовётся «2»

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Копия уровня в ответе смены пароля читает записанный уровень, а не выводит его из имён способов («3» больше не называется «2»).

## Затронутые каталоги

`internal/apps/kaname/api/humansession` (PRO-Robotech/kaname).

Коммиты в составе волны: `691efc24a`, `1640efcf8`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/208#issuecomment-6009361493): `git grep -n 'KeyAssertion(false, true)' -- internal/apps/kaname/api/humansession/change_password.go` → rc 1, 0 строк; `go test -race -count=1 -run TestChangePassword_208` → pass, 1 / 3, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[resources/iam-human-session]] — копия уровня (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4
- [[KAC/issue-343-kaname]]

#kac #kacho-iam
