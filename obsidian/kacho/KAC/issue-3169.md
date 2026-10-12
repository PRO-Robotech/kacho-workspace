---
title: "kacho#3169: ci: синхронизация ветки эпика 1266 со стволом main"
aliases:
  - issue-3169
  - kacho#3169
ticket_id: 3169
category: kac
status: test
type: refactor
repos:
  - kacho
areas:
  - gateway/internal/cmuxh2
  - deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3170
issue_url: https://github.com/PRO-Robotech/kacho/issues/3169
opened: 2026-10-12
closed: 2026-10-12
tags:
  - kac
  - refactor
  - kacho-api-gateway
  - kacho-deploy
verified_against: "`gh` 2026-10-12: kacho PR #3170 MERGED в `1266` 2026-10-12T13:24Z коммитом слияния 41ea276b288c; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались, кроме предиката `merge-base --is-ancestor` на origin/1266 @fd9f1793e70d (код 0)"
---

# kacho#3169: ci: синхронизация ветки эпика 1266 со стволом main

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Ветка эпика `1266` отставала от `main`. Ствол влит в `1266` через ветку задачи с разрешёнными конфликтами; из ствола пришли #3134, #3024, #3012, #3011 (перечень и разрешения — в описании PR).

## Затронутые каталоги

`gateway/internal/cmuxh2`, `deploy` (PRO-Robotech/kacho). Ветка задачи — `3169-sync-main-into-1266` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3170](https://github.com/PRO-Robotech/kacho/pull/3170) | `1266` | `41ea276b288c` | 2026-10-12T13:24Z | синхронизация `main` → `1266` |

Комментария формы `DoD-proof` у задачи нет; исход предиката — в комментарии сдачи и перемерен этой записью. Заменил запрос kacho#3160.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `41ea276b288c` (kacho#3170);
- [x] сдача — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3169#issuecomment-6125201967): предикат `git merge-base --is-ancestor origin/main origin/1266` — код 0 (со слов комментария); перемерено этой записью 2026-10-12 на origin/1266 @fd9f1793e70d — код 0;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)

## History

- 2026-10-12 — trail заведён после вливания (kacho#3170); статус `test` (ws#1035).

#kac #refactor #kacho-api-gateway #kacho-deploy
