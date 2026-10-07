---
title: "kacho#3044: docs: подъём уязвимых пакетов в lockfile сайтов документации"
aliases:
  - issue-3044
  - kacho#3044
ticket_id: 3044
category: kac
status: test
type: fix
repos:
  - kacho
areas:
  - "*/docs/package-lock.json"
prs:
  - https://github.com/PRO-Robotech/kacho/pull/3043
issue_url: https://github.com/PRO-Robotech/kacho/issues/3044
opened: 2026-10-06
closed: 2026-10-06
tags:
  - kac
  - kacho-deploy
  - docs
verified_against: "kacho 1266@680d1794b6b8 (коммит слияния PR #3043, родители e3476f0bc280 + a3d38ec4ebbb; голова origin/1266 = этот коммит, git ls-remote 2026-10-06): состав — git log e3476f0bc280..680d1794 --no-merges --grep; состояние задачи — gh issue view 2026-10-06; DoD — по комментарию DoD-proof задачи; пробы и конвейер этой записью не перезапускались"
---

# kacho#3044: docs: подъём уязвимых пакетов в lockfile сайтов документации

> [!note] Состояние — `test`: задача ЗАКРЫТА в трекере вливанием волны в ветку эпика, в `main` не влито
> Волна [[KAC/issue-2967]] влита в `1266` коммитом слияния `680d1794b6b8` ([kacho#3043](https://github.com/PRO-Robotech/kacho/pull/3043)), задача закрыта 2026-10-06 как completed. Состояние `done` — после вливания эпика в `main`.

## Что и зачем

Подъём уязвимых транзитивных пакетов в lockfile семи сайтов документации до исправленных версий (P0: новые записи базы уязвимостей роняли проверку `trivy` на любой ревизии, не только на волне).

## Затронутые каталоги

`*/docs/package-lock.json` (PRO-Robotech/kacho).

Коммиты в составе волны: `8ced7b6648a`.

## DoD

Отметка `[x]` — предъявлено артефактом, названным в строке; `[ ]` — не выполнено либо не доказано, причина в строке.

- [x] работа в ветке эпика `1266` — коммит слияния волны `680d1794b6b8`;
- [x] DoD-proof — [комментарий задачи](https://github.com/PRO-Robotech/kacho/issues/3044#issuecomment-6012649653): проверка конвейера `trivy (fs + IaC)` на `a3d38ec4ebbb` — success ( HIGH+CRITICAL по сайтам документации — 0; `docs-sites` — success ( Правка — ветка issue-3044 @8ced7b6648a0, предок `1266`. Блокер «Blocked by #2967» снят вливанием волны.
- [ ] эпик влит в `main` — нет.

## Затронутые сущности vault

- — (узких записок предмет не трогает)

## Связанные задачи

- [[KAC/issue-2967]] — волна-4

#kac #kacho-deploy #docs
