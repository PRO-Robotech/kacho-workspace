---
title: "ws#924: проба пишет фикстуру в рабочий каталог общего клона вместо временного"
aliases:
  - issue-924-ws
  - ws#924
ticket_id: 924
category: kac
status: done
type: fix
repos:
  - kacho-workspace
areas:
  - scripts/lib/product-fixture.sh
  - scripts/docs-gate
  - scripts/skills-gate
prs:
  - https://github.com/PRO-Robotech/kacho-workspace/pull/927
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/924
opened: 2026-09-22
closed: 2026-10-07
tags:
  - kac
  - fix
  - conventions
verified_against: "kacho-workspace main: коммит слияния PR #927 = a338e47692f6 (gh pr view → MERGED 2026-10-07T22:04Z; git log origin/main); файлы — gh pr view --json files; состояние задачи — gh issue view 2026-10-08 (CLOSED; sub-issue kaname#540); DoD — комментарий задачи DoD-proof @c16590b21b9d; самопробы этой записью не перезапускались"
---

# ws#924: проба пишет фикстуру в рабочий каталог общего клона вместо временного

> [!note] Состояние — `done`: влито в `main` воркспейса
> Запрос [ws#927](https://github.com/PRO-Robotech/kacho-workspace/pull/927) влит коммитом слияния `a338e47692f6`
> 2026-10-07; задача закрыта как completed. В трекере стоит подзадачей волны службы [[KAC/issue-540-kaname]]
> (перенесена из волны-5).

## Что и зачем

Фикстура продукта создавалась внутри рабочей копии общего клона и оставалась там следом. Страж
`product_fixture_outside_worktree` в `product_fixture_init` отвергает каталог внутри любой рабочей копии git
(код 2), перепись места фикстур печатается в выводе доказательств docs-gate и skills-gate; фикстуры
skills-gate вынесены в отдельный временный корень.

## Затронутые каталоги

`scripts/lib/product-fixture.sh`, `scripts/docs-gate/{inject.sh,inject-10.sh,README.md}`, `scripts/skills-gate/inject.sh`
(PRO-Robotech/kacho-workspace).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в `main` — коммит слияния `a338e47692f6` (ws#927);
- [x] DoD-proof @`c16590b21b9d` — [комментарий задачи](https://github.com/PRO-Robotech/kacho-workspace/issues/924#issuecomment-6047578542): inject-10 10/10, docs-gate 9/9, skills-gate 7/7.

## Затронутые сущности vault

- — (узких записок предмет не трогает: оснастка воркспейса)

## Связанные задачи

- [[KAC/issue-967-ws]] — норма «прогон не оставляет следов»
- [[KAC/issue-540-kaname]] — волна, в которой задача закрыта

#kac #fix #conventions
