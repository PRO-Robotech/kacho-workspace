---
title: "kaname#388: отсечка отзыва-всех и момент выдачи — от одних часов"
aliases:
  - issue-388-kaname
  - kaname#388
ticket_id: 388
category: kac
status: in-progress
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/api/user_tokens
  - internal/revocationpolicy
prs:
  - https://github.com/PRO-Robotech/kaname/pull/599
issue_url: https://github.com/PRO-Robotech/kaname/issues/388
opened: 2026-09-23
tags:
  - kac
  - kacho-iam
  - iam
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались"
---

# kaname#388: отсечка отзыва-всех и момент выдачи — от одних часов

> [!warning] Состояние — `in-progress`: задача ОТКРЫТА, работа в ветке эпика есть, предикат не предъявлен
> Полоса NA4 волны-2 влита в `296` запросом [kaname#599](https://github.com/PRO-Robotech/kaname/pull/599) (`77dae639`), задача стоит в запросе строкой `Refs`.
> Перенесена в волну-3 [[KAC/issue-537-kaname]] и закроется с ней, когда предикат тела будет доказан
> командой (комментарий задачи 2026-10-04). В sub-issue она по-прежнему числится за закрытой #536.

## Что и зачем

Момент выдачи долговременного удостоверения ставили часы базы, отсечку — часы процесса; граница
правила была разницей двух часов. Теперь оба момента — часы процесса; держит
`TestRevokeAll_IssuanceAndCutoffShareOneClockOnEveryRuleLane`. Остаток (реплик больше одной) — [[KAC/issue-589-kaname]].

## Как доехало

Коммиты задачи в `296` (`git log d2f6f182..77dae639`): `57d165b0f`.

## Затронутые каталоги

`internal/apps/kaname/api/user_tokens`, `internal/revocationpolicy`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке, либо измерено этой записью на ревизии из `verified_against`; `[ ]` — не выполнено либо не доказано, причина в строке.

- [ ] предикат тела задачи — исход предиката из тела задачи в запросе не предъявлен;
- [ ] в `main` службы — нет.

## Затронутые сущности vault

- [[resources/iam-user-token-revocation]] — History #388

## Связанные задачи

- [[KAC/issue-589-kaname]] — остаток
- [[KAC/issue-171-kaname]] — та же полоса
- [[KAC/issue-537-kaname]] — волна-3
- [[KAC/issue-536-kaname]] — волна-2

#kac #kacho-iam #iam
