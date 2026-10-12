---
title: "kacho#2947: край: values называет накладку own местом адреса полосы формы"
aliases:
  - issue-2947
  - kacho#2947
ticket_id: 2947
category: kac
status: test
type: docs
repos:
  - kacho
areas:
  - gateway/deploy/values.yaml
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/2947
opened: 2026-10-01
closed: 2026-10-07
tags:
  - kac
  - docs
  - kacho-api-gateway
  - kacho-deploy
verified_against: "kacho 1266: коммит слияния PR #3073 = 8725b886e124 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @775621f1115e; пробы и конвейер этой записью не перезапускались"
---

# kacho#2947: край: values называет накладку own местом адреса полосы формы

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073) (первая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `8725b886e124` 2026-10-07.

## Что и зачем

Комментарий у адреса полосы формы в values края называл накладку `values.own.yaml` местом этого адреса; накладки в цепочке нет. Комментарий называет корни цепочек профиля. Закрыта той же работой, что [[KAC/issue-2717]] (коммит полосы #2717).

## Затронутые каталоги

`gateway/deploy/values.yaml` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `8725b886e124` (kacho#3073);
- [x] DoD-proof @`775621f1115e` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2947#issuecomment-6034489257): git grep -n "values.own.yaml" 775621f1115ee641127f590a9aca7e62a361d971 -- gateway/deploy/values.yaml | wc -l → 0 (было 1, :335); комментарий у authn.iamLoginLaneUrl называет корни цепочек deploy/helm/umbrella/values.prod.yaml и values.dev.y…
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #docs #kacho-api-gateway #kacho-deploy
