---
title: "#2218: Деривация корня listfiltergate принадлежит закреплённому corelib"
aliases:
  - issue-2218
ticket_id: 2218
category: kac
status: done
type: fix
repos:
  - kacho
prs: 
  - https://github.com/PRO-Robotech/kacho/pull/2598
issue_url: https://github.com/PRO-Robotech/kacho/issues/2218
opened: 2026-09-07
closed: 2026-09-17
tags:
  - kac
  - kacho-test
  - fix
  - done
verified_against: "kacho main b5fa093341f1fdbe96adfc6a9555482690968253; независимая проверка и CLOSED сверены 2026-09-17"
---

# #2218: Деривация корня listfiltergate принадлежит закреплённому corelib

## Что и зачем

Выбран предусмотренный задачей исход: прежняя дублирующая реализация линии платформы снята вместе с раскладкой. Compute/VPC/NLB/Geo импортируют corelib/listfiltergate из закреплённой версии v1.8.0 без replace при GOWORK=off. Преемник проверяет владельца module-декларации и отказывает, когда своего корня нет.

## Сверка и доставка

Исправление доставлено [PR #2598](https://github.com/PRO-Robotech/kacho/pull/2598), коммит [0cc1cd54c388](https://github.com/PRO-Robotech/kacho/commit/0cc1cd54c3885f307c729b5717e9ae9b7c3e797b).

6 верхних тестов; 12 RUN / 12 PASS с подпробами, FAIL/SKIP 0. Проверены обе раскладки, чужой вложенный go.mod с декоем, отсутствие своего корня и фактический import path потребителя.

[Постоянное свидетельство независимой проверки и точная команда](https://github.com/PRO-Robotech/kacho/issues/2218#issuecomment-5712868316) привязаны к указанному main. Код возврата, число верхних тестов и события подпроб разделены; ни пустой пакет, ни пропуск не засчитаны успехом.

Issue закрыта как COMPLETED 2026-09-17T10:29:33Z; состояние повторно прочитано через GitHub API. Эта записка фиксирует текущий результат закрытия, а не новое выполнение исторической реализации.

## Граница вывода

Записка [[KAC/issue-2211]] сохраняет историю накопительной линии. Здесь зафиксирована новая сверка main и действующего преемника; остальные вопросы listfiltergate этим закрытием не решаются.

## Затронутые сущности vault

- [[lessons/absence-of-finding-versus-absence-of-inspection]] — исполненная непустая проверка отделена от отсутствующего предмета.
- [[lessons/checks-with-form-but-no-substance]] — утверждение о защите имеет действующего производителя.

## DoD

- [x] Текущий predicate сверён на указанном main и подтверждён независимым проверяющим.
- [x] Доставка либо исправленная координата названа постоянной ссылкой.
- [x] CLOSED/COMPLETED повторно прочитано; исторические свидетельства сохранены.

#kac #kacho-test #fix #done
