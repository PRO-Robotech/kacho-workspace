---
title: "kaname#280: полоса входа: пути слушателя объявлены дважды, равенство не держится"
aliases:
  - issue-280-kaname
  - kaname#280
ticket_id: 280
category: kac
status: test
type: refactor
repos:
  - kaname
areas:
  - internal/handler/loginlanehttp
prs:
  - https://github.com/PRO-Robotech/kaname/pull/640
issue_url: https://github.com/PRO-Robotech/kaname/issues/280
opened: 2026-09-18
closed: 2026-10-07
tags:
  - kac
  - refactor
  - kacho-iam
verified_against: "kaname 296: коммит слияния PR #640 = 76ca2c8aa6e0 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @8f96e12055ed; пробы и конвейер этой записью не перезапускались"
---

# kaname#280: полоса входа: пути слушателя объявлены дважды, равенство не держится

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kaname#640](https://github.com/PRO-Robotech/kaname/pull/640) (первая сборка волны-6) влит в ветку эпика `296` коммитом слияния `76ca2c8aa6e0` 2026-10-07.

## Что и зачем

Пути слушателя полосы входа были объявлены дважды, и равенство двух мест не держалось. `Paths()` сличается с обслуживаемым слушателем в обе стороны. Закрыта работой полосы #261.

## Затронутые каталоги

`internal/handler/loginlanehttp` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `76ca2c8aa6e0` (kaname#640);
- [x] DoD-proof @`8f96e12055ed` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/280#issuecomment-6028682628): go test -count=1 -json ./internal/handler/... ./internal/errors/... ./internal/refusaldomain/... ./internal/admission/... → исполнено 406 (пакетов 10), отказов 0, пропусков 0; go test -count=1 -short -run 'Paths' ./internal/handler/loginlan…
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- [[rpc/iam-login-lane]]

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #refactor #kacho-iam
