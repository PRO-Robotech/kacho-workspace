---
title: "kacho#3053: край: отсутствие внутренних путей на публичном входе не доказано"
aliases:
  - issue-3053
  - kacho#3053
ticket_id: 3053
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/restmux
  - gateway/cmd/api-gateway
  - tests/newman
  - ui-future/e2e
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/3053
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-api-gateway
  - kacho-test
verified_against: "kacho 1266: коммит слияния PR #3073 = 8725b886e124 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @0db381145a6f; пробы и конвейер этой записью не перезапускались"
---

# kacho#3053: край: отсутствие внутренних путей на публичном входе не доказано

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073) (первая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `8725b886e124` 2026-10-07.

## Что и зачем

Край на публичном входе отвечает «маршрута нет» на внутреннее пространство путей до аутентификации; сквозные пробы утверждают промах маршрута целиком, ведомости newman записывают исход точно. Разбор — по диффу запроса волны, не здесь.

## Затронутые каталоги

`gateway/internal/restmux`, `gateway/cmd/api-gateway`, `tests/newman`, `ui-future/e2e` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `8725b886e124` (kacho#3073);
- [x] DoD-proof @`0db381145a6f` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3053#issuecomment-6034909226): go test -count=1 ./gateway/internal/restmux/... ./gateway/internal/e2e/... → исполнено 523 (тестов с подтестами; верхнего уровня 193), отказов 0, пропусков 0; go test -count=1 -run TestExternalRouteGate ./gateway/cmd/api-gateway/ → ok.
- [ ] стендовая часть — подзадача kacho#3066 волны-6: проверяется после выкатки волны (стенд не перекачен, см. [[KAC/issue-2969]]).
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- [[packages/apigw-middleware]]

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #fix #kacho-api-gateway #kacho-test
