---
title: "kaname#460: newman: 109 позиций уровня E шести приёмок без кейса набора"
aliases:
  - issue-460-kaname
  - kaname#460
ticket_id: 460
category: kac
status: test
type: refactor
repos:
  - kaname
areas:
  - tests/newman
prs:
  - https://github.com/PRO-Robotech/kaname/pull/623
issue_url: https://github.com/PRO-Robotech/kaname/issues/460
opened: 2026-09-27
closed: 2026-10-06
tags:
  - kac
  - kacho-iam
verified_against: "kaname 296@2cf9c8528b1f (коммит слияния PR #623, родители 115db76949bd + 7663d9537efb; голова origin/296 = этот коммит, git ls-remote 2026-10-06): состав — git log 115db76949bd..2cf9c852 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kaname#460: newman: 109 позиций уровня E шести приёмок без кейса набора

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-538-kaname]] влита в `296` коммитом слияния `2cf9c8528b1f` ([kaname#623](https://github.com/PRO-Robotech/kaname/pull/623)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

109 позиций уровня E шести приёмок получили кейсы набора newman; держатель долга за задачей — 0.

## Затронутые каталоги

`tests/newman` (PRO-Robotech/kaname).

Работа влита до волны-4; в волне — доказательство на дереве слияния.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `296` — коммит слияния волны `2cf9c8528b1f`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/460#issuecomment-6009370169): `newman-suite-debt.py` → rc 0, позиций за kaname#460: 0, влито в эпик 296 через PRO-Robotech/kaname#623
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-538-kaname]] — волна-4

#kac #kacho-iam
