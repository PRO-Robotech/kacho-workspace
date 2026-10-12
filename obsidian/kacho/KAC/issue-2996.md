---
title: "kacho#2996: край: исход /oauth/logout расходится с выходом полосы входа"
aliases:
  - issue-2996
  - kacho#2996
ticket_id: 2996
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/handler
  - gateway/internal/e2e
  - gateway/docs
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/2996
opened: 2026-10-02
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#2996: край: исход /oauth/logout расходится с выходом полосы входа

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Исход `POST /oauth/logout` приведён к исходу выхода полосы входа: `200 {}` при выходе, `503` «не выполнен», когда отзыв или источник проверочных ключей не ответил (токен на сервере жив — клиенту не говорится его выбросить). Срок проверки предъявителя задаёт проверяющий, а не ручка бюджета вызовов (KA1-37, приёмка KA1 ред. 9 Р4). В той же ветке — откат правки текста отказа неподтверждённого адреса (`81f7bf3504e`), см. [[lessons/edge-refusal-text-changed-past-its-acceptance]].

## Затронутые каталоги

`gateway/internal/handler`, `gateway/internal/e2e`, `gateway/docs` (PRO-Robotech/kacho).

Коммиты в составе волны: `7112c2087be`, `bb867e02fff`, `b8971b9d05c`, `610eb0911a6`, `81f7bf3504e`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2996#issuecomment-6012632946): `go test -count=1 ./gateway/internal/e2e/ -run TestE2E_Logout_EndsTheCredentialServerSideOnEveryAcceptedPresentation` → код 0, PASS 3; `go test -count=1 ./gateway/internal/handler/ -run TestLogout_KeySourceUnanswered_IsNotPerformedOnEveryPresentation` → код 0, PASS 7 (замечание M1); `go test -count=1 ./gateway/internal/e2e/ka1budget/ -run TestKA1_37_LogoutVerificationIsBoundedByTheKeySetBudgetNotTheKnob` → код 0, PASS 1. Страницы края о выходе — коммит 610eb0911a6. Конвейер: юниты gateway — success.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/apigw-middleware]] — откат текста отказа неподтверждённого адреса (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4
- [[KAC/issue-2959]]
- [[KAC/issue-2956]]
- [[KAC/issue-3029]]

#kac #kacho-api-gateway
