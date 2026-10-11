---
title: "kaname#630: mailHeaders: добавить Date и Message-ID в SMTP"
aliases:
  - issue-630-kaname
  - kaname#630
ticket_id: 630
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/clients
prs:
  - https://github.com/PRO-Robotech/kaname/pull/640
issue_url: https://github.com/PRO-Robotech/kaname/issues/630
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "kaname 296: коммит слияния PR #640 = 76ca2c8aa6e0 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @0dda81eb7656; пробы и конвейер этой записью не перезапускались"
---

# kaname#630: mailHeaders: добавить Date и Message-ID в SMTP

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kaname#640](https://github.com/PRO-Robotech/kaname/pull/640) (первая сборка волны-6) влит в ветку эпика `296` коммитом слияния `76ca2c8aa6e0` 2026-10-07.

## Что и зачем

Письма службы несут заголовки `Date` и `Message-ID`.

## Затронутые каталоги

`internal/clients` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `76ca2c8aa6e0` (kaname#640);
- [x] DoD-proof @`0dda81eb7656` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/630#issuecomment-6028521816): go test -count=1 -race -v ./internal/clients/... → 2 пакета ok, исполнено 41 (верхних тестов 29 + подтестов 12), отказов 0, пропущено 0.
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam
