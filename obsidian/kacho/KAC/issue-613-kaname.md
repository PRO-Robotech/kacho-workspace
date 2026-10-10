---
title: "kaname#613: Ф13 служба: вход ключом доступа без пароля — глаголы формы, испытание, выдача сессии"
aliases:
  - issue-613-kaname
  - kaname#613
ticket_id: 613
category: kac
status: test
type: feature
repos:
  - kaname
areas:
  - internal/handler/loginlanehttp
  - internal/apps/kaname/api/humansession
  - internal/migrations
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/613
opened: 2026-10-05
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#613: Ф13 служба: вход ключом доступа без пароля — глаголы формы, испытание, выдача сессии

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Ф13 в службе: вход ключом доступа без пароля — два глагола полосы формы (`access-key/begin`, `access-key/login`), испытание, привязанное к контексту формы, выдача сессии. Ретрансляция этих глаголов краем — kacho#3037, перенесена в волну-5.

## Затронутые каталоги

`internal/handler/loginlanehttp`, `internal/apps/kaname/api/humansession`, `internal/migrations` (PRO-Robotech/kaname).

Коммиты в составе волны: `caf7c0e77`, `c4a3d3810`, `691efc24a`, `1640efcf8`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/613#issuecomment-6009362355): `git grep -c access-key -- internal/handler/loginlanehttp/handler.go` → 2; `go test -race -count=1 -run TestF13_` → pass, 16 / 16, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[rpc/iam-login-lane]] — глаголы ключа доступа в перечне, 18 путей (History 2026-10-06)
- [[resources/kaname-access-key]] — вход ключом, испытание формы (History 2026-10-06)
- [[packages/kaname-migrations]] — миграция `20261005032942` (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4
- [[KAC/issue-343-kaname]]

#kac #kacho-iam
