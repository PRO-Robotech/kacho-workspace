---
title: "kacho#3155: стенд: пины образов профиля a8f60d на голову волны 7"
aliases:
  - issue-3155
  - kacho#3155
ticket_id: 3155
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - deploy/helm/umbrella
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3156
issue_url: https://github.com/PRO-Robotech/kacho/issues/3155
opened: 2026-10-12
closed: 2026-10-12
tags:
  - kac
  - feature
  - kacho-deploy
verified_against: "`gh` 2026-10-12: kacho PR #3156 MERGED в `1266` 2026-10-12T03:31Z коммитом слияния 7c58c384ce4c; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kacho#3155: стенд: пины образов профиля a8f60d на голову волны 7

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `1266`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Профиль управляемого стенда a8f60d нёс пины головы волны 6: выкатка волны 7 из git была невыводима. Пины профиля подняты на голову волны 7 — выкатка выводится из git.

## Затронутые каталоги

`deploy/helm/umbrella` (PRO-Robotech/kacho). Ветка задачи — `3155-*` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kacho#3156](https://github.com/PRO-Robotech/kacho/pull/3156) | `1266` | `7c58c384ce4c` | 2026-10-12T03:31Z | запрос задачи |

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `1266` — коммит слияния `7c58c384ce4c` (kacho#3156);
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3155#issuecomment-6117208934): @47ada84356;
- [x] закрытие — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3155#issuecomment-6127453711): голова — предок origin/1266; родителя на волне нет, закрыта явно;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-1266]] — эпик identity-own; волна 7 — kacho#3101 (открыта)
- [[KAC/issue-2969]] — волна 6, родитель задачи

## History

- 2026-10-12 — trail заведён после вливания (kacho#3156); статус `test` (ws#1035).

#kac #feature #kacho-deploy
