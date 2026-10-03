---
title: "kacho#2795: волна-1 identity-own — край без own,external, стенд без Kratos/Hydra"
aliases:
  - issue-2795
ticket_id: 2795
category: kac
status: done
type: epic
repos:
  - kacho
areas:
  - gateway
  - deploy
  - .github/workflows
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2834
issue_url: https://github.com/PRO-Robotech/kacho/issues/2795
opened: 2026-09-22
closed: 2026-09-23
tags:
  - kac
  - epic
verified_against: "PRO-Robotech/kacho: запрос kacho#2834 → `2564` влит 2026-09-23 коммитом слияния 5a3766e1cb4 (`gh pr view 2834`); трекер закрыт 2026-09-23, sub-issue закрыты 28 из 28 (`gh api .../sub_issues`); эпик kacho#2564 влит в main запросом #2824 коммитом e702195f599, предок origin/main (`git merge-base --is-ancestor`), 2026-10-03"
---

# kacho#2795: волна-1 identity-own — край без own,external, стенд без Kratos/Hydra

**Состояние на 2026-10-03**: `done`, работа в `main`. Трекер закрыт 2026-09-23 (`completed`); эпик kacho#2564 влит в `main` запросом #2824 2026-10-02 коммитом слияния `e702195f599`. Записка заведена после посадки, сжато: предмет каждой задачи — в её записке, а не здесь.

## Что и зачем

Край перестаёт держать переходное состояние носителей `own,external`; стенд посадки `own` поднимается без Kratos/Hydra, посевы идут через наш API.

Родитель — [[KAC/issue-2564|#2564]].

## Как влито

- запрос [kacho#2834](https://github.com/PRO-Robotech/kacho/pull/2834) → `2564`: влит 2026-09-23, коммит слияния `5a3766e1cb4`;
- в `main` — посадкой эпика kacho#2564 запросом #2824, коммит слияния `e702195f599`.

## Дочерние

Закрыты все 28 (2026-10-03, `gh api repos/PRO-Robotech/kacho/issues/2795/sub_issues`):

#2732, #2802, #2803, #2805, #2809, #2810, #2685, #2730, #2761, #2725, #2726, #2727, [[KAC/issue-2781|#2781]], #2744, #2800, #2815, #2816, #2765, #2766, #2767, #2724, #2709, #2714, #2819, #2821, #2822, #2823, #2838.

## Затронутые сущности vault

Узкие записки не правились: предмет — состояние трекера и веток.

## Связанные задачи

- зонтичный эпик: [[KAC/issue-2564|#2564]]
