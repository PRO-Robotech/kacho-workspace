---
title: "Волна identity-own w0 (kacho): консоль долита схлопыванием, голова 9fcf1e81e9a"
aliases:
  - волна identity-own w0
  - wave/identity-own-w0-kacho
category: kac
ticket_id: ""
status: done
type: refactor
repos:
  - kacho
prs:
  - https://github.com/PRO-Robotech/kacho/pull/2787
opened: 2026-09-22
closed: 2026-09-22
tags:
  - kac
  - kacho
  - kacho-deploy
  - kacho-ui
verified_against: "PRO-Robotech/kacho, 2026-09-26: PR #2787 wave/identity-own-w0-kacho → main влит 2026-09-22T14:43:12Z коммитом b32ca653083 с одним родителем bec320cf47d, голова запроса bdac9a1f8d1 (`gh pr view 2787`, `git log -1 --format=%P`); b32ca653083 — предок origin/main, 9fcf1e81e9a — не предок b32ca653083 (`git merge-base --is-ancestor`); трекер волны kacho#2794 закрыт 2026-09-22T16:02:52Z (`gh issue view 2794`). Замеры ниже по разделам сделаны на 9fcf1e81e9a и на итоговой голове не перемерялись"
---

# Волна identity-own w0 (kacho): состояние на 2026-09-22

> [!important] Состояние сменилось 2026-09-22 — волна в стволе
> Запрос волны PRO-Robotech/kacho#2787 влит в `main` 2026-09-22T14:43:12Z коммитом `b32ca653083`
> с одним родителем `bec320cf47d`, то есть схлопыванием, а не коммитом слияния. Итоговая
> голова запроса — `bdac9a1f8d1`, а не голова `9fcf1e81e9a` из таблицы ниже; трекер волны
> PRO-Robotech/kacho#2794 закрыт тем же днём. Таблица и разделы ниже — снимок на
> `9fcf1e81e9a`, верный как прошлое; на итоговой голове они не перемерялись. Записи ревью этой
> волны — [[KAC/issue-779-ws]], [[KAC/issue-783-ws]], [[KAC/issue-775-ws]]; запись схождения —
> [[KAC/issue-767-ws]].

**Состояние на момент снимка**: `test` — работа собрана в ветке волны, запроса на слияние **нет**,
в ствол не влито. Волна — единица запроса на слияние: полосы сводятся в одну ветку, проверки гонятся на
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
