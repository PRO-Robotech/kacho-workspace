---
title: "#602: Все объявленные команды lint консоли исполняются"
aliases:
  - issue-602
ticket_id: 602
category: kac
status: done
type: fix
repos:
  - kacho
prs:
  - https://github.com/PRO-Robotech/kacho/pull/1732
issue_url: https://github.com/PRO-Robotech/kacho/issues/602
opened: 2026-08-17
closed: 2026-09-17
tags:
  - kac
  - kacho-test
  - fix
  - done
verified_against: "kacho main b5fa093341f1fdbe96adfc6a9555482690968253; независимая проверка 2026-09-17"
---

# #602: Все объявленные команды lint консоли исполняются

## Что и зачем

Доставка сохранила --allow-empty-input для CSS-проверок и общий запуск всех объявленных lint из корня UI и workflow. Исполнимость проверена чистой установкой по всем действующим lock-файлам, без изменения source.

## Сверка и доставка

[PR #1732](https://github.com/PRO-Robotech/kacho/pull/1732), коммит [74eb331234d3](https://github.com/PRO-Robotech/kacho/commit/74eb331234d31aa29a147bea9544d50fff3f2046).

После npm ci для workspace и семи standalone-пакетов корневой npm run lint завершился RC0 на Node 26.8.1 / npm 11.19.0. Сопоставление журнала с объявлениями подтвердило 10/10 пакетных lint и все 9 lint:css. Независимый Go-гейт исполнил 9/9 проб, FAIL/SKIP0; перепись: 11 пакетов прочитано, 10 объявляют lint и все 10 вызваны.

[Постоянное свидетельство независимой проверки](https://github.com/PRO-Robotech/kacho/issues/602#issuecomment-5712915844) содержит точные команды/координаты и границы результата. Issue закрыта как COMPLETED 2026-09-17T10:33:29Z; состояние повторно прочитано через GitHub API.

## Граница вывода

Это подтверждение объявленного lint и его производителя. Сквозные UI-сценарии этим результатом не подменяются; прежний PR #1710 относится к соседним format/type проверкам.

## Затронутые сущности vault

- [[lessons/absence-of-finding-versus-absence-of-inspection]] — измеренный объём и область вердикта.
- [[lessons/checks-with-form-but-no-substance]] — действующий производитель подтверждён исполняемой проверкой.

## DoD

- [x] Текущий predicate подтверждён независимой проверкой с ненулевым объёмом.
- [x] Постоянное свидетельство и граница результата названы.
- [x] CLOSED/COMPLETED повторно прочитано; исторические свидетельства не переписаны.

#kac #kacho-test #fix #done
