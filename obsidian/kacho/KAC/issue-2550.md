---
title: "#2550: Гейт Make проверяет команды канонической обёртки"
aliases:
  - issue-2550
ticket_id: 2550
category: kac
status: done
type: fix
repos:
  - kacho
prs: [2593]
issue_url: https://github.com/PRO-Robotech/kacho/issues/2550
opened: 2026-09-10
closed: 2026-09-17
tags:
  - kac
  - kacho-test
  - fix
  - done
verified_against: "main b5fa093341f1fdbe96adfc6a9555482690968253, 2026-09-17"
---

# #2550: Гейт Make проверяет команды канонической обёртки

## Что и зачем

Предмет S3 подтверждён на main: stand-up.sh разрешается по пути и рабочему
каталогу, дочерние Make-команды проверяются тем же предикатом. Чужой одноимённый
файл и упоминание не считаются вызовом; неподдерживаемая форма получает
координату отказа.

## Сверка и доставка

Независимая команда с GOWORK=off и TMPDIR вне git:
`go test ./services/storage/tools -run '^Test(EveryCIMakeCommandResolves|RG11_1[1-8]|RG11Make.*)$' -count=1 -json -timeout=10m`.
Результат: **61 RUN / 61 PASS**, 10 верхних тестов, 0 FAIL / 0 SKIP.
Все 20 обязательных S3-вариантов исполнены. Текущий main даёт 34 Make-записи,
из них 4 под обёрткой. Независимый go-style-reviewer прочитал оба файла целиком
и дал APPROVED на точные байты main после устранения прежних замечаний.

Предмет доставлен [PR #2593](https://github.com/PRO-Robotech/kacho/pull/2593),
коммит `13bdec4175cac89bf02a200e5e9839ef57f3cb53`.
[Постоянное независимое свидетельство](https://github.com/PRO-Robotech/kacho/issues/2550#issuecomment-5713047799)
содержит команды, счётчики и границу проверки. CLOSED/COMPLETED с
2026-09-17T10:44:06Z; состояние повторно прочитано через GitHub API.

## Граница вывода

Исторический corpus 37 = 33 + 4 и текущие 34 относятся к разным ревизиям.
Нынешний post-diff review не объявляется прежним convergence.

## Затронутые сущности vault

- [[lessons/absence-of-finding-versus-absence-of-inspection]] — явный объём проверки.
- [[lessons/checks-with-form-but-no-substance]] — исполняемый предмет и отрицательные контроли.

## DoD

- [x] Все обязательные варианты исполнены на main.
- [x] Повторный независимый Go-review выполнен на точных байтах.
- [x] CLOSED повторно прочитано; исторические свидетельства не переписаны.

#kac #kacho-test #fix #done
