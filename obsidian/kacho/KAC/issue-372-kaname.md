---
title: "kaname#372: ci: самопробы хука отправки и установщика не зовёт ни одно задание"
aliases:
  - issue-372-kaname
  - kaname#372
ticket_id: 372
category: kac
status: test
type: feature
repos:
  - kaname
areas:
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/372
opened: 2026-09-22
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#372: ci: самопробы хука отправки и установщика не зовёт ни одно задание

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Посылка «самопробы хука отправки и установщика не зовёт ни одно задание» опровергнута на дереве: конвейер зовёт четыре `*-inject.sh`, отдельного кода не понадобилось.

## Затронутые каталоги

`.github/workflows` (PRO-Robotech/kaname).

Кода нет: предикат выполнен деревом, см. DoD-proof.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/372#issuecomment-6009368209): четыре `*-inject.sh`, которые зовёт ci.yml на этой ревизии → rc 0 у каждого: install 44/0, classify 21/0, budget 33/0, branch-rule 98/0, все дефекты красные, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4

#kac #kacho-iam
