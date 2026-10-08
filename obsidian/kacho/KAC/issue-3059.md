---
title: "kacho#3059: e2e playwright: ключи доступа сквозь консоль — завести, войти, удалить"
aliases:
  - issue-3059
  - kacho#3059
ticket_id: 3059
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - .github/scripts
  - ui-future/e2e
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3095
issue_url: https://github.com/PRO-Robotech/kacho/issues/3059
opened: 2026-10-06
closed: 2026-10-08
tags:
  - kac
  - feature
  - kacho-test
  - kacho-ui
verified_against: "kacho 1266: коммит слияния PR #3095 = 1fd076f80965 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @a53849e32a15; пробы и конвейер этой записью не перезапускались"
---

# kacho#3059: e2e playwright: ключи доступа сквозь консоль — завести, войти, удалить

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3095](https://github.com/PRO-Robotech/kacho/pull/3095) (вторая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `1fd076f80965` 2026-10-08.

## Что и зачем

Сквозная браузерная проба ключа доступа: завести, войти, удалить. F8S4-03 переутверждён по редакции 4 приёмки F8-S4 ([[KAC/issue-897-ws]]): наблюдаемый исход браузера — отказ и следующий шаг; уровень «2» ключа без проверки пользователя остаётся за пробой службы.

## Затронутые каталоги

`.github/scripts`, `ui-future/e2e` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `1fd076f80965` (kacho#3095);
- [x] DoD-proof @`a53849e32a15` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3059#issuecomment-6053269413): console-e2e (свой стенд, ключи включены) https://github.com/PRO-Robotech/kacho/actions/runs/37729171597 → 227 passed, 0 failed, 0 skipped; access-key-lifecycle.spec.ts F8S4-02 (уровень «3») и F8S4-03 — зелёные; инъекция чужого происхождения…
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- [[resources/kaname-access-key]]

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #feature #kacho-test #kacho-ui
