---
title: "kaname#631: security: администратор в журнале без адреса"
aliases:
  - issue-631-kaname
  - kaname#631
ticket_id: 631
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps/kaname/seed
  - cmd/kaname
prs:
  - https://github.com/PRO-Robotech/kaname/pull/640
issue_url: https://github.com/PRO-Robotech/kaname/issues/631
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "kaname 296: коммит слияния PR #640 = 76ca2c8aa6e0 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @c218fa52e585; пробы и конвейер этой записью не перезапускались"
---

# kaname#631: security: администратор в журнале без адреса

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kaname#640](https://github.com/PRO-Robotech/kaname/pull/640) (первая сборка волны-6) влит в ветку эпика `296` коммитом слияния `76ca2c8aa6e0` 2026-10-07.

## Что и зачем

Посев больше не пишет адрес администратора в журнал. Разбор — по диффу (PR kaname#640), не здесь.

## Затронутые каталоги

`internal/apps/kaname/seed`, `cmd/kaname` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `76ca2c8aa6e0` (kaname#640);
- [x] DoD-proof @`c218fa52e585` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/631#issuecomment-6029574672): go test -count=1 -json ./internal/apps/kaname/seed/... ./cmd/kaname/... → исполнено 733 проб, отказов 0, пропущено 0 (2 пакета ok).
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam
