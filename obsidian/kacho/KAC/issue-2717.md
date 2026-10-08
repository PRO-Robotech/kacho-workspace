---
title: "kacho#2717: gateway: проза края называет четыре глагола формы вместо перечня"
aliases:
  - issue-2717
  - kacho#2717
ticket_id: 2717
category: kac
status: test
type: docs
repos:
  - kacho
areas:
  - gateway/deploy
  - deploy/helm
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/2717
opened: 2026-09-18
closed: 2026-10-07
tags:
  - kac
  - docs
  - kacho-api-gateway
  - kacho-deploy
verified_against: "kacho 1266: коммит слияния PR #3073 = 8725b886e124 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @775621f1115e; пробы и конвейер этой записью не перезапускались"
---

# kacho#2717: gateway: проза края называет четыре глагола формы вместо перечня

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073) (первая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `8725b886e124` 2026-10-07.

## Что и зачем

Проза края и подчарта службы называла «четыре глагола формы» числом, которое расходилось с перечнем ретрансляции. Теперь текст называет перечень объявлением и числа не несёт; число строк комментария слушателя полосы формы в настройках подчарта держится прежним.

## Затронутые каталоги

`gateway/deploy`, `deploy/helm` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `8725b886e124` (kacho#3073);
- [x] DoD-proof @`775621f1115e` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2717#issuecomment-6034488088): git grep -n -iE "четыре глагола (формы|под)|четырёх глаголов формы" 775621f1115ee641127f590a9aca7e62a361d971 -- gateway deploy | wc -l → 0 (было 7 @0ae22f8f8); go test -count=1 ./deploy/... -run "LoginLane|LoginConsole" → исполнено 10 верхн…
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- [[edges/api-gateway-to-kaname-login-lane]]

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #docs #kacho-api-gateway #kacho-deploy
