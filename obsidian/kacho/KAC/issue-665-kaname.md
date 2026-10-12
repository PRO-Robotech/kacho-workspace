---
title: "kaname#665: bug P2: удаление проекта оставляет факты выдачи в модели прав"
aliases:
  - issue-665-kaname
  - kaname#665
ticket_id: 665
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - internal/apps
  - internal/repo/kaname/pg
prs:
  - https://github.com/PRO-Robotech/kaname/pull/668
issue_url: https://github.com/PRO-Robotech/kaname/issues/665
opened: 2026-10-07
closed: 2026-10-08
tags:
  - kac
  - fix
  - kacho-iam
verified_against: "kaname 296: коммит слияния PR #668 = 8b0379e2a9c5 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @0fffe35157ea; пробы и конвейер этой записью не перезапускались"
---

# kaname#665: bug P2: удаление проекта оставляет факты выдачи в модели прав

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kaname#668](https://github.com/PRO-Robotech/kaname/pull/668) (сборка 6b волны-6) влит в ветку эпика `296` коммитом слияния `8b0379e2a9c5` 2026-10-08.

## Что и зачем

Удаление проекта не оставляет фактов выдачи в модели прав. Разбор — по диффу (PR kaname#668), не здесь.

## Затронутые каталоги

`internal/apps`, `internal/repo/kaname/pg` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `8b0379e2a9c5` (kaname#668);
- [x] DoD-proof @`0fffe35157ea` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/665#issuecomment-6049666322): go test -count=1 -run 'TestProjectDelete_LeavesNoFactsNamingTheProject|TestProjectDelete_BootstrapBindingObjectLeavesNoFacts|TestAccountDelete_LeavesNoFactsOfItsBindings' ./internal/repo/kaname/pg/ → ok, 3 из 3 PASS
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam
