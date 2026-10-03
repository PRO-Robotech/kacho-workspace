---
title: "corelib#26: эпик identity-own corelib — движок OAuth2/OIDC на библиотеках Ory"
aliases:
  - issue-26-corelib
ticket_id: 26
category: kac
status: done
type: epic
repos:
  - corelib
areas:
  - oauthceremony
  - oauth2
  - identityposture
prs:
  - https://github.com/PRO-Robotech/corelib/pull/28
issue_url: https://github.com/PRO-Robotech/corelib/issues/26
opened: 2026-09-22
closed: 2026-10-02
tags:
  - kac
  - epic
  - kacho-corelib
verified_against: "PRO-Robotech/corelib: запрос corelib#28 → `main` влит 2026-10-02 коммитом слияния 2a8f797aa8c (`gh pr view 28`); трекер закрыт 2026-10-02, sub-issue закрыты 5 из 5 (`gh api .../sub_issues`); эпик corelib#26 влит в main запросом corelib#28 коммитом 2a8f797aa8c, предок origin/main (`git merge-base --is-ancestor`), 2026-10-03"
---

# corelib#26: эпик identity-own corelib — движок OAuth2/OIDC на библиотеках Ory

**Состояние на 2026-10-03**: `done`, работа в `main`. Трекер закрыт 2026-10-02 (`completed`); эпик corelib#26 влит в `main` запросом corelib#28 2026-10-02 коммитом слияния `2a8f797aa8c`. Записка заведена после посадки, сжато: предмет каждой задачи — в её записке, а не здесь.

## Что и зачем

Дочерний эпик фундамента под kacho#2564: движок OAuth2/OIDC на библиотеках Ory в corelib, порты движка под службу доступа, словарь посадки без `external`. Ветка эпика `26`, запрос в `main` — corelib#28.

Родитель — [[KAC/issue-2564|#2564]].

## Как влито

- запрос [corelib#28](https://github.com/PRO-Robotech/corelib/pull/28) → `main`: влит 2026-10-02, коммит слияния `2a8f797aa8c`;

## Дочерние

Закрыты все 5 (2026-10-03, `gh api repos/PRO-Robotech/corelib/issues/26/sub_issues`):

[[KAC/issue-27-corelib|corelib#27]], [[KAC/issue-29-corelib|corelib#29]], [[KAC/issue-32-corelib|corelib#32]], [[KAC/issue-74-corelib|corelib#74]], corelib#73.

## Затронутые сущности vault

Узкие записки не правились: предмет — состояние трекера и веток.

## Связанные задачи

- зонтичный эпик: [[KAC/issue-2564|#2564]]
