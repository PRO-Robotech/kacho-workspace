---
title: "kacho#2955: консоль: страж адреса без признака края запирает консоль целиком"
aliases:
  - issue-2955
  - kacho#2955
ticket_id: 2955
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - ui-future/shared
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3095
issue_url: https://github.com/PRO-Robotech/kacho/issues/2955
opened: 2026-10-01
closed: 2026-10-08
tags:
  - kac
  - fix
  - kacho-ui
verified_against: "kacho 1266: коммит слияния PR #3095 = 1fd076f80965 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @a53849e32a15; пробы и конвейер этой записью не перезапускались"
---

# kacho#2955: консоль: страж адреса без признака края запирает консоль целиком

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3095](https://github.com/PRO-Robotech/kacho/pull/3095) (вторая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `1fd076f80965` 2026-10-08.

## Что и зачем

Страж адреса без признака края запирал консоль целиком. Ответ о сессии без признака подтверждённости ведёт на страницу, которая называет шаг и адресата и не несёт внутреннего слова. Древесная часть — коммит полосы #2952.

## Затронутые каталоги

`ui-future/shared` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `1fd076f80965` (kacho#3095);
- [x] DoD-proof @`a53849e32a15` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2955#issuecomment-6053267987): console-e2e (свой стенд) https://github.com/PRO-Robotech/kacho/actions/runs/37729171597 → 227 passed, 0 failed, 0 skipped; проба «2955 · ответ о сессии без признака подтверждённости: страница без «край», шаг и адресат названы» (recovery.spe…
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #fix #kacho-ui
