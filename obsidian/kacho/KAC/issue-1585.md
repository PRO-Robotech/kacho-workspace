---
title: "#1585: Шапка foreignclouds называет фактический предмет и источник счёта"
aliases:
  - issue-1585
ticket_id: 1585
category: kac
status: done
type: fix
repos:
  - kacho
prs: 
  - https://github.com/PRO-Robotech/kacho/pull/2593
issue_url: https://github.com/PRO-Robotech/kacho/issues/1585
opened: 2026-08-30
closed: 2026-09-17
tags:
  - kac
  - kacho-test
  - fix
  - done
verified_against: "kacho main b5fa093341f1fdbe96adfc6a9555482690968253; независимая проверка и CLOSED сверены 2026-09-17"
---

# #1585: Шапка foreignclouds называет фактический предмет и источник счёта

## Что и зачем

Шапка foreignclouds ссылается на ScanDebt как источник числа вхождений и файлов и отделяет эти числа от длины ledger. Описание compute guard ограничено Go-комментариями internal/cmd; SQL и Newman в этот предикат не входят.

## Сверка и доставка

Исправление доставлено [PR #2593](https://github.com/PRO-Robotech/kacho/pull/2593), коммит [13bdec4175ca](https://github.com/PRO-Robotech/kacho/commit/13bdec4175cac89bf02a200e5e9839ef57f3cb53).

16 верхних тестов; 24 RUN / 24 PASS с подпробами, FAIL/SKIP 0. Самостоятельный verify-no-foreign-clouds на main завершился RC0 и сообщил объявленный долг: 22 вхождения / 9 файлов. Долг не назван отсутствием находок.

[Постоянное свидетельство независимой проверки и точная команда](https://github.com/PRO-Robotech/kacho/issues/1585#issuecomment-5712870103) привязаны к указанному main. Код возврата, число верхних тестов и события подпроб разделены; ни пустой пакет, ни пропуск не засчитаны успехом.

Issue закрыта как COMPLETED 2026-09-17T10:29:41Z; состояние повторно прочитано через GitHub API. Эта записка фиксирует текущий результат закрытия, а не новое выполнение исторической реализации.

## Граница вывода

Исправлен текст о действующем механизме. Расширение обхода и снятие объявленного долга не входят в predicate #1585. Сохранность нужной шапки независимо сверена между коммитом доставки и main.

## Затронутые сущности vault

- [[lessons/absence-of-finding-versus-absence-of-inspection]] — исполненная непустая проверка отделена от отсутствующего предмета.
- [[lessons/checks-with-form-but-no-substance]] — утверждение о защите имеет действующего производителя.

## DoD

- [x] Текущий predicate сверён на указанном main и подтверждён независимым проверяющим.
- [x] Доставка либо исправленная координата названа постоянной ссылкой.
- [x] CLOSED/COMPLETED повторно прочитано; исторические свидетельства сохранены.

#kac #kacho-test #fix #done
