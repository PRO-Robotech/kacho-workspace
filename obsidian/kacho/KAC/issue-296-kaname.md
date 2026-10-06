---
title: "kaname#296: эпик identity-own — своя личность в службе доступа"
aliases:
  - issue-296-kaname
ticket_id: 296
category: kac
status: in-progress
type: epic
repos:
  - kaname
areas:
  - docs
  - proto
  - internal
  - tests/newman
prs:
  - https://github.com/PRO-Robotech/kaname/pull/582
  - https://github.com/PRO-Robotech/kaname/pull/599
  - https://github.com/PRO-Robotech/kaname/pull/607
  - https://github.com/PRO-Robotech/kaname/pull/623
  - https://github.com/PRO-Robotech/kaname/pull/629
issue_url: https://github.com/PRO-Robotech/kaname/issues/296
opened: 2026-09-18
tags:
  - kac
  - kacho-iam
  - epic
verified_against: "kaname 296@77dae639 (коммит слияния PR #599, родители d2f6f182 + 594af5af; голова origin/296 = этот коммит, 2026-10-04): состав — git log d2f6f182..77dae639 --no-merges; состояние задачи и sub-issue — gh issue view / gh api …/sub_issues 2026-10-04; DoD — по комментариям задачи и телу PR #599; пробы и конвейер этой записью не перезапускались; 2026-10-06 — волны 3–4: голова origin/296 = 2cf9c8528b1f (git ls-remote), волны — gh api …/issues/296/sub_issues (#535–#538 closed, #539–#541 open); 2026-10-07 — волна 5: голова origin/296 = d9e233f42051 (git ls-remote), волны — gh api …/issues/296/sub_issues (#535–#539 closed, #540–#541 open)"
---

# kaname#296: эпик identity-own — своя личность в службе доступа

> [!note] Состояние — `in-progress`: эпик открыт, влиты волны 1–5 из семи
> Ветка эпика `296` на origin @`d9e233f42051` (2026-10-07). Запроса `296` → `main` нет.
> Волны — sub-issue эпика: #535…#539 закрыты, #540…#541 открыты (`gh api …/issues/296/sub_issues`).

## Что и зачем

Дочерний эпик [[KAC/issue-1266]] в доме службы доступа: своя личность — после снятия внешнего стека
([[KAC/issue-357-kaname]], влит в `main`). Записка заведена сжато при закрытии волны-1.

| волна | состояние на 2026-10-07 |
|---|---|
| [[KAC/issue-535-kaname]] волна-1 — приёмки, модель прав, ключи доступа, проза | влита в `296` (PR kaname#582, `d2f6f182`) |
| [[KAC/issue-536-kaname]] волна-2 — отсечка, авторитет отзыва, рукоятка ключа, гейты, почта | влита в `296` (PR kaname#599, `77dae639`) |
| [[KAC/issue-537-kaname]] волна-3 — Ф13, чарт, проза | влита в `296` (PR kaname#607, `115db76949bd`) |
| [[KAC/issue-538-kaname]] волна-4 — регистрация и приглашение, мигратор, рукоятка, Ф13 | влита в `296` (PR kaname#623, `2cf9c8528b1f`); 15 задач — в #539 |
| [[KAC/issue-539-kaname]] волна-5 — перепись AWI-13, кейс Ф4-27, носитель окна темпа, приёмка службы ред. 8 | влита в `296` (PR kaname#629, `d9e233f42051`); 16 задач — в #540 |
| #540 волна-6 … #541 волна-7 | открыты |

## Затронутые каталоги

Ветка эпика `296`; по волнам — [[KAC/issue-535-kaname]], [[KAC/issue-536-kaname]].

## DoD

Отметка `[x]` — измерено этой записью на ревизии из `verified_against` либо предъявлено артефактом, названным в строке; `[ ]` — не перепроверено этой записью либо не выполнено, причина в строке.

- [x] волна-1 влита в ветку эпика — [[KAC/issue-535-kaname]].
- [x] волна-2 влита в ветку эпика — [[KAC/issue-536-kaname]].
- [x] волна-3 влита в ветку эпика — [[KAC/issue-537-kaname]].
- [x] волна-4 влита в ветку эпика — [[KAC/issue-538-kaname]].
- [x] волна-5 влита в ветку эпика — [[KAC/issue-539-kaname]].
- [ ] волны 6–7 — открыты.
- [ ] эпик влит в `main` службы — нет.

## Затронутые сущности vault

- [[KAC/issue-535-kaname]] — волна-1 и узкие записки, которые она тронула
- [[KAC/issue-536-kaname]] — волна-2 и узкие записки, которые она тронула
- [[KAC/issue-538-kaname]] — волна-4 и узкие записки, которые она тронула
- [[KAC/issue-539-kaname]] — волна-5 и узкие записки, которые она тронула

## Связанные задачи

- [[KAC/issue-1266]] — эпик платформы
- [[KAC/issue-357-kaname]] — снятие внешнего стека в службе, предшественник

#kac #kacho-iam #epic
