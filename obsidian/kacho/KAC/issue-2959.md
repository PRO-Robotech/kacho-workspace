---
title: "kacho#2959: край: выход обязан гасить сессию на сервере на каждом пути"
aliases:
  - issue-2959
  - kacho#2959
ticket_id: 2959
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/handler
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/2959
opened: 2026-10-01
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#2959: край: выход обязан гасить сессию на сервере на каждом пути

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Выход края на каждом принимаемом предъявлении (Bearer, DPoP, форма `token`) гасит удостоверение на сервере либо отвечает «не выполнен»; кука сессии браузера выходом пути токенов не снимается.

## Затронутые каталоги

`gateway/internal/handler` (PRO-Robotech/kacho).

Коммиты в составе волны: `7112c2087be`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2959#issuecomment-6012628720): `go test -count=1 -v ./gateway/internal/handler/ -run 'TestLogout_2959|TestLogout_NeverEndsTheBrowserSessionCarrier'` → код 0, PASS 6, FAIL 0; сквозная `go test -count=1 ./gateway/internal/e2e/ -run TestE2E_Logout_EndsTheCredentialServerSideOnEveryAcceptedPresentation` → код 0, PASS 3. Красный до кода — комментарий от 2026-10-05 (ревизия d7710e33). Конвейер: юниты gateway — success.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4
- [[KAC/issue-2996]]
- [[KAC/issue-2956]]

#kac #kacho-api-gateway
