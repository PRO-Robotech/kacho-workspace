---
title: "kacho#3194: сборка волны 1266 — пин kaname, каталог края, консоль смены адреса"
aliases:
  - issue-3194
ticket_id: 3194
category: kac
status: done
type: feature
repos:
  - kacho
areas:
  - gateway
  - ui-future
  - deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3195
  - https://github.com/PRO-Robotech/kacho/pull/3158
issue_url: https://github.com/PRO-Robotech/kacho/issues/3194
opened: 2026-10-13
closed: 2026-10-14
tags:
  - kac
  - feature
verified_against: "kacho: PR #3195 MERGED в 1266, коммит слияния 0f1b467da88a (gh pr view, по DoD-proof задачи); 0f1b467da88a — предок main@dd9739fe6dfe (git merge-base --is-ancestor, код 0, 2026-10-14); состояние задачи — gh issue view 2026-10-14; прогоны этой записью не перезапускались"
---

# kacho#3194: сборка волны 1266 — пин kaname, каталог края, консоль смены адреса

**Status**: `done` — задача закрыта 2026-10-14 каскадом посадки эпика [[KAC/issue-1266]] в `main`.
**Type**: feature (сборка). **Родитель**: [[KAC/issue-1266]].

## Что и зачем

Сборка последних полос эпика в его ветку. Ветки kacho#3193 и kacho#3192 сведены `git merge --no-ff`
в ветку сборки от `1266`, и в `1266` ушёл один запрос сборки. Предметы полос — пин kaname, каталог
края и консоль смены адреса. Каждый описан в своей задаче. Ревизия этой сборки, `1266-0f1b467d`,
стоит на стенде на 2026-10-14 (см. [[KAC/issue-1266]]).

## PR и ревизия

- Сборка: https://github.com/PRO-Robotech/kacho/pull/3195 в `1266`, голова `76718c6db0a6`, коммит
  слияния `0f1b467da88a`.
- В `main` — с эпиком: https://github.com/PRO-Robotech/kacho/pull/3158, коммит слияния `dd9739fe6dfe`.

## DoD

Доказательство — комментарий DoD-proof: https://github.com/PRO-Robotech/kacho/issues/3194#issuecomment-6162266037.

- [x] Обе головы, `b7e335c699` (#3193) и `09a9ff0b5` (#3192), — предки головы сборки.
- [x] Запрос сборки влит в `1266`. Конвейер на его голове: 8 процессов из 8 — `success`, красных 0.
- [x] kacho#3192 и kacho#3193 закрыты. Ветки полос и сборки сняты.

## Затронутые сущности vault

Узких записок задача не меняет: перечня затронутых сущностей у неё нет.

## Связанные задачи

- [[KAC/issue-1266]] — эпик, в ветку которого шла сборка

## History

- 2026-10-14 — trail заведён при посадке эпика: статус `done`, PR #3195 и #3158, DoD-proof (#1266).

#kac #feature
