---
title: "kacho#2698: iam: восстановление у личности без способа входа паролем отказывает 503"
aliases:
  - issue-2698
  - kacho#2698
ticket_id: 2698
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/humansession
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kacho/issues/2698
opened: 2026-09-16
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#2698: iam: восстановление у личности без способа входа паролем отказывает 503

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Восстановление у личности без способа входа паролем больше не отказывает `503`: завершение восстановления заводит строку «пароль», если её нет (Ф5-34). Задача живёт в трекере kacho (kacho#2698), исполнена в службе.

## Затронутые каталоги

`internal/apps/kaname/api/humansession` (PRO-Robotech/kaname).

Коммиты в составе волны: `07a42550e`, `f1eaf8281`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2698#issuecomment-6009673492): `git grep -c 'has no password sign-in method to replace'` по дереву → rc 1, 0; пробы `F5_34` (`go test -race -count=1 -run F5_34`) → pass, 5 / 7, fail 0, skip 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4
- [[KAC/issue-343-kaname]]

#kac #kacho-iam
