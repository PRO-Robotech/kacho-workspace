---
title: "#259: брошенные рабочие копии держали влитые ветки"
aliases:
  - issue-259
ticket_id: 259
category: kac
status: done
type: bug
repos:
  - kacho-workspace
areas:
  - scripts
prs:
  - PRO-Robotech/kacho-workspace#295
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/259
opened: 2026-08-19
tags:
  - kac
---

# #259: брошенные рабочие копии держали влитые ветки

**Type**: bug

**Состояние**: done — в составе релизной линии gates (PR ws#295).

**PRs**: PRO-Robotech/kacho-workspace#295
**Issue**: https://github.com/PRO-Robotech/kacho-workspace/issues/259

## Что и зачем

Копия агента переживает самого агента: 26 копий возрастом 16–56 часов. Перепись
видела в них одно «занято», поэтому влитые ветки не снимались никогда.

Живость решается двумя признаками сразу — держит ли копию чей-то рабочий каталог
(из /proc) и трогали ли содержимое за последние часы. Снятие остаётся за человеком:
удалить чужое состояние необратимо.

## Затронутые сущности vault

[[lessons/probe-that-pins-someone-elses-tree-state]]

## DoD

- [x] живая копия отличается от брошенной двумя признаками
- [x] брошенная названа вместе с готовой командой снятия
- [x] перепись ничего не снимает сама
- [x] два утверждения инъекции, 29 из 29
