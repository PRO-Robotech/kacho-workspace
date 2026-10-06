---
title: "corelib#27: волна-1 corelib — движок OAuth2/OIDC в фундаменте"
aliases:
  - issue-27-corelib
ticket_id: 27
category: kac
status: done
type: epic
repos:
  - corelib
areas:
  - oauthceremony
  - oauth2
prs:
  - https://github.com/PRO-Robotech/corelib/pull/46
issue_url: https://github.com/PRO-Robotech/corelib/issues/27
opened: 2026-09-22
closed: 2026-09-23
tags:
  - kac
  - epic
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: запрос corelib#46 → `26` влит 2026-09-23 коммитом слияния 8dff416ec55 (`gh pr view 46`); трекер закрыт 2026-09-23, sub-issue закрыты 3 из 3 (`gh api .../sub_issues`); эпик corelib#26 влит в main запросом corelib#28 коммитом 2a8f797aa8c, предок origin/main (`git merge-base --is-ancestor`), 2026-10-03"
---

# corelib#27: волна-1 corelib — движок OAuth2/OIDC в фундаменте

**Состояние на 2026-10-03**: `done`, работа в `main`. Трекер закрыт 2026-09-23 (`completed`); эпик corelib#26 влит в `main` запросом corelib#28 2026-10-02 коммитом слияния `2a8f797aa8c`. Записка заведена после посадки, сжато: предмет каждой задачи — в её записке, а не здесь.

## Что и зачем

Движок OAuth2/OIDC в фундаменте — первая волна эпика corelib#26.

Родитель — [[KAC/issue-26-corelib|corelib#26]].

## Как влито

- запрос [corelib#46](https://github.com/PRO-Robotech/corelib/pull/46) → `26`: влит 2026-09-23, коммит слияния `8dff416ec55`;
- в `main` — посадкой эпика corelib#26 запросом corelib#28, коммит слияния `2a8f797aa8c`.

## Дочерние

Закрыты все 3 (2026-10-03, `gh api repos/PRO-Robotech/corelib/issues/27/sub_issues`):

corelib#20, corelib#48, corelib#52.

## Затронутые сущности vault

Узкие записки не правились: предмет — состояние трекера и веток.

## Связанные задачи

- зонтичный эпик: [[KAC/issue-2564|#2564]]
