---
title: "kacho#2952: консоль: восстановление доступа объявлено, экрана нет"
aliases:
  - issue-2952
  - kacho#2952
ticket_id: 2952
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - ui-future/shared
  - ui-future/host
  - ui-future/e2e
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3095
issue_url: https://github.com/PRO-Robotech/kacho/issues/2952
opened: 2026-10-01
closed: 2026-10-08
tags:
  - kac
  - feature
  - kacho-ui
  - kacho-test
verified_against: "kacho 1266: коммит слияния PR #3095 = 1fd076f80965 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @a53849e32a15; пробы и конвейер этой записью не перезапускались"
---

# kacho#2952: консоль: восстановление доступа объявлено, экрана нет

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3095](https://github.com/PRO-Robotech/kacho/pull/3095) (вторая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `1fd076f80965` 2026-10-08.

## Что и зачем

Восстановление доступа было объявлено, а экрана не было. Экран восстановления в консоли, шаг к отказам 16 и 9, страница стража без внутреннего слова; браузерные F8S3-01…16 зелёные на своём стенде конвейера.

## Затронутые каталоги

`ui-future/shared`, `ui-future/host`, `ui-future/e2e`, `.github/workflows` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `1fd076f80965` (kacho#3095);
- [x] DoD-proof @`a53849e32a15` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/2952#issuecomment-6053267260): console-e2e «сквозные пробы консоли (свой стенд)» https://github.com/PRO-Robotech/kacho/actions/runs/37729171597 → 227 passed, 0 failed, 0 skipped; F8S3-01…F8S3-16 (ui-future/e2e/specs/recovery.spec.ts, // verifies #2952) — зелёные. Решение…
- [ ] стендовая часть — подзадача kacho#3068 волны-6: проверяется после выкатки волны (стенд не перекачен, см. [[KAC/issue-2969]]).
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #feature #kacho-ui #kacho-test
