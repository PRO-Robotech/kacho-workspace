---
title: "kacho#2798: волна-4 identity-own — чарты и зависимости Kratos/Hydra, документы"
aliases:
  - issue-2798
ticket_id: 2798
category: kac
status: done
type: epic
repos:
  - kacho
areas:
  - deploy
  - gateway
  - docs
  - tests
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2978
issue_url: https://github.com/PRO-Robotech/kacho/issues/2798
opened: 2026-09-22
closed: 2026-10-01
tags:
  - kac
  - epic
verified_against: "PRO-Robotech/kacho: запрос kacho#2978 → `2564` влит 2026-10-01 коммитом слияния e201adbf36f (`gh pr view 2978`); трекер закрыт 2026-10-01, sub-issue закрыты 19 из 19 (`gh api .../sub_issues`); эпик kacho#2564 влит в main запросом #2824 коммитом e702195f599, предок origin/main (`git merge-base --is-ancestor`), 2026-10-03"
---

# kacho#2798: волна-4 identity-own — чарты и зависимости Kratos/Hydra, документы

**Состояние на 2026-10-03**: `done`, работа в `main`. Трекер закрыт 2026-10-01 (`completed`); эпик kacho#2564 влит в `main` запросом #2824 2026-10-02 коммитом слияния `e702195f599`. Записка заведена после посадки, сжато: предмет каждой задачи — в её записке, а не здесь.

## Что и зачем

Снятие чартов и зависимостей Kratos/Hydra, имён поставщика в путях и документах; перенос коллекций службы доступа в наборы платформы. Волна шла двумя сборками (#2926, #2937).

Родитель — [[KAC/issue-2564|#2564]].

## Как влито

- запрос [kacho#2978](https://github.com/PRO-Robotech/kacho/pull/2978) → `2564`: влит 2026-10-01, коммит слияния `e201adbf36f`;
- в `main` — посадкой эпика kacho#2564 запросом #2824, коммит слияния `e702195f599`.

## Дочерние

Закрыты все 19 (2026-10-03, `gh api repos/PRO-Robotech/kacho/issues/2798/sub_issues`):

#2731, #2759, #2818, #2862, #2846, #2910, #2912, #2913, #2922, #2830, #2923, #2926, #2928, #2929, #2930, #2931, #2932, #2937, #2941.

## Затронутые сущности vault

Узкие записки не правились: предмет — состояние трекера и веток.

## Связанные задачи

- зонтичный эпик: [[KAC/issue-2564|#2564]]
