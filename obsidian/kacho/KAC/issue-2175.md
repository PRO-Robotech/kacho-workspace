---
title: "#2175: Снимок скана сохраняется при отсутствии Trivy и отказе восстановления"
aliases:
  - issue-2175
ticket_id: 2175
category: kac
status: done
type: fix
repos:
  - kacho
prs: [2593]
issue_url: https://github.com/PRO-Robotech/kacho/issues/2175
opened: 2026-09-07
closed: 2026-09-17
tags:
  - kac
  - kacho-test
  - fix
  - done
verified_against: "kacho main b5fa093341f1fdbe96adfc6a9555482690968253, 2026-09-17"
---

# #2175: Снимок скана сохраняется при отсутствии Trivy и отказе восстановления

## Что и зачем

Предмет S1 подтверждён на текущем main настоящим Trivy 0.70.0 и отдельным исполнением ветки отсутствующей зависимости. До создания снимка проверяются предпосылки, отказ восстановления сохраняет пригодные данные.

## Сверка и доставка

21 RUN / 21 PASS, 7 верхних тестов, 0 FAIL / 0 SKIP. Исполнились все 11 обязательных вариантов. Отсутствие Trivy дало код 2 при сохранении байтов и git-состояния; законный близнец с подготовленным policy cache восстановил чистое и грязное состояния побайтово. Actions run 35185180836 независимо подтвердил ту же полосу.

Изменение доставлено коммитом [13bdec4175cac89bf02a200e5e9839ef57f3cb53](https://github.com/PRO-Robotech/kacho/commit/13bdec4175cac89bf02a200e5e9839ef57f3cb53). [Постоянное независимое свидетельство](https://github.com/PRO-Robotech/kacho/issues/2175#issuecomment-5713044928) содержит команды, счётчики и границу проверки. Issue CLOSED/COMPLETED с 2026-09-17T10:43:53Z; состояние повторно прочитано через GitHub API.

## Граница вывода

Это доказательство S1, без общего вердикта всей линии release:gates.

## Затронутые сущности vault

- [[lessons/absence-of-finding-versus-absence-of-inspection]] — явные исходы и объём исследования.
- [[lessons/checks-with-form-but-no-substance]] — предикат подтверждён исполнением и отрицательными контролями.

## DoD

- [x] Текущий predicate подтверждён независимым исполнением на main.
- [x] Постоянное свидетельство и предел вывода названы.
- [x] Состояние CLOSED повторно прочитано; исторические evidence не переписаны.

#kac #kacho-test #fix #done
