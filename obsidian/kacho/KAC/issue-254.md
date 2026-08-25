---
title: "#254: правило называло enforce_admins false, в обоих репозиториях true"
aliases:
  - issue-254
ticket_id: 254
category: kac
status: done
type: bug
repos:
  - kacho-workspace
areas:
  - .claude/rules
prs:
  - PRO-Robotech/kacho-workspace#295
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/254
opened: 2026-08-19
tags:
  - kac
---

# #254: правило называло enforce_admins false, в обоих репозиториях true

**Type**: bug

**Состояние**: done — в составе релизной линии gates (PR ws#295).

**PRs**: PRO-Robotech/kacho-workspace#295
**Issue**: https://github.com/PRO-Robotech/kacho-workspace/issues/254

## Что и зачем

Утверждение о настройке было записано по намерению и ни разу не сверено. Читатель,
упёршись в отказ сервера, искал причину не там: он ждал, что для него запрет не
действует.

Закрыто коммитом `623b04f` (PR ws#266): записка называет предикат, которым это
проверяется. Норма от этого строже — прямой push в `main` отвергается для всех.

## DoD

- [x] факт перемерен предикатом в обоих репозиториях
- [x] предикат назван в тексте правила
