---
title: "kacho#3026: deploy: own-up не перекатывает поды консоли на новый образ"
aliases:
  - issue-3026
  - kacho#3026
ticket_id: 3026
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - deploy/Makefile
  - deploy/scripts
  - deploy/tests/helm
  - ui-future/deploy/templates
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/3026
opened: 2026-10-04
closed: 2026-10-06
tags:
  - kac
  - kacho-deploy
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3026: deploy: own-up не перекатывает поды консоли на новый образ

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

`own-up` перекатывает поды консоли на новый образ: образы сборки консоли привязаны к шаблонам подов дайджестом платформенного манифеста; при неизменном образе переката нет; выход посева стенда не отслеживается и судится по индексу git.

## Затронутые каталоги

`deploy/Makefile`, `deploy/scripts`, `deploy/tests/helm`, `ui-future/deploy/templates` (PRO-Robotech/kacho).

Коммиты в составе волны: `bd49e5dda80`, `ae6fdb9f788`, `c09c4d800c9`, `dc7c362faba`, `75852049acf`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3026#issuecomment-6012638111): `bash deploy/tests/helm/image-rollout-binding-test.sh` → код 0, «привязано к содержимому своих образов: 16 (образов в предмете: 16)»; `bash deploy/tests/helm/image-ids-map-covers-built-images-test.sh` → код 0, 4 утверждения, расхождений 0; `go test -count=1 ./internal/repohygiene/ -run TestStandSeedOutput` → код 0, PASS 2. Живой замер на стенде own (`make own-up`, перекат при новом образе и его отсутствие при неизменном) — комментарий от 2026-10-05 (ветка 3025 @75852049acfb, предок `1266`). Конвейер: юниты deploy — success.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — перекат подов консоли (History 2026-10-06)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4

#kac #kacho-deploy
