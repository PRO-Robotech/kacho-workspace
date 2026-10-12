---
title: "kacho#3058: консоль: первый пароль из сессии у человека без пароля"
aliases:
  - issue-3058
  - kacho#3058
ticket_id: 3058
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - ui-future/shared
  - ui-future/e2e
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3095
issue_url: https://github.com/PRO-Robotech/kacho/issues/3058
opened: 2026-10-06
closed: 2026-10-08
tags:
  - kac
  - feature
  - kacho-ui
verified_against: "kacho 1266: коммит слияния PR #3095 = 1fd076f80965 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @a53849e32a15; пробы и конвейер этой записью не перезапускались"
---

# kacho#3058: консоль: первый пароль из сессии у человека без пароля

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3095](https://github.com/PRO-Robotech/kacho/pull/3095) (вторая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `1fd076f80965` 2026-10-08.

## Что и зачем

Первый пароль из сессии у человека без пароля: экран консоли над глаголом края [[KAC/issue-3056]]; глагол объявлен в перехвате ответов проб (F8-63).

## Затронутые каталоги

`ui-future/shared`, `ui-future/e2e` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `1fd076f80965` (kacho#3095);
- [x] DoD-proof @`a53849e32a15` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3058#issuecomment-6053269794): console-e2e (свой стенд) https://github.com/PRO-Robotech/kacho/actions/runs/37729171597 → 227 passed, 0 failed, 0 skipped; F8-63 (account-settings.spec.ts:465, // verifies #3058) — зелёная (на локальном стенде было «не выполнилось» ×3, усло…
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #feature #kacho-ui
