---
title: "Волна identity-own w0 (kacho): консоль долита схлопыванием, голова 9fcf1e81e9a"
aliases:
  - волна identity-own w0
  - wave/identity-own-w0-kacho
category: kac
ticket_id: ""
status: test
type: refactor
repos:
  - kacho
prs: []
opened: 2026-09-22
closed: ""
tags:
  - kac
  - kacho
  - kacho-deploy
  - kacho-ui
---

# Волна identity-own w0 (kacho): состояние на 2026-09-22

**Состояние**: `test` — работа собрана в ветке волны, запроса на слияние **нет**, в ствол не
влито. Волна — единица запроса на слияние: полосы сводятся в одну ветку, проверки гонятся на
сведённом, и в `main` уходит один запрос на всю волну.

| ось | значение | чем снято |
|---|---|---|
| голова волны (координата, не живая ссылка) | `9fcf1e81e9adb260de08dbadf4a7f872bb47cf5d` | `git rev-parse wave/identity-own-w0-kacho` |
| на origin | **нет** — ветка существует только в рабочей копии | `git ls-remote origin 'refs/heads/wave/identity-own-w0-kacho'` → пусто |
| ствол продукта | `bec320cf47d668173bf27f60ebaf6cbe413a4903` | `git ls-remote origin refs/heads/main` |
| запрос на слияние | **нет** | — |

## Смена состояния, которую записка фиксирует

Долита полоса консоли (`fix/console-serves-identity-flows` — координата, не живая ссылка),
и долита **схлопыванием**: её голова `89fd35c60cd` ствола волны **не предок**
(`git merge-base --is-ancestor 89fd35c60cd wave/identity-own-w0-kacho` → ненулевой код), а
верхний коммит волны несёт её предмет одним изменением. Схлопывание здесь и есть штатная форма
посадки полосы в волну; исходная ветка на origin осталась.

> [!warning] Голова волны не на origin — второго экземпляра нет
> Сведённое состояние существует **в одном месте**. Это ровно тот случай, ради которого
> [[KAC/issue-752-ws]] и [[KAC/issue-761-ws]] заведены: прибор, отвечающий «уникальна», обязан
> печатать, что он осмотрел.

## Что на этой голове измерено, а что нет

Перемерено мной 2026-09-22 на самой голове: полоса `deploy/helm/umbrella/values.own.yaml`
**не опустела** — три её объявления там на месте, и гейта `login_lane_prereq_test.go` в
`gateway/deploy` **нет**. То есть работа по [[KAC/issue-2777]] и предпосылки посадки живут на
**других** ветках и в эту волну ещё не сведены; их координаты названы в
[[packages/kacho-deploy-helm-umbrella]] и [[packages/kacho-gateway-deploy]].

## Затронутые сущности vault

- [[packages/kacho-deploy-helm-umbrella]] — зонт и его семь цепочек: где какая посадка объявлена.
- [[packages/kacho-gateway-deploy]] — гейты края о стендах, в том числе предпосылка полосы формы.
- [[KAC/issue-2777]] · [[KAC/issue-2780]] · [[KAC/issue-2781]] — задачи линии `release:identity-own`.

#kac #kacho #kacho-deploy #kacho-ui
