---
title: "#1660: Ожидание дренажа снято вместе с прежним механизмом журнала"
aliases:
  - issue-1660
ticket_id: 1660
category: kac
status: done
type: fix
repos:
  - kacho
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2064
issue_url: https://github.com/PRO-Robotech/kacho/issues/1660
opened: 2026-08-30
closed: 2026-09-17
tags:
  - kac
  - kacho-test
  - fix
  - done
verified_against: "kacho main b5fa093341f1fdbe96adfc6a9555482690968253; независимая проверка 2026-09-17"
---

# #1660: Ожидание дренажа снято вместе с прежним механизмом журнала

## Что и зачем

Прежний drain_fga_outbox.sh удалён. На main Kachō и Kaname, а также фактическом пине Kaname исполняемых и иных tracked ссылок на него нет. Действующий журнал применяет прямой факт в той же транзакции; ожидание снятых маркеров доставки не описывает этот механизм.

## Сверка и доставка

[PR #2064](https://github.com/PRO-Robotech/kacho/pull/2064), коммит [2171a6690a81](https://github.com/PRO-Robotech/kacho/commit/2171a6690a81c197caa2663eb92ea447e2f21613).

Схема baseline SQL у фактического пина Kaname 94352d9c4a88 и main39628487099f совпадает побайтово. Независимый преемник контроля TestJournalWithoutDeliveryMarker / TestMarkerQuery / TestJournalDictionary исполнил 8/8 проб PASS, FAIL/SKIP0; различены запрос отсутствующих маркеров, комментарий и законная очередь с такими столбцами.

[Постоянное свидетельство независимой проверки](https://github.com/PRO-Robotech/kacho/issues/1660#issuecomment-5712956306) содержит точные команды/координаты и границы результата. Issue закрыта как COMPLETED 2026-09-17T10:36:50Z; состояние повторно прочитано через GitHub API.

## Граница вывода

Закрытие по опровержению исходной посылки. Старый скрипт не восстанавливался ради прежнего счётчика глубины. Проверены поставленные исходники и регрессии; состояние развёрнутой БД не заявляется.

## Затронутые сущности vault

- [[lessons/absence-of-finding-versus-absence-of-inspection]] — измеренный объём и область вердикта.
- [[lessons/checks-with-form-but-no-substance]] — действующий производитель подтверждён исполняемой проверкой.

## DoD

- [x] Текущий predicate подтверждён независимой проверкой с ненулевым объёмом.
- [x] Постоянное свидетельство и граница результата названы.
- [x] CLOSED/COMPLETED повторно прочитано; исторические свидетельства не переписаны.

#kac #kacho-test #fix #done
