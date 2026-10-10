---
title: "kaname#643: docs: записи Ф13 в ведомости долга устарели"
aliases:
  - issue-643-kaname
  - kaname#643
ticket_id: 643
category: kac
status: test
type: docs
repos:
  - kaname
areas:
  - tests/newman
  - .github/scripts
  - tests/authz-fixtures
prs:
  - https://github.com/PRO-Robotech/kaname/pull/668
issue_url: https://github.com/PRO-Robotech/kaname/issues/643
opened: 2026-10-07
closed: 2026-10-08
tags:
  - kac
  - docs
  - kacho-iam
  - kacho-test
verified_against: "kaname 296: коммит слияния PR #668 = 8b0379e2a9c5 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @71334e2741ea; пробы и конвейер этой записью не перезапускались"
---

# kaname#643: docs: записи Ф13 в ведомости долга устарели

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kaname#668](https://github.com/PRO-Robotech/kaname/pull/668) (сборка 6b волны-6) влит в ветку эпика `296` коммитом слияния `8b0379e2a9c5` 2026-10-08.

## Что и зачем

Записи Ф13 ведомости долга newman устарели после посадки входа ключом. Вход ключом покрыт сквозными кейсами; записей долга Ф13 стало 8 (было 27) — со слов DoD-proof задачи.

## Затронутые каталоги

`tests/newman`, `.github/scripts`, `tests/authz-fixtures` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `8b0379e2a9c5` (kaname#668);
- [x] DoD-proof @`71334e2741ea` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/643#issuecomment-6050022265): python3 .github/scripts/newman-suite-debt.py → код 0; записей долга Ф13 — 8 (было 27), доводов «полосы входа ключом в дереве нет» — 0; прогон e2e-newman 37706122915 на этой голове: 8/8 коллекций отчиталось, 2843 запросов, 7319 утверждений,…
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #docs #kacho-iam #kacho-test
