---
title: "kacho#3057: консоль: заведение, перечень и удаление ключей доступа на /settings"
aliases:
  - issue-3057
  - kacho#3057
ticket_id: 3057
category: kac
status: test
type: feature
repos:
  - kacho
areas:
  - ui-future/shared
  - ui-future/e2e
  - gateway/internal
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3095
issue_url: https://github.com/PRO-Robotech/kacho/issues/3057
opened: 2026-10-06
closed: 2026-10-08
tags:
  - kac
  - feature
  - kacho-ui
  - kacho-api-gateway
verified_against: "kacho 1266: коммит слияния PR #3095 = 1fd076f80965 (gh pr view → MERGED 2026-10-08); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-08); DoD — комментарий задачи DoD-proof @a53849e32a15; пробы и конвейер этой записью не перезапускались"
---

# kacho#3057: консоль: заведение, перечень и удаление ключей доступа на /settings

> [!note] Состояние — `test`: задача закрыта 2026-10-08, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3095](https://github.com/PRO-Robotech/kacho/pull/3095) (вторая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `1fd076f80965` 2026-10-08.

## Что и зачем

Заведение, перечень и удаление ключей доступа на `/settings`; клиент ключей — транспорт в `api/`, исход единым сигналом; «не использовался» — в контракте края. Браузерные F8-48…F8-57 зелёные на своём стенде конвейера.

## Затронутые каталоги

`ui-future/shared`, `ui-future/e2e`, `gateway/internal` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `1fd076f80965` (kacho#3095);
- [x] DoD-proof @`a53849e32a15` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3057#issuecomment-6053268706): console-e2e (свой стенд) https://github.com/PRO-Robotech/kacho/actions/runs/37729171597 → 227 passed, 0 failed, 0 skipped; F8-48, F8-49, F8-50, F8-51, F8-56, F8-57 (account-access-keys.spec.ts, // verifies #3057) — зелёные; отказ браузера в…
- [ ] стендовая часть — подзадача kacho#3068 волны-6: проверяется после выкатки волны (стенд не перекачен, см. [[KAC/issue-2969]]).
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- [[resources/kaname-access-key]]

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #feature #kacho-ui #kacho-api-gateway
