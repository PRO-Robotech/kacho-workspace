---
title: "#293: у проверки состава приёмок не было ни одной пробы"
aliases:
  - issue-293
ticket_id: 293
category: kac
status: done
type: bug
repos:
  - kacho-workspace
areas:
  - scripts
prs:
  - PRO-Robotech/kacho-workspace#295
issue_url: https://github.com/PRO-Robotech/kacho-workspace/issues/293
opened: 2026-08-19
tags:
  - kac
---

# #293: у проверки состава приёмок не было ни одной пробы

**Type**: bug

**Состояние**: done — в составе релизной линии gates (PR ws#295).

**PRs**: PRO-Robotech/kacho-workspace#295
**Issue**: https://github.com/PRO-Robotech/kacho-workspace/issues/293

## Что и зачем

Вердикт проверки читал прогонщик набора, а способность упасть не подтверждалась
ничем. Шесть входов в пустом каталоге приёмок: на живых 154 документах вход не
детерминирован, и проба судила бы дерево, а не проверку.

## DoD

- [x] строка состава без сценария краснеет с координатой
- [x] со сценарием и с передачей в дочернюю — молчит
- [x] передача в несуществующий документ краснеет
- [x] обе предпосылки дают «не выполнилось», а не успех
