---
title: "kaname#231: migrations — README и мигратор называют чужой гейт формы с приставкой дома"
aliases:
  - issue-231-kaname
  - kaname#231
ticket_id: 231
category: kac
status: in-progress
type: docs
repos:
  - kaname
areas:
  - internal/migrations
prs:
  - https://github.com/PRO-Robotech/kaname/pull/599
issue_url: https://github.com/PRO-Robotech/kaname/issues/231
opened: 2026-09-17
tags:
  - kac
  - kacho-iam
  - migrations
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#231: migrations — README и мигратор называют чужой гейт формы с приставкой дома

> [!warning] Состояние — `in-progress`: задача ОТКРЫТА, работа в ветке эпика есть, предикат не предъявлен
> Полоса NA2 волны-2 влита в `296` запросом [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) (`77dae639`), задача стоит в запросе строкой `Refs`.
> Перенесена в волну-3 [[KAC/issue-537-kaname]] и закроется с ней, когда предикат тела будет доказан
> командой (комментарий задачи 2026-10-04). В sub-issue она по-прежнему числится за закрытой #536.

## Что и зачем

README миграций и мигратор называли гейт формы и документ, которых в дереве службы нет. Координата
чужого гейта записана с приставкой дома.

## Как доехало

Коммиты задачи в `296` (`git log d2f6f182..77dae639`): `e740424d2`.

## Затронутые каталоги

`internal/migrations`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [ ] предикат тела задачи — исход предиката из тела задачи в запросе не предъявлен;
- [ ] в `main` службы — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-336-kaname]] — та же полоса
- [[KAC/issue-537-kaname]] — волна-3
- [[KAC/issue-536-kaname]] — волна-2

#kac #kacho-iam #migrations
