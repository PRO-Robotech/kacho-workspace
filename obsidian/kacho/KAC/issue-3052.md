---
title: "kacho#3052: deploy: профиль a8f60d не поднимает стенд без подстановок --set"
aliases:
  - issue-3052
  - kacho#3052
ticket_id: 3052
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - deploy
  - deploy/helm/umbrella
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3073
issue_url: https://github.com/PRO-Robotech/kacho/issues/3052
opened: 2026-10-06
closed: 2026-10-07
tags:
  - kac
  - fix
  - kacho-deploy
verified_against: "kacho 1266: коммит слияния PR #3073 = 8725b886e124 (gh pr view → MERGED 2026-10-07); состояние задачи — gh issue view 2026-10-08 (CLOSED 2026-10-07); DoD — комментарий задачи DoD-proof @4157f4fbf68d; пробы и конвейер этой записью не перезапускались"
---

# kacho#3052: deploy: профиль a8f60d не поднимает стенд без подстановок --set

> [!note] Состояние — `test`: задача закрыта 2026-10-07, работа в ветке эпика, в `main` не влита
> Запрос [kacho#3073](https://github.com/PRO-Robotech/kacho/pull/3073) (первая сборка волны-6) влит в ветку эпика `1266` коммитом слияния `8725b886e124` 2026-10-07.

## Что и зачем

Профиль a8f60d не поднимал стенд без подстановок `--set`. Пины образов профиля выводятся из записи «порождено-от», пол ёмкости проверяющего и достижимость опубликованного образа судятся пробами `deploy/`.

## Затронутые каталоги

`deploy`, `deploy/helm/umbrella` (PRO-Robotech/kacho).

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] влито в ветку эпика `1266` — коммит слияния `8725b886e124` (kacho#3073);
- [x] DoD-proof @`4157f4fbf68d` — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3052#issuecomment-6035119898): KACHO_IMAGE_REGISTRY_CHECK=1 go test ./deploy/ -run 'TestPublishedProductImagePinIsReachable|TestManagedProfile|TestOutsourcedImagePinAgreesWithItsModulePin|TestProductImagePinsAreDerivedFromTheRecordedCommit|TestVerifierCapacityFloor' -v →…
- [ ] стендовая часть — подзадача kacho#3064 волны-6: проверяется после выкатки волны (стенд не перекачен, см. [[KAC/issue-2969]]).
- [ ] влито в `main` — нет: эпик `1266` в `main` не сведён.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]]

## Связанные задачи

- [[KAC/issue-2969]] — волна-6
- [[KAC/issue-1266]] — эпик платформы

#kac #fix #kacho-deploy
