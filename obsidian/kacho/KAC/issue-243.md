---
title: "#243: имя ветки в кавычках судилось как путь в дереве"
aliases:
  - issue-243
ticket_id: 243
category: kac
status: done
type: bug
repos:
  - kacho-workspace
areas:
  - .claude/hooks
prs:
  - PRO-Robotech/kacho-workspace#295
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/243
opened: 2026-08-19
tags:
  - kac
---

# #243: имя ветки в кавычках судилось как путь в дереве

**Type**: bug

**Состояние**: done — в составе релизной линии gates (PR ws#295).

**PRs**: PRO-Robotech/kacho-workspace#295
**Issue**: https://github.com/PRO-Robotech/kacho-workspace/issues/243

## Что и зачем

У пути и у имени ветки одна форма, и проверка свежести не различала их: правило
подстраивалось под инструмент, а не наоборот.

Вид решается КОНТЕКСТОМ фразы — маркер вплотную слева, окно узкое. Сужение
обосновано замером: при широком применении правило снимало бы с проверки 50 из 64
координат, к git-ссылкам отношения не имеющих.

## DoD

- [x] имя ветки под маркером не находка
- [x] тот же токен без маркера судится как путь
- [x] составное определение маркером не является
- [x] снятое с проверки печатается в переписи
