---
title: "kaname#548: волна-8 kaname — ID аккаунта можно указать при создании"
aliases:
  - issue-548-kaname
ticket_id: 548
category: kac
status: done
type: epic
repos:
  - kaname
areas:
  - internal
  - proto
prs:
  - https://github.com/PRO-Robotech/kaname/pull/551
issue_url: https://github.com/PRO-Robotech/kaname/issues/548
opened: 2026-10-01
closed: 2026-10-02
tags:
  - kac
  - epic
verified_against: "PRO-Robotech/kaname: запрос kaname#551 → `357` влит 2026-10-02 коммитом слияния 1b9067128e7 (`gh pr view 551`); трекер закрыт 2026-10-02, sub-issue закрыты 1 из 1 (`gh api .../sub_issues`); эпик kaname#357 влит в main запросом kaname#359 коммитом 8cbc0fdc82c, предок origin/main (`git merge-base --is-ancestor`), 2026-10-03"
---

# kaname#548: волна-8 kaname — ID аккаунта можно указать при создании

**Состояние на 2026-10-03**: `done`, работа в `main`. Трекер закрыт 2026-10-02 (`completed`); эпик kaname#357 влит в `main` запросом kaname#359 2026-10-02 коммитом слияния `8cbc0fdc82c`. Записка заведена после посадки, сжато: предмет каждой задачи — в её записке, а не здесь.

## Что и зачем

Служба доступа принимает `id` аккаунта при создании (задача kaname#549); сторона платформы — волна-6 kacho#2983.

Родитель — [[KAC/issue-357-kaname|kaname#357]].

## Как влито

- запрос [kaname#551](https://github.com/PRO-Robotech/kaname/pull/551) → `357`: влит 2026-10-02, коммит слияния `1b9067128e7`;
- в `main` — посадкой эпика kaname#357 запросом kaname#359, коммит слияния `8cbc0fdc82c`.

## Дочерние

Закрыты все 1 (2026-10-03, `gh api repos/PRO-Robotech/kaname/issues/548/sub_issues`):

kaname#549.

## Затронутые сущности vault

Узкие записки не правились: предмет — состояние трекера и веток.

## Связанные задачи

- зонтичный эпик: [[KAC/issue-2564|#2564]]
