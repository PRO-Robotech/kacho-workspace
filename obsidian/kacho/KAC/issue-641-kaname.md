---
title: "kaname#641: security: текст ошибки RPC раскрывает адреса участников"
aliases:
  - issue-641-kaname
  - kaname#641
ticket_id: 641
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps
  - internal/check
  - internal/repo
prs:
  - https://github.com/PRO-Robotech/kaname/pull/668
issue_url: https://github.com/PRO-Robotech/kaname/issues/641
opened: 2026-10-07
closed: 2026-10-08
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "kaname 296: коммит слияния PR #668 = 8b0379e2a9c5 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @85bdb3d5e70d; пробы и конвейер этой записью не перезапускались"
---

# kaname#641: security: текст ошибки RPC раскрывает адреса участников

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kaname#668](https://github.com/PRO-Robotech/kaname/pull/668) (сборка 6b волны-6) влит в ветку эпика `296` коммитом слияния `8b0379e2a9c5` 2026-10-08.

## Что и зачем

Адрес почты не уходит в текст отказа RPC и в журнал. Разбор — по диффу (PR kaname#668), не здесь.

## Затронутые каталоги

`internal/apps`, `internal/check`, `internal/repo` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `8b0379e2a9c5` (kaname#668);
- [x] DoD-proof @`85bdb3d5e70d` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/641#issuecomment-6049437589): go test -race -short -count=1 ./internal/check/... ./internal/apps/kaname/api/internal_iam/... + go test -count=1 ./internal/repo/kaname/pg/... → ok (0 FAIL)
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam
