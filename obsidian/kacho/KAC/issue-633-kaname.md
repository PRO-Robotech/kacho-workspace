---
title: "kaname#633: newman: Ф5-14 — доставка письма восстановления и возраст неотправленного"
aliases:
  - issue-633-kaname
  - kaname#633
ticket_id: 633
category: kac
status: test
type: fix
repos:
  - kaname
areas:
  - tests/newman
  - tests/authz-fixtures
  - .github/scripts
prs:
  - https://github.com/PRO-Robotech/kaname/pull/640
issue_url: https://github.com/PRO-Robotech/kaname/issues/633
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-iam
  - kacho-test
verified_against: "kaname 296: коммит слияния PR #640 = 76ca2c8aa6e0 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @6b4c6e80de9d; пробы и конвейер этой записью не перезапускались"
---

# kaname#633: newman: Ф5-14 — доставка письма восстановления и возраст неотправленного

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kaname#640](https://github.com/PRO-Robotech/kaname/pull/640) (первая сборка волны-6) влит в ветку эпика `296` коммитом слияния `76ca2c8aa6e0` 2026-10-07.

## Что и зачем

Ф5-14 — доставка письма восстановления и возраст неотправленного — получила сквозные кейсы набора. Работа вошла коммитами под номером kaname#614 (полоса N-E2E); задача закрыта комментарием со ссылкой на коммит.

## Затронутые каталоги

`tests/newman`, `tests/authz-fixtures`, `.github/scripts` (PRO-Robotech/kaname).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `296` — коммит слияния `76ca2c8aa6e0` (kaname#640);
- [x] DoD-proof @`6b4c6e80de9d` — [комментарий задачи](https://github.com/PRO-Robotech/kaname/issues/633#issuecomment-6029515538): gh workflow run e2e-newman.yml --ref 614 → прогон 37557871652, conclusion success; задание chart-own: 7/7 коллекций, 2183 запроса, 5571 утверждение, упавших 0, без ответа 0.
- [ ] влито в `main` — нет: эпик `296` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-540-kaname]] — волна-6
- [[KAC/issue-296-kaname]] — эпик службы

#kac #fix #kacho-iam #kacho-test
