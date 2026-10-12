---
title: "kacho#3060: чарт консоли: discovery церемонии OAuth не доходит до края"
aliases:
  - issue-3060
  - kacho#3060
ticket_id: 3060
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - ui-future/deploy
  - deploy/helm
  - docs/architecture
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/3060
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-ui
  - kacho-deploy
verified_against: "kacho 1266: коммит слияния PR #3073 = 8725b886e124 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @c673d9961512; пробы и конвейер этой записью не перезапускались"
---

# kacho#3060: чарт консоли: discovery церемонии OAuth не доходит до края

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073) (первая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `8725b886e124` 2026-10-07.

## Что и зачем

Discovery церемонии OAuth не доходил до края через вход консоли. Чарт консоли объявляет церемонию на входе консоли; фронт консоли стенда берётся из релиза (коммит полосы #3024).

## Затронутые каталоги

`ui-future/deploy`, `deploy/helm`, `docs/architecture` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `8725b886e124` (kacho#3073);
- [x] DoD-proof @`c673d9961512` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3060#issuecomment-6036276361): go test -count=1 ./ui-future/deploy/... -run 'TestConsoleDiscovery' -v → код 0, исполнено 2, отказов 0; go test -count=1 ./ui-future/deploy/... ./deploy/... -run "Console" -v → код 0, исполнено 30, отказов 0, пропусков 0; go test -count=1 -…
- [ ] стендовая часть — подзадача kacho#3067 волны-6: проверяется после выкатки волны (стенд не перекачен, см. [[KAC/issue-2969]]).
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #fix #kacho-ui #kacho-deploy
