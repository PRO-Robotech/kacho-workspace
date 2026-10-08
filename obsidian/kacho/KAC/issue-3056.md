---
title: "kacho#3056: край: пересылать /iam/v1/auth/password/enroll — первый пароль из сессии"
aliases:
  - issue-3056
  - kacho#3056
ticket_id: 3056
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - gateway/internal/middleware
  - gateway/internal/handler
  - gateway/docs
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/3056
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - feature
  - kacho-api-gateway
verified_against: "kacho 1266: коммит слияния PR #3073 = 8725b886e124 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @1faf59ec6945; пробы и конвейер этой записью не перезапускались"
---

# kacho#3056: край: пересылать /iam/v1/auth/password/enroll — первый пароль из сессии

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073) (первая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `8725b886e124` 2026-10-07.

## Что и зачем

Край ретранслирует `POST /iam/v1/auth/password/enroll` — заведение первого пароля из сессии у человека без пароля. Сторона службы — kaname#213; экран консоли — [[KAC/issue-3058]].

## Затронутые каталоги

`gateway/internal/middleware`, `gateway/internal/handler`, `gateway/docs` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `8725b886e124` (kacho#3073);
- [x] DoD-proof @`1faf59ec6945` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3056#issuecomment-6035044806): go test -count=1 ./gateway/internal/middleware/... ./gateway/internal/handler/... → ok, исполнено 1111 (тесты и подтесты, go test -json), отказов 0, пропусков 0.
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- [[edges/api-gateway-to-kaname-login-lane]]
- [[packages/apigw-middleware]]

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #feature #kacho-api-gateway
