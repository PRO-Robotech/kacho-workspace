---
title: "kacho#3029: edge: текст отказа наружу называет внутренний сервис"
aliases:
  - issue-3029
  - kacho#3029
ticket_id: 3029
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - gateway/internal/middleware
  - gateway/internal/subscriptionstream
  - internal/repohygiene
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/3029
opened: 2026-10-04
closed: 2026-10-06
tags:
  - kac
  - kacho-api-gateway
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3029: edge: текст отказа наружу называет внутренний сервис

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Текст отказа, уходящий наружу с края, не называет внутренних служб. Держится гейтом дерева `TestEdgeRefusalNamesNoInternalService` (шесть форм записи отказа, инъекции и законные близнецы).

## Затронутые каталоги

`gateway/internal/middleware`, `gateway/internal/subscriptionstream`, `internal/repohygiene` (PRO-Robotech/kacho).

Коммиты в составе волны: `c07b79ee5cc`, `03b3dec9fe6`, `610eb0911a6`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3029#issuecomment-6012635535): `go test -count=1 -v ./internal/repohygiene/ -run 'TestEdgeRefusalNamesNoInternalService|TestEdgeRefusalInjection_'` → код 0, PASS 5 (гейт с инъекциями и законными близнецами, шесть форм записи); `go test -count=1 ./gateway/internal/middleware/ -run TestAuthz_3029_UndecidedRefusalNamesNoInternalService` → код 0, PASS 1. Конвейер: юниты internal юниты gateway — success.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/apigw-middleware]] — гейт текста отказа наружу (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4
- [[KAC/issue-2996]]

#kac #kacho-api-gateway
