---
title: "kacho#2564: эпик identity-own — снять стек Ory (Kratos/Hydra) из kacho, kaname и corelib"
aliases:
  - issue-2564
ticket_id: 2564
category: kac
status: done
type: epic
repos:
  - kacho
areas:
  - gateway
  - services/iam
  - ui-future
  - deploy
  - docs
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2824
issue_url: https://github.com/PRO-Robotech/kacho/issues/2564
opened: 2026-09-10
closed: 2026-10-03
tags:
  - kac
  - epic
verified_against: "PRO-Robotech/kacho: запрос kacho#2824 → `main` влит 2026-10-02 коммитом слияния e702195f599 (`gh pr view 2824`); трекер закрыт 2026-10-03, sub-issue закрыты 10 из 10 (`gh api .../sub_issues`); эпик kacho#2564 влит в main запросом #2824 коммитом e702195f599, предок origin/main (`git merge-base --is-ancestor`), 2026-10-03"
---

# kacho#2564: эпик identity-own — снять стек Ory (Kratos/Hydra) из kacho, kaname и corelib

**Состояние на 2026-10-03**: `done`, работа в `main`. Трекер закрыт 2026-10-03 (`completed`); эпик kacho#2564 влит в `main` запросом #2824 2026-10-02 коммитом слияния `e702195f599`. Записка заведена после посадки, сжато: предмет каждой задачи — в её записке, а не здесь.

## Что и зачем

Зонтичный эпик линии `release:identity-own`: внешний OAuth-сервер и чужая служба личности снимаются целиком, выдачу и церемонию входа ведёт движок на библиотеках Ory в corelib, которым пользуются служба доступа kaname и платформа. У каждого репозитория свой дочерний эпик со своей веткой и запросом в `main`; волны платформы — sub-issue этого эпика.

## Как влито

- запрос [kacho#2824](https://github.com/PRO-Robotech/kacho/pull/2824) → `main`: влит 2026-10-02, коммит слияния `e702195f599`;

## Дочерние

Закрыты все 10 (2026-10-03, `gh api repos/PRO-Robotech/kacho/issues/2564/sub_issues`):

[[KAC/issue-2794|#2794]], [[KAC/issue-2795|#2795]], [[KAC/issue-2796|#2796]], [[KAC/issue-2797|#2797]], [[KAC/issue-2798|#2798]], [[KAC/issue-771-ws|ws#771]], [[KAC/issue-26-corelib|corelib#26]], [[KAC/issue-357-kaname|kaname#357]], [[KAC/issue-2940|#2940]], [[KAC/issue-2983|#2983]].

Задачи PRO-Robotech/kaname#460, #467, #469 перенесены из поддерева в kaname#296 — эпик своей личности под kacho#1266, соседний и не дочерний.

## Затронутые сущности vault

Узкие записки не правились: предмет — состояние трекера и веток.

## Связанные задачи

- соседний эпик своего входа: kacho#1266 (не дочерний)
