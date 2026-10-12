---
title: "kacho#2983: волна-6 identity-own — ID аккаунта при создании: пин службы и край"
aliases:
  - issue-2983
ticket_id: 2983
category: kac
status: done
type: epic
repos:
  - kacho
areas:
  - gateway
  - deploy
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2990
issue_url: https://github.com/PRO-Robotech/kacho/issues/2983
opened: 2026-10-01
closed: 2026-10-02
tags:
  - kac
  - epic
verified_against: "PRO-Robotech/kacho: запрос kacho#2990 → `2564` влит 2026-10-02 коммитом слияния f164c276bbc (`gh pr view 2990`); трекер закрыт 2026-10-02, sub-issue закрыты 1 из 1 (`gh api .../sub_issues`); эпик kacho#2564 влит в main запросом #2824 коммитом e702195f599, предок origin/main (`git merge-base --is-ancestor`), 2026-10-03"
---

# kacho#2983: волна-6 identity-own — ID аккаунта при создании: пин службы и край

**Состояние на 2026-10-03**: `done`, работа в `main`. Трекер закрыт 2026-10-02 (`completed`); эпик kacho#2564 влит в `main` запросом #2824 2026-10-02 коммитом слияния `e702195f599`. Записка заведена после посадки, сжато: предмет каждой задачи — в её записке, а не здесь.

## Что и зачем

Сторона платформы для поля `id` в создании аккаунта: пин службы доступа и проба края. Служба — волна-8 kaname#548. Шла параллельно эпику по решению владельца и села в `main` вместе с ним.

Родитель — [[KAC/issue-2564|#2564]].

## Как влито

- запрос [kacho#2990](https://github.com/PRO-Robotech/kacho/pull/2990) → `2564`: влит 2026-10-02, коммит слияния `f164c276bbc`;
- в `main` — посадкой эпика kacho#2564 запросом #2824, коммит слияния `e702195f599`.

## Дочерние

Закрыты все 1 (2026-10-03, `gh api repos/PRO-Robotech/kacho/issues/2983/sub_issues`):

#2984.

## Затронутые сущности vault

Узкие записки не правились: предмет — состояние трекера и веток.

## Связанные задачи

- зонтичный эпик: [[KAC/issue-2564|#2564]]
