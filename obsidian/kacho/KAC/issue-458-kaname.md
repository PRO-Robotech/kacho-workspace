---
title: "kaname#458: iam: адрес, занятый неподтверждённой записью, — путь владельца ящика"
aliases:
  - issue-458-kaname
  - kaname#458
ticket_id: 458
category: kac
status: test
type: feature
repos:
  - kaname
areas:
  - docs/engineering
  - internal/apps
  - internal/migrations
  - internal/repo
  - internal/handler
  - tests/newman
prs:
  - https://github.com/PRO-Robotech/kaname/pull/706
  - https://github.com/PRO-Robotech/kaname/pull/713
issue_url: https://github.com/PRO-Robotech/kaname/issues/458
opened: 2026-09-27
closed: 2026-10-12
tags:
  - kac
  - feature
  - kacho-iam
verified_against: "`gh` 2026-10-12: kaname PR #706 MERGED в `296` 2026-10-11T23:46Z коммитом слияния a29c15cf4085; kaname PR #713 MERGED в `296` 2026-10-12T07:19Z коммитом слияния 31711b375785; состояние задачи — `gh issue view` (CLOSED 2026-10-12); DoD — комментарии задачи, названные в записке; прогоны этой записью не перезапускались"
---

# kaname#458: iam: адрес, занятый неподтверждённой записью, — путь владельца ящика

> [!note] Состояние — `test`: задача закрыта 2026-10-12, работа в ветке эпика `296`, в `main` не влита
> Статус `done` — после посадки эпика в `main` (каскад закрытия, `git-issues.md#gi-close-cascade`).

## Что и зачем

Решение владельца 2026-09-27: вход дальше экрана регистрации или логина — только после подтверждения почты. Адрес, занятый неподтверждённой учётной записью, переходит к тому, кто подтвердит владение ящиком. Сначала приёмка (PR #706), затем реализация (PR #713).

## Затронутые каталоги

`docs/engineering`, `internal/apps`, `internal/migrations`, `internal/repo`, `internal/handler`, `tests/newman` (PRO-Robotech/kaname). Ветка задачи — `458` (координата, не живая ссылка).

## Вливания

| запрос | база | коммит слияния | влит (UTC) | что |
|---|---|---|---|---|
| [kaname#706](https://github.com/PRO-Robotech/kaname/pull/706) | `296` | `a29c15cf4085` | 2026-10-11T23:46Z | приёмка |
| [kaname#713](https://github.com/PRO-Robotech/kaname/pull/713) | `296` | `31711b375785` | 2026-10-12T07:19Z | реализация |

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено.

- [x] влито в `296` — коммит слияния `a29c15cf4085` (kaname#706);
- [x] влито в `296` — коммит слияния `31711b375785` (kaname#713);
- [x] закрытие — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/458#issuecomment-6119637563): пп. 1–8 — комментарии DoD-proof задачи; работа e21f12226, cf3b4c26f, 6ff530132, пробы befa56661, 893c2a59d;
- [x] DoD-proof п.10 — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/458#issuecomment-6119634917): кейс newman на автономном стенде, прогон 38210075984: отказов 0;
- [ ] влито в `main` — нет: эпик в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-296-kaname]] — эпик службы доступа

## History

- 2026-10-12 — trail заведён после вливания (kaname#706, kaname#713); статус `test` (ws#1035).

#kac #feature #kacho-iam
